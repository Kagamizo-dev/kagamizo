//! `inventory`: the owner's items, against the schema ../default.nix renders
//! (INVENTORY_FACTS). The items are one document, kept by `statestore` in
//! the declared vault, or in the file INVENTORY_STORE names (a stand-in).
//! Quantities and amounts are whole hundredths, as ../_lean/Inventory.lean
//! proves `use`, `restock` and `low` over.

use std::io::Write;
use std::process::{Command, Stdio};

include!(env!("INVENTORY_FACTS"));

const HEADER: &str = "#kagamizo-inventory\tv1";
const USAGE: &str = "usage: inventory <list [--category C] [--place P] | show <id> | low | add <id> --name N --category C --place P [--qty Q] [--unit U] [--acquired YYYY-MM-DD] [--cost AMOUNT CUR] [--source ACCOUNT] [--reorder-at R] [--tag T]... | move <id> <place> | use <id> <qty> | restock <id> <qty> | remove <id>> [--json]";

#[derive(Clone, Debug, PartialEq)]
pub struct Item {
    pub id: String,
    pub name: String,
    pub category: String,
    pub owner: String,
    pub place: String,
    /// Hundredths of `unit`.
    pub qty: u64,
    pub unit: String,
    pub acquired: Option<String>,
    /// Hundredths of `currency`.
    pub cost: Option<(u64, String)>,
    pub source: Option<String>,
    pub reorder_at: Option<u64>,
    pub tags: Vec<String>,
}

// ---- the rules, as ../_lean/Inventory.lean states them ----------------------

pub fn take(q: u64, n: u64) -> Option<u64> {
    if n <= q {
        Some(q - n)
    } else {
        None
    }
}

pub fn restock(q: u64, n: u64) -> u64 {
    q.saturating_add(n)
}

pub fn low(q: u64, reorder_at: u64) -> bool {
    q <= reorder_at
}

// ---- values -----------------------------------------------------------------

/// A non-negative decimal with at most two places, as hundredths.
pub fn hundredths(s: &str) -> Result<u64, String> {
    let bad = || format!("{s} is not a non-negative number with at most two decimals");
    let (whole, frac) = s.split_once('.').unwrap_or((s, ""));
    if whole.is_empty() || !whole.bytes().all(|b| b.is_ascii_digit()) || frac.len() > 2 || !frac.bytes().all(|b| b.is_ascii_digit()) {
        return Err(bad());
    }
    let w: u64 = whole.parse().map_err(|_| bad())?;
    let f: u64 = format!("{frac:0<2}").parse().map_err(|_| bad())?;
    w.checked_mul(100).and_then(|x| x.checked_add(f)).ok_or_else(bad)
}

pub fn show_hundredths(n: u64) -> String {
    if n % 100 == 0 {
        format!("{}", n / 100)
    } else {
        format!("{}.{:02}", n / 100, n % 100)
    }
}

fn one_of(what: &str, v: &str, allowed: &[&str]) -> Result<String, String> {
    if allowed.contains(&v) {
        Ok(v.to_string())
    } else {
        Err(format!("{what} {v} is not one of {}", allowed.join(", ")))
    }
}

fn plain(what: &str, v: &str) -> Result<String, String> {
    if v.is_empty() || v == "-" || v.contains(['\t', '\n', '\r']) {
        Err(format!("{what} must be non-empty text without tabs or newlines"))
    } else {
        Ok(v.to_string())
    }
}

fn ident(v: &str) -> Result<String, String> {
    let ok = !v.is_empty()
        && v.as_bytes()[0].is_ascii_lowercase()
        && v.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-');
    if ok {
        Ok(v.to_string())
    } else {
        Err(format!("id {v} must be lowercase letters, digits and dashes, starting with a letter"))
    }
}

fn date(v: &str) -> Result<String, String> {
    let b = v.as_bytes();
    let ok = b.len() == 10 && b[4] == b'-' && b[7] == b'-' && b.iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit());
    if ok {
        Ok(v.to_string())
    } else {
        Err(format!("{v} is not YYYY-MM-DD"))
    }
}

