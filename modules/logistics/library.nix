# modules/logistics in the shell's library (../shell): a card on the work
# shelf, opening the module's page. Its view is generated from the
# declarations, so what the owner sees on the Yoga or the phone is the
# same data Lean checks: the wearable kit pocket by pocket, the vest's
# should-cost, the hubs, and every channel by how it is reached.
{ lib, config, ... }:
let
  cfg = config.logistics;
  items = config.kit.items;
  holds =
    slot:
    lib.concatStringsSep ", " (
      lib.mapAttrsToList (n: _: n) (lib.filterAttrs (_: i: i.slot == slot) items)
    );
  pockets =
    g:
    lib.concatStringsSep "; " (
      lib.mapAttrsToList (
        s: ml: "${s} ${toString ml} ml${lib.optionalString (holds s != "") " (${holds s})"}"
      ) g.pockets
    );
  byAccess =
    want:
    lib.filterAttrs (_: c: lib.any (o: lib.elem o.access want) (lib.attrValues c.ops)) cfg.channels;
  channelRows =
    want:
    lib.mapAttrsToList (n: c: {
      title = n;
      detail = "${c.kind}, ${lib.concatStringsSep "/" c.regions}: ${
        lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: v: lib.elem v.access want) c.ops))
      }";
    }) (byAccess want);
  vest = cfg.outfit.garments.vest.bom;
  inherit (cfg) sla;
  # Minutes as the owner reads them.
  span =
    m:
    if m >= 1440 then
      "${toString (m / 1440)} d${
        lib.optionalString (lib.mod m 1440 >= 60) " ${toString (lib.mod m 1440 / 60)} h"
      }"
    else if m >= 60 then
      "${toString (m / 60)} h"
    else
      "${toString m} min";
  backing =
    s:
    if s.basis == "stated" then
      "the provider's own figure"
    else if s.assumption != null && sla.assumptions.${s.assumption}.backing != [ ] then
      "backed: ${(lib.head sla.assumptions.${s.assumption}.backing).ref}"
    else
      "not yet backed";
  breach =
    s:
    if s.onBreach == "reroute" then
      "reroute to ${s.fallback} (${sla.steps.${s.fallback}.channel}, ${
        span sla.steps.${s.fallback}.boundMin
      })"
    else if s.onBreach == "retry" then
      "retry once"
    else
      "fail, the step named";
  stepRow = n: {
    title = "${n}: ${sla.steps.${n}.channel}, within ${span sla.steps.${n}.boundMin}";
    detail = "then ${breach sla.steps.${n}}; ${backing sla.steps.${n}}";
  };
  onPaths = lib.unique (lib.concatMap (p: lib.concatLists p.stages) (lib.attrValues sla.paths));
  offPaths = lib.filter (
    n: !(lib.elem n onPaths) && !(lib.any (s: s.fallback == n) (lib.attrValues sla.steps))
  ) (lib.attrNames sla.steps);
  priced = lib.filterAttrs (_: r: r.cents != null) cfg.rates;
in
{
  shell.apps."logistics" = {
    name = "Logistics";
    category = "work";
    kind = "module";
    module = "logistics";
    description = "From a specification to a thing in hand: the kit, should-costs, hubs, channels ranked by reliability";
    view = [
      {
        title = "The wearable kit (no pack)";
        rows = lib.mapAttrsToList (n: g: {
          title = "${n}: ${g.kind}, at most ${toString g.massG} g";
          detail = "${g.shell.fibre}; ${if g.pockets == { } then "no device pockets" else pockets g}";
        }) cfg.outfit.garments;
      }
      {
        title = "No step waits: every path within ${span sla.targetLeadMin}";
        rows = lib.concatLists (
          lib.mapAttrsToList (
            n: p:
            [
              {
                title = "${n}, delivered in ${p.destination}";
                detail = "${p.why}. Stages run in order, the steps of a stage side by side; ${toString sla.unbackedBaseline} deadlines rest on nothing measured yet, a count that only falls";
              }
            ]
            ++ lib.concatLists (
              lib.imap1 (
                i: stage:
                map (
                  step:
                  stepRow step
                  // {
                    title = "stage ${toString i} · ${(stepRow step).title}";
                  }
                ) stage
              ) p.stages
            )
          ) sla.paths
        );
      }
      {
        title = "What each deadline of ours rests on";
        rows = lib.mapAttrsToList (n: a: {
          title = "${n}: ${if a.backing == [ ] then "not yet backed" else "backed"}";
          detail = "${a.claim}. ${
            if a.backing == [ ] then
              "Wants: ${a.wants}"
            else
              lib.concatMapStringsSep "; " (b: "${b.kind}, ${b.on}: ${b.ref}") a.backing
          }";
        }) sla.assumptions;
      }
      {
        title = "Declared, on no path yet";
        rows = map (n: {
          title = "${n}: ${sla.steps.${n}.channel}, ${span sla.steps.${n}.boundMin}";
          detail = sla.steps.${n}.note;
        }) offPaths;
      }
      {
        title = "No bounded channel yet";
        rows = lib.mapAttrsToList (n: why: {
          title = n;
          detail = why;
        }) sla.open;
      }
      {
        title = "Kept off every path";
        rows = lib.mapAttrsToList (n: why: {
          title = n;
          detail = why;
        }) sla.excluded;
      }
      {
        title = "Should-cost";
        rows = [
          {
            title = "vest, ${toString vest.quantity} units";
            detail = "${toString (lib.length vest.materials)} materials, ${toString (lib.length vest.operations)} operations; ${toString (lib.length (lib.attrNames priced))} of ${toString (lib.length (lib.attrNames cfg.rates))} rates priced; quotes accepted up to ${toString cfg.quotes.premiumPct}% above, ${cfg.quotes.incoterm}, inspection level ${cfg.quotes.inspection.level}";
          }
        ];
      }
      {
        title = "Hubs";
        rows = lib.mapAttrsToList (n: h: {
          title = "${n} (${h.status})";
          detail = "${lib.concatStringsSep " " h.airports}: ${h.why}";
        }) cfg.hubs;
      }
      {
        title = "Keyless: no account";
        rows = channelRows [ "keyless" ];
      }
      {
        title = "Needs an account or a contract";
        rows = channelRows [
          "open"
          "gated"
          "partner"
        ];
      }
      {
        title = "By hand only";
        rows = lib.mapAttrsToList (n: c: {
          title = n;
          detail = "${c.kind}, terms ${c.terms.position}${lib.optionalString (c.note != null) ": ${c.note}"}";
        }) (lib.filterAttrs (_: c: lib.all (o: o.access == "none") (lib.attrValues c.ops)) cfg.channels);
      }
    ];
  };
}
