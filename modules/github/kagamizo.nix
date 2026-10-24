# Kagamizo's organization and the repos in it.
let
  # Public: no secrets live in git, and on GitHub Free environments and
  # unlimited Actions minutes need it.
  visibility = "public";
in
{
  github = {
    account = "github-kagamizo";
    org = "kagamizo-dev";
    verifiedDomains."kagamizo.com" = "b80fee20e0";

    # Everything: images, infrastructure, identity, accounts. Seeded from
    # nix-images' history, with one branch, main.
    repos.kagamizo = {
      seed = true;
      inherit visibility;
      # PR plans: the read-only view.
      secrets.PROTON_PASS_AGENT_TOKEN = "PROTON_PASS_AGENT_TOKEN";
      # Applies from main only.
      environments.cloudflare = {
        branches = [ "main" ];
        secrets.PROTON_PASS_CI_TOKEN = "PROTON_PASS_CI_TOKEN";
      };
      variables.INFRA_ENABLED = "true";
    };

    # Superseded by kagamizo; kept read-only for its history and releases.
    repos.nix-images = {
      from = "presentatou";
      inherit visibility;
      archived = true;
    };
  };
}
