# Non-secret facts about the Cloudflare account. Fill in the REPLACE values
# before the first run; `nix run .#infra` refuses to start while they remain.
# IDs are on the dashboard: open the zone, Overview page, "API" box (right column).
{
  accountId = "73f11fa58ac09529a4fb40284b8ce236";
  zoneId = "2f1f4505269c5d5ea904ca73d379ef99";
  zone = "example.com";

  # R2 bucket holding the encrypted OpenTofu state. Created by hand once, since
  # the state cannot live in a bucket the state itself creates.
  stateBucket = "nix-images-tofu-state";

  # Every minted token stops working on this date. To rotate: bump it and
  # re-apply the bootstrap layer, then store the new values in Proton Pass.
  tokenExpiry = "2027-01-15T00:00:00Z";

  # Proton Mail records for the zone apex. Values come from Proton's
  # Settings, Domain names, "Add domain" wizard.
  proton = {
    enable = false;
    verification = ""; # the part after "protonmail-verification="
    dkimId = ""; # the unique part of protonmail.domainkey.<id>.domains.proton.ch
  };

  # Extra DNS records, keyed by resource name. Example:
  #   www = { name = "www.example.com"; type = "CNAME"; content = "example.pages.dev"; proxied = true; };
  records = { };
}
