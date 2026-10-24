# The three GitHub organizations, one per identity, and the plan they are on.
# Its capabilities are the closed set every github plan must state, each with
# the page that states it (../accounts).
let
  orgSignup = owner: email: {
    provider = "github";
    plan = "free-org";
    inherit owner;
    status = "planned";
    signup = {
      url = "https://github.com/account/organizations/new?plan=free";
      handle = "${owner}-dev";
      inherit email;
      credential = "parent";
      parent = "presentatou";
      findings = [
        {
          fact = "whether the handle is free is unchecked: the session's network refuses unauthenticated api.github.com";
          source = "https://docs.github.com/en/rest/users/users#get-a-user";
          checked = "2026-10-22";
        }
        {
          fact = "organizations can only be created in the web UI on github.com (no POST /orgs)";
          source = "https://github.com/github/rest-api-description";
          checked = "2026-10-20";
        }
      ];
    };
  };
in
{
  accounts = {
    roles.github = [ "code" ];

    capabilities.github = {
      privateRepos = "limit";
      actionsMinutesPrivate = "limit";
      verifiedDomains = "flag";
      protectedBranchesPrivate = "flag";
      environmentsPrivate = "flag";
    };

    plans.github.free-org = {
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

    # Kagamizo's organization, contact dev@kagamizo.com, created from your
    # own GitHub account (it owns the org; the repo moves over from it).
    held = {
      github-kagamizo = {
        provider = "github";
        plan = "free-org";
        owner = "kagamizo";
        status = "active";
        signup = {
          url = "https://github.com/account/organizations/new?plan=free";
          handle = "kagamizo-dev";
          email = "dev@kagamizo.com";
          credential = "parent";
          parent = "presentatou";
          findings = [
            {
              fact = "the name kagamizo is taken by another account (id 188455801)";
              source = "GitHub user search API";
              checked = "2026-10-20";
            }
            {
              fact = "organizations can only be created in the web UI on github.com (no POST /orgs)";
              source = "https://github.com/github/rest-api-description";
              checked = "2026-10-20";
            }
            {
              fact = "one free personal account per person, so the org is created from the existing one rather than a new dev@ user";
              source = "https://docs.github.com/en/site-policy/github-terms/github-terms-of-service";
              checked = "2026-10-20";
            }
            {
              fact = "the org can verify kagamizo.com by API (addVerifiableDomain, then a DNS TXT record)";
              source = "https://docs.github.com/en/organizations/managing-organization-settings/verifying-or-approving-a-domain-for-your-organization";
              checked = "2026-10-20";
            }
          ];
        };
      };

      # Jingzo's and Mirazo's organizations, created the same way, from your
      # own GitHub account: research and trading code under Jingzo, your
      # papers and personal projects under Mirazo.
      github-jingzo = orgSignup "jingzo" "dev@jingzo.org";
      github-mirazo = orgSignup "mirazo" "zach@mirazo.org";
    };
  };
}
