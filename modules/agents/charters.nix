# The teams as contracted teams (the owner's direction, 2026-11-06): each
# governance agent has a charter (a goal, how it is measured, a project
# manager, and every persona's role), and every kind of work has a typed
# lifecycle (who proposes it, which other teams must pass it, and whether
# the owner signs it off), so the teams hold each other in check.
#
#   agents.charters.<agent> = { goal; measures; pm; roles.<persona>; }
#   agents.lifecycle.<kind> = { proposer; reviewers; signOff; touches; }
#
# The project manager and every role are one of the agent's own personas
# (../governance/options.nix), so a charter cannot name a role the team
# does not have. Trades are reviewed by the legal and accounting swarms of
# the account's owner (public-mirazo: the owner's own, the decision of
# 2026-11-05), and anything that moves money or goes live needs the owner.
#
# checks.agents-charters (./_lean/Charters.lean) decides: no kind is
# reviewed by its own proposer, every kind has a reviewer, every trade is
# reviewed by both legal and accounting of the account's owner, everything
# touching money or going live is signed off by the owner, and every
# chartered team that proposes work is reviewed by some other team.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  agents = config.governance.agents;
  names = lib.attrNames agents;
  cfg = config.agents;

  charter = types.submodule {
    options = {
      goal = mkOption {
        type = types.str;
        description = "What the team is contracted to deliver, in one sentence.";
      };
      measures = mkOption {
        type = types.nonEmptyListOf types.str;
        description = "How the goal is measured.";
      };
      pm = mkOption {
        type = types.str;
        description = "The persona that runs the team's backlog: one of its own personas.";
      };
      roles = mkOption {
        type = types.attrsOf types.str;
        description = "Each persona's duty, keyed by persona.";
      };
    };
  };

  kind = types.submodule {
    options = {
      proposer = mkOption {
        type = types.enum names;
        description = "The team that proposes this kind of work.";
      };
      reviewers = mkOption {
        type = types.listOf (types.enum names);
        description = "The teams that must all pass it.";
      };
      signOff = mkOption {
        type = types.enum [
          "owner"
          "none"
        ];
        description = "Whether the owner signs it off after the reviews.";
      };
      touches = mkOption {
        type = types.listOf (
          types.enum [
            "code"
            "pages"
            "world"
            "research"
            "trade"
            "live"
            "money"
            "filing"
            "publication"
          ]
        );
        description = "What it affects; trade, live and money carry the strictest rules.";
      };
    };
  };

  # A charter's personas must be the agent's own.
  problems = lib.concatLists (
    lib.mapAttrsToList (
      a: c:
      let
        own = agents.${a}.personas or [ ];
      in
      lib.optional (!(agents ? ${a})) "agents.charters.${a}: no such governance agent"
      ++ lib.optional (!(lib.elem c.pm own)) "agents.charters.${a}.pm: ${c.pm} is not one of its personas"
      ++ map (p: "agents.charters.${a}.roles: ${p} is not one of its personas") (
        lib.filter (p: !(lib.elem p own)) (lib.attrNames c.roles)
      )
    ) cfg.charters
  );

  q = builtins.toJSON;
  list = xs: "[${lib.concatMapStringsSep ", " q xs}]";
  facts = ''

    namespace Kagamizo.Charters

    def accountOwner : String := ${q cfg.tradingAccountOwner}

    def kinds : List Kind := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: k:
        "  { name := ${q n}, proposer := ${q k.proposer}, reviewers := ${list k.reviewers}, ownerSignsOff := ${
            lib.boolToString (k.signOff == "owner")
          }, touches := ${list k.touches} }"
      ) cfg.lifecycle
    )}
    ]

    def chartered : List String := ${list (lib.attrNames cfg.charters)}

    theorem lifecycle_sound : sound accountOwner kinds = true := by decide +kernel

    theorem every_proposer_reviewed : proposersReviewed kinds chartered = true := by decide +kernel

    end Kagamizo.Charters
  '';
