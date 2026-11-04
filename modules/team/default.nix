# Agent identities, typed in Nix, proven in Lean, served by Rust. Every
# agent (governance.agents) is in one team (governance.teams), serves one
# entity, runs on one tier and one capped model key, reports in one room and
# proposes only the change classes it lists.
#
#   nix run .#team -- list [--json]
#   nix run .#team -- show <agent> [--json]
#   nix run .#team -- tree [--json]        entities -> teams -> agents
#   nix run .#team -- whoami [--json]      the agent KAGAMIZO_PRINCIPAL names
#                                          (orca-swarm sets agent:<name>)
#
# checks.team-lean has Lean decide the rules of ./_lean/Team.lean over every
# declared agent (own entity, tier within the team's cap, no self-review,
# reviewers propose nothing, own entity's key); checks.team-tests runs the
# crate's tests over the same facts. Read-only: no account, no secret.
{ lib, config, ... }:
let
  gov = config.governance;
  inherit (config.agents) tiers;
  q = builtins.toJSON;
  keyOf = a: "swarms-${a.serves}";
  key = a: config.openrouter.keys.${keyOf a};
  token = name: config.proton.agents."swarm-${name}";

  problems = lib.concatLists (
    lib.mapAttrsToList (
      n: a:
      let
        t = gov.teams.${a.team};
      in
      lib.optional (
        t.serves != null && t.serves != a.serves
      ) "governance.agents.${n}: team ${a.team} serves ${t.serves}, the agent ${a.serves}"
      ++ lib.optional (
        tiers.${a.tier}.rank > tiers.${t.tierCap}.rank
      ) "governance.agents.${n}: tier ${a.tier} is above team ${a.team}'s cap (${t.tierCap})"
      ++ lib.optional (lib.elem a.team a.reviews) "governance.agents.${n}: reviews its own team ${a.team}"
      ++ lib.optional (
        t.review && (a.changeClasses != [ ] || a.reviews == [ ])
      ) "governance.agents.${n}: a ${a.team} agent reviews some team and proposes no change class"
      ++ lib.optional (
        !(config.openrouter.keys ? ${keyOf a})
      ) "governance.agents.${n}: no OpenRouter key ${keyOf a}"
    ) gov.agents
  );

  lean = ''
    namespace Kagamizo.Team

    /-- Every team, rendered by modules/team. -/
    def teams : List Team := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: t:
        "  { name := ${q n}, serves := ${
            if t.serves == null then "none" else "some ${q t.serves}"
          }, review := ${lib.boolToString t.review}, capRank := ${toString tiers.${t.tierCap}.rank} }"
      ) gov.teams
    )}
    ]

    /-- Every agent. -/
    def agents : List Agent := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: a:
        "  { name := ${q n}, serves := ${q a.serves}, team := ${q a.team}, tierRank := ${toString tiers.${a.tier}.rank}, keyProfile := ${q (key a).profile}, changeClasses := ${q a.changeClasses}, reviews := ${q a.reviews} }"
      ) gov.agents
    )}
    ]

    theorem declared_sound : sound teams agents = true := by decide +kernel

    end Kagamizo.Team
  '';

  # The same facts as Rust source, for the CLI: string slices only.
  strs = xs: "&[${lib.concatMapStringsSep ", " q xs}]";
  opt = v: if v == null then "None" else "Some(${q v})";
  rust = ''
    pub const ENTITIES: &[(&str, &str)] = &[${
      lib.concatStringsSep ", " (
        lib.mapAttrsToList (n: e: "(${q n}, ${q e.kind})") config.identity.checked.entities
      )
    }];

    pub const TEAMS: &[Team] = &[
    ${
      lib.concatStrings (
        lib.mapAttrsToList (n: t: ''
          Team { name: ${q n}, purpose: ${q t.purpose}, serves: ${opt t.serves}, review: ${lib.boolToString t.review}, tier_cap: ${q t.tierCap} },
        '') gov.teams
      )
    }];

    pub const AGENTS: &[Agent] = &[
    ${
      lib.concatStrings (
        lib.mapAttrsToList (n: a: ''
          Agent {
            name: ${q n}, serves: ${q a.serves}, team: ${q a.team}, purpose: ${q a.purpose},
            tier: ${q a.tier}, tier_rank: ${toString tiers.${a.tier}.rank}, paid: ${
              lib.boolToString (tiers.${a.tier}.runs != "host")
            },
            model: ${opt tiers.${a.tier}.model},
            key: ${q (keyOf a)}, key_limit_usd: ${toString (key a).limitUsd}, key_reset: ${q (key a).reset},
            harness: ${q a.harness}, room: ${q a.room}, mail: ${q a.mail},
            token: ${q "swarm-${n}"}, token_vault: ${q (token n).vault}, token_expires: ${q (token n).expiration},
            personas: ${strs a.personas}, change_classes: ${strs a.changeClasses}, reviews: ${strs a.reviews},
            grants: &[${
              lib.concatMapStringsSep ", " (
                g: "Grant { account: ${q g.account}, effects: ${strs g.effects}, why: ${q g.why} }"
              ) a.grants
            }],
          },
        '') gov.agents
      )
    }];
  '';
in
{
  governance.problems = problems;

  perSystem =
    { pkgs, ... }:
    let
      facts = pkgs.writeText "team-facts.rs" rust;
      team = pkgs.rustPlatform.buildRustPackage {
        pname = "team";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        TEAM_FACTS = facts;
        meta.mainProgram = "team";
      };
    in
    {
      packages.team = team;
      checks.team-lean =
        assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
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
