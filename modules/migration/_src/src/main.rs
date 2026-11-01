//! `migrate`: the migration's Phase 3 runners (modules/migration), each a
//! pinned tool run with its session from Proton Pass and ending in a
//! manifest (every file's size and SHA-256) next to what it wrote. The
//! `migrate` wrapper (../export.nix) asks governance first and sets the
//! environment read here (MIGRATE_*).
//!
//!   migrate login icloudpd
//!       signs icloudpd in (its own session: it is pyicloud's fork, with
//!       its own cookie jar) with the Apple ID's password piped from Proton
//!       Pass; Apple's code is relayed by the session into the FIFO; the
//!       trusted cookies are kept in the owner's Sessions vault
//!   migrate login rclone
//!       the same for rclone's iclouddrive remote: its config (apple_id,
//!       the obscured password, the trust token and cookies Apple hands it)
//!       kept in the Sessions vault, never on disk outside the private dir
//!   migrate photos DIR      icloudpd: every original with its XMP sidecar
//!   migrate drive DIR       rclone copy of iCloud Drive, then rclone check
//!   migrate notes DIR       pyicloud: every note as HTML with attachments
//!   migrate reminders DIR   pyicloud: every list's reminders as JSON
//!   migrate verify DIR      every file in DIR's manifest is there, with its
//!                           size and hash, and nothing else is
//!
//! No secret is printed: the tools' own output is passed through on stderr
//! only where it carries none (icloudpd's log, rclone's stats).

mod icloudpd;
mod pyicloud;
mod rclone;

use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, Result};
use icloudpd::icloudpd;
use migrate::{verify, MANIFEST};
use pyicloud::pyicloud;
use rclone::{drive, rclone_login};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let usage = "usage: migrate login <icloudpd|rclone> | photos DIR | drive DIR | notes DIR | reminders DIR | verify DIR";
    match (args.first().map(String::as_str), args.get(1).map(String::as_str)) {
        (Some("login"), Some("icloudpd")) => icloudpd(None),
        (Some("login"), Some("rclone")) => rclone_login(),
        (Some("photos"), Some(dir)) => icloudpd(Some(&target(dir)?)),
        (Some("drive"), Some(dir)) => drive(&target(dir)?),
        (Some("notes"), Some(dir)) => pyicloud("notes", &target(dir)?),
        (Some("reminders"), Some(dir)) => pyicloud("reminders", &target(dir)?),
        (Some("verify"), Some(dir)) => {
            let problems = verify(Path::new(dir))?;
            for p in &problems {
                eprintln!("migrate: {p}");
            }
            if !problems.is_empty() {
                bail!("{} problem(s) in {dir}", problems.len());
            }
            eprintln!("migrate: {dir} matches its manifest");
            Ok(())
        }
        _ => bail!("{usage}"),
    }
}

/// An export's directory: made, and empty or already an export of ours.
fn target(dir: &str) -> Result<PathBuf> {
    let path = PathBuf::from(dir);
    fs::create_dir_all(&path)?;
    let entries = fs::read_dir(&path)?.count();
    if entries > 0 && !path.join(MANIFEST).exists() {
        bail!("{dir} is not empty and holds no manifest of ours");
    }
    Ok(path)
}

/// A child in a session of its own: no controlling terminal, so a password
/// prompt (getpass) falls back to the stdin it is given.
pub fn detached(mut cmd: Command) -> Command {
    // SAFETY: setsid only changes the child's session; nothing is shared.
    unsafe {
        cmd.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    cmd
}

