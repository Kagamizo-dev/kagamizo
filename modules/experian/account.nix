# Experian: your consumer credit file, an account you already hold. The
# bureaus offer no API for your own file (theirs serve businesses with a
# permissible purpose under the FCRA), so this is a login, its alerts and
# its freeze, all on Experian's site. Alerts go to automations@mirazo.org.
{
  accounts = {
    roles.experian = [ "credit" ];

    capabilities.experian = {
      consumerApi = "flag";
      creditAlerts = "flag";
      onlineFreeze = "flag";
      threeBureauMonitoring = "flag";
    };

    plans.experian.free = {
      checked = "2026-10-21";
      capabilities = {
        # Bureau APIs are for approved businesses, not a person's own file.
        consumerApi = {
          value = false;
          source = "https://developer.experian.com/";
        };
        # New inquiries, new accounts, changed personal details: by email.
        creditAlerts = {
          value = true;
          source = "https://www.experian.com/credit/credit-monitoring/";
        };
        # Freeze and thaw online with the free account; each change is alerted.
        onlineFreeze = {
          value = true;
          source = "https://www.experian.com/help/credit-freeze/";
        };
        # Experian's file only; all three bureaus are a paid tier.
        threeBureauMonitoring = {
          value = false;
          source = "https://www.experian.com/credit/credit-monitoring/";
        };
      };
    };

    held.experian = {
      provider = "experian";
      plan = "free";
      owner = "zachariah";
      status = "active";
      # The login as it is to be, with its email moved to
      # automations@mirazo.org. Its item already exists in Zachariah-Root,
      # titled "Experian" (made by hand before this repo), so `signup
      # prepare` is not run for it: that would make a second one.
      signup = {
        url = "https://www.experian.com/login";
        handle = "zachariah";
        email = "automations@mirazo.org";
        credential = "password";
        findings = [
          {
            fact = "a credit freeze is free and managed online with the free account; freezes are per bureau";
            source = "https://www.experian.com/help/credit-freeze/";
            checked = "2026-10-21";
          }
        ];
      };
    };
  };
}
