# The agent swarms: legal, accounting and governance, one of each per legal
# identity (you included), so no agent ever works for two of them. Personas are agency-agents'
# (flake input); grants are the only account access an agent gets, and the
# base policies (./cedar.nix) cap them whatever they say.
{ lib, ... }:
let
  swarm = serves: {
    "legal-${serves}" = {
      inherit serves;
      purpose = "Compliance, filings and documents served on ${serves}";
      personas = [
        "support/support-legal-compliance-checker"
        "specialized/legal-document-review"
      ];
    };
    "accounting-${serves}" = {
      inherit serves;
      purpose = "Books, invoices and tax for ${serves}";
      personas = [
        "finance/finance-bookkeeper-controller"
        "finance/finance-tax-strategist"
        "finance/finance-fpa-analyst"
      ];
    };
    "governance-${serves}" = {
      inherit serves;
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
    kagamizo = [ "zachariah" ];
    qsearch = [ "zachariah" ];
  };

  # Public's personal secret trades as well as reads, so no swarm holds it:
  # brokerage stays with its owner until Public offers a read-only credential.

  governance.agents = lib.mkMerge [
    (swarm "kagamizo")
    (swarm "qsearch")
    (swarm "zachariah")
    {
      legal-qsearch.grants = [
        {
          account = "northwest-qsearch";
          effects = [ "read" ];
          why = "filing status, annual report due dates, documents served";
        }
      ];
      accounting-qsearch.grants = [
        {
          account = "northwest-qsearch";
          effects = [ "read" ];
          why = "Northwest invoices and refunds, for the books";
        }
        {
          account = "mercury-qsearch";
          effects = [ "read" ];
          why = "balances and card spend, for the books";
        }
      ];
      # Reads only: changing the company's record stays with its controller.
      governance-qsearch.grants = [
        {
          account = "northwest-qsearch";
          effects = [ "read" ];
          why = "company records and registered agent services";
        }
        {
          account = "mercury-qsearch";
          effects = [ "read" ];
          why = "what the bank holds and what the cards spend, against their limits";
        }
      ];
    }
  ];
}
