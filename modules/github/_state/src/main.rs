//! `github-state`: the kagamizo repository's settings and its project
//! management as code (modules/github/repo-state.nix, rendered to one JSON
//! file fixed at build time, GITHUB_STATE_DECLARED).
//!
//!   github-state plan    every declared setting, label and backlog issue
//!                        against the live repository; exits 1 on drift or
//!                        on any label or backlog issue not declared
//!   github-state apply   make the repository match
//!
//! REST only (a cloud session cannot reach GraphQL). The token is
//! GITHUB_TOKEN when set; without it the request goes unauthenticated,
//! which a session's proxy authorises for its own repository.
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::process::ExitCode;

const DECLARED: &str = env!("GITHUB_STATE_DECLARED");
const API: &str = "https://api.github.com";

#[derive(Deserialize, Clone, Debug)]
struct Label {
    color: String,
    description: String,
}

#[derive(Deserialize, Clone, Debug)]
struct Issue {
    title: String,
    body: String,
    labels: Vec<String>,
    open: bool,
}

#[derive(Deserialize, Debug)]
struct Declared {
    repo: String,
    settings: Map<String, Value>,
    security: Map<String, Value>,
    labels: BTreeMap<String, Label>,
    issues: BTreeMap<String, Issue>,
}

type R<T> = Result<T, String>;

