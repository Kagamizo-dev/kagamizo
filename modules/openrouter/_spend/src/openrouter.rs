//! `openrouter`: the OpenRouter account as code. Every key (ours and the
//! one OpenRouter made at signup), the guardrails that bound where each key
//! may be routed, and the workspace's defaults are declared in Nix
//! (modules/openrouter) and rendered to one JSON file fixed at build time
//! (OPENROUTER_DECLARED). Nothing live may go undeclared.
//!
//!   openrouter plan      every declared setting against the live one; exits
//!                        1 on any drift or any undeclared key or guardrail
//!   openrouter apply     mint missing keys (piped into their secretspec
//!                        profile, never printed), set caps and disabled
//!                        states, create or update the guardrails and assign
//!                        their keys, set the workspace's defaults; delete
//!                        undeclared kagamizo/ keys (another's are reported)
//!   openrouter models    every declared model is still offered
//!   openrouter credits   the account's balance
//!   openrouter usage     each key's cap, what is left and when it resets
//!   openrouter probe MODEL TAG...
//!                        time to first token and tokens per second at each
//!                        endpoint, one tiny request each, for the routing
//!                        expectations (modules/openrouter/routing.nix)
//!
//! Run without its secret, it runs itself again under `secretspec run`: the
//! management key for the account, the research key for probes.
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::process::CommandExt;
use std::process::{Command, ExitCode, Stdio};
use std::time::Instant;

const DECLARED: &str = env!("OPENROUTER_DECLARED");
const API: &str = "https://openrouter.ai/api/v1";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dated_slug_is_its_alias() {
        assert!(same_model("deepseek/deepseek-v4.1-flash-20260910", "deepseek/deepseek-v4.1-flash"));
        assert!(same_model("deepseek/deepseek-v4.1-flash", "deepseek/deepseek-v4.1-flash"));
        assert!(!same_model("deepseek/deepseek-v4.1-flash-1017", "deepseek/deepseek-v4.1-flash"));
        assert!(!same_model("deepseek/deepseek-v4-pro", "deepseek/deepseek-v4.1-flash"));
    }
}

#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct Key {
    /// The key's name at OpenRouter: kagamizo/<name>, or a name OpenRouter gave it.
    label: String,
    /// Whether we mint it (false: it exists already and is adopted as is).
    minted: bool,
    profile: Option<String>,
    variable: Option<String>,
    limit_usd: Option<f64>,
    reset: Option<String>,
    disabled: bool,
}

#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct Guardrail {
    label: String,
    description: String,
    allowed_models: Vec<String>,
    allowed_providers: Vec<String>,
    keys: Vec<String>,
}

#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct Workspace {
    slug: String,
    default_provider_sort: Option<String>,
    default_text_model: Option<String>,
}

#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct Declared {
    secretspec: String,
    spec: String,
    keys: BTreeMap<String, Key>,
    guardrails: BTreeMap<String, Guardrail>,
    workspace: Workspace,
    models: Vec<String>,
}

fn declared() -> Declared {
    let text = std::fs::read_to_string(DECLARED).expect("the declared OpenRouter state");
    serde_json::from_str(&text).expect("the declared OpenRouter state is valid")
}

type R<T> = Result<T, String>;

/// Run this command again under `secretspec run` when its secret is unset.
fn under_secret(d: &Declared, var: &str, profile: &str, args: &[String]) -> R<()> {
    if std::env::var(var).is_ok_and(|v| !v.is_empty()) {
        return Ok(());
    }
    if std::env::var("OPENROUTER_UNDER_SECRETSPEC").is_ok() {
        return Err(format!("{var} is not set in the {profile} profile"));
    }
    let me = std::env::current_exe().map_err(|e| e.to_string())?;
    let err = Command::new(&d.secretspec)
        .args(["run", "--file", &d.spec, "--profile", profile, "--reason", &format!("openrouter {}", args.join(" ")), "--"])
        .arg(me)
        .args(args)
        .env("OPENROUTER_UNDER_SECRETSPEC", "1")
        .env("PROTON_PASS_KEY_PROVIDER", std::env::var("PROTON_PASS_KEY_PROVIDER").unwrap_or_else(|_| "fs".into()))
        .exec();
    Err(format!("{}: {err}", d.secretspec))
}

struct Api {
    token: String,
}

impl Api {
    fn management() -> R<Api> {
        Ok(Api { token: std::env::var("OPENROUTER_MANAGEMENT_KEY").map_err(|_| "OPENROUTER_MANAGEMENT_KEY is not set")? })
    }

