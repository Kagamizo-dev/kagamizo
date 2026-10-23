//! The engine as a WebAuthn authenticator: a virtual one in Chromium (the
//! DevTools Protocol's WebAuthn domain) that holds the account's passkey.
//! The credential, private key included, moves only between Chromium and
//! Proton Pass (through secretspec), never through the terminal.

use std::path::Path;

use anyhow::{bail, Context, Result};
use chromiumoxide::Page;
use serde_json::{json, Value};
use tokio::process::Command;
use zeroize::Zeroizing;

use crate::flow::{Login, PasskeySource, PasskeyStore};
use crate::Raw;

pub struct Authenticator {
    id: String,
}

/// A platform authenticator with resident keys and user verification, as a
/// phone's or a laptop's is; it answers every request without a prompt.
pub async fn start(page: &Page, store: &PasskeyStore, login: &Login) -> Result<Authenticator> {
    page.execute(Raw::new("WebAuthn.enable", json!({ "enableUI": false })))
        .await?;
    let added = page
        .execute(Raw::new(
            "WebAuthn.addVirtualAuthenticator",
            json!({ "options": {
                "protocol": "ctap2",
                "ctap2Version": "ctap2_1",
                "transport": "internal",
                "hasResidentKey": true,
                "hasUserVerification": true,
                "isUserVerified": true,
                "automaticPresenceSimulation": true,
            }}),
        ))
        .await?;
    let id = added.result["authenticatorId"]
        .as_str()
        .context("no authenticator id")?
        .to_owned();
    let credentials: Vec<Value> = match store.source {
        PasskeySource::Engine => match get(store).await? {
            Some(stored) => serde_json::from_str(&stored)
                .context("the stored passkey is not a credential list")?,
            None => vec![],
        },
        // Every passkey the login item holds for the site; the site's own
        // request picks the one it knows.
        PasskeySource::LoginItem => {
            let mut found = vec![];
            for content in crate::pass::passkeys(login, &store.rp_id).await? {
                let (_, credential) = crate::proton_passkey::credential(&content)
                    .context("the login item's passkey")?;
                found.push(credential);
            }
            if found.is_empty() {
                bail!("the login item has no passkey for {}", store.rp_id);
            }
            found
        }
    };
    for credential in credentials
        .into_iter()
        .filter(|c| c["rpId"] == store.rp_id.as_str())
    {
        page.execute(Raw::new(
            "WebAuthn.addCredential",
            json!({ "authenticatorId": id, "credential": credential }),
        ))
        .await?;
    }
    Ok(Authenticator { id })
}

/// The credentials the site registered, into Proton Pass.
pub async fn save(page: &Page, auth: &Authenticator, store: &PasskeyStore) -> Result<()> {
    let found = page
        .execute(Raw::new(
            "WebAuthn.getCredentials",
            json!({ "authenticatorId": auth.id }),
        ))
        .await?;
    let ours: Vec<&Value> = found.result["credentials"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|c| c["rpId"] == store.rp_id.as_str())
        .collect();
    if ours.is_empty() {
        bail!("{} registered no passkey", store.rp_id);
    }
    let text = Zeroizing::new(serde_json::to_string(&ours)?);
    let dir = std::env::var("BROWSER_PROFILE").context("BROWSER_PROFILE is not set")?;
    let file = Path::new(&dir).join("passkey.json");
    std::fs::write(&file, text.as_bytes())?;
    let result = secretspec(&[
        "set",
        "PASSKEY",
        "--profile",
        &store.profile,
        "--from-file",
        file.to_str().context("profile path")?,
        "--reason",
        "browser: keep the passkey just registered",
    ])
    .await;
    std::fs::remove_file(&file).ok();
    result.map(|_| ())
}

async fn get(store: &PasskeyStore) -> Result<Option<Zeroizing<String>>> {
    match secretspec(&[
        "get",
        "PASSKEY",
        "--profile",
        &store.profile,
        "--reason",
        "browser: sign in with the account's passkey",
    ])
    .await
    {
        Ok(v) if !v.trim().is_empty() => Ok(Some(v)),
        _ => {
            eprintln!("browser: no passkey stored for {} yet", store.rp_id);
            Ok(None)
        }
    }
}

async fn secretspec(args: &[&str]) -> Result<Zeroizing<String>> {
    let file =
        std::env::var("BROWSER_SECRETSPEC_FILE").context("BROWSER_SECRETSPEC_FILE is not set")?;
    let out = Command::new("secretspec")
        .args(args)
        .args(["--file", &file])
        .stderr(std::process::Stdio::null())
        .output()
        .await
        .context("running secretspec")?;
    let text =
        Zeroizing::new(String::from_utf8(out.stdout).context("secretspec output is not UTF-8")?);
    if !out.status.success() {
        bail!("secretspec {} failed", args[0]);
    }
    Ok(text)
}