/// The repository settings' names at GitHub.
fn snake(camel: &str) -> String {
    let mut out = String::new();
    for c in camel.chars() {
        if c.is_ascii_uppercase() {
            out.push('_');
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}

/// security_and_analysis's names for the declared security switches.
fn security_field(name: &str) -> Option<&'static str> {
    match name {
        "secretScanning" => Some("secret_scanning"),
        "secretScanningPushProtection" => Some("secret_scanning_push_protection"),
        "secretScanningNonProviderPatterns" => Some("secret_scanning_non_provider_patterns"),
        "dependabotSecurityUpdates" => Some("dependabot_security_updates"),
        _ => None,
    }
}

struct Gh {
    token: Option<String>,
    repo: String,
}

impl Gh {
    fn req(&self, method: &str, path: &str) -> ureq::Request {
        let r = ureq::request(method, &format!("{API}/repos/{}{path}", self.repo))
            .set("Accept", "application/vnd.github+json")
            .set("X-GitHub-Api-Version", "2022-11-28")
            .set("User-Agent", "kagamizo-github-state");
        match &self.token {
            Some(t) => r.set("Authorization", &format!("Bearer {t}")),
            None => r,
        }
    }

    fn call(&self, method: &str, path: &str, body: Option<Value>) -> R<Value> {
        let resp = match body {
            Some(b) => self.req(method, path).send_json(b),
            None => self.req(method, path).call(),
        };
        match resp {
            Ok(r) if r.status() == 204 => Ok(Value::Null),
            Ok(r) => Ok(r.into_json::<Value>().unwrap_or(Value::Null)),
            Err(ureq::Error::Status(code, r)) => Err(format!("{method} {path}: HTTP {code} {}", r.into_string().unwrap_or_default())),
            Err(e) => Err(format!("{method} {path}: {}", transport(&e))),
        }
    }

    /// Every page of a list.
    fn all(&self, path: &str) -> R<Vec<Value>> {
        let mut out = Vec::new();
        for page in 1..=20 {
            let sep = if path.contains('?') { '&' } else { '?' };
            let v = self.call("GET", &format!("{path}{sep}per_page=100&page={page}"), None)?;
            let items = v.as_array().cloned().unwrap_or_default();
            let n = items.len();
            out.extend(items);
            if n < 100 {
                break;
            }
        }
        Ok(out)
    }

    /// Whether Dependabot alerts are on (204) or off (404).
    fn dependabot_alerts(&self) -> R<bool> {
        match self.req("GET", "/vulnerability-alerts").call() {
            Ok(_) => Ok(true),
            Err(ureq::Error::Status(404, _)) => Ok(false),
            Err(e) => Err(format!("GET /vulnerability-alerts: {}", transport(&e))),
        }
    }
}

/// A transport error by its kind only: ureq's message can quote a request
/// header, and the Authorization header is a secret.
fn transport(e: &ureq::Error) -> String {
    match e {
        ureq::Error::Transport(t) => format!("transport error ({:?})", t.kind()),
        ureq::Error::Status(code, _) => format!("HTTP {code}"),
    }
}

struct Plan {
    lines: Vec<String>,
    drift: bool,
}

impl Plan {
    fn diff(&mut self, what: String) {
        self.drift = true;
        self.lines.push(what);
    }
}

fn issue_labels(i: &Value) -> Vec<String> {
    let mut l: Vec<String> = i["labels"].as_array().map(|a| a.iter().filter_map(|x| x["name"].as_str().map(String::from)).collect()).unwrap_or_default();
    l.sort();
    l
}

fn backlog_issues(gh: &Gh) -> R<Vec<Value>> {
    Ok(gh.all("/issues?state=all&labels=backlog")?.into_iter().filter(|i| i.get("pull_request").is_none()).collect())
}

fn plan(d: &Declared, gh: &Gh) -> R<Plan> {
    let mut p = Plan { lines: vec![], drift: false };
    let repo = gh.call("GET", "", None)?;
    for (k, want) in &d.settings {
        let have = &repo[snake(k)];
        if have != want {
            p.diff(format!("~ setting {k}: {have} -> {want}"));
        }
    }
    let sec = &repo["security_and_analysis"];
    for (k, want) in &d.security {
        if k == "dependabotAlerts" {
            let have = gh.dependabot_alerts()?;
            if Value::Bool(have) != *want {
                p.diff(format!("~ security {k}: {have} -> {want}"));
            }
            continue;
        }
        let field = security_field(k).ok_or_else(|| format!("no security field {k}"))?;
        let have = &sec[field]["status"];
        if have != want {
            p.diff(format!("~ security {k}: {have} -> {want}"));
        }
    }
    let labels = gh.all("/labels")?;
    for (name, l) in &d.labels {
        match labels.iter().find(|x| x["name"] == name.as_str()) {
            None => p.diff(format!("+ label {name}")),
            Some(x) if x["color"] != l.color.as_str() || x["description"].as_str().unwrap_or("") != l.description => {
                p.diff(format!("~ label {name}"))
            }
            Some(_) => {}
        }
    }
    for x in &labels {
        let n = x["name"].as_str().unwrap_or("");
        if !d.labels.contains_key(n) {
            p.diff(format!("- label {n} (undeclared)"));
        }
    }
    let issues = backlog_issues(gh)?;
    for (id, i) in &d.issues {
        match issues.iter().find(|x| x["title"] == i.title.as_str()) {
            None => p.diff(format!("+ issue {id}")),
            Some(x) => {
                let mut want = i.labels.clone();
                want.sort();
                let open = x["state"] == "open";
                if issue_labels(x) != want || open != i.open || x["body"].as_str().unwrap_or("") != i.body {
                    p.diff(format!("~ issue {id} (#{})", x["number"]));
                }
            }
        }
    }
    for x in &issues {
        let t = x["title"].as_str().unwrap_or("");
        if !d.issues.values().any(|i| i.title == t) && x["state"] == "open" {
            p.diff(format!("- issue #{} {t:?}: labelled backlog, not in the backlog", x["number"]));
        }
    }
    if !p.drift {
        p.lines.push(format!("  ok: {} settings, {} security switches, {} labels, {} backlog issues", d.settings.len(), d.security.len(), d.labels.len(), d.issues.len()));
    }
    Ok(p)
}

fn apply(d: &Declared, gh: &Gh) -> R<()> {
    let mut body = Map::new();
    for (k, v) in &d.settings {
        // GitHub sets this one itself for a public repository (forks are
        // always allowed); it is declared and checked, never sent.
        if k == "allowForking" {
            continue;
        }
        body.insert(snake(k), v.clone());
    }
    let mut sec = Map::new();
    for (k, v) in &d.security {
        if let Some(f) = security_field(k) {
            sec.insert(f.into(), json!({"status": v}));
        }
    }
    body.insert("security_and_analysis".into(), Value::Object(sec));
    gh.call("PATCH", "", Some(Value::Object(body)))?;
    println!("set the repository's settings and security");
    let alerts = d.security.get("dependabotAlerts").and_then(Value::as_bool).unwrap_or(false);
    gh.call(if alerts { "PUT" } else { "DELETE" }, "/vulnerability-alerts", None)?;
    println!("dependabot alerts {}", if alerts { "on" } else { "off" });

    let labels = gh.all("/labels")?;
    for (name, l) in &d.labels {
        let b = json!({"name": name, "color": l.color, "description": l.description});
        match labels.iter().find(|x| x["name"] == name.as_str()) {
            None => {
                gh.call("POST", "/labels", Some(b))?;
                println!("created label {name}");
            }
            Some(x) if x["color"] != l.color.as_str() || x["description"].as_str().unwrap_or("") != l.description => {
                gh.call("PATCH", &format!("/labels/{}", enc(name)), Some(b))?;
                println!("updated label {name}");
            }
            Some(_) => {}
        }
    }
    for x in &labels {
        let n = x["name"].as_str().unwrap_or("");
        if !d.labels.contains_key(n) {
            gh.call("DELETE", &format!("/labels/{}", enc(n)), None)?;
            println!("deleted undeclared label {n}");
        }
    }

    let issues = backlog_issues(gh)?;
    for (id, i) in &d.issues {
        let state = if i.open { "open" } else { "closed" };
        match issues.iter().find(|x| x["title"] == i.title.as_str()) {
            None => {
                let made = gh.call("POST", "/issues", Some(json!({"title": i.title, "body": i.body, "labels": i.labels})))?;
                if !i.open {
                    gh.call("PATCH", &format!("/issues/{}", made["number"]), Some(json!({"state": "closed", "state_reason": "completed"})))?;
                }
                println!("created issue {id} (#{})", made["number"]);
            }
            Some(x) => {
                let mut want = i.labels.clone();
                want.sort();
                if issue_labels(x) != want || (x["state"] == "open") != i.open || x["body"].as_str().unwrap_or("") != i.body {
                    let mut b = json!({"body": i.body, "labels": i.labels, "state": state});
                    if !i.open {
                        b["state_reason"] = json!("completed");
                    }
                    gh.call("PATCH", &format!("/issues/{}", x["number"]), Some(b))?;
                    println!("updated issue {id} (#{})", x["number"]);
                }
            }
        }
    }
    Ok(())
}

/// A label's name in a path.
fn enc(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn main() -> ExitCode {
    let d: Declared = serde_json::from_str(&std::fs::read_to_string(DECLARED).expect("the declared state")).expect("valid declared state");
    // A stored token may end in a newline; a header cannot.
    let gh = Gh { token: std::env::var("GITHUB_TOKEN").ok().map(|t| t.trim().to_string()).filter(|t| !t.is_empty()), repo: d.repo.clone() };
    let run = || -> R<bool> {
        match std::env::args().nth(1).as_deref() {
            Some("plan") => {
                let p = plan(&d, &gh)?;
                for l in &p.lines {
                    println!("{l}");
                }
                Ok(!p.drift)
            }
            Some("apply") => {
                apply(&d, &gh)?;
                Ok(true)
            }
            _ => Err("usage: github-state plan|apply".into()),
        }
    };
    match run() {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(e) => {
            eprintln!("github-state: {e}");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_are_named_as_github_names_them() {
        assert_eq!(snake("deleteBranchOnMerge"), "delete_branch_on_merge");
        assert_eq!(snake("hasIssues"), "has_issues");
        assert_eq!(security_field("secretScanningPushProtection"), Some("secret_scanning_push_protection"));
        assert_eq!(security_field("dependabotAlerts"), None);
    }

    #[test]
    fn label_names_are_escaped_in_paths() {
        assert_eq!(enc("team:upkeep"), "team%3Aupkeep");
        assert_eq!(enc("good first issue"), "good%20first%20issue");
    }
}