    fn call(&self, method: &str, path: &str, body: Option<Value>) -> R<Value> {
        let req = ureq::request(method, &format!("{API}{path}")).set("Authorization", &format!("Bearer {}", self.token));
        let resp = match body {
            Some(b) => req.send_json(b),
            None => req.call(),
        };
        match resp {
            Ok(r) => r.into_json::<Value>().map_err(|e| format!("{method} {path}: {e}")),
            Err(ureq::Error::Status(code, r)) => Err(format!("{method} {path}: HTTP {code} {}", r.into_string().unwrap_or_default())),
            Err(e) => Err(format!("{method} {path}: {e}")),
        }
    }

    fn list(&self, path: &str) -> R<Vec<Value>> {
        Ok(self.call("GET", path, None)?["data"].as_array().cloned().unwrap_or_default())
    }
}

fn f(v: &Value) -> Option<f64> {
    v.as_f64()
}

/// What `plan` found, one line each; drift makes the plan fail.
struct Report {
    lines: Vec<String>,
    drift: bool,
}

impl Report {
    fn ok(&mut self, s: String) {
        self.lines.push(format!("  ok      {s}"));
    }
    fn change(&mut self, sign: &str, s: String) {
        self.drift = true;
        self.lines.push(format!("{sign} {s}"));
    }
}

fn key_drift(k: &Key, live: &Value) -> Vec<String> {
    let mut d = Vec::new();
    if live["disabled"].as_bool().unwrap_or(false) != k.disabled {
        d.push(format!("disabled {} -> {}", live["disabled"], k.disabled));
    }
    if f(&live["limit"]) != k.limit_usd {
        d.push(format!("limit {} -> {}", live["limit"], k.limit_usd.map_or("none".into(), |l| l.to_string())));
    }
    if live["limit_reset"].as_str() != k.reset.as_deref() {
        d.push(format!("reset {} -> {}", live["limit_reset"], k.reset.as_deref().unwrap_or("none")));
    }
    d
}

fn sorted(v: &Value) -> Vec<String> {
    let mut x: Vec<String> = v.as_array().map(|a| a.iter().filter_map(|s| s.as_str().map(String::from)).collect()).unwrap_or_default();
    x.sort();
    x
}

/// OpenRouter stores a model by its dated canonical slug
/// (deepseek/deepseek-v4.1-flash-20260910): the same model as its alias.
fn same_model(live: &str, alias: &str) -> bool {
    live == alias
        || live.strip_prefix(alias).and_then(|r| r.strip_prefix('-')).is_some_and(|d| d.len() == 8 && d.bytes().all(|b| b.is_ascii_digit()))
}

fn models_match(live: &Value, want: &[String]) -> bool {
    let live: Vec<String> = sorted(live);
    live.len() == want.len() && want.iter().all(|w| live.iter().any(|l| same_model(l, w)))
}

fn guardrail_drift(g: &Guardrail, live: &Value) -> Vec<String> {
    let mut d = Vec::new();
    let mut want_m = g.allowed_models.clone();
    want_m.sort();
    let mut want_p = g.allowed_providers.clone();
    want_p.sort();
    if !models_match(&live["allowed_models"], &want_m) {
        d.push(format!("models {:?} -> {want_m:?}", sorted(&live["allowed_models"])));
    }
    if sorted(&live["allowed_providers"]) != want_p {
        d.push(format!("providers {:?} -> {want_p:?}", sorted(&live["allowed_providers"])));
    }
    d
}

