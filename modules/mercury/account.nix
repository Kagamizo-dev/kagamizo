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
      writeTokensNeedIpAllowlist = "flag";
      oauthSessions = "flag";
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
        # Read-write and custom write tokens only work from allowlisted IPs,
        # which is why the repo uses no dashboard tokens at all (below).
        writeTokensNeedIpAllowlist = {
          value = true;
          source = "https://docs.mercury.com/docs/getting-started";
        };
        # The official CLI signs in with OAuth (offline_access, read, write)
        # and refreshes the session itself: `mercury-session login`.
        oauthSessions = {
          value = true;
          source = "https://github.com/MercuryTechnologies/mercury-cli";
        };
        # Money movement asks for a tap in the Mercury app.
        paymentApprovals = {
          value = true;
          source = "https://mercury.com/api";
        };
      };
    };

    # Kagamizo's own business account. Until it is open, nothing is signed in
    # with a personal account: the cards are Kagamizo's spending, and the
    # API, OAuth and agent cards are documented for business customers.
    held.mercury = {
      provider = "mercury";
      plan = "standard";
      owner = "kagamizo";
      status = "planned";
      signup = {
        url = "https://mercury.com/";
        handle = "kagamizo";
        email = "billing@kagamizo.com";
        credential = "password";
        findings = [
          {
            fact = "the application asks for the EIN (the IRS confirmation letter), the articles of organization and each 25%+ owner with a government ID";
            source = "https://www.zenind.com/help/post/how-to-open-a-mercury-business-account-for-your-llc-a-practical-founder-guide";
            checked = "2026-10-21";
          }
          {
            fact = "the legal name, EIN record, owner names and addresses must match exactly; a registered agent's address may not be accepted as the business address";
            source = "https://www.zenind.com/help/post/how-to-open-a-mercury-business-account-for-your-llc-a-practical-founder-guide";
            checked = "2026-10-21";
          }
          {
            fact = "after approval, mercury-session login signs the repo in; no dashboard token is made";
            source = "https://github.com/MercuryTechnologies/mercury-cli";
            checked = "2026-10-20";
          }
        ];
      };
    };

    # QSearch's account, already open. Declared so nothing reaches for it
    # without a demand; it has no cards or session here yet.
    held.mercury-qsearch = {
      provider = "mercury";
      plan = "standard";
      owner = "qsearch";
      status = "active";
    };
  };
}
