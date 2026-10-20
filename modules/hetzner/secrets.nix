# The Hetzner Cloud project token OpenTofu and hcloud use, from CI.
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.ci = {
    # Absent until the hetzner account exists (its first token is a Gap).
    HCLOUD_TOKEN = secret "Hetzner Cloud project token for OpenTofu and hcloud" "hcloud-token" // {
      required = false;
    };
  };
}
