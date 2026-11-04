//! `scout`: every role and what could fill it, as typed and proven by
//! ../default.nix (SCOUT_FACTS). `score` reads candidates' repositories
//! through `gh api`; everything else is read-only over the baked facts.

use std::process::Command;

pub struct Role {
    pub name: &'static str,
    /// A need no account fills yet (scout.needs), not an account role.
    pub need: bool,
    /// The providers whose held accounts fill it today.
    pub held: &'static [&'static str],
}

pub struct Evidence {
    pub fact: &'static str,
    pub source: &'static str,
    pub checked: &'static str,
}

pub struct Candidate {
    pub role: &'static str,
    pub name: &'static str,
    pub url: &'static str,
    pub repo: Option<&'static str>,
    pub license: &'static str,
    pub self_host: bool,
    pub cost: &'static str,
    pub api: &'static str,
    pub status: &'static str,
    pub provider: Option<&'static str>,
    pub held: bool,
    pub alternative: bool,
    pub why: &'static str,
    pub evidence: &'static [Evidence],
}

include!(env!("SCOUT_FACTS"));

const USAGE: &str = "usage: scout <roles | list [role] [--status S] | show <name> | gaps | score <role|name>> [--json]";

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
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
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

fn of_role(role: &str) -> impl Iterator<Item = &'static Candidate> + '_ {
    CANDIDATES.iter().filter(move |c| c.role == role)
}

fn exits(r: &Role) -> Vec<&'static Candidate> {
    of_role(r.name).filter(|c| c.status != "rejected" && c.alternative).collect()
}

fn candidate_json(c: &Candidate) -> String {
    let ev = c
        .evidence
        .iter()
        .map(|e| format!("{{\"fact\":{},\"source\":{},\"checked\":{}}}", esc(e.fact), esc(e.source), esc(e.checked)))
        .collect::<Vec<_>>()
        .join(",");
    format!(
        "{{\"role\":{},\"name\":{},\"url\":{},\"repo\":{},\"license\":{},\"selfHost\":{},\"cost\":{},\"api\":{},\"status\":{},\"provider\":{},\"held\":{},\"alternative\":{},\"why\":{},\"evidence\":[{}]}}",
        esc(c.role),
        esc(c.name),
        esc(c.url),
        opt(c.repo),
        esc(c.license),
        c.self_host,
        esc(c.cost),
        esc(c.api),
        esc(c.status),
        opt(c.provider),
        c.held,
        c.alternative,
        esc(c.why),
        ev
    )
}

fn candidate_line(c: &Candidate) -> String {
    format!(
        "{:<14} {:<32} {:<10} {:<10} {:<12} {}{}",
        c.role,
        c.name,
        c.status,
        c.cost,
        c.license,
        if c.self_host { "self-host " } else { "" },
        c.why
    )
}

/// What a role still lacks: a need nothing fills or is adopted for, or a
/// held role whose exits are none of them mapped yet.
fn gaps() -> Vec<(&'static str, String)> {
    ROLES
        .iter()
        .filter_map(|r| {
            let adopted = of_role(r.name).any(|c| c.status == "adopted");
            if r.held.is_empty() && !adopted {
                let n = of_role(r.name).filter(|c| c.status != "rejected").count();
                Some((r.name, format!("nothing fills it; {n} candidate(s) to map")))
            } else if !r.held.is_empty() && !exits(r).iter().any(|c| c.status == "mapped" || c.status == "adopted") {
                Some((r.name, format!("held by {}; its exits are unmapped", r.held.join(", "))))
            } else {
                None
            }
        })
        .collect()
}

// ---- scoring ---------------------------------------------------------------

/// Days since 1970-01-01 of a YYYY-MM-DD date (Hinnant's algorithm).
fn days(date: &str) -> Option<i64> {
    let y: i64 = date.get(0..4)?.parse().ok()?;
    let m: i64 = date.get(5..7)?.parse().ok()?;
    let d: i64 = date.get(8..10)?.parse().ok()?;
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some(era * 146_097 + doe - 719_468)
}

fn now_days() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64 / 86_400)
        .unwrap_or(0)
}

pub struct Repo {
    pub archived: bool,
    pub pushed: String,
    pub license: String,
    pub stars: u64,
    pub release: Option<String>,
}

