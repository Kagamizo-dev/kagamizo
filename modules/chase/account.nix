# Chase: personal checking (closing, modules/migration) and two credit cards (modules/money credit lines).
{
  accounts = {
    roles.chase = [ "bank" ];

    capabilities.chase = {
      consumerApi = "flag";
      statementsOnline = "flag";
    };

    plans.chase.personal = {
      # fees waived on the plan held
      billing = {
        value = "free";
        source = "https://www.chase.com/personal/checking";
      };
      checked = "2026-11-01";
      capabilities = {
        # data reaches apps only through paid aggregator agreements
        consumerApi = {
          value = false;
          source = "https://www.chase.com/digital/data-sharing";
        };
        # PDF statements, up to seven years
        statementsOnline = {
          value = true;
          source = "https://www.chase.com/digital/customer-service/helpful-tips/online-banking/statements";
        };
      };
    };

    # Kept for its two cards; its checking account closes
    # (migration.sources.chase-mirazo, product checking). Its login item is
    # not in Proton Pass yet (identity-audit lists it).
    held.chase-mirazo = {
      provider = "chase";
      plan = "personal";
      owner = "mirazo";
      status = "active";
      login = {
        item = "Chase";
        email = "finance@mirazo.org";
      };
    };
  };
}
