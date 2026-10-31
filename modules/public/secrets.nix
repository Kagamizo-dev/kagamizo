# Yours, in your root vault: the personal secret (made once in Public's
# settings, a Gap) and the account the commands act on.
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.public = {
    defaults.providers = [ "root" ];
    PUBLIC_PERSONAL_SECRET = secret {
      kind = "api-token";
      issuer = "human:console-credential";
      description = "Public personal secret, made once in Settings (a Gap)";
      item = "public-personal-secret";
    };
    PUBLIC_ACCOUNT_ID =
      secret {
        kind = "identifier";
        issuer = "human:console-credential";
        description = "The Public account commands act on";
        item = "public-account-id";
      }
      // {
        required = false;
      };
  };
}
