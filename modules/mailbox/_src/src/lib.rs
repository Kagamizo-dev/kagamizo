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

/// `secretspec get NAME`, empty when nothing is stored yet; any other
/// failure (no Proton Pass session, say) is an error, never "nothing".
pub fn get(name: &str, reason: &str) -> Result<Zeroizing<String>> {
    let (ok, out, err) = output(&["get", name, "--reason", reason])?;
    if ok {
        return Ok(out);
    }
    if err.contains("not found") {
        return Ok(Zeroizing::new(String::new()));
    }
    bail!("secretspec get {name} failed")
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

/// The declared environment's variable names (runtime.caller, PATH and the
/// host's pass-through ones), as modules/_lib/frozen.nix sets FROZEN_VARS.
pub fn frozen_vars() -> Result<Vec<String>> {
    Ok(var("FROZEN_VARS")?.split_whitespace().map(str::to_owned).collect())
}

/// secretspec in the caller's declared environment, where pass-cli finds its
/// session. The driver runs in it already; under Bridge (the keychain
/// stand-in) the environment is Bridge's, and the caller's comes as
/// MAILBOX_CALLER_<NAME>, so it is set from those and nothing else.
fn command(args: &[&str]) -> Result<Command> {
    let mut cmd = Command::new("secretspec");
    if std::env::var_os("MAILBOX_UNDER_BRIDGE").is_some() {
        cmd.env_clear();
        for name in var("MAILBOX_CALLER_VARS")?.split_whitespace() {
            if let Ok(v) = std::env::var(format!("MAILBOX_CALLER_{name}")) {
                cmd.env(name, v);
            }
        }
    }
    cmd.args(args)
        .args([
            "--file",
            &var("MAILBOX_SECRETSPEC_FILE")?,
            "--profile",
            &var("MAILBOX_PROFILE")?,
        ])
        .stdin(Stdio::null())
        .stderr(Stdio::piped());
    Ok(cmd)
}

fn run(args: &[&str]) -> Result<Zeroizing<String>> {
    let (ok, out, _) = output(args)?;
    if !ok {
        bail!("secretspec {} {} failed", args[0], args[1]);
    }
    Ok(out)
}

/// Whether it succeeded, its stdout, and its stderr (messages, no values).
fn output(args: &[&str]) -> Result<(bool, Zeroizing<String>, String)> {
    let out = command(args)?.output().context("running secretspec")?;
    let text = Zeroizing::new(String::from_utf8(out.stdout).context("secretspec output is not UTF-8")?);
    Ok((out.status.success(), text, String::from_utf8_lossy(&out.stderr).into_owned()))
}