/// Every field checked against the schema, as `add` and the parser both do.
pub fn validate(i: &Item) -> Result<(), String> {
    ident(&i.id)?;
    plain("name", &i.name)?;
    one_of("category", &i.category, CATEGORIES)?;
    one_of("owner", &i.owner, OWNERS)?;
    one_of("place", &i.place, PLACES)?;
    plain("unit", &i.unit)?;
    if let Some(d) = &i.acquired {
        date(d)?;
    }
    if let Some((_, c)) = &i.cost {
        one_of("currency", c, CURRENCIES)?;
    }
    if let Some(s) = &i.source {
        one_of("source account", s, SOURCES)?;
    }
    for t in &i.tags {
        ident(t).map_err(|_| format!("tag {t} must be lowercase letters, digits and dashes"))?;
    }
    Ok(())
}

// ---- the document -------------------------------------------------------------

fn dash(v: &Option<String>) -> &str {
    v.as_deref().unwrap_or("-")
}

pub fn render(items: &[Item]) -> String {
    let mut sorted: Vec<&Item> = items.iter().collect();
    sorted.sort_by(|a, b| a.id.cmp(&b.id));
    let mut o = String::from(HEADER);
    o.push('\n');
    for i in sorted {
        let row = [
            i.id.clone(),
            i.name.clone(),
            i.category.clone(),
            i.owner.clone(),
            i.place.clone(),
            i.qty.to_string(),
            i.unit.clone(),
            dash(&i.acquired).to_string(),
            i.cost.as_ref().map(|(a, _)| a.to_string()).unwrap_or_else(|| "-".into()),
            i.cost.as_ref().map(|(_, c)| c.clone()).unwrap_or_else(|| "-".into()),
            dash(&i.source).to_string(),
            i.reorder_at.map(|r| r.to_string()).unwrap_or_else(|| "-".into()),
            if i.tags.is_empty() { "-".into() } else { i.tags.join(",") },
        ];
        o.push_str(&row.join("\t"));
        o.push('\n');
    }
    o
}

pub fn parse(doc: &str) -> Result<Vec<Item>, String> {
    let mut lines = doc.lines();
    match lines.next() {
        None => return Ok(Vec::new()),
        Some(h) if h == HEADER => {}
        Some(h) => return Err(format!("not an inventory document (header {h:?})")),
    }
    let opt = |v: &str| (v != "-").then(|| v.to_string());
    let num = |v: &str, line: usize| v.parse::<u64>().map_err(|_| format!("line {line}: {v} is not a whole number of hundredths"));
    let mut items = Vec::new();
    for (n, line) in lines.enumerate().map(|(n, l)| (n + 2, l)) {
        if line.is_empty() {
            continue;
        }
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() != 13 {
            return Err(format!("line {n}: {} fields, not 13", f.len()));
        }
        let item = Item {
            id: f[0].into(),
            name: f[1].into(),
            category: f[2].into(),
            owner: f[3].into(),
            place: f[4].into(),
            qty: num(f[5], n)?,
            unit: f[6].into(),
            acquired: opt(f[7]),
            cost: match (f[8], f[9]) {
                ("-", "-") => None,
                (a, c) => Some((num(a, n)?, c.to_string())),
            },
            source: opt(f[10]),
            reorder_at: match f[11] {
                "-" => None,
                r => Some(num(r, n)?),
            },
            tags: if f[12] == "-" { Vec::new() } else { f[12].split(',').map(String::from).collect() },
        };
        validate(&item).map_err(|e| format!("line {n}: {e}"))?;
        if items.iter().any(|i: &Item| i.id == item.id) {
            return Err(format!("line {n}: {} appears twice", item.id));
        }
        items.push(item);
    }
    Ok(items)
}

// ---- the store ----------------------------------------------------------------

enum Store {
    File(String),
    Vault,
}

fn store() -> Store {
    match std::env::var("INVENTORY_STORE") {
        Ok(p) if !p.is_empty() => Store::File(p),
        _ => Store::Vault,
    }
}

