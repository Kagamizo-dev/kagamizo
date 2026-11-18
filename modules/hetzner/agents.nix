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

  # The teams that hold an Access service token (../cloudflare/options.nix).
  dshAgentTeams = config.cloudflare.accessTeams;

  # The team variable name for secretspec: upper case, hyphens -> underscores.
  svcTokenVar =
    name: lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] name) + "_ACCESS_SERVICE_TOKEN";
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
                "chat"
                "harness"
                "os"
                "files"
              ];
              description = "agents: Open WebUI; code: OpenCode's web interface; chat: Element Web and the Matrix homeserver; harness: DeepSeek Harness's web UI; os: the Kagamizo shell's web target (../shell).";
            };
            port = mkOption { type = types.ints.between 1024 65535; };
            paths = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    path = mkOption {
                      type = types.strMatching "\\^/[A-Za-z0-9_./-]*";
                      description = "A path regex the tunnel matches before the hostname's port.";
                    };
                    port = mkOption { type = types.ints.between 1024 65535; };
                  };
                }
              );
              default = [ ];
              description = "Paths of this hostname served by another loopback port.";
            };
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
        {
          name = "harness";
          port = 3080;
        }
        {
          name = "chat";
          port = 8082;
          paths = [
            {
              path = "^/_matrix";
              port = 6167;
            }
            # GitHub's App manifest flow lands here (./_github-app.nix).
            {
              path = "^/_github/";
              port = 8083;
            }
          ];
        }
        {
          name = "os";
          port = 8084;
        }
        # What the units of work publish (../agents/_files-host.nix).
        {
          name = "files";
          port = 8085;
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

        # After `infra ci apply`: each dsh team's Access service token, from
        # OpenTofu's structured output (client_id, client_secret JSON) straight
        # into the host's vault (host/ACCESS_SERVICE_TOKEN_<team>), never
        # printed. The host reads it at its next boot or switch.
        packages.infra-service-tokens = pkgs.writeShellApplication {
          name = "infra-service-tokens";
          runtimeInputs = [
            config.packages.infra
            config.packages.secretspec
            pkgs.jq
          ];
          text = ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            spec=${config.packages.secretspec-toml}
            ${lib.concatStringsSep "\n" (
              builtins.map (team: ''
                var="${svcTokenVar team}"
                # OpenTofu prints one named output as its bare value
                # (client_id, client_secret), with no wrapper. Fail rather
                # than store a value that lacks either field.
                infra ci output -json agents-service-token-${team} |
                  jq -ce 'select(.client_id and .client_secret) | {client_id, client_secret}' |
                  secretspec set "$var" --file "$spec" --profile host \
                    --from-file - \
                    --reason "infra-service-tokens: store team ${team} Access service token" >/dev/null
                echo "infra-service-tokens: stored host/$var"
              '') dshAgentTeams
            )}
          '';
        };
      };
  };
}
