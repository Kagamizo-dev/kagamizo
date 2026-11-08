# Readiness for live trading: every step of the live lifecycle, and what
# exercises it today. The owner's rule (2026-11-07): paper trading must
# exercise every API and every piece of wiring, so that going live is a
# setting and nothing else. A step is exercised against Public's real
# backend every paper day (real), once by a deliberate real order (real-once,
# the canary), only against the stub in CI (stub), or not yet (none).
#
#   trading.readiness.<step> = { what; exercised; by; }
#
#   checks.trading-readiness  Lean (./_lean/Readiness.lean): no strategy is
#                             at stage live unless every step is exercised
#                             against the real backend
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.trading;
  q = builtins.toJSON;
in
{
  options.trading.readiness = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          what = mkOption { type = types.str; };
          exercised = mkOption {
            type = types.enum [
              "real"
              "real-once"
              "stub"
              "none"
            ];
          };
          by = mkOption {
            type = types.str;
            description = "The command, unit or test that exercises it.";
          };
        };
      }
    );
    default = { };
  };

  config = {
    trading.readiness = {
      sign-in = {
        what = "a Public access token from the host's secret";
        exercised = "real";
        by = "every paper day (trading-paper-day-*)";
      };
      account = {
        what = "the brokerage account read through the placer client";
        exercised = "real";
        by = "every rehearsal (trading-rehearse-*)";
      };
      market-data = {
        what = "event contracts, their details and quotes";
        exercised = "real";
        by = "every paper day";
      };
      signals = {
        what = "the live forecasts the weather rules price against";
        exercised = "real";
        by = "every paper day (Open-Meteo, NWS)";
      };
      risk = {
        what = "the limits' admissibility check (Lean's Risk.admissible)";
        exercised = "real";
        by = "every paper day and rehearsal";
      };
      preflight = {
        what = "Public validating the exact order, placing nothing";
        exercised = "real";
        by = "every paper day, and the rehearsal through the placer client";
      };
      place = {
        what = "the one call that places the order";
        exercised = "stub";
        by = "trade's test a_live_strategy_places_reads_back_and_records_the_position";
      };
      read-back = {
        what = "reading the order back until it ends";
        exercised = "stub";
        by = "trade's tests on place";
      };
      cancel = {
        what = "cancelling an order still working after the read-back";
        exercised = "stub";
        by = "trade's test an_order_still_working_is_cancelled_and_opens_nothing";
      };
      position = {
        what = "the day's open position recorded only on a fill";
        exercised = "stub";
        by = "trade's tests on place";
      };
      settlement = {
        what = "each recorded contract's outcome read and the ledger written";
        exercised = "real";
        by = "every paper settlement (trading-paper-settle-*)";
      };
      reconcile = {
        what = "the day's positions checked against Public's portfolio";
        exercised = "none";
        by = "not built";
      };
      ledger = {
        what = "the nightly read of the brokerage's books into the bank";
        exercised = "none";
        by = "money.ledger, off until the host reads Public's token";
      };
      approval = {
        what = "the owner's dated promotion and approval of each order, by a link";
        exercised = "none";
        by = "the plan's promotion decision; the link to the owner is not built";
      };
      agents = {
        what = "the agents' whole lifecycle (analysts, the bull and bear debate, the trader, risk, the portfolio manager) deciding the day for an agent-option strategy";
        exercised = "real";
        by = "the daily dry run on the host's small quantized model (trading-research-*), at no cost; the paid models only once credit returns";
      };
      observability = {
        what = "the paper days, rehearsals and settlements on the host's console";
        exercised = "real";
        by = "host-report, hourly";
      };
    };

    perSystem =
      { config, ... }:
      {
        checks.trading-readiness = config.kagamizo.leanCheck {
          name = "trading-readiness";
          source = ./_lean/Readiness.lean;
          facts = ''

            namespace Kagamizo.Readiness
            def steps : List Step := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (
                  n: s: "{ name := ${q n}, exercised := .${lib.replaceStrings [ "-o" ] [ "O" ] s.exercised} }"
                ) cfg.readiness
              )
            }]
            def strategies : List (String × Bool) := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (n: s: "(${q n}, ${lib.boolToString (s.stage == "live")})") cfg.strategies
              )
            }]

            theorem readiness_holds : sound steps strategies = true := by decide +kernel
            end Kagamizo.Readiness
          '';
        };
      };
  };
}