fn authorize(write: bool) -> Result<(), String> {
    let action = if write { "proton:inventory-write" } else { "proton:inventory-read" };
    let status = Command::new("governance-authorize")
        .args([action, ACCOUNT])
        .status()
        .map_err(|e| format!("governance-authorize: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("not authorized: {action}"))
    }
}

fn load(s: &Store) -> Result<Vec<Item>, String> {
    match s {
        Store::File(p) => match std::fs::read_to_string(p) {
            Ok(doc) => parse(&doc),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
            Err(e) => Err(format!("{p}: {e}")),
        },
        Store::Vault => {
            let out = Command::new("statestore")
                .args(["get", "--vault", VAULT, "--name", NAME])
                .output()
                .map_err(|e| format!("statestore: {e}"))?;
            if out.status.success() {
                parse(&String::from_utf8_lossy(&out.stdout))
            } else {
                let err = String::from_utf8_lossy(&out.stderr);
                if err.contains("no state under") {
                    Ok(Vec::new())
                } else {
                    Err(format!("statestore: {}", err.trim()))
                }
            }
        }
    }
}

fn save(s: &Store, items: &[Item]) -> Result<(), String> {
    let doc = render(items);
    match s {
        Store::File(p) => std::fs::write(p, doc).map_err(|e| format!("{p}: {e}")),
        Store::Vault => {
            let mut child = Command::new("statestore")
                .args(["put", "--vault", VAULT, "--name", NAME])
                .stdin(Stdio::piped())
                .spawn()
                .map_err(|e| format!("statestore: {e}"))?;
            child.stdin.take().ok_or("statestore: no stdin")?.write_all(doc.as_bytes()).map_err(|e| e.to_string())?;
            let status = child.wait().map_err(|e| e.to_string())?;
            if status.success() {
                Ok(())
            } else {
                Err("statestore put failed".into())
            }
        }
    }
}

// ---- output -------------------------------------------------------------------

fn esc(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn item_json(i: &Item) -> String {
    format!(
        "{{\"id\":{},\"name\":{},\"category\":{},\"owner\":{},\"place\":{},\"qty\":{},\"unit\":{},\"acquired\":{},\"cost\":{},\"source\":{},\"reorderAt\":{},\"low\":{},\"tags\":[{}]}}",
        esc(&i.id),
        esc(&i.name),
        esc(&i.category),
        esc(&i.owner),
        esc(&i.place),
        show_hundredths(i.qty),
        esc(&i.unit),
        i.acquired.as_deref().map(esc).unwrap_or_else(|| "null".into()),
        i.cost.as_ref().map(|(a, c)| format!("{{\"amount\":{},\"currency\":{}}}", show_hundredths(*a), esc(c))).unwrap_or_else(|| "null".into()),
        i.source.as_deref().map(esc).unwrap_or_else(|| "null".into()),
        i.reorder_at.map(show_hundredths).unwrap_or_else(|| "null".into()),
        i.reorder_at.is_some_and(|r| low(i.qty, r)),
        i.tags.iter().map(|t| esc(t)).collect::<Vec<_>>().join(",")
    )
}

fn item_line(i: &Item) -> String {
    format!(
        "{:<20} {:<11} {:<10} {:>8} {:<5} {}{}",
        i.id,
        i.category,
        i.place,
        show_hundredths(i.qty),
        i.unit,
        i.name,
        if i.reorder_at.is_some_and(|r| low(i.qty, r)) { "  (low)" } else { "" }
    )
}

fn many(items: &[&Item], json: bool) -> String {
    if json {
        format!("[{}]", items.iter().map(|i| item_json(i)).collect::<Vec<_>>().join(","))
    } else {
        items.iter().map(|i| item_line(i)).collect::<Vec<_>>().join("\n")
    }
}

// ---- commands -------------------------------------------------------------------

struct Args {
    words: Vec<String>,
    json: bool,
    flags: Vec<(String, Vec<String>)>,
}

fn args(raw: &[String]) -> Result<Args, String> {
    let mut a = Args { words: Vec::new(), json: false, flags: Vec::new() };
    let mut it = raw.iter().peekable();
    while let Some(w) = it.next() {
        match w.as_str() {
            "--json" => a.json = true,
            "--cost" => {
                let amount = it.next().ok_or("--cost takes AMOUNT CURRENCY")?.clone();
                let cur = it.next().ok_or("--cost takes AMOUNT CURRENCY")?.clone();
                a.flags.push(("cost".into(), vec![amount, cur]));
            }
            f if f.starts_with("--") => {
                let v = it.next().ok_or_else(|| format!("{f} takes a value"))?.clone();
                a.flags.push((f.trim_start_matches("--").into(), vec![v]));
            }
            w => a.words.push(w.to_string()),
        }
    }
    Ok(a)
}

impl Args {
    fn flag(&self, k: &str) -> Option<&str> {
        self.flags.iter().find(|(n, _)| n == k).map(|(_, v)| v[0].as_str())
    }
    fn all(&self, k: &str) -> Vec<String> {
        self.flags.iter().filter(|(n, _)| n == k).map(|(_, v)| v[0].clone()).collect()
    }
    fn only(&self, allowed: &[&str]) -> Result<(), String> {
        match self.flags.iter().find(|(n, _)| !allowed.contains(&n.as_str())) {
            Some((n, _)) => Err(format!("--{n} is not an option here")),
            None => Ok(()),
        }
    }
}

fn find<'a>(items: &'a mut [Item], id: &str) -> Result<&'a mut Item, String> {
    items.iter_mut().find(|i| i.id == id).ok_or_else(|| format!("no item {id}"))
}

