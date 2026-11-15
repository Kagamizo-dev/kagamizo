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
#   agents.chat.address the owner's address, as Cloudflare Access vouches
#                       for it: the one the chat pages talk for
#   agents.chat.accessTeam, .port, .prefix
#                       the Access team that signs assertions, and where
#                       the gateway listens and is served
#
# checks.agents-rooms (./_lean/Rooms.lean): every team has exactly one room,
# no two rooms share an alias, and a room's members are the owner and its
# own team.
#
#   packages.matrix-rooms  the tool that makes them true on the homeserver
#                          (./_rooms, Rust). It is the homeserver's one
#                          application service: its namespace is exactly
#                          the declared accounts and aliases, and its token
#                          is the only credential. No account has a
#                          password; nothing signs in (the owner's rule,
#                          2026-11-15). It does only what is missing,
#                          removes nothing, and reports anyone in a room
#                          who is not declared. The host runs it
#                          (../hetzner/_chat.nix).
#   checks.matrix-rooms    the tool against the pinned homeserver on the
#                          loopback: the rooms are made with the token
#                          alone, a second run does nothing, a wrong token
#                          is refused
#
#   packages.chat-gateway  the chat pages (./_chat, Rust): the owner reads a
#                          team's room and talks in it on the shell's own
#                          site, behind Access, with no second sign-in.
#                          It serves only the address Access vouches for,
#                          and reaches the homeserver with the application
#                          service's token. Its second program,
#                          chat-check-server, is the same pages over a
#                          homeserver kept in memory, for
#                          checks.shell-e2e (../shell/shell.nix).
#
# No team answers yet: that waits on the runner listening in its room.
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
      address = mkOption {
        type = types.str;
        description = "The owner's address, as Cloudflare Access vouches for it.";
      };
      accessTeam = mkOption {
        type = types.str;
        # As ../cloudflare/infra.nix names it to Cloudflare (auth_domain).
        default = "kagamizo.cloudflareaccess.com";
        description = "The Access team whose keys sign the assertions the gateway believes.";
      };
      port = mkOption {
        type = types.port;
        default = 8086;
        description = "The loopback port the chat gateway listens on.";
      };
      prefix = mkOption {
        type = types.strMatching "(/[a-z]+)+";
        default = "/next/chat";
        description = "Where the chat pages are served on the shell's site.";
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
        owner = lib.head (lib.splitString "@" cfg.chat.address);
        address = lib.head config.hetzner.host.agents.viewers;
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
      { config, pkgs, ... }:
      {
        packages.matrix-rooms = pkgs.rustPlatform.buildRustPackage {
          pname = "matrix-rooms";
          version = "0.1.0";
          src = ./_rooms;
          cargoLock.lockFile = ./_rooms/Cargo.lock;
          MATRIX_ROOMS = pkgs.writeText "matrix-rooms.json" (q {
            inherit (cfg.chat) owner server;
            rooms = lib.mapAttrsToList (team: r: r // { inherit team; }) cfg.rooms;
          });
          meta.mainProgram = "matrix-rooms";
        };
        packages.chat-gateway = pkgs.rustPlatform.buildRustPackage {
          pname = "chat-gateway";
          version = "0.1.0";
          # The gateway is built from the rooms crate and the site's own
          # parts, each where it lives.
          src = lib.fileset.toSource {
            root = ../.;
            fileset = lib.fileset.unions [
              ./_chat
              ./_rooms
              ../shell/_site
              ../shell/_shell/src/model.rs
            ];
          };
          sourceRoot = "source/agents/_chat";
          cargoLock.lockFile = ./_chat/Cargo.lock;
          inherit (config.packages.matrix-rooms) MATRIX_ROOMS;
          meta.mainProgram = "chat-gateway";
        };
        checks.matrix-rooms = pkgs.stdenvNoCC.mkDerivation {
          name = "matrix-rooms-check";
          dontUnpack = true;
          nativeBuildInputs = [ config.packages.matrix-rooms ];
          # The homeserver reads /etc/resolv.conf and the system's
          # certificates at its start, and a build has neither: it is shown
          # a resolver that names the loopback and the pinned bundle.
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          LD_PRELOAD = "${pkgs.libredirect}/lib/libredirect.so";
          NIX_REDIRECTS = "/etc/resolv.conf=${pkgs.writeText "resolv.conf" "nameserver 127.0.0.1\n"}";
          installPhase = "matrix-rooms-check ${lib.getExe pkgs.matrix-tuwunel} > $out";
        };
        checks.agents-rooms = config.kagamizo.leanCheck {
          name = "agents-rooms";
          source = ./_lean/Rooms.lean;
          inherit facts;
        };
      };
  };
}
