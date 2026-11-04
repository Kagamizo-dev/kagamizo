# The agent swarms: legal, accounting and governance, one of each per legal
# identity (you included), so no agent ever works for two of them. Personas are agency-agents'
# (flake input); grants are the only account access an agent gets, and the
# base policies (./cedar.nix) cap them whatever they say.
{ lib, ... }:
let
  swarm = serves: {
    "legal-${serves}" = {
      inherit serves;
      team = "legal";
      room = "#legal-${serves}";
      purpose = "Compliance, filings and documents served on ${serves}";
      personas = [
        "support/support-legal-compliance-checker"
        "specialized/legal-document-review"
      ];
    };
    "accounting-${serves}" = {
      inherit serves;
      team = "accounting";
      room = "#accounting-${serves}";
      purpose = "Books, invoices and tax for ${serves}";
      personas = [
        "finance/finance-bookkeeper-controller"
        "finance/finance-tax-strategist"
        "finance/finance-fpa-analyst"
      ];
    };
    "governance-${serves}" = {
      inherit serves;
      team = "governance";
      room = "#governance-${serves}";
      purpose = "Records, controls and agent oversight for ${serves}";
      personas = [
        "specialized/specialized-chief-of-staff"
        "specialized/chief-financial-officer"
        "specialized/agentic-identity-trust"
        "security/security-compliance-auditor"
        "specialized/automation-governance-architect"
      ];
    };
  };
in
{
  governance.controllers = {
    kagamizo = [ "mirazo" ];
    jingzo = [ "mirazo" ];
  };

  # Public's personal secret trades as well as reads, so no swarm holds it:
  # brokerage stays with its owner until Public offers a read-only credential.

  # Every agent is in one team. legal, accounting and governance run once
  # per entity; the rest serve one entity, which holds all their agents.
  governance.teams = {
    legal = {
      purpose = "compliance, filings and documents, one swarm per entity";
      tierCap = "flash";
    };
    accounting = {
      purpose = "books, invoices and tax, one swarm per entity";
      tierCap = "flash";
    };
    governance = {
      purpose = "records, controls and agent oversight, one swarm per entity";
      tierCap = "flash";
    };
    # Discovery (../scout): finds, scores and records the candidates for
    # every role, so no module is bound to one provider. Jingzo's: research.
    research = {
      purpose = "discovery: candidates for every role, scored and kept fresh (scout)";
      serves = "jingzo";
      tierCap = "flash";
    };
    # The project as typed data (../project): epics, decisions, gaps, the
    # handoff. The repo is Kagamizo's, so its coordinators are too.
    pm = {
      purpose = "project management and coordination: epics, decisions, gaps (project)";
      serves = "kagamizo";
      tierCap = "pro";
    };
    # Reviews every other team's changes and proposes none of its own
    # (HANDOFF, epic 14); no agents yet.
    review = {
      purpose = "code review and QA of every change, never its own";
      serves = "kagamizo";
      review = true;
      tierCap = "flash";
    };
  };

  governance.agents = lib.mkMerge [
    (swarm "kagamizo")
    (swarm "jingzo")
    (swarm "mirazo")
    {
      # Read-only work on the repo's own declarations: no grants, and the
      # only change they propose is content (candidates, project data).
      research-jingzo = {
        serves = "jingzo";
        team = "research";
        room = "#research";
        purpose = "Find, score and record candidates for every role (scout gaps, scout score)";
        personas = [
          "research/research-synthesist"
          "product/product-trend-researcher"
        ];
        changeClasses = [ "content" ];
      };
      pm-coordinator = {
        serves = "kagamizo";
        team = "pm";
        room = "#pm";
        purpose = "Keep the epics, decisions and gaps current and say what is next (project status)";
        personas = [
          "project-management/project-management-project-shepherd"
          "project-management/project-management-studio-producer"
        ];
        changeClasses = [ "content" ];
      };
      pm-planner = {
        serves = "kagamizo";
        team = "pm";
        room = "#pm";
        tier = "pro";
        purpose = "Break approved epics into stories and order the work (project next)";
        personas = [ "project-management/project-manager-senior" ];
        changeClasses = [ "content" ];
      };

      legal-jingzo.grants = [
        {
          account = "northwest-jingzo";
          effects = [ "read" ];
          why = "filing status, annual report due dates, documents served";
        }
      ];
      accounting-jingzo.grants = [
        {
          account = "northwest-jingzo";
          effects = [ "read" ];
          why = "Northwest invoices and refunds, for the books";
        }
        {
          account = "mercury-jingzo";
          effects = [ "read" ];
          why = "balances and card spend, for the books";
        }
      ];
      # Reads only: changing the company's record stays with its controller.
      governance-jingzo.grants = [
        {
          account = "northwest-jingzo";
          effects = [ "read" ];
          why = "company records and registered agent services";
        }
        {
          account = "mercury-jingzo";
          effects = [ "read" ];
          why = "what the bank holds and what the cards spend, against their limits";
        }
      ];
    }
  ];
}