fn plan(d: &Declared, api: &Api) -> R<Report> {
    let mut r = Report { lines: vec![], drift: false };
    let keys = api.list("/keys?include_disabled=true")?;
    let by_name = |n: &str| keys.iter().find(|k| k["name"] == n);
    for (name, k) in &d.keys {
        match by_name(&k.label) {
            None if k.minted => r.change("+", format!("create  key {name} ({})", k.label)),
            None => r.change("!", format!("missing key {name}: {} is declared as adopted but does not exist", k.label)),
            Some(live) => {
                let drift = key_drift(k, live);
                if drift.is_empty() {
                    r.ok(format!("key {name}: used ${:.2} of {}", f(&live["usage"]).unwrap_or(0.0), live["limit"]));
                } else {
                    r.change("~", format!("update  key {name}: {}", drift.join(", ")));
                }
            }
        }
    }
    let labels: Vec<&str> = d.keys.values().map(|k| k.label.as_str()).collect();
    for live in &keys {
        let n = live["name"].as_str().unwrap_or("");
        if !labels.contains(&n) {
            r.change("-", format!("undeclared key {n:?} (limit {}, used ${:.2})", live["limit"], f(&live["usage"]).unwrap_or(0.0)));
        }
    }
    let guardrails = api.list("/guardrails")?;
    let assignments = api.list("/guardrails/assignments/keys")?;
    for (name, g) in &d.guardrails {
        match guardrails.iter().find(|x| x["name"] == g.label.as_str()) {
            None => r.change("+", format!("create  guardrail {name}: providers {:?}, models {:?}", g.allowed_providers, g.allowed_models)),
            Some(live) => {
                let mut drift = guardrail_drift(g, live);
                for kn in &g.keys {
                    let label = &d.keys[kn].label;
                    if !assignments.iter().any(|a| a["guardrail_id"] == live["id"] && a["key_name"] == label.as_str()) {
                        drift.push(format!("assign {kn}"));
                    }
                }
                if drift.is_empty() {
                    r.ok(format!("guardrail {name}: {} provider(s), {} model(s)", g.allowed_providers.len(), g.allowed_models.len()));
                } else {
                    r.change("~", format!("update  guardrail {name}: {}", drift.join(", ")));
                }
            }
        }
    }
    let glabels: Vec<&str> = d.guardrails.values().map(|g| g.label.as_str()).collect();
    for live in &guardrails {
        let n = live["name"].as_str().unwrap_or("");
        if !glabels.contains(&n) {
            r.change("-", format!("undeclared guardrail {n:?}"));
        }
    }
    let ws = api.list("/workspaces")?;
    match ws.iter().find(|w| w["slug"] == d.workspace.slug.as_str()) {
        None => r.change("!", format!("missing workspace {}", d.workspace.slug)),
        Some(w) => {
            let mut drift = vec![];
            if w["default_provider_sort"].as_str() != d.workspace.default_provider_sort.as_deref() {
                drift.push(format!("provider sort {} -> {:?}", w["default_provider_sort"], d.workspace.default_provider_sort));
            }
            if w["default_text_model"].as_str() != d.workspace.default_text_model.as_deref() {
                drift.push(format!("text model {} -> {:?}", w["default_text_model"], d.workspace.default_text_model));
            }
            if drift.is_empty() {
                r.ok(format!("workspace {}", d.workspace.slug));
            } else {
                r.change("~", format!("update  workspace {}: {}", d.workspace.slug, drift.join(", ")));
            }
        }
    }
    for w in &ws {
        if w["slug"] != d.workspace.slug.as_str() {
            r.change("-", format!("undeclared workspace {}", w["slug"]));
        }
    }
    Ok(r)
}

/// Mint a key and pipe its value, shown only once, into its profile.
fn mint(d: &Declared, api: &Api, name: &str, k: &Key) -> R<()> {
    let (Some(profile), Some(variable)) = (&k.profile, &k.variable) else {
        return Err(format!("key {name} is minted but declares no profile"));
    };
    let made = api.call("POST", "/keys", Some(json!({"name": k.label, "limit": k.limit_usd, "limit_reset": k.reset})))?;
    let secret = made["key"].as_str().ok_or("POST /keys returned no key")?.to_string();
    let mut child = Command::new(&d.secretspec)
        .args(["set", variable, "--file", &d.spec, "--profile", profile, "--from-file", "-", "--reason", &format!("openrouter: mint {name}")])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    child.stdin.take().expect("piped stdin").write_all(secret.as_bytes()).map_err(|e| e.to_string())?;
    if !child.wait().map_err(|e| e.to_string())?.success() {
        return Err(format!("secretspec set {profile}/{variable} failed; the minted key is unstored"));
    }
    println!("minted {name} -> {profile}/{variable}");
    if k.disabled {
        let hash = made["data"]["hash"].as_str().unwrap_or_default();
        api.call("PATCH", &format!("/keys/{hash}"), Some(json!({"disabled": true})))?;
    }
    Ok(())
}

