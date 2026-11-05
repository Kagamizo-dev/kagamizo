# The cost report: every recurring cost, normalised to cents a month, drawn
# on the Mercury card that bills it, in one priced view. Cost is a dimension
# of performance — this is where it is totalled and bounded.
#
#   nix run .#cost -- report [--json]   every card: its monthly limit, the
#                                       draw on it (OpenRouter key caps, an
#                                       infra budget, or the subscription),
#                                       and the headroom; then the ceiling
#   nix run .#cost -- usage [--json]    the live OpenRouter spend per key
#                                       against its cap (needs a signed-in
#                                       session; `openrouter usage`)
#
# checks.cost-lean (./_lean/Cost.lean) proves every card's draw fits its
# limit, so nothing is committed that a card does not cover, and the sum of
# the limits is the whole monthly ceiling. Reads only declared values
# (mercury.cards, openrouter.keys, the infra budgets); no secret, no card.
{ lib, config, ... }:
let
  q = builtins.toJSON;
  cards = config.mercury.cards;
  keys = config.openrouter.keys;

  # To whole cents a month, from any of Mercury's / OpenRouter's intervals.
  perMonthCents =
    usd: interval:
    let
      c = usd * 100.0;
      m =
        {
          daily = c * 30.0;
          weekly = c * 4.0;
          monthly = c;
          yearly = c / 12.0;
        }
        .${interval};
    in
    builtins.floor (m + 0.5);

  keyCapsCents = lib.foldl' (n: k: n + perMonthCents k.limitUsd k.reset) 0 (lib.attrValues keys);

  # What actually bills a card: the OpenRouter keys' caps on the OpenRouter
  # card, an infra budget on its card, else the subscription itself (its
  # limit is the committed ceiling).
  drawCents =
    name: card:
    let
      lim = perMonthCents card.limitUsd card.interval;
    in
    if name == "openrouter" then
      keyCapsCents
    else if name == "hetzner" then
      perMonthCents config.hetzner.monthlyBudgetUsd "monthly"
    else if name == "cloudflare" then
      perMonthCents config.cloudflare.monthlyBudgetUsd "monthly"
    else
      lim;
  coversOf =
    name:
    {
      openrouter = "the agents' and units' model keys";
      hetzner = "the always-on host";
      cloudflare = "domains and the edge";
    }
    .${name} or "a subscription";

  rows = lib.mapAttrsToList (name: card: {
    inherit name;
    limitCents = perMonthCents card.limitUsd card.interval;
    draw = drawCents name card;
    inherit (card) interval why account;
    covers = coversOf name;
  }) cards;

  problems = map (
    r: "cost: ${r.name} draws ${toString r.draw}c against a ${toString r.limitCents}c/month limit"
  ) (lib.filter (r: r.draw > r.limitCents) rows);

  lean = ''
    namespace Kagamizo.Cost

    def declared : List Card := [
    ${lib.concatMapStringsSep ",\n" (
      r:
      "  { name := ${q r.name}, limitCents := ${toString r.limitCents}, drawCents := ${toString r.draw} }"
    ) rows}
    ]

    theorem declared_bounded : bounded declared = true := by decide +kernel

    end Kagamizo.Cost
  '';

  rust = ''
    pub const CARDS: &[Card] = &[
    ${
      lib.concatMapStrings (r: ''
        Card { name: ${q r.name}, limit_cents: ${toString r.limitCents}, draw_cents: ${toString r.draw}, interval: ${q r.interval}, covers: ${q r.covers}, account: ${q r.account}, why: ${q r.why} },
      '') rows
    }];
    pub const KEY_CAPS_CENTS: u64 = ${toString keyCapsCents};
  '';
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      facts = pkgs.writeText "cost-facts.rs" rust;
      bin = pkgs.rustPlatform.buildRustPackage {
        pname = "cost";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        COST_FACTS = facts;
        meta.mainProgram = "cost";
      };
      # `usage` shells out to the signed-in openrouter CLI; `report` needs
      # nothing live.
      cost = pkgs.writeShellApplication {
        name = "cost";
        runtimeInputs = [ config.packages.openrouter ];
        text = ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          exec ${lib.getExe bin} "$@"
        '';
      };
    in
    {
      packages.cost = cost;
      checks = {
        cost-lean =
          assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
          pkgs.runCommand "cost-lean"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = lean;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Cost.lean} "$factsPath" > Check.lean
              lean Check.lean
              touch $out
            '';
        cost-tests = bin.overrideAttrs (_: {
          doCheck = true;
        });
      };
    };
}
