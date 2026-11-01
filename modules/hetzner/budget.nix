# What the Hetzner account may cost a month; what pays for it is
# accounts.held.hetzner.payment (../accounts).
#
# The owner pays Hetzner with a Capital One virtual card locked to Hetzner
# (2026-10-24), which they mint and manage; it is not a Mercury card. The
# budget is the owner's $7 a month: the cheapest server with a fixed IPv4
# was $6.59 on Hetzner's own prices (GET /pricing, 2026-10-24). Hetzner has
# no spending limit of its own, so the host's plan (./infra.nix) reads its
# live prices and refuses declared resources that add up to more.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.hetzner = {
    monthlyBudgetUsd = mkOption {
      type = types.ints.positive;
      description = "Most the Hetzner account may cost a month, in dollars.";
    };
  };
  config.hetzner = {
    monthlyBudgetUsd = 7;
  };
}
