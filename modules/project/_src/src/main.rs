//! `project`: the epics, decisions and gaps of ../_data, as typed and proven
//! by ../default.nix (PROJECT_FACTS). Everything is read-only except
//! `decide`, which rewrites decisions.json in jq's canonical form
//! (`jq -S --indent 2`), the form checks.project-data holds the file to.

use std::path::PathBuf;

pub struct Epic {
    pub id: &'static str,
    pub title: &'static str,
    pub serves: &'static str,
    pub team: Option<&'static str>,
    pub status: &'static str,
    pub blocked_on: &'static [&'static str],
    pub owner: &'static [&'static str],
    pub eta_hours: u32,
    pub modules: &'static [&'static str],
}

pub struct Decision {
    pub id: &'static str,
    pub asked: &'static str,
    pub question: &'static str,
    pub options: &'static [&'static str],
    pub answer: Option<&'static str>,
    pub decided: Option<&'static str>,
}

pub struct Gap {
    pub id: &'static str,
    pub step: &'static str,
    pub why: &'static str,
    pub closes_with: &'static str,
}

include!(env!("PROJECT_FACTS"));

const USAGE: &str = "usage: project <status | next | epic <id> | decisions [--open] | gaps | decide <id> <option> [--date YYYY-MM-DD] | render decisions> [--json]";
const DECISIONS_FILE: &str = "modules/project/_data/decisions.json";

fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 2);
    o.push('"');
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn list(xs: &[&str]) -> String {
    format!("[{}]", xs.iter().map(|x| esc(x)).collect::<Vec<_>>().join(","))
}

fn opt(v: Option<&str>) -> String {
    v.map(esc).unwrap_or_else(|| "null".into())
}

fn epic(id: &str) -> Option<&'static Epic> {
    EPICS.iter().find(|e| e.id == id)
}

fn decision(id: &str) -> Option<&'static Decision> {
    DECISIONS.iter().find(|d| d.id == id)
}

/// A blocker is settled when its epic is done or its decision answered.
fn settled(id: &str) -> bool {
    match (epic(id), decision(id)) {
        (Some(e), _) => e.status == "done",
        (None, Some(d)) => d.answer.is_some(),
        _ => false,
    }
}

fn open_blockers(e: &Epic) -> Vec<&'static str> {
    e.blocked_on.iter().copied().filter(|b| !settled(b)).collect()
}

fn next() -> Vec<&'static Epic> {
    EPICS
        .iter()
        .filter(|e| matches!(e.status, "approved" | "in-progress") && open_blockers(e).is_empty())
        .collect()
}

fn epic_json(e: &Epic) -> String {
    format!(
        "{{\"id\":{},\"title\":{},\"serves\":{},\"team\":{},\"status\":{},\"blockedOn\":{},\"openBlockers\":{},\"owner\":{},\"etaHours\":{},\"modules\":{}}}",
        esc(e.id),
        esc(e.title),
        esc(e.serves),
        opt(e.team),
        esc(e.status),
        list(e.blocked_on),
        list(&open_blockers(e)),
        list(e.owner),
        e.eta_hours,
        list(e.modules)
    )
}

fn decision_json(d: &Decision) -> String {
    format!(
        "{{\"id\":{},\"asked\":{},\"question\":{},\"options\":{},\"answer\":{},\"decided\":{}}}",
        esc(d.id),
        esc(d.asked),
        esc(d.question),
        list(d.options),
        opt(d.answer),
        opt(d.decided)
    )
}

fn gap_json(g: &Gap) -> String {
    format!(
        "{{\"id\":{},\"step\":{},\"why\":{},\"closesWith\":{}}}",
        esc(g.id),
        esc(g.step),
        esc(g.why),
        esc(g.closes_with)
    )
}

fn epic_line(e: &Epic) -> String {
    let open = open_blockers(e);
    format!(
        "{:<20} {:<11} {:<9} {:<9} {:>3}h  {}{}",
        e.id,
        e.status,
        e.serves,
        e.team.unwrap_or("-"),
        e.eta_hours,
        e.title,
        if open.is_empty() { String::new() } else { format!("  [waits on {}]", open.join(", ")) }
    )
}

