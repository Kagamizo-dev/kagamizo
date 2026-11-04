# DeepSeek Harness on jingzo-host (../dsh): its web UI on the loopback,
# reached through the agents tunnel at harness.<zone> behind Access. Its
# profile is the shipped `web` one under a patch this file renders from
# the declarations: OpenRouter as the provider with the declared
# open-weight models (the capped chat-and-code key from /run/agents, the
# same Open WebUI holds), the host's free tier-1 model beside it, and the
# default model the repo names. The harness's own state (sessions, the
# plugins its agents add) lives in /var/lib/dsh; what should outlive the
# host goes to the repository as a pull request (modules/governance/changes.nix).
{
  zone,
  port,
  tier1Port,
  dsh,
  models,
  defaultModel,
  smallModel,
}:
{ pkgs, lib, ... }:
let
  host = "harness.${zone}";
  model = id: {
    inherit id;
    name = id;
  };
  patch = pkgs.writeText "kagamizo.patch.json" (
    builtins.toJSON [
      {
        id = "llm";
        config.providers = {
          openrouter = {
            displayName = "OpenRouter (Jingzo's capped key)";
            api = "openai-completions";
            baseURL = "https://openrouter.ai/api/v1";
            apiKeyEnv = "OPENROUTER_API_KEY";
            models = map model models;
            compat.thinkingFormat = "openrouter";
          };
          host = {
            displayName = "jingzo-host tier 1 (free)";
            api = "openai-completions";
            baseURL = "http://127.0.0.1:${toString tier1Port}/v1";
            apiKey = "local";
            models = [ (model smallModel) ];
            defaultContextWindow = 8192;
            defaultMaxTokens = 2048;
          };
        };
      }
      {
        id = "agent-default-model";
        config = {
          provider = "openrouter";
          model = defaultModel;
        };
      }
    ]
  );
in
{
  systemd.services.dsh-web = {
    description = "DeepSeek Harness, web UI";
    wantedBy = [ "multi-user.target" ];
    after = [
      "agents-secrets.service"
      "llama-cpp.service"
    ];
    requires = [ "agents-secrets.service" ];
    environment = {
      DSH_HOME = "/var/lib/dsh";
      HOME = "/var/lib/dsh";
    };
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "dsh";
      WorkingDirectory = "/var/lib/dsh";
      EnvironmentFile = "/run/agents/openrouter.env";
      ExecStart = lib.concatStringsSep " " [
        (lib.getExe dsh)
        "--profile web"
        "--patch ${patch}"
        "--host 127.0.0.1"
        "--port ${toString port}"
        "--no-open"
        "--public-url https://${host}/"
        "--trusted-host ${host}"
      ];
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
