//! `cost`: the recurring-cost report (../default.nix renders COST_FACTS).
//! `report` is static; `usage` shells out to the signed-in openrouter CLI.

use std::process::Command;

pub struct Card {
    pub name: &'static str,
    pub limit_cents: u64,
    pub draw_cents: u64,
    pub interval: &'static str,
    pub covers: &'static str,
    pub account: &'static str,
    pub why: &'static str,
}

include!(env!("COST_FACTS"));

const USAGE: &str = "usage: cost <report | usage> [--json]";

fn dollars(c: u64) -> String {
    format!("{}.{:02}", c / 100, c % 100)
}

fn total_limit() -> u64 {
    CARDS.iter().map(|c| c.limit_cents).sum()
}

fn total_draw() -> u64 {
    CARDS.iter().map(|c| c.draw_cents).sum()
}

fn report(json: bool) -> String {
    if json {
        let rows = CARDS
            .iter()
            .map(|c| {
                format!(
                    "{{\"card\":\"{}\",\"limitUsdMonthly\":{},\"drawUsdMonthly\":{},\"headroomUsdMonthly\":{},\"interval\":\"{}\",\"covers\":\"{}\",\"account\":\"{}\"}}",
                    c.name,
                    dollars(c.limit_cents),
                    dollars(c.draw_cents),
                    dollars(c.limit_cents.saturating_sub(c.draw_cents)),
                    c.interval,
                    c.covers,
                    c.account
                )
            })
            .collect::<Vec<_>>()
            .join(",");
        format!(
            "{{\"cards\":[{}],\"committedUsdMonthly\":{},\"ceilingUsdMonthly\":{}}}",
            rows,
            dollars(total_draw()),
            dollars(total_limit())
        )
    } else {
        let mut o = format!(
            "{:<14} {:>10} {:>10} {:>10}  {}\n",
            "card", "limit/mo", "draw/mo", "headroom", "covers"
        );
        o.push_str(&"-".repeat(72));
        o.push('\n');
        let mut cards: Vec<&Card> = CARDS.iter().collect();
        cards.sort_by(|a, b| b.draw_cents.cmp(&a.draw_cents));
        for c in cards {
            o.push_str(&format!(
                "{:<14} {:>10} {:>10} {:>10}  {} ({})\n",
                c.name,
                dollars(c.limit_cents),
                dollars(c.draw_cents),
                dollars(c.limit_cents.saturating_sub(c.draw_cents)),
                c.covers,
                c.interval
            ));
        }
        o.push_str(&"-".repeat(72));
        o.push('\n');
        o.push_str(&format!(
            "{:<14} {:>10} {:>10}\n",
            "total",
            dollars(total_limit()),
            dollars(total_draw())
        ));
        o.push_str(&format!(
            "\nThe universe costs at most ${}/month, committed ${}/month, all on Mercury cards.",
            dollars(total_limit()),
            dollars(total_draw())
        ));
        o
    }
}

fn usage(json: bool) -> Result<String, String> {
    let mut args = vec!["usage"];
    if json {
        args.push("--json");
    }
    let out = Command::new("openrouter").args(&args).output().map_err(|e| format!("openrouter: {e}"))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    } else {
        Err(format!("openrouter usage: {}", String::from_utf8_lossy(&out.stderr).trim()))
    }
}

fn run(args: &[String]) -> Result<String, String> {
    let json = args.iter().any(|a| a == "--json");
    let words: Vec<&str> = args.iter().map(String::as_str).filter(|a| *a != "--json").collect();
    match words.as_slice() {
        ["report"] => Ok(report(json)),
        ["usage"] => usage(json),
        _ => Err(USAGE.into()),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(o) => println!("{o}"),
        Err(e) => {
            eprintln!("cost: {e}");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_draw_fits_its_card() {
        for c in CARDS {
            assert!(c.draw_cents <= c.limit_cents, "{} over", c.name);
        }
    }

    #[test]
    fn the_openrouter_card_covers_the_key_caps() {
        let or = CARDS.iter().find(|c| c.name == "openrouter").expect("openrouter card");
        assert_eq!(or.draw_cents, KEY_CAPS_CENTS, "draw should be the key caps");
        assert!(KEY_CAPS_CENTS <= or.limit_cents, "key caps exceed the card");
    }

    #[test]
    fn committed_never_exceeds_ceiling() {
        assert!(total_draw() <= total_limit());
    }

    #[test]
    fn report_renders_both_ways() {
        assert!(report(true).starts_with('{'));
        assert!(report(false).contains("universe costs at most"));
    }

    #[test]
    fn commands() {
        assert!(run(&["report".into()]).is_ok());
        assert!(run(&["report".into(), "--json".into()]).is_ok());
        assert!(run(&["bogus".into()]).is_err());
    }
}
