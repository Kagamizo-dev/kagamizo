//! lean-check: the builder of every Lean proof check, with no shell in it.
//!
//! A check is a Lean source file (types, predicates, lemmas) and the facts
//! its module renders from the declarations (definitions and the theorems
//! over them, decided by the kernel). This builder joins the two into
//! Check.lean, runs Lean on it, and creates $out only if every proof
//! holds, so the derivation exists exactly when the theorems do.
//!
//!   lean-check <lean> <source.lean>     facts from $factsPath (passAsFile)

use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitCode};

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().collect();
    let (lean, source) = match (args.get(1), args.get(2)) {
        (Some(l), Some(s)) => (l, s),
        _ => return Err("usage: lean-check <lean> <source.lean> (facts in $factsPath)".into()),
    };
    let facts_path = std::env::var("factsPath").map_err(|_| "factsPath is not set")?;
    let out = std::env::var("out").map_err(|_| "out is not set")?;
    let dir = std::env::var("NIX_BUILD_TOP")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());

    let mut text = fs::read_to_string(source).map_err(|e| format!("{source}: {e}"))?;
    if !text.ends_with('\n') {
        text.push('\n');
    }
    text.push_str(&fs::read_to_string(&facts_path).map_err(|e| format!("facts: {e}"))?);
    let check = dir.join("Check.lean");
    fs::write(&check, text).map_err(|e| format!("{}: {e}", check.display()))?;

    let status = Command::new(lean)
        .arg(&check)
        .current_dir(&dir)
        .status()
        .map_err(|e| format!("{lean}: {e}"))?;
    if !status.success() {
        return Err("a proof does not hold (Lean's errors above)".into());
    }
    fs::write(&out, "").map_err(|e| format!("{out}: {e}"))
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("lean-check: {e}");
            ExitCode::FAILURE
        }
    }
}