fn run(raw: &[String]) -> Result<String, String> {
    let a = args(raw)?;
    let words: Vec<&str> = a.words.iter().map(String::as_str).collect();
    let s = store();
    let write = matches!(words.first(), Some(&("add" | "move" | "use" | "restock" | "remove")));
    if words.is_empty() || !matches!(words[0], "list" | "show" | "low" | "add" | "move" | "use" | "restock" | "remove") {
        return Err(USAGE.into());
    }
    if let Store::Vault = s {
        authorize(write)?;
    }
    let mut items = load(&s)?;
    let out = match words.as_slice() {
        ["list"] => {
            a.only(&["category", "place"])?;
            let picked: Vec<&Item> = items
                .iter()
                .filter(|i| a.flag("category").map_or(true, |c| i.category == c))
                .filter(|i| a.flag("place").map_or(true, |p| i.place == p))
                .collect();
            many(&picked, a.json)
        }
        ["low"] => {
            let picked: Vec<&Item> = items.iter().filter(|i| i.reorder_at.is_some_and(|r| low(i.qty, r))).collect();
            many(&picked, a.json)
        }
        ["show", id] => {
            let i = items.iter().find(|i| i.id == *id).ok_or_else(|| format!("no item {id}"))?;
            if a.json {
                item_json(i)
            } else {
                item_line(i)
            }
        }
        ["add", id] => {
            a.only(&["name", "category", "place", "qty", "unit", "acquired", "cost", "source", "reorder-at", "tag", "owner"])?;
            if items.iter().any(|i| i.id == *id) {
                return Err(format!("{id} exists already"));
            }
            let need = |k: &str| a.flag(k).ok_or_else(|| format!("add needs --{k}"));
            let item = Item {
                id: id.to_string(),
                name: need("name")?.into(),
                category: need("category")?.into(),
                owner: a.flag("owner").unwrap_or(OWNERS.iter().copied().find(|o| *o == "mirazo").unwrap_or(OWNERS[0])).into(),
                place: need("place")?.into(),
                qty: hundredths(a.flag("qty").unwrap_or("1"))?,
                unit: a.flag("unit").unwrap_or("each").into(),
                acquired: a.flag("acquired").map(String::from),
                cost: match a.flags.iter().find(|(n, _)| n == "cost") {
                    Some((_, v)) => Some((hundredths(&v[0])?, v[1].clone())),
                    None => None,
                },
                source: a.flag("source").map(String::from),
                reorder_at: a.flag("reorder-at").map(hundredths).transpose()?,
                tags: a.all("tag"),
            };
            validate(&item)?;
            items.push(item);
            save(&s, &items)?;
            format!("added {id}")
        }
        ["move", id, place] => {
            let p = one_of("place", place, PLACES)?;
            find(&mut items, id)?.place = p;
            save(&s, &items)?;
            format!("{id} is now in {place}")
        }
        ["use", id, qty] => {
            let n = hundredths(qty)?;
            let i = find(&mut items, id)?;
            let left = take(i.qty, n).ok_or_else(|| format!("{id} has {} {}, not {qty}", show_hundredths(i.qty), i.unit))?;
            i.qty = left;
            let msg = format!("{id}: {} {} left{}", show_hundredths(left), i.unit, if i.reorder_at.is_some_and(|r| low(left, r)) { " (low)" } else { "" });
            save(&s, &items)?;
            msg
        }
        ["restock", id, qty] => {
            let n = hundredths(qty)?;
            let i = find(&mut items, id)?;
            i.qty = restock(i.qty, n);
            let msg = format!("{id}: {} {}", show_hundredths(i.qty), i.unit);
            save(&s, &items)?;
            msg
        }
        ["remove", id] => {
            let before = items.len();
            items.retain(|i| i.id != *id);
            if items.len() == before {
                return Err(format!("no item {id}"));
            }
            save(&s, &items)?;
            format!("removed {id}")
        }
        _ => return Err(USAGE.into()),
    };
    Ok(out)
}

