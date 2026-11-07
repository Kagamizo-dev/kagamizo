# Amazon: shopping and Prime.
{
  accounts = {
    roles.amazon = [ "shopping" ];

    capabilities.amazon = {
      consumerApi = "flag";
    };

    plans.amazon.prime = {
      # Prime membership
      billing = {
        value = "subscription";
        source = "https://www.amazon.com/amazonprime";
      };
      checked = "2026-11-01";
      capabilities = {
        # no API for a shopper's own account
        consumerApi = {
          value = false;
          source = "https://developer.amazon.com/";
        };
      };
    };

    # Its login moves onto zach@mirazo.org (Roadmap epic 5).
    held.amazon-mirazo = {
      provider = "amazon";
      plan = "prime";
      owner = "mirazo";
      status = "active";
      payment.ownerCard = {
        issuer = "personal";
        replacedBy = "amazon";
      };
      login = {
        item = "amazon.com";
        email = "zach@mirazo.org";
      };
    };
  };
}
