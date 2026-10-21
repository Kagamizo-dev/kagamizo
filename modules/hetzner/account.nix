# Hetzner Cloud: the always-on host for chat and code.
# Its capabilities are the closed set every hetzner plan must state, each with
# the page that states it (../accounts).
{
  accounts = {
    roles.hetzner = [ "hosting" ];

    capabilities.hetzner = {
      projects = "limit";
      apiTokens = "flag";
    };

    # Pay as you go: servers are billed hourly, capped monthly.
    plans.hetzner.cloud = {
      checked = "2026-10-20";
      capabilities = {
        projects = {
          value = 20;
          source = "https://docs.hetzner.com/cloud/general/faq/";
        };
        # Per-project API tokens, which hcloud and the OpenTofu provider use.
        apiTokens = {
          value = true;
          source = "https://docs.hetzner.cloud/";
        };
      };
    };

    # The always-on host for chat and code (modules/kagamizo-host).
    held.hetzner = {
      provider = "hetzner";
      plan = "cloud";
      owner = "kagamizo";
      status = "planned";
      signup = {
        url = "https://accounts.hetzner.com/signUp";
        handle = "kagamizo";
        email = "admin@kagamizo.com";
        credential = "password";
        findings = [
          {
            fact = "signup checks identity with a government ID and a selfie (iDenfy)";
            source = "https://docs.hetzner.com/general/security-and-identify/fraud-prevention-faq/";
            checked = "2026-10-20";
          }
          {
            fact = "sign up without a VPN and with a non-free mail domain, or the fraud check may hold the account";
            source = "https://docs.hetzner.com/general/security-and-identify/fraud-prevention-faq/";
            checked = "2026-10-20";
          }
          {
            fact = "the first project API token is created in the Cloud Console; after it, hcloud and OpenTofu do everything";
            source = "https://docs.hetzner.cloud/";
            checked = "2026-10-20";
          }
        ];
      };
    };
  };
}
