# Logistics: from a specification to a thing in the owner's hands,
# anywhere, reliability first and price last (the owner's rule,
# 2026-11-08). Owned by Mirazo, the owner himself, until an LLC earns its
# keep (the owner's decision, 2026-11-08). Every order waits on the owner's
# approval of the payment; agents search, specify, quote and rank.
#
#   logistics.channels.<c>  a marketplace, resale site, maker, carrier,
#                           courier or holding point, and per operation
#                           (search, specs, quote, order, track, locate,
#                           collect, proof) how software reaches it, with
#                           the page that says so (./channels.nix)
#   logistics.hubs.<h>      where things land, by airport (./outfit.nix)
#   logistics.outfit        the first order: the garments that carry the
#                           kit, typed down to pockets and fabric
#
#   packages.logistics-book  everything above as JSON
#   packages.logistics       the CLI: channels, hubs, outfit, rank
#   checks.logistics         Lean (./_lean/Logistics.lean): no channel
#                            whose terms forbid automation is automated;
#                            every region has a hub and there is one home;
#                            the outfit carries every device of the kit
#                            with no pack; and the route chosen is the
#                            most reliable that meets the deadline
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.logistics;
  q = builtins.toJSON;
  url = types.strMatching "https://.+";
  evidence = types.enum [
    "page"
    "snippet"
    "secondary"
  ];
  slug = types.strMatching "[a-z][a-z0-9-]*";

  ops = [
    "search"
    "specs"
    "quote"
    "order"
    "track"
    "locate"
    "collect"
    "proof"
    "standards"
    "reliability"
    "tariff"
    "routes"
    "disruption"
    "rates"
  ];

  op = types.submodule {
    options = {
      access = mkOption {
        type = types.enum [
          "keyless"
          "open"
          "gated"
          "partner"
          "none"
        ];
        description = "keyless: no account at all; open: a self-serve key; gated: an account or approval first; partner: a contract; none: by hand.";
      };
      source = mkOption { type = url; };
      evidence = mkOption { type = evidence; };
    };
  };

  channel = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "marketplace"
          "resale"
          "maker"
          "data"
          "carrier"
          "courier"
          "holding"
        ];
      };
      regions = mkOption { type = types.nonEmptyListOf (types.enum (cfg.regions ++ [ "global" ])); };
      goods = mkOption {
        type = types.nonEmptyListOf (
          types.enum [
            "general"
            "apparel"
            "electronics"
            "parcels"
          ]
        );
        default = [ "general" ];
        description = "What it sells, makes or carries.";
      };
      terms = {
        position = mkOption {
          type = types.enum [
            "allowed"
            "api-only"
            "forbidden"
            "unknown"
          ];
        };
        source = mkOption { type = url; };
        evidence = mkOption { type = evidence; };
      };
      ops = mkOption {
        # Only the declared operations, so a misspelt one fails evaluation.
        type = types.addCheck (types.attrsOf op) (a: lib.all (n: lib.elem n ops) (lib.attrNames a));
        description = "Per operation (${lib.concatStringsSep ", " ops}), how software reaches it.";
      };
      protection = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "What protects the buyer: a guarantee, escrow, authentication.";
      };
      guarantee = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "A carrier's money-back guarantee, as it stands.";
      };
      prior = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              onTimeBp = mkOption { type = types.ints.between 0 10000; };
              source = mkOption { type = url; };
              evidence = mkOption { type = evidence; };
            };
          }
        );
        default = null;
        description = "Published on-time rate, in basis points: the reliability prior before our own deliveries.";
      };
      account = mkOption {
        type = types.nullOr (types.enum (lib.attrNames config.accounts.held));
        default = null;
        description = "The held account it is reached through; none is held yet.";
      };
      note = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  hub = types.submodule {
    options = {
      region = mkOption { type = types.enum cfg.regions; };
      airports = mkOption { type = types.nonEmptyListOf (types.strMatching "[A-Z]{3}"); };
      status = mkOption {
        type = types.enum [
          "home"
          "chosen"
          "candidate"
        ];
      };
      why = mkOption { type = types.str; };
    };
  };

  kitSlots = lib.attrNames config.kit.slots;

  garment = types.submodule {
    options = {
      # No backpack, bag or case: the owner wears everything.
      kind = mkOption {
        type = types.enum [
          "vest"
          "sleeve"
          "trousers"
          "belt"
          "cloak"
          "hardware"
        ];
      };
      pockets = mkOption {
        type = types.attrsOf types.ints.positive;
        description = "The kit slots it provides, each with its pocket's volume in millilitres.";
      };
      extraPockets = mkOption {
        type = types.ints.unsigned;
        description = "Further pockets for whatever is not a declared device.";
      };
      massG = mkOption { type = types.ints.unsigned; };
      shell = {
        fibre = mkOption {
          # Generic fibre names (ISO 2076, 16 CFR 303.7), lower case.
          type = types.enum [
            "polyamide"
            "polyester"
            "aramid"
            "cotton"
            "wool"
            "elastane"
            "none"
          ];
        };
        gsm = mkOption {
          type = types.ints.unsigned;
          description = "Fabric weight, grams per square metre (ISO 3801); 0 where denier is the measure.";
        };
        denier = mkOption {
          type = types.ints.unsigned;
          description = "Yarn weight of the face fabric; 0 where not specified.";
        };
      };
      waterColumnMm = mkOption {
        type = types.ints.unsigned;
        description = "Hydrostatic head (ISO 811); 0 where not required.";
      };
      closures = mkOption {
        type = types.listOf (
          types.enum [
            "zip"
            "hook-and-loop"
            "snap"
            "buckle"
            "quick-release"
          ]
        );
      };
      attachment = mkOption {
        type = types.enum [
          "pals"
          "none"
        ];
      };
      washable = mkOption {
        type = types.bool;
        default = true;
        description = "Survives a machine wash: the outfits are rotated and washed (plan goal carried).";
      };
      condition = mkOption {
        type = types.enum [
          "new"
          "new-or-secondhand"
        ];
      };
      note = mkOption { type = types.str; };
      bom = mkOption {
        type = types.nullOr bom;
        default = null;
        description = "Its bill of materials and operations, for a should-cost and a request for quotes.";
      };
    };
  };

  rateKey = types.enum (lib.attrNames cfg.rates);

  bom = types.submodule {
    options = {
      quantity = mkOption {
        type = types.ints.positive;
        description = "Units in one order: the quantity quoted.";
      };
      materials = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              rate = mkOption { type = rateKey; };
              qty = mkOption {
                type = types.numbers.nonnegative;
                description = "Per unit made, in the rate's unit.";
              };
              basis = mkOption {
                type = types.enum [
                  "estimate"
                  "measured"
                ];
                description = "estimate: from the specification; measured: from a pattern's marker or a maker's sheet.";
              };
            };
          }
        );
      };
      operations = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              machine = mkOption { type = rateKey; };
              labour = mkOption { type = rateKey; };
              minutes = mkOption { type = types.numbers.positive; };
            };
          }
        );
      };
    };
  };

  rate = types.submodule {
    options = {
      unit = mkOption {
        type = types.enum [
          "m2"
          "m"
          "piece"
          "hour"
        ];
      };
      cents = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
        description = "US cents per unit; null until a source prices it.";
      };
      source = mkOption {
        type = types.nullOr url;
        default = null;
        description = "Where the rate comes from; null while it waits on a supplier's quote.";
      };
      evidence = mkOption {
        type = types.enum [
          "page"
          "snippet"
          "secondary"
          "quote"
          "pending"
        ];
      };
    };
  };

  book = {
    inherit (cfg)
      regions
      channels
      hubs
      outfit
      owner
      rates
      quotes
      ;
    kit = {
      inherit (config.kit) slots;
      items = lib.mapAttrs (_: i: {
        inherit (i)
          device
          slot
          massG
          volumeMl
          owned
          ;
      }) config.kit.items;
    };
  };

  terms = {
    allowed = ".allowed";
    api-only = ".apiOnly";
    forbidden = ".forbidden";
    unknown = ".unknown";
  };
  used = lib.unique (lib.mapAttrsToList (_: i: i.slot) config.kit.items);

  facts = ''

    namespace Kagamizo.Logistics

    def channels : List Channel := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          n: c:
          "{ name := ${q n}, kind := ${q c.kind}, regions := ${q c.regions}, terms := ${terms.${c.terms.position}}, ops := [${
            lib.concatStringsSep ", " (
              lib.mapAttrsToList (o: v: "{ name := ${q o}, access := .${v.access} }") c.ops
            )
          }] }"
        ) cfg.channels
      )
    }]

    def regions : List String := ${q cfg.regions}

    def hubs : List Hub := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          n: h:
          "{ name := ${q n}, region := ${q h.region}, airports := ${q h.airports}, home := ${
            lib.boolToString (h.status == "home")
          } }"
        ) cfg.hubs
      )
    }]

    def slots : List Slot := [${
      lib.concatStringsSep ", " (
        lib.mapAttrsToList (
          n: s:
          "{ name := ${q n}, volumeMl := ${toString s.volumeMl}, used := ${lib.boolToString (lib.elem n used)} }"
        ) config.kit.slots
      )
    }]

    def worn : List String := ${q cfg.outfit.worn}

    def garments : List Garment := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          n: g:
          "{ name := ${q n}, kind := ${q g.kind}, provides := [${
            lib.concatStringsSep ", " (lib.mapAttrsToList (s: v: "(${q s}, ${toString v})") g.pockets)
          }], massG := ${toString g.massG}, washable := ${lib.boolToString g.washable} }"
        ) cfg.outfit.garments
      )
    }]

    theorem logistics_sound :
        sound channels regions hubs slots worn garments ${toString cfg.outfit.maxMassG} = true := by
      decide +kernel

    end Kagamizo.Logistics
  '';
