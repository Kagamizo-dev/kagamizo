# Credit One Bank: one card (modules/money credit lines).
{
  accounts = {
    roles.credit-one = [ "credit" ];

    capabilities.credit-one = {
      consumerApi = "flag";
    };

    plans.credit-one.consumer = {
      # annual fees are per card: money.creditLines
      billing = {
        value = "free";
        source = "https://www.creditonebank.com/credit-cards";
      };
      checked = "2026-11-01";
      capabilities = {
        # no consumer API
        consumerApi = {
          value = false;
          source = "https://www.creditonebank.com/";
        };
      };
    };

    # Its login moves onto finance@mirazo.org (Roadmap epic 5); identity-audit shows it
    # until it has.
    held.credit-one-mirazo = {
      provider = "credit-one";
      plan = "consumer";
      owner = "mirazo";
      status = "active";
      login = {
        item = "creditonebank.com";
        email = "finance@mirazo.org";
      };
    };
  };
}
