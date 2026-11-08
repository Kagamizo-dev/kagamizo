//! logistics: the book (channels, hubs, the outfit) and the reliability-first
//! route rule of ../_lean/Logistics.lean, over live quotes.
//!
//!   logistics channels [--op OP] [--region R] [--kind K] [--automated]
//!   logistics hubs
//!   logistics outfit [--json]
//!   logistics source <garment>
//!   logistics rank <quotes.json> --deadline-hours H [--floor-bp B]
//!   logistics cost <garment>        its should-cost, or what is unpriced
//!   logistics rfq <garment>         the request for quotes a supplier gets
//!   logistics accept <garment> --quote-cents N [--inspection]
//!   logistics book
//!
//! The book is rendered by ../logistics.nix and compiled in (LOGISTICS_BOOK).
//! `rank` reads routes priced at run time; it picks exactly as Lean's
//! `choose` does: among routes that meet the deadline and the floor, the most
//! reliable, and the cheaper only between equally reliable ones.

use serde::Deserialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::process::ExitCode;

const BOOK: &str = include_str!(env!("LOGISTICS_BOOK"));

#[derive(Deserialize)]
struct Op {
    access: String,
    source: String,
    evidence: String,
}

#[derive(Deserialize)]
struct Terms {
    position: String,
}

