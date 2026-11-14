//! What the migration's exporter shares across its commands: the declared
//! environment it runs in, Proton Pass through secretspec (sessions in, and
//! back out, never printed), the owner's Apple password piped from pass-cli,
//! the owner's 2FA code relayed through a FIFO, and the manifest every
//! export ends with (every file's size and SHA-256), which `migrate verify`
//! checks a copy against.

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{bail, Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

pub fn var(name: &str) -> Result<String> {
    std::env::var(name).with_context(|| format!("{name} is not set"))
}

/// The private working directory the wrapper made (mode 700, removed after).
pub fn private() -> Result<PathBuf> {
    Ok(PathBuf::from(var("MIGRATE_PRIVATE")?))
}

fn secretspec(args: &[&str]) -> Result<Command> {
    let mut cmd = Command::new("secretspec");
    cmd.args(args)
        .args([
            "--file",
            &var("MIGRATE_SECRETSPEC_FILE")?,
            "--profile",
            &var("MIGRATE_PROFILE")?,
        ])
        .stdin(Stdio::null())
        .stderr(Stdio::piped());
    Ok(cmd)
}

/// `secretspec get NAME`: empty when nothing is stored yet; any other
/// failure (no Proton Pass session) is an error, never "nothing".
pub fn get(name: &str, reason: &str) -> Result<Zeroizing<String>> {
    let out = secretspec(&["get", name, "--reason", reason])?
        .output()
        .context("running secretspec")?;
    let text = Zeroizing::new(String::from_utf8(out.stdout).context("secretspec output is not UTF-8")?);
    if out.status.success() {
        return Ok(text);
    }
    if String::from_utf8_lossy(&out.stderr).contains("not found") {
        return Ok(Zeroizing::new(String::new()));
    }
    bail!("secretspec get {name} failed")
}

/// `secretspec set NAME`, the value through a file in the private directory.
pub fn set(name: &str, value: &[u8], reason: &str) -> Result<()> {
    let staged = private()?.join(format!("{name}.staged"));
    fs::write(&staged, value)?;
    let path = staged.to_str().context("private path")?.to_owned();
    let status = secretspec(&["set", name, "--from-file", &path, "--reason", reason])?
        .status()
        .context("running secretspec")?;
    fs::remove_file(&staged).ok();
    if !status.success() {
        bail!("secretspec set {name} failed");
    }
    eprintln!("migrate: {name} kept in Proton Pass");
    Ok(())
}

/// A directory kept in Proton Pass as a base64 tarball (a tool's session
/// cookies): restored into `dir` when one is stored.
pub fn restore_dir(name: &str, dir: &Path) -> Result<bool> {
    let stored = get(name, &format!("migrate: restore {name}"))?;
    if stored.trim().is_empty() {
        return Ok(false);
    }
    let bytes = Zeroizing::new(STANDARD.decode(stored.trim()).context("stored session is not base64")?);
    fs::create_dir_all(dir)?;
    let mut tar = Command::new("tar")
        .args(["-xz", "-C"])
        .arg(dir)
        .stdin(Stdio::piped())
        .spawn()
        .context("running tar")?;
    tar.stdin.take().context("tar stdin")?.write_all(&bytes)?;
    if !tar.wait()?.success() {
        bail!("restoring {name} failed");
    }
    Ok(true)
}

pub fn save_dir(name: &str, dir: &Path, reason: &str) -> Result<()> {
    let out = Command::new("tar")
        .args(["-cz", "-C"])
        .arg(dir)
        .arg(".")
        .output()
        .context("running tar")?;
    if !out.status.success() {
        bail!("packing {name} failed");
    }
    set(name, STANDARD.encode(out.stdout).as_bytes(), reason)
}

/// The Apple ID's password, from its Login item: piped on, never printed.
pub fn password() -> Result<Zeroizing<String>> {
    let out = Command::new("pass-cli")
        .args([
            "item",
            "view",
            "--vault-name",
            &var("MIGRATE_LOGIN_VAULT")?,
            "--item-title",
            &var("MIGRATE_LOGIN_ITEM")?,
            "--field",
            "password",
        ])
        .stdin(Stdio::null())
        .stderr(Stdio::inherit())
        .output()
        .context("running pass-cli")?;
    if !out.status.success() {
        bail!("pass-cli could not read the login item's password");
    }
    let mut text = Zeroizing::new(String::from_utf8(out.stdout).context("password is not UTF-8")?);
    while text.ends_with('\n') || text.ends_with('\r') {
        text.pop();
    }
    Ok(text)
}

/// Apple's code, read off the owner's device and relayed by the session into
/// the FIFO named by the wrapper (made here; removed after one read).
pub fn code() -> Result<Zeroizing<String>> {
    let fifo = var("MIGRATE_CODE_FIFO")?;
    fs::remove_file(&fifo).ok();
    let status = Command::new("mkfifo").args(["-m", "600", &fifo]).status()?;
    if !status.success() {
        bail!("mkfifo {fifo} failed");
    }
    eprintln!("migrate: Apple sent a code to the owner's trusted devices; it goes into {fifo}");
    let mut line = Zeroizing::new(String::new());
    BufReader::new(fs::File::open(&fifo)?).read_line(&mut line)?;
    fs::remove_file(&fifo).ok();
    let trimmed = line.trim();
    if trimmed.is_empty() || !trimmed.chars().all(|c| c.is_ascii_digit()) {
        bail!("the relayed code is not a number");
    }
    Ok(Zeroizing::new(trimmed.to_owned()))
}

// --- manifests --------------------------------------------------------------

#[derive(Serialize, Deserialize)]
pub struct Entry {
    pub path: String,
    pub bytes: u64,
    pub sha256: String,
}

/// What an export ends with, next to its files as manifest.json.
#[derive(Serialize, Deserialize)]
pub struct Manifest {
    pub class: String,
    pub tool: String,
    pub source: serde_json::Value,
    pub count: usize,
    pub bytes: u64,
    pub files: Vec<Entry>,
}

pub const MANIFEST: &str = "manifest.json";

pub fn sha256_of(path: &Path) -> Result<(u64, String)> {
    let mut file = fs::File::open(path).with_context(|| format!("opening {}", path.display()))?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    let mut total = 0u64;
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        total += n as u64;
    }
    Ok((total, format!("{:x}", hasher.finalize())))
}

