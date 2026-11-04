# What each plan includes, as its provider states it. Only capabilities the
# repo relies on are listed (options.nix closes the set per provider); add one
# there first, then give every plan of that provider a value and a source.
{
  accounts.plans = {
    proton.unlimited = {
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

    cloudflare.free = {
      checked = "2026-10-20";
      capabilities = {
        registrarAtCost = {
          value = true;
          source = "https://developers.cloudflare.com/registrar/";
        };
        # Also confirmed live: `bootstrap plan` lists the account token groups.
        accountTokens = {
          value = true;
          source = "https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/";
        };
        emailRoutingRules = {
          value = 200;
          source = "https://developers.cloudflare.com/email-routing/limits/";
        };
        emailRoutingAddresses = {
          value = 200;
          source = "https://developers.cloudflare.com/email-routing/limits/";
        };
        workersRequestsPerDay = {
          value = 100000;
          source = "https://developers.cloudflare.com/workers/platform/pricing/";
        };
        kvWritesPerDay = {
          value = 1000;
          source = "https://developers.cloudflare.com/kv/platform/limits/";
        };
      };
    };

    github.free-org = {
      checked = "2026-10-20";
      capabilities = {
        privateRepos = {
          value = "unlimited";
          source = "https://docs.github.com/en/get-started/learning-about-github/githubs-plans";
        };
        actionsMinutesPrivate = {
          value = 2000;
          source = "https://docs.github.com/en/get-started/learning-about-github/githubs-plans";
        };
        verifiedDomains = {
          value = true;
          source = "https://docs.github.com/en/organizations/managing-organization-settings/verifying-or-approving-a-domain-for-your-organization";
        };
        # Environments (and their secrets and branch rules) on private repos
        # are paid; public repos get them on every plan.
        environmentsPrivate = {
          value = false;
          source = "https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment";
        };
        # Required reviewers and branch protection on private repos are Team and up.
        protectedBranchesPrivate = {
          value = false;
          source = "https://docs.github.com/en/get-started/learning-about-github/githubs-plans";
        };
      };
    };
  };
}
