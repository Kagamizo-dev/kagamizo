# Proton: mail for every declared domain, Pass for every secret.
# Its capabilities are the closed set every proton plan must state, each with
# the page that states it (../accounts).
{
  accounts = {
    roles.proton = [
      "mail"
      "passwords"
    ];

    capabilities.proton = {
      customDomains = "limit";
      addresses = "limit";
      bridge = "flag";
      passAccessTokens = "flag";
    };

    plans.proton.unlimited = {
      checked = "2026-10-20";
      capabilities = {
        customDomains = {
          value = 3;
          source = "https://proton.me/news/proton-unlimited-plan";
        };
        addresses = {
          value = 15;
          source = "https://proton.me/news/proton-unlimited-plan";
        };
        # Bridge serves paid accounts only.
        bridge = {
          value = true;
          source = "https://proton.me/support/protonmail-bridge-install";
        };
        # Personal access and agent tokens, which pass-cli and secretspec use.
        passAccessTokens = {
          value = true;
          source = "https://proton.me/support/pass-access-tokens";
        };
      };
    };

    # Mail for every declared domain, Proton Pass for every secret.
    held.proton = {
      provider = "proton";
      plan = "unlimited";
      owner = "mirazo";
      status = "active";
      # Proton signs in with any address of the account, the domain's too.
      login = {
        item = "Proton";
        email = "zach@mirazo.org";
      };
    };
  };
}