fn main() {
    let raw: Vec<String> = std::env::args().skip(1).collect();
    match run(&raw) {
        Ok(out) => {
            if !out.is_empty() {
                println!("{out}");
            }
        }
        Err(e) => {
            eprintln!("inventory: {e}");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str) -> Item {
        Item {
            id: id.into(),
            name: "A thing".into(),
            category: CATEGORIES[0].into(),
            owner: OWNERS[0].into(),
            place: PLACES[0].into(),
            qty: 250,
            unit: "each".into(),
            acquired: Some("2026-11-04".into()),
            cost: Some((8990, CURRENCIES[0].into())),
            source: None,
            reorder_at: Some(100),
            tags: vec!["daily".into()],
        }
    }

    #[test]
    fn hundredths_parse_and_print() {
        assert_eq!(hundredths("300"), Ok(30_000));
        assert_eq!(hundredths("89.9"), Ok(8_990));
        assert_eq!(hundredths("0.05"), Ok(5));
        assert!(hundredths("-1").is_err());
        assert!(hundredths("1.234").is_err());
        assert!(hundredths("").is_err());
        assert_eq!(show_hundredths(35_000), "350");
        assert_eq!(show_hundredths(250), "2.50");
    }

    #[test]
    fn rules_match_the_proofs() {
        assert_eq!(take(5, 7), None);
        assert_eq!(take(7, 5), Some(2));
        assert!(restock(3, 4) >= 3);
        assert!(low(100, 100) && !low(101, 100));
    }

    #[test]
    fn documents_round_trip() {
        let items = vec![item("b"), item("a")];
        let doc = render(&items);
        let back = parse(&doc).unwrap();
        assert_eq!(back.len(), 2);
        assert_eq!(back[0].id, "a");
        assert_eq!(render(&back), doc);
    }

    #[test]
    fn the_schema_is_enforced() {
        let mut bad = item("x");
        bad.category = "nonsense".into();
        assert!(validate(&bad).is_err());
        let mut tab = item("x");
        tab.name = "a\tb".into();
        assert!(validate(&tab).is_err());
        assert!(parse("#something else\n").is_err());
        let doc = render(&[item("a")]);
        assert!(parse(&format!("{doc}{}", doc.lines().nth(1).unwrap())).is_err(), "a duplicate id");
    }
}
