# The bridge: what the owner says in a room becomes one turn of that room's
# agent, and the answer is said back in the room (the owner's direction,
# 2026-11-16: one chat for everything).
#
#   agents.answering       the agents that answer in their rooms: every
#                          governance agent whose harness is "opencode",
#                          each with its model, its month's cap and the
#                          loopback port its own `opencode serve` listens on
#   agents.opencodeCalls   the calls the bridge makes to `opencode serve`.
#                          Each must be an operation of the pinned server
#                          (./_json/opencode-serve.json, read from its own
#                          /doc), or evaluation fails naming it.
#   packages.agent-bridge  the bridge (./_bridge, Rust), with the rooms and
#                          the answering agents compiled in
#   packages.opencode-answering-config
#                          the config every answering agent's server runs
#                          with: OpenRouter only, and every tool denied.
#                          An answering agent talks; it gets a tool only
#                          as a declared skill, later.
#
# The bridge holds to these, tested in ./_bridge: only the owner starts
# work; an answer is said only in the room spoken in, as its own agent; an
# agent stops at its month's cap and says so; nothing is answered twice.
#
# The host runs it (../hetzner/_bridge.nix). No agent answers until its
# key is minted and OpenRouter holds credit: both are the owner's word.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.agents;
  catalog = lib.importJSON ./_json/opencode-serve.json;
  known = builtins.map (o: "${o.method} ${o.path}") catalog.operations;
  names = lib.attrNames (lib.filterAttrs (_: a: a.harness == "opencode") config.governance.agents);
in
{
  options.agents = {
    answering = mkOption {
      type = types.listOf (types.attrsOf types.anything);
      readOnly = true;
      description = "The agents that answer in their rooms, as the bridge is built with them.";
    };
    opencodeCalls = mkOption {
      type = types.listOf (types.enum known);
      description = "The calls the bridge makes to `opencode serve`.";
    };
  };

  config = {
    agents = {
      opencodeCalls = [
        "POST /session"
        "POST /session/{sessionID}/message"
      ];
      answering = lib.imap0 (
        i: name:
        let
          agent = config.governance.agents.${name};
        in
        assert lib.assertMsg (
          cfg.rooms ? ${name}
        ) "agents.answering: ${name} answers and has no room (agents.rooms)";
        assert lib.assertMsg (
          agent.key != null && config.openrouter.keys ? ${agent.key}
        ) "agents.answering: ${name} answers and names no declared key of its own";
        {
          inherit name;
          inherit (agent) model;
          port = 4100 + i;
          capUsd = agent.budgetUsdPerMonth;
          # Where its key lands (openrouter.keys.<k>.profile).
          inherit (config.openrouter.keys.${agent.key}) profile;
        }
      ) names;
    };

    perSystem =
      { pkgs, ... }:
      {
        packages.agent-bridge = pkgs.rustPlatform.buildRustPackage {
          pname = "agent-bridge";
          version = "0.1.0";
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./_bridge
              ./_rooms
            ];
          };
          sourceRoot = "source/_bridge";
          cargoLock.lockFile = ./_bridge/Cargo.lock;
          MATRIX_ROOMS = pkgs.writeText "matrix-rooms.json" (
            builtins.toJSON {
              inherit (cfg.chat) owner server;
              rooms = lib.mapAttrsToList (team: r: r // { inherit team; }) cfg.rooms;
            }
          );
          BRIDGE_AGENTS = pkgs.writeText "bridge-agents.json" (builtins.toJSON cfg.answering);
          BRIDGE_CALLS = pkgs.writeText "bridge-calls.json" (builtins.toJSON cfg.opencodeCalls);
          meta.mainProgram = "agent-bridge";
        };

        packages.opencode-answering-config = pkgs.writeText "opencode-answering.json" (
          builtins.toJSON {
            "$schema" = "https://opencode.ai/config.json";
            model = "openrouter/${config.openrouter.defaultModel}";
            enabled_providers = [ "openrouter" ];
            provider.openrouter.models = lib.genAttrs config.openrouter.models (_: { });
            permission = "deny";
            share = "disabled";
            autoupdate = false;
          }
        );
      };
  };
}
