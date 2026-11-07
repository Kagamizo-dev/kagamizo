# Penetration testing of our own surfaces only. The scope is every asset we
# hold that can be tested; an online asset is tested through the account
# that hosts it, by a penetration tester serving that account's entity, with
# the `probe` effect (../governance), so Cedar refuses a probe of anything
# else exactly as it refuses a read: an agent acts only on its own entity's
# accounts, and only with a grant. The business takes no client work, so
# nobody else's systems are ever in scope.
#
#   security.scope.<s>  an asset: what it is, which account hosts it (for
#                       online assets) and which entity owns it
#   security.tools.<t>  a pinned scanner and the targets whose images carry
#                       it (the kit's Pi among them, so it travels)
#   security.toolsModule <target>   those tools as a NixOS module
#
#   checks.security-scope  Lean (./_lean/Scope.lean): every online asset has
#                          an account; every hostname is under a domain of
#                          its owner; every online asset's account is probed
#                          by a grant, and every probe grant has an asset
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.security;
  q = builtins.toJSON;
  zone = config.hetzner.host.agents.zone;
  entities = lib.attrNames config.identity.entities;

  asset = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "host"
          "hostname"
          "repo"
          "image"
          "device"
        ];
        description = "host, hostname, repo: online, tested through their account; image, device: offline, tested on our own machines.";
      };
      asset = mkOption {
        type = types.str;
        description = "The server's name, the hostname, the repository, the image or the device.";
      };
      account = mkOption {
        type = types.nullOr (types.enum (lib.attrNames config.accounts.held));
        default = null;
      };
      entity = mkOption { type = types.enum entities; };
      why = mkOption { type = types.str; };
    };
  };

  tool = types.submodule {
    options = {
      package = mkOption { type = types.str; };
      targets = mkOption { type = types.listOf (types.enum (lib.attrNames config.shell.targets)); };
      why = mkOption { type = types.str; };
    };
  };

  # A penetration tester for one entity: probe grants on its accounts.
  tester = entity: accounts: {
    serves = entity;
    purpose = "the penetration tester for ${entity}'s own surface: probes only the assets in security.scope, through the accounts that host them";
    personas = [ "security/security-penetration-tester" ];
    # It runs scanners, not models: no share of a key.
    budgetUsdPerMonth = 0;
    grants = map (account: {
      inherit account;
      effects = [
        "read"
        "probe"
      ];
      why = "probing ${account}'s assets in security.scope";
    }) accounts;
  };
