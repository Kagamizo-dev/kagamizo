# Sourcing: find goods, food, parts and facilities near wherever you are, and
# rank them by how far their inventory reports can be trusted, not only by
# price. Declared here, typed, and rendered to the JSON the `sourcing` CLI
# reads (./sourcing.nix):
#
#   sourcing.places.<name>    where you are: coordinates, country, language,
#                             currency, and what moving yourself costs
#   sourcing.home             the place used when none is given
#   sourcing.sources.<name>   every data source: what it reports, how much its
#                             inventory signal is worth, the account it runs
#                             on, its secret, its hosts
#   sourcing.policy           how stability is scored and how much premium a
#                             more stable offer may cost
#   sourcing.shops            shop categories as OpenStreetMap tags
#   sourcing.facilities       capabilities (3D printing, laser, ...) as
#                             fablabs.io capabilities and OpenStreetMap tags
#   sourcing.watch.<name>     items the status bar keeps an eye on
#   sourcing.outreach         the mailbox and model outreach mail is drafted with
#
# Every closed set (countries, languages, currencies, signals, adapters) is an
# enum, so a typo fails evaluation naming the field. A source that runs on an
# account declares what it needs as accounts.demands, like every other module.
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.sourcing;

  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
  https = types.strMatching "https://.+";
  host = types.strMatching "([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}";
  secretName = types.strMatching "[A-Z][A-Z0-9_]*";
  unit = types.numbers.between 0 1;
  nonNegative = types.addCheck types.number (x: x >= 0) // {
    description = "non-negative number";
  };

  # Mercado Livre runs one site per country; the countries it has are the
  # ones its adapter can search.
  mercadoLivreSites = {
    BR = "MLB";
    AR = "MLA";
    MX = "MLM";
    CL = "MLC";
    CO = "MCO";
    UY = "MLU";
    PE = "MPE";
  };
  countries = lib.attrNames mercadoLivreSites ++ [
    "US"
    "PT"
    "ES"
    "DE"
    "JP"
    "CN"
  ];
  locales = [
    "pt-BR"
    "pt-PT"
    "es-419"
    "es-ES"
    "en-US"
    "de-DE"
    "ja-JP"
    "zh-CN"
  ];
  currencies = [
    "BRL"
    "ARS"
    "MXN"
    "CLP"
    "COP"
    "UYU"
    "PEN"
    "USD"
    "EUR"
    "JPY"
    "CNY"
  ];

  # How an offer knows it is in stock, strongest first:
  #   fulfilled     the marketplace holds the stock in its own warehouse
  #   seller-stock  the seller reports a stock count
  #   quote         a carrier quoted it just now (shipping)
  #   capability    a registry lists the machine (fab labs)
  #   observed      someone saw it on a shelf at a price, some days ago
  #   listed        the shop exists; nothing is known about its stock
  signals = [
    "fulfilled"
    "seller-stock"
    "quote"
    "capability"
    "observed"
    "listed"
  ];
  kinds = [
    "listings"
    "products"
    "prices"
    "shops"
    "facilities"
    "shipping"
    "geocode"
    "translate"
  ];
  # Each must be implemented by the CLI (_cli/sourcing/adapters); the
  # `sourcing-config` check fails when one is declared but missing.
  adapters = [
    "mercadolivre"
    "openfoodfacts"
    "openprices"
    "overpass"
    "fablabs"
    "melhorenvio"
    "nominatim"
    "openrouter"
  ];

  place = types.submodule {
    options = {
      label = mkOption { type = types.str; };
      lat = mkOption { type = types.numbers.between (-90) 90; };
      lon = mkOption { type = types.numbers.between (-180) 180; };
      country = mkOption { type = types.enum countries; };
      locale = mkOption {
        type = types.enum locales;
        description = "The language mail and searches are written in here.";
      };
      currency = mkOption { type = types.enum currencies; };
      timeZone = mkOption { type = types.strMatching "[A-Za-z_]+/[A-Za-z_/]+"; };
      postalCode = mkOption {
        type = types.nullOr (types.strMatching "[0-9A-Z -]+");
        default = null;
        description = ''
          A public reference code (a city centre), used for shipping quotes
          when SOURCING_DELIVERY_POSTCODE is not set. Your real address is a
          secret and never lives here.
        '';
      };
      radiusKm = mkOption {
        type = types.ints.positive;
        default = 10;
        description = "How far local results reach by default.";
      };
      travelPerKm = mkOption {
        type = nonNegative;
        description = "What moving yourself costs per km, in the place's currency; a pickup counts it both ways.";
      };
      unknownShipping = mkOption {
        type = nonNegative;
        description = "Shipping assumed, for ranking, when a listing does not state it.";
      };
    };
  };

  source = types.submodule {
    options = {
      adapter = mkOption { type = types.enum adapters; };
      kind = mkOption { type = types.enum kinds; };
      signal = mkOption {
        type = types.nullOr (types.enum signals);
        default = null;
        description = "The inventory signal its results carry; null for sources that report no offers.";
      };
      base = mkOption {
        type = https;
        description = "API root the adapter calls.";
      };
      hosts = mkOption {
        type = types.nonEmptyListOf host;
        description = "Every host it reaches; each must be in the session allowlist.";
      };
      docs = mkOption { type = https; };
      countries = mkOption {
        type = types.listOf (types.enum countries);
        default = [ ];
        description = "Where it has data; empty is everywhere.";
      };
      account = mkOption {
        type = types.nullOr (types.enum (lib.attrNames config.accounts.held));
        default = null;
      };
      needs = mkOption {
        type = types.attrsOf (types.either types.ints.unsigned types.bool);
        default = { };
        description = "Capabilities of `account` it relies on, as accounts.demands.";
      };
      secret = mkOption {
        type = types.nullOr secretName;
        default = null;
        description = "The secretspec variable (profile sourcing) holding its key.";
      };
      secretRequired = mkOption {
        type = types.bool;
        default = false;
        description = "Without the secret the source is skipped; otherwise it runs anonymously.";
      };
      minIntervalMs = mkOption {
        type = types.ints.unsigned;
        default = 0;
        description = "Least time between two requests, as the provider's usage policy asks.";
      };
      verified = mkOption {
        type = types.nullOr date;
        default = null;
        description = "When a live request last matched what the adapter parses; null until one has.";
      };
    };
  };

  policy = types.submodule {
    options = {
      fidelity = mkOption {
        type = types.attrsOf unit;
        description = "What each inventory signal is worth, 0 to 1. Must cover every signal.";
      };
      halfLifeDays = mkOption {
        type = types.ints.positive;
        description = "An observation's trust halves every this many days.";
      };
      minStability = mkOption {
        type = unit;
        description = "Offers below this are hidden unless asked for (--all).";
      };
      premiumPct = mkOption {
        type = types.numbers.between 0 100;
        description = "A more stable offer wins while it costs at most this much more than the cheapest.";
      };
      depthFull = mkOption {
        type = types.ints.positive;
        description = "A reported stock this deep counts as full; shallower stock is less certain.";
      };
      spreadPenalty = mkOption {
        type = nonNegative;
        description = "How hard price dispersion across observations (coefficient of variation) lowers stability.";
      };
    };
  };

  facility = types.submodule {
    options = {
      fablabs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "fablabs.io capability names.";
      };
      osm = mkOption {
        type = types.listOf (types.strMatching "[a-z_:]+=[a-z_;]+");
        default = [ ];
        description = "OpenStreetMap tags (key=value) of places that may have it.";
      };
    };
  };

  watch = types.submodule {
    options = {
      query = mkOption { type = types.str; };
      place = mkOption {
        type = types.nullOr (types.enum (lib.attrNames cfg.places));
        default = null;
        description = "Null follows sourcing.home.";
      };
      maxPrice = mkOption {
        type = types.nullOr nonNegative;
        default = null;
        description = "Landed cost above which the item shows as a warning.";
      };
    };
  };

  addresses = lib.concatLists (
    lib.mapAttrsToList (
      domain: d: map (m: "${m}@${domain}") d.mailboxes
    ) config.identity.checked.domains
  );

  missingSignals = lib.subtractLists (lib.attrNames cfg.policy.fidelity) signals;
  extraSignals = lib.subtractLists signals (lib.attrNames cfg.policy.fidelity);
  problems =
    lib.optional (
      missingSignals != [ ]
    ) "sourcing.policy.fidelity: no value for ${lib.concatStringsSep ", " missingSignals}"
    ++
      lib.optional (extraSignals != [ ])
        "sourcing.policy.fidelity: unknown signals ${lib.concatStringsSep ", " extraSignals}; known: ${lib.concatStringsSep ", " signals}"
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: s:
        lib.optional (
          s.needs != { } && s.account == null
        ) "sourcing.sources.${name}: `needs` without an `account` to need it from"
        ++ lib.optional (
          s.secretRequired && s.secret == null
        ) "sourcing.sources.${name}: secretRequired without a `secret`"
        ++ lib.optional (
          s.kind != "translate" && s.kind != "geocode" && s.kind != "products" && s.signal == null
        ) "sourcing.sources.${name}: a ${s.kind} source must declare its inventory `signal`"
      ) cfg.sources
    );