/// decisions.json exactly as `jq -S --indent 2` prints it, with one answer
/// changed when `set` is given: ids and fields in sorted order.
fn render_decisions(set: Option<(&str, &str, &str)>) -> String {
    let mut ds: Vec<&Decision> = DECISIONS.iter().collect();
    ds.sort_by_key(|d| d.id);
    let entries: Vec<String> = ds
        .iter()
        .map(|d| {
            let (answer, decided) = match set {
                Some((id, a, date)) if id == d.id => (Some(a), Some(date)),
                _ => (d.answer, d.decided),
            };
            let options = d.options.iter().map(|o| format!("      {}", esc(o))).collect::<Vec<_>>().join(",\n");
            format!(
                "  {}: {{\n    \"answer\": {},\n    \"asked\": {},\n    \"decided\": {},\n    \"options\": [\n{}\n    ],\n    \"question\": {}\n  }}",
                esc(d.id),
                opt(answer),
                esc(d.asked),
                opt(decided),
                options,
                esc(d.question)
            )
        })
        .collect();
    format!("{{\n{}\n}}\n", entries.join(",\n"))
}

/// Days since 1970-01-01 to a civil date (Hinnant's algorithm).
fn civil(days: i64) -> String {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

fn today() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    civil(secs.div_euclid(86_400))
}

fn valid_date(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 10
        && b[4] == b'-'
        && b[7] == b'-'
        && b.iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit())
}

/// The repository root: the nearest directory up holding the decisions file.
fn root() -> Result<PathBuf, String> {
    let mut dir = std::env::current_dir().map_err(|e| e.to_string())?;
    loop {
        if dir.join(DECISIONS_FILE).is_file() {
            return Ok(dir);
        }
        if !dir.pop() {
            return Err(format!("no {DECISIONS_FILE} above the current directory"));
        }
    }
}

fn decide(id: &str, answer: &str, date: &str) -> Result<String, String> {
    let d = decision(id).ok_or_else(|| format!("no decision {id}"))?;
    if !d.options.contains(&answer) {
        return Err(format!("{answer} is not one of {}", d.options.join(", ")));
    }
    if !valid_date(date) {
        return Err(format!("{date} is not YYYY-MM-DD"));
    }
    Ok(render_decisions(Some((id, answer, date))))
}