in
{
  options.security = {
    scope = mkOption {
      type = types.attrsOf asset;
      default = { };
    };
    tools = mkOption {
      type = types.attrsOf tool;
      default = { };
    };
    toolsModule = mkOption {
      type = types.functionTo types.raw;
      readOnly = true;
      description = "A target's scanners as a NixOS module, for its image to import.";
      default =
        t:
        { pkgs, lib, ... }:
        {
          environment.systemPackages = map (w: pkgs.${w.package}) (
            lib.filter (w: lib.elem t w.targets) (lib.attrValues cfg.tools)
          );
        };
    };
  };

  config = {
    security = {
      scope = {
        jingzo-host = {
          kind = "host";
          asset = config.hetzner.host.name;
          account = "hetzner";
          entity = "jingzo";
          why = "the server: a probe confirms it exposes nothing beyond what is declared, its services being reached through the tunnel";
        };
        status = {
          kind = "hostname";
          asset = "status.mirazo.org";
          account = "cloudflare";
          entity = "mirazo";
          why = "the status page, behind Access";
        };
        repo = {
          kind = "repo";
          asset = config.github.repoState.repo;
          account = "github-kagamizo";
          entity = "kagamizo";
          why = "the public repository: secrets, dependencies and the workflows";
        };
        yoga-c940 = {
          kind = "image";
          asset = "yoga-c940";
          entity = "kagamizo";
          why = "the Yoga's image: its packages' known vulnerabilities";
        };
        rpi5 = {
          kind = "image";
          asset = "rpi5";
          entity = "kagamizo";
          why = "the Pi's image: its packages' known vulnerabilities";
        };
        pixel-9a = {
          kind = "device";
          asset = "pixel-9a";
          entity = "mirazo";
          why = "the phone: what it exposes over its radios and USB, tested from the kit";
        };
      }
      # Every service behind the agents tunnel, by its hostname.
      // lib.listToAttrs (
        map (
          s:
          lib.nameValuePair "host-${s.name}" {
            kind = "hostname";
            asset = "${s.name}.${zone}";
            account = "cloudflare";
            entity = "jingzo";
            why = "a service of jingzo-host behind Access";
          }
        ) config.hetzner.host.agents.services
      );

      # The scanners, on the Yoga and on the Pi in the pocket.
      tools =
        let
          both = [
            "yoga-c940"
            "rpi5"
          ];
        in
        {
          nmap = {
            package = "nmap";
            targets = both;
            why = "which ports and services an asset exposes";
          };
          nuclei = {
            package = "nuclei";
            targets = both;
            why = "known weaknesses of web services, from a pinned template set";
          };
          testssl = {
            package = "testssl";
            targets = both;
            why = "TLS configuration of every hostname";
          };
          trivy = {
            package = "trivy";
            targets = both;
            why = "known vulnerabilities of an image's packages and the repository's dependencies";
          };
          gitleaks = {
            package = "gitleaks";
            targets = both;
            why = "secrets in the repository's history";
          };
          zap = {
            package = "zap";
            targets = [ "yoga-c940" ];
            why = "OWASP ZAP: the web services, actively, with a screen";
          };
        };
    };

    # The testers: one per entity whose accounts host online assets.
    governance = {
      agents = lib.mapAttrs' (e: accounts: lib.nameValuePair "security-${e}" (tester e accounts)) (
        lib.groupBy' (acc: a: lib.unique (acc ++ [ a.account ])) [ ] (
          a: config.accounts.held.${a.account}.owner
        ) (lib.filter (a: a.account != null && a.kind != "repo") (lib.attrValues cfg.scope))
      );

      # The probes, each a typed action of the account's provider.
      actions = {
        hetzner.probe-host = {
          effect = "probe";
          description = "Scan jingzo-host's ports and services (nmap, nuclei) from outside";
          command = "security-scan host";
        };
        cloudflare.probe-hostname = {
          effect = "probe";
          description = "Test a hostname behind Access (testssl, nuclei, ZAP baseline) with the tester's service token";
          command = "security-scan hostname";
        };
      };

      # Only a penetration tester holds a probe grant.
      problems = lib.concatLists (
        lib.mapAttrsToList (
          n: a:
          lib.optional (
            lib.any (g: lib.elem "probe" g.effects) a.grants
            && !(lib.elem "security/security-penetration-tester" a.personas)
          ) "governance.agents.${n}: holds a probe grant but is not a penetration tester"
        ) config.governance.agents
      );
    };

    perSystem =
      { config, ... }:
      let
        probeGrants = lib.concatLists (
          lib.mapAttrsToList (
            n: a: map (g: "(${q n}, ${q g.account})") (lib.filter (g: lib.elem "probe" g.effects) a.grants)
          ) top.governance.agents
        );
      in
      {
        checks.security-scope = config.kagamizo.leanCheck {
          name = "security-scope";
          source = ./_lean/Scope.lean;
          facts = ''

            namespace Kagamizo.Security
            def scope : List Asset := [${
              lib.concatStringsSep ",\n  " (
                lib.mapAttrsToList (
                  n: s:
                  "{ name := ${q n}, kind := .${s.kind}, asset := ${q s.asset}, account := ${
                    q (if s.account == null then "" else s.account)
                  }, entity := ${q s.entity} }"
                ) cfg.scope
              )
            }]
            def domains : List (String × String) := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (d: v: "(${q d}, ${q v.entity})") top.identity.checked.domains
              )
            }]
            def owners : List (String × String) := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (n: a: "(${q n}, ${q a.owner})") (
                  lib.filterAttrs (_: a: a ? owner) top.accounts.held
                )
              )
            }]
            def probes : List (String × String) := [${lib.concatStringsSep ", " probeGrants}]

            theorem scope_sound : sound scope domains owners probes = true := by decide +kernel
            end Kagamizo.Security
          '';
        };
      };
  };
}
