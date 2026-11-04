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

    # The agent fleet's models, and the sourcing harness's translations. The
    # key sits in Kagamizo-Agents (secretspec profiles agent and sourcing).
    openrouter = {
      provider = "openrouter";
      plan = "credits";
      owner = "kagamizo";
      status = "active";
    };

    # Marketplace listings and shipping quotes for `sourcing` (parts/sourcing).
    # Planned: their plan pages are unread and their signup pages unrecorded
    # (Gaps in parts/cloudflare/README.md). Search works without either.
    mercadolivre = {
      provider = "mercadolivre";
      plan = "developer";
      owner = "kagamizo";
      status = "planned";
    };
    melhorenvio = {
      provider = "melhorenvio";
      plan = "free";
      owner = "kagamizo";
      status = "planned";
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
