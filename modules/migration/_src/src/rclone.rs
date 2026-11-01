//! rclone (pinned; ../../../catalog/_json/rclone.json): the iclouddrive remote's sign-in and the Drive copy.
//!
//! catalog: rclone

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{bail, Context, Result};
use migrate::{code, password, private, var, write_manifest};
use serde_json::{json, Value};
use zeroize::Zeroizing;

// --- rclone ------------------------------------------------------------

const RCLONE_CONFIG: &str = "RCLONE_ICLOUD_CONFIG";
const REMOTE: &str = "icloud";

/// The remote's config file in the private directory, from Proton Pass.
fn rclone_config(must_exist: bool) -> Result<PathBuf> {
    let file = private()?.join("rclone.conf");
    let stored = migrate::get(RCLONE_CONFIG, "migrate: restore rclone's iCloud remote")?;
    if stored.trim().is_empty() {
        if must_exist {
            bail!("rclone's iCloud remote is not signed in: migrate login rclone");
        }
    } else {
        fs::write(&file, stored.as_bytes())?;
    }
    Ok(file)
}

fn rclone(config: &Path) -> Command {
    let mut cmd = Command::new("rclone");
    cmd.arg("--config").arg(config).stdin(Stdio::null());
    cmd
}

/// `login rclone`: the remote made with `rclone config create` in its
/// non-interactive protocol (its questions come back as JSON; the one for
/// Apple's code is answered from the FIFO, any other refused), its config
/// then kept in Proton Pass.
pub fn rclone_login() -> Result<()> {
    let config = rclone_config(false)?;
    let obscured = {
        let pw = password()?;
        let mut child = Command::new("rclone")
            .args(["obscure", "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .context("running rclone obscure")?;
        writeln!(child.stdin.take().context("obscure stdin")?, "{}", pw.as_str())?;
        let out = child.wait_with_output()?;
        if !out.status.success() {
            bail!("rclone obscure failed");
        }
        Zeroizing::new(String::from_utf8(out.stdout)?.trim().to_owned())
    };
    let apple_id = var("MIGRATE_APPLE_ID")?;
    let mut answer: Option<(String, Zeroizing<String>)> = None;
    loop {
        let mut cmd = rclone(&config);
        cmd.args(["config", "create", REMOTE, "iclouddrive", "--non-interactive", "--no-obscure"])
            .arg(format!("apple_id={apple_id}"))
            .arg(format!("password={}", obscured.as_str()))
            .arg("service=drive");
        if let Some((state, result)) = &answer {
            cmd.args(["--continue", "--state", state, "--result", result.as_str()]);
        }
        let out = cmd.stdout(Stdio::piped()).stderr(Stdio::inherit()).output().context("running rclone config create")?;
        if !out.status.success() {
            bail!("rclone config create failed");
        }
        let reply: Value = serde_json::from_slice(&out.stdout).context("rclone's reply is not JSON")?;
        let error = reply["Error"].as_str().unwrap_or("");
        if !error.is_empty() {
            bail!("rclone: {error}");
        }
        let state = reply["State"].as_str().unwrap_or("").to_owned();
        if state.is_empty() {
            break;
        }
        let name = reply["Option"]["Name"].as_str().unwrap_or("").to_owned();
        let help = reply["Option"]["Help"].as_str().unwrap_or("").to_lowercase();
        if name.contains("2fa") || help.contains("2fa") || help.contains("two-factor") {
            eprintln!("migrate: rclone asks `{name}`");
            answer = Some((state, code()?));
        } else {
            bail!("rclone asks `{name}` (state {state}), which is not mapped: refused rather than guessed");
        }
    }
    let text = Zeroizing::new(fs::read(&config)?);
    migrate::set(RCLONE_CONFIG, &text, "migrate: keep rclone's iCloud remote")?;
    eprintln!("migrate: rclone's iCloud remote is signed in");
    Ok(())
}

/// `drive DIR`: iCloud Drive copied whole, checked against the source, then
/// the manifest.
pub fn drive(dir: &Path) -> Result<()> {
    let config = rclone_config(true)?;
    let source = format!("{REMOTE}:");
    let status = rclone(&config)
        .args(["copy", &source])
        .arg(dir)
        .args(["--checksum", "--transfers", "4", "--stats-one-line", "--stats", "1m"])
        .stderr(Stdio::inherit())
        .status()
        .context("running rclone copy")?;
    if !status.success() {
        bail!("rclone copy failed ({status})");
    }
    let status = rclone(&config)
        .args(["check", &source])
        .arg(dir)
        .args(["--one-way"])
        .stderr(Stdio::inherit())
        .status()
        .context("running rclone check")?;
    if !status.success() {
        bail!("rclone check found differences ({status})");
    }
    let listing = rclone(&config)
        .args(["lsjson", "--recursive", "--files-only", &source])
        .stderr(Stdio::inherit())
        .output()
        .context("running rclone lsjson")?;
    if !listing.status.success() {
        bail!("rclone lsjson failed");
    }
    let objects: Vec<Value> = serde_json::from_slice(&listing.stdout)?;
    let bytes: u64 = objects.iter().filter_map(|o| o["Size"].as_u64()).sum();
    let m = write_manifest(dir, "files", &format!("rclone {}", var("MIGRATE_RCLONE_VERSION")?), json!({"objects": objects.len(), "bytes": bytes}))?;
    if m.count != objects.len() || m.bytes != bytes {
        bail!("the copy has {} files / {} bytes, the source {} / {}", m.count, m.bytes, objects.len(), bytes);
    }
    eprintln!("migrate: drive: {} files, {} bytes, checked and manifest written", m.count, m.bytes);
    Ok(())
}

