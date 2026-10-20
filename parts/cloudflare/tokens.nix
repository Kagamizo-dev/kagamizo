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
      ];
    };

    # CI applying merged changes from master.
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
      ];
    };
  };
}
