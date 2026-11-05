//! `market`: the priced order book of resources (../default.nix renders
//! MARKET_FACTS). Read-only; the host refreshes the rates.

use serde_json::Value;

const FACTS: &str = include_str!(env!("MARKET_FACTS"));
const USAGE: &str = "usage: market <compare <class> | chosen | gaps | classes> [--json]";

fn facts() -> Value {
    serde_json::from_str(FACTS).expect("MARKET_FACTS is rendered by Nix")
}

fn s<'a>(v: &'a Value, k: &str) -> &'a str {
    v.get(k).and_then(Value::as_str).unwrap_or("")
}

fn usd(r: &Value) -> f64 {
    r.get("usd").and_then(Value::as_f64).unwrap_or(f64::INFINITY)
}

/// A class's rates, cheapest first.
fn rates_sorted(f: &Value, c: &str) -> Vec<Value> {
    let mut rs: Vec<Value> = f["rates"].get(c).and_then(Value::as_array).cloned().unwrap_or_default();
    rs.sort_by(|a, b| usd(a).partial_cmp(&usd(b)).unwrap_or(std::cmp::Ordering::Equal));
    rs
}

fn class_names(f: &Value) -> Vec<String> {
    let mut ks: Vec<String> = f["classes"].as_object().map(|o| o.keys().cloned().collect()).unwrap_or_default();
    ks.sort();
    ks
}

fn premium_pct(f: &Value) -> f64 {
    f.get("premiumPct").and_then(Value::as_f64).unwrap_or(25.0)
}

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

fn rate_line(r: &Value) -> String {
    format!(
        "  {:<34} {:>10.4}  {}{}{}",
        s(r, "provider"),
        usd(r),
        if r.get("held").and_then(Value::as_bool).unwrap_or(false) { "held " } else { "     " },
        if s(r, "verified").is_empty() { "unverified " } else { "verified " },
        s(r, "note")
    )
}

/// The premium the chosen provider pays over the cheapest, as a percent.
fn premium(f: &Value, c: &str) -> Option<(String, f64, f64)> {
    let ch = f["chosen"].get(c)?;
    let prov = s(ch, "provider").to_string();
    let rs = rates_sorted(f, c);
    let lo = usd(rs.first()?);
    let mine = rs.iter().find(|r| s(r, "provider") == prov).map(usd)?;
    let pct = if lo > 0.0 { (mine - lo) / lo * 100.0 } else { 0.0 };
    Some((prov, mine, pct))
}

fn run(args: &[String]) -> Result<String, String> {
    let json = args.iter().any(|a| a == "--json");
    let words: Vec<&str> = args.iter().map(String::as_str).filter(|a| *a != "--json").collect();
    let f = facts();
    match words.as_slice() {
        ["classes"] => Ok(if json {
            f["classes"].to_string()
        } else {
            class_names(&f)
                .iter()
                .map(|c| format!("{:<10} {:<24} {}", c, s(&f["classes"][c], "unit"), s(&f["classes"][c], "description")))
                .collect::<Vec<_>>()
                .join("\n")
        }),
        ["compare", c] => {
            if f["classes"].get(c).is_none() {
                return Err(format!("no class {c}; try: {}", class_names(&f).join(", ")));
            }
            let rs = rates_sorted(&f, c);
            Ok(if json {
                Value::Array(rs).to_string()
            } else if rs.is_empty() {
                format!("{c}: no rates yet (a gap)")
            } else {
                let unit = s(&f["classes"][c], "unit");
                let chosen = s(f["chosen"].get(c).unwrap_or(&Value::Null), "provider");
                format!(
                    "{c} ({unit})\n{}",
                    rs.iter()
                        .map(|r| {
                            let mark = if s(r, "provider") == chosen { "*" } else { " " };
                            format!("{mark}{}", rate_line(r))
                        })
                        .collect::<Vec<_>>()
                        .join("\n")
                )
            })
        }
        ["chosen"] => {
            let rows: Vec<(String, String, f64, f64, String)> = class_names(&f)
                .into_iter()
                .filter_map(|c| {
                    premium(&f, &c).map(|(p, u, pct)| (c.clone(), p, u, pct, s(f["chosen"].get(&c).unwrap(), "reason").to_string()))
                })
                .collect();
            Ok(if json {
                format!(
                    "[{}]",
                    rows.iter()
                        .map(|(c, p, u, pct, r)| format!(
                            "{{\"class\":{},\"provider\":{},\"usd\":{},\"premiumPct\":{:.1},\"reason\":{}}}",
                            esc(c), esc(p), u, pct, esc(r)
                        ))
                        .collect::<Vec<_>>()
                        .join(",")
                )
            } else {
                rows.iter()
                    .map(|(c, p, u, pct, r)| {
                        format!(
                            "{:<10} {:<34} {:>10.4}  +{:>5.1}%{}",
                            c,
                            p,
                            u,
                            pct,
                            if r.is_empty() { String::new() } else { format!("  ({r})") }
                        )
                    })
                    .collect::<Vec<_>>()
                    .join("\n")
            })
        }
        ["gaps"] => {
            let mut out = Vec::new();
            for c in class_names(&f) {
                let n = rates_sorted(&f, &c).len();
                let picked = f["chosen"].get(&c).is_some();
                if n == 0 {
                    out.push((c, "no provider yet".to_string()));
                } else if n < 2 {
                    out.push((c, "single-sourced: no competition, find an alternative".to_string()));
                } else if !picked {
                    out.push((c, format!("{n} rates but none chosen", n = n)));
                }
            }
            Ok(if json {
                format!("[{}]", out.iter().map(|(c, g)| format!("{{\"class\":{},\"gap\":{}}}", esc(c), esc(g))).collect::<Vec<_>>().join(","))
            } else if out.is_empty() {
                "no gaps: every class has a choice and an alternative".into()
            } else {
                out.iter().map(|(c, g)| format!("{c:<10} {g}")).collect::<Vec<_>>().join("\n")
            })
        }
        _ => Err(USAGE.into()),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(o) => println!("{o}"),
        Err(e) => {
            eprintln!("market: {e}");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_chosen_is_a_real_rate() {
        let f = facts();
        for (c, ch) in f["chosen"].as_object().unwrap() {
            let prov = s(ch, "provider");
            assert!(rates_sorted(&f, c).iter().any(|r| s(r, "provider") == prov), "{c}: {prov} not a rate");
        }
    }

    #[test]
    fn chosen_within_cap_or_reasoned() {
        let f = facts();
        let cap = premium_pct(&f);
        for c in class_names(&f) {
            if let Some((_, _, pct)) = premium(&f, &c) {
                let reason = s(f["chosen"].get(&c).unwrap(), "reason");
                let single = rates_sorted(&f, &c).len() < 2;
                assert!(single || pct <= cap || !reason.is_empty(), "{c}: {pct:.1}% over, no reason");
            }
        }
    }

    #[test]
    fn compare_is_sorted_cheapest_first() {
        let f = facts();
        for c in class_names(&f) {
            let rs = rates_sorted(&f, &c);
            for w in rs.windows(2) {
                assert!(usd(&w[0]) <= usd(&w[1]), "{c} not sorted");
            }
        }
    }

    #[test]
    fn commands() {
        assert!(run(&["classes".into()]).is_ok());
        assert!(run(&["chosen".into(), "--json".into()]).unwrap().starts_with('['));
        assert!(run(&["gaps".into()]).is_ok());
        assert!(run(&["compare".into(), "tokens".into()]).is_ok());
        assert!(run(&["compare".into(), "nope".into()]).is_err());
        assert!(run(&["bogus".into()]).is_err());
    }
}
