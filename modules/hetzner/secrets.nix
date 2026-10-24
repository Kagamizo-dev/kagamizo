# The Hetzner Cloud project token OpenTofu and hcloud use, kept in the
# account owner's sessions vault: the owner of the token is the owner of
# the account (accounts.held.hetzner.owner).
{ config, ... }:
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.hetzner = {
    defaults.providers = [ "${config.accounts.held.hetzner.owner}-sessions" ];
    # Absent until the account exists (its first token is made in the
    # Cloud Console, a Gap).
    HCLOUD_TOKEN = secret "Hetzner Cloud project token for OpenTofu and hcloud" "hcloud-token" // {
      required = false;
    };
  };
}
