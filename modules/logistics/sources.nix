# The keyless sources: data reached with no account at all (the owner's
# direction, 2026-11-08: open data, OSINT and sanctioned keyless channels
# first; accounts only where a payment or a dispatch needs one). Researched
# on 2026-11-08 from search results; none has been called live yet, since
# the hosts are outside the session's allowlist (data/keyless-verify).
# Sanctioned keyless channels only: storefront pages are read only where the
# site's own robots rules allow it, and never where its terms forbid it.
let
  op = access: source: evidence: { inherit access source evidence; };
  terms = position: source: evidence: { inherit position source evidence; };
in
{
  logistics.channels = {
    # Products and stock.
    shopify-catalog = {
      kind = "marketplace";
      goods = [
        "general"
        "apparel"
      ];
      regions = [ "global" ];
      terms = terms "allowed" "https://shopify.dev/docs/agents/catalog" "snippet";
      ops = {
        search = op "keyless" "https://shopify.dev/docs/agents/catalog" "snippet";
        specs = op "keyless" "https://shopify.dev/docs/agents/catalog" "snippet";
        order = op "none" "https://shopify.dev/docs/agents/catalog" "snippet";
      };
      note = "Shopify's Global Catalog for agents (UCP over MCP): every opted-in merchant, keyless with an agent profile URL at the lowest rate limits; orders are the owner's guest checkout";
    };
    shopify-stores = {
      kind = "marketplace";
      goods = [
        "general"
        "apparel"
      ];
      regions = [ "global" ];
      terms = terms "allowed" "https://shopify.dev/docs/agents/catalog/storefront-mcp" "snippet";
      ops = {
        search = op "keyless" "https://shopify.dev/docs/agents/catalog/storefront-mcp" "snippet";
        specs = op "keyless" "https://shopify.dev/docs/agents/catalog/storefront-mcp" "snippet";
        order = op "none" "https://shopify.dev/docs/agents/catalog/storefront-mcp" "snippet";
      };
      note = "One brand's own store over its UCP endpoint: per-variant size, colour, price, in stock or not, often the GTIN; materials as free text";
    };
    woocommerce-stores = {
      kind = "marketplace";
      goods = [
        "general"
        "apparel"
      ];
      regions = [ "global" ];
      terms = terms "allowed" "https://developer.woocommerce.com/docs/apis/store-api/" "snippet";
      ops = {
        search = op "keyless" "https://developer.woocommerce.com/docs/apis/store-api/" "snippet";
        specs = op "keyless" "https://developer.woocommerce.com/docs/apis/store-api/" "snippet";
        order = op "none" "https://developer.woocommerce.com/docs/apis/store-api/" "snippet";
      };
      note = "The Store API every WooCommerce shop serves: price, attributes, variations, in stock";
    };
    web-data-commons = {
      kind = "data";
      regions = [ "global" ];
      terms = terms "allowed" "https://webdatacommons.org/structureddata/" "snippet";
      ops.specs = op "keyless" "https://webdatacommons.org/structureddata/" "snippet";
      note = "University of Mannheim's schema.org Product extraction from Common Crawl: specs and GTINs in bulk, last confirmed October 2024, so never stock";
    };
    cpsc-recalls = {
      kind = "data";
      regions = [ "north-america" ];
      terms =
        terms "allowed"
          "https://www.cpsc.gov/Recalls/CPSC-Recalls-Application-Program-Interface-API-Information"
          "snippet";
      ops.reliability =
        op "keyless"
          "https://www.cpsc.gov/Recalls/CPSC-Recalls-Application-Program-Interface-API-Information"
          "snippet";
      note = "US recalls by product, model and UPC: a candidate is checked against them before it is quoted";
    };
    eu-safety-gate = {
      kind = "data";
      regions = [ "europe" ];
      terms = terms "unknown" "https://ec.europa.eu/safety-gate" "secondary";
      ops.reliability = op "keyless" "https://ec.europa.eu/safety-gate" "secondary";
      note = "The EU's dangerous-product alerts, heavy on apparel and Chinese origin";
    };

    # Where things land and who holds them.
    osm-lockers = {
      kind = "holding";
      goods = [ "parcels" ];
      regions = [ "global" ];
      terms = terms "allowed" "https://wiki.openstreetmap.org/wiki/Tag:amenity%3Dparcel_locker" "snippet";
      ops.locate =
        op "keyless" "https://wiki.openstreetmap.org/wiki/Tag:amenity%3Dparcel_locker"
          "snippet";
      note = "Parcel lockers and post offices from OpenStreetMap (ODbL), read from Geofabrik extracts on our own host, not the public Overpass servers";
    };

    # Rates, standards and reliability.
    usps-prices = {
      kind = "carrier";
      goods = [ "parcels" ];
      regions = [ "north-america" ];
      terms = terms "allowed" "https://pe.usps.com/pricechange/index" "snippet";
      ops = {
        quote = op "keyless" "https://pe.usps.com/pricechange/index" "snippet";
        standards =
          op "keyless" "https://postalpro.usps.com/resources/operations/service-standards"
            "snippet";
        reliability = op "keyless" "https://www.prc.gov" "snippet";
      };
      note = "Retail prices as Excel and CSV, delivery-day standards per 3-digit ZIP pair, and quarterly on-time performance";
    };
    ups-rates = {
      kind = "carrier";
      goods = [ "parcels" ];
      regions = [ "global" ];
      terms = terms "allowed" "https://www.ups.com/us/en/shipping/daily-rates" "secondary";
      ops.quote = op "keyless" "https://www.ups.com/us/en/shipping/daily-rates" "secondary";
      note = "The Daily Rate and Service Guide and retail rates, published as PDF and Excel";
    };

    # Hubs, flights and disruption.
    ourairports = {
      kind = "data";
      regions = [ "global" ];
      terms = terms "allowed" "https://ourairports.com/data/" "snippet";
      ops.routes = op "keyless" "https://ourairports.com/data/" "snippet";
      note = "Every airport, public domain, rebuilt nightly";
    };
    bts = {
      kind = "data";
      regions = [ "north-america" ];
      terms = terms "allowed" "https://www.transtats.bts.gov" "snippet";
      ops = {
        routes = op "keyless" "https://www.transtats.bts.gov" "secondary";
        reliability = op "keyless" "https://www.transtats.bts.gov" "snippet";
      };
      note = "T-100 routes and seats, the DB1B fare sample and airline on-time data, about six months behind";
    };
    eurostat-air = {
      kind = "data";
      regions = [ "europe" ];
      terms = terms "allowed" "https://ec.europa.eu/eurostat" "secondary";
      ops.routes = op "keyless" "https://ec.europa.eu/eurostat" "secondary";
      note = "Passengers per airport pair (avia_par), monthly";
    };
    anac = {
      kind = "data";
      regions = [ "south-america" ];
      terms = terms "allowed" "https://dados.gov.br" "snippet";
      ops.routes = op "keyless" "https://dados.gov.br" "snippet";
      note = "Brazil's flight records (VRA), licence-free open data";
    };
    weather-gov = {
      kind = "data";
      regions = [ "north-america" ];
      terms = terms "allowed" "https://www.weather.gov/documentation/services-web-api" "snippet";
      ops.disruption = op "keyless" "https://www.weather.gov/documentation/services-web-api" "snippet";
    };
    faa-nas = {
      kind = "data";
      regions = [ "north-america" ];
      terms = terms "allowed" "https://nasstatus.faa.gov" "secondary";
      ops.disruption = op "keyless" "https://nasstatus.faa.gov" "secondary";
      note = "Airport delays, ground stops and closures";
    };
    imf-portwatch = {
      kind = "data";
      regions = [ "global" ];
      terms = terms "unknown" "https://portwatch.imf.org" "snippet";
      ops.disruption = op "keyless" "https://portwatch.imf.org" "snippet";
      note = "Daily port calls and disruptions for about 1,700 ports";
    };

    # Customs.
    eu-taric = {
      kind = "data";
      regions = [ "europe" ];
      terms = terms "allowed" "https://circabc.europa.eu" "snippet";
      ops.tariff = op "keyless" "https://circabc.europa.eu" "snippet";
    };
    brazil-ncm = {
      kind = "data";
      regions = [ "south-america" ];
      terms = terms "allowed" "https://www.gov.br/siscomex" "snippet";
      ops.tariff = op "keyless" "https://www.gov.br/siscomex" "snippet";
    };
    us-hts = {
      kind = "data";
      regions = [ "north-america" ];
      terms = terms "unknown" "https://hts.usitc.gov" "secondary";
      ops.tariff = op "keyless" "https://hts.usitc.gov" "secondary";
      note = "Sources disagree on whether its API needs an account: settled by the live check";
    };

    # Cost inputs.
    ilostat = {
      kind = "data";
      regions = [ "global" ];
      terms = terms "allowed" "https://ilostat.ilo.org/data/" "secondary";
      ops.rates = op "keyless" "https://ilostat.ilo.org/data/" "secondary";
      note = "Wages by country and industry (garment manufacturing included): the labour rates of a should-cost";
    };
  };
}