/// Stability in [0, 1] and why: alive (not archived), recently pushed,
/// recently released, under a licence GitHub recognises.
fn stability(r: &Repo, today: i64) -> (f64, Vec<String>) {
    let mut why = Vec::new();
    let alive = if r.archived { 0.0 } else { 1.0 };
    if r.archived {
        why.push("archived".to_string());
    }
    let age = |d: &str| days(d).map(|x| today - x);
    let push = match age(&r.pushed) {
        Some(a) if a <= 90 => 1.0,
        Some(a) if a <= 365 => 0.6,
        Some(_) => 0.2,
        None => 0.2,
    };
    why.push(format!("pushed {}", r.pushed.get(0..10).unwrap_or("?")));
    let release = match r.release.as_deref().and_then(age) {
        Some(a) if a <= 365 => 1.0,
        Some(_) => 0.7,
        None => 0.5,
    };
    why.push(match &r.release {
        Some(d) => format!("released {}", d.get(0..10).unwrap_or("?")),
        None => "no release".into(),
    });
    let licence = if r.license == "NOASSERTION" || r.license == "none" || r.license.is_empty() { 0.6 } else { 1.0 };
    why.push(format!("licence {}", r.license));
    why.push(format!("{} stars", r.stars));
    (alive * push * release * licence, why)
}

