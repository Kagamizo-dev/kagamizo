# The Cloudflare account: its non-secret facts, the free plan it is on and
# that plan's capabilities (../accounts). Zone IDs live with each domain
# under identity.domains.
{
  cloudflare = {
    accountId = "73f11fa58ac09529a4fb40284b8ce236";

    # Every minted token stops working on this date. Bump it and run
    # `bootstrap apply` to extend them all in place.
    tokenExpiry = "2027-01-15T00:00:00Z";

    # Cloudflare has no spending cap of its own (budget alerts only email), so
    # this one is enforced here: the declared registrations must fit it, and
    # `registrar register` refuses a purchase that would exceed it this month.
    # About three domains a month at current prices.
    monthlyBudgetUsd = 40;
  };

  accounts = {
    roles.cloudflare = [ "registrar" ];

    capabilities.cloudflare = {
      registrarAtCost = "flag";
      accountTokens = "flag";
      emailRoutingRules = "limit";
      emailRoutingAddresses = "limit";
      workersRequestsPerDay = "limit";
      kvWritesPerDay = "limit";
      zeroTrustSeats = "limit";
    };

    plans.cloudflare.free = {
      checked = "2026-10-20";
      capabilities = {
        registrarAtCost = {
          value = true;
          source = "https://developers.cloudflare.com/registrar/";
        };
        # Also confirmed live: `bootstrap plan` lists the account token groups.
        accountTokens = {
          value = true;
          source = "https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/";
        };
        emailRoutingRules = {
          value = 200;
          source = "https://developers.cloudflare.com/email-routing/limits/";
        };
        emailRoutingAddresses = {
          value = 200;
          source = "https://developers.cloudflare.com/email-routing/limits/";
        };
        workersRequestsPerDay = {
          value = 100000;
          source = "https://developers.cloudflare.com/workers/platform/pricing/";
        };
        kvWritesPerDay = {
          value = 1000;
          source = "https://developers.cloudflare.com/kv/platform/limits/";
        };
        # Access users on the free Zero Trust plan.
        zeroTrustSeats = {
          value = 50;
          source = "https://blog.cloudflare.com/teams-plans";
        };
      };
    };

    held.cloudflare = {
      provider = "cloudflare";
      plan = "free";
      owner = "mirazo";
      status = "active";
      login = {
        item = "Cloudflare";
        email = "zach@mirazo.org";
      };
    };
  };
}
