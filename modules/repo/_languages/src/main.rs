//! lang-scan: holds the repository to its languages (modules/repo/languages.nix).
//!
//! The code we author is Rust, Lean or Nix. Every other file must be a
//! declared data format, a declared exact name, or a dated exception; and a
//! Nix file may carry inline code (shell wrappers, build scripts, script or
//! style tags, Python) only up to the count its exception records, so the
//! backlog can shrink and never grow.
//!
//!   lang-scan check <root>       fail, naming each violation, if any
//!   lang-scan baseline <root>    print today's violations as exceptions JSON
//!   lang-scan install-hook       link .git/hooks/pre-commit to this binary
//!   pre-commit (argv[0])         the hook: check the work tree, then nixfmt
//!                                --check the staged Nix files
//!
//! The policy is the JSON modules/repo/languages.nix renders, fixed at build
//! time (LANG_SCAN_POLICY), as is nixfmt's path (LANG_SCAN_NIXFMT).

use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const POLICY: &str = env!("LANG_SCAN_POLICY");
const NIXFMT: &str = env!("LANG_SCAN_NIXFMT");

struct Policy {
    code: Vec<String>,
    data: Vec<String>,
    names: Vec<String>,
    skip: Vec<String>,
    markers: Vec<String>,
    /// path -> allowed marker count (files) or None (a whole non-code file)
    exceptions: BTreeMap<String, Option<u64>>,
}

fn strings(v: &Value, key: &str) -> Vec<String> {
    v[key]
        .as_array()
        .map(|a| a.iter().filter_map(|s| s.as_str().map(String::from)).collect())
        .unwrap_or_default()
}

fn load_policy() -> Result<Policy, String> {
    let text = fs::read_to_string(POLICY).map_err(|e| format!("policy {POLICY}: {e}"))?;
    let v: Value = serde_json::from_str(&text).map_err(|e| format!("policy: {e}"))?;
    let mut exceptions = BTreeMap::new();
    if let Some(obj) = v["exceptions"].as_object() {
        for (path, e) in obj {
            exceptions.insert(path.clone(), e["markers"].as_u64());
        }
    }
    Ok(Policy {
        code: strings(&v, "code"),
        data: strings(&v, "data"),
        names: strings(&v, "names"),
        skip: strings(&v, "skip"),
        markers: strings(&v, "markers"),
        exceptions,
    })
}

#[derive(Debug)]
enum Finding {
    /// A file whose language is neither code nor declared data.
    Language { path: String, ext: String },
    /// A Nix file with inline code.
    Inline { path: String, count: u64 },
}

impl Finding {
    fn path(&self) -> &str {
        match self {
            Finding::Language { path, .. } | Finding::Inline { path, .. } => path,
        }
    }
}

fn walk(root: &Path, dir: &Path, policy: &Policy, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    let mut entries: Vec<_> = fs::read_dir(dir)?.collect::<Result<_, _>>()?;
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let name = entry.file_name().to_string_lossy().into_owned();
        let path = entry.path();
        let kind = entry.file_type()?;
        if kind.is_symlink() {
            continue;
        }
        if kind.is_dir() {
            if policy.skip.iter().any(|s| s == &name) {
                continue;
            }
            walk(root, &path, policy, out)?;
        } else if kind.is_file() {
            out.push(path.strip_prefix(root).unwrap_or(&path).to_path_buf());
        }
    }
    Ok(())
}

fn extension(path: &Path) -> String {
    path.extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default()
}

/// Inline code in a Nix file: one count per marker occurrence.
fn inline_count(text: &str, markers: &[String]) -> u64 {
    markers
        .iter()
        .map(|m| text.matches(m.as_str()).count() as u64)
        .sum()
}

fn scan(root: &Path, policy: &Policy) -> Result<Vec<Finding>, String> {
    let mut files = Vec::new();
    walk(root, root, policy, &mut files).map_err(|e| format!("walk {}: {e}", root.display()))?;
    let mut findings = Vec::new();
    for rel in files {
        let path = rel.to_string_lossy().replace('\\', "/");
        let name = rel
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let ext = extension(&rel);
        if ext == "nix" {
            let text = fs::read_to_string(root.join(&rel)).unwrap_or_default();
            let count = inline_count(&text, &policy.markers);
            if count > 0 {
                findings.push(Finding::Inline { path, count });
            }
        } else if policy.code.contains(&ext)
            || policy.data.contains(&ext)
            || policy.names.contains(&name)
        {
            continue;
        } else {
            findings.push(Finding::Language { path, ext });
        }
    }
    Ok(findings)
}

/// Findings the exceptions do not cover, and exceptions that cover nothing.
fn judge(findings: &[Finding], policy: &Policy) -> (Vec<String>, Vec<String>) {
    let mut problems = Vec::new();
    for f in findings {
        match (f, policy.exceptions.get(f.path())) {
            (_, None) => problems.push(match f {
                Finding::Language { path, ext } => format!(
                    "{path}: .{ext} is not Rust, Lean, Nix or a declared data format; write it in Rust or declare a dated exception"
                ),
                Finding::Inline { path, count } => format!(
                    "{path}: {count} inline code marker(s) (shell, script, style or Python inside Nix); move the code into a Rust crate or declare a dated exception"
                ),
            }),
            (Finding::Inline { path, count }, Some(Some(allowed))) if count > allowed => {
                problems.push(format!(
                    "{path}: {count} inline code markers, its exception allows {allowed}; the backlog may only shrink"
                ))
            }
            _ => {}
        }
    }
    let present: Vec<&str> = findings.iter().map(Finding::path).collect();
    let stale = policy
        .exceptions
        .keys()
        .filter(|p| !present.contains(&p.as_str()))
        .cloned()
        .collect();
    (problems, stale)
}