fn run(args: &[String]) -> Result<String, String> {
    let json = args.iter().any(|a| a == "--json");
    let open_only = args.iter().any(|a| a == "--open");
    let mut date: Option<String> = None;
    let mut words: Vec<&str> = Vec::new();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--json" | "--open" => {}
            "--date" => date = Some(it.next().ok_or(USAGE)?.clone()),
            w => words.push(w),
        }
    }
    match words.as_slice() {
        ["status"] => Ok(if json {
            format!(
                "{{\"epics\":[{}],\"openDecisions\":{},\"gaps\":{},\"next\":{}}}",
                EPICS.iter().map(epic_json).collect::<Vec<_>>().join(","),
                list(&DECISIONS.iter().filter(|d| d.answer.is_none()).map(|d| d.id).collect::<Vec<_>>()),
                list(&GAPS.iter().map(|g| g.id).collect::<Vec<_>>()),
                list(&next().iter().map(|e| e.id).collect::<Vec<_>>())
            )
        } else {
            let mut o = String::from("epics\n");
            for s in ["in-progress", "approved", "blocked", "proposed", "paused", "done"] {
                for e in EPICS.iter().filter(|e| e.status == s) {
                    o.push_str(&format!("  {}\n", epic_line(e)));
                }
            }
            let open: Vec<_> = DECISIONS.iter().filter(|d| d.answer.is_none()).collect();
            o.push_str(&format!("open decisions ({})\n", open.len()));
            for d in open {
                o.push_str(&format!("  {:<20} {} [{}]\n", d.id, d.question, d.options.join(" | ")));
            }
            o.push_str(&format!("gaps ({})\n", GAPS.len()));
            for g in GAPS {
                o.push_str(&format!("  {:<20} {} (closes with {})\n", g.id, g.step, g.closes_with));
            }
            o.push_str(&format!("next: {}", next().iter().map(|e| e.id).collect::<Vec<_>>().join(", ")));
            o
        }),
        ["next"] => Ok(if json {
            format!("[{}]", next().into_iter().map(epic_json).collect::<Vec<_>>().join(","))
        } else {
            next().into_iter().map(epic_line).collect::<Vec<_>>().join("\n")
        }),
        ["epic", id] => {
            let e = epic(id).ok_or_else(|| format!("no epic {id}"))?;
            Ok(if json {
                epic_json(e)
            } else {
                format!(
                    "{}\n  {}\n  status   {}\n  serves   {}\n  team     {}\n  waits on {}\n  owner    {}\n  eta      {}h\n  modules  {}",
                    e.id,
                    e.title,
                    e.status,
                    e.serves,
                    e.team.unwrap_or("none yet"),
                    if e.blocked_on.is_empty() { "nothing".into() } else { e.blocked_on.join(", ") },
                    if e.owner.is_empty() {
                        "nothing".into()
                    } else {
                        e.owner
                            .iter()
                            .map(|s| {
                                let why = HUMAN_STEPS.iter().find(|(n, _)| n == s).map(|(_, w)| *w).unwrap_or("");
                                format!("{s} ({why})")
                            })
                            .collect::<Vec<_>>()
                            .join("; ")
                    },
                    e.eta_hours,
                    e.modules.join(", ")
                )
            })
        }
        ["decisions"] => {
            let ds: Vec<_> = DECISIONS.iter().filter(|d| !open_only || d.answer.is_none()).collect();
            Ok(if json {
                format!("[{}]", ds.into_iter().map(decision_json).collect::<Vec<_>>().join(","))
            } else {
                ds.into_iter()
                    .map(|d| {
                        format!(
                            "{:<20} {:<16} {} [{}]",
                            d.id,
                            d.answer.map(|a| format!("{a} ({})", d.decided.unwrap_or(""))).unwrap_or_else(|| "open".into()),
                            d.question,
                            d.options.join(" | ")
                        )
                    })
                    .collect::<Vec<_>>()
                    .join("\n")
            })
        }
        ["gaps"] => Ok(if json {
            format!("[{}]", GAPS.iter().map(gap_json).collect::<Vec<_>>().join(","))
        } else {
            GAPS.iter()
                .map(|g| format!("{}\n  {}\n  why: {}\n  closes with: {}", g.id, g.step, g.why, g.closes_with))
                .collect::<Vec<_>>()
                .join("\n")
        }),
        ["decide", id, answer] => {
            let date = date.unwrap_or_else(today);
            let out = decide(id, answer, &date)?;
            let path = root()?.join(DECISIONS_FILE);
            std::fs::write(&path, out).map_err(|e| format!("{}: {e}", path.display()))?;
            Ok(format!("{id}: {answer} ({date}), written to {DECISIONS_FILE}"))
        }
        ["render", "decisions"] => Ok(render_decisions(None).trim_end_matches('\n').to_string()),
        _ => Err(USAGE.into()),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(out) => println!("{out}"),
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civil_dates() {
        assert_eq!(civil(0), "1970-01-01");
        assert_eq!(civil(20_396), "2025-11-04");
        assert_eq!(civil(11_016), "2000-02-29");
    }

    #[test]
    fn decide_checks_its_answer() {
        let d = DECISIONS.iter().find(|d| d.answer.is_none()).expect("an open decision");
        assert!(decide(d.id, d.options[0], "2026-11-04").unwrap().contains(&format!("\"answer\": {}", esc(d.options[0]))));
        assert!(decide(d.id, "not-an-option", "2026-11-04").is_err());
        assert!(decide(d.id, d.options[0], "4 Nov").is_err());
        assert!(decide("no-such-decision", "x", "2026-11-04").is_err());
    }

    #[test]
    fn next_has_only_settled_work() {
        for e in next() {
            assert!(open_blockers(e).is_empty(), "{}", e.id);
            assert!(matches!(e.status, "approved" | "in-progress"), "{}", e.id);
        }
    }

    #[test]
    fn rendering_is_stable() {
        assert_eq!(render_decisions(None), render_decisions(None));
        assert!(render_decisions(None).ends_with("}\n"));
    }

    #[test]
    fn commands() {
        for c in [&["status"][..], &["next"], &["gaps"], &["decisions", "--open"], &["status", "--json"]] {
            assert!(run(&c.iter().map(|s| s.to_string()).collect::<Vec<_>>()).is_ok(), "{c:?}");
        }
        assert!(run(&["epic".into(), EPICS[0].id.into()]).is_ok());
        assert!(run(&["epic".into(), "nope".into()]).is_err());
        assert!(run(&["nope".into()]).is_err());
    }
}
