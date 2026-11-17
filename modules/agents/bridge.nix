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
#   agents.provider        "rehearsal" or "openrouter": the one switch for
#                          what the answering agents' harnesses call. It
#                          is "rehearsal" (the owner's rule, 2026-11-17:
#                          credit is the last step, after everything is
#                          tested and shown): the whole stack runs against
#                          a stand-in that bills nothing.
#   checks.chat-whole      the whole chain on the loopback, nothing billed:
#                          the owner is answered in the front room by the
#                          front agent through the real homeserver, bridge
#                          and harness; a room with no agent and the
#                          agent's own words start nothing; the turn is
#                          charged at the pinned price; a restart answers
#                          nothing twice; a failing provider ends in a
#                          refusal that is said and not charged
#   packages.rehearsal     the stand-in (./_rehearsal, Rust): it answers
#                          the call a harness makes for a turn, marks every
#                          answer as rehearsed, reports the cost the pinned
#                          prices give, and misbehaves on request (error,
#                          no-cost, dear)
#
# A turn is charged at the dearest pinned price of the agent's model
# (../openrouter/_spend/prices.json) for the tokens the harness reports,
# not at the harness's own figure.
#
# The host runs it (../hetzner/_bridge.nix). No agent reaches OpenRouter
# until the provider is switched, its key is minted and OpenRouter holds
# credit: each is the owner's word, and credit is the last.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.agents;
  catalog = lib.importJSON ./_json/opencode-serve.json;
  known = builtins.map (o: "${o.method} ${o.path}") catalog.operations;
  names = lib.attrNames (lib.filterAttrs (_: a: a.harness == "opencode") config.governance.agents);
  prices = lib.importJSON ../openrouter/_spend/prices.json;
  dearest = model: field: lib.foldl' lib.max 0 (builtins.map (e: e.${field}) prices.models.${model});
  rehearsalPort = 4090;
in
{
  options.agents = {
    answering = mkOption {
      type = types.listOf (types.attrsOf types.anything);
      readOnly = true;
      description = "The agents that answer in their rooms, as the bridge is built with them.";
    };
    provider = mkOption {
      type = types.enum [
        "rehearsal"
        "openrouter"
      ];
      default = "rehearsal";
      description = "What the answering agents' harnesses call: the stand-in that bills nothing, or OpenRouter.";
    };
    rehearsalPort = mkOption {
      type = types.port;
      readOnly = true;
      description = "The loopback port the stand-in listens on.";
    };
    opencodeCalls = mkOption {
      type = types.listOf (types.enum known);
      description = "The calls the bridge makes to `opencode serve`.";
    };
  };

  config = {
    agents = {
      inherit rehearsalPort;
      opencodeCalls = [
        "POST /session"
        "POST /session/{sessionID}/message"
        "POST /session/{sessionID}/abort"
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
        assert lib.assertMsg (prices.models ? ${agent.model})
          "agents.answering: ${name} runs ${agent.model}, which has no pinned price (openrouter/_spend/prices.json)";
        {
          inherit name;
          inherit (agent) model;
          inputUsdPerMillion = dearest agent.model "input";
          outputUsdPerMillion = dearest agent.model "output";
          port = 4100 + i;
          capUsd = agent.budgetUsdPerMonth;
          # Where its key lands (openrouter.keys.<k>.profile).
          inherit (config.openrouter.keys.${agent.key}) profile;
        }
      ) names;
    };

    perSystem =
      { pkgs, self', ... }:
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

        # The whole chain on the loopback, with nothing billed: the pinned
        # homeserver, the rooms, the bridge, `opencode serve` and the
        # stand-in, as the host runs them (./_bridge/src/bin).
        checks.chat-whole = pkgs.stdenvNoCC.mkDerivation {
          name = "chat-whole-check";
          dontUnpack = true;
          nativeBuildInputs = [ self'.packages.agent-bridge ];
          # The homeserver reads /etc/resolv.conf and the system's
          # certificates at its start, and a build has neither; the check
          # shows them to the homeserver alone.
          CHECK_PRELOAD = "${pkgs.libredirect}/lib/libredirect.so";
          CHECK_REDIRECTS = "/etc/resolv.conf=${pkgs.writeText "resolv.conf" "nameserver 127.0.0.1\n"}";
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          installPhase = "HOME=$TMPDIR chat-whole-check ${lib.getExe pkgs.matrix-tuwunel} ${lib.getExe pkgs.opencode} ${self'.packages.opencode-answering-config} ${lib.getExe self'.packages.rehearsal} ${lib.getExe self'.packages.agent-bridge} > $out";
        };

        packages.rehearsal = pkgs.rustPlatform.buildRustPackage {
          pname = "rehearsal";
          version = "0.1.0";
          src = ./_rehearsal;
          cargoLock.lockFile = ./_rehearsal/Cargo.lock;
          REHEARSAL_PRICES = ../openrouter/_spend/prices.json;
          meta.mainProgram = "rehearsal";
        };

        packages.opencode-answering-config = pkgs.writeText "opencode-answering.json" (
          builtins.toJSON {
            "$schema" = "https://opencode.ai/config.json";
            model = "openrouter/${config.openrouter.defaultModel}";
            enabled_providers = [ "openrouter" ];
            provider.openrouter = {
              models = lib.genAttrs config.openrouter.models (_: { });
            }
            // lib.optionalAttrs (cfg.provider == "rehearsal") {
              options.baseURL = "http://127.0.0.1:${toString rehearsalPort}/api/v1";
            };
            permission = "deny";
            share = "disabled";
            autoupdate = false;
          }
        );
      };
  };
}
