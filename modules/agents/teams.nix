# The agent teams the plan of 2026-11-04 starts with, each a governance
# agent (../governance/options.nix: one entity, personas, grants) with
# what it runs on and may propose. They run in DeepSeek Harness on
# jingzo-host (../hetzner/_harness.nix reads `agents.teamsJson`) and spend
# the chat-and-code key; their shares (review 3 + design 4 + upkeep 4 = 11)
# fit its $20 cap. research-jingzo runs on the research key ($20), and twin
# and builders run on the mirazo swarm key (swarms-mirazo, $20). Lean checks
# every key's shares fit (./tiers.nix, checks.agents-budget).
#
#   design     proposes each page's layout against the mobile rubric
#   twin       turns inventory and CAD into the twin's items
#   builders   the bots in the world
#   review     reads every code or tool pull request
#   upkeep     bumps pinned projects and reads changelogs
{ lib, config, ... }:
let
  team = personas: tools: changeClasses: budget: purpose: key: model: {
    serves = "kagamizo";
    inherit
      personas
      tools
      changeClasses
      purpose
      ;
    inherit key model;
    budgetUsdPerMonth = budget;
    harness = "dsh";
  };
  # The twin is the person's: its teams serve mirazo on mirazo's swarm key.
  personal = personas: tools: changeClasses: budget: purpose: {
    serves = "mirazo";
    inherit
      personas
      tools
      changeClasses
      purpose
      ;
    budgetUsdPerMonth = budget;
    harness = "dsh";
  };
in
{
  governance.agents = {
    # Reviews the repository's code and tools before the owner approves:
    # never an owner of an area, so it never reviews its own work.
    review =
      team
        [
          "engineering/engineering-code-reviewer"
          "testing/testing-reality-checker"
        ] [ "repo" "matrix" ] [ ]
        3
        "the review team: reads every pull request of code or tools against the checks and the plan"
        "chat-and-code"
        "deepseek/deepseek-v4-flash";
    # Jingzo's research: the research-to-trade loop (research@jingzo.org).
    research-jingzo = {
      serves = "jingzo";
      purpose = "the research team: the trading plan's research loops, read-only on markets";
      personas = [
        "research/research-synthesist"
        "finance/finance-fpa-analyst"
      ];
      tools = [
        "web"
        "repo"
        "matrix"
      ];
      changeClasses = [ "content" ];
      key = "research";
      budgetUsdPerMonth = 20;
      harness = "dsh";
    };
    design =
      team
        [
          "design/design-ui-designer"
          "design/design-ux-architect"
          "design/design-ui-finish-gate-reviewer"
        ] [ "shell" "repo" "matrix" ] [ "page-design" "content" ]
        4
        "the design team: three layouts, a critique, a pick; every page checked on a phone and a desktop"
        "chat-and-code"
        "deepseek/deepseek-v4-flash";
    twin =
      personal
        [
          "game-development/technical-artist"
          "engineering/engineering-rust-refactoring-specialist"
          "engineering/engineering-software-architect"
        ] [ "shell" "repo" "twin" "matrix" ] [ "content" "mod" ]
        4
        "the twin team: the owner's inventory and CAD into typed items and the world's mod";
    builders = personal [
      "game-development/game-designer"
      "game-development/level-designer"
    ] [ "twin" "matrix" ] [ "content" ] 3 "the builders: the bots that build, craft and keep the world";
    # The owner's direction of 2026-11-06: industry-grade security in the
    # pipelines, and a team for every change's security review.
    security =
      team
        [
          "security/security-appsec-engineer"
          "security/security-penetration-tester"
          "security/security-threat-intelligence-analyst"
          "security/security-ai-generated-code-auditor"
        ] [ "shell" "repo" "matrix" ] [ ]
        3
        "the security team: reviews every change for vulnerabilities and secrets, tests what runs, watches advisories"
        "chat-and-code"
        "deepseek/deepseek-v4-flash";
    # Reverse engineering: maps an existing tool, protocol or device with REA
    # into a typed catalog and ports its tests, so we adopt the minimal
    # surface instead of building or running the whole thing.
    reverse-engineering =
      team
        [
          "specialized/specialized-codebase-archaeologist"
          "engineering/engineering-embedded-firmware-engineer"
          "testing/testing-api-tester"
        ] [ "shell" "web" "repo" "matrix" ] [ "tool" "code" ]
        3
        "the reverse-engineering team: maps tools, protocols and devices with REA into typed catalogs and ported tests"
        "chat-and-code"
        "deepseek/deepseek-v4-flash";
    # Browser automation, in Rust: sign-ups, aliases and web flows no API
    # covers, each a typed flow the owner's 2FA approves.
    browser =
      team
        [
          "testing/testing-test-automation-engineer"
          "engineering/engineering-api-platform-engineer"
        ] [ "shell" "web" "repo" "matrix" ] [ "tool" "code" ]
        3
        "the browser team: Rust browser flows for what no API covers, each typed and approved"
        "chat-and-code"
        "deepseek/deepseek-v4-flash";
    upkeep =
      team
        [
          "engineering/engineering-developer-tooling-engineer"
          "engineering/engineering-git-workflow-master"
          "testing/testing-tool-evaluator"
        ] [ "shell" "web" "repo" "matrix" ] [ "tool" "code" ]
        4
        "the upkeep team: bumps pinned projects, reads changelogs, maps new tools"
        "chat-and-code"
        "deepseek/deepseek-v4-flash";
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
