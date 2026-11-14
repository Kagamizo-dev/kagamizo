# OpenRouter as code: the models chat and code may use, and every API key,
# each scoped to one consumer with its own credit cap. Keys are minted by
# `openrouter apply` with the account's management key and piped straight
# into the consumer's secretspec profile; a value never reaches a terminal.
#
#   openrouter plan     every declared setting against the live one: keys
#                       (ours and the adopted signup key), the routing
#                       guardrails and their key assignments, the workspace's
#                       defaults; fails on drift or anything undeclared
#   openrouter apply    mint missing keys, set caps and disabled states,
#                       create or update the guardrails, set the workspace
#   openrouter models   check every declared model is still offered
#   openrouter credits  the account's balance
#   openrouter probe    measure endpoints for ./routing.nix
#
# (./wrapper.nix renders the declarations; the tool is Rust, ./_spend.)
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
      defaultModel = "deepseek/deepseek-v4.1-flash";
      # Open-weight models only. Flash is v4.1: for agent loops, which re-read
      # their context every step, its cache reads cost a tenth of v4's or
      # less (openrouter.spend, ./_spend/prices.json).
      models = [
        "deepseek/deepseek-v4.1-flash"
        "deepseek/deepseek-v4-pro"
        "qwen/qwen3.8-27b"
        "z-ai/glm-5.3"
        "moonshotai/kimi-k3"
        "openai/gpt-oss-120b"
        "meta-llama/llama-4-maverick"
        "mistralai/devstral-2512"
      ];
      keys = {
        # Open WebUI and OpenCode on the host (modules/kagamizo-host).
        chat-and-code = {
          profile = "host";
          limitUsd = 20;
          why = "agents.jingzo.org and code.jingzo.org";
        };
        # Orca's agents, started under `secretspec run --profile agent`.
        orca-fleet = {
          profile = "agent";
          limitUsd = 25;
          why = "the Orca agent fleet and the Kagamizo teams (modules/agents/teams.nix)";
        };
        # The research-to-trade loop (modules/research), the plan of
        # 2026-11-02: the owner's research budget.
        research = {
          profile = "research";
          limitUsd = 20;
          why = "the research loops of the trading plan (research-jingzo)";
        };
        # The agents' daily dry run on jingzo-host (the owner, 2026-11-08:
        # test the whole strategy on cheap models, pennies a day): its own
        # small cap, so a runaway dry run cannot touch the research budget.
        research-host = {
          profile = "research-host";
          limitUsd = 5;
          why = "the trading agents' daily dry run on jingzo-host (research --cheap)";
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