fn check(root: &Path) -> Result<bool, String> {
    let policy = load_policy()?;
    let findings = scan(root, &policy)?;
    let (problems, stale) = judge(&findings, &policy);
    for p in &problems {
        eprintln!("lang-scan: {p}");
    }
    for s in &stale {
        eprintln!("lang-scan: {s}: its exception covers nothing now; remove it and lower the baseline");
    }
    let markers: u64 = findings
        .iter()
        .map(|f| match f {
            Finding::Inline { count, .. } => *count,
            Finding::Language { .. } => 0,
        })
        .sum();
    eprintln!(
        "lang-scan: {} exception(s) open, {} inline marker(s) left",
        policy.exceptions.len(),
        markers
    );
    Ok(problems.is_empty() && stale.is_empty())
}

fn baseline(root: &Path) -> Result<(), String> {
    let policy = load_policy()?;
    let findings = scan(root, &policy)?;
    let mut out = serde_json::Map::new();
    for f in findings {
        let entry = match &f {
            Finding::Language { ext, .. } => serde_json::json!({ "language": ext }),
            Finding::Inline { count, .. } => serde_json::json!({ "language": "nix-inline", "markers": count }),
        };
        out.insert(f.path().to_string(), entry);
    }
    println!(
        "{}",
        serde_json::to_string_pretty(&Value::Object(out)).map_err(|e| e.to_string())?
    );
    Ok(())
}

fn git(args: &[&str]) -> Result<String, String> {
    let out = Command::new("git")
        .args(args)
        .output()
        .map_err(|e| format!("git {}: {e}", args.join(" ")))?;
    if !out.status.success() {
        return Err(format!("git {} failed", args.join(" ")));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn hook() -> Result<bool, String> {
    let root = PathBuf::from(git(&["rev-parse", "--show-toplevel"])?);
    let mut ok = check(&root)?;
    let staged = git(&["diff", "--cached", "--name-only", "--diff-filter=ACM"])?;
    let nix: Vec<&str> = staged.lines().filter(|p| p.ends_with(".nix")).collect();
    if !nix.is_empty() {
        let status = Command::new(NIXFMT)
            .arg("--check")
            .args(&nix)
            .current_dir(&root)
            .status()
            .map_err(|e| format!("nixfmt: {e}"))?;
        if !status.success() {
            eprintln!("lang-scan: staged Nix files are not formatted; run `nix fmt -- modules`");
            ok = false;
        }
    }
    Ok(ok)
}

fn install_hook() -> Result<(), String> {
    let hooks = PathBuf::from(git(&["rev-parse", "--git-path", "hooks"])?);
    fs::create_dir_all(&hooks).map_err(|e| e.to_string())?;
    let target = hooks.join("pre-commit");
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let _ = fs::remove_file(&target);
    std::os::unix::fs::symlink(&exe, &target).map_err(|e| format!("{}: {e}", target.display()))?;
    println!("lang-scan: {} -> {}", target.display(), exe.display());
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    let invoked = Path::new(&args[0])
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let result = if invoked == "pre-commit" {
        hook()
    } else {
        match (args.get(1).map(String::as_str), args.get(2)) {
            (Some("check"), Some(root)) => check(Path::new(root)),
            (Some("baseline"), Some(root)) => baseline(Path::new(root)).map(|_| true),
            (Some("install-hook"), None) => install_hook().map(|_| true),
            _ => Err("usage: lang-scan check <root> | baseline <root> | install-hook".into()),
        }
    };
    match result {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(e) => {
            eprintln!("lang-scan: {e}");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy(exceptions: &[(&str, Option<u64>)]) -> Policy {
        Policy {
            code: vec!["rs".into(), "lean".into(), "nix".into()],
            data: vec!["json".into()],
            names: vec![],
            skip: vec![],
            markers: vec!["writeShellApplication".into()],
            exceptions: exceptions.iter().map(|(p, m)| (p.to_string(), *m)).collect(),
        }
    }

    #[test]
    fn counts_markers() {
        let m = vec!["writeShellApplication".to_string(), "<script".to_string()];
        assert_eq!(inline_count("a writeShellApplication b <script c <script", &m), 3);
    }

    #[test]
    fn uncovered_file_is_a_problem() {
        let f = vec![Finding::Language { path: "a.py".into(), ext: "py".into() }];
        assert_eq!(judge(&f, &policy(&[])).0.len(), 1);
    }

    #[test]
    fn growth_past_the_exception_fails() {
        let f = vec![Finding::Inline { path: "m.nix".into(), count: 3 }];
        assert_eq!(judge(&f, &policy(&[("m.nix", Some(2))])).0.len(), 1);
        assert!(judge(&f, &policy(&[("m.nix", Some(3))])).0.is_empty());
    }

    #[test]
    fn exception_with_nothing_left_is_stale() {
        assert_eq!(judge(&[], &policy(&[("gone.py", None)])).1, vec!["gone.py".to_string()]);
    }
}
