# The agent swarms: legal, accounting and governance, one of each per legal
# identity (you included), so no agent ever works for two of them. Personas are agency-agents'
# (flake input); the cards an agent holds (wallet.cards.<c>.holders) are the
# only account access it gets, and the
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
    kagamizo = [ "mirazo" ];
    jingzo = [ "mirazo" ];
  };

  # Public's personal secret trades as well as reads, so no swarm holds it:
  # the secret stays in the owner's root vault. The accounting swarm's hold
  # on the API card below is Cedar's read permit for the nightly ledger
  # (modules/money, money.ledger, off until the owner allows it); the
  # secret still only reaches it when Public offers a read-only credential
  # (a Gap).

  governance.agents = lib.mkMerge [
    (swarm "kagamizo")
    (swarm "jingzo")
    (swarm "mirazo")
  ];

  # What the swarms may use is what they hold (wallet step 3, 2026-11-09):
  # each holder below is the agent's grant on the card's account.
  wallet.cards = {
    login-northwest-jingzo.holders = {
      legal-jingzo = {
        effects = [ "read" ];
        why = "filing status, annual report due dates, documents served";
      };
      accounting-jingzo = {
        effects = [ "read" ];
        why = "Northwest invoices and refunds, for the books";
      };
      # Reads only: changing the company's record stays with its controller.
      governance-jingzo = {
        effects = [ "read" ];
        why = "company records and registered agent services";
      };
    };
    # The owner's decision, 2026-11-06: accounting manages the OpenRouter
    # account's keys and budgets with the management key; each change is
    # first code (the account-limit lifecycle, modules/agents).
    login-openrouter.holders.accounting-jingzo = {
      effects = [
        "read"
        "write"
      ];
      why = "every key's cap and the workspace budgets, set from openrouter.keys after review";
    };
    mercury-jingzo.holders = {
      accounting-jingzo = {
        effects = [ "read" ];
        why = "balances and card spend, for the books";
      };
      governance-jingzo = {
        effects = [ "read" ];
        why = "what the bank holds and what the cards spend, against their limits";
      };
    };
    public-api-mirazo.holders.accounting-mirazo = {
      effects = [ "read" ];
      why = "the brokerage's portfolio, history, orders and tax lots, for the nightly ledger (money.ledger)";
    };
  };
}
