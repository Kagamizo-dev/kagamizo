//! The state as generations of Proton Pass note items, written by the
//! protocol `../_lean/Store.lean` proves safe:
//!
//!   1. create every chunk of the new generation (`<name>@<g>#<i>`),
//!   2. create its manifest (`<name>@<g>`),
//!   3. delete every other generation's manifest,
//!   4. delete their chunks.
//!
//! A read takes the newest complete generation whose joined chunks match
//! the manifest's SHA-256. Proton Pass is only ever asked to create, view,
//! list and delete items: the pinned pass-cli's own commands
//! (modules/catalog/_json/pass-cli.json).

use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::io::Write;
use std::process::{Command, Stdio};

/// One backend: a vault, the title every item starts with, and the
/// largest chunk (in bytes) a note may hold.
pub struct Store {
    pub vault: String,
    pub name: String,
    pub chunk_size: usize,
}

#[derive(Deserialize)]
struct Listed {
    id: String,
    share_id: String,
    title: Option<String>,
}

#[derive(Deserialize)]
struct Listing {
    items: Vec<Listed>,
}

#[derive(Serialize, Deserialize, PartialEq, Debug)]
pub struct Manifest {
    pub generation: u64,
    pub count: usize,
    pub bytes: usize,
    pub sha256: String,
}

/// What a listing says of one item of this backend.
#[derive(PartialEq, Debug)]
enum Kind {
    Manifest(u64),
    Chunk(u64, usize),
    Lock,
}

fn pass_cli(args: &[&str], stdin: Option<&str>) -> Result<String> {
    let mut child = Command::new("pass-cli")
        .args(args)
        .stdin(if stdin.is_some() { Stdio::piped() } else { Stdio::null() })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("running pass-cli")?;
    if let Some(input) = stdin {
        child
            .stdin
            .take()
            .ok_or_else(|| anyhow!("pass-cli stdin"))?
            .write_all(input.as_bytes())?;
    }
    let out = child.wait_with_output()?;
    if !out.status.success() {
        // pass-cli's own message; it never carries a value.
        let msg = String::from_utf8_lossy(&out.stderr);
        bail!("pass-cli {}: {}", args[..2.min(args.len())].join(" "), msg.lines().next().unwrap_or(""));
    }
    Ok(String::from_utf8(out.stdout)?)
}

pub fn sha256_hex(data: &[u8]) -> String {
    Sha256::digest(data).iter().map(|b| format!("{b:02x}")).collect()
}

/// Split on character boundaries into pieces of at most `size` bytes
/// (`chunk` and `chunk_join` in Store.lean).
pub fn chunks(value: &str, size: usize) -> Vec<&str> {
    let mut out = Vec::new();
    let mut rest = value;
    while !rest.is_empty() {
        let mut end = size.min(rest.len());
        while !rest.is_char_boundary(end) {
            end -= 1;
        }
        let (head, tail) = rest.split_at(end);
        out.push(head);
        rest = tail;
    }
    out
}

impl Store {
    fn classify(&self, title: &str) -> Option<Kind> {
        if title == format!("{}.lock", self.name) {
            return Some(Kind::Lock);
        }
        let rest = title.strip_prefix(&self.name)?.strip_prefix('@')?;
        match rest.split_once('#') {
            None => rest.parse().ok().map(Kind::Manifest),
            Some((g, i)) => Some(Kind::Chunk(g.parse().ok()?, i.parse().ok()?)),
        }
    }

    fn list(&self) -> Result<Vec<(Kind, Listed)>> {
        let out = pass_cli(&["item", "list", &self.vault, "--output", "json"], None)?;
        let listing: Listing = serde_json::from_str(&out).context("pass-cli item list: not JSON")?;
        Ok(listing
            .items
            .into_iter()
            .filter_map(|i| Some((self.classify(i.title.as_deref()?)?, i)))
            .collect())
    }

    fn view(&self, title: &str) -> Result<String> {
        let out = pass_cli(
            &["item", "view", "--vault-name", &self.vault, "--item-title", title, "--output", "json"],
            None,
        )?;
        let v: serde_json::Value = serde_json::from_str(&out)?;
        v.pointer("/item/content/note")
            .and_then(|n| n.as_str())
            .map(str::to_owned)
            .ok_or_else(|| anyhow!("{title}: not a note"))
    }

    fn create(&self, title: &str, note: &str) -> Result<()> {
        let template = serde_json::json!({ "title": title, "note": note }).to_string();
        pass_cli(
            &["item", "create", "note", "--vault-name", &self.vault, "--from-template", "-"],
            Some(&template),
        )
        .with_context(|| format!("creating {title} ({} bytes)", note.len()))?;
        Ok(())
    }

