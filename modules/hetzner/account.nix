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

    # The declared host (./host.nix): the one fixed address the write-scoped
    # tokens (Mercury's) are allowed from. Jingzo's, the owner's call
    # (2026-10-24): it exists, and it owns the bank account the host serves.
    held.hetzner = {
      provider = "hetzner";
      plan = "cloud";
      owner = "jingzo";
      status = "active";
      signup = {
        url = "https://accounts.hetzner.com/signUp";
        handle = "jingzo";
        email = "admin@jingzo.org";
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
