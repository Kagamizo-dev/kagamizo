# The organization's token, stored by `github-bootstrap` in Kagamizo's vault.
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.github = {
    defaults.providers = [ "kagamizo" ];
    GITHUB_TOKEN = secret "Fine-grained token administering the kagamizo GitHub organization" "github-token";
  };
}
