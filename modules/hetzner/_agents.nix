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
#                    Discord relay's env when its token is there, and each
#                    dsh team's Access service token as /run/agents/<team>.env
#   open-webui       Open WebUI on OpenRouter, signing in whoever Access let
#                    through (Cf-Access-Authenticated-User-Email)
#   opencode-web     OpenCode's web interface, with the repo's OpenCode
#                    config (OpenRouter only, the declared open-weight models)
#   cloudflared      the tunnel, dialling out with its token as a credential
{
  services,
  openWebuiEnvironment, # openWebui.environment
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

  # DSH agent teams that get Cloudflare Access service tokens
  # (matching modules/cloudflare/_agents-access.nix).
  dshAgentTeams = [
    "review"
    "research-jingzo"
    "design"
    "twin"
    "builders"
    "upkeep"
  ];

  # The secretspec variable name for a team: upper case, hyphens -> underscores.
  svcTokenVar =
    name: lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] name) + "_ACCESS_SERVICE_TOKEN";
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
        pkgs.jq
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
        # Each dsh team's Access service token: JSON {client_id, client_secret}
        # in a note, parsed into CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET.
        ${lib.concatStringsSep "\n" (
          builtins.map (team: ''
            token=$(get ${svcTokenVar team} 2>/dev/null || true)
            if [ -n "$token" ]; then
              cid=$(jq -r '.client_id // empty' <<<"$token")
              cs=$(jq -r '.client_secret // empty' <<<"$token")
              if [ -n "$cid" ] && [ -n "$cs" ]; then
                printf 'CF_ACCESS_CLIENT_ID=%s\nCF_ACCESS_CLIENT_SECRET=%s\n' "$cid" "$cs" >/run/agents/${team}.env
              else
                echo "agents-secrets: ${team} Access service token is missing client_id or client_secret" >&2
              fi
            else
              echo "agents-secrets: no ${team} Access service token yet (infra-service-tokens)" >&2
            fi
            unset token cid cs
          '') dshAgentTeams
        )}
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
    # Every switch decided and the settings, typed and bounded
    # (./open-webui.nix, checks.open-webui).
    environment = openWebuiEnvironment;
  };
}