in
{
  options.logistics = {
    owner = mkOption {
      type = types.enum (lib.attrNames config.identity.checked.entities);
      description = "The entity that buys: whose accounts and cards the orders go through.";
    };
    regions = mkOption { type = types.nonEmptyListOf slug; };
    channels = mkOption { type = types.attrsOf channel; };
    hubs = mkOption { type = types.attrsOf hub; };
    rates = mkOption {
      type = types.attrsOf rate;
      default = { };
      description = "Materials, machine hours and labour hours, each priced from its source.";
    };
    quotes = {
      premiumPct = mkOption {
        type = types.ints.between 0 100;
        description = "How far above the should-cost a quote may be accepted.";
      };
      incoterm = mkOption {
        # Incoterms 2020: delivered duty paid keeps customs off the critical path.
        type = types.enum [
          "EXW"
          "FCA"
          "FOB"
          "CIF"
          "DAP"
          "DDP"
        ];
      };
      inspection = {
        level = mkOption {
          type = types.enum [
            "I"
            "II"
            "III"
          ];
          description = "ISO 2859-1 general inspection level.";
        };
        majorAql = mkOption {
          type = types.enum [
            "1.0"
            "1.5"
            "2.5"
            "4.0"
          ];
        };
        minorAql = mkOption {
          type = types.enum [
            "2.5"
            "4.0"
            "6.5"
          ];
        };
      };
    };
    outfit = {
      worn = mkOption {
        type = types.listOf (types.enum kitSlots);
        description = "Kit slots worn on the body itself, which no garment provides.";
      };
      maxMassG = mkOption { type = types.ints.positive; };
      garments = mkOption { type = types.attrsOf garment; };
    };
  };

  config = {
    logistics.owner = "mirazo";

    perSystem =
      { pkgs, config, ... }:
      let
        bookJson = pkgs.writeText "logistics-book.json" (q book);
      in
      {
        packages = {
          logistics-book = bookJson;
          logistics = pkgs.rustPlatform.buildRustPackage {
            pname = "logistics";
            version = "0.1.0";
            src = ./_src;
            cargoLock.lockFile = ./_src/Cargo.lock;
            LOGISTICS_BOOK = bookJson;
            meta.mainProgram = "logistics";
          };
        };
        checks.logistics = config.kagamizo.leanCheck {
          name = "logistics";
          source = ./_lean/Logistics.lean;
          inherit facts;
        };
      };
  };
}
