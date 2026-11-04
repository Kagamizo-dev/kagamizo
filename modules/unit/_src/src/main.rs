//! `unit`: delegated units of work (../default.nix renders UNITS_JSON).
//!
//! `run` is a loop after mini-swe-agent's: the model answers with one bash
//! block per turn, the block runs in a throwaway worktree of the
//! repository (no network when `unshare` allows it), its output goes back,
//! and the run ends when the model says UNIT_DONE, the step limit is hit,
//! or the provider's reported cost would pass the unit's cap. What it
//! changed is written as a patch, refused if it touches a path the unit
//! does not list.

use serde_json::{json, Value};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const UNITS: &str = include_str!(env!("UNITS_JSON"));
const USAGE: &str = "usage: unit <list | show <id> | bounds | run <id>> [--json]";
const ENDPOINT: &str = "https://openrouter.ai/api/v1/chat/completions";
const OUTPUT_LIMIT: usize = 6000;

fn units() -> Value {
    serde_json::from_str(UNITS).expect("UNITS_JSON is rendered by Nix")
}

fn unit(id: &str) -> Result<Value, String> {
    units().get(id).cloned().ok_or_else(|| format!("no unit {id}"))
}

fn s<'a>(v: &'a Value, k: &str) -> &'a str {
    v.get(k).and_then(Value::as_str).unwrap_or("")
}

fn n(v: &Value, k: &str) -> u64 {
    v.get(k).and_then(Value::as_u64).unwrap_or(0)
}

fn strs(v: &Value, k: &str) -> Vec<String> {
    v.get(k)
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
        .unwrap_or_default()
}

/// The one bash block of a reply, if it has exactly one.
pub fn bash_block(reply: &str) -> Option<String> {
    let mut blocks = Vec::new();
    let mut rest = reply;
    while let Some(start) = rest.find("```bash") {
        let after = &rest[start + 7..];
        let end = after.find("```")?;
        blocks.push(after[..end].trim().to_string());
        rest = &after[end + 3..];
    }
    if blocks.len() == 1 {
        blocks.pop()
    } else {
        None
    }
}

/// Whether a path is one a unit lists (a trailing `/**` is a whole tree).
pub fn allowed(path: &str, paths: &[String]) -> bool {
    paths.iter().any(|p| match p.strip_suffix("/**") {
        Some(dir) => path == dir || path.starts_with(&format!("{dir}/")),
        None => path == p,
    })
}

fn truncate(s: &str) -> String {
    if s.len() <= OUTPUT_LIMIT {
        return s.to_string();
    }
    let head: String = s.chars().take(OUTPUT_LIMIT / 2).collect();
    let tail: String = s.chars().rev().take(OUTPUT_LIMIT / 2).collect::<Vec<_>>().into_iter().rev().collect();
    format!("{head}\n[... {} bytes elided ...]\n{tail}", s.len() - OUTPUT_LIMIT)
}

fn system_prompt(u: &Value) -> String {
    format!(
        concat!(
            "You complete one unit of work in a git checkout of the kagamizo repository (Nix, Rust, Lean). ",
            "Each turn: one or two sentences of thought, then exactly one ```bash block, which is run in the ",
            "checkout's root; you get its exit code and output back. Inspect before you edit. You may change only: {}. ",
            "Make the smallest change that does the task. When the task is done and checked, reply with the word ",
            "UNIT_DONE and no bash block. Never print secrets; there is no network."
        ),
        strs(u, "paths").join(", ")
    )
}

