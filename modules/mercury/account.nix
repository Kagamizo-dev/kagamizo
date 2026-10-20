# Mercury: Kagamizo's bank, and the only way anything is paid for. Every
# vendor gets its own virtual card with a spend limit (./cards.nix); no
# long-lived card is ever handed out. Moving money still needs a tap in the
# Mercury app, the one approval that stays manual by design.
{
  accounts = {
    capabilities.mercury = {
      apiTokens = "flag";
      virtualCards = "flag";
      cardSpendLimits = "flag";
      cardReveal = "flag";
      paymentApprovals = "flag";
    };

    plans.mercury.standard = {
      checked = "2026-10-20";
      capabilities = {
        # Scoped tokens with fine-grained permissions; the CLI reads one from
        # MERCURY_API_KEY.
        apiTokens = {
          value = true;
          source = "https://mercury.com/api";
        };
        # `mercury cards create` issues a virtual card; `update` changes its
        # limit, `freeze`/`unfreeze`/`cancel` end it.
        virtualCards = {
          value = true;
          source = "https://github.com/MercuryTechnologies/mercury-cli";
        };
        cardSpendLimits = {
          value = true;
          source = "https://github.com/MercuryTechnologies/mercury-cli";
        };
        # Full card details, for agentic cards only.
        cardReveal = {
          value = true;
          source = "https://github.com/MercuryTechnologies/mercury-go";
        };
        # Money movement asks for a tap in the Mercury app.
        paymentApprovals = {
          value = true;
          source = "https://mercury.com/api";
        };
      };
    };

    held.mercury = {
      provider = "mercury";
      plan = "standard";
      owner = "kagamizo";
      status = "active";
    };
  };
}
