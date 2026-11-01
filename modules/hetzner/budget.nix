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
    # $7 for the host; $27 while the migration's staging volume exists (the
    # owner raised it on 2026-11-01 when Hetzner's live prices put the host,
    # its IPv4 and 250 GB at $25.77 with cpx11; the apply then found cpx11
    # withdrawn from the EU locations since 2025-12-31, and cx23, the
    # cheapest type still sold there, makes it $26.26: ./_json/prices.json
    # keeps every observation). Back to 7 when hetzner.volumes is empty.
    monthlyBudgetUsd = 27;
    # cx23 (2 cores, 4 GB, 40 GB; $6.49 in fsn1 on 2026-11-01): cpx11 is no
    # longer ordered in the EU.
    host.serverType = "cx23";
    volumes.staging = {
      sizeGb = 250;
      why = "staging for the migration off Apple, Google and Outlook (modules/migration): photos, drives and the full archives on their way to Proton Drive";
      until = "2027-01-31";
    };
  };
}
