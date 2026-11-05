//! `delegation`: an agent's authority (its governance grants) and the
//! narrowing of it (../default.nix renders DELEGATION_FACTS). The policy a
//! biscuit token carries; see the module header for the crypto seam.

include!(env!("DELEGATION_FACTS"));

const USAGE: &str = "usage: delegation <mint <agent> | attenuate <agent> <account>:<effect>... | check <agent> <account>:<effect>> [--json]";

/// (account, effect) pairs an agent may exercise.
fn authority(agent: &str) -> Vec<(&'static str, &'static str)> {
    CAPS.iter().filter(|(a, _, _)| *a == agent).map(|(_, acc, eff)| (*acc, *eff)).collect()
}

fn known_agent(agent: &str) -> bool {
    AGENTS.contains(&agent)
}

fn parse_pair(s: &str) -> Result<(String, String), String> {
    let (acc, eff) = s.split_once(':').ok_or_else(|| format!("{s} is not account:effect"))?;
    if acc.is_empty() || eff.is_empty() {
        return Err(format!("{s} is not account:effect"));
    }
    Ok((acc.to_string(), eff.to_string()))
}

/// Narrow an authority to a request, or reject if the request reaches past it.
fn attenuate<'a>(auth: &[(&'a str, &'a str)], request: &[(String, String)]) -> Result<Vec<(String, String)>, String> {
    for (acc, eff) in request {
        if !auth.iter().any(|(a, e)| a == acc && e == eff) {
            return Err(format!("{acc}:{eff} is not in the authority — attenuation only narrows"));
        }
    }
    Ok(request.to_vec())
}

fn json_pairs(ps: &[(String, String)]) -> String {
    format!(
        "[{}]",
        ps.iter().map(|(a, e)| format!("{{\"account\":\"{a}\",\"effect\":\"{e}\"}}")).collect::<Vec<_>>().join(",")
    )
}

fn run(args: &[String]) -> Result<String, String> {
    let json = args.iter().any(|a| a == "--json");
    let words: Vec<&str> = args.iter().map(String::as_str).filter(|a| *a != "--json").collect();
    match words.as_slice() {
        ["mint", agent] => {
            if !known_agent(agent) {
                return Err(format!("no agent {agent}"));
            }
            let auth = authority(agent);
            let owned: Vec<(String, String)> = auth.iter().map(|(a, e)| (a.to_string(), e.to_string())).collect();
            Ok(if json {
                json_pairs(&owned)
            } else if owned.is_empty() {
                format!("{agent}: no grants (reads nothing, writes nothing)")
            } else {
                format!("{agent} authority:\n{}", owned.iter().map(|(a, e)| format!("  {a} {e}")).collect::<Vec<_>>().join("\n"))
            })
        }
        ["attenuate", agent, rest @ ..] => {
            if !known_agent(agent) {
                return Err(format!("no agent {agent}"));
            }
            if rest.is_empty() {
                return Err("attenuate needs at least one account:effect".into());
            }
            let request: Vec<(String, String)> = rest.iter().map(|s| parse_pair(s)).collect::<Result<_, _>>()?;
            let narrowed = attenuate(&authority(agent), &request)?;
            Ok(if json { json_pairs(&narrowed) } else { format!("attenuated {agent} to {} pair(s); within authority", narrowed.len()) })
        }
        ["check", agent, pair] => {
            if !known_agent(agent) {
                return Err(format!("no agent {agent}"));
            }
            let (acc, eff) = parse_pair(pair)?;
            let ok = authority(agent).iter().any(|(a, e)| *a == acc && *e == eff);
            Ok(if json {
                format!("{{\"agent\":\"{agent}\",\"account\":\"{acc}\",\"effect\":\"{eff}\",\"allowed\":{ok}}}")
            } else if ok {
                format!("allowed: {agent} may {eff} {acc}")
            } else {
                format!("denied: {agent} has no {eff} on {acc}")
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
            eprintln!("delegation: {e}");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn effects_are_only_read_or_write() {
        for (_, _, e) in CAPS {
            assert!(*e == "read" || *e == "write", "agent effect {e} is not read/write");
        }
    }

    #[test]
    fn attenuation_only_narrows() {
        if let Some(agent) = AGENTS.iter().find(|a| !authority(a).is_empty()) {
            let auth = authority(agent);
            let (acc, eff) = auth[0];
            // A real subset is admitted.
            assert!(attenuate(&auth, &[(acc.to_string(), eff.to_string())]).is_ok());
            // A pair outside the authority is refused.
            assert!(attenuate(&auth, &[("no-such-account".into(), "read".into())]).is_err());
            // write is refused where only read is granted.
            if !auth.iter().any(|(a, e)| *a == acc && *e == "write") {
                assert!(attenuate(&auth, &[(acc.to_string(), "write".into())]).is_err());
            }
        }
    }

    #[test]
    fn check_matches_authority() {
        for (agent, acc, eff) in CAPS {
            assert!(run(&["check".into(), agent.to_string(), format!("{acc}:{eff}")]).unwrap().contains("allowed"));
        }
    }

    #[test]
    fn commands() {
        let a = AGENTS[0];
        assert!(run(&["mint".into(), a.into()]).is_ok());
        assert!(run(&["mint".into(), "nobody".into()]).is_err());
        assert!(run(&["check".into(), a.into(), "x:read".into()]).unwrap().contains("denied"));
        assert!(run(&["attenuate".into(), a.into(), "bad".into()]).is_err());
        assert!(run(&["bogus".into()]).is_err());
    }
}
