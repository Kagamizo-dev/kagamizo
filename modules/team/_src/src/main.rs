//! `team`: the governance agents and the areas they own and review, as
//! rendered by ../default.nix (TEAM_FACTS). Read-only.

pub struct Grant {
    pub account: &'static str,
    pub effects: &'static [&'static str],
    pub why: &'static str,
}

pub struct Area {
    pub entity: &'static str,
    pub mailbox: &'static str,
    pub owner: Option<&'static str>,
    pub reviewers: &'static [&'static str],
    pub classes: &'static [&'static str],
    pub purpose: &'static str,
}

pub struct Agent {
    pub name: &'static str,
    pub serves: &'static str,
    pub purpose: &'static str,
    pub model: &'static str,
    pub key: &'static str,
    pub key_limit_usd: u32,
    pub key_reset: &'static str,
    pub share_usd: u32,
    pub harness: &'static str,
    pub tools: &'static [&'static str],
    pub change_classes: &'static [&'static str],
    pub personas: &'static [&'static str],
    pub token: &'static str,
    pub token_vault: &'static str,
    pub owns: &'static [&'static str],
    pub reviews: &'static [&'static str],
    pub grants: &'static [Grant],
}

include!(env!("TEAM_FACTS"));

const USAGE: &str = "usage: team <list | show <agent> | tree | whoami> [--json]";

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

fn or_dash(xs: &[&str]) -> String {
    if xs.is_empty() {
        "-".into()
    } else {
        xs.join(", ")
    }
}

fn agent_json(a: &Agent) -> String {
    let grants = a
        .grants
        .iter()
        .map(|g| format!("{{\"account\":{},\"effects\":{},\"why\":{}}}", esc(g.account), list(g.effects), esc(g.why)))
        .collect::<Vec<_>>()
        .join(",");
    format!(
        concat!(
            "{{\"name\":{},\"serves\":{},\"purpose\":{},\"model\":{},",
            "\"key\":{{\"name\":{},\"limitUsd\":{},\"reset\":{},\"shareUsd\":{}}},",
            "\"harness\":{},\"tools\":{},\"changeClasses\":{},\"personas\":{},",
            "\"token\":{{\"name\":{},\"vault\":{}}},\"owns\":{},\"reviews\":{},\"grants\":[{}]}}"
        ),
        esc(a.name),
        esc(a.serves),
        esc(a.purpose),
        esc(a.model),
        esc(a.key),
        a.key_limit_usd,
        esc(a.key_reset),
        a.share_usd,
        esc(a.harness),
        list(a.tools),
        list(a.change_classes),
        list(a.personas),
        esc(a.token),
        esc(a.token_vault),
        list(a.owns),
        list(a.reviews),
        grants
    )
}

fn agent_text(a: &Agent) -> String {
    let mut o = format!(
        "{}\n  serves   {}\n  purpose  {}\n  model    {}\n  key      {} (${} of ${}/{})\n  harness  {}\n  tools    {}\n  proposes {}\n  owns     {}\n  reviews  {}\n  token    {}{}\n  personas {}\n",
        a.name,
        a.serves,
        a.purpose,
        a.model,
        a.key,
        a.share_usd,
        a.key_limit_usd,
        a.key_reset,
        a.harness,
        or_dash(a.tools),
        if a.change_classes.is_empty() { "nothing".into() } else { a.change_classes.join(", ") },
        or_dash(a.owns),
        or_dash(a.reviews),
        if a.token.is_empty() { "-" } else { a.token },
        if a.token_vault.is_empty() { String::new() } else { format!(" in {}", a.token_vault) },
        a.personas.join(", "),
    );
    for g in a.grants {
        o.push_str(&format!("  grant    {} {}: {}\n", g.account, g.effects.join("+"), g.why));
    }
    o.trim_end().to_string()
}

fn find(name: &str) -> Option<&'static Agent> {
    AGENTS.iter().find(|a| a.name == name)
}

/// The agent a principal names: `agent:<name>`.
fn principal_agent(p: &str) -> Result<&'static Agent, String> {
    let name = p
        .strip_prefix("agent:")
        .ok_or_else(|| format!("{p} is not an agent principal (agent:<name>)"))?;
    find(name).ok_or_else(|| format!("no agent {name} is declared"))
}

