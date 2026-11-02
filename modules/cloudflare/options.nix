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
      storeIn = mkOption {
        type = types.nonEmptyListOf types.str;
        description = "secretspec profiles whose vaults receive the minted value.";
      };
    };
  };
in
{
  options.cloudflare = {
    accountId = mkOption { type = types.str; };
    tokenExpiry = mkOption { type = types.str; };
    monthlyBudgetUsd = mkOption { type = types.number; };
    tokens = mkOption {
      type = types.attrsOf profile;
      default = { };
    };
    # Which OAuth scope of the root sign-in covers each permission group a
    # token holds. Cloudflare enforces it: a sign-in can mint only groups
    # its scopes cover ("The OAuth session does not include the scopes
    # required for the requested permission groups", 2026-11-01, Billing
    # Read), and every group below was minted under its scope.
    # modules/tokens proves each token's groups are covered.
    groupScopes = mkOption {
      type = types.attrsOf (types.enum (lib.importJSON ../catalog/_json/cf.json).oauthScopes);
      default = { };
      description = "Permission group name -> the cf OAuth scope that covers it.";
    };
    # Live objects the state adopts (OpenTofu import blocks), by address:
    # how a lost state is rebuilt from Cloudflare without touching it. Once
    # the state holds them, each import is a no-op.
    imports = mkOption {
      type = types.attrsOf (types.strMatching "[0-9a-f]{32}/[A-Za-z0-9_-]+");
      default = { };
      description = "Resource address -> import id (<zone or account id>/<object id>).";
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
          tokenExpiry
          monthlyBudgetUsd
          ;
      }
    )
    // {
      inherit (cfg) tokens;
    };
}
