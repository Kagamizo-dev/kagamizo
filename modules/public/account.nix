# Public: the brokerages, yours and Jingzo's (its API is for personal,
# non-commercial use). Its API trades and reads; it moves no money in or out,
# so funding it stays a Gap.
{
  accounts = {
    roles.public = [ "brokerage" ];

    capabilities.public = {
      tradingApi = "flag";
      personalSecrets = "flag";
      transfersApi = "flag";
      historyApi = "flag";
      scopedSecrets = "flag";
      documentsApi = "flag";
    };

    plans.public.individual = {
      checked = "2026-10-20";
      capabilities = {
        # Accounts, portfolio, market data, preflight and orders.
        tradingApi = {
          value = true;
          source = "https://public.com/api/docs";
        };
        # A personal secret from Settings mints short-lived access tokens;
        # the CLI takes it as PUBLIC_PERSONAL_SECRET.
        personalSecrets = {
          value = true;
          source = "https://public.com/api/docs/templates/publicdotcom-cli";
        };
        # Deposits and withdrawals are not part of the API.
        transfersApi = {
          value = false;
          source = "https://public.com/api/docs";
        };
        # History lists trades, deposits, withdrawals, dividends, interest
        # and fees: money movement is readable, not startable.
        historyApi = {
          value = true;
          source = "https://public.com/api/docs";
        };
        # An access token is minted from the secret with only a validity
        # (default 15 minutes); no scope narrows it, so every token can trade.
        scopedSecrets = {
          value = false;
          source = "https://public.com/api/docs/templates/get-access-token";
        };
        # No statements, confirmations or tax forms (1099) in the API; tax
        # lots (unrealized, also as CSV) are the closest.
        documentsApi = {
          value = false;
          source = "https://public.com/api/docs";
        };
      };
    };

    # A business account of a single-owner LLC. Its API is not relied on
    # until Public says its API terms (personal, non-commercial) cover one.
    plans.public.business = {
      checked = "2026-10-22";
      capabilities = {
        tradingApi = {
          value = false;
          source = "https://public.com/api/docs";
        };
        personalSecrets = {
          value = false;
          source = "https://public.com/api/docs";
        };
        transfersApi = {
          value = false;
          source = "https://public.com/api/docs";
        };
        historyApi = {
          value = false;
          source = "https://public.com/api/docs";
        };
        scopedSecrets = {
          value = false;
          source = "https://public.com/api/docs/templates/get-access-token";
        };
        documentsApi = {
          value = false;
          source = "https://public.com/api/docs";
        };
      };
    };

    # Yours: the portfolio and retirement accounts, the one `brokerage` and
    # `trade` act on.
    held.public-mirazo = {
      provider = "public";
      plan = "individual";
      owner = "mirazo";
      status = "active";
      login = {
        item = "Public";
        email = "finance@mirazo.org";
      };
    };

    # Jingzo's research and trading account, a business account of QSearch
    # LLC. Nothing acts on it yet: Public's API terms are for personal use,
    # and nothing found says they cover a business account (HANDOFF.md).
    held.public-jingzo = {
      provider = "public";
      plan = "business";
      owner = "jingzo";
      status = "active";
      login = {
        item = "public.com";
        email = "finance@jingzo.org";
      };
    };
  };
}
