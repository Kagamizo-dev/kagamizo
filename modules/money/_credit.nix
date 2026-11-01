# Every line of credit the owner holds, typed: who issues it, its limit,
# annual fee and age where known, what pays it each month, and its fate.
# Open dates and fees come off the credit report (accounts.held.experian)
# and the cards' statements; null is "not read yet", never a guess.
#
# The rules (checked below): every line's issuer is a declared account;
# every kept line is paid from Mercury once Chase's checking closes
# (modules/migration); a fee is never left unexplained.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.money.creditLines;
  line = types.submodule {
    options = {
      account = mkOption {
        type = types.enum (lib.attrNames config.accounts.held);
        description = "The issuer's login (accounts.held).";
      };
      product = mkOption { type = types.str; };
      limitUsd = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
      };
      annualFeeUsd = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
      };
      opened = mkOption {
        type = types.nullOr (types.strMatching "[0-9]{4}-[0-9]{2}");
        default = null;
      };
      autopayFrom = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The account its monthly payment is drawn from.";
      };
      fate = mkOption {
        type = types.enum [
          "keep"
          "downgrade"
          "close"
          "undecided"
        ];
        default = "undecided";
      };
      why = mkOption {
        type = types.str;
        default = "";
      };
    };
  };
  problems = lib.concatLists (
    lib.mapAttrsToList (
      n: l:
      lib.optional (
        l.fate != "close" && l.annualFeeUsd != null && l.annualFeeUsd > 0 && l.why == ""
      ) "money.creditLines.${n}: a $${toString l.annualFeeUsd} annual fee, kept without saying why"
      ++
        lib.optional
          (
            l.fate == "keep"
            && l.autopayFrom != null
            && !(lib.hasPrefix "mercury" l.autopayFrom)
            && !(config.migration.sources ? ${l.autopayFrom})
          )
          "money.creditLines.${n}: kept, but paid from ${l.autopayFrom}, which is neither Mercury nor being moved"
    ) cfg
  );
in
{
  options.money.creditLines = mkOption {
    type = types.attrsOf line;
    default = { };
  };
  config.money.creditLinesChecked =
    assert lib.assertMsg (problems == [ ]) (
      "modules/money/_credit.nix:\n" + lib.concatMapStrings (p: "  - ${p}\n") problems
    );
    cfg;

  # The owner's statement, 2026-11-01. Fates wait on the credit report's
  # open dates and the statements' fees, except Amazon Prime, which the
  # owner keeps; Chase's checking pays both Chase cards until it closes.
  config.money.creditLines = {
    chase-sapphire = {
      account = "chase-mirazo";
      product = "Chase Sapphire";
      autopayFrom = "chase-mirazo";
    };
    chase-amazon-prime = {
      account = "chase-mirazo";
      product = "Amazon Prime Visa";
      annualFeeUsd = 0;
      autopayFrom = "chase-mirazo";
      fate = "keep";
      why = "the owner's: it serves them directly (no fee with Prime)";
    };
    capital-one-venture-x = {
      account = "capital-one-mirazo";
      product = "Capital One Venture X";
      limitUsd = 10000;
    };
    capital-one-basic = {
      account = "capital-one-mirazo";
      product = "Capital One (basic)";
      limitUsd = 300;
    };
    discover = {
      account = "discover-mirazo";
      product = "Discover it";
      limitUsd = 2000;
    };
    credit-one = {
      account = "credit-one-mirazo";
      product = "Credit One Bank";
    };
  };
}
