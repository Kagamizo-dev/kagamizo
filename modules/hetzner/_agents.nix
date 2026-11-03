# The always-on agents on jingzo-host (./agents.nix): Open WebUI and
# OpenCode on the loopback, reached only through the agents tunnel behind
# Access (../cloudflare/_agents.nix). No port is open.
#
#   agents-secrets   once a boot: the OpenRouter key (chat-and-code, capped)
#                    and the tunnel token, from the host's read-only vault,
#                    into /run/agents (mode 600, never printed)
#   open-webui       Open WebUI on OpenRouter, signing in whoever Access let
#                    through (Cf-Access-Authenticated-User-Email)
#   opencode-web     OpenCode's web interface, with the repo's OpenCode
#                    config (OpenRouter only, the declared open-weight models)
#   cloudflared      the tunnel, dialling out with its token as a credential
{
  services,
  zone,
  passCli,
  secretspec,
  secretspecToml,
  opencodeConfig,
  tokenFile,
}:
{ lib, pkgs, ... }:
let
  port = name: (lib.findFirst (s: s.name == name) (throw "agents: no service ${name}") services).port;
  # agents-secrets itself waits for the network.
  after = [ "agents-secrets.service" ];
in
{
  # Open WebUI's licence (BSD-3 with a branding clause, nixpkgs: unfree)
  # allows self-hosting with its branding kept; the one exception admitted.
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "open-webui";

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
        printf 'OPENAI_API_KEY=%s\nOPENROUTER_API_KEY=%s\n' "$key" "$key" >/run/agents/openrouter.env
        unset key
        get TUNNEL_TOKEN >/run/agents/tunnel-token
        [ -s /run/agents/tunnel-token ] || { echo "agents-secrets: no tunnel token yet (infra-tunnel-token)" >&2; exit 1; }
      '';
    };

    open-webui = {
      inherit after;
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
      OPENAI_API_BASE_URL = "https://openrouter.ai/api/v1";
      ENABLE_OLLAMA_API = "False";
      WEBUI_URL = "https://agents.${zone}";
      # Access has signed the viewer in: Open WebUI takes its address.
      WEBUI_AUTH_TRUSTED_EMAIL_HEADER = "Cf-Access-Authenticated-User-Email";
      ENABLE_SIGNUP = "False";
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
    };
  };
}
