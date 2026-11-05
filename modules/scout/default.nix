# Discovery: what could fill every role, so nothing is bound to the tools
# at hand. A role is an account role (accounts.roles) or a need no account
# fills yet (scout.needs); every role keeps candidates in
# ./_data/candidates.json, typed here and proven in Lean:
#
#   * every role a held account fills has a live alternative (an exit);
#   * nothing adopted adds a cost: free, a free tier, or an account already
#     held, whose payment is declared there (accounts.held.<a>.payment);
#   * adopting or rejecting needs a dated finding.
#
#   nix run .#scout -- roles | list [role] [--status S] | show <name>
#                      | gaps | score <role|name> [--json]
#
# `score` reads each candidate's GitHub repository through the pinned gh
# (archived, last push, latest release, licence) and prints a stability
# score; no model, no key beyond gh's. The research team
# (governance.teams.research) keeps the candidates current: the file is
# agent-mergeable content, adopting stays the owner's.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.scout;
  q = builtins.toJSON;
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";

  accountRoles = lib.unique (lib.concatLists (lib.attrValues config.accounts.roles));
  roles = accountRoles ++ cfg.needs;
  providers = lib.attrNames config.accounts.roles;

  # The providers filling a role today: a held account, active or planned.
  heldIn =
    role:
    lib.unique (
      lib.mapAttrsToList (_: a: a.provider) (
        lib.filterAttrs (
          _: a: a.status != "retiring" && lib.elem role (config.accounts.roles.${a.provider} or [ ])
        ) config.accounts.held
      )
    );
  isHeld = p: p != null && lib.any (a: a.provider == p) (lib.attrValues config.accounts.held);

  candidate = types.submodule {
    options = {
      url = mkOption { type = types.strMatching "https://.+"; };
      repo = mkOption {
        type = types.nullOr (types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+");
        description = "Its GitHub repository, for `scout score`.";
      };
      license = mkOption {
        type = types.enum [
          "MIT"
          "Apache-2.0"
          "BSD-3-Clause"
          "MPL-2.0"
          "LGPL-3.0"
          "GPL-3.0"
          "AGPL-3.0"
          "open-data"
          "proprietary"
          "unknown"
        ];
      };
      selfHost = mkOption { type = types.bool; };
      cost = mkOption {
        type = types.enum [
          "free"
          "free-tier"
          "usage"
          "subscription"
        ];
      };
      api = mkOption {
        type = types.enum [
          "none"
          "rest"
          "graphql"
          "websocket"
          "cli"
          "mcp"
          "dataset"
        ];
      };
      status = mkOption {
        type = types.enum [
          "candidate"
          "mapped"
          "adopted"
          "rejected"
        ];
        description = "candidate: found; mapped: its API catalogued from the pinned thing; adopted: in use; rejected: with a dated reason.";
      };
      provider = mkOption {
        type = types.nullOr (types.enum providers);
        description = "The accounts provider it is, when it is one.";
      };
      evidence = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              fact = mkOption { type = types.str; };
              source = mkOption { type = types.strMatching "https://.+"; };
              checked = mkOption { type = date; };
            };
          }
        );
      };
      why = mkOption { type = types.str; };
    };
  };

  flat = lib.concatLists (
    lib.mapAttrsToList (role: lib.mapAttrsToList (name: c: c // { inherit role name; })) cfg.candidates
  );
  alternative = c: c.provider == null || !(lib.elem c.provider (heldIn c.role));

  problems =
    map
      (
        r:
        "scout: role ${r} is filled by ${lib.concatStringsSep ", " (heldIn r)} and has no live alternative"
      )
      (
        lib.filter (
          r: heldIn r != [ ] && !(lib.any (c: c.role == r && c.status != "rejected" && alternative c) flat)
        ) roles
      )
    ++ map (c: "scout.candidates.${c.role}.${c.name}: adopted at cost ${c.cost} with no held account") (
      lib.filter (
        c:
        c.status == "adopted"
        && !(lib.elem c.cost [
          "free"
          "free-tier"
        ])
        && !(isHeld c.provider)
      ) flat
    )
    ++ map (c: "scout.candidates.${c.role}.${c.name}: ${c.status} needs evidence") (
      lib.filter (
        c:
        lib.elem c.status [
          "adopted"
          "rejected"
        ]
        && c.evidence == [ ]
      ) flat
    );

  ctor =
    s:
    "."
    + (
      {
        free-tier = "freeTier";
      }
      .${s} or s
    );
  lean = ''
    namespace Kagamizo.Scout

    def roles : List Role := [
    ${lib.concatMapStringsSep ",\n" (
      r: "  { name := ${q r}, heldProviders := ${toString (lib.length (heldIn r))} }"
    ) roles}
    ]

    def candidates : List Candidate := [
    ${lib.concatMapStringsSep ",\n" (
      c:
      "  { role := ${q c.role}, name := ${q c.name}, cost := ${ctor c.cost}, status := ${ctor c.status}, held := ${lib.boolToString (isHeld c.provider)}, alternative := ${lib.boolToString (alternative c)}, evidence := ${toString (lib.length c.evidence)} }"
    ) flat}
    ]

    theorem declared_sound : sound roles candidates = true := by decide +kernel

    end Kagamizo.Scout
  '';

  strs = xs: "&[${lib.concatMapStringsSep ", " q xs}]";
  opt = v: if v == null then "None" else "Some(${q v})";
  rust = ''
    pub const ROLES: &[Role] = &[
    ${
      lib.concatMapStrings (r: ''
        Role { name: ${q r}, need: ${lib.boolToString (lib.elem r cfg.needs)}, held: ${strs (heldIn r)} },
      '') roles
    }];

    pub const CANDIDATES: &[Candidate] = &[
    ${
      lib.concatMapStrings (c: ''
        Candidate {
          role: ${q c.role}, name: ${q c.name}, url: ${q c.url}, repo: ${opt c.repo}, license: ${q c.license},
          self_host: ${lib.boolToString c.selfHost}, cost: ${q c.cost}, api: ${q c.api}, status: ${q c.status},
          provider: ${opt c.provider}, held: ${lib.boolToString (isHeld c.provider)}, alternative: ${lib.boolToString (alternative c)},
          why: ${q c.why},
          evidence: &[${
            lib.concatMapStringsSep ", " (
              e: "Evidence { fact: ${q e.fact}, source: ${q e.source}, checked: ${q e.checked} }"
            ) c.evidence
          }],
        },
      '') flat
    }];
  '';
in
{
  options.scout = {
    needs = mkOption {
      type = types.listOf (types.strMatching "[a-z][a-z0-9-]*");
      description = "Roles no account fills yet, searched for all the same.";
    };
    candidates = mkOption {
      type = types.submodule {
        options = lib.genAttrs roles (
          _:
          mkOption {
            type = types.attrsOf candidate;
            default = { };
          }
        );
      };
      description = "Per role, everything that could fill it (./_data/candidates.json).";
    };
  };

  config = {
    scout = {
      needs = [
        "research"
        "inventory"
        "parts"
        "shipping"
        "flights"
        "fx"
        "market-data"
        "agent-mail"
        "code-review"
        "osint"
        "connectivity"
        "search"
      ];
      candidates = lib.importJSON ./_data/candidates.json;
    };

    perSystem =
      { pkgs, config, ... }:
      let
        facts = pkgs.writeText "scout-facts.rs" rust;
        bin = pkgs.rustPlatform.buildRustPackage {
          pname = "scout";
          version = "0.1.0";
          src = ./_src;
          cargoLock.lockFile = ./_src/Cargo.lock;
          SCOUT_FACTS = facts;
          meta.mainProgram = "scout";
        };
        # The pinned gh on PATH for `score`.
        scout = pkgs.writeShellApplication {
          name = "scout";
          runtimeInputs = [ config.packages.gh ];
          text = ''exec ${lib.getExe bin} "$@"'';
        };
      in
      {
        packages.scout = scout;
        checks = {
          scout-lean =
            assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
            pkgs.runCommand "scout-lean"
              {
                nativeBuildInputs = [ pkgs.lean4 ];
                facts = lean;
                passAsFile = [ "facts" ];
              }
              ''
                cat ${./_lean/Scout.lean} "$factsPath" > Check.lean
                lean Check.lean
                touch $out
              '';
          scout-tests = bin.overrideAttrs (_: {
            doCheck = true;
          });
          scout-data = pkgs.runCommand "scout-data" { nativeBuildInputs = [ pkgs.jq ]; } ''
            f=${./_data/candidates.json}
            jq -S --indent 2 . "$f" | diff -u - "$f" || {
              echo "$f is not canonical: jq -S --indent 2" >&2
              exit 1
            }
            touch $out
          '';
        };
      };
  };
}
