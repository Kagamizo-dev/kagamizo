/-
The logistics module's paper: from a specification to a thing in hand.
Checked by checks.paper-logistics (modules/repo/papers.nix).
-/
open Kagamizo.Paper

def paper : Paper := {
  module := "logistics",
  title := "Reliability before price: a typed path from a specification to a thing in the owner's hands, anywhere",
  abstract := "The logistics module declares every channel a thing can be found, made, carried, held or handed over through (marketplaces, resale sites, makers, carriers, couriers and holding points), each operation typed by how software may reach it and cited to the page that says so; the hubs where things land, chosen by airport; and the first order, a fully wearable kit typed down to pockets and fabric. Lean proves that no channel whose terms forbid automation is automated, that the outfit carries every device of the kit with no pack, and that the route chosen is the most reliable one that meets the deadline, price only breaking ties.",
  authors := ["twin", "upkeep"],
  date := "2026-11-08",
  sections := [
    { kind := .purpose,
      body := "The owner wants to describe a thing down to its exact specification and have it bought, shipped to the best place for wherever they are, and fetched by a courier, so they never search a marketplace by hand. Their rule (2026-11-08) is that reliability comes first: a drastically better price never outranks the certainty that a thing arrives, or can be collected, at a given place and time. Without this module every purchase is a manual search across sites with no shared vocabulary, no record of which sites software may touch, and no way to compare routes on what matters. The module makes the channels, the hubs, the specifications and the rule for choosing a route typed values.",
      cites := ["sheffi-resilient"] },
    { kind := .lifecycle,
      body := "Declared: logistics.channels (./channels.nix) with every operation's access, source and evidence; logistics.hubs and logistics.outfit (./outfit.nix); logistics.owner, Mirazo, the owner himself, by the owner's decision of 2026-11-08 until an LLC earns its keep. Checked: checks.logistics on every push. Changed: a channel whose account the owner opens gains `account` and its operations move from gated to reachable; a page read whole moves its evidence from snippet to page; a bought garment's specification gives way to the product's own figures. Run: agents search, specify, quote and rank; the owner approves every payment. Retired: a channel that closes or changes its terms is edited in the same commit, and the proof must still hold.",
      cites := ["dolstra-thesis"] },
    { kind := .pipeline,
      body := "checks.logistics renders the channels, the regions, the hubs, the kit's slots (from modules/kit, with which of them hold a device) and the outfit's garments as Lean facts after ./_lean/Logistics.lean and decides logistics_sound by the kernel. packages.logistics-book renders the same declarations as JSON, and packages.logistics compiles that book into the Rust CLI, whose unit tests (run in its build) hold its ranking to Lean's: reliability beats price, price breaks ties, the deadline and the floor exclude. checks.paper-logistics holds this paper to the repository. It deploys two ways: the CLI is on the Yoga image's PATH (modules/yoga-c940), and the shell's Logistics card (./library.nix) shows a page generated from the same declarations, on the Yoga and in the browser: the wearable kit pocket by pocket, the should-cost, the hubs, and every channel by how it is reached.",
      cites := ["lean4"] },
    { kind := .agents,
      body := "twin owns the module while no logistics team is chartered (the plan's data/logistics-team): the outfit is the physical side of the owner's twin and the kit's slots are its pockets. upkeep keeps the CLI and its pins building. No agent spends: Cedar's base layer forbids agents any spend, and every order is the owner's approve-payment step. Agents may query only the operations whose access is open or gated on an account the owner holds, never a channel whose terms forbid automation, and they send nothing to a supplier or courier in the owner's name without the owner's approval.",
      cites := ["sheffi-resilient"] },
    { kind := .tools,
      body := "packages.logistics is the CLI. `logistics cost <garment>` prints a should-cost line by line, or which rates are still unpriced and where each will come from; `logistics rfq <garment>` renders the request for quotes a supplier receives (the specification, our bill of materials and operations to confirm or correct, the Incoterm, and an ISO 2859-1 inspection plan); `logistics accept` judges a quote against the should-cost by Lean's rule. `logistics channels` filters the channels by operation, region, kind or reachability and prints each operation's access, source and evidence, with published on-time rates, guarantees and buyer protection. `logistics hubs` lists where things land. `logistics outfit` prints the wearable kit as a buying specification, pocket by pocket with the devices each holds. `logistics source <garment>` says, per channel, whether agents can query it now, once an account is approved, or only the owner by hand, and who places the order. `logistics rank` reads priced routes and picks one by Lean's rule.",
      cites := ["lean4"] },
    { kind := .data,
      body := "The channels were researched on 2026-11-08 from search results over each provider's own pages (Amazon Business, Amazon's Creators API, AliExpress's open platform, OTCommerce, Mercado Libre, eBay, Depop, Vinted, Poshmark, Grailed, The RealReal, Printful, Printify, JLCPCB, Sewport, UPS, FedEx, DHL, EasyPost, YunExpress, Uber Direct, Lalamove, DoorDash, InPost and Cainiao); every source is a URL and every claim carries its evidence. The reliability priors are ShipMatrix's 2025 peak-season on-time rates as reported by FreightWaves. Quotes are read at run time and never committed; the owner's whereabouts never enter the repository, which is public.",
      cites := ["shipmatrix-2025"] },
    { kind := .design,
      body := "A channel is a set of operations (search, specs, quote, order, track, locate, collect, proof), each open, gated, partner or none, so what software may do is a property of the declaration and not of a script. Data comes keyless first (the owner's direction, 2026-11-08): Shopify's Global Catalog and stores, WooCommerce's Store API, Web Data Commons, OpenStreetMap, USPS's price and standards files, BTS, Eurostat, ANAC, the tariff schedules, NWS, FAA and ILOSTAT need no account; an account exists only where a payment or a dispatch needs one, and only with a second factor that is not a phone number. A thing's should-cost is its bill of materials, machine time and labour, so every quote is negotiated against it, and the request goes to the supplier's own channel. A route is a chain of legs, each with a reliability in basis points and a worst-case duration; its reliability is the product of its legs', computed in whole basis points the same way in Lean and in Rust, which treats legs as independent (the optimistic case, stated so that a correlated failure is a known gap). The outfit is typed against the kit: a garment's pockets are the kit's slots, so the kit's devices decide what the clothes must hold.",
      cites := ["lean4", "sheffi-resilient"] },
    { kind := .guarantees,
      body := "forbidden_is_manual: a channel that is sound and whose terms forbid automation offers no automated operation. pick_ge and pick_cases: choosing between two routes keeps one of them and never a less reliable one. foldl_ge: the route kept over a list is at least as reliable as every route in it. foldl_keeps: any property every candidate has, the kept route has. best_most_reliable: the best of a list is at least as reliable as each of its routes. choose_sound: the chosen route meets the deadline and the reliability floor, and no route that meets them is more reliable, so price can only break a tie. total_append_ge: adding a line to a bill never lowers its cost. unpriced_has_no_cost: a thing with a line whose rate no source has priced has no should-cost, so nothing is negotiated against a guess. accepted_is_bounded: an accepted quote carries an inspection plan and sits within the declared premium of the should-cost. The rendered theorem logistics_sound decides the declarations: unique names, no scraping, a hub for every region and exactly one home, and an outfit whose pockets hold every used slot, that washes, weighs at most its limit and has no pack.",
      cites := ["lean4"] },
    { kind := .performance,
      body := "No perf target is declared. The check decides over thirty channels, four hubs, nine kit slots and seven garments in seconds, and ranking is linear in the number of routes. What will matter is delivery itself: the share of orders that arrive or are collected inside their window, measured from our own deliveries and replacing the published priors per channel and lane, with a target set once there are twenty orders to measure. That measurement is the module's reason to exist and becomes its perf target.",
      cites := ["shipmatrix-2025"] },
    { kind := .priorWork,
      body := "Sheffi's work on resilient supply chains argues that redundancy and flexibility, not the lowest unit cost, decide whether goods arrive when a link fails; this module encodes that priority as the order of comparison. ShipMatrix's on-time measurements of the large parcel carriers give the first priors. Nix's purely functional deployment, after Dolstra, makes the declarations a value checked before use, and Lean 4 decides the rules by the kernel. Procurement suites keep catalogues, suppliers and approvals in one schema; this module does the same for one person, with the schema typed and the choice of route proved.",
      cites := ["sheffi-resilient", "shipmatrix-2025", "dolstra-thesis", "lean4"] },
    { kind := .gaps,
      body := "No account is held yet: Uber Direct, Lalamove, UPS's developer access, eBay's keys, AliExpress's open platform and Amazon Business are each the owner's sign-up, so every gated operation waits on them. No provider page has been read whole: the developer hosts are outside the session's allowlist, so every claim is a search snippet or secondary until they are added. Live quoting, the courier hand-off at a holding point, flight data for choosing the hubs, the owner's body measurements for sizes, image and 3D previews of a specification through OpenRouter and a 3D API, bills of materials, and translated requests to Chinese makers are the next items in the plan's data and make tracks.",
      cites := ["sheffi-resilient"] }
  ],
  citations := [
    { key := "sheffi-resilient", title := "The Resilient Enterprise: Overcoming Vulnerability for Competitive Advantage", authors := ["Yossi Sheffi"], year := 2005,
      source := .url "https://mitpress.mit.edu/9780262693493/the-resilient-enterprise/" },
    { key := "shipmatrix-2025", title := "Large parcel carriers improved on-time delivery during 2025 peak season", authors := ["FreightWaves"], year := 2026,
      source := .url "https://www.freightwaves.com/news/large-parcel-carriers-improved-on-time-delivery-during-2025-peak-season" },
    { key := "dolstra-thesis", title := "The Purely Functional Software Deployment Model", authors := ["Eelco Dolstra"], year := 2006,
      source := .url "https://edolstra.github.io/pubs/phd-thesis.pdf" },
    { key := "lean4", title := "The Lean 4 Theorem Prover and Programming Language", authors := ["Leonardo de Moura", "Sebastian Ullrich"], year := 2021,
      source := .doi "10.1007/978-3-030-79876-5_37" }
  ],
  theorems := ["forbidden_is_manual", "pick_ge", "pick_cases", "foldl_ge", "foldl_keeps", "best_most_reliable", "choose_sound", "total_append_ge", "unpriced_has_no_cost", "accepted_is_bounded"],
  perf := [],
  checks := ["logistics", "paper-logistics"],
  packages := ["logistics", "logistics-book"],
  agents := ["twin", "upkeep"]
}
