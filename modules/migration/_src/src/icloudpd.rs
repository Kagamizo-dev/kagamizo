//! icloudpd (pinned; ../../../catalog/_json/icloudpd.json): its own sign-in and the photos export.
//!
//! catalog: icloudpd

use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{bail, Context, Result};
use migrate::{code, password, private, restore_dir, save_dir, var, write_manifest};
use serde_json::json;

use crate::detached;

// --- icloudpd ----------------------------------------------------------

const ICLOUDPD_SESSION: &str = "ICLOUDPD_SESSION";

/// `login icloudpd` (auth only) and `photos DIR`: one icloudpd run, its
/// cookies restored from Proton Pass first and kept after.
pub fn icloudpd(photos: Option<&Path>) -> Result<()> {
    let cookies = private()?.join("icloudpd-cookies");
    fs::create_dir_all(&cookies)?;
    restore_dir(ICLOUDPD_SESSION, &cookies)?;
    let mut cmd = Command::new("icloudpd");
    cmd.args(["--username", &var("MIGRATE_APPLE_ID")?])
        .arg("--cookie-directory")
        .arg(&cookies)
        .args(["--password-provider", "console", "--mfa-provider", "console"])
        .args(["--no-progress-bar", "--log-level", "info"]);
    match photos {
        None => {
            cmd.arg("--auth-only");
        }
        Some(dir) => {
            cmd.arg("--directory")
                .arg(dir)
                .args(["--size", "original", "--live-photo-size", "original"])
                .args(["--align-raw", "as-is", "--folder-structure", "{:%Y/%m}"])
                .args(["--file-match-policy", "name-id7", "--xmp-sidecar"])
                .args(["--keep-unicode-in-filenames", "--threads-num", "2"]);
        }
    }
    let mut child = detached(cmd)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .context("running icloudpd")?;
    let mut stdin = child.stdin.take().context("icloudpd stdin")?;
    {
        let pw = password()?;
        writeln!(stdin, "{}", pw.as_str())?;
    }
    // icloudpd asks for the code on stdout; the session relays it.
    let out = child.stdout.take().context("icloudpd stdout")?;
    let relay = std::thread::spawn(move || -> Result<()> {
        use std::io::BufRead;
        let mut asked = false;
        for line in std::io::BufReader::new(out).lines() {
            let line = line?;
            if line.contains("two-factor authentication code") && !asked {
                asked = true;
                let c = code()?;
                writeln!(stdin, "{}", c.as_str())?;
            } else if line.contains("Try again") || line.contains("Invalid") {
                bail!("icloudpd refused the relayed code: {line}");
            }
        }
        Ok(())
    });
    let status = child.wait()?;
    relay.join().map_err(|_| anyhow::anyhow!("relay thread"))??;
    if !status.success() {
        bail!("icloudpd failed ({status})");
    }
    save_dir(ICLOUDPD_SESSION, &cookies, "migrate: keep icloudpd's trusted session")?;
    if let Some(dir) = photos {
        let m = write_manifest(dir, "photos", &format!("icloudpd {}", var("MIGRATE_ICLOUDPD_VERSION")?), json!({}))?;
        eprintln!("migrate: photos: {} files, {} bytes, manifest written", m.count, m.bytes);
    }
    Ok(())
}