in
{
  options.sourcing = {
    places = mkOption {
      type = types.attrsOf place;
      default = { };
    };
    home = mkOption { type = types.enum (lib.attrNames cfg.places); };
    sources = mkOption {
      type = types.attrsOf source;
      default = { };
    };
    policy = mkOption { type = policy; };
    shops = mkOption {
      type = types.attrsOf (types.nonEmptyListOf (types.strMatching "[a-z_:]+=[a-z_;]+"));
      default = { };
      description = "Shop categories for `sourcing near`, as OpenStreetMap tags.";
    };
    facilities = mkOption {
      type = types.attrsOf facility;
      default = { };
    };
    watch = mkOption {
      type = types.attrsOf watch;
      default = { };
    };
    outreach = {
      from = mkOption {
        type = types.enum addresses;
        description = "A declared mailbox (identity.domains.*.mailboxes).";
      };
      model = mkOption {
        type = types.strMatching "[a-z0-9-]+/[a-z0-9.:-]+";
        description = "OpenRouter model that drafts and translates.";
      };
      smtp = {
        host = mkOption { type = types.str; };
        port = mkOption { type = types.port; };
      };
      signature = mkOption { type = types.str; };
    };
    rendered = mkOption {
      type = types.raw;
      readOnly = true;
      description = "The checked declarations as the CLI reads them.";
    };
  };

  config = {
    sourcing.rendered =
      if problems == [ ] then
        {
          inherit (cfg)
            places
            home
            policy
            shops
            facilities
            outreach
            ;
          sources = lib.mapAttrs (
            _: s:
            removeAttrs s [ "needs" ]
            // {
              accountStatus = if s.account == null then null else config.accounts.held.${s.account}.status;
            }
          ) cfg.sources;
          watch = lib.mapAttrs (
            _: w: w // { place = if w.place == null then cfg.home else w.place; }
          ) cfg.watch;
          inherit adapters mercadoLivreSites;
        }
      else
        throw "sourcing does not check:\n${lib.concatMapStrings (p: "  - ${p}\n") problems}";

    accounts.demands =
      lib.concatLists (
        lib.mapAttrsToList (
          name: s:
          lib.mapAttrsToList (capability: need: {
            inherit (s) account;
            inherit capability need;
            why = "sourcing.sources.${name}";
          }) s.needs
        ) cfg.sources
      )
      ++ [
        # `sourcing send` hands drafts to Proton Bridge over SMTP.
        {
          account = "proton";
          capability = "bridge";
          need = true;
          why = "sourcing.outreach (send through Proton Bridge)";
        }
      ];
  };
}
