//! Values from the account's login item in Proton Pass, through pass-cli.
//! They live only in memory, zeroed on drop, and are never printed: an
//! error names the field, never its value.

use anyhow::{bail, Context, Result};
use tokio::process::Command;
use zeroize::Zeroizing;

use crate::flow::{Login, PassField};

async fn pass_cli(args: &[&str]) -> Result<Zeroizing<String>> {
    let out = Command::new("pass-cli")
        .args(args)
        .stderr(std::process::Stdio::null())
        .output()
        .await
        .context("running pass-cli")?;
    let text =
        Zeroizing::new(String::from_utf8(out.stdout).context("pass-cli output is not UTF-8")?);
    if !out.status.success() {
        bail!(
            "pass-cli {} failed",
            args.first().copied().unwrap_or_default()
        );
    }
    Ok(text)
}

/// The id of the one login item with this title; an alias or a second item
/// of the same name is never guessed at.
async fn item_id(login: &Login) -> Result<String> {
    let list = pass_cli(&[
        "item",
        "list",
        &login.vault,
        "--filter-type",
        "login",
        "--output",
        "json",
    ])
    .await?;
    let json: serde_json::Value = serde_json::from_str(&list).context("pass-cli item list")?;
    let items = json
        .get("items")
        .unwrap_or(&json)
        .as_array()
        .cloned()
        .unwrap_or_default();
    let ids: Vec<String> = items
        .iter()
        .filter(|i| i.get("title").and_then(|t| t.as_str()) == Some(login.item.as_str()))
        .filter_map(|i| i.get("id").and_then(|t| t.as_str()).map(str::to_owned))
        .collect();
    match ids.as_slice() {
        [id] => Ok(id.clone()),
        [] => bail!("no login item {:?} in vault {}", login.item, login.vault),
        _ => bail!(
            "{} login items titled {:?} in vault {}",
            ids.len(),
            login.item,
            login.vault
        ),
    }
}

/// The passkeys' contents in the login item that Proton Pass saved for this
/// relying party (`passkeys[].content`, Proton's own format), in memory only.
pub async fn passkeys(login: &Login, rp_id: &str) -> Result<Vec<Zeroizing<Vec<u8>>>> {
    let id = item_id(login).await?;
    let out = pass_cli(&[
        "item",
        "view",
        "--vault-name",
        login.vault.as_str(),
        "--item-id",
        id.as_str(),
        "--output",
        "json",
    ])
    .await?;
    let json: serde_json::Value = serde_json::from_str(&out).context("pass-cli item view")?;
    let found = json
        .pointer("/item/content/content/Login/passkeys")
        .and_then(|p| p.as_array())
        .cloned()
        .unwrap_or_default();
    Ok(found
        .iter()
        .filter(|p| p["rp_id"] == rp_id)
        .filter_map(|p| p["content"].as_array())
        .map(|bytes| {
            Zeroizing::new(
                bytes
                    .iter()
                    .filter_map(|b| b.as_u64().map(|b| b as u8))
                    .collect(),
            )
        })
        .collect())
}

pub async fn read(login: &Login, field: PassField) -> Result<Zeroizing<String>> {
    let id = item_id(login).await?;
    let base = [
        "--vault-name",
        login.vault.as_str(),
        "--item-id",
        id.as_str(),
    ];
    let value = match field {
        PassField::Totp => {
            let out =
                pass_cli(&[&["item", "totp"][..], &base[..], &["--output", "json"][..]].concat())
                    .await?;
            let json: serde_json::Value =
                serde_json::from_str(&out).context("pass-cli item totp")?;
            Zeroizing::new(first_code(&json).context("the login item has no TOTP")?)
        }
        _ => {
            let name = match field {
                PassField::Username => "username",
                PassField::Email => "email",
                PassField::Password => "password",
                PassField::Totp => unreachable!(),
            };
            let out =
                pass_cli(&[&["item", "view"][..], &base[..], &["--field", name][..]].concat())
                    .await?;
            Zeroizing::new(out.trim_end_matches('\n').to_owned())
        }
    };
    if value.is_empty() {
        bail!("the login item's {field:?} is empty");
    }
    Ok(value)
}

/// The first string of 6 to 8 digits anywhere in pass-cli's TOTP output.
fn first_code(v: &serde_json::Value) -> Option<String> {
    match v {
        serde_json::Value::String(s)
            if (6..=8).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_digit()) =>
        {
            Some(s.clone())
        }
        serde_json::Value::Array(a) => a.iter().find_map(first_code),
        serde_json::Value::Object(o) => o.values().find_map(first_code),
        _ => None,
    }
}
