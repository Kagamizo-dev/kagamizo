# Kagamizo's organization and the repos in it.
{
  github = {
    account = "github-kagamizo";
    org = "kagamizo-dev";
    approvalsIssue = 2;
    verifiedDomains."kagamizo.com" = null;

    repos.nix-images = {
      from = "presentatou";
      # Public: no secrets live in git, and on GitHub Free environments and
      # unlimited Actions minutes need it.
      visibility = "public";
      # PR plans: the read-only view.
      secrets.PROTON_PASS_AGENT_TOKEN = "PROTON_PASS_AGENT_TOKEN";
      # Applies from master only.
      environments.cloudflare = {
        branches = [ "master" ];
        secrets.PROTON_PASS_CI_TOKEN = "PROTON_PASS_CI_TOKEN";
      };
      variables.INFRA_ENABLED = "true";
    };
  };
}
