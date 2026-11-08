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