in
{
  options.agents = {
    charters = mkOption {
      type = types.attrsOf charter;
      default = { };
      description = "Each team's contract: goal, measures, project manager, roles.";
    };
    lifecycle = mkOption {
      type = types.attrsOf kind;
      default = { };
      description = "Each kind of work: who proposes, who reviews, who signs off.";
    };
    tradingAccountOwner = mkOption {
      type = types.enum (lib.attrNames config.identity.checked.entities);
      default = "mirazo";
      description = "Whose account the trading agents trade (public-mirazo, 2026-11-05).";
    };
  };

  config = {
    governance.problems = problems;

    agents.charters = {
      research-jingzo = {
        goal = "Find and prove trading strategies that earn after costs, from research to a paper record good enough to promote";
        measures = [
          "a backtest and five dated paper days per strategy before promotion"
          "every strategy's paper published, redacted, with its numbers"
        ];
        pm = "research/research-synthesist";
        roles = {
          "research/research-synthesist" = "runs the research loop and writes each strategy's paper";
          "finance/finance-fpa-analyst" = "models returns, costs and drawdowns for every proposal";
        };
      };
      legal-mirazo = {
        goal = "Pass no trade or promotion that breaks a rule the compliance index names for the owner's account";
        measures = [
          "every trade proposal reviewed against modules/compliance before it runs"
          "no pattern-day-trader or options-level breach"
        ];
        pm = "support/support-legal-compliance-checker";
        roles = {
          "support/support-legal-compliance-checker" = "checks each proposal against the compliance index";
          "specialized/legal-document-review" = "reads every account agreement and change of terms";
        };
      };
      accounting-mirazo = {
        goal = "Keep the owner's books exact and every trade's tax effect known before it runs";
        measures = [
          "the ledger reconciled nightly with Public and Mercury, read-only"
          "each proposal's realized gain, wash-sale risk and cash effect stated"
        ];
        pm = "finance/finance-bookkeeper-controller";
        roles = {
          "finance/finance-bookkeeper-controller" = "reconciles the ledger and proposes the floor flows";
          "finance/finance-tax-strategist" = "states each trade's tax effect and the year's position";
          "finance/finance-fpa-analyst" = "forecasts the operating floor and the cash that can stay invested";
        };
      };
      governance-mirazo = {
        goal = "Hold every agent acting for the owner to its grants, and sign nothing the owner must";
        measures = [
          "every promotion and money flow reviewed before it reaches the owner"
          "no agent action outside its Cedar grants"
        ];
        pm = "specialized/specialized-chief-of-staff";
        roles = {
          "specialized/specialized-chief-of-staff" =
            "runs the review queue and brings the owner what needs a tap";
          "specialized/chief-financial-officer" = "weighs each promotion against the money plan";
          "specialized/agentic-identity-trust" = "checks every agent's identity and grants";
          "security/security-compliance-auditor" = "audits the controls each quarter";
          "specialized/automation-governance-architect" = "keeps the lifecycles and policies coherent";
        };
      };
      legal-jingzo = {
        goal = "Keep Jingzo (QSearch LLC) in good standing: filings, records and published research cleared";
        measures = [
          "every filing prepared before its deadline"
          "every published paper cleared of facts the denylist forbids"
        ];
        pm = "support/support-legal-compliance-checker";
        roles = {
          "support/support-legal-compliance-checker" = "tracks filings and their deadlines";
          "specialized/legal-document-review" = "clears each paper and document before it is published";
        };
      };
      accounting-jingzo = {
        goal = "Keep Jingzo's books, spend and tax exact";
        measures = [
          "every card and key's spend reconciled monthly"
          "every filing's figures prepared from the books"
        ];
        pm = "finance/finance-bookkeeper-controller";
        roles = {
          "finance/finance-bookkeeper-controller" = "keeps the books and reconciles spend";
          "finance/finance-tax-strategist" = "prepares the company's tax position";
          "finance/finance-fpa-analyst" = "budgets the teams' keys against the card";
        };
      };
      governance-jingzo = {
        goal = "Hold Jingzo's agents to their grants and its research to its rules";
        measures = [
          "every research signal reviewed before it becomes a proposal"
          "every filing reviewed before the owner signs it"
        ];
        pm = "specialized/specialized-chief-of-staff";
        roles = {
          "specialized/specialized-chief-of-staff" = "runs Jingzo's review queue";
          "specialized/chief-financial-officer" = "weighs spend and research against the plan";
          "specialized/agentic-identity-trust" = "checks every agent's identity and grants";
          "security/security-compliance-auditor" = "audits the controls";
          "specialized/automation-governance-architect" = "keeps the lifecycles coherent";
        };
      };
      review = {
        goal = "Pass no code, tool, page or mod that fails the checks or the plan";
        measures = [
          "every pull request from agents/* reviewed against nix flake check"
          "no merged change that later fails CI"
        ];
        pm = "engineering/engineering-code-reviewer";
        roles = {
          "engineering/engineering-code-reviewer" = "reviews every change and runs the gate";
          "testing/testing-reality-checker" = "checks that what a change claims is what it does";
        };
      };
      upkeep = {
        goal = "Keep the repository's tools pinned, building and within its language rule";
        measures = [
          "the language exceptions' baseline lowered every week"
          "every pinned project current within a month of its release"
        ];
        pm = "engineering/engineering-git-workflow-master";
        roles = {
          "engineering/engineering-developer-tooling-engineer" = "rewrites shell and Python into Rust crates";
          "engineering/engineering-git-workflow-master" = "runs the backlog and the branches";
          "testing/testing-tool-evaluator" = "maps each new tool with REA before it is adopted";
        };
      };
      design = {
        goal = "Make every page the owner opens clear on a phone and a desktop, from adopted parts";
        measures = [
          "every page passing the page check at 390 and 1280 pixels"
          "every visual adopted from an open-licensed source, cited"
        ];
        pm = "design/design-ux-architect";
        roles = {
          "design/design-ui-designer" = "lays out each page from the design system";
          "design/design-ux-architect" = "runs the backlog and decides each page's structure";
          "design/design-ui-finish-gate-reviewer" = "passes or fails each page against the rubric";
        };
      };
      twin = {
        goal = "Mirror the business and the owner's inventory in the Minecraft twin, built from adopted Rust parts";
        measures = [
          "every module, team and account represented in the world"
          "every adopted server, bot and renderer pinned with its licence read"
        ];
        pm = "engineering/engineering-software-architect";
        roles = {
          "game-development/technical-artist" = "brings adopted assets and models into the world";
          "engineering/engineering-rust-refactoring-specialist" =
            "writes the world's Rust plugins and wiring";
          "engineering/engineering-software-architect" = "runs the backlog and the world's architecture";
        };
      };
      builders = {
        goal = "Build the twin's world: rooms per team, districts per area, kept in step with the declarations";
        measures = [
          "every declared team's room built and labelled"
          "the world's map matching the declarations after each change"
        ];
        pm = "game-development/level-designer";
        roles = {
          "game-development/game-designer" = "designs how the world shows status";
          "game-development/level-designer" = "runs the backlog and lays out districts and rooms";
        };
      };
    };

    agents.lifecycle = {
      research-signal = {
        proposer = "research-jingzo";
        reviewers = [ "governance-jingzo" ];
        signOff = "none";
        touches = [ "research" ];
      };
      paper-trade = {
        proposer = "research-jingzo";
        reviewers = [
          "legal-mirazo"
          "accounting-mirazo"
        ];
        signOff = "none";
        touches = [ "trade" ];
      };
      promotion = {
        proposer = "research-jingzo";
        reviewers = [
          "legal-mirazo"
          "accounting-mirazo"
          "governance-mirazo"
        ];
        signOff = "owner";
        touches = [
          "trade"
          "live"
        ];
      };
      live-trade = {
        proposer = "research-jingzo";
        reviewers = [
          "legal-mirazo"
          "accounting-mirazo"
        ];
        signOff = "owner";
        touches = [
          "trade"
          "live"
          "money"
        ];
      };
      money-flow = {
        proposer = "accounting-mirazo";
        reviewers = [ "governance-mirazo" ];
        signOff = "owner";
        touches = [ "money" ];
      };
      filing = {
        proposer = "legal-jingzo";
        reviewers = [
          "accounting-jingzo"
          "governance-jingzo"
        ];
        signOff = "owner";
        touches = [ "filing" ];
      };
      publication = {
        proposer = "research-jingzo";
        reviewers = [
          "legal-jingzo"
          "review"
        ];
        signOff = "owner";
        touches = [ "publication" ];
      };
      code = {
        proposer = "upkeep";
        reviewers = [ "review" ];
        signOff = "owner";
        touches = [ "code" ];
      };
      page = {
        proposer = "design";
        reviewers = [
          "review"
          "upkeep"
        ];
        signOff = "owner";
        touches = [ "pages" ];
      };
      world = {
        proposer = "twin";
        reviewers = [
          "review"
          "builders"
        ];
        signOff = "owner";
        touches = [ "world" ];
      };
      world-content = {
        proposer = "builders";
        reviewers = [ "twin" ];
        signOff = "none";
        touches = [ "world" ];
      };
    };

    perSystem =
      { config, ... }:
      {
        checks.agents-charters =
          assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
          config.kagamizo.leanCheck {
            name = "agents-charters";
            source = ./_lean/Charters.lean;
            inherit facts;
          };
      };
  };
}
