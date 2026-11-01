# Capital One: Venture X and a basic card (modules/money credit lines).
{
  accounts = {
    roles.capital-one = [ "credit" ];

    capabilities.capital-one = {
      consumerApi = "flag";
    };

    plans.capital-one.consumer = {
      # annual fees are per card: money.creditLines
      billing = {
        value = "free";
        source = "https://www.capitalone.com/credit-cards/";
      };
      checked = "2026-11-01";
      capabilities = {
        # its developer APIs are for partners
        consumerApi = {
          value = false;
          source = "https://developer.capitalone.com/";
        };
      };
    };

    held.capital-one-mirazo = {
      provider = "capital-one";
      plan = "consumer";
      owner = "mirazo";
      status = "active";
      login = {
        item = "CapitalOne";
        email = "zach@mirazo.org";
      };
    };
  };
}
