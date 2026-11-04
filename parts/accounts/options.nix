# Accounts and their plans, typed. Nothing the repo relies on about an
# account (how many custom domains it may have, whether it has Bridge, whether
# Pass access tokens exist on it) is assumed: each is a capability of the plan
# the account is declared on, with the page that states it and when it was
# read.
#
#   accounts.plans.<provider>.<plan>  what a plan includes (plans.nix)
#   accounts.held.<name>              the accounts that exist or are planned
#                                     (held.nix), each on one declared plan
#   accounts.checked                  the held accounts with their plans'
#                                     capabilities, after every demand the rest
#                                     of the repo makes is checked against them
#
# Each provider has its own closed capability set, so a plan can neither omit
# one nor invent one; a limit is a count or "unlimited".
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.accounts;

  # A capability: its value and the evidence for it.
  cap =
    valueType:
    types.submodule {
      options = {
        value = mkOption { type = valueType; };
        source = mkOption {
          type = types.strMatching "https://.+";
          description = "The page that states it.";
        };
      };
    };
  Limit = cap (types.either types.ints.unsigned (types.enum [ "unlimited" ]));
  Flag = cap types.bool;

  capabilities = {
    proton = {
      customDomains = Limit;
      addresses = Limit;
      bridge = Flag;
      passAccessTokens = Flag;
    };
    cloudflare = {
      registrarAtCost = Flag;
      accountTokens = Flag;
      emailRoutingRules = Limit;
      emailRoutingAddresses = Limit;
      workersRequestsPerDay = Limit;
      kvWritesPerDay = Limit;
    };
    github = {
      privateRepos = Limit;
      actionsMinutesPrivate = Limit;
      verifiedDomains = Flag;
      protectedBranchesPrivate = Flag;
      environmentsPrivate = Flag;
    };
  };
  providers = lib.attrNames capabilities;

  plan =
    provider:
    types.submodule {
      options = {
        checked = mkOption {
          type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
          description = "When the sources were last read.";
        };
        capabilities = lib.mapAttrs (_: t: mkOption { type = t; }) capabilities.${provider};
      };
    };

  held = types.submodule (
    { config, ... }:
    {
      options = {
        provider = mkOption { type = types.enum providers; };
        plan = mkOption {
          type = types.enum (lib.attrNames cfg.plans.${config.provider});
          description = "One of the provider's declared plans.";
        };
        owner = mkOption {
          type = types.enum (lib.attrNames config'.identity.entities);
          description = "The entity the account belongs to.";
        };
        status = mkOption {
          type = types.enum [
            "active"
            "planned"
          ];
        };
        signup = mkOption {
          type = types.nullOr signup;
          default = null;
          description = "How the account is created, for `signup`.";
        };
      };
    }
  );

  # A web signup, prepared by `signup prepare` and done once by hand: the one
  # step most providers offer no API for.
  signup = types.submodule {
    options = {
      url = mkOption {
        type = types.strMatching "https://.+";
        description = "The page the signup starts on.";
      };
      handle = mkOption {
        type = types.strMatching "[A-Za-z0-9][A-Za-z0-9-]*";
        description = "The account or organization name to claim.";
      };
      email = mkOption {
        type = types.enum addresses;
        description = "A declared mailbox (identity.domains.*.mailboxes).";
      };
      credential = mkOption {
        type = types.enum [
          "password"
          "parent"
        ];
        description = ''
          password: a login of its own, with a generated password and its 2FA
          seed in the vault item. parent: created from another account's
          session (a GitHub organization under its owner's user account).
        '';
      };
      parent = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "For credential = parent: the account it is created from, by its login.";
      };
      findings = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              fact = mkOption { type = types.str; };
              source = mkOption { type = types.str; };
              checked = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
            };
          }
        );
        default = [ ];
        description = "What was learned about the provider before signing up, with where from.";
      };
    };
  };
  addresses = lib.concatLists (
    lib.mapAttrsToList (
      domain: d: map (m: "${m}@${domain}") d.mailboxes
    ) config.identity.checked.domains
  );
  config' = config;

  # Every demand the repo makes of an account: { account; capability; need; why; }.
  # `need` is a count (the limit must cover it) or true (the flag must be set).
  covers =
    limit: need:
    if builtins.isBool need then limit == true || !need else limit == "unlimited" || need <= limit;
  signupProblems = lib.concatLists (
    lib.mapAttrsToList (
      name: a:
      lib.optionals (a.signup != null) (
        lib.optional (
          (a.signup.credential == "parent") != (a.signup.parent != null)
        ) "accounts.held.${name}.signup: `parent` is set exactly when credential = \"parent\""
      )
    ) cfg.held
  );
  problems =
    signupProblems
    ++ lib.concatMap (
      d:
      let
        a = cfg.held.${d.account} or null;
        c = if a == null then null else cfg.plans.${a.provider}.${a.plan}.capabilities.${d.capability};
      in
      if a == null then
        [ "${d.why}: no account `${d.account}` is declared" ]
      else if !(capabilities.${a.provider} ? ${d.capability}) then
        [
          "${d.why}: ${a.provider} plans have no capability `${d.capability}`; known: ${
            lib.concatStringsSep ", " (lib.attrNames capabilities.${a.provider})
          }"
        ]
      else if covers c.value d.need then
        [ ]
      else
        [
          "${d.why}: needs ${d.capability} = ${builtins.toJSON d.need}, but ${d.account} is on ${a.provider} ${a.plan} with ${builtins.toJSON c.value} (${c.source})"
        ]
    ) cfg.demands;
in
{
  options.accounts = {
    plans = lib.genAttrs providers (
      p:
      mkOption {
        type = types.attrsOf (plan p);
        default = { };
      }
    );
    held = mkOption {
      type = types.attrsOf held;
      default = { };
    };
    demands = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            account = mkOption { type = types.str; };
            capability = mkOption { type = types.str; };
            need = mkOption { type = types.either types.ints.unsigned types.bool; };
            why = mkOption { type = types.str; };
          };
        }
      );
      default = [ ];
      description = "What the rest of the repo needs from each account; checked against its plan.";
    };
    checked = mkOption {
      type = types.raw;
      readOnly = true;
    };
  };

  config.accounts.checked =
    if problems == [ ] then
      lib.mapAttrs (
        _: a:
        a // { capabilities = lib.mapAttrs (_: c: c.value) cfg.plans.${a.provider}.${a.plan}.capabilities; }
      ) cfg.held
    else
      throw "accounts: the declared plans do not cover what the repo needs:\n${
        lib.concatMapStrings (p: "  - ${p}\n") problems
      }";
}
