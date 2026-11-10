# No unbounded step anywhere (the owner's rule, 2026-11-10): the chain from
# a design to parts in hand is a closed loop. Nothing in it waits on a
# person, an approval, a contract or a reply. Makers rarely promise a bound
# (audited 2026-11-10 from their own pages: a file review, an approval-gated
# API or a lead time given as an average), so the bound is ours: every step
# has a deadline and an action taken when it passes.
#
#   logistics.sla.steps.<s>    one step: its channel, how software reaches
#                              it, who answers inside it, how an order is
#                              placed, the deadline in minutes, and what
#                              happens on a breach (retry once, reroute to a
#                              fallback step, or fail with the step named;
#                              never wait)
#   logistics.sla.paths.<p>    a product's steps in order, with the lead
#                              time it is published with
#   logistics.sla.excluded.<c> a channel that may be on no path, and why
#   logistics.sla.open.<q>     what has no bounded channel yet: a gap, never
#                              a step
#
# A deadline in business days is typed in calendar minutes with the weekend
# counted: N business days are at most N + 2 days.
#
# checks.logistics-sla (./_lean/Sla.lean): every step of every path has a
# deadline, is keyless or self-serve, has no person inside it, rests on the
# provider's own page, and uses a browser checkout only where the store's
# terms were read; every breach ends; no excluded channel is on a path; and
# each path's worst case is within its published lead time.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.logistics.sla;
  q = builtins.toJSON;
  url = types.strMatching "https://.+";
  slug = types.strMatching "[a-z][a-z0-9-]*";

  day = 1440;
  # N business days, the weekend counted.
  business = n: (n + 2) * day;

  step = types.submodule {
    options = {
      channel = mkOption { type = slug; };
      access = mkOption {
        type = types.enum [
          "keyless"
          "open"
          "gated"
          "partner"
          "none"
        ];
      };
      latency = mkOption {
        type = types.enum [
          "instant"
          "published"
          "human"
        ];
        description = "Who answers inside the step: the channel at once, a file on its own cadence, or a person.";
      };
      checkout = mkOption {
        type = types.enum [
          "read"
          "api"
          "protocol"
          "browser"
        ];
        description = "How an order is placed; read where nothing is ordered.";
      };
      termsRead = mkOption {
        type = types.bool;
        default = false;
        description = "The store's terms on automated use were read whole.";
      };
      boundMin = mkOption { type = types.ints.positive; };
      basis = mkOption {
        type = types.enum [
          "stated"
          "ours"
        ];
        description = "stated: the provider's own figure (plus our margin); ours: no figure is published.";
      };
      onBreach = mkOption {
        type = types.enum [
          "retry"
          "reroute"
          "fail"
        ];
      };
      fallback = mkOption {
        type = types.nullOr slug;
        default = null;
      };
      source = mkOption { type = url; };
      evidence = mkOption {
        type = types.enum [
          "page"
          "snippet"
          "secondary"
        ];
      };
      note = mkOption {
        type = types.str;
        default = "";
      };
    };
  };

  path = types.submodule {
    options = {
      steps = mkOption { type = types.nonEmptyListOf (types.enum (lib.attrNames cfg.steps)); };
      maxLeadMin = mkOption { type = types.ints.positive; };
      why = mkOption { type = types.str; };
    };
  };

  facts = ''

    namespace Kagamizo.Logistics.Sla

    def steps : List Step := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          n: s:
          "{ name := ${q n}, channel := ${q s.channel}, access := .${s.access}, latency := .${s.latency}, checkout := .${s.checkout}, evidence := .${s.evidence}, termsRead := ${lib.boolToString s.termsRead}, boundMin := ${toString s.boundMin}, onBreach := .${s.onBreach}, fallback := ${
            if s.fallback == null then "none" else "some ${q s.fallback}"
          } }"
        ) cfg.steps
      )
    }]

    def paths : List Path := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          n: p: "{ name := ${q n}, steps := ${q p.steps}, maxLeadMin := ${toString p.maxLeadMin} }"
        ) cfg.paths
      )
    }]

    def excluded : List String := ${q (lib.attrNames cfg.excluded)}

    theorem sla_sound : sound steps paths excluded = true := by
      decide +kernel

    end Kagamizo.Logistics.Sla
  '';
