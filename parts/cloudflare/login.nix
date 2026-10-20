# The root credential is a short-lived OAuth session, never a stored token:
#
#   cloudflare-login
#
# prints a link and a one-time code. Open the link on your phone, sign in to
# Cloudflare (your 2FA), check the code and the scopes below, and approve.
# The session then mints the scoped tokens in tokens.nix; tokens minted over
# OAuth can never exceed the scopes approved here, so this list is the ceiling
# for every token in the account.
{
  config,
  lib,
  inputs,
  ...
}:
let
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  # Each scope must be one cf's OAuth client is registered for (catalog/cf.json).
  scopes = map (
    s: if cli.Scope.check s then s else throw "cloudflare.login.scopes: `${s}` is not a cf OAuth scope"
  ) config.cloudflare.login.scopes;
in
{
  options.cloudflare.login.scopes = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    description = "OAuth scopes requested by `cloudflare-login`, checked against catalog/cf.json.";
  };

  config = {
    cloudflare.login.scopes = [
      # The session itself.
      "offline"
      "user:read"
      "account:read"
      "zone:read"
      # Minting the account-owned tokens in tokens.nix.
      "account_api_tokens:create"
      # Everything those tokens may hold (tokens.nix), read and write.
      "zone.read"
      "dns.read"
      "dns.write"
      "zone-settings.read"
      "zone-settings.write"
      "ssl-and-certificates.read"
      "ssl-and-certificates.write"
      "cache.purge"
      "workers-routes.read"
      "workers-routes.write"
      "email-routing-rule.read"
      "email-routing-rule.write"
      "account-settings.read"
      "workers-scripts.read"
      "workers-scripts.write"
      "pages:read"
      "pages:write"
      "workers-kv-storage.read"
      "workers-kv-storage.write"
      "workers-r2.read"
      "workers-r2.write"
      "d1.read"
      "d1.write"
      "argotunnel.read"
      "argotunnel.write"
      "access.read"
      "access.write"
      # Buying domains and reading their state.
      "registrar:read"
      "registrar:write"
      "registrar-domains.read"
      "registrar-domains.admin"
    ];

    perSystem =
      { pkgs, config, ... }:
      {
        packages.cloudflare-login = pkgs.writeShellApplication {
          name = "cloudflare-login";
          runtimeInputs = [ config.packages.cf ];
          text = ''
            # The session file lives in ~/.config/cloudflare and dies with the
            # container.
            exec ${
              cli.cf "auth login" {
                browser = false;
                device = true;
                force = true;
                inherit scopes;
              }
            }
          '';
        };
      };
  };
}
