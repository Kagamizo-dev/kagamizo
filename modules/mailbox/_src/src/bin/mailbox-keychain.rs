//! `pass`, as Proton Mail Bridge's keychain calls it (Docker's pass
//! credential helper, pinned by Bridge 3.24.2): `ls`, `show PATH`,
//! `insert -f -m PATH` (the secret on stdin) and `rm -rf PATH`. The helper
//! finds entries by the store's folders, so each entry is an empty marker
//! file there; the one real secret, Bridge's vault key, lives in Proton Pass
//! (secretspec, BRIDGE_VAULT_KEY), and the only other entry Bridge writes,
//! its keychain test, is the fixed value "check". Anything else is refused.

use std::io::{Read, Write};
use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use mailbox::{check, get, marker, set, vault_key};
use zeroize::Zeroizing;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let store = PathBuf::from(std::env::var("PASSWORD_STORE_DIR").context("PASSWORD_STORE_DIR")?);
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    match args.as_slice() {
        ["ls"] => Ok(()),
        ["show", p] if *p == vault_key().1 => {
            let key = get("BRIDGE_VAULT_KEY", "mailbox: open Bridge's vault")?;
            if key.trim().is_empty() {
                bail!("no vault key in Proton Pass");
            }
            std::io::stdout().write_all(key.trim_end().as_bytes())?;
            Ok(())
        }
        ["show", p] if *p == check().1 => {
            print!("check");
            Ok(())
        }
        ["insert", "-f", "-m", p] if *p == vault_key().1 => {
            let mut key = Zeroizing::new(String::new());
            std::io::stdin().read_to_string(&mut key)?;
            set("BRIDGE_VAULT_KEY", &key, "mailbox: keep Bridge's vault key")?;
            marker(&store, p)
        }
        ["insert", "-f", "-m", p] if *p == check().1 => {
            let mut value = String::new();
            std::io::stdin().read_to_string(&mut value)?;
            if value != "check" {
                bail!("the keychain test writes only \"check\"");
            }
            marker(&store, p)
        }
        // Forgetting an entry drops its marker; Proton Pass keeps the vault
        // key until Bridge writes a new one.
        ["rm", "-rf", p] if *p == vault_key().0 || *p == check().0 => {
            let dir = store.join(p);
            if dir.exists() {
                std::fs::remove_dir_all(dir)?;
            }
            Ok(())
        }
        _ => bail!("pass {}: not a call Bridge's keychain makes", args.join(" ")),
    }
}
