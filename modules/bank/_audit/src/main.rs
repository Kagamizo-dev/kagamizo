//! `bank-audit`: the audit of transaction history across accounts.
//!
//!   bank-audit --out FILE [--closing ACCOUNT]... ACCOUNT=FILE[:charges-negative]...
//!
//! Each ACCOUNT=FILE is a bank's exported CSV (or a JSON array of
//! transactions from the bank-link feed, by its .json extension). The
//! audit (recurring charges, where each rests, merchants on several
//! accounts, fees, what must move off the accounts being closed) is
//! written to FILE (mode 600); only counts and totals are printed.

use std::collections::BTreeSet;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;

use anyhow::{bail, Context, Result};
use bank_audit::{audit, read_csv, Txn};

fn main() -> Result<()> {
    let usage = "usage: bank-audit --out FILE [--closing ACCOUNT]... ACCOUNT=FILE[:charges-negative]...";
    let mut args = std::env::args().skip(1);
    let (mut out, mut closing, mut txns) = (None, BTreeSet::new(), Vec::<Txn>::new());
    while let Some(a) = args.next() {
        match a.as_str() {
            "--out" => out = Some(args.next().context(usage)?),
            "--closing" => {
                closing.insert(args.next().context(usage)?);
            }
            source => {
                let (account, rest) = source.split_once('=').context(usage)?;
                let (file, negative) = match rest.strip_suffix(":charges-negative") {
                    Some(f) => (f, true),
                    None => (rest, false),
                };
                let text = std::fs::read_to_string(file).with_context(|| file.to_string())?;
                if file.ends_with(".json") {
                    let mut t: Vec<Txn> = serde_json::from_str(&text).with_context(|| file.to_string())?;
                    for x in &mut t {
                        x.account = account.to_string();
                    }
                    txns.extend(t);
                } else {
                    txns.extend(read_csv(account, &text, negative)?);
                }
            }
        }
    }
    let Some(out) = out else { bail!(usage) };
    if txns.is_empty() {
        bail!("no transactions read; {usage}");
    }
    let a = audit(&txns, &closing);
    let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&out)?;
    f.write_all(serde_json::to_string_pretty(&a)?.as_bytes())?;
    let monthly: f64 = a.recurring.iter().map(|r| r.per_month).sum();
    let fees: f64 = a.fees.iter().map(|t| t.amount).sum();
    println!(
        "{{\"transactions\":{},\"accounts\":{},\"recurring\":{},\"recurring_per_month\":{monthly:.2},\"on_several_accounts\":{},\"to_move\":{},\"fees\":{fees:.2}}}",
        a.transactions,
        a.accounts.len(),
        a.recurring.len(),
        a.on_several_accounts.len(),
        a.to_move.len()
    );
    Ok(())
}