fn walk(root: &Path, dir: &Path, found: &mut Vec<Entry>) -> Result<()> {
    let mut names: Vec<_> = fs::read_dir(dir)?.collect::<std::io::Result<_>>()?;
    names.sort_by_key(|e| e.file_name());
    for entry in names {
        let path = entry.path();
        let kind = entry.file_type()?;
        if kind.is_dir() {
            walk(root, &path, found)?;
        } else if kind.is_file() {
            let rel = path.strip_prefix(root)?.to_string_lossy().into_owned();
            if rel == MANIFEST {
                continue;
            }
            let (bytes, sha256) = sha256_of(&path)?;
            found.push(Entry { path: rel, bytes, sha256 });
        }
    }
    Ok(())
}

/// Hash every file under `dir` and write the manifest beside them.
pub fn write_manifest(dir: &Path, class: &str, tool: &str, source: serde_json::Value) -> Result<Manifest> {
    let mut files = Vec::new();
    walk(dir, dir, &mut files)?;
    let manifest = Manifest {
        class: class.to_owned(),
        tool: tool.to_owned(),
        source,
        count: files.len(),
        bytes: files.iter().map(|f| f.bytes).sum(),
        files,
    };
    fs::write(dir.join(MANIFEST), serde_json::to_vec_pretty(&manifest)?)?;
    Ok(manifest)
}

/// Every file in the manifest is there with its size and hash, and nothing
/// else is: the problems found, empty when the copy is whole.
pub fn verify(dir: &Path) -> Result<Vec<String>> {
    let manifest: Manifest = serde_json::from_slice(&fs::read(dir.join(MANIFEST)).context("no manifest.json")?)?;
    let mut problems = Vec::new();
    let mut present = Vec::new();
    walk(dir, dir, &mut present)?;
    let expected: std::collections::BTreeMap<_, _> = manifest.files.iter().map(|f| (f.path.as_str(), f)).collect();
    for have in &present {
        match expected.get(have.path.as_str()) {
            None => problems.push(format!("{}: not in the manifest", have.path)),
            Some(want) if want.sha256 != have.sha256 || want.bytes != have.bytes => {
                problems.push(format!("{}: differs from the manifest", have.path))
            }
            Some(_) => {}
        }
    }
    let have: std::collections::BTreeSet<_> = present.iter().map(|f| f.path.as_str()).collect();
    for want in expected.keys() {
        if !have.contains(want) {
            problems.push(format!("{want}: missing"));
        }
    }
    if manifest.count != manifest.files.len() {
        problems.push("manifest count does not match its own list".to_owned());
    }
    Ok(problems)
}
