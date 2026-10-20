# The cloud environment's network allowlist, declared here and pasted into the
# environment settings (Network access: Custom). It cannot apply itself: the
# sandbox's limits are set outside the sandbox, on purpose.
#
#   nix build .#claude-allowed-domains && cat result
#
# Each host is type-checked, so a typo fails `nix flake check` instead of
# silently allowing or blocking the wrong thing.
{ lib, ... }:
let
  inherit (lib) mkOption types;

  # A hostname, optionally with a leading "*." (matches every subdomain).
  domain = types.strMatching "(\\*\\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}";

  group = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      reason = mkOption { type = types.str; };
      hosts = mkOption { type = types.nonEmptyListOf domain; };
    };
  };
in
{
  options.network = {
    includeDefaults = mkOption {
      type = types.bool;
      description = ''Tick "Also include default list of common package managers".'';
    };
    allow = mkOption { type = types.attrsOf group; };
  };

  config.network = {
    # The defaults already cover GitHub release downloads, *.r2.cloudflarestorage.com
    # (OpenTofu state) and *.nixos.org.
    includeDefaults = true;

    allow = {
      cloudflare = {
        reason = "Cloudflare API: OpenTofu layers and the registrar (modules/cloudflare)";
        hosts = [
          "api.cloudflare.com"
          # OAuth device login (cloudflare-login): the root session
          "dash.cloudflare.com"
        ];
      };
      proton = {
        reason = "pass-cli and secretspec reading Proton Pass";
        hosts = [
          "proton.me"
          "*.proton.me"
        ];
      };
      openrouter = {
        reason = "Models and key management (modules/openrouter)";
        hosts = [ "openrouter.ai" ];
      };
      mercury = {
        reason = "Virtual cards (modules/mercury); card details go to the vault API";
        hosts = [
          "api.mercury.com"
          "vault-api.mercury.com"
        ];
      };
      public = {
        reason = "Brokerage reads and orders (modules/public)";
        hosts = [ "api.public.com" ];
      };
      # Live data for running World Monitor / God's Eye View in a session.
      globe-data = {
        enable = false;
        reason = "Map tiles and public feeds for the globe apps";
        hosts = [
          "worldmonitor.app"
          "*.worldmonitor.app"
          "server.arcgisonline.com"
          "services.arcgisonline.com"
          "tile.openstreetmap.org"
          "opensky-network.org"
          "earthquake.usgs.gov"
          "api.cesium.com"
        ];
      };
    };
  };
}