    fn delete(&self, item: &Listed) -> Result<()> {
        // Ids are URL-safe base64 and may start with '-'.
        let share = format!("--share-id={}", item.share_id);
        let id = format!("--item-id={}", item.id);
        pass_cli(&["item", "delete", &share, &id], None)?;
        Ok(())
    }

    /// The newest complete, verified generation's value, or None.
    pub fn read(&self) -> Result<Option<(Manifest, String)>> {
        let items = self.list()?;
        let mut gens: BTreeMap<u64, (bool, usize)> = BTreeMap::new();
        for (k, _) in &items {
            match k {
                Kind::Manifest(g) => gens.entry(*g).or_default().0 = true,
                Kind::Chunk(g, _) => gens.entry(*g).or_default().1 += 1,
                Kind::Lock => {}
            }
        }
        for (&g, &(manifest, present)) in gens.iter().rev() {
            if !manifest {
                continue;
            }
            let m: Manifest = serde_json::from_str(&self.view(&format!("{}@{g}", self.name))?)?;
            if m.generation != g || present != m.count {
                continue;
            }
            let mut value = String::with_capacity(m.bytes);
            for i in 0..m.count {
                value.push_str(&self.view(&format!("{}@{g}#{i}", self.name))?);
            }
            if value.len() == m.bytes && sha256_hex(value.as_bytes()) == m.sha256 {
                return Ok(Some((m, value)));
            }
            eprintln!("statestore: generation {g} does not match its manifest; trying older");
        }
        Ok(None)
    }

    /// Write `value` as a new generation, then remove every other one.
    pub fn write(&self, value: &str) -> Result<Manifest> {
        let items = self.list()?;
        let next = items
            .iter()
            .filter_map(|(k, _)| match k {
                Kind::Manifest(g) | Kind::Chunk(g, _) => Some(*g),
                Kind::Lock => None,
            })
            .max()
            .map_or(1, |g| g + 1);
        let parts = chunks(value, self.chunk_size);
        for (i, part) in parts.iter().enumerate() {
            self.create(&format!("{}@{next}#{i}", self.name), part)?;
        }
        let m = Manifest {
            generation: next,
            count: parts.len(),
            bytes: value.len(),
            sha256: sha256_hex(value.as_bytes()),
        };
        self.create(&format!("{}@{next}", self.name), &serde_json::to_string(&m)?)?;
        // Read back before anything old goes: the new generation must verify.
        match self.read()? {
            Some((got, _)) if got == m => {}
            _ => bail!("generation {next} does not read back; the previous one is kept"),
        }
        let old = |k: &Kind| matches!(k, Kind::Manifest(g) | Kind::Chunk(g, _) if *g != next);
        for (k, item) in items.iter().filter(|(k, _)| matches!(k, Kind::Manifest(_)) && old(k)) {
            self.delete(item).with_context(|| format!("deleting {k:?}"))?;
        }
        for (k, item) in items.iter().filter(|(k, _)| matches!(k, Kind::Chunk(..)) && old(k)) {
            self.delete(item).with_context(|| format!("deleting {k:?}"))?;
        }
        Ok(m)
    }

    /// Take the lock: create the lock item only when none exists. On a held
    /// lock, its info (OpenTofu's lock JSON) comes back as the error.
    pub fn lock(&self, info: &str) -> Result<std::result::Result<(), String>> {
        let title = format!("{}.lock", self.name);
        if self.list()?.iter().any(|(k, _)| *k == Kind::Lock) {
            return Ok(Err(self.view(&title).unwrap_or_default()));
        }
        self.create(&title, info)?;
        Ok(Ok(()))
    }

    pub fn unlock(&self) -> Result<()> {
        for (_, item) in self.list()?.iter().filter(|(k, _)| *k == Kind::Lock) {
            self.delete(item)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunks_join_back_and_fit() {
        for size in [1, 3, 7, 8000] {
            for v in ["", "a", "état {\"x\":1}", &"z".repeat(20001)] {
                let c = chunks(v, size.max(4));
                assert_eq!(c.concat(), v);
                assert!(c.iter().all(|p| p.len() <= size.max(4)));
            }
        }
    }

    #[test]
    fn titles_classify() {
        let s = Store { vault: "V".into(), name: "cf".into(), chunk_size: 10 };
        assert_eq!(s.classify("cf@3"), Some(Kind::Manifest(3)));
        assert_eq!(s.classify("cf@3#0"), Some(Kind::Chunk(3, 0)));
        assert_eq!(s.classify("cf.lock"), Some(Kind::Lock));
        assert_eq!(s.classify("cf-other@3"), None);
        assert_eq!(s.classify("tofu-state"), None);
    }
}
