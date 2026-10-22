# Mercury: Kagamizo's bank, and the only way anything is paid for. Every
# vendor gets its own virtual card with a spend limit (./cards.nix); no
# long-lived card is ever handed out. Moving money still needs a tap in the
# Mercury app, the one approval that stays manual by design.
{
  accounts = {
    roles.mercury = [ "bank" ];

    capabilities.mercury = {
      apiTokens = "flag";
      virtualCards = "flag";
      cardSpendLimits = "flag";
      cardReveal = "flag";
      paymentApprovals = "flag";
      writeTokensNeedIpAllowlist = "flag";
      oauthSessions = "flag";
      passkeys = "flag";
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
        # "Continue with passkey" bypasses the password and the 2FA code;
        # adding one needs an authenticator-app 2FA set up first.
        passkeys = {
          value = true;
          source = "https://support.mercury.com/hc/en-us/articles/48188889174036";
        };
      };
    };

    # Personal banking: the same sign-in, OAuth and CLI, but Mercury states
    # its API, tokens and cards for business accounts only, so nothing here
    # relies on them for a personal one.
    plans.mercury.personal = {
      checked = "2026-10-22";
      capabilities = {
        apiTokens = {
          value = false;
          source = "https://mercury.com/api";
        };
        virtualCards = {
          value = false;
          source = "https://mercury.com/personal-banking";
        };
        cardSpendLimits = {
          value = false;
          source = "https://mercury.com/personal-banking";
        };
        cardReveal = {
          value = false;
          source = "https://github.com/MercuryTechnologies/mercury-go";
        };
        writeTokensNeedIpAllowlist = {
          value = true;
          source = "https://docs.mercury.com/docs/getting-started";
        };
        # Signed in on 2026-10-22: the CLI's OAuth reads its accounts.
        oauthSessions = {
          value = true;
          source = "https://github.com/MercuryTechnologies/mercury-cli";
        };
        paymentApprovals = {
          value = true;
          source = "https://mercury.com/personal-banking";
        };
        # Mercury's passkey page is about business sign-in; personal
        # banking's is unconfirmed, so it is not relied on.
        passkeys = {
          value = false;
          source = "https://support.mercury.com/hc/en-us/articles/48188889174036";
        };
      };
    };

    # Kagamizo's own business account. Until it is open, nothing is signed in
    # with a personal account: the cards are Kagamizo's spending, and the
    # API, OAuth and agent cards are documented for business customers.
    held = {
      mercury = {
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

      # Jingzo's (QSearch LLC's) account, already open and not signed in yet:
      # its session goes to Jingzo's sessions vault, and its swarms read it
      # (modules/governance).
      mercury-jingzo = {
        provider = "mercury";
        plan = "standard";
        owner = "jingzo";
        status = "active";
        # Its own Mercury user, not the person's: a company's bank login says
        # whose it is.
        login = {
          item = "Mercury - Jingzo LLC";
          email = "finance@jingzo.org";
        };
      };

      # Yours personally: Mercury's personal banking, signed in with its
      # session in your own sessions vault, where no company's swarm reaches.
      mercury-mirazo = {
        provider = "mercury";
        plan = "personal";
        owner = "mirazo";
        status = "active";
        login = {
          item = "Mercury";
          email = "finance@mirazo.org";
        };
      };
    };
  };
}
