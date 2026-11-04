//! pyicloud (pinned; ../../../catalog/_json/pyicloud.json) through ../../_export.py: notes and reminders.

use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{bail, Context, Result};
use migrate::{password, private, restore_dir, save_dir, var, write_manifest};
use serde_json::Value;

// --- pyicloud ----------------------------------------------------------

/// `notes DIR` and `reminders DIR`: the pyicloud exporter (../_export.py),
/// with the session `icloud login` (modules/apple) keeps.
pub fn pyicloud(class: &str, dir: &Path) -> Result<()> {
    let cookies = private()?.join("pyicloud-cookies");
    fs::create_dir_all(&cookies)?;
    if !restore_dir("ICLOUD_SESSION", &cookies)? {
        bail!("no iCloud session in Proton Pass: nix run .#icloud -- login first");
    }
    let mut child = Command::new("python3")
        .args(["-I", &var("MIGRATE_EXPORT_PY")?, class, &var("MIGRATE_APPLE_ID")?])
        .arg(&cookies)
        .arg(dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .context("running the exporter")?;
    {
        let pw = password()?;
        writeln!(child.stdin.take().context("exporter stdin")?, "{}", pw.as_str())?;
    }
    let out = child.wait_with_output()?;
    if !out.status.success() {
        bail!("the {class} export failed");
    }
    let source: Value = serde_json::from_slice(&out.stdout).context("the exporter's counts are not JSON")?;
    save_dir("ICLOUD_SESSION", &cookies, "migrate: keep the iCloud session")?;
    let m = write_manifest(dir, class, &format!("pyicloud {}", var("MIGRATE_PYICLOUD_VERSION")?), source.clone())?;
    let expected = source["count"].as_u64().unwrap_or(0) as usize;
    if class == "reminders" && m.count != source["lists"].as_u64().unwrap_or(0) as usize {
        bail!("{} list files written for {} lists", m.count, source["lists"]);
    }
    if class == "notes" && expected == 0 {
        eprintln!("migrate: no notes found");
    }
    eprintln!("migrate: {class}: {} items, {} files, manifest written", expected, m.count);
    Ok(())
}
