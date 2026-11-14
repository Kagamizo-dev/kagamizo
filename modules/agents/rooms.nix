# The teams' rooms: talking to a team is talking in its room (the owner's
# direction, 2026-11-14: click a team and talk to it, with the teams and
# their roles apart). Every team is its own identity on the homeserver
# (../hetzner/_chat.nix registers each and keeps its login in Proton Pass)
# and has one room, holding the owner and that team only.
#
#   agents.rooms.<team> = { alias; topic; members; }
#       derived from governance.agents: none is written by hand
#   agents.chat.owner   the owner's localpart on the homeserver
#   agents.chat.server  the homeserver's name
#
# checks.agents-rooms (./_lean/Rooms.lean): every team has exactly one room,
# no two rooms share an alias, and a room's members are the owner and its
# own team.
#
# What is declared here is not yet live: the rooms are created on the
# homeserver by a tool still to be written, and no team answers until the
# runner listens in its room.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.agents;
  q = builtins.toJSON;
  teams = lib.attrNames config.governance.agents;

  room = types.submodule {
    options = {
      alias = mkOption { type = types.strMatching "[a-z][a-z0-9-]*"; };
      topic = mkOption { type = types.str; };
      members = mkOption { type = types.listOf types.str; };
    };
  };

  facts = ''

    namespace Kagamizo.Rooms

    def owner : String := ${q cfg.chat.owner}

    def teams : List String := ${q teams}

    def rooms : List Room := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          t: r: "{ team := ${q t}, alias := ${q r.alias}, members := ${q r.members} }"
        ) cfg.rooms
      )
    }]

    theorem rooms_sound : sound owner teams rooms = true := by
      decide +kernel

    end Kagamizo.Rooms
  '';
in
{
  options.agents = {
    chat = {
      owner = mkOption {
        type = types.strMatching "[a-z][a-z0-9-]*";
        description = "The owner's localpart on the homeserver.";
      };
      server = mkOption {
        type = types.str;
        description = "The homeserver's name.";
      };
    };
    rooms = mkOption {
      type = types.attrsOf room;
      description = "One room per team: its alias, its topic and who is in it.";
    };
  };

  config = {
    agents = {
      chat = {
        # As ../hetzner/host.nix names the owner to the homeserver.
        owner = lib.head (lib.splitString "@" (lib.head config.hetzner.host.agents.viewers));
        server = config.hetzner.host.agents.zone;
      };
      rooms = lib.genAttrs teams (t: {
        alias = t;
        topic = config.governance.agents.${t}.purpose;
        members = [
          cfg.chat.owner
          t
        ];
      });
    };

    perSystem =
      { config, ... }:
      {
        checks.agents-rooms = config.kagamizo.leanCheck {
          name = "agents-rooms";
          source = ./_lean/Rooms.lean;
          inherit facts;
        };
      };
  };
}
