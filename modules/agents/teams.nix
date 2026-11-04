# The agent teams the plan of 2026-11-04 starts with, each a governance
# agent (../governance/options.nix: one entity, personas, grants) with
# what it runs on and may propose. They run in DeepSeek Harness on
# jingzo-host (../hetzner/_harness.nix reads `agents.teamsJson`) and spend
# the Orca fleet's key; their shares add up to its cap, which Lean checks
# (./tiers.nix, checks.agents-budget).
#
#   design     proposes each page's layout against the mobile rubric
#   twin       turns inventory and CAD into the twin's items
#   builders   the bots in the world
#   research   the trading plan's research loops
#   upkeep     bumps pinned projects and reads changelogs
{ lib, config, ... }:
let
  team = personas: tools: changeClasses: budget: purpose: {
    serves = "kagamizo";
    inherit
      personas
      tools
      changeClasses
      purpose
      ;
    key = "orca-fleet";
    budgetUsdPerMonth = budget;
    harness = "dsh";
  };
in
{
  governance.agents = {
    design =
      team
        [
          "design/design-ui-designer"
          "design/design-ux-architect"
          "design/design-ui-finish-gate-reviewer"
        ] [ "shell" "repo" "matrix" ] [ "page-design" "content" ]
        4
        "the design team: three layouts, a critique, a pick; every page checked on a phone and a desktop";
    twin =
      team
        [
          "game-development/technical-artist"
          "engineering/engineering-rust-refactoring-specialist"
          "engineering/engineering-software-architect"
        ] [ "shell" "repo" "twin" "matrix" ] [ "content" "mod" ]
        4
        "the twin team: the owner's inventory and CAD into typed items and the world's mod";
    builders = team [
      "game-development/game-designer"
      "game-development/level-designer"
    ] [ "twin" "matrix" ] [ "content" ] 3 "the builders: the bots that build, craft and keep the world";
    research =
      team
        [
          "research/research-synthesist"
          "engineering/engineering-data-engineer"
        ] [ "web" "repo" "matrix" ] [ "content" ]
        5
        "the research team: the trading plan's research loops, read-only on markets";
    upkeep =
      team
        [
          "engineering/engineering-developer-tooling-engineer"
          "engineering/engineering-git-workflow-master"
          "testing/testing-tool-evaluator"
        ] [ "shell" "web" "repo" "matrix" ] [ "tool" "code" ]
        4
        "the upkeep team: bumps pinned projects, reads changelogs, maps new tools";
  };

  # A key an agent names must be declared; its entity's swarm key is the
  # default and always is.
  governance.problems = lib.concatLists (
    lib.mapAttrsToList (
      n: a:
      lib.optional (
        a.key != null && !(config.openrouter.keys ? ${a.key})
      ) "governance.agents.${n}: no openrouter.keys.${a.key}"
    ) config.governance.agents
  );
}
