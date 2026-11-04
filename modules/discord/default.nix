# Discord as the share-from-phone channel (the owner's decision,
# 2026-11-04): the owner drops links, videos and voice notes into one
# private server's one channel, and a bot relays them into the agents'
# Matrix room on jingzo-host (../hetzner/_chat.nix) and the agents' replies
# back. Matrix stays the core chat; Discord is the phone's share sheet.
# The bot reads one channel and posts to that channel only, never anywhere
# public: ./_lean/Relay.lean is the rule, ./_src the Rust that keeps it.
#
#   discord.channelId      the one channel the bot reads and posts in
#   discord.ownerUserId    the owner's Discord user: the only author relayed
#   discord.guildId        the private server
#   discord.matrixRoom     the Matrix room alias the shares land in; the
#                          relay makes it, invites the owner, if absent
#
#   packages.discord-relay       the relay (./_src)
#   checks.discord-relay         Lean proves the rule and decides the
#                                declared ids; the crate's tests run
#
# The ids are null until the owner has made the server and the bot
# (./account.nix); the host's service stays off until then (./_host.nix).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.discord;
  q = builtins.toJSON;
  snowflake = types.nullOr (types.strMatching "[0-9]{15,22}");
  declared = cfg.channelId != null && cfg.ownerUserId != null;

  facts = ''

    namespace Kagamizo.Relay

    ${
      if declared then
        ''
          /-- The declared ids, rendered by modules/discord/default.nix. -/
          def declared : Declared :=
            { owner := ⟨${q cfg.ownerUserId}⟩, channel := ⟨${q cfg.channelId}⟩ }

          /-- A user and a channel are never the same snowflake. -/
          theorem owner_is_not_channel : declared.owner ≠ declared.channel := by decide +kernel

          /-- The owner's own message in the channel is relayed ... -/
          theorem owner_relayed :
              relayed declared { author := declared.owner, channel := declared.channel, bot := false } = true := by
            decide +kernel

          /-- ... a bot's with the owner's id is not, nor the owner's elsewhere. -/
          theorem bot_dropped :
              relayed declared { author := declared.owner, channel := declared.channel, bot := true } = false := by
            decide +kernel
          theorem elsewhere_dropped :
              relayed declared { author := declared.owner, channel := declared.owner, bot := false } = false := by
            decide +kernel
        ''
      else
        ''
          /-- No ids are declared yet (discord.channelId, discord.ownerUserId): the
          rule is proven for any; the host's relay stays off. -/
          def declared : Option Declared := none
        ''
    }

    end Kagamizo.Relay
  '';
in
{
  options.discord = {
    channelId = mkOption {
      type = snowflake;
      default = null;
      description = "The one channel the bot reads and posts in (a Discord snowflake).";
    };
    ownerUserId = mkOption {
      type = snowflake;
      default = null;
      description = "The owner's Discord user id: the only author whose messages are relayed.";
    };
    guildId = mkOption {
      type = snowflake;
      default = null;
      description = "The owner's private server.";
    };
    matrixRoom = mkOption {
      type = types.strMatching "#[A-Za-z0-9._=-]+";
      default = "#share";
      description = "The room alias's local part on the agents' homeserver; the relay creates the room if it is missing.";
    };
  };

  config.perSystem =
    { pkgs, ... }:
    let
      relay = pkgs.rustPlatform.buildRustPackage {
        pname = "discord-relay";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        meta.mainProgram = "discord-relay";
      };
      tests = relay.overrideAttrs (_: {
        doCheck = true;
      });
    in
    {
      packages.discord-relay = relay;

      checks.discord-relay =
        pkgs.runCommand "discord-relay"
          {
            nativeBuildInputs = [ pkgs.lean4 ];
            inherit facts;
            passAsFile = [ "facts" ];
            # The crate's tests, built and run alongside.
            inherit tests;
          }
          ''
            cat ${./_lean/Relay.lean} "$factsPath" > Check.lean
            lean Check.lean
            touch $out
          '';
    };
}
