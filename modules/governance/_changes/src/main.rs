//! `changes`: which class each changed path falls in, and whether an agent's
//! request may merge (modules/governance/changes.nix; the rules are
//! `_lean/Changes.lean`'s). The table is baked in at build (CHANGE_CLASSES,
//! one line per rule: `class<TAB>merge<TAB>pattern`), so the binary states
//! the repository's own declaration and nothing else.
//!
//!   changes classify PATH...                 each path's class, then the request's
//!   changes decide --branch B [--approved] PATH...
//!       exit 0 when the request may merge as it stands, 1 with the reason
//!       when not: an agent's branch (agents/*) merges only classes agents
//!       hold, or owner classes once the owner approved; infra, secret and
//!       spend never; any other branch is the owner's own.
//!
//! Patterns are globs over `/`-separated paths: `*` within a segment,
//! `**` any run of segments. The most restrictive matching class wins
//! (never > owner > agent); a path matching no rule is `code` (owner).
use std::process::exit;

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
enum Merge {
    Agent,
    Owner,
    Never,
}

impl Merge {
    fn parse(s: &str) -> Merge {
        match s {
            "agent" => Merge::Agent,
            "owner" => Merge::Owner,
            "never" => Merge::Never,
            other => panic!("changes: unknown merge rule {other}"),
        }
    }
    fn name(self) -> &'static str {
        match self {
            Merge::Agent => "agent",
            Merge::Owner => "owner",
            Merge::Never => "never",
        }
    }
}

struct Rule {
    class: &'static str,
    merge: Merge,
    pattern: &'static str,
}

const TABLE: &str = include_str!(env!("CHANGE_CLASSES"));
const DEFAULT: (&str, Merge) = ("code", Merge::Owner);

fn rules() -> Vec<Rule> {
    TABLE
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| {
            let mut f = l.split('\t');
            Rule {
                class: f.next().expect("class"),
                merge: Merge::parse(f.next().expect("merge")),
                pattern: f.next().expect("pattern"),
            }
        })
        .collect()
}

/// Segment-wise glob: `*` matches within one segment, `**` any segments.
fn glob(pattern: &[&str], path: &[&str]) -> bool {
    match (pattern.split_first(), path.split_first()) {
        (None, None) => true,
        (None, Some(_)) => false,
        (Some((&"**", rest)), _) => {
            (0..=path.len()).any(|i| glob(rest, &path[i..]))
        }
        (Some((seg, rest)), Some((head, tail))) => segment(seg, head) && glob(rest, tail),
        (Some(_), None) => false,
    }
}

/// One segment against one: `*` matches any run of characters.
fn segment(pat: &str, s: &str) -> bool {
    match pat.split_once('*') {
        None => pat == s,
        Some((pre, post)) => {
            s.len() >= pre.len() + post.len()
                && s.starts_with(pre)
                && s.ends_with(post)
                && segment_rest(post, &s[pre.len()..])
        }
    }
}

fn segment_rest(post: &str, s: &str) -> bool {
    // `post` may hold more stars: match it against some suffix of `s`.
    (0..=s.len()).any(|i| s.is_char_boundary(i) && segment(post, &s[i..]))
}

fn classify<'a>(rules: &'a [Rule], path: &str) -> (&'a str, Merge) {
    let segs: Vec<&str> = path.split('/').collect();
    rules
        .iter()
        .filter(|r| glob(&r.pattern.split('/').collect::<Vec<_>>(), &segs))
        .map(|r| (r.class, r.merge))
        .max_by_key(|&(_, m)| m)
        .unwrap_or(DEFAULT)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let rules = rules();
    match args.first().map(String::as_str) {
        Some("classify") => {
            let paths = &args[1..];
            let mut worst = Merge::Agent;
            for p in paths {
                let (c, m) = classify(&rules, p);
                println!("{c}\t{}\t{p}", m.name());
                worst = worst.max(m);
            }
            if paths.is_empty() {
                eprintln!("changes: no paths");
                exit(2);
            }
            println!("request\t{}", worst.name());
        }
        Some("decide") => {
            let mut branch = None;
            let mut approved = false;
            let mut paths = Vec::new();
            let mut it = args[1..].iter();
            while let Some(a) = it.next() {
                match a.as_str() {
                    "--branch" => branch = it.next().cloned(),
                    "--approved" => approved = true,
                    p => paths.push(p.to_string()),
                }
            }
            let branch = branch.unwrap_or_else(|| {
                eprintln!("usage: changes decide --branch BRANCH [--approved] PATH...");
                exit(2)
            });
            let (ok, why) = decide(&rules, &branch, approved, &paths);
            println!("{why}");
            exit(if ok { 0 } else { 1 });
        }
        _ => {
            eprintln!("usage: changes classify PATH... | changes decide --branch BRANCH [--approved] PATH...");
            exit(2);
        }
    }
}

