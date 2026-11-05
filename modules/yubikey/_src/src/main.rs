//! `yubikey`: the 2FA map (../default.nix renders YUBIKEY_FACTS). The key
//! itself is driven by ykman on the owner's machine; this prints the plan.

type Key = (&'static str, &'static str, &'static str, &'static str); // name, serial, model, form
type Factor = (&'static str, &'static str, &'static str, &'static str, &'static str); // account, method, key, since, reason

include!(env!("YUBIKEY_FACTS"));

const USAGE: &str = "usage: yubikey <status | legacy | enroll <account>> [--json]";

fn esc(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn enroll_steps(method: &str) -> &'static [&'static str] {
    match method {
        "fido2" => &[
            "On the account's security page, add a security key / passkey.",
            "Insert the YubiKey and tap it when it blinks.",
            "Remove any SMS factor once the key is confirmed.",
        ],
        "totp" => &[
            "On the account's 2FA page, choose authenticator app and reveal the secret.",
            "ykman oath accounts add -t '<issuer>:<account>' (paste the secret), then tap.",
            "Confirm the 6-digit code from `ykman oath accounts code`.",
        ],
        "piv" => &[
            "ykman piv keys generate / import for the slot, then a certificate.",
            "Register the certificate or public key with the account (or age-plugin-yubikey for secrets).",
        ],
        _ => &["This account is on SMS; no key enrollment. Record a reason or pick a key method."],
    }
}

fn run(args: &[String]) -> Result<String, String> {
    let json = args.iter().any(|a| a == "--json");
    let words: Vec<&str> = args.iter().map(String::as_str).filter(|a| *a != "--json").collect();
    match words.as_slice() {
        ["status"] => Ok(if json {
            let keys = KEYS
                .iter()
                .map(|(n, s, m, f)| format!("{{\"name\":{},\"serial\":{},\"model\":{},\"form\":{}}}", esc(n), esc(s), esc(m), esc(f)))
                .collect::<Vec<_>>()
                .join(",");
            let facs = FACTORS
                .iter()
                .map(|(a, m, k, s, r)| {
                    format!("{{\"account\":{},\"method\":{},\"key\":{},\"since\":{},\"reason\":{}}}", esc(a), esc(m), esc(k), esc(s), esc(r))
                })
                .collect::<Vec<_>>()
                .join(",");
            format!("{{\"keys\":[{keys}],\"factors\":[{facs}],\"accounts\":{}}}", ACCOUNTS.len())
        } else {
            let mut o = String::from("keys\n");
            if KEYS.is_empty() {
                o.push_str("  (none enrolled yet)\n");
            }
            for (n, s, m, f) in KEYS {
                o.push_str(&format!("  {n:<12} {m} ({f}), serial {s}\n"));
            }
            o.push_str(&format!("factors ({} of {} accounts)\n", FACTORS.len(), ACCOUNTS.len()));
            if FACTORS.is_empty() {
                o.push_str("  (none declared yet; every account still on its current factor)\n");
            }
            for (a, m, k, _s, r) in FACTORS {
                let tail = if *m == "sms" { format!("  (legacy: {r})") } else { format!("  on {k}") };
                o.push_str(&format!("  {a:<22} {m:<6}{tail}\n"));
            }
            o.trim_end().to_string()
        }),
        ["legacy"] => {
            let sms: Vec<&Factor> = FACTORS.iter().filter(|(_, m, _, _, _)| *m == "sms").collect();
            Ok(if json {
                format!("[{}]", sms.iter().map(|(a, _, _, _, r)| format!("{{\"account\":{},\"reason\":{}}}", esc(a), esc(r))).collect::<Vec<_>>().join(","))
            } else if sms.is_empty() {
                "no accounts on legacy SMS".into()
            } else {
                sms.iter().map(|(a, _, _, _, r)| format!("{a:<22} {r}")).collect::<Vec<_>>().join("\n")
            })
        }
        ["enroll", account] => {
            let f = FACTORS.iter().find(|(a, _, _, _, _)| a == account);
            let method = f.map(|(_, m, _, _, _)| *m).unwrap_or("fido2");
            Ok(format!(
                "enroll {account} ({method}) — the owner's steps (operations.humanSteps.enroll-security-key):\n{}",
                enroll_steps(method).iter().map(|s| format!("  - {s}")).collect::<Vec<_>>().join("\n")
            ))
        }
        _ => Err(USAGE.into()),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(o) => println!("{o}"),
        Err(e) => {
            eprintln!("yubikey: {e}");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_methods_name_a_declared_key() {
        let names: Vec<&str> = KEYS.iter().map(|(n, _, _, _)| *n).collect();
        for (a, m, k, _, _) in FACTORS {
            if *m != "sms" {
                assert!(names.contains(k), "{a}: {m} on undeclared key {k}");
            }
        }
    }

    #[test]
    fn sms_factors_have_a_reason() {
        for (a, m, _, _, r) in FACTORS {
            if *m == "sms" {
                assert!(!r.is_empty(), "{a} on sms with no reason");
            }
        }
    }

    #[test]
    fn enroll_covers_every_method() {
        for m in ["fido2", "totp", "piv", "sms"] {
            assert!(!enroll_steps(m).is_empty());
        }
    }

    #[test]
    fn commands() {
        assert!(run(&["status".into()]).is_ok());
        assert!(run(&["status".into(), "--json".into()]).unwrap().starts_with('{'));
        assert!(run(&["legacy".into()]).is_ok());
        assert!(run(&["enroll".into(), "proton".into()]).is_ok());
        assert!(run(&["bogus".into()]).is_err());
    }
}
