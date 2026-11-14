# Every channel a thing can be found, made, carried, held or handed over
# through, typed by what software may do with it (./logistics.nix holds the
# types). Researched on 2026-11-08 from search results over each provider's
# own pages: `evidence = "snippet"` is the provider's page as quoted in a
# search result, `"secondary"` a third party's; none has been read whole
# yet, because the hosts are outside the session's allowlist (a gap in the
# paper). Nothing here is held: every account is the owner's sign-up.
let
  op = access: source: evidence: { inherit access source evidence; };
  terms = position: source: evidence: { inherit position source evidence; };
in
{
  logistics.channels = {
    # Marketplaces.
    amazon-business = {
      kind = "marketplace";
      regions = [ "north-america" ];
      terms = terms "api-only" "https://docs.business.amazon.com/docs/ordering-api-overview" "snippet";
      ops = {
        search = op "gated" "https://docs.business.amazon.com/docs/product-search-api-overview" "snippet";
        order = op "gated" "https://docs.business.amazon.com/docs/placing-an-order" "snippet";
        track =
          op "gated" "https://developer-docs.amazon.com/amazon-business/docs/ab-api-endpoints"
            "snippet";
      };
      protection = "A-to-z Guarantee; the Ordering API's safeguards cap price rises and delivery time per order";
      note = "Needs an Amazon Business customer account and partner onboarding with the Order Placement role";
    };
    amazon-creators = {
      kind = "data";
      regions = [ "north-america" ];
      terms =
        terms "api-only" "https://affiliate-program.amazon.com/creatorsapi/docs/en-us/concepts/api-rates"
          "snippet";
      ops = {
        search =
          op "gated" "https://affiliate-program.amazon.com/creatorsapi/docs/en-us/concepts/api-rates"
            "snippet";
        specs =
          op "gated" "https://affiliate-program.amazon.com/creatorsapi/docs/en-us/paapiv5-deprecation"
            "snippet";
      };
      note = "PA-API 5.0 retired 2026-05-15; the Creators API needs Associates with 10 qualifying sales in 30 days";
    };
    keepa = {
      kind = "data";
      regions = [ "global" ];
      terms = terms "allowed" "https://keepa.com/api-docs/plans-tokens.html" "snippet";
      ops = {
        search = op "open" "https://keepa.com/api-docs/plans-tokens.html" "snippet";
        specs = op "open" "https://keepa.com/api-docs/plans-tokens.html" "snippet";
      };
      note = "Amazon price history and offers, billed in tokens per minute (about 49 EUR a month at the lowest tier, secondary)";
    };
    aliexpress = {
      kind = "marketplace";
      regions = [
        "global"
        "asia"
      ];
      terms = terms "api-only" "https://openservice.aliexpress.com" "snippet";
      ops = {
        search = op "gated" "https://openservice.aliexpress.com" "secondary";
        specs = op "gated" "https://openservice.aliexpress.com" "secondary";
        quote = op "gated" "https://openservice.aliexpress.com" "secondary";
        order = op "gated" "https://openservice.aliexpress.com" "snippet";
        track = op "gated" "https://openservice.aliexpress.com" "secondary";
      };
      protection = "AliExpress buyer protection (secondary)";
      note = "The Dropshipping developer type places orders (aliexpress.ds.order.create); one account cannot hold both a Dropshipping and an Affiliate app";
    };
    taobao-1688 = {
      kind = "marketplace";
      regions = [ "asia" ];
      terms = terms "unknown" "https://otcommerce.com/key-payments/otapi-documentation/" "snippet";
      ops = {
        search = op "open" "https://otcommerce.com/key-payments/otapi-documentation/" "snippet";
        specs = op "open" "https://otcommerce.com/key-payments/otapi-documentation/" "snippet";
        order = op "partner" "https://otcommerce.com/key-payments/" "snippet";
      };
      protection = "None across the border: a buying agent's QC photos and parcel insurance are the only safeguards";
      note = "Through OTCommerce's paid keys; 1688's and Taobao's own open platforms need a Chinese business licence (secondary)";
    };
    alibaba-com = {
      kind = "marketplace";
      regions = [ "asia" ];
      terms = terms "unknown" "https://www.alibaba.com" "secondary";
      ops.search = op "none" "https://www.alibaba.com" "secondary";
      note = "No buyer-side or RFQ API: requests for quotes are written by agents and sent by the owner";
    };
    mercado-libre = {
      kind = "marketplace";
      regions = [ "south-america" ];
      terms = terms "api-only" "https://developers.mercadolibre.cl/en_us/items-and-searches" "snippet";
      ops = {
        search = op "gated" "https://developers.mercadolibre.cl/en_us/items-and-searches" "snippet";
        specs = op "gated" "https://developers.mercadolibre.cl/en_us/items-and-searches" "snippet";
        order = op "none" "https://developers.mercadolibre.cl/en_us/items-and-searches" "secondary";
      };
      protection = "Compra Protegida (secondary)";
      note = "OAuth; buyer orders are placed by the owner, the API is seller-side";
    };
    ebay = {
      kind = "marketplace";
      regions = [ "global" ];
      terms =
        terms "api-only" "https://www.developer.ebay.com/api-docs/buy/buy-requirements.html"
          "snippet";
      ops = {
        search = op "open" "https://developer.ebay.com/api-docs/buy/browse/overview.html" "snippet";
        specs = op "open" "https://developer.ebay.com/api-docs/buy/browse/overview.html" "snippet";
        order = op "partner" "https://developer.ebay.com/api-docs/buy/order/overview.html" "snippet";
      };
      protection = "eBay Money Back Guarantee";
      note = "Browse returns size and condition in localizedAspects; the Order API is limited release through the Partner Network";
    };

    # Secondhand clothing.
    depop = {
      kind = "resale";
      goods = [ "apparel" ];
      regions = [
        "north-america"
        "europe"
      ];
      terms = terms "forbidden" "https://partnerapi.depop.com/api-docs/" "secondary";
      ops.search = op "none" "https://partnerapi.depop.com/api-docs/" "secondary";
      note = "Partner API is for approved sellers; no buyer search; browsed by the owner";
    };
    vinted = {
      kind = "resale";
      goods = [ "apparel" ];
      regions = [ "europe" ];
      terms = terms "forbidden" "https://pro-docs.svc.vinted.com" "secondary";
      ops.search = op "none" "https://pro-docs.svc.vinted.com" "snippet";
      note = "Pro Integrations API is allowlisted Pro sellers only; terms from 2026-10-08 ban unauthorised bots (secondary)";
    };
    poshmark = {
      kind = "resale";
      goods = [ "apparel" ];
      regions = [ "north-america" ];
      terms = terms "forbidden" "https://poshmark.com/terms" "secondary";
      ops.search = op "none" "https://poshmark.com/terms" "secondary";
    };
    grailed = {
      kind = "resale";
      goods = [ "apparel" ];
      regions = [
        "north-america"
        "europe"
      ];
      terms = terms "unknown" "https://www.grailed.com/about/terms" "snippet";
      ops.search = op "none" "https://www.grailed.com/about/terms" "secondary";
    };
    the-realreal = {
      kind = "resale";
      goods = [ "apparel" ];
      regions = [ "north-america" ];
      terms = terms "unknown" "https://vendor-docs.therealreal.com/support" "snippet";
      ops.search = op "none" "https://vendor-docs.therealreal.com/support" "secondary";
      protection = "Items authenticated and graded (Pristine, Excellent, Very Good, Good, Fair)";
    };

    # Makers to a specification.
    printful = {
      kind = "maker";
      goods = [ "apparel" ];
      regions = [ "global" ];
      terms = terms "api-only" "https://printful.com/api" "snippet";
      ops = {
        quote = op "open" "https://printful.com/api" "snippet";
        order = op "open" "https://printful.com/api" "snippet";
        track = op "open" "https://printful.com/api" "snippet";
      };
      note = "Cut-and-sew is offered; whether the API covers it is unconfirmed";
    };
    printify = {
      kind = "maker";
      goods = [ "apparel" ];
      regions = [ "global" ];
      terms = terms "api-only" "https://developers.printify.com" "snippet";
      ops = {
        quote = op "open" "https://developers.printify.com" "snippet";
        order = op "open" "https://developers.printify.com" "snippet";
        track = op "open" "https://developers.printify.com" "snippet";
      };
    };
    jlcpcb = {
      kind = "maker";
      goods = [ "electronics" ];
      regions = [ "asia" ];
      terms = terms "api-only" "https://api.jlcpcb.com/" "snippet";
      ops = {
        quote = op "gated" "https://api.jlcpcb.com/" "snippet";
        order = op "gated" "https://api.jlcpcb.com/" "snippet";
        track = op "gated" "https://api.jlcpcb.com/" "snippet";
      };
    };
    sewport = {
      kind = "maker";
      goods = [ "apparel" ];
      regions = [ "global" ];
      terms = terms "unknown" "https://sewport.com/how-it-works" "secondary";
      ops.quote = op "none" "https://sewport.com/how-it-works" "secondary";
      protection = "Payments held in escrow";
      note = "Cut-and-sew makers by brief: agents write the tech pack, the owner sends it";
    };

    # Parcel carriers and lines.
    ups = {
      kind = "carrier";
      goods = [ "parcels" ];
      regions = [ "global" ];
      terms =
        terms "api-only"
          "https://developer.ups.com/us/en/support/shipping-support/legal-terms-conditions/ups-service-guarantee"
          "snippet";
      ops = {
        quote =
          op "gated"
            "https://developer.ups.com/us/en/support/shipping-support/legal-terms-conditions/ups-service-guarantee"
            "secondary";
        order =
          op "gated"
            "https://developer.ups.com/us/en/support/shipping-support/legal-terms-conditions/ups-service-guarantee"
            "secondary";
        track =
          op "gated"
            "https://developer.ups.com/us/en/support/shipping-support/legal-terms-conditions/ups-service-guarantee"
            "secondary";
        locate =
          op "gated" "https://www.ups.com/assets/resources/media/ShiptoaUPSAccessPointlocation_US_EN.pdf"
            "snippet";
      };
      guarantee = "Money back only on Next Day Air, 2nd Day Air A.M., Worldwide Express, Express Plus and Express NA1; suspended on every other service, Ground included";
      prior = {
        onTimeBp = 9720;
        source = "https://www.freightwaves.com/news/large-parcel-carriers-improved-on-time-delivery-during-2025-peak-season";
        evidence = "secondary";
      };
    };
    fedex = {
      kind = "carrier";
      goods = [ "parcels" ];
      regions = [ "global" ];
      terms = terms "api-only" "https://developer.fedex.com/api/en-br/catalog.html" "snippet";
      ops = {
        quote = op "gated" "https://developer.fedex.com/api/en-br/catalog.html" "snippet";
        order = op "gated" "https://developer.fedex.com/api/en-br/catalog.html" "snippet";
        track = op "gated" "https://developer.fedex.com/api/en-br/catalog.html" "snippet";
        locate = op "gated" "https://developer.fedex.com/api/en-br/catalog.html" "snippet";
      };
      guarantee = "Money back suspended from 2025-12-01, reinstated 2026-02-12 for some international services only";
      prior = {
        onTimeBp = 9530;
        source = "https://www.freightwaves.com/news/large-parcel-carriers-improved-on-time-delivery-during-2025-peak-season";
        evidence = "secondary";
      };
    };
    dhl-express = {
      kind = "carrier";
      goods = [ "parcels" ];
      regions = [ "global" ];
      terms = terms "api-only" "https://developer.dhl.com/api-reference/dhl-express-mydhl-api" "snippet";
      ops = {
        quote = op "partner" "https://developer.dhl.com/api-reference/dhl-express-mydhl-api" "snippet";
        order = op "partner" "https://developer.dhl.com/api-reference/dhl-express-mydhl-api" "snippet";
        track = op "partner" "https://developer.dhl.com/api-reference/dhl-express-mydhl-api" "snippet";
      };
      note = "Credentials come from a DHL Express account consultant";
    };
    easypost = {
      kind = "carrier";
      goods = [ "parcels" ];
      regions = [ "north-america" ];
      terms = terms "api-only" "https://docs.easypost.com/guides/smartrate-guide" "snippet";
      ops = {
        quote = op "open" "https://docs.easypost.com/guides/smartrate-guide" "snippet";
        order = op "open" "https://docs.easypost.com/guides/smartrate-guide" "secondary";
        track = op "open" "https://docs.easypost.com/guides/smartrate-guide" "secondary";
      };
      note = "SmartRate gives per-lane transit percentiles (p50 to p99), the best machine-readable reliability prior found; US domestic";
    };
    yunexpress = {
      kind = "carrier";
      goods = [ "parcels" ];
      regions = [
        "asia"
        "global"
      ];
      terms = terms "unknown" "https://www.yunexpress.com" "secondary";
      ops = {
        quote = op "gated" "https://www.yunexpress.com" "secondary";
        track = op "gated" "https://www.yunexpress.com" "secondary";
      };
      note = "China to the world; about 7 to 20 business days to the US (secondary); no published on-time data";
    };

    # Couriers: someone fetches it for the owner.
    uber-direct = {
      kind = "courier";
      goods = [ "parcels" ];
      regions = [ "north-america" ];
      terms = terms "api-only" "https://developer.uber.com/docs/deliveries" "snippet";
      ops = {
        quote = op "gated" "https://developer.uber.com/docs/deliveries" "snippet";
        order = op "gated" "https://developer.uber.com/docs/deliveries/guides/delivery-window" "snippet";
        track = op "gated" "https://developer.uber.com/docs/deliveries" "snippet";
        collect = op "gated" "https://developer.uber.com/docs/deliveries/guides/delivery-window" "snippet";
        proof = op "gated" "https://developer.uber.com/docs/deliveries/guides/proof-of-delivery" "snippet";
      };
      protection = "Refunds capped at 200 USD a delivery (Canada's order form)";
      note = "Scheduled up to 30 days ahead; drop-off deadline at least 90 minutes out; proof by signature, photo, ID or PIN; about 15 km range";
    };
    lalamove = {
      kind = "courier";
      goods = [ "parcels" ];
      regions = [
        "asia"
        "south-america"
      ];
      terms = terms "api-only" "https://developers.lalamove.com/v2/index.html" "snippet";
      ops = {
        quote = op "gated" "https://developers.lalamove.com/v2/index.html" "snippet";
        order = op "gated" "https://developers.lalamove.com/v2/index.html" "snippet";
        track = op "gated" "https://developers.lalamove.com/v2/index.html" "snippet";
        collect = op "gated" "https://developers.lalamove.com/v2/index.html" "snippet";
        proof = op "gated" "https://developers.lalamove.com/v2/index.html" "secondary";
      };
      note = "Hong Kong, Singapore, Malaysia, Thailand, the Philippines, Indonesia, Vietnam, Brazil and more; business API sign-up";
    };
    doordash-drive = {
      kind = "courier";
      goods = [ "parcels" ];
      regions = [ "north-america" ];
      terms = terms "api-only" "https://developer.doordash.com/en-US/docs/drive/overview/faqs" "snippet";
      ops.collect = op "partner" "https://merchants.doordash.com/products/drive" "snippet";
      note = "Self-serve only for restaurants; others need more than five locations: closed to us";
    };

    # Holding points a courier can collect from.
    ups-access-point = {
      kind = "holding";
      goods = [ "parcels" ];
      regions = [
        "north-america"
        "europe"
      ];
      terms =
        terms "api-only"
          "https://www.ups.com/assets/resources/media/ShiptoaUPSAccessPointlocation_US_EN.pdf"
          "snippet";
      ops = {
        locate =
          op "gated" "https://www.ups.com/assets/resources/media/ShiptoaUPSAccessPointlocation_US_EN.pdf"
            "snippet";
        collect =
          op "none"
            "https://www.ups.com/gb/en/support/shipping-support/id-requirements-for-tendering-shipment"
            "snippet";
      };
      note = "A courier collects with their own photo ID and a copy of the owner's: one document from the owner, once";
    };
    inpost = {
      kind = "holding";
      goods = [ "parcels" ];
      regions = [ "europe" ];
      terms =
        terms "api-only" "https://dokumentacja-inpost.atlassian.net/wiki/spaces/PL/pages/18153493"
          "snippet";
      ops = {
        locate =
          op "open" "https://dokumentacja-inpost.atlassian.net/wiki/spaces/PL/pages/18153493"
            "snippet";
        collect =
          op "none" "https://dokumentacja-inpost.atlassian.net/wiki/spaces/PL/pages/18153493"
            "secondary";
      };
      note = "Code lockers: whoever holds the pickup code collects, so a courier needs no ID";
    };
    fedex-hold = {
      kind = "holding";
      goods = [ "parcels" ];
      regions = [ "north-america" ];
      terms =
        terms "api-only" "https://www.fedex.com/en-us/delivery-manager/hold-at-location.html"
          "snippet";
      ops.locate = op "gated" "https://developer.fedex.com/api/en-br/catalog.html" "snippet";
      note = "Held up to seven days; a proxy needs a signed letter and a copy of the owner's ID";
    };
    cainiao-station = {
      kind = "holding";
      goods = [ "parcels" ];
      regions = [ "asia" ];
      terms = terms "unknown" "https://m.jiemian.com/article/13461310.html" "secondary";
      ops.collect = op "none" "https://m.jiemian.com/article/13461310.html" "secondary";
      note = "Collected with the pickup code; a recipient-designated proxy is allowed (Interim Regulations on Express Delivery, art. 25)";
    };
  };
}
