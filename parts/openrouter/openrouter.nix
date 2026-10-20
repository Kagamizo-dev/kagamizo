# OpenRouter as code: the models chat and code may use, and every API key,
# each scoped to one consumer with its own credit cap. Keys are minted by
# `openrouter apply` with the account's management key and piped straight
# into the consumer's secretspec profile; a value never reaches a terminal.
#
#   openrouter plan     declared keys against the live ones (names, caps,
#                       usage) and whether each one's secret is stored
#   openrouter apply    create missing keys, correct caps, re-mint a key whose
#                       secret is gone (its value cannot be read back)
#   openrouter models   check every declared model is still offered
#   openrouter credits  the account's balance
#
# The management key itself is the one value made by hand (a Gap): created in
# the dashboard after signup, saved as Kagamizo-LLC/openrouter-management-key.
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.openrouter;
  inherit (config.proton.secretspec) profiles;

  key = types.submodule {
    options = {
      profile = mkOption {
        type = types.enum (lib.attrNames profiles);
        description = "The secretspec profile the key is stored in.";
      };
      variable = mkOption {
        type = types.strMatching "[A-Z][A-Z0-9_]*";
        default = "OPENROUTER_API_KEY";
      };
      limitUsd = mkOption {
        type = types.ints.positive;
        description = "Credit cap, in dollars, per reset period.";
      };
      reset = mkOption {
        type = types.enum [
          "daily"
          "weekly"
          "monthly"
        ];
        default = "monthly";
      };
      why = mkOption { type = types.str; };
    };
  };
in
{
  options.openrouter = {
    account = mkOption {
      type = types.enum (lib.attrNames config.accounts.held);
    };
    defaultModel = mkOption {
      type = types.str;
      description = "The model chat and code start on.";
    };
    models = mkOption {
      type = types.listOf types.str;
      description = "Every model offered in chat and code; `openrouter models` checks each exists.";
    };
    keys = mkOption {
      type = types.attrsOf key;
      default = { };
    };
  };

  config = {
    openrouter = {
      account = "openrouter";
      defaultModel = "deepseek/deepseek-v4-flash";
      # Open-weight models only.
      models = [
        "deepseek/deepseek-v4-flash"
        "deepseek/deepseek-v4-pro"
        "qwen/qwen3.8-27b"
        "z-ai/glm-5.3"
        "moonshotai/kimi-k3"
        "openai/gpt-oss-120b"
        "meta-llama/llama-4-maverick"
        "mistralai/devstral-2512"
      ];
      keys = {
        # Open WebUI and OpenCode on the host (devices/kagamizo-host).
        chat-and-code = {
          profile = "host";
          limitUsd = 20;
          why = "chat.kagamizo.com and code.kagamizo.com";
        };
        # Orca's agents, started under `secretspec run --profile agent`.
        orca-fleet = {
          profile = "agent";
          limitUsd = 20;
          why = "the Orca agent fleet";
        };
      };
    };

    accounts.demands = [
      {
        inherit (cfg) account;
        capability = "managementKeys";
        need = true;
        why = "openrouter apply mints every key";
      }
      {
        inherit (cfg) account;
        capability = "keyCreditLimits";
        need = true;
        why = "openrouter.keys.*.limitUsd";
      }
    ];
  };
}
