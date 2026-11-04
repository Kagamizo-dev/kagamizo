//! `team`: the agent identities declared in governance.agents and
//! governance.teams, as rendered by ../default.nix (TEAM_FACTS). Read-only.

pub struct Team {
    pub name: &'static str,
    pub purpose: &'static str,
    pub serves: Option<&'static str>,
    pub review: bool,
    pub tier_cap: &'static str,
}

pub struct Grant {
    pub account: &'static str,
    pub effects: &'static [&'static str],
    pub why: &'static str,
}

pub struct Agent {
    pub name: &'static str,
    pub serves: &'static str,
    pub team: &'static str,
    pub purpose: &'static str,
    pub tier: &'static str,
    pub tier_rank: u8,
    pub paid: bool,
    pub model: Option<&'static str>,
    pub key: &'static str,
    pub key_limit_usd: u32,
    pub key_reset: &'static str,
    pub harness: &'static str,
    pub room: &'static str,
    pub mail: &'static str,
    pub token: &'static str,
    pub token_vault: &'static str,
    pub token_expires: &'static str,
    pub personas: &'static [&'static str],
    pub change_classes: &'static [&'static str],
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

fn opt(v: Option<&str>) -> String {
    v.map(esc).unwrap_or_else(|| "null".into())
}

fn agent_json(a: &Agent) -> String {
    let grants = a
        .grants
        .iter()
        .map(|g| {
            format!(
                "{{\"account\":{},\"effects\":{},\"why\":{}}}",
                esc(g.account),
                list(g.effects),
                esc(g.why)
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    format!(
        concat!(
            "{{\"name\":{},\"serves\":{},\"team\":{},\"purpose\":{},",
            "\"tier\":{},\"tierRank\":{},\"paid\":{},\"model\":{},",
            "\"key\":{{\"name\":{},\"limitUsd\":{},\"reset\":{}}},",
            "\"harness\":{},\"room\":{},\"mail\":{},",
            "\"token\":{{\"name\":{},\"vault\":{},\"expires\":{}}},",
            "\"personas\":{},\"changeClasses\":{},\"reviews\":{},\"grants\":[{}]}}"
        ),
        esc(a.name),
        esc(a.serves),
        esc(a.team),
        esc(a.purpose),
        esc(a.tier),
        a.tier_rank,
        a.paid,
        opt(a.model),
        esc(a.key),
        a.key_limit_usd,
        esc(a.key_reset),
        esc(a.harness),
        esc(a.room),
        esc(a.mail),
        esc(a.token),
        esc(a.token_vault),
        esc(a.token_expires),
        list(a.personas),
        list(a.change_classes),
        list(a.reviews),
        grants
    )
}

fn agent_text(a: &Agent) -> String {
    let mut o = format!(
        "{}\n  serves   {}\n  team     {}\n  purpose  {}\n  tier     {} (rank {}, {}{})\n  key      {} (${}/{})\n  harness  {}\n  room     {}\n  mail     {}\n  token    {} in {} (expires {})\n",
        a.name,
        a.serves,
        a.team,
        a.purpose,
        a.tier,
        a.tier_rank,
        if a.paid { "paid" } else { "free" },
        a.model.map(|m| format!(", {m}")).unwrap_or_default(),
        a.key,
        a.key_limit_usd,
        a.key_reset,
        a.harness,
        a.room,
        a.mail,
        a.token,
        a.token_vault,
        a.token_expires,
    );
    o.push_str(&format!("  personas {}\n", a.personas.join(", ")));
    o.push_str(&format!(
        "  proposes {}\n",
        if a.change_classes.is_empty() { "nothing".into() } else { a.change_classes.join(", ") }
    ));
    if !a.reviews.is_empty() {
        o.push_str(&format!("  reviews  {}\n", a.reviews.join(", ")));
    }
    if a.grants.is_empty() {
        o.push_str("  grants   none\n");
    }
    for g in a.grants {
        o.push_str(&format!("  grant    {} {}: {}\n", g.account, g.effects.join("+"), g.why));
    }
    o
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

/// Entities, then the teams their agents are in, then the agents.
fn tree() -> Vec<(&'static str, Vec<(&'static str, Vec<&'static Agent>)>)> {
    ENTITIES
        .iter()
        .map(|(e, _)| {
            let teams = TEAMS
                .iter()
                .filter_map(|t| {
                    let members: Vec<_> = AGENTS.iter().filter(|a| a.serves == *e && a.team == t.name).collect();
                    (!members.is_empty()).then_some((t.name, members))
                })
                .collect();
            (*e, teams)
        })
        .collect()
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
                .map(|a| format!("{:<24} {:<9} {:<11} {:<6} {}", a.name, a.serves, a.team, a.tier, a.room))
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
        ["tree"] => {
            let t = tree();
            Ok(if json {
                let es = t
                    .iter()
                    .map(|(e, teams)| {
                        let ts = teams
                            .iter()
                            .map(|(n, members)| {
                                format!(
                                    "{{\"team\":{},\"agents\":{}}}",
                                    esc(n),
                                    list(&members.iter().map(|a| a.name).collect::<Vec<_>>())
                                )
                            })
                            .collect::<Vec<_>>()
                            .join(",");
                        format!("{{\"entity\":{},\"teams\":[{}]}}", esc(e), ts)
                    })
                    .collect::<Vec<_>>()
                    .join(",");
                format!("[{es}]")
            } else {
                let mut o = String::new();
                for (e, teams) in &t {
                    o.push_str(&format!("{e}\n"));
                    for (n, members) in teams {
                        o.push_str(&format!("  {n}\n"));
                        for a in members {
                            o.push_str(&format!("    {} ({}, {})\n", a.name, a.tier, a.room));
                        }
                    }
                }
                o.trim_end().to_string()
            })
        }
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

    fn team(name: &str) -> Option<&'static Team> {
        TEAMS.iter().find(|t| t.name == name)
    }

    #[test]
    fn every_agent_is_in_a_declared_team_of_its_entity() {
        for a in AGENTS {
            let t = team(a.team).unwrap_or_else(|| panic!("{}: no team {}", a.name, a.team));
            if let Some(e) = t.serves {
                assert_eq!(e, a.serves, "{}", a.name);
            }
            assert!(ENTITIES.iter().any(|(e, _)| *e == a.serves), "{}", a.name);
        }
    }

    #[test]
    fn no_agent_reviews_its_own_team_and_reviewers_propose_nothing() {
        for a in AGENTS {
            assert!(!a.reviews.contains(&a.team), "{}", a.name);
            if team(a.team).unwrap().review {
                assert!(a.change_classes.is_empty(), "{}", a.name);
            }
        }
    }

    #[test]
    fn keys_are_the_entitys_own() {
        for a in AGENTS {
            assert_eq!(a.key, format!("swarms-{}", a.serves), "{}", a.name);
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
        assert_eq!(esc("\u{1}"), "\"\\u0001\"");
    }

    #[test]
    fn tree_holds_every_agent_once() {
        let n: usize = tree().iter().flat_map(|(_, ts)| ts.iter().map(|(_, m)| m.len())).sum();
        assert_eq!(n, AGENTS.len());
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
