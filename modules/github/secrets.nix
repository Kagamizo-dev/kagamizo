# The organization's token, stored by `github-bootstrap` in Kagamizo's vault.
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.github = {
    defaults.providers = [ "kagamizo" ];
    GITHUB_TOKEN = secret {
      kind = "api-token";
      issuer = "automation:github-bootstrap";
      needs = [ "approve-sign-in" ];
      description = "Fine-grained token administering the kagamizo GitHub organization";
      item = "github-token";
    };
  };
}