fn apply(d: &Declared, api: &Api) -> R<()> {
    let keys = api.list("/keys?include_disabled=true")?;
    for (name, k) in &d.keys {
        match keys.iter().find(|x| x["name"] == k.label.as_str()) {
            None if k.minted => mint(d, api, name, k)?,
            None => return Err(format!("{}: declared as adopted, does not exist", k.label)),
            Some(live) if !key_drift(k, live).is_empty() => {
                let hash = live["hash"].as_str().unwrap_or_default();
                api.call("PATCH", &format!("/keys/{hash}"), Some(json!({"disabled": k.disabled, "limit": k.limit_usd, "limit_reset": k.reset})))?;
                println!("updated key {name}");
            }
            Some(_) => {}
        }
    }
    let labels: Vec<&str> = d.keys.values().map(|k| k.label.as_str()).collect();
    for live in &keys {
        let n = live["name"].as_str().unwrap_or("");
        if n.starts_with("kagamizo/") && !labels.contains(&n) {
            api.call("DELETE", &format!("/keys/{}", live["hash"].as_str().unwrap_or_default()), None)?;
            println!("deleted undeclared key {n}");
        } else if !labels.contains(&n) {
            println!("left undeclared key {n:?}: not ours to delete; declare it");
        }
    }
    let keys = api.list("/keys?include_disabled=true")?;
    let guardrails = api.list("/guardrails")?;
    for (name, g) in &d.guardrails {
        let body = json!({"name": g.label, "description": g.description, "allowed_models": g.allowed_models, "allowed_providers": g.allowed_providers});
        let id = match guardrails.iter().find(|x| x["name"] == g.label.as_str()) {
            Some(live) => {
                let id = live["id"].as_str().unwrap_or_default().to_string();
                if !guardrail_drift(g, live).is_empty() {
                    api.call("PATCH", &format!("/guardrails/{id}"), Some(body))?;
                    println!("updated guardrail {name}");
                }
                id
            }
            None => {
                let made = api.call("POST", "/guardrails", Some(body))?;
                println!("created guardrail {name}");
                made["data"]["id"].as_str().unwrap_or_default().to_string()
            }
        };
        let hashes: Vec<&str> = g
            .keys
            .iter()
            .filter_map(|kn| keys.iter().find(|x| x["name"] == d.keys[kn].label.as_str()).and_then(|x| x["hash"].as_str()))
            .collect();
        if !hashes.is_empty() {
            // A guardrail just created can answer 404 for a moment.
            let mut tries = 0;
            loop {
                match api.call("POST", &format!("/guardrails/{id}/assignments/keys"), Some(json!({"key_hashes": hashes}))) {
                    Ok(_) => break,
                    Err(e) if e.contains("HTTP 404") && tries < 5 => {
                        tries += 1;
                        std::thread::sleep(std::time::Duration::from_secs(2));
                    }
                    Err(e) => return Err(e),
                }
            }
            println!("assigned {} key(s) to guardrail {name}", hashes.len());
        }
    }
    let ws = api.list("/workspaces")?;
    if let Some(w) = ws.iter().find(|w| w["slug"] == d.workspace.slug.as_str()) {
        api.call(
            "PATCH",
            &format!("/workspaces/{}", w["id"].as_str().unwrap_or_default()),
            Some(json!({"default_provider_sort": d.workspace.default_provider_sort, "default_text_model": d.workspace.default_text_model})),
        )?;
        println!("set workspace {} defaults", d.workspace.slug);
    }
    Ok(())
}