/// One chat completion through curl; the key goes in a header file only
/// this process can read, never on a command line.
fn complete(u: &Value, messages: &[Value], key: &str, scratch: &Path) -> Result<(String, f64), String> {
    let mut body = json!({
        "model": s(u, "model"),
        "messages": messages,
        "max_tokens": 1500,
        "temperature": 0.2,
    });
    if !u.get("reasoning").and_then(Value::as_bool).unwrap_or(false) {
        body["reasoning"] = json!({ "enabled": false });
    }
    let header = scratch.join("auth-header");
    {
        use std::os::unix::fs::OpenOptionsExt;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(&header)
            .map_err(|e| e.to_string())?;
        writeln!(f, "Authorization: Bearer {key}").map_err(|e| e.to_string())?;
    }
    let mut child = Command::new("curl")
        .args(["-sS", "--max-time", "180", "-H", "Content-Type: application/json", "--data-binary", "@-"])
        .arg("-H")
        .arg(format!("@{}", header.display()))
        .arg(ENDPOINT)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("curl: {e}"))?;
    child.stdin.take().ok_or("curl: no stdin")?.write_all(body.to_string().as_bytes()).map_err(|e| e.to_string())?;
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    let _ = std::fs::remove_file(&header);
    if !out.status.success() {
        return Err(format!("curl: {}", String::from_utf8_lossy(&out.stderr).trim()));
    }
    let v: Value = serde_json::from_slice(&out.stdout).map_err(|e| format!("not JSON from OpenRouter: {e}"))?;
    if let Some(err) = v.get("error") {
        return Err(format!("OpenRouter: {err}"));
    }
    let reply = v["choices"][0]["message"]["content"].as_str().unwrap_or("").to_string();
    let cost = v["usage"]["cost"].as_f64().unwrap_or(0.0);
    Ok((reply, cost))
}

