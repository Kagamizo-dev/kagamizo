# The accounts that exist or are planned, each on a declared plan.
{
  accounts.held = {
    # Mail for every declared domain, Proton Pass for every secret.
    proton = {
      provider = "proton";
      plan = "unlimited";
      owner = "zachariah";
      status = "active";
    };

    cloudflare = {
      provider = "cloudflare";
      plan = "free";
      owner = "zachariah";
      status = "active";
    };

    # The always-on host for chat and code (devices/kagamizo-host).
    hetzner = {
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

    # Models for chat and code, default deepseek/deepseek-v4-flash.
    openrouter = {
      provider = "openrouter";
      plan = "pay-as-you-go";
      owner = "kagamizo";
      status = "planned";
      signup = {
        url = "https://openrouter.ai/sign-up";
        handle = "kagamizo";
        email = "dev@kagamizo.com";
        credential = "password";
        findings = [
          {
            fact = "OpenRouter has no official CLI; its management API creates, limits and disables keys";
            source = "https://openrouter.ai/docs/guides/overview/auth/management-api-keys";
            checked = "2026-10-20";
          }
          {
            fact = "the first management key and the first credit top-up are made in the web dashboard";
            source = "https://openrouter.ai/docs/guides/overview/auth/management-api-keys";
            checked = "2026-10-20";
          }
        ];
      };
    };

    # Kagamizo's organization, contact dev@kagamizo.com, created from your
    # own GitHub account (it owns the org; the repo moves over from it).
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
  };
}
