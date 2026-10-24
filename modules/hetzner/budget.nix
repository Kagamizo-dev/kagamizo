# What the Hetzner account may cost a month, all of it: the owner's $5
# (2026-10-24). The host's plan reads Hetzner's own prices (GET /pricing)
# and refuses a declared server and address that add up to more.
{ lib, ... }:
{
  options.hetzner.monthlyBudgetUsd = lib.mkOption {
    type = lib.types.ints.positive;
    description = "Most the Hetzner account may cost a month, in dollars.";
  };
  config.hetzner.monthlyBudgetUsd = 5;
}
