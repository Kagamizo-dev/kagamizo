# Public: the brokerage, yours personally (its API is for personal,
# non-commercial use). Its API trades and reads; it moves no money in or out,
# so funding it stays a Gap.
{
  accounts = {
    roles.public = [ "brokerage" ];

    capabilities.public = {
      tradingApi = "flag";
      personalSecrets = "flag";
      transfersApi = "flag";
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
      };
    };

    held.public = {
      provider = "public";
      plan = "individual";
      owner = "zachariah";
      status = "active";
    };
  };
}
