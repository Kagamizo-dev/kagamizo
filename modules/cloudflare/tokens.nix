# Cloudflare API token profiles, minted by `bootstrap` as account-owned tokens.
# Each profile is a view: the exact set of things whoever holds it can do.
# Names are permission group names as the API lists them; `bootstrap plan`
# fails, naming it, on one Cloudflare does not offer account tokens.
#
# Deliberately absent everywhere: Billing, API Tokens, Account Settings Write,
# Memberships, Zone Write (which can delete the zone) and Registrar. Account
# tokens cannot hold Registrar at all; buying domains takes your own
# `cloudflare-login` session.
# Zone permissions apply to every zone declared under identity.domains.
{
  accounts.demands = [
    {
      account = "cloudflare";
      capability = "accountTokens";
      need = true;
      why = "cloudflare.tokens, minted as account tokens by bootstrap";
    }
  ];

  cloudflare.groupScopes = {
    "Zone Read" = "zone.read";
    "DNS Read" = "dns.read";
    "DNS Write" = "dns.write";
    "Zone Settings Read" = "zone-settings.read";
    "Zone Settings Write" = "zone-settings.write";
    "SSL and Certificates Read" = "ssl-and-certificates.read";
    "SSL and Certificates Write" = "ssl-and-certificates.write";
    "Cache Purge" = "cache.purge";
    "Workers Routes Read" = "workers-routes.read";
    "Workers Routes Write" = "workers-routes.write";
    "Email Routing Rules Read" = "email-routing-rule.read";
    "Email Routing Rules Write" = "email-routing-rule.write";
    "Account Settings Read" = "account-settings.read";
    "Workers Scripts Read" = "workers-scripts.read";
    "Workers Scripts Write" = "workers-scripts.write";
    "Pages Read" = "pages:read";
    "Pages Write" = "pages:write";
    "Workers KV Storage Read" = "workers-kv-storage.read";
    "Workers KV Storage Write" = "workers-kv-storage.write";
    "Workers R2 Storage Read" = "workers-r2.read";
    "Workers R2 Storage Write" = "workers-r2.write";
    "D1 Read" = "d1.read";
    "D1 Write" = "d1.write";
    "Cloudflare Tunnel Read" = "argotunnel.read";
    "Cloudflare Tunnel Write" = "argotunnel.write";
    "Access: Apps and Policies Read" = "access.read";
    "Access: Apps and Policies Write" = "access.write";
    "Access: Organizations, Identity Providers, and Groups Read" = "access.read";
    "Access: Organizations, Identity Providers, and Groups Write" = "access.write";
    "Access: Service Tokens Read" = "access.read";
    "Access: Service Tokens Write" = "access.write";
  };

  cloudflare.tokens = {
    # Agents and PR plans: look at everything, change nothing.
    agent-readonly = {
      storeIn = [ "agent" ];
      zone = [
        "Zone Read"
        "DNS Read"
        "Zone Settings Read"
        "SSL and Certificates Read"
        "Workers Routes Read"
        "Email Routing Rules Read"
      ];
      account = [
        "Account Settings Read"
        "Workers Scripts Read"
        "Pages Read"
        "Workers KV Storage Read"
        "Workers R2 Storage Read"
        "D1 Read"
        "Cloudflare Tunnel Read"
        "Access: Apps and Policies Read"
        # The Zero Trust organization and its sign-in method, so a
        # pull-request plan can refresh them (2026-11-04).
        "Access: Organizations, Identity Providers, and Groups Read"
        # The dsh teams' service tokens (../cloudflare/_agents-access.nix),
        # so a pull-request plan can refresh them (2026-11-06).
        "Access: Service Tokens Read"
      ];
    };

    # CI on any branch, writing the build cache's bucket (modules/cache),
    # and nothing else of the account. Its R2 S3 keys are derived from it
    # by bootstrap (the key id is the token's id, the secret its SHA-256).
    cache-push = {
      storeIn = [ "cache" ];
      zone = [ ];
      account = [ "Workers R2 Storage Write" ];
    };

    # CI applying merged changes from main.
    ci-apply = {
      storeIn = [ "ci" ];
      zone = [
        "Zone Read"
        "DNS Write"
        "Zone Settings Write"
        "SSL and Certificates Write"
        "Cache Purge"
        "Workers Routes Write"
        "Email Routing Rules Write"
      ];
      account = [
        "Account Settings Read"
        "Workers Scripts Write"
        "Pages Write"
        "Workers KV Storage Write"
        "Workers R2 Storage Write"
        "D1 Write"
        "Cloudflare Tunnel Write"
        "Access: Apps and Policies Write"
        # The Zero Trust organization itself (status.mirazo.org, and the
        # agents behind Access).
        "Access: Organizations, Identity Providers, and Groups Write"
        # The dsh teams' service tokens, minted at apply (2026-11-06).
        "Access: Service Tokens Write"
      ];
    };
  };
}