/// The decision, as `_lean/Changes.lean` states it: an agent's request
/// merges when every class is the agents' own; owner classes once the owner
/// approved; a never class refuses it. The owner's own branches are theirs.
fn decide(rules: &[Rule], branch: &str, approved: bool, paths: &[String]) -> (bool, String) {
    if !branch.starts_with("agents/") {
        return (true, format!("{branch}: the owner's branch; the owner decides"));
    }
    if paths.is_empty() {
        return (false, "an empty request".into());
    }
    let classes: Vec<(&str, Merge, &str)> = paths
        .iter()
        .map(|p| {
            let (c, m) = classify(rules, p);
            (c, m, p.as_str())
        })
        .collect();
    if let Some((c, _, p)) = classes.iter().find(|(_, m, _)| *m == Merge::Never) {
        return (false, format!("refused: {p} is {c}, never an agent's"));
    }
    let owner: Vec<_> = classes.iter().filter(|(_, m, _)| *m == Merge::Owner).collect();
    if owner.is_empty() {
        return (true, "agents merge it: every path is theirs (content)".into());
    }
    if approved {
        return (
            true,
            format!("the owner approved it ({} owner-class paths)", owner.len()),
        );
    }
    let (c, _, p) = owner[0];
    (false, format!("waits for the owner: {p} is {c}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table() -> Vec<Rule> {
        rules()
    }

    #[test]
    fn globs() {
        let g = |p: &str, s: &str| glob(&p.split('/').collect::<Vec<_>>(), &s.split('/').collect::<Vec<_>>());
        assert!(g("modules/cloudflare/**", "modules/cloudflare/infra.nix"));
        assert!(g("modules/cloudflare/**", "modules/cloudflare/_cf/x.json"));
        assert!(!g("modules/cloudflare/**", "modules/hetzner/host.nix"));
        assert!(g("modules/*/secrets.nix", "modules/github/secrets.nix"));
        assert!(!g("modules/*/secrets.nix", "modules/a/b/secrets.nix"));
        assert!(g("**/*.lean", "modules/agents/_lean/Budget.lean"));
        assert!(g("secretspec.toml", "secretspec.toml"));
        assert!(!g("secretspec.toml", "x/secretspec.toml"));
    }

    #[test]
    fn classes_from_the_table() {
        let r = table();
        assert_eq!(classify(&r, "modules/cloudflare/infra.nix").1, Merge::Never);
        assert_eq!(classify(&r, "secretspec.toml").1, Merge::Never);
        assert_eq!(classify(&r, "modules/openrouter/secrets.nix").1, Merge::Never);
        assert_eq!(classify(&r, "modules/twin/_items/laptop.json"), ("content", Merge::Agent));
        assert_eq!(classify(&r, "modules/site/default.nix"), ("page-design", Merge::Owner));
        assert_eq!(classify(&r, "modules/agents/tiers.nix"), ("spend", Merge::Never));
        assert_eq!(classify(&r, "modules/lean/_lean/Api.lean"), ("code", Merge::Owner));
        assert_eq!(classify(&r, "modules/site/_copy/home.md"), ("content", Merge::Agent));
        assert_eq!(classify(&r, "something/odd.txt"), DEFAULT);
    }

    #[test]
    fn decisions() {
        let r = table();
        let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        assert!(decide(&r, "ccr-x", false, &s(&["modules/cloudflare/infra.nix"])).0);
        assert!(decide(&r, "agents/twin/laptop", false, &s(&["modules/twin/_items/laptop.json"])).0);
        assert!(!decide(&r, "agents/twin/x", false, &s(&["modules/twin/_items/a.json", "modules/lean/_lean/Api.lean"])).0);
        assert!(decide(&r, "agents/twin/x", true, &s(&["modules/lean/_lean/Api.lean"])).0);
        assert!(!decide(&r, "agents/twin/x", true, &s(&["modules/agents/tiers.nix"])).0);
        assert!(!decide(&r, "agents/twin/x", true, &s(&["modules/cloudflare/infra.nix"])).0);
        assert!(!decide(&r, "agents/twin/x", true, &s(&["modules/mercury/owner-cards.nix"])).0);
    }
}
