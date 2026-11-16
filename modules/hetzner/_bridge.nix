# The answering agents on jingzo-host (modules/agents/bridge.nix): one
# `opencode serve` per agent, on the loopback, and the bridge that turns
# what the owner says in a room into a turn of that room's agent.
#
#   opencode-<agent>   the agent's own server: its own user, its own state
#                      directory, its own OpenRouter key and a config that
#                      denies every tool. It starts only once its key is on
#                      the host (agents-secrets writes
#                      /run/agents/<agent>.openrouter.env when the key is
#                      minted), so an unfunded agent is simply absent.
#   agent-bridge       follows the rooms with the application service's
#                      token and keeps what it handled, each room's thread
#                      and the month's spend in its state directory
{
  answering, # agents.answering
  bridge, # agent-bridge
  opencodeConfig, # opencode-answering-config
  matrixPort,
}:
{ lib, pkgs, ... }:
{
  systemd.services =
    lib.listToAttrs (
      builtins.map (
        agent:
        lib.nameValuePair "opencode-${agent.name}" {
          description = "The ${agent.name} agent's harness (opencode serve, loopback)";
          wantedBy = [ "multi-user.target" ];
          after = [ "agents-secrets.service" ];
          unitConfig.ConditionPathExists = "/run/agents/${agent.name}.openrouter.env";
          environment = {
            OPENCODE_CONFIG = "${opencodeConfig}";
            HOME = "/var/lib/opencode-${agent.name}";
          };
          serviceConfig = {
            DynamicUser = true;
            StateDirectory = "opencode-${agent.name}";
            WorkingDirectory = "/var/lib/opencode-${agent.name}";
            EnvironmentFile = "/run/agents/${agent.name}.openrouter.env";
            ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 127.0.0.1 --port ${toString agent.port}";
            Restart = "on-failure";
            RestartSec = 10;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        }
      ) answering
    )
    // {
      agent-bridge = {
        description = "The bridge: what the owner says in a room becomes a turn of its agent";
        wantedBy = [ "multi-user.target" ];
        after = [ "matrix-rooms.service" ];
        requires = [ "matrix-tuwunel.service" ];
        serviceConfig = {
          StateDirectory = "agent-bridge";
          ExecStart = "${bridge}/bin/agent-bridge http://127.0.0.1:${toString matrixPort} /run/matrix/as-token /var/lib/agent-bridge/state.json";
          Restart = "always";
          RestartSec = 10;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
    };
}