fn sandboxed(cmd: &str, dir: &Path) -> (i32, String) {
    let isolated = Command::new("unshare").args(["-rn", "true"]).status().map(|s| s.success()).unwrap_or(false);
    let mut c = if isolated {
        let mut c = Command::new("unshare");
        c.args(["-rn", "timeout", "60", "bash", "-c", cmd]);
        c
    } else {
        let mut c = Command::new("timeout");
        c.args(["60", "bash", "-c", cmd]);
        c
    };
    // Nothing of the runner's environment, the key above all, reaches it.
    c.current_dir(dir)
        .env_clear()
        .env("PATH", std::env::var("PATH").unwrap_or_default())
        .env("HOME", dir)
        .env("LANG", "C.UTF-8");
    match c.output() {
        Ok(o) => {
            let mut text = String::from_utf8_lossy(&o.stdout).to_string();
            text.push_str(&String::from_utf8_lossy(&o.stderr));
            (o.status.code().unwrap_or(-1), truncate(&text))
        }
        Err(e) => (-1, format!("could not run: {e}")),
    }
}

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    let o = Command::new("git").arg("-C").arg(dir).args(args).output().map_err(|e| format!("git: {e}"))?;
    if o.status.success() {
        Ok(String::from_utf8_lossy(&o.stdout).to_string())
    } else {
        Err(format!("git {}: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()))
    }
}

fn run(id: &str) -> Result<String, String> {
    let u = unit(id)?;
    let key = std::env::var(s(&u, "variable")).map_err(|_| format!("{} is not set: run through `unit run`", s(&u, "variable")))?;
    let root = PathBuf::from(git(Path::new("."), &["rev-parse", "--show-toplevel"])?.trim());
    let scratch = std::env::temp_dir().join(format!("unit-{id}-{}", std::process::id()));
    let wt = scratch.join("checkout");
    std::fs::create_dir_all(&scratch).map_err(|e| e.to_string())?;
    git(&root, &["worktree", "add", "--detach", wt.to_str().ok_or("path")?, "HEAD"])?;
    let result = (|| {
        let cap = n(&u, "maxCents") as f64 / 100.0;
        let mut spent = 0.0;
        let mut messages = vec![
            json!({"role": "system", "content": system_prompt(&u)}),
            json!({"role": "user", "content": s(&u, "instruction")}),
        ];
        let mut done = false;
        let mut steps = 0;
        while steps < n(&u, "maxSteps") {
            steps += 1;
            let (reply, cost) = complete(&u, &messages, &key, &scratch)?;
            spent += cost;
            eprintln!("unit {id}: step {steps}, ${spent:.5} of ${cap:.2}");
            messages.push(json!({"role": "assistant", "content": reply}));
            if spent >= cap {
                return Err(format!("stopped at the cap: ${spent:.5} of ${cap:.2}"));
            }
            match bash_block(&reply) {
                Some(cmd) => {
                    let (code, out) = sandboxed(&cmd, &wt);
                    messages.push(json!({"role": "user", "content": format!("exit {code}\n{out}")}));
                }
                None if reply.contains("UNIT_DONE") => {
                    done = true;
                    break;
                }
                None => messages.push(json!({"role": "user", "content": "Reply with exactly one ```bash block, or UNIT_DONE when finished."})),
            }
        }
        git(&wt, &["add", "-A"])?;
        let changed: Vec<String> = git(&wt, &["diff", "--cached", "--name-only"])?.lines().map(String::from).collect();
        let paths = strs(&u, "paths");
        let outside: Vec<&String> = changed.iter().filter(|p| !allowed(p, &paths)).collect();
        if !outside.is_empty() {
            return Err(format!("refused: the patch touches paths the unit does not list: {outside:?}"));
        }
        let patch = git(&wt, &["diff", "--cached"])?;
        let dir = root.join(".git").join("units");
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        let file = dir.join(format!("{id}.patch"));
        std::fs::write(&file, &patch).map_err(|e| e.to_string())?;
        Ok(format!(
            "unit {id}: {} after {steps} steps, ${spent:.5} of ${cap:.2}\n  changed: {}\n  patch:   {}\n  accept:  {}",
            if done { "done" } else { "step limit reached" },
            if changed.is_empty() { "nothing".into() } else { changed.join(", ") },
            file.display(),
            strs(&u, "accept").iter().map(|c| format!(".#checks.x86_64-linux.{c}")).collect::<Vec<_>>().join(" ")
        ))
    })();
    let _ = git(&root, &["worktree", "remove", "--force", wt.to_str().unwrap_or("")]);
    let _ = std::fs::remove_dir_all(&scratch);
    result
}

fn cli(args: &[String]) -> Result<String, String> {
    let json = args.iter().any(|a| a == "--json");
    let words: Vec<&str> = args.iter().map(String::as_str).filter(|a| *a != "--json").collect();
    match words.as_slice() {
        ["list"] => {
            let all = units();
            let map = all.as_object().ok_or("units")?;
            Ok(if json {
                all.to_string()
            } else {
                map.iter()
                    .map(|(id, u)| format!("{id:<28} {:<16} {:<6} {:>3}c  {}", s(u, "owner"), s(u, "task"), n(u, "maxCents"), s(u, "model")))
                    .collect::<Vec<_>>()
                    .join("\n")
            })
        }
        ["show", id] => {
            let u = unit(id)?;
            Ok(if json { u.to_string() } else { serde_json::to_string_pretty(&u).map_err(|e| e.to_string())? })
        }
        ["bounds"] => {
            let all = units();
            let map = all.as_object().ok_or("units")?;
            let mut owners: Vec<(String, u64, u64)> = Vec::new();
            for u in map.values() {
                let o = s(u, "owner").to_string();
                match owners.iter_mut().find(|(n, _, _)| *n == o) {
                    Some(e) => e.1 += n(u, "maxCents"),
                    None => owners.push((o, n(u, "maxCents"), n(u, "shareCents"))),
                }
            }
            Ok(owners
                .iter()
                .map(|(o, used, share)| format!("{o:<16} units may spend {used}c of a {share}c monthly share"))
                .collect::<Vec<_>>()
                .join("\n"))
        }
        ["run", id] => run(id),
        _ => Err(USAGE.into()),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match cli(&args) {
        Ok(out) => println!("{out}"),
        Err(e) => {
            eprintln!("unit: {e}");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_bash_block_or_none() {
        assert_eq!(bash_block("look:\n```bash\nls -la\n```\n"), Some("ls -la".into()));
        assert_eq!(bash_block("```bash\na\n```\n```bash\nb\n```"), None);
        assert_eq!(bash_block("UNIT_DONE"), None);
    }

    #[test]
    fn paths_are_held() {
        let p = vec!["modules/project/_data/decisions.json".to_string(), "modules/scout/_data/**".to_string()];
        assert!(allowed("modules/project/_data/decisions.json", &p));
        assert!(allowed("modules/scout/_data/candidates.json", &p));
        assert!(!allowed("modules/project/default.nix", &p));
        assert!(!allowed("modules/scoutx/a", &p));
    }

    #[test]
    fn every_unit_is_complete() {
        for (id, u) in units().as_object().unwrap() {
            assert!(!s(u, "model").is_empty(), "{id}: no model");
            assert!(!s(u, "variable").is_empty(), "{id}: no key variable");
            assert!(n(u, "maxCents") <= n(u, "shareCents"), "{id}: cap above share");
        }
    }

    #[test]
    fn long_output_is_cut() {
        let long = "x".repeat(OUTPUT_LIMIT * 2);
        assert!(truncate(&long).len() < long.len());
    }
}
