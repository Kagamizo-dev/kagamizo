# Hetzner's tools, pinned with the flake: hcloud and OpenTofu with the
# hcloud provider. What each can do is in ../catalog/_json (hcloud.json,
# hetzner-provider.json), and the API they call is hetzner-api.json.
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        inherit (pkgs) hcloud;
        tofu-hetzner = pkgs.opentofu.withPlugins (p: [ p.hetznercloud_hcloud ]);
      };
    };
}
