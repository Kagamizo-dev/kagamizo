# PayPal: a personal account.
{
  accounts = {
    roles.paypal = [ "payments" ];

    capabilities.paypal = {
      consumerApi = "flag";
    };

    plans.paypal.personal = {
      # free for personal payments funded by a bank
      billing = {
        value = "free";
        source = "https://www.paypal.com/us/webapps/mpp/paypal-fees";
      };
      checked = "2026-11-01";
      capabilities = {
        # its REST APIs are for merchants
        consumerApi = {
          value = false;
          source = "https://developer.paypal.com/";
        };
      };
    };

    # Its login moves onto finance@mirazo.org (Roadmap epic 5); identity-audit shows it
    # until it has.
    held.paypal-mirazo = {
      provider = "paypal";
      plan = "personal";
      owner = "mirazo";
      status = "active";
      login = {
        item = "paypal.com";
        email = "finance@mirazo.org";
      };
    };
  };
}
