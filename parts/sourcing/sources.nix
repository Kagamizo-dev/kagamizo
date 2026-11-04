# Every source `sourcing` reads, what its results are worth, and the shop and
# facility vocabularies it searches with. `verified` stays null until a live
# response has been checked against what the adapter parses: none could be
# from the session that wrote this (the hosts were not yet allowlisted), so
# `sourcing sources` shows each as unverified.
let
  osmPolicy = "https://operations.osmfoundation.org/policies/";
in
{
  sourcing = {
    sources = {
      # Listings with price, stock and seller; logistic_type "fulfillment"
      # (Mercado Envios Full) means Mercado Livre's own warehouse holds the
      # stock, which the adapter reports as the `fulfilled` signal.
      mercadolivre = {
        adapter = "mercadolivre";
        kind = "listings";
        signal = "seller-stock";
        base = "https://api.mercadolibre.com";
        hosts = [ "api.mercadolibre.com" ];
        docs = "https://developers.mercadolivre.com.br/en_us/about-us";
        countries = [
          "BR"
          "AR"
          "MX"
          "CL"
          "CO"
          "UY"
          "PE"
        ];
        account = "mercadolivre";
        needs = {
          searchApi = true;
          fulfillmentSignal = true;
        };
        # Search is public; a token only raises the limits.
        secret = "MERCADOLIVRE_ACCESS_TOKEN";
      };

      # Products by name, for the barcodes Open Prices is keyed on.
      openfoodfacts = {
        adapter = "openfoodfacts";
        kind = "products";
        base = "https://world.openfoodfacts.org";
        hosts = [ "world.openfoodfacts.org" ];
        docs = "https://openfoodfacts.github.io/documentation/";
        # Search is limited to about ten requests a minute.
        minIntervalMs = 6000;
      };

      # Prices people photographed on shelves, with the shop (an OSM node) and
      # the date: the observed signal, decaying with age.
      openprices = {
        adapter = "openprices";
        kind = "prices";
        signal = "observed";
        base = "https://prices.openfoodfacts.org";
        hosts = [ "prices.openfoodfacts.org" ];
        docs = "https://openfoodfacts.github.io/documentation/docs/Open-prices/prices/prices_retrieve/";
      };

      osm-shops = {
        adapter = "overpass";
        kind = "shops";
        signal = "listed";
        base = "https://overpass-api.de/api";
        hosts = [ "overpass-api.de" ];
        docs = osmPolicy;
        minIntervalMs = 1000;
      };

      osm-facilities = {
        adapter = "overpass";
        kind = "facilities";
        signal = "listed";
        base = "https://overpass-api.de/api";
        hosts = [ "overpass-api.de" ];
        docs = osmPolicy;
        minIntervalMs = 1000;
      };

      # Fab labs with the machines each declares.
      fablabs = {
        adapter = "fablabs";
        kind = "facilities";
        signal = "capability";
        base = "https://api.fablabs.io";
        hosts = [ "api.fablabs.io" ];
        docs = "https://fablabs.io/";
      };

      # Quotes across Correios, Jadlog, Loggi and the rest, each with a
      # delivery range: the spread of that range lowers its stability.
      melhorenvio = {
        adapter = "melhorenvio";
        kind = "shipping";
        signal = "quote";
        base = "https://melhorenvio.com.br";
        hosts = [ "melhorenvio.com.br" ];
        docs = "https://docs.melhorenvio.com.br/reference/calculo-de-fretes-por-produtos";
        countries = [ "BR" ];
        account = "melhorenvio";
        needs.shippingQuotes = true;
        secret = "MELHORENVIO_TOKEN";
        secretRequired = true;
      };

      # Free-text places (--at "Av. Paulista 1578") to coordinates; one request
      # a second and an identifying User-Agent, by its usage policy.
      nominatim = {
        adapter = "nominatim";
        kind = "geocode";
        base = "https://nominatim.openstreetmap.org";
        hosts = [ "nominatim.openstreetmap.org" ];
        docs = "https://operations.osmfoundation.org/policies/nominatim/";
        minIntervalMs = 1000;
      };

      # Query translation into the place's language, and outreach drafts.
      openrouter = {
        adapter = "openrouter";
        kind = "translate";
        base = "https://openrouter.ai/api/v1";
        hosts = [ "openrouter.ai" ];
        docs = "https://openrouter.ai/docs/api-reference/overview";
        account = "openrouter";
        needs = {
          chatCompletions = true;
          jsonMode = true;
        };
        secret = "OPENROUTER_API_KEY";
        secretRequired = true;
      };
    };

    # `sourcing near <category>`: OpenStreetMap tags per category.
    shops = {
      food = [
        "amenity=restaurant"
        "amenity=fast_food"
        "amenity=cafe"
        "shop=bakery"
      ];
      groceries = [
        "shop=supermarket"
        "shop=convenience"
        "shop=greengrocer"
      ];
      pharmacy = [
        "amenity=pharmacy"
        "shop=chemist"
      ];
      supplements = [ "shop=nutrition_supplements" ];
      electronics = [ "shop=electronics" ];
      hardware = [
        "shop=hardware"
        "shop=doityourself"
      ];
    };

    # `sourcing facilities <capability>`: machines to rent or borrow rather
    # than buy. Fab labs say what they have; makerspaces, libraries and
    # universities are only places that may have it, so they rank lower.
    facilities =
      let
        makers = [ "leisure=hackerspace" ];
      in
      {
        "3d-printing" = {
          fablabs = [ "three_d_printing" ];
          osm = makers;
        };
        laser-cutting = {
          fablabs = [ "laser" ];
          osm = makers;
        };
        cnc-milling = {
          fablabs = [
            "cnc_milling"
            "precision_milling"
          ];
          osm = makers;
        };
        vinyl-cutting.fablabs = [ "vinyl_cutting" ];
        electronics = {
          fablabs = [ "circuit_production" ];
          osm = makers;
        };
        workspace.osm = [
          "amenity=library"
          "amenity=coworking_space"
        ];
        lab.osm = [
          "amenity=university"
          "amenity=college"
          "amenity=research_institute"
        ];
      };
  };
}