fn run(args: &[String]) -> Result<String, String> {
    let json = args.iter().any(|a| a == "--json");
    let words: Vec<&str> = args.iter().map(String::as_str).filter(|a| *a != "--json").collect();
    match words.as_slice() {
        ["list"] => Ok(if json {
            format!("[{}]", AGENTS.iter().map(agent_json).collect::<Vec<_>>().join(","))
        } else {
            AGENTS
                .iter()
                .map(|a| format!("{:<22} {:<9} {:<8} {:<16} ${:<3} {}", a.name, a.serves, a.harness, a.key, a.share_usd, or_dash(a.owns)))
                .collect::<Vec<_>>()
                .join("\n")
        }),
        ["show", name] => {
            let a = find(name).ok_or_else(|| format!("no agent {name} is declared"))?;
            Ok(if json { agent_json(a) } else { agent_text(a) })
        }
        ["whoami"] => {
            let p = std::env::var("KAGAMIZO_PRINCIPAL").map_err(|_| "KAGAMIZO_PRINCIPAL is not set".to_string())?;
            let a = principal_agent(&p)?;
            Ok(if json { agent_json(a) } else { agent_text(a) })
        }
        ["tree"] => Ok(if json {
            format!(
                "[{}]",
                AREAS
                    .iter()
                    .map(|a| format!(
                        "{{\"entity\":{},\"area\":{},\"owner\":{},\"reviewers\":{},\"classes\":{},\"purpose\":{}}}",
                        esc(a.entity),
                        esc(a.mailbox),
                        a.owner.map(esc).unwrap_or_else(|| "null".into()),
                        list(a.reviewers),
                        list(a.classes),
                        esc(a.purpose)
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        } else {
            let mut o = String::new();
            for (e, kind) in ENTITIES {
                o.push_str(&format!("{e} ({kind})\n"));
                for a in AREAS.iter().filter(|a| a.entity == *e) {
                    o.push_str(&format!(
                        "  {:<18} {:<22} reviewed by {}\n",
                        a.mailbox,
                        a.owner.unwrap_or("(the owner's own)"),
                        or_dash(a.reviewers)
                    ));
                }
            }
            o.trim_end().to_string()
        }),
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
    fn every_agent_has_work() {
        for a in AGENTS {
            assert!(!a.owns.is_empty() || !a.reviews.is_empty(), "{} owns and reviews nothing", a.name);
        }
    }

    #[test]
    fn owners_and_reviewers_are_declared_and_of_the_entity() {
        for area in AREAS {
            for n in area.owner.iter().chain(area.reviewers.iter()) {
                let a = find(n).unwrap_or_else(|| panic!("{}/{}: no agent {n}", area.entity, area.mailbox));
                assert_eq!(a.serves, area.entity, "{n} in {}/{}", area.entity, area.mailbox);
            }
        }
    }

    #[test]
    fn shares_fit_their_keys() {
        for a in AGENTS.iter().filter(|a| a.key_limit_usd > 0) {
            assert!(a.share_usd <= a.key_limit_usd, "{}", a.name);
        }
    }

    #[test]
    fn whoami_reads_agent_principals_only() {
        let a = &AGENTS[0];
        assert_eq!(principal_agent(&format!("agent:{}", a.name)).unwrap().name, a.name);
        assert!(principal_agent("person:mirazo").is_err());
        assert!(principal_agent("agent:no-such-agent").is_err());
    }

    #[test]
    fn json_escapes() {
        assert_eq!(esc("a\"b\\c\nd"), "\"a\\\"b\\\\c\\nd\"");
    }

    #[test]
    fn commands() {
        assert!(run(&["list".into()]).is_ok());
        assert!(run(&["tree".into(), "--json".into()]).unwrap().starts_with('['));
        assert!(run(&["show".into(), AGENTS[0].name.into()]).is_ok());
        assert!(run(&["show".into(), "nobody".into()]).is_err());
        assert!(run(&["bogus".into()]).is_err());
    }
}
