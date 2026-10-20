# GitHub as code: the organization, its verified domains and every repo's
# visibility, environments, Actions secrets and variables. Secret values are
# never here: each names a variable of the secretspec profile `proton-agents`,
# and `github-bootstrap` pipes it from Proton Pass into GitHub.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.github;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  Secret = types.enum (
    lib.attrNames (removeAttrs config.proton.secretspec.profiles.proton-agents [ "defaults" ])
  );

  repo = types.submodule {
    options = {
      from = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The owner the repo is transferred from, if it lives elsewhere first.";
      };
      visibility = mkOption { type = types.enum (cli.ghChoices "repo edit" "visibility"); };
      secrets = mkOption {
        type = types.attrsOf Secret;
        default = { };
        description = "Repository Actions secrets: name -> proton-agents variable.";
      };
      variables = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      environments = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              branches = mkOption {
                type = types.nonEmptyListOf types.str;
                description = "The only branches that may deploy to it.";
              };
              secrets = mkOption {
                type = types.attrsOf Secret;
                default = { };
              };
            };
          }
        );
        default = { };
      };
    };
  };
in
{
  options.github = {
    account = mkOption {
      type = types.enum (lib.attrNames config.accounts.held);
      description = "The held account the organization is.";
    };
    org = mkOption { type = types.strMatching "[A-Za-z0-9][A-Za-z0-9-]*"; };
    verifiedDomains = mkOption {
      type = types.attrsOf (types.nullOr (types.strMatching "[a-z0-9]+"));
      default = { };
      description = ''
        Declared domains the organization verifies: domain -> the TXT token
        GitHub issued for it (null until `github-bootstrap` prints it). A
        token becomes the _gh-<org>-o record on the domain's zone.
      '';
    };
    repos = mkOption {
      type = types.attrsOf repo;
      default = { };
    };
  };

  config.identity.domains = lib.mapAttrs (domain: token: {
    records.github-verification = {
      name = "_gh-${cfg.org}-o.${domain}";
      type = "TXT";
      content = token;
    };
  }) (lib.filterAttrs (_: t: t != null) cfg.verifiedDomains);

  config.accounts.demands =
    lib.optional (cfg.verifiedDomains != { }) {
      inherit (cfg) account;
      capability = "verifiedDomains";
      need = true;
      why = "github.verifiedDomains (${lib.concatStringsSep ", " (lib.attrNames cfg.verifiedDomains)})";
    }
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: r:
        lib.optional (r.environments != { } && r.visibility != "public") {
          inherit (cfg) account;
          capability = "environmentsPrivate";
          need = true;
          why = "github.repos.${name}: environments on a ${r.visibility} repo";
        }
      ) cfg.repos
    );
}
