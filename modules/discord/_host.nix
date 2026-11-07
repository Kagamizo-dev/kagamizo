# The relay on jingzo-host (../discord): one systemd service, its secrets
# from /run/agents/discord.env (written by agents-secrets,
# ../hetzner/_agents.nix: the bot token from the host's vault, the agents'
# Matrix password from the host's state vault). It speaks to the homeserver
# on the loopback and to Discord outbound; nothing listens.
#
# Off until the ids are declared (discord.channelId, discord.ownerUserId)
# and the token is in the vault: without the file the unit waits and says
# so, without the ids it is not declared at all.
{
  relay,
  channelId, # null until declared
  ownerUserId, # null until declared
  matrixPort,
  zone,
  room, # the alias's local part
  owner, # the owner's Matrix localpart, invited into the room
}:
{ lib, ... }:
let
  envFile = "/run/agents/discord.env";
in
{
  systemd.services.discord-relay = lib.mkIf (channelId != null && ownerUserId != null) {
    description = "Discord into the agents' Matrix room, and back";
    wantedBy = [ "multi-user.target" ];
    after = [
      "agents-secrets.service"
      "matrix-seed.service"
    ];
    requires = [ "agents-secrets.service" ];
    unitConfig = {
      # agents-secrets writes the file only once the token is in the vault.
      ConditionPathExists = envFile;
    };
    environment = {
      DISCORD_CHANNEL_ID = channelId;
      DISCORD_OWNER_ID = ownerUserId;
      MATRIX_URL = "http://127.0.0.1:${toString matrixPort}";
      MATRIX_USER = "agents";
      MATRIX_ROOM = "${room}:${zone}";
      MATRIX_INVITE = "@${owner}:${zone}";
    };
    serviceConfig = {
      DynamicUser = true;
      EnvironmentFile = envFile;
      ExecStart = lib.getExe relay;
      Restart = "always";
      RestartSec = 10;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };
}