/// `gh api <path> --jq <filter>`: the one gh command scout runs.
fn gh(path: &str, filter: &str) -> Result<String, String> {
    let out = Command::new("gh").args(["api", path, "--jq", filter]).output().map_err(|e| format!("gh: {e}"))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

fn fetch(repo: &str) -> Result<Repo, String> {
    let row = gh(
        &format!("repos/{repo}"),
        "[.archived, .pushed_at, (.license.spdx_id // \"none\"), .stargazers_count] | @tsv",
    )?;
    let f: Vec<&str> = row.split('\t').collect();
    if f.len() != 4 {
        return Err(format!("{repo}: unexpected answer {row:?}"));
    }
    let release = gh(&format!("repos/{repo}/releases/latest"), ".published_at").ok();
    Ok(Repo {
        archived: f[0] == "true",
        pushed: f[1].to_string(),
        license: f[2].to_string(),
        stars: f[3].parse().unwrap_or(0),
        release: release.filter(|s| !s.is_empty()),
    })
}

fn score(target: &str, json: bool) -> Result<String, String> {
    let picked: Vec<&Candidate> = CANDIDATES.iter().filter(|c| c.role == target || c.name == target).collect();
    if picked.is_empty() {
        return Err(format!("no role or candidate {target}"));
    }
    let today = now_days();
    let mut rows = Vec::new();
    for c in picked {
        let row = match c.repo {
            None => (c, Err("no repository declared".to_string())),
            Some(repo) => (c, fetch(repo).map(|r| stability(&r, today))),
        };
        rows.push(row);
    }
    Ok(if json {
        format!(
            "[{}]",
            rows.iter()
                .map(|(c, r)| match r {
                    Ok((s, why)) => format!("{{\"name\":{},\"score\":{:.2},\"why\":{}}}", esc(c.name), s, list(&why.iter().map(String::as_str).collect::<Vec<_>>())),
                    Err(e) => format!("{{\"name\":{},\"score\":null,\"error\":{}}}", esc(c.name), esc(e)),
                })
                .collect::<Vec<_>>()
                .join(",")
        )
    } else {
        rows.iter()
            .map(|(c, r)| match r {
                Ok((s, why)) => format!("{:<32} {:.2}  {}", c.name, s, why.join(", ")),
                Err(e) => format!("{:<32}  -    {e}", c.name),
            })
            .collect::<Vec<_>>()
            .join("\n")
    })
}

fn run(args: &[String]) -> Result<String, String> {
    let json = args.iter().any(|a| a == "--json");
    let mut status: Option<String> = None;
    let mut words: Vec<&str> = Vec::new();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--json" => {}
            "--status" => status = Some(it.next().ok_or(USAGE)?.clone()),
            w => words.push(w),
        }
    }
    match words.as_slice() {
        ["roles"] => Ok(if json {
            format!(
                "[{}]",
                ROLES
                    .iter()
                    .map(|r| format!(
                        "{{\"role\":{},\"need\":{},\"held\":{},\"exits\":{}}}",
                        esc(r.name),
                        r.need,
                        list(r.held),
                        list(&exits(r).iter().map(|c| c.name).collect::<Vec<_>>())
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        } else {
            ROLES
                .iter()
                .map(|r| {
                    format!(
                        "{:<18} {:<34} exits: {}",
                        r.name,
                        if r.held.is_empty() { "(nothing held)".to_string() } else { format!("held: {}", r.held.join(", ")) },
                        exits(r).iter().map(|c| format!("{} ({})", c.name, c.status)).collect::<Vec<_>>().join(", ")
                    )
                })
                .collect::<Vec<_>>()
                .join("\n")
        }),
        ["list", rest @ ..] if rest.len() <= 1 => {
            let cs: Vec<&Candidate> = CANDIDATES
                .iter()
                .filter(|c| rest.first().map_or(true, |r| c.role == *r))
                .filter(|c| status.as_deref().map_or(true, |s| c.status == s))
                .collect();
            if let Some(r) = rest.first() {
                if !ROLES.iter().any(|x| x.name == *r) {
                    return Err(format!("no role {r}"));
                }
            }
            Ok(if json {
                format!("[{}]", cs.into_iter().map(candidate_json).collect::<Vec<_>>().join(","))
            } else {
                cs.into_iter().map(candidate_line).collect::<Vec<_>>().join("\n")
            })
        }
        ["show", name] => {
            let cs: Vec<&Candidate> = CANDIDATES.iter().filter(|c| c.name == *name).collect();
            if cs.is_empty() {
                return Err(format!("no candidate {name}"));
            }
            Ok(if json {
                format!("[{}]", cs.into_iter().map(candidate_json).collect::<Vec<_>>().join(","))
            } else {
                cs.into_iter()
                    .map(|c| {
                        let mut o = format!(
                            "{} ({})\n  {}\n  url      {}\n  repo     {}\n  status   {}\n  cost     {}\n  licence  {}{}\n  api      {}\n  provider {}\n",
                            c.name,
                            c.role,
                            c.why,
                            c.url,
                            c.repo.unwrap_or("-"),
                            c.status,
                            c.cost,
                            c.license,
                            if c.self_host { ", self-hostable" } else { "" },
                            c.api,
                            match c.provider {
                                Some(p) => format!("{p}{}", if c.held { " (held)" } else { "" }),
                                None => "-".into(),
                            }
                        );
                        for e in c.evidence {
                            o.push_str(&format!("  found    {} ({}, {})\n", e.fact, e.source, e.checked));
                        }
                        o.trim_end().to_string()
                    })
                    .collect::<Vec<_>>()
                    .join("\n")
            })
        }
        ["gaps"] => {
            let g = gaps();
            Ok(if json {
                format!(
                    "[{}]",
                    g.iter().map(|(r, w)| format!("{{\"role\":{},\"gap\":{}}}", esc(r), esc(w))).collect::<Vec<_>>().join(",")
                )
            } else {
                g.iter().map(|(r, w)| format!("{r:<18} {w}")).collect::<Vec<_>>().join("\n")
            })
        }
        ["score", target] => score(target, json),
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
    fn every_held_role_has_an_exit() {
        for r in ROLES.iter().filter(|r| !r.held.is_empty()) {
            assert!(!exits(r).is_empty(), "{}", r.name);
        }
    }

    #[test]
    fn every_candidate_is_in_a_declared_role() {
        for c in CANDIDATES {
            assert!(ROLES.iter().any(|r| r.name == c.role), "{} in {}", c.name, c.role);
        }
    }

    #[test]
    fn nothing_adopted_costs_something_new() {
        for c in CANDIDATES.iter().filter(|c| c.status == "adopted") {
            assert!(matches!(c.cost, "free" | "free-tier") || c.held, "{}", c.name);
        }
    }

    #[test]
    fn dates() {
        assert_eq!(days("1970-01-01"), Some(0));
        assert_eq!(days("2000-02-29"), Some(11_016));
        assert_eq!(days("2026-11-04"), Some(20_761));
        assert_eq!(days("x"), None);
    }

    #[test]
    fn stability_orders_alive_over_archived() {
        let today = days("2026-11-04").unwrap();
        let alive = Repo { archived: false, pushed: "2026-10-30T00:00:00Z".into(), license: "MIT".into(), stars: 10, release: Some("2026-09-01T00:00:00Z".into()) };
        let dead = Repo { archived: true, ..Repo { pushed: "2023-01-01T00:00:00Z".into(), license: "none".into(), release: None, archived: true, stars: 0 } };
        let (a, _) = stability(&alive, today);
        let (d, _) = stability(&dead, today);
        assert!((a - 1.0).abs() < 1e-9);
        assert_eq!(d, 0.0);
    }

    #[test]
    fn commands() {
        for c in [&["roles"][..], &["gaps"], &["list"], &["list", "inventory"], &["roles", "--json"]] {
            assert!(run(&c.iter().map(|s| s.to_string()).collect::<Vec<_>>()).is_ok(), "{c:?}");
        }
        assert!(run(&["list".into(), "no-such-role".into()]).is_err());
        assert!(run(&["show".into(), CANDIDATES[0].name.into()]).is_ok());
        assert!(run(&["show".into(), "nobody".into()]).is_err());
    }
}