/// One tiny streamed request pinned to one endpoint: time to first token
/// and output tokens per second after it.
fn probe_one(token: &str, model: &str, tag: &str) -> Value {
    let (provider, quant) = tag.split_once('/').unwrap_or((tag, ""));
    let mut routing = json!({"only": [provider], "allow_fallbacks": false});
    if !quant.is_empty() {
        routing["quantizations"] = json!([quant]);
    }
    let body = json!({
        "model": model, "stream": true, "max_tokens": 96, "provider": routing,
        "usage": {"include": true},
        "messages": [{"role": "user", "content": "Count from one to twenty in words, separated by spaces."}],
    });
    let start = Instant::now();
    let resp = ureq::post(&format!("{API}/chat/completions"))
        .set("Authorization", &format!("Bearer {token}"))
        .timeout(std::time::Duration::from_secs(60))
        .send_json(body);
    let resp = match resp {
        Ok(r) => r,
        Err(e) => return json!({"tag": tag, "ok": false, "error": e.to_string()}),
    };
    let (mut first, mut tokens, mut cost) = (None, 0u64, 0.0);
    for line in BufReader::new(resp.into_reader()).lines() {
        let Ok(line) = line else { break };
        let Some(data) = line.strip_prefix("data: ") else { continue };
        if data == "[DONE]" {
            break;
        }
        let Ok(v) = serde_json::from_str::<Value>(data) else { continue };
        // The first token of either kind: a reasoning model streams its
        // reasoning before its content.
        let delta = &v["choices"][0]["delta"];
        let any = |k: &str| delta[k].as_str().is_some_and(|s| !s.is_empty());
        if first.is_none() && (any("content") || any("reasoning") || any("reasoning_content")) {
            first = Some(start.elapsed());
        }
        if let Some(n) = v["usage"]["completion_tokens"].as_u64() {
            tokens = n;
            cost = v["usage"]["cost"].as_f64().unwrap_or(0.0);
        }
    }
    let total = start.elapsed();
    match first {
        Some(t) => {
            let after = (total - t).as_secs_f64().max(1e-3);
            json!({"tag": tag, "ok": true, "ttftMs": t.as_millis() as u64, "tokensPerSecond": ((tokens as f64) / after * 10.0).round() / 10.0, "costUsd": cost})
        }
        None => json!({"tag": tag, "ok": false, "error": "no token streamed"}),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let d = declared();
    let go = || -> R<bool> {
        match args.first().map(String::as_str) {
            Some("plan") => {
                under_secret(&d, "OPENROUTER_MANAGEMENT_KEY", "openrouter", &args)?;
                let r = plan(&d, &Api::management()?)?;
                for l in &r.lines {
                    println!("{l}");
                }
                Ok(!r.drift)
            }
            Some("apply") => {
                under_secret(&d, "OPENROUTER_MANAGEMENT_KEY", "openrouter", &args)?;
                apply(&d, &Api::management()?)?;
                Ok(true)
            }
            Some("credits") => {
                under_secret(&d, "OPENROUTER_MANAGEMENT_KEY", "openrouter", &args)?;
                let c = Api::management()?.call("GET", "/credits", None)?;
                let (t, u) = (f(&c["data"]["total_credits"]).unwrap_or(0.0), f(&c["data"]["total_usage"]).unwrap_or(0.0));
                println!("credits {t}, used {u:.2}, left {:.2}", t - u);
                Ok(true)
            }
            Some("usage") => {
                under_secret(&d, "OPENROUTER_MANAGEMENT_KEY", "openrouter", &args)?;
                let keys = Api::management()?.list("/keys")?;
                let out: Vec<Value> = d
                    .keys
                    .iter()
                    .filter_map(|(name, k)| {
                        let l = keys.iter().find(|x| x["name"] == k.label.as_str())?;
                        Some(json!({"key": name, "profile": k.profile, "capUsd": l["limit"], "leftUsd": l["limit_remaining"],
                            "usedUsd": l["usage"], "reset": l["limit_reset"], "disabled": l["disabled"]}))
                    })
                    .collect();
                println!("{}", serde_json::to_string_pretty(&out).unwrap());
                Ok(true)
            }
            Some("models") => {
                let offered: Vec<String> = ureq::get(&format!("{API}/models")).call().map_err(|e| e.to_string())?.into_json::<Value>().map_err(|e| e.to_string())?["data"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|m| m["id"].as_str().map(String::from)).collect())
                    .unwrap_or_default();
                let missing: Vec<&String> = d.models.iter().filter(|m| !offered.contains(m)).collect();
                if missing.is_empty() {
                    println!("all {} models offered", d.models.len());
                    Ok(true)
                } else {
                    eprintln!("no longer offered: {missing:?}");
                    Ok(false)
                }
            }
            Some("probe") if args.len() >= 3 => {
                under_secret(&d, "OPENROUTER_API_KEY", "research", &args)?;
                let token = std::env::var("OPENROUTER_API_KEY").map_err(|_| "OPENROUTER_API_KEY is not set")?;
                let results: Vec<Value> = args[2..].iter().map(|tag| probe_one(&token, &args[1], tag)).collect();
                let spent: f64 = results.iter().filter_map(|r| r["costUsd"].as_f64()).sum();
                println!("{}", serde_json::to_string_pretty(&json!({"model": args[1], "endpoints": results, "costUsd": spent})).unwrap());
                Ok(true)
            }
            _ => Err("usage: openrouter <plan|apply|models|credits|usage|probe MODEL TAG...>".into()),
        }
    };
    match go() {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(e) => {
            eprintln!("openrouter: {e}");
            ExitCode::from(2)
        }
    }
}
