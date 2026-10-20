# Two Mercury tokens, by what they may do, both made once in Mercury's
# dashboard (a Gap) and kept in Kagamizo's vault:
#
#   mercury        read-only: balances, transactions, card states. Mercury
#                  needs no IP allowlist for it, so it works anywhere.
#   mercury-cards  card writes (issue, re-limit, freeze, cancel, reveal).
#                  Mercury only accepts write tokens from allowlisted IPs,
#                  so it is bound to the host's static address and card
#                  changes run there.
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles = {
    mercury = {
      defaults.providers = [ "kagamizo" ];
      MERCURY_API_KEY = secret "Mercury read-only API token (no IP allowlist), made once in the dashboard" "mercury-api-token-read";
    };
    mercury-cards = {
      defaults.providers = [ "kagamizo" ];
      MERCURY_API_KEY =
        secret "Mercury card-write API token, allowlisted to the host's IP, made once in the dashboard" "mercury-api-token-cards"
        // {
          required = false;
        };
    };
  };
}
