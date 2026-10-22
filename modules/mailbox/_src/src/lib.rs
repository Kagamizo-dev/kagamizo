//! What the keychain stand-in (`pass`, src/bin/mailbox-keychain.rs) and the
//! driver (`mailbox`, src/main.rs) share: where Bridge's keychain keeps its
//! entries, and secretspec run as the caller.

use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{bail, Context, Result};
use base64::engine::general_purpose::URL_SAFE;
use base64::Engine;
use zeroize::Zeroizing;

const FOLDER: &str = "docker-credential-helpers";

/// The XDG folders Bridge is given privately and secretspec needs as the
/// caller's.
pub const XDG: [&str; 4] = [
    "XDG_CONFIG_HOME",
    "XDG_DATA_HOME",
    "XDG_CACHE_HOME",
    "XDG_STATE_HOME",
];

/// Where Docker's pass helper keeps a server URL's entry: its folder, and
/// the folder plus its one username.
pub fn entry(url: &str, user: &str) -> (String, String) {
    let dir = format!("{FOLDER}/{}", URL_SAFE.encode(url));
    (dir.clone(), format!("{dir}/{user}"))
}

/// Bridge's vault key (keychain "bridge-v3", secret "bridge-vault-key").
pub fn vault_key() -> (String, String) {
    entry(
        "protonmail/bridge-v3/users/bridge-vault-key",
        "bridge-vault-key",
    )
}

/// The entry Bridge's keychain test writes, reads and deletes on Linux.
pub fn check() -> (String, String) {
    entry("bridge/check", "check")
}

/// The empty file that tells the helper an entry exists.
pub fn marker(store: &Path, entry: &str) -> Result<()> {
    let file = store.join(format!("{entry}.gpg"));
    std::fs::create_dir_all(file.parent().context("entry path")?)?;
    std::fs::write(file, b"")?;
    Ok(())
}

fn var(name: &str) -> Result<String> {
    std::env::var(name).with_context(|| format!("{name} is not set"))
}

/// `secretspec get NAME`, empty when nothing is stored yet.
pub fn get(name: &str, reason: &str) -> Result<Zeroizing<String>> {
    match run(&["get", name, "--reason", reason]) {
        Ok(v) => Ok(v),
        Err(_) => Ok(Zeroizing::new(String::new())),
    }
}

/// `secretspec set NAME`, the value through a file in the private directory.
pub fn set(name: &str, value: &str, reason: &str) -> Result<()> {
    let staged = Path::new(&var("MAILBOX_PRIVATE")?).join(format!("{name}.staged"));
    std::fs::write(&staged, value.as_bytes())?;
    let path = staged.to_str().context("private path")?.to_owned();
    let result = run(&["set", name, "--from-file", &path, "--reason", reason]);
    std::fs::remove_file(&staged).ok();
    result.map(|_| ())
}

/// secretspec as the caller, whose HOME holds the Proton Pass session; the
/// driver runs Bridge, and so this, under a private HOME.
fn run(args: &[&str]) -> Result<Zeroizing<String>> {
    let mut cmd = Command::new("secretspec");
    cmd.args(args)
        .args([
            "--file",
            &var("MAILBOX_SECRETSPEC_FILE")?,
            "--profile",
            &var("MAILBOX_PROFILE")?,
        ])
        .env("HOME", var("MAILBOX_CALLER_HOME")?)
        .stdin(Stdio::null())
        .stderr(Stdio::null());
    // pass-cli keeps its session under the caller's XDG data folder, so
    // every XDG folder is the caller's, not Bridge's private one.
    for name in XDG {
        match std::env::var(format!("MAILBOX_CALLER_{name}")) {
            Ok(v) if !v.is_empty() => cmd.env(name, v),
            _ => cmd.env_remove(name),
        };
    }
    let out = cmd.output().context("running secretspec")?;
    let text = Zeroizing::new(String::from_utf8(out.stdout).context("secretspec output is not UTF-8")?);
    if !out.status.success() {
        bail!("secretspec {} {} failed", args[0], args[1]);
    }
    Ok(text)
}
