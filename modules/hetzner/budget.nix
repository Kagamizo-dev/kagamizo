# What the Hetzner account may cost a month, and what pays for it.
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
    payment = mkOption {
      type = types.submodule {
        options = {
          issuer = mkOption { type = types.enum [ "capital-one" ]; };
          kind = mkOption { type = types.enum [ "virtual-card" ]; };
          lockedTo = mkOption {
            type = types.str;
            description = "The one merchant the card is locked to.";
          };
          managedBy = mkOption {
            type = types.enum [ "owner" ];
            description = "Who mints and cancels it: the owner, outside the repo.";
          };
        };
      };
    };
  };
  config.hetzner = {
    monthlyBudgetUsd = 7;
    payment = {
      issuer = "capital-one";
      kind = "virtual-card";
      lockedTo = "Hetzner";
      managedBy = "owner";
    };
  };
}
