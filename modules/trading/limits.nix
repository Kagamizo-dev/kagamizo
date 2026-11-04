# The trading limits, as the owner set them (2026-11-02): the seed, the
# most one trade may lose, how many positions may be open, when the day
# stops, and which trades are allowed at all (each with a known worst case
# at entry). Every proposal is held to `admissible` (./_lean/Risk.lean)
# before Public's preflight, and `trade place` holds it again.
#
#   trading.limits.<backend> = { seedUsd; maxPremiumUsd; maxOpenPositions;
#                                dailyLossStopUsd; allowed; }
#
# checks.trading-risk: Lean proves what admissible guarantees (an order
# loses at most the cap; a day loses at most stop plus cap; a stopped day
# or a full book admits nothing) and decides the declared limits are sane.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.trading.limits;
  q = builtins.toJSON;
  kinds = [
    "long-call"
    "long-put"
    "debit-spread"
  ];
  camel =
    k:
    lib.replaceStrings [ "long-call" "long-put" "debit-spread" ] [ "longCall" "longPut" "debitSpread" ]
      k;
  limits = types.submodule {
    options = {
      seedUsd = mkOption {
        type = types.ints.positive;
        description = "What the account is funded with; nothing above it is ever at risk.";
      };
      maxPremiumUsd = mkOption {
        type = types.ints.positive;
        description = "The most one trade may cost, and so lose.";
      };
      maxOpenPositions = mkOption { type = types.ints.positive; };
      dailyLossStopUsd = mkOption {
        type = types.ints.positive;
        description = "Once the day has lost this much, nothing more is proposed.";
      };
      allowed = mkOption {
        type = types.nonEmptyListOf (types.enum kinds);
        description = "Defined-risk kinds only: a long option or a debit spread.";
      };
    };
  };
  rendered = ''
    namespace Kagamizo.Risk

    /-- The declared limits, rendered by modules/trading/limits.nix. -/
    def declared : List (String × Limits) := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: l:
        "  (${q n}, { seedUsd := ${toString l.seedUsd}, maxPremiumUsd := ${toString l.maxPremiumUsd}, maxOpenPositions := ${toString l.maxOpenPositions}, dailyLossStopUsd := ${toString l.dailyLossStopUsd}, allowed := [${
            lib.concatMapStringsSep ", " (k: ".${camel k}") l.allowed
          }] })"
      ) cfg
    )}
    ]

    /-- A trade's cap and the day's stop never exceed the seed, and a full
    day of losses at the stop plus one more cap stays within twice the seed. -/
    theorem declared_sane :
        declared.all (fun (_, l) =>
          l.maxPremiumUsd ≤ l.seedUsd && l.dailyLossStopUsd ≤ l.seedUsd &&
          l.dailyLossStopUsd + l.maxPremiumUsd ≤ 2 * l.seedUsd) = true := by decide

    end Kagamizo.Risk
  '';
in
{
  options.trading.limits = mkOption {
    type = types.attrsOf limits;
    default = { };
    description = "Per backend (trading.backends).";
  };

  config = {
    trading.limits.public = {
      seedUsd = 100;
      maxPremiumUsd = 25;
      maxOpenPositions = 1;
      dailyLossStopUsd = 25;
      allowed = [
        "long-call"
        "long-put"
        "debit-spread"
      ];
    };

    perSystem =
      { pkgs, ... }:
      {
        checks.trading-risk =
          assert lib.assertMsg (lib.all (b: config.trading.backends ? ${b}) (
            lib.attrNames cfg
          )) "trading.limits names a backend that is not declared";
          pkgs.runCommand "trading-risk"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = rendered;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Risk.lean} "$factsPath" > Check.lean
              lean Check.lean
              touch $out
            '';
      };
  };
}
