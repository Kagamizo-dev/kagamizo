# The token every `cards` command runs with: made once in Mercury's dashboard
# (a Gap), scoped to cards, kept in Kagamizo's vault.
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.mercury = {
    defaults.providers = [ "kagamizo" ];
    MERCURY_API_KEY = secret "Mercury API token for cards, made once in the dashboard (a Gap)" "mercury-api-token";
  };
}
