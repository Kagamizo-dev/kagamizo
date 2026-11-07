# Paper trading on jingzo-host (the owner's go of 2026-11-06: validate the
# research and trading teams on paper before live money). Each day, for
# each paper strategy, `trade paper-day` records the day's proposal (priced
# and preflighted at Public, placed nowhere), and `trade paper-settle`
# settles every recorded day whose contract Public has settled, writing the
# ledger whose P&L and drawdown are the paper evidence ./stages.nix gates
# live on. Both are deterministic (the weather rules, tier 0): no model, no
# credit.
#
#   trading.paper = { enable; strategies; dayAt; settleAt; agent; dir; }
#
# The units run as trading-mirazo, a read-only agent of the owner's (the
# account is theirs: modules/agents/charters.nix tradingAccountOwner), whose
# one grant is reading the brokerage; Cedar keeps spend from every agent.
# They start `trade` through trading-host (./_rust/trade/src/host.rs),
# which signs pass-cli in with the host's token, so no shell is involved.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  eventRule = lib.attrNames (
    lib.filterAttrs (_: s: s.kind == "event-rule") config.trading.strategies
  );
in
{
  options.trading.paper = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Run the paper days and their settlement on jingzo-host.";
    };
    strategies = mkOption {
      type = types.listOf (types.enum eventRule);
      default = [ ];
      description = "The event-rule strategies papered daily (paper-settle settles event contracts).";
    };
    dayAt = mkOption {
      type = types.str;
      default = "*-*-* 14:17:00 UTC";
      description = "When the day's proposal is recorded (systemd OnCalendar): mid-morning in New York, tomorrow's weather contracts listed.";
    };
    settleAt = mkOption {
      type = types.str;
      default = "*-*-* 13:43:00 UTC";
      description = "When the recorded days are settled, before the day's proposal.";
    };
    agent = mkOption {
      type = types.enum (lib.attrNames config.governance.agents);
      default = "trading-mirazo";
      description = "The governance agent the units act as.";
    };
    dir = mkOption {
      type = types.str;
      default = "/var/lib/kagamizo/trading";
      description = "Where the strategies' decisions directories live on the host (research/ under it).";
    };
  };

  config = {
    governance.agents.trading-mirazo = {
      serves = "mirazo";
      purpose = "the owner's brokerage, read-only: the deterministic paper days and their settlement (tier 0, no model)";
      personas = [ "finance/finance-fpa-analyst" ];
      grants = [
        {
          account = "public-mirazo";
          effects = [ "read" ];
          why = "paper days: event contracts, quotes and preflights, which place nothing, and their settlement (trading.paper)";
        }
      ];
    };

    trading.paper = {
      enable = true;
      strategies = [ "weather-rules" ];
    };
  };
}