#[derive(Deserialize)]
struct Channel {
    kind: String,
    goods: Vec<String>,
    regions: Vec<String>,
    terms: Terms,
    ops: BTreeMap<String, Op>,
    protection: Option<String>,
    guarantee: Option<String>,
    prior: Option<Prior>,
    note: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Prior {
    on_time_bp: u64,
}

#[derive(Deserialize)]
struct Hub {
    region: String,
    airports: Vec<String>,
    status: String,
    why: String,
}

#[derive(Deserialize)]
struct Shell {
    fibre: String,
    gsm: u64,
    denier: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Garment {
    kind: String,
    pockets: BTreeMap<String, u64>,
    extra_pockets: u64,
    mass_g: u64,
    shell: Shell,
    water_column_mm: u64,
    closures: Vec<String>,
    attachment: String,
    washable: bool,
    condition: String,
    note: String,
    bom: Option<Bom>,
}

#[derive(Deserialize)]
struct Material {
    name: String,
    rate: String,
    qty: f64,
    basis: String,
}

#[derive(Deserialize)]
struct Operation {
    name: String,
    machine: String,
    labour: String,
    minutes: f64,
}

#[derive(Deserialize)]
struct Bom {
    quantity: u64,
    materials: Vec<Material>,
    operations: Vec<Operation>,
}

#[derive(Deserialize)]
struct Rate {
    unit: String,
    cents: Option<u64>,
    source: Option<String>,
    evidence: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Inspection {
    level: String,
    major_aql: String,
    minor_aql: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct QuotePolicy {
    premium_pct: u64,
    incoterm: String,
    inspection: Inspection,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Outfit {
    worn: Vec<String>,
    max_mass_g: u64,
    garments: BTreeMap<String, Garment>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct KitItem {
    device: String,
    slot: String,
    volume_ml: u64,
    owned: bool,
}

#[derive(Deserialize)]
struct Kit {
    items: BTreeMap<String, KitItem>,
}

#[derive(Deserialize)]
struct Book {
    owner: String,
    channels: BTreeMap<String, Channel>,
    hubs: BTreeMap<String, Hub>,
    outfit: Outfit,
    kit: Kit,
    rates: BTreeMap<String, Rate>,
    quotes: QuotePolicy,
}

#[derive(Deserialize, Clone)]
struct Leg {
    channel: String,
    bp: u64,
    hours: u64,
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
struct Route {
    name: String,
    legs: Vec<Leg>,
    cost_cents: u64,
}

#[derive(Deserialize)]
struct Quotes {
    routes: Vec<Route>,
}

/// Lean's `Route.rel`: legs taken as independent, rounded down each step.
fn rel(r: &Route) -> u64 {
    r.legs.iter().fold(10_000, |a, l| a * l.bp / 10_000)
}

fn hours(r: &Route) -> u64 {
    r.legs.iter().map(|l| l.hours).sum()
}

/// Lean's `pick`: keep `a` unless `b` is more reliable, or as reliable and cheaper.
fn pick(a: Route, b: Route) -> Route {
    let (ra, rb) = (rel(&a), rel(&b));
    if ra < rb || (rb == ra && b.cost_cents < a.cost_cents) {
        b
    } else {
        a
    }
}

/// Lean's `choose`.
fn choose(floor: u64, deadline: u64, routes: &[Route]) -> Option<Route> {
    let mut eligible = routes
        .iter()
        .filter(|r| floor <= rel(r) && hours(r) <= deadline)
        .cloned();
    let first = eligible.next()?;
    Some(eligible.fold(first, pick))
}

/// One should-cost line, as Lean's `Line`: thousandths of a unit at a rate.
struct Line {
    name: String,
    rate: String,
    qty_milli: u64,
}

fn lines(bom: &Bom) -> Vec<Line> {
    let milli = |x: f64| (x * 1000.0).round() as u64;
    let mut out: Vec<Line> = bom
        .materials
        .iter()
        .map(|m| Line {
            name: m.name.clone(),
            rate: m.rate.clone(),
            qty_milli: milli(m.qty),
        })
        .collect();
    for o in &bom.operations {
        for (who, rate) in [("machine", &o.machine), ("labour", &o.labour)] {
            out.push(Line {
                name: format!("{} ({who})", o.name),
                rate: rate.clone(),
                qty_milli: milli(o.minutes / 60.0),
            });
        }
    }
    out
}

/// Lean's `shouldCost`: the sum, or none while any line is unpriced.
fn should_cost(book: &Book, ls: &[Line]) -> Option<u64> {
    ls.iter()
        .map(|l| book.rates[&l.rate].cents.map(|c| l.qty_milli * c / 1000))
        .sum()
}

/// Lean's `acceptable`.
fn acceptable(should: u64, premium: u64, cents: u64, inspection: bool) -> bool {
    inspection && cents * 100 <= should * (100 + premium)
}

fn bom_of<'a>(book: &'a Book, garment: &str) -> Result<(&'a Garment, &'a Bom), ExitCode> {
    match book.outfit.garments.get(garment) {
        None => {
            eprintln!("no garment {garment}");
            Err(ExitCode::from(1))
        }
        Some(g) => match &g.bom {
            None => {
                eprintln!("{garment} has no bill of materials yet");
                Err(ExitCode::from(1))
            }
            Some(b) => Ok((g, b)),
        },
    }
}

fn cost(book: &Book, garment: &str) -> ExitCode {
    let (_, bom) = match bom_of(book, garment) {
        Ok(x) => x,
        Err(e) => return e,
    };
    let ls = lines(bom);
    println!("Should-cost of one {garment}, per line:");
    for l in &ls {
        let r = &book.rates[&l.rate];
        let qty = format!(
            "{}.{:03} {}",
            l.qty_milli / 1000,
            l.qty_milli % 1000,
            r.unit
        );
        match r.cents {
            Some(c) => println!(
                "  {:36} {qty:>12}  {:>9.2} USD",
                l.name,
                (l.qty_milli * c / 1000) as f64 / 100.0
            ),
            None => println!(
                "  {:36} {qty:>12}  unpriced ({}: {}{})",
                l.name,
                l.rate,
                r.evidence,
                r.source
                    .as_deref()
                    .map(|s| format!(", from {s}"))
                    .unwrap_or_else(|| ", from a supplier's quote".into())
            ),
        }
    }
    let estimates = bom
        .materials
        .iter()
        .filter(|m| m.basis == "estimate")
        .count();
    match should_cost(book, &ls) {
        Some(c) => {
            println!(
                "\nShould-cost: {:.2} USD a unit, {:.2} USD for {}; quotes up to {}% above are acceptable with an inspection plan.",
                c as f64 / 100.0,
                (c * bom.quantity) as f64 / 100.0,
                bom.quantity,
                book.quotes.premium_pct
            );
            ExitCode::SUCCESS
        }
        None => {
            let missing: std::collections::BTreeSet<&str> = ls
                .iter()
                .filter(|l| book.rates[&l.rate].cents.is_none())
                .map(|l| l.rate.as_str())
                .collect();
            println!(
                "\nNo should-cost yet: {} rates unpriced ({}); {} quantities are estimates. Nothing is negotiated against a guess.",
                missing.len(),
                missing.into_iter().collect::<Vec<_>>().join(", "),
                estimates
            );
            ExitCode::from(3)
        }
    }
}

fn rfq(book: &Book, garment: &str) -> ExitCode {
    let (g, bom) = match bom_of(book, garment) {
        Ok(x) => x,
        Err(e) => return e,
    };
    let q = &book.quotes;
    println!(
        "REQUEST FOR QUOTATION: {garment} ({}), {} units",
        g.kind, bom.quantity
    );
    println!("\nWhat it is: {}", g.note);
    println!(
        "Shell: {} {}D, {} g/m2; water column at least {} mm (ISO 811); closures {}; webbing {}.",
        g.shell.fibre,
        g.shell.denier,
        g.shell.gsm,
        g.water_column_mm,
        g.closures.join(", "),
        g.attachment
    );
    println!("Mass at most {} g. Machine washable.", g.mass_g);
    for (slot, ml) in &g.pockets {
        println!("Pocket {slot}: at least {ml} ml.");
    }
    println!("\nOur bill of materials (please confirm or correct each line):");
    for m in &bom.materials {
        let unit = &book.rates[&m.rate].unit;
        println!("  - {}: {} {unit} per unit ({})", m.name, m.qty, m.basis);
    }
    println!("Our operations (minutes per unit):");
    for o in &bom.operations {
        println!("  - {}: {} min", o.name, o.minutes);
    }
    println!(
        "\nPlease quote, per unit and in total, {} to the delivery address we give:",
        q.incoterm
    );
    println!("  materials (per line), machine time, labour, overhead and margin, freight, duties.");
    println!(
        "Quality: inspection before shipment per ISO 2859-1, general level {}, AQL {} major and {} minor, with photos of the sample.",
        q.inspection.level, q.inspection.major_aql, q.inspection.minor_aql
    );
    println!("Lead time: days to ship, and days in transit.");
    println!("\n(Sent from the owner's address through the supplier's own channel, once the owner approves.)");
    ExitCode::SUCCESS
}

fn accept(book: &Book, garment: &str, args: &[String]) -> ExitCode {
    let (_, bom) = match bom_of(book, garment) {
        Ok(x) => x,
        Err(e) => return e,
    };
    let Some(quote) = flag(args, "--quote-cents").and_then(|c| c.parse::<u64>().ok()) else {
        return usage();
    };
    let inspection = args.iter().any(|a| a == "--inspection");
    let Some(should) = should_cost(book, &lines(bom)) else {
        println!("No should-cost yet (`logistics cost {garment}`): a quote cannot be judged.");
        return ExitCode::from(3);
    };
    let ok = acceptable(should, book.quotes.premium_pct, quote, inspection);
    println!(
        "Quote {:.2} USD a unit against a should-cost of {:.2} (premium cap {}%){}: {}",
        quote as f64 / 100.0,
        should as f64 / 100.0,
        book.quotes.premium_pct,
        if inspection {
            ""
        } else {
            ", no inspection plan"
        },
        if ok {
            "acceptable; it waits on the owner's approval"
        } else {
            "refused"
        }
    );
    if ok {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(4)
    }
}

fn pct(bp: u64) -> String {
    format!("{}.{:02}%", bp / 100, bp % 100)
}

fn usage() -> ExitCode {
    eprintln!(
        "usage: logistics channels [--op OP] [--region R] [--kind K] [--automated]\n\
         \x20      logistics hubs | outfit [--json] | source <garment> | book\n\
         \x20      logistics rank <quotes.json> --deadline-hours H [--floor-bp B]\n\
         \x20      logistics cost|rfq <garment> | accept <garment> --quote-cents N [--inspection]"
    );
    ExitCode::from(2)
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1).cloned())
}

fn channels(book: &Book, args: &[String]) {
    let op = flag(args, "--op");
    let region = flag(args, "--region");
    let kind = flag(args, "--kind");
    let automated = args.iter().any(|a| a == "--automated");
    let keyless = args.iter().any(|a| a == "--keyless");
    for (name, c) in &book.channels {
        if kind.as_deref().is_some_and(|k| k != c.kind)
            || region
                .as_deref()
                .is_some_and(|r| !c.regions.iter().any(|x| x == r || x == "global"))
        {
            continue;
        }
        let shown: Vec<(&String, &Op)> = c
            .ops
            .iter()
            .filter(|(o, v)| {
                op.as_deref().is_none_or(|w| w == o.as_str())
                    && (!automated || v.access != "none")
                    && (!keyless || v.access == "keyless")
            })
            .collect();
        if shown.is_empty() {
            continue;
        }
        println!(
            "{name} ({}, {}; terms {})",
            c.kind,
            c.regions.join(", "),
            c.terms.position
        );
        for (o, v) in shown {
            println!("  {o:8} {:8} {} [{}]", v.access, v.source, v.evidence);
        }
        if let Some(p) = &c.prior {
            println!("  on time  {} (published)", pct(p.on_time_bp));
        }
        for (label, text) in [
            ("protects", &c.protection),
            ("guarant.", &c.guarantee),
            ("note", &c.note),
        ] {
            if let Some(t) = text {
                println!("  {label:8} {t}");
            }
        }
    }
}

fn hubs(book: &Book) {
    for (name, h) in &book.hubs {
        println!(
            "{name} [{}] {} via {}: {}",
            h.status,
            h.region,
            h.airports.join(" "),
            h.why
        );
    }
}

fn outfit(book: &Book) {
    let o = &book.outfit;
    let total: u64 = o.garments.values().map(|g| g.mass_g).sum();
    println!(
        "The wearable kit, for {}: {} garments, at most {} g of {} g allowed; no pack.",
        book.owner,
        o.garments.len(),
        total,
        o.max_mass_g
    );
    for (name, g) in &o.garments {
        println!("\n{name} ({}, {}):", g.kind, g.condition);
        println!("  {}", g.note);
        let fabric = match (g.shell.gsm, g.shell.denier) {
            (0, 0) => g.shell.fibre.clone(),
            (0, d) => format!("{} {d}D", g.shell.fibre),
            (s, 0) => format!("{} {s} g/m2", g.shell.fibre),
            (s, d) => format!("{} {d}D, {s} g/m2", g.shell.fibre),
        };
        println!("  fabric    {fabric}");
        if g.water_column_mm > 0 {
            println!(
                "  water     at least {} mm hydrostatic head",
                g.water_column_mm
            );
        }
        println!(
            "  closes    {}; webbing {}; {}",
            g.closures.join(", "),
            g.attachment,
            if g.washable {
                "machine washable"
            } else {
                "not washable"
            }
        );
        println!(
            "  mass      at most {} g; {} free pockets",
            g.mass_g, g.extra_pockets
        );
        for (slot, ml) in &g.pockets {
            let holds: Vec<String> = book
                .kit
                .items
                .iter()
                .filter(|(_, i)| &i.slot == slot)
                .map(|(n, i)| {
                    format!(
                        "{n} ({} ml{})",
                        i.volume_ml,
                        if i.owned { "" } else { ", proposed" }
                    )
                })
                .collect();
            println!(
                "  pocket    {slot}: at least {ml} ml, holds {}",
                if holds.is_empty() {
                    "nothing yet".into()
                } else {
                    holds.join(", ")
                }
            );
        }
    }
    let worn: Vec<String> = book
        .kit
        .items
        .iter()
        .filter(|(_, i)| o.worn.contains(&i.slot))
        .map(|(n, i)| format!("{n} ({})", i.device))
        .collect();
    if !worn.is_empty() {
        println!("\nWorn directly: {}", worn.join(", "));
    }
}

fn source(book: &Book, garment: &str) -> ExitCode {
    let Some(g) = book.outfit.garments.get(garment) else {
        eprintln!(
            "no garment {garment}; known: {}",
            book.outfit
                .garments
                .keys()
                .cloned()
                .collect::<Vec<_>>()
                .join(", ")
        );
        return ExitCode::from(1);
    };
    let kinds: &[&str] = if g.condition == "new" {
        &["marketplace", "maker"]
    } else {
        &["marketplace", "resale", "maker"]
    };
    println!(
        "Where {garment} ({}, {}) can come from:",
        g.kind, g.condition
    );
    for (name, c) in &book.channels {
        if !kinds.contains(&c.kind.as_str())
            || !c.goods.iter().any(|x| x == "general" || x == "apparel")
        {
            continue;
        }
        let found = c.ops.get("search").or_else(|| c.ops.get("quote"));
        let how = match found.map(|o| o.access.as_str()) {
            Some("keyless") => "agents query it now, no account",
            Some("open") => "agents query it with a self-serve key",
            Some("gated") => "agents query it once the owner's account is approved",
            Some("partner") => "needs a partner contract",
            _ => {
                if c.terms.position == "forbidden" {
                    "the owner browses it: its terms forbid automation"
                } else {
                    "the owner browses it: no API"
                }
            }
        };
        let order = match c.ops.get("order").map(|o| o.access.as_str()) {
            Some("open") | Some("gated") => "; orders by API, after the owner approves the payment",
            _ => "; the owner places the order",
        };
        println!("  {name:16} {how}{order}");
    }
    ExitCode::SUCCESS
}

fn rank(book: &Book, args: &[String]) -> ExitCode {
    let (Some(path), Some(deadline)) = (
        args.first(),
        flag(args, "--deadline-hours").and_then(|d| d.parse::<u64>().ok()),
    ) else {
        return usage();
    };
    let floor = flag(args, "--floor-bp")
        .and_then(|f| f.parse::<u64>().ok())
        .unwrap_or(0);
    let quotes: Quotes = match std::fs::read_to_string(path)
        .map_err(|e| e.to_string())
        .and_then(|s| serde_json::from_str(&s).map_err(|e| e.to_string()))
    {
        Ok(q) => q,
        Err(e) => {
            eprintln!("{path}: {e}");
            return ExitCode::from(1);
        }
    };
    let mut bad = false;
    for r in &quotes.routes {
        for l in &r.legs {
            if !book.channels.contains_key(&l.channel) {
                eprintln!("{}: no channel {}", r.name, l.channel);
                bad = true;
            }
            if l.bp > 10_000 {
                eprintln!("{}: {} above 10000 bp", r.name, l.channel);
                bad = true;
            }
        }
    }
    if bad {
        return ExitCode::from(1);
    }
    let mut sorted = quotes.routes.clone();
    sorted.sort_by(|a, b| rel(b).cmp(&rel(a)).then(a.cost_cents.cmp(&b.cost_cents)));
    println!(
        "Routes, most reliable first (deadline {deadline} h, floor {}):",
        pct(floor)
    );
    for r in &sorted {
        let ok = floor <= rel(r) && hours(r) <= deadline;
        println!(
            "  {} {:24} {:>7}  {:>4} h  {:>9.2} USD  {}",
            if ok { "+" } else { "-" },
            r.name,
            pct(rel(r)),
            hours(r),
            r.cost_cents as f64 / 100.0,
            r.legs
                .iter()
                .map(|l| l.channel.as_str())
                .collect::<Vec<_>>()
                .join(" > ")
        );
    }
    match choose(floor, deadline, &quotes.routes) {
        Some(b) => {
            println!(
                "\nChosen: {} at {}, {} h, {:.2} USD. It waits on the owner's approval of the payment.",
                b.name,
                pct(rel(&b)),
                hours(&b),
                b.cost_cents as f64 / 100.0
            );
            ExitCode::SUCCESS
        }
        None => {
            println!("\nNo route meets the deadline and the floor.");
            ExitCode::from(3)
        }
    }
}

fn main() -> ExitCode {
    let book: Book = serde_json::from_str(BOOK).expect("the compiled-in book is the Nix rendering");
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(cmd) = args.first() else {
        return usage();
    };
    let rest = &args[1..];
    match cmd.as_str() {
        "channels" => channels(&book, rest),
        "hubs" => hubs(&book),
        "outfit" if rest.iter().any(|a| a == "--json") => {
            let v: Value = serde_json::from_str(BOOK).expect("book");
            println!("{}", v["outfit"]);
        }
        "outfit" => outfit(&book),
        "source" => {
            return match rest.first() {
                Some(g) => source(&book, g),
                None => usage(),
            }
        }
        "rank" => return rank(&book, rest),
        "cost" | "rfq" | "accept" => {
            let Some(g) = rest.first() else {
                return usage();
            };
            return match cmd.as_str() {
                "cost" => cost(&book, g),
                "rfq" => rfq(&book, g),
                _ => accept(&book, g, &rest[1..]),
            };
        }
        "book" => println!("{BOOK}"),
        _ => return usage(),
    }
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn route(name: &str, bps: &[u64], cost: u64) -> Route {
        Route {
            name: name.into(),
            legs: bps
                .iter()
                .map(|&bp| Leg {
                    channel: "ups".into(),
                    bp,
                    hours: 10,
                })
                .collect(),
            cost_cents: cost,
        }
    }

    #[test]
    fn reliability_beats_price() {
        let rs = [
            route("cheap", &[9000], 100),
            route("sure", &[9900], 100_000),
        ];
        assert_eq!(choose(0, 100, &rs).unwrap().name, "sure");
    }

    #[test]
    fn price_breaks_ties() {
        let rs = [route("a", &[9500], 500), route("b", &[9500], 300)];
        assert_eq!(choose(0, 100, &rs).unwrap().name, "b");
    }

    #[test]
    fn deadline_and_floor_exclude() {
        let rs = [route("slow", &[9999, 9999], 1), route("weak", &[5000], 1)];
        assert!(choose(9000, 15, &rs).is_none());
    }

    #[test]
    fn rel_is_lean_rel() {
        assert_eq!(rel(&route("x", &[9720, 9500], 0)), 9234);
    }

    #[test]
    fn acceptance_is_lean_acceptable() {
        assert!(acceptable(10_000, 15, 11_500, true));
        assert!(!acceptable(10_000, 15, 11_501, true));
        assert!(!acceptable(10_000, 15, 5_000, false));
    }

    #[test]
    fn unpriced_vest_has_no_cost() {
        let b: Book = serde_json::from_str(BOOK).unwrap();
        let bom = b.outfit.garments["vest"].bom.as_ref().unwrap();
        let ls = lines(bom);
        assert_eq!(ls.len(), bom.materials.len() + 2 * bom.operations.len());
        if ls.iter().any(|l| b.rates[&l.rate].cents.is_none()) {
            assert!(should_cost(&b, &ls).is_none());
        }
    }

    #[test]
    fn book_parses() {
        let b: Book = serde_json::from_str(BOOK).unwrap();
        assert!(!b.channels.is_empty() && !b.outfit.garments.is_empty());
    }
}
