# Interactive Brokers: QSearch LLC's accounts (two logins in its vault).
{
  accounts = {
    roles.ibkr = [ "brokerage" ];

    capabilities.ibkr = {
      tradingApi = "flag";
    };

    plans.ibkr.pro = {
      # commissions per trade
      billing = {
        value = "usage";
        source = "https://www.interactivebrokers.com/en/pricing/commissions-home.php";
      };
      checked = "2026-11-01";
      capabilities = {
        # TWS and Client Portal APIs
        tradingApi = {
          value = true;
          source = "https://www.interactivebrokers.com/campus/ibkr-api-page/";
        };
      };
    };

    # Its login moves onto finance@jingzo.org (Roadmap epic 5); identity-audit shows it
    # until it has.
    held.ibkr-jingzo = {
      provider = "ibkr";
      plan = "pro";
      owner = "jingzo";
      status = "active";
      payment.fromBalance = "commissions and fees, from the brokerage's own cash";
      login = {
        item = "IBKR";
        email = "finance@jingzo.org";
      };
    };
  };
}
