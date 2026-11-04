# jingzo-host's always-on agents, typed: each service is a name (its
# hostname under the zone) and a loopback port. The host runs them
# (./_agents.nix); Cloudflare routes each name to its port through the
# agents tunnel, behind Access (../cloudflare/_agents.nix).
#
#   hetzner.host.agents.zone        the zone the hostnames live in
#   hetzner.host.agents.viewers     who Access lets through
#   hetzner.host.agents.services    [ { name; port; } ]
#
#   nix run .#infra-tunnel-token
#       after `infra ci apply`: the tunnel's token, from OpenTofu's
#       sensitive output straight into the host's vault (host/TUNNEL_TOKEN),
#       never printed. The host reads it at its next boot or switch.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.hetzner.host.agents;
  names = map (s: s.name) cfg.services;
  ports = map (s: s.port) cfg.services;
in
{
  options.hetzner.host.agents = {
    zone = mkOption {
      type = types.enum (lib.attrNames config.identity.checked.domains);
      default = "jingzo.org";
    };
    viewers = mkOption {
      type = types.listOf (types.strMatching "[^@ ]+@[^@ ]+");
      default = [ "zach@mirazo.org" ];
    };
    tier1Port = mkOption {
      type = types.ints.between 1024 65535;
      default = 8081;
      description = "llama.cpp's loopback port for the small model (./_tier1.nix).";
    };
    services = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.enum [
                "agents"
                "code"
              ];
              description = "agents: Open WebUI; code: OpenCode's web interface.";
            };
            port = mkOption { type = types.ints.between 1024 65535; };
          };
        }
      );
      default = [
        {
          name = "agents";
          port = 8080;
        }
        {
          name = "code";
          port = 4096;
        }
      ];
    };
  };

  config = {
    perSystem =
      { pkgs, config, ... }:
      {
        packages.infra-tunnel-token = pkgs.writeShellApplication {
          name = "infra-tunnel-token";
          runtimeInputs = [
            config.packages.infra
            config.packages.secretspec
          ];
          text =
            assert lib.assertMsg (lib.unique names == names) "hetzner.host.agents: a service is named twice";
            assert lib.assertMsg (lib.unique ports == ports) "hetzner.host.agents: a port is used twice";
            ''
              export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
              # OpenTofu's output into secretspec's stdin: never printed.
              infra ci output -raw agents_tunnel_token |
                secretspec set TUNNEL_TOKEN --file ${config.packages.secretspec-toml} --profile host \
                  --from-file - --reason "infra-tunnel-token: the agents tunnel's token for jingzo-host" >/dev/null
              echo "infra-tunnel-token: stored host/TUNNEL_TOKEN"
            '';
        };
      };
  };
}
