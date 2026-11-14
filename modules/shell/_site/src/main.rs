//! shell-site: the shell as plain pages. It reads the declarations the
//! shell is built with and writes one HTML file per screen and one
//! stylesheet (./pages.rs), so a page is on the screen before any program
//! runs in the browser, has an address of its own, and reads as text.
//!
//!   shell-site DECLARED.json TARGET OUT_DIR
#[path = "../../_shell/src/model.rs"]
#[allow(dead_code)]
mod model;

mod a11y;
mod html;
mod pages;
mod style;

use std::path::Path;
use std::process::ExitCode;

fn run(args: &[String]) -> Result<usize, String> {
    let [declared, target, out] = args else {
        return Err("usage: shell-site DECLARED.json TARGET OUT_DIR".into());
    };
    let text = std::fs::read_to_string(declared).map_err(|e| format!("{declared}: {e}"))?;
    let declared: model::Declared = serde_json::from_str(&text).map_err(|e| format!("the declarations: {e}"))?;
    let files = pages::site(declared, target).map_err(|found| format!("{} accessibility problem(s), so nothing is written:\n  {}", found.len(), found.join("\n  ")))?;
    for (path, content) in &files {
        let to = Path::new(out).join(path);
        if let Some(dir) = to.parent() {
            std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        std::fs::write(&to, content).map_err(|e| format!("{}: {e}", to.display()))?;
    }
    Ok(files.len())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(n) => {
            println!("shell-site: {n} files");
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("shell-site: {e}");
            ExitCode::FAILURE
        }
    }
}
