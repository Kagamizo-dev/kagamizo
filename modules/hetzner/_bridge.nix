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
#   rehearsal          while agents.provider is "rehearsal": the stand-in
#                      for OpenRouter on the loopback. Every harness is
#                      built to call it, holds no key and bills nothing.
#   agent-bridge       follows the rooms with the application service's
#                      token and keeps what it handled, each room's thread
#                      and the month's spend in its state directory
{
  answering, # agents.answering
  bridge, # agent-bridge
  opencodeConfig, # opencode-answering-config
  matrixPort,
  provider, # agents.provider: "rehearsal" or "openrouter"
  rehearsal, # the stand-in
  rehearsalPort,
}:
{ lib, pkgs, ... }:
let
  rehearsed = provider == "rehearsal";
in
{
  systemd.services =
    lib.listToAttrs (
      builtins.map (
        agent:
        lib.nameValuePair "opencode-${agent.name}" {
          description = "The ${agent.name} agent's harness (opencode serve, loopback)";
          wantedBy = [ "multi-user.target" ];
          after = if rehearsed then [ "rehearsal.service" ] else [ "agents-secrets.service" ];
          # On OpenRouter it starts only once its key is on the host; in
          # rehearsal it needs none.
          unitConfig = lib.optionalAttrs (!rehearsed) {
            ConditionPathExists = "/run/agents/${agent.name}.openrouter.env";
          };
          environment = {
            OPENCODE_CONFIG = "${opencodeConfig}";
            HOME = "/var/lib/opencode-${agent.name}";
          }
          // lib.optionalAttrs rehearsed {
            # Not a key: the stand-in asks for none, the harness for a value.
            OPENROUTER_API_KEY = "rehearsal";
          };
          serviceConfig = {
            DynamicUser = true;
            StateDirectory = "opencode-${agent.name}";
            WorkingDirectory = "/var/lib/opencode-${agent.name}";
            ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 127.0.0.1 --port ${toString agent.port}";
            Restart = "on-failure";
            RestartSec = 10;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          }
          // lib.optionalAttrs (!rehearsed) {
            EnvironmentFile = "/run/agents/${agent.name}.openrouter.env";
          };
        }
      ) answering
    )
    // lib.optionalAttrs rehearsed {
      rehearsal = {
        description = "The stand-in for OpenRouter: answers marked as rehearsed, nothing billed";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${rehearsal}/bin/rehearsal ${toString rehearsalPort}";
          Restart = "always";
          RestartSec = 5;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          # It reaches nothing: the loopback only.
          IPAddressDeny = "any";
          IPAddressAllow = "localhost";
        };
      };
    }
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
