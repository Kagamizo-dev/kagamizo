# DJI: the drone's account (flight logs, DJI Fly).
{
  accounts = {
    roles.dji = [ "device" ];

    capabilities.dji = {
      consumerApi = "flag";
    };

    plans.dji.free = {
      # free account
      billing = {
        value = "free";
        source = "https://www.dji.com/";
      };
      checked = "2026-11-01";
      capabilities = {
        # its SDKs drive aircraft, not the account
        consumerApi = {
          value = false;
          source = "https://developer.dji.com/";
        };
      };
    };

    # Its login moves onto zach@mirazo.org (Roadmap epic 5); identity-audit shows it
    # until it has.
    held.dji-mirazo = {
      provider = "dji";
      plan = "free";
      owner = "mirazo";
      status = "active";
      login = {
        item = "account.dji.com";
        email = "zach@mirazo.org";
      };
    };
  };
}
