# The agent teams as one readable view: every governance agent (a team, in
# ../agents/teams.nix's sense) with what it runs on (model, key and share,
# harness, tools), what it may propose, the areas it owns and reviews
# (organization.areas) and the Proton token it signs in with.
#
#   nix run .#team -- list [--json]
#   nix run .#team -- show <agent> [--json]
#   nix run .#team -- tree [--json]        entity -> area -> owner, reviewers
#   nix run .#team -- whoami [--json]      the agent KAGAMIZO_PRINCIPAL names
#                                          (orca-swarm sets agent:<name>)
#
# checks.team-lean proves, over every agent and area, that work is
# delegated: every agent owns or reviews some area, so none is idle, and
# every area but the owner's own address (zach@) has an owner. ../organization's Lean holds
# the rest (no self-review, classes within the owner's); ../agents' holds
# the budgets. Read-only: no account, no secret.
{ lib, config, ... }:
let
  agents = config.governance.agents;
  areas = config.organization.areas;
  q = builtins.toJSON;
  keyOf = a: if a.key != null then a.key else "swarms-${a.serves}";
  token = name: config.proton.agents."swarm-${name}" or null;

  flatAreas = lib.concatLists (
    lib.mapAttrsToList (
      entity: as: lib.mapAttrsToList (mailbox: a: a // { inherit entity mailbox; }) as
    ) areas
  );
  # The owner's own address on any domain (zach@, zach+tag@): the one kind
  # of area that has no agent owner by design (organization.areas).
  ownersOwn = m: m == "zach" || lib.hasPrefix "zach+" m;
  owns = n: map (a: "${a.entity}/${a.mailbox}") (lib.filter (a: a.owner == n) flatAreas);
  reviews = n: map (a: "${a.entity}/${a.mailbox}") (lib.filter (a: lib.elem n a.reviewers) flatAreas);

  lean = ''
    namespace Kagamizo.Team

    def agents : List String := ${q (lib.attrNames agents)}

    def areas : List Area := [
    ${lib.concatMapStringsSep ",\n" (
      a:
      "  { name := ${q "${a.entity}/${a.mailbox}"}, owner := ${
          if a.owner == null then "none" else "some ${q a.owner}"
        }, reviewers := ${q a.reviewers}, personal := ${lib.boolToString (ownersOwn a.mailbox)} }"
    ) flatAreas}
    ]

    theorem declared_delegated : delegated agents areas = true := by decide +kernel

    end Kagamizo.Team
  '';

  strs = xs: "&[${lib.concatMapStringsSep ", " q xs}]";
  rust = ''
    pub const ENTITIES: &[(&str, &str)] = &[${
      lib.concatStringsSep ", " (
        lib.mapAttrsToList (n: e: "(${q n}, ${q e.kind})") config.identity.checked.entities
      )
    }];

    pub const AREAS: &[Area] = &[
    ${
      lib.concatMapStrings (a: ''
        Area { entity: ${q a.entity}, mailbox: ${q a.mailbox}, owner: ${
          if a.owner == null then "None" else "Some(${q a.owner})"
        }, reviewers: ${strs a.reviewers}, classes: ${strs a.changeClasses}, purpose: ${q a.purpose} },
      '') flatAreas
    }];

    pub const AGENTS: &[Agent] = &[
    ${
      lib.concatStrings (
        lib.mapAttrsToList (
          n: a:
          let
            k = config.openrouter.keys.${keyOf a} or null;
            t = token n;
          in
          ''
            Agent {
              name: ${q n}, serves: ${q a.serves}, purpose: ${q a.purpose},
              model: ${q a.model}, key: ${q (keyOf a)}, key_limit_usd: ${
                toString (if k == null then 0 else k.limitUsd)
              }, key_reset: ${q (if k == null then "" else k.reset)}, share_usd: ${toString a.budgetUsdPerMonth},
              harness: ${q a.harness}, tools: ${strs a.tools}, change_classes: ${strs a.changeClasses},
              personas: ${strs a.personas},
              token: ${q (if t == null then "" else "swarm-${n}")}, token_vault: ${
                q (if t == null then "" else t.vault)
              },
              owns: ${strs (owns n)}, reviews: ${strs (reviews n)},
              grants: &[${
                lib.concatMapStringsSep ", " (
                  g: "Grant { account: ${q g.account}, effects: ${strs g.effects}, why: ${q g.why} }"
                ) a.grants
              }],
            },
          ''
        ) agents
      )
    }];
  '';
in
{
  perSystem =
    { pkgs, ... }:
    let
      facts = pkgs.writeText "team-facts.rs" rust;
      team = pkgs.rustPlatform.buildRustPackage {
        pname = "team";
        version = "0.2.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        TEAM_FACTS = facts;
        meta.mainProgram = "team";
      };
    in
    {
      packages.team = team;
      checks.team-lean =
        pkgs.runCommand "team-lean"
          {
            nativeBuildInputs = [ pkgs.lean4 ];
            facts = lean;
            passAsFile = [ "facts" ];
          }
          ''
            cat ${./_lean/Team.lean} "$factsPath" > Check.lean
            lean Check.lean
            touch $out
          '';
      checks.team-tests = team.overrideAttrs (_: {
        doCheck = true;
      });
    };
}
