# What agent work costs, held to a budget (the owner's rule of 2026-11-06:
# estimate and check every job's spend; never run blind into a limit).
# OpenRouter routes one model to many providers whose cache-read prices
# differ by up to 200×, and an agent loop re-reads its whole context every
# step: on 2026-11-05, 97% of the fleet key's prompt tokens were cache
# reads, billed at Parasail's $0.07/M against $0.001/M at the cheapest
# provider of deepseek-v4.1-flash. ./_spend (agent-spend) prices a job from
# ./_spend/prices.json, dated, per provider.
#
#   openrouter.spend = { jobBudgetUsd; allowedProviders; }
#
#   agent-spend estimate --model M --steps S --context C    before a job
#   agent-spend measure  --model M LOG.jsonl...             after a job
#   agent-spend run --model M --budget USD -- CMD...        the hard cap:
#       `dispatch` runs every team job under it, and it stops the job the
#       moment its cost at the dearest allowed provider reaches the budget
#
#   checks.agent-spend   the crate's tests (pricing, the event stream, the
#                        cap stopping a runaway job)
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.openrouter.spend;
  prices = lib.importJSON ./_spend/prices.json;
  fleet = config.openrouter.keys.orca-fleet.limitUsd;
in
{
  options.openrouter.spend = {
    jobBudgetUsd = mkOption {
      type = types.numbers.between 0.01 5.0;
      default = 0.25;
      description = "The most one dispatched job may spend, at the dearest allowed provider's prices.";
    };
    allowedProviders = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = config.openrouter.routing.agents.endpoints;
      description = "Derived: the endpoints the agents' routing class allows (./routing.nix), as exact tags.";
    };
  };

  config = {
    perSystem =
      { config, ... }:
      {
        packages.agent-spend =
          assert lib.assertMsg (cfg.jobBudgetUsd <= fleet)
            "openrouter.spend.jobBudgetUsd (${toString cfg.jobBudgetUsd}) is over the fleet key's limit (${toString fleet})";
          assert lib.assertMsg (
            prices.models ? ${top.openrouter.defaultModel}
          ) "openrouter.defaultModel ${top.openrouter.defaultModel} has no prices in ./_spend/prices.json";
          config.packages.openrouter-tools;
        checks.agent-spend = config.packages.openrouter-tools;
      };
  };
}
