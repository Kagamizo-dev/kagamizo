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

    # Kagamizo's organization, signed up with dev@kagamizo.com.
    github-kagamizo = {
      provider = "github";
      plan = "free-org";
      owner = "kagamizo";
      status = "planned";
    };
  };
}
