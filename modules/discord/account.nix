# Discord: the owner's free account, one private server, one bot. The bot
# is made in Discord's developer portal, where its token is shown once
# (a console credential: the owner pastes it into the prepared
# api-credential item, nothing else is prepared by hand).
# Its capabilities are the closed set every discord plan must state, each
# with the page that states it (../accounts).
let
  secret = import ../_lib/secret.nix;
in
{
  accounts = {
    capabilities.discord = {
      botApi = "flag";
      gatewayIntents = "flag";
      fileUploadMb = "limit";
    };

    plans.discord.free = {
      # No fee; Nitro is the paid tier.
      billing = {
        value = "free";
        source = "https://discord.com/nitro";
      };
      checked = "2026-11-04";
      capabilities = {
        # Bots (applications) are made in the developer portal on any
        # account; their token signs the REST and gateway calls.
        botApi = {
          value = true;
          source = "https://discord.com/developers/docs/intro";
        };
        # The privileged Message Content intent is a switch on the bot's
        # page; under 100 servers it needs no verification.
        gatewayIntents = {
          value = true;
          source = "https://discord.com/developers/docs/events/gateway#gateway-intents";
        };
        # Uploads from a free account: 10 MB a file (Nitro raises it).
        fileUploadMb = {
          value = 10;
          source = "https://support.discord.com/hc/en-us/articles/25444343143063";
        };
      };
    };

    # Yours: the share sheet on the phone. The server is private (the
    # owner alone and the bot) and the bot posts nowhere else.
    held.discord-mirazo = {
      provider = "discord";
      plan = "free";
      owner = "mirazo";
      status = "planned";
      signup = {
        url = "https://discord.com/register";
        handle = "mirazo";
        email = "zach@mirazo.org";
        credential = "password";
        findings = [
          {
            fact = "a bot is an application made in the developer portal; its token is shown once on the Bot page and reset there";
            source = "https://discord.com/developers/docs/quick-start/getting-started";
            checked = "2026-11-04";
          }
          {
            fact = "reading message text needs the Message Content privileged intent, switched on in the portal for bots in under 100 servers";
            source = "https://discord.com/developers/docs/events/gateway#privileged-intents";
            checked = "2026-11-04";
          }
        ];
      };
      login = {
        item = "discord";
        email = "zach@mirazo.org";
      };
      credential = {
        item = "discord-bot-token";
        template = "api-credential";
      };
    };

    demands = [
      {
        account = "discord-mirazo";
        capability = "botApi";
        need = true;
        why = "discord-relay signs in as the bot (modules/discord)";
      }
      {
        account = "discord-mirazo";
        capability = "gatewayIntents";
        need = true;
        why = "discord-relay reads message text (MESSAGE_CONTENT)";
      }
    ];
  };

  # The bot's token, on the host beside the other agents' keys. The owner
  # makes the bot and pastes the token (human:console-credential); absent
  # until then, and the relay stays off.
  secrets.profiles.host.DISCORD_BOT_TOKEN =
    secret {
      kind = "api-token";
      issuer = "human:console-credential";
      description = "Discord bot token for discord-relay (modules/discord), made in the developer portal and pasted by the owner into the prepared api-credential item";
      item = "discord-bot-token";
      template = "api-credential";
      field = "Secret";
    }
    // {
      required = false;
    };
}
