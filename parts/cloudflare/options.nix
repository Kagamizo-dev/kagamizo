# The Cloudflare account: non-secret facts and the API token profiles.
# Checked against ../_lib/types.nix; consumers read `cloudflare.checked`.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  t = import ../_lib/types.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  cfg = config.cloudflare;

  profile = types.submodule {
    options = {
      zone = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Permission group names, granted on every declared zone.";
      };
      account = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Permission group names, granted on the account.";
      };
      allZones = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Zone permission group names, granted on every zone in the account, including ones bought later.";
      };
    };
  };
in
{
  options.cloudflare = {
    accountId = mkOption { type = types.str; };
    stateBucket = mkOption { type = types.str; };
    tokenExpiry = mkOption { type = types.str; };
    monthlyBudgetUsd = mkOption { type = types.number; };
    tokens = mkOption {
      type = types.attrsOf profile;
      default = { };
    };
    checked = mkOption {
      type = types.raw;
      readOnly = true;
    };
  };

  # Also checks that the declared registrations fit the monthly budget.
  config.cloudflare.checked =
    builtins.seq (t.budget cfg.monthlyBudgetUsd config.identity.checked.domains) (
      t.cloudflare {
        inherit (cfg)
          accountId
          stateBucket
          tokenExpiry
          monthlyBudgetUsd
          ;
      }
    )
    // {
      inherit (cfg) tokens;
    };
}
