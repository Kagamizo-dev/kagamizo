# The always-on agents on jingzo-host (./agents.nix): Open WebUI and
# OpenCode on the loopback, reached only through the agents tunnel behind
# Access (../cloudflare/_agents.nix). No port is open.
#
# Owner single sign-on (Cloudflare Access):
#   Open WebUI trusts the Cf-Access-Authenticated-User-Email header that
#   cloudflared sets after Access verifies the viewer.  Because the app then
#   trusts a header for auth, it must be reachable only through cloudflared
#   on the loopback — which it is (host = 127.0.0.1, port opened only by the
#   tunnel's ingress).  ENABLE_SIGNUP=off keeps sign-ups closed, but the
#   trusted header path admits Access-verified identities regardless.
#   OpenCode (v2.2.5) and dsh (v0.2.1-rc.5) do not support a trusted-header
#   auth mode; see Gaps in modules/cloudflare/README.md.
#   Element/tuwunel keep Matrix accounts (the seeded login is the owner's);
#   no change needed.
#
#   agents-secrets   once a boot: the OpenRouter key (chat-and-code, capped)
#                    and the tunnel token, from the host's read-only vault,
#                    into /run/agents (mode 600, never printed); and the
#                    Discord relay's env when its token is there
#   open-webui       Open WebUI on OpenRouter, signing in whoever Access let
#                    through (Cf-Access-Authenticated-User-Email)
#   opencode-web     OpenCode's web interface, with the repo's OpenCode
#                    config (OpenRouter only, the declared open-weight models)
#   cloudflared      the tunnel, dialling out with its token as a credential
{
  services,
  zone,
  tier1Port,
  passCli,
  secretspec,
  secretspecToml,
  opencodeConfig,
  tokenFile,
  stateVault,
  alsoUnfree ? [ ], # further unfree packages admitted by name (../android)
}:
{ lib, pkgs, ... }:
let
  port = name: (lib.findFirst (s: s.name == name) (throw "agents: no service ${name}") services).port;
  # agents-secrets itself waits for the network.
  after = [ "agents-secrets.service" ];
in
{
  # Open WebUI's licence (BSD-3 with a branding clause, nixpkgs: unfree)
  # allows self-hosting with its branding kept; the one exception admitted,
  # beside the Android SDK's packages (../android, by name).
  nixpkgs.config.allowUnfreePredicate =
    pkg: lib.elem (lib.getName pkg) ([ "open-webui" ] ++ alsoUnfree);

  systemd.services = {
    agents-secrets = {
      description = "The agents' keys, from the host's vault into /run/agents";
      wantedBy = [ "multi-user.target" ];
      # One pass-cli at a time on the shared session.
      after = [
        "network-online.target"
        "migration-staging.service"
      ];
      wants = [ "network-online.target" ];
      path = [
        passCli
        secretspec
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      script = ''
        set -euo pipefail
        export PROTON_PASS_KEY_PROVIDER=fs HOME=/root
        export PROTON_PASS_AGENT_REASON="jingzo-host: the agents' keys"
        pass-cli info >/dev/null 2>&1 || pass-cli login --pat "$(cat ${tokenFile})" >/dev/null
        umask 077
        mkdir -p /run/agents
        get() { secretspec get "$1" --file ${secretspecToml} --profile host --reason "agents-secrets: $1"; }
        key=$(get OPENROUTER_API_KEY)
        # Open WebUI takes every endpoint at once: OpenRouter, then the
        # host's free tier-1 model (llama.cpp needs no key; "local" is a
        # placeholder, not a secret).
        printf 'OPENAI_API_KEY=%s\nOPENROUTER_API_KEY=%s\nOPENAI_API_KEYS=%s;local\n' "$key" "$key" "$key" >/run/agents/openrouter.env
        unset key
        get TUNNEL_TOKEN >/run/agents/tunnel-token
        [ -s /run/agents/tunnel-token ] || { echo "agents-secrets: no tunnel token yet (infra-tunnel-token)" >&2; exit 1; }
        # The Discord relay (modules/discord): the bot's token, pasted by the
        # owner, and the agents' Matrix login (matrix-seed's item). Without
        # either there is no file, and the relay's unit waits.
        rm -f /run/agents/discord.env
        discord=$(get DISCORD_BOT_TOKEN 2>/dev/null || true)
        matrix=$(pass-cli item view --vault-name ${stateVault} --item-title matrix-agents --field password 2>/dev/null || true)
        if [ -n "$discord" ] && [ -n "$matrix" ]; then
          printf 'DISCORD_BOT_TOKEN=%s\nMATRIX_PASSWORD=%s\n' "$discord" "$matrix" >/run/agents/discord.env
        else
          echo "agents-secrets: no Discord relay yet (bot token in host/DISCORD_BOT_TOKEN, matrix-agents in ${stateVault})"
        fi
        unset discord matrix
      '';
    };

    open-webui = {
      after = after ++ [ "llama-cpp.service" ];
      requires = [ "agents-secrets.service" ];
    };

    opencode-web = {
      description = "OpenCode's web interface";
      wantedBy = [ "multi-user.target" ];
      inherit after;
      requires = [ "agents-secrets.service" ];
      environment = {
        OPENCODE_CONFIG = "${opencodeConfig}";
        HOME = "/var/lib/opencode-web";
      };
      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "opencode-web";
        WorkingDirectory = "/var/lib/opencode-web";
        EnvironmentFile = "/run/agents/openrouter.env";
        ExecStart = "${pkgs.opencode}/bin/opencode web --hostname 127.0.0.1 --port ${toString (port "code")}";
        Restart = "on-failure";
      };
    };

    cloudflared-agents = {
      description = "The agents tunnel (Cloudflare, dialling out)";
      wantedBy = [ "multi-user.target" ];
      inherit after;
      requires = [ "agents-secrets.service" ];
      serviceConfig = {
        DynamicUser = true;
        LoadCredential = "tunnel:/run/agents/tunnel-token";
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %d/tunnel";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };

  services.open-webui = {
    enable = true;
    host = "127.0.0.1";
    port = port "agents";
    environmentFile = "/run/agents/openrouter.env";
    environment = {
      OPENAI_API_BASE_URLS = "https://openrouter.ai/api/v1;http://127.0.0.1:${toString tier1Port}/v1";
      ENABLE_OLLAMA_API = "False";
      WEBUI_URL = "https://agents.${zone}";
      # Owner single sign-on: Cloudflare Access has verified the viewer, so
      # Open WebUI trusts the header instead of running its own login.
      # Reachable only on 127.0.0.1 through cloudflared (the tunnel sets this
      # header from Access's JWT), so no external actor can forge it.
      WEBUI_AUTH_TRUSTED_EMAIL_HEADER = "Cf-Access-Authenticated-User-Email";
      # ENABLE_SIGNUP off except for the trusted-header path, which the docs
      # say bypasses this gate for Access-verified identities.
      ENABLE_SIGNUP = "False";
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
    };
  };
}
