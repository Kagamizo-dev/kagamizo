# Yours, in your root vault: the personal secret (made once in Public's
# settings, a Gap) and the account the commands act on.
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.public = {
    defaults.providers = [ "root" ];
    PUBLIC_PERSONAL_SECRET = secret "Public personal secret, made once in Settings (a Gap)" "public-personal-secret";
    PUBLIC_ACCOUNT_ID = secret "The Public account commands act on" "public-account-id" // {
      required = false;
    };
  };
}
