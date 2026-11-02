# Yours, in your root vault: the personal secret (made once in Public's
# settings, a Gap) and the account the commands act on.
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.public = {
    defaults.providers = [ "root" ];
    # The owner's API credential item (Mirazo-Root/Public), its Secret field:
    # Public mints short-lived access tokens from it.
    PUBLIC_PERSONAL_SECRET = secret {
      kind = "api-token";
      issuer = "human:console-credential";
      description = "Public personal secret, made once in Settings (a Gap)";
      item = "Public";
      template = "api-credential";
      field = "Secret";
    };
    PUBLIC_ACCOUNT_ID =
      secret {
        kind = "identifier";
        # Read from Public's own `accounts list` (the one BROKERAGE account)
        # when absent; never typed by hand.
        issuer = "automation:brokerage";
        description = "The Public account commands act on";
        item = "public-account-id";
      }
      // {
        required = false;
      };
  };
}
