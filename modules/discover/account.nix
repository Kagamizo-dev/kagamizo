# Discover: one card, now Capital One's (modules/money credit lines).
{
  accounts = {
    roles.discover = [ "credit" ];

    capabilities.discover = {
      consumerApi = "flag";
    };

    plans.discover.consumer = {
      # no annual fee
      billing = {
        value = "free";
        source = "https://www.discover.com/credit-cards/";
      };
      checked = "2026-11-01";
      capabilities = {
        # no consumer API
        consumerApi = {
          value = false;
          source = "https://www.discover.com/";
        };
      };
    };

    # Its login moves onto finance@mirazo.org (Roadmap epic 5); identity-audit shows it
    # until it has.
    held.discover-mirazo = {
      provider = "discover";
      plan = "consumer";
      owner = "mirazo";
      status = "active";
      login = {
        item = "card.discover.com";
        email = "finance@mirazo.org";
      };
    };
  };
}
