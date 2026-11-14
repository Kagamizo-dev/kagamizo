# Where each strategy stands, and what it took to get there (the plan of
# 2026-11-02, part E): research, backtest, paper, live. A stage is declared
# with its evidence; Lean (./_lean/Stages.lean) proves nothing is live
# without a recorded backtest, paper days that held (enough of them, P&L
# not below zero, drawdown within 20%, from `trade paper-settle`'s ledger)
# and the owner's dated decision. `trade place` reads the stage from the declaration and
# refuses anything but live; `trade paper-day` records paper evidence.
#
#   trading.strategies.<s>.stage = "research" | "backtest" | "paper" | "live"
#   trading.strategies.<s>.promotion = {
#     backtest = { recorded; alpha; maxDrawdownPct; };   # to reach paper
#     paper = { days; from; to; pnlUsd; maxDrawdownPct; ledger; }  # to reach live
#     live = { decided; };                               # the owner's date
#   }
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.trading;
  q = builtins.toJSON;
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
  paperDaysNeeded = 5;
  strategy = types.submodule {
    options = {
      stage = mkOption {
        type = types.enum [
          "research"
          "backtest"
          "paper"
          "live"
        ];
        default = "backtest";
      };
      promotion = {
        backtest = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                recorded = mkOption {
                  type = date;
                  description = "The day the backtest was recorded (its grid and result kept under research/backtests).";
                };
                alpha = mkOption {
                  type = types.float;
                  description = "Annualised alpha over the benchmark, as the record states.";
                };
                maxDrawdownPct = mkOption { type = types.numbers.between 0.0 100.0; };
              };
            }
          );
          default = null;
        };
        paper = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                days = mkOption { type = types.ints.positive; };
                from = mkOption { type = date; };
                to = mkOption { type = date; };
                pnlUsd = mkOption {
                  type = types.number;
                  description = "The settled paper trades' P&L, as the ledger states it.";
                };
                maxDrawdownPct = mkOption { type = types.numbers.between 0.0 100.0; };
                ledger = mkOption {
                  type = types.str;
                  description = "The ledger the numbers are from: research/paper/ledger-<strategy>.json at a commit.";
                };
              };
            }
          );
          default = null;
        };
        live = mkOption {
          type = types.nullOr (types.submodule { options.decided = mkOption { type = date; }; });
          default = null;
        };
      };
    };
  };
  # The thresholds a backtest must meet to count (the plan's gate).
  backtestCounts = b: b != null && b.alpha > 0.0 && b.maxDrawdownPct <= 20.0;
  # Paper trading held: no loss over the days, and the drawdown within the
  # backtest's own bound. The day count is Lean's (paperDaysNeeded).
  paperHeld = p: p != null && p.pnlUsd >= 0 && p.maxDrawdownPct <= 20.0;
  facts = lib.mapAttrsToList (n: s: {
    name = n;
    inherit (s) stage;
    backtested = backtestCounts s.promotion.backtest;
    paperDays = if s.promotion.paper == null then 0 else s.promotion.paper.days;
    paperHeld = paperHeld s.promotion.paper;
    decided = s.promotion.live != null;
  }) cfg.strategies;
  rendered = ''
    namespace Kagamizo.Stages

    /-- Every declared strategy, rendered by modules/trading/stages.nix. -/
    def declared : List Strategy := [
    ${lib.concatMapStringsSep ",\n" (
      f:
      "  { name := ${q f.name}, stage := .${f.stage}, backtested := ${lib.boolToString f.backtested}, paperDays := ${toString f.paperDays}, paperHeld := ${lib.boolToString f.paperHeld}, decided := ${lib.boolToString f.decided} }"
    ) facts}
    ]

    /-- Every declared strategy is at a stage its evidence allows. -/
    theorem all_well_staged : declared.all wellStaged = true := by decide
    /-- The repository's count of paper days needed is Lean's. -/
    example : paperDaysNeeded = ${toString paperDaysNeeded} := rfl

    end Kagamizo.Stages
  '';
in
{
  options.trading.strategies = mkOption { type = types.attrsOf strategy; };

  config = {
    # The engine's reference example stays a backtest; the agents' strategy
    # starts at research until its first recorded backtest.
    trading.strategies = {
      ema-cross-spy.stage = "backtest";
      spy-agents.stage = "research";
      # The weather rules: paper first (the owner's framing of 2026-11-04),
      # and paper only after a recorded backtest over settled contracts.
      weather-rules.stage = "research";
      # Bitcoin on Public, the round-the-clock venue: research until its
      # first recorded backtest, its dry run daily meanwhile.
      btc-agents.stage = "research";
    };

    perSystem =
      { pkgs, ... }:
      {
        checks.trading-stages =
          pkgs.runCommand "trading-stages"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = rendered;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Stages.lean} "$factsPath" > Check.lean
              lean Check.lean
              touch $out
            '';
      };
  };
}