in
{
  options.logistics.sla = {
    steps = mkOption { type = types.attrsOf step; };
    paths = mkOption { type = types.attrsOf path; };
    excluded = mkOption {
      type = types.attrsOf types.str;
      description = "Channels that may be on no path, each with the unbounded step that keeps it out.";
    };
    open = mkOption {
      type = types.attrsOf types.str;
      description = "What has no bounded channel yet.";
    };
  };

  config = {
    logistics.sla = {
      steps = {
        # The twin costs the design on our own host: no one else is asked.
        cost-design = {
          channel = "own-twin";
          access = "keyless";
          latency = "instant";
          checkout = "read";
          boundMin = 30;
          basis = "ours";
          onBreach = "fail";
          source = "https://github.com/Kagamizo-dev/kagamizo";
          evidence = "page";
          note = "Every stage has its own timeout; runtimes are not yet measured on the host";
        };
        part-prices = {
          channel = "digikey";
          access = "open";
          latency = "instant";
          checkout = "read";
          boundMin = 1;
          basis = "ours";
          onBreach = "retry";
          source = "https://developer.digikey.com/faq";
          evidence = "page";
          note = "Product Information v4: 120 requests a minute, 429 beyond; prices and stock only, its ordering needs a credit account";
        };
        material-rates = {
          channel = "world-bank-pink-sheet";
          access = "keyless";
          latency = "published";
          checkout = "read";
          boundMin = 1;
          basis = "ours";
          onBreach = "retry";
          source = "https://www.worldbank.org/en/research/commodity-markets";
          evidence = "page";
          note = "A monthly file; the last dated value stands between issues";
        };
        tariff = {
          channel = "usitc-hts";
          access = "keyless";
          latency = "instant";
          checkout = "read";
          boundMin = 1;
          basis = "ours";
          onBreach = "retry";
          source = "https://hts.usitc.gov/reststop/search?keyword=6211";
          evidence = "page";
          note = "Answered in under a second with no key (called 2026-11-10; release 2026 Rev 22)";
        };
        screening = {
          channel = "trade-gov-screening-list";
          access = "keyless";
          latency = "published";
          checkout = "read";
          boundMin = 1;
          basis = "ours";
          # A seller that cannot be screened is not bought from.
          onBreach = "fail";
          source = "https://developer.trade.gov";
          evidence = "page";
          note = "The bulk file needs no key and was under a day old (2026-11-10); OFAC's own files are the cross-check";
        };

        # Fabric and notions: the one purchase whose every step a store
        # states and software reaches (Shopify's agent checkout).
        fabric = {
          channel = "rockywoods";
          access = "keyless";
          latency = "instant";
          checkout = "protocol";
          boundMin = business 3;
          basis = "stated";
          onBreach = "reroute";
          fallback = "fabric-second";
          source = "https://www.rockywoods.com/policies/shipping-policy";
          evidence = "page";
          note = "\"Processing Time 3 Business Days\"";
        };
        fabric-second = {
          channel = "ripstop-by-the-roll";
          access = "keyless";
          latency = "instant";
          checkout = "protocol";
          boundMin = business 5;
          basis = "ours";
          onBreach = "fail";
          source = "https://ripstopbytheroll.com/agents.md";
          evidence = "page";
          note = "Its agents.md: orders and payment only with the buyer's authorization, through the checkout protocol, never scripted form fills";
        };

        # Cut parts. SendCutSend's own guide allows an automated checkout
        # with the buyer's authorization, requests a second apart.
        sheet-parts = {
          channel = "sendcutsend";
          access = "open";
          latency = "instant";
          checkout = "browser";
          termsRead = true;
          boundMin = business 4;
          basis = "stated";
          onBreach = "fail";
          source = "https://cdn.sendcutsend.com/specs/sendcutsend-ordering-guide.md";
          evidence = "page";
          note = "Standard \"ships in 2-4 business days\"; production starts once the files are cut-ready, so a file it rejects is our breach";
        };

        # Printed parts: a self-serve key and an order API, but no lead time
        # is stated, so the deadline is ours.
        printed-parts = {
          channel = "slant3d";
          access = "open";
          latency = "instant";
          checkout = "api";
          boundMin = business 5;
          basis = "ours";
          onBreach = "fail";
          source = "https://www.slant3dapi.com/";
          evidence = "page";
          note = "100 requests a minute; files are hand checked on its side, which our deadline bounds";
        };

        transit = {
          channel = "seller-shipping";
          access = "open";
          latency = "instant";
          checkout = "read";
          boundMin = 7 * day;
          basis = "ours";
          onBreach = "fail";
          source = "https://sendcutsend.com/shipping/";
          evidence = "page";
          note = "Within the United States only, so no customs; a breach is an alert and a claim, tracked by the carrier's own number";
        };

        # Declared, and on no path until its provider's pages are read.
        buy-parts = {
          channel = "mouser";
          access = "open";
          latency = "instant";
          checkout = "api";
          boundMin = business 1;
          basis = "stated";
          onBreach = "fail";
          source = "https://www.mouser.com/api-search/";
          evidence = "snippet";
          note = "Order API with a card saved on the account, same-day shipping before 8 p.m. Central: from search snippets only, its pages refused the reader";
        };
        bare-boards = {
          channel = "osh-park";
          access = "open";
          latency = "instant";
          checkout = "browser";
          boundMin = business 7;
          basis = "stated";
          onBreach = "fail";
          source = "https://docs.oshpark.com/services/";
          evidence = "page";
          note = "Super Swift \"4-5 business days\", made in the United States; its terms on automated checkout are not read yet";
        };
        cut-parts-guaranteed = {
          channel = "osh-cut";
          access = "open";
          latency = "instant";
          checkout = "browser";
          boundMin = business 4;
          basis = "stated";
          onBreach = "fail";
          source = "https://oshcut.com/faq";
          evidence = "page";
          note = "\"We guarantee whatever lead-time you select during checkout\"; its terms on automated checkout are not read yet";
        };
      };

      paths.vest-kit-of-parts = {
        steps = [
          "cost-design"
          "part-prices"
          "material-rates"
          "tariff"
          "screening"
          "fabric"
          "sheet-parts"
          "printed-parts"
          "transit"
        ];
        # The purchases run side by side; the sum is the bound proved, so
        # the published figure is safe and not yet tight.
        maxLeadMin = 35 * day;
        why = "Everything the vest is made of, costed, screened, bought and delivered, with no step that waits";
      };

      excluded = {
        jlcpcb = "its API is by application, reviewed with no stated time";
        lcsc = "its API is by application, reviewed with no stated time";
        pcbway = "its API is approved by email";
        aliexpress = "its order API needs an app review";
        amazon-business = "ordering needs the Amazon Business team's approval";
        arrow = "keys come through sales";
        mcmaster-carr = "its API is for approved customers";
        alibaba-com = "a request for quotes is answered by a person";
        sewport = "a request for quotes is answered by a person";
        taobao-1688 = "closed without a Chinese legal entity";
        cbp-entry = "a formal entry needs a licensed broker, and no carrier states a clearance time";
      };

      open = {
        cut-and-sew = "No maker sews from our own pattern with a stated price and lead time; the vest is a kit of parts until one does";
        assembled-boards = "CircuitHub quotes and orders by API, but its key is a 24-hour browser sign-in and it sets up the billing account itself";
        bare-boards = "OSH Park is self-serve with a stated lead time; its terms on automated checkout are to be read";
        machined-parts = "No maker has an order API; Protolabs Network reviews within 48 hours and its checkout terms are to be read";
        buy-parts = "Mouser's order terms rest on search snippets until its pages are read from the host";
        imports = "The de minimis exemption is suspended for every shipment (2026), so an import always meets customs: United States makers and stock only";
        payment = "An order is paid from the buying agent's own bounded card, whose limit is the control: an approval per order would be a wait";
      };
    };

    perSystem =
      { config, ... }:
      {
        checks.logistics-sla = config.kagamizo.leanCheck {
          name = "logistics-sla";
          source = ./_lean/Sla.lean;
          inherit facts;
        };
      };
  };
}
