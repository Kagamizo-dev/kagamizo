//! logistics: the book (channels, hubs, the outfit) and the reliability-first
//! route rule of ../_lean/Logistics.lean, over live quotes.
//!
//!   logistics channels [--op OP] [--region R] [--kind K] [--automated]
//!   logistics hubs
//!   logistics outfit [--json]
//!   logistics source <garment>
//!   logistics rank <quotes.json> --deadline-hours H [--floor-bp B]
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

fn pct(bp: u64) -> String {
    format!("{}.{:02}%", bp / 100, bp % 100)
}

fn usage() -> ExitCode {
    eprintln!(
        "usage: logistics channels [--op OP] [--region R] [--kind K] [--automated]\n\
         \x20      logistics hubs | outfit [--json] | source <garment> | book\n\
         \x20      logistics rank <quotes.json> --deadline-hours H [--floor-bp B]"
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
                op.as_deref().is_none_or(|w| w == o.as_str()) && (!automated || v.access != "none")
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
            println!("  water     at least {} mm hydrostatic head", g.water_column_mm);
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
    println!("Where {garment} ({}, {}) can come from:", g.kind, g.condition);
    for (name, c) in &book.channels {
        if !kinds.contains(&c.kind.as_str())
            || !c.goods.iter().any(|x| x == "general" || x == "apparel")
        {
            continue;
        }
        let found = c.ops.get("search").or_else(|| c.ops.get("quote"));
        let how = match found.map(|o| o.access.as_str()) {
            Some("open") => "agents query it now",
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
    sorted.sort_by(|a, b| {
        rel(b)
            .cmp(&rel(a))
            .then(a.cost_cents.cmp(&b.cost_cents))
    });
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
    fn book_parses() {
        let b: Book = serde_json::from_str(BOOK).unwrap();
        assert!(!b.channels.is_empty() && !b.outfit.garments.is_empty());
    }
}
