//! The bank's audit over transaction history: one typed transaction for
//! every source (a bank's exported CSV today, the bank-link provider's feed
//! once chosen), then the facts consolidation needs: what recurs, on which
//! account and card it rests, what is paid twice, what fees and interest
//! cost, and what still sits on the accounts the owner is closing.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{bail, Context, Result};
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};

/// One transaction, whatever its source. `amount` is money out as a
/// positive number (a charge, a fee), money in as negative (a payment, a
/// refund).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Txn {
    pub account: String,
    pub date: NaiveDate,
    pub description: String,
    pub amount: f64,
    #[serde(default)]
    pub category: Option<String>,
}

/// A merchant's name from a statement line: card-network noise removed
/// (store numbers, phone numbers, city and state, processor prefixes), so
/// one merchant reads the same across months and accounts.
pub fn merchant(description: &str) -> String {
    let mut d = description.to_uppercase();
    for prefix in ["SQ *", "TST* ", "TST*", "SP ", "PP*", "DD *", "IC* "] {
        if let Some(rest) = d.strip_prefix(prefix) {
            d = rest.to_string();
        }
    }
    let words: Vec<&str> = d
        .split(|c: char| c.is_whitespace() || c == '*' || c == '#')
        .filter(|w| !w.is_empty())
        .collect();
    let mut kept = vec![];
    for (i, w) in words.iter().enumerate() {
        let digits = w.chars().filter(|c| c.is_ascii_digit()).count();
        // A store number, a phone number or a reference: drop it and stop
        // at the first one after the name.
        if digits * 2 >= w.len() {
            if !kept.is_empty() {
                break;
            }
            continue;
        }
        // A trailing two-letter state code.
        if i == words.len() - 1 && w.len() == 2 && kept.len() > 1 {
            break;
        }
        kept.push(w.trim_matches(|c: char| !c.is_ascii_alphanumeric() && c != '.' && c != '&'));
        if kept.len() == 3 {
            break;
        }
    }
    let name = kept.join(" ");
    let name = name.trim_end_matches(".COM").trim_end_matches(".NET").trim();
    if name.is_empty() {
        description.trim().to_uppercase()
    } else {
        name.to_string()
    }
}

/// How often something charges, from its charge dates.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Cadence {
    Weekly,
    Monthly,
    Quarterly,
    Yearly,
    Irregular,
    Once,
}

impl Cadence {
    pub fn per_year(self) -> f64 {
        match self {
            Cadence::Weekly => 52.0,
            Cadence::Monthly => 12.0,
            Cadence::Quarterly => 4.0,
            Cadence::Yearly => 1.0,
            Cadence::Irregular | Cadence::Once => 0.0,
        }
    }
}

/// The cadence of distinct charge days: the median gap between them.
pub fn cadence(dates: &[NaiveDate]) -> Cadence {
    let mut d: Vec<NaiveDate> = dates.to_vec();
    d.sort_unstable();
    d.dedup();
    if d.len() < 2 {
        return Cadence::Once;
    }
    let mut gaps: Vec<i64> = d.windows(2).map(|w| (w[1] - w[0]).num_days()).collect();
    gaps.sort_unstable();
    match gaps[gaps.len() / 2] {
        5..=9 => Cadence::Weekly,
        25..=35 => Cadence::Monthly,
        80..=100 => Cadence::Quarterly,
        330..=400 => Cadence::Yearly,
        _ => Cadence::Irregular,
    }
}

const FEES: &[&str] = &[
    "ANNUAL FEE", "LATE FEE", "INTEREST CHARGE", "FINANCE CHARGE", "FOREIGN TRANSACTION", "OVERDRAFT",
    "MONTHLY SERVICE FEE", "SERVICE FEE", "RETURNED PAYMENT", "CASH ADVANCE FEE",
];
/// Lines that move money between the owner's own accounts, never spending.
const TRANSFERS: &[&str] = &[
    "PAYMENT THANK YOU", "AUTOPAY", "AUTOMATIC PAYMENT", "ONLINE TRANSFER", "TRANSFER TO", "TRANSFER FROM",
    "PAYMENT - THANK", "MOBILE PAYMENT", "ZELLE",
];

#[derive(Debug, Clone, Serialize)]
pub struct Recurring {
    pub merchant: String,
    pub cadence: Cadence,
    pub charges: usize,
    pub last: NaiveDate,
    pub last_amount: f64,
    pub per_month: f64,
    /// Every account it has charged, newest last.
    pub accounts: Vec<String>,
    /// The account its newest charge landed on.
    pub rests_on: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Audit {
    pub transactions: usize,
    pub from: Option<NaiveDate>,
    pub to: Option<NaiveDate>,
    pub accounts: BTreeMap<String, AccountSummary>,
    pub recurring: Vec<Recurring>,
    /// Merchants charging on more than one account: likely paid twice or
    /// half moved.
    pub on_several_accounts: Vec<String>,
    pub fees: Vec<Txn>,
    /// Recurring charges whose newest charge rests on an account being
    /// closed: each must move before the close.
    pub to_move: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct AccountSummary {
    pub transactions: usize,
    pub spent: f64,
    pub fees: f64,
    pub recurring_per_month: f64,
}

fn is_any(d: &str, words: &[&str]) -> bool {
    let u = d.to_uppercase();
    words.iter().any(|w| u.contains(w))
}

/// The audit of every transaction, given the accounts being closed.
pub fn audit(txns: &[Txn], closing: &BTreeSet<String>) -> Audit {
    let spend: Vec<&Txn> = txns.iter().filter(|t| t.amount > 0.0 && !is_any(&t.description, TRANSFERS)).collect();
    let fees: Vec<Txn> = spend.iter().filter(|t| is_any(&t.description, FEES)).map(|t| (*t).clone()).collect();
    let mut by: BTreeMap<String, Vec<&Txn>> = BTreeMap::new();
    for t in spend.iter().filter(|t| !is_any(&t.description, FEES)) {
        by.entry(merchant(&t.description)).or_default().push(t);
    }
    let mut recurring = vec![];
    for (m, mut ts) in by {
        ts.sort_by_key(|t| t.date);
        let dates: Vec<NaiveDate> = ts.iter().map(|t| t.date).collect();
        let c = cadence(&dates);
        if c.per_year() == 0.0 {
            continue;
        }
        let last = ts.last().expect("a merchant has a charge");
        let mut accounts: Vec<String> = vec![];
        for t in &ts {
            if !accounts.contains(&t.account) {
                accounts.push(t.account.clone());
            }
        }
        recurring.push(Recurring {
            merchant: m,
            cadence: c,
            charges: ts.len(),
            last: last.date,
            last_amount: last.amount,
            per_month: last.amount * c.per_year() / 12.0,
            accounts,
            rests_on: last.account.clone(),
        });
    }
    recurring.sort_by(|a, b| b.per_month.partial_cmp(&a.per_month).unwrap_or(std::cmp::Ordering::Equal));
    let mut accounts: BTreeMap<String, AccountSummary> = BTreeMap::new();
    for t in txns {
        let a = accounts.entry(t.account.clone()).or_default();
        a.transactions += 1;
        if t.amount > 0.0 && !is_any(&t.description, TRANSFERS) {
            a.spent += t.amount;
        }
    }
    for f in &fees {
        accounts.entry(f.account.clone()).or_default().fees += f.amount;
    }
    for r in &recurring {
        accounts.entry(r.rests_on.clone()).or_default().recurring_per_month += r.per_month;
    }
    Audit {
        transactions: txns.len(),
        from: txns.iter().map(|t| t.date).min(),
        to: txns.iter().map(|t| t.date).max(),
        on_several_accounts: recurring.iter().filter(|r| r.accounts.len() > 1).map(|r| r.merchant.clone()).collect(),
        to_move: recurring.iter().filter(|r| closing.contains(&r.rests_on)).map(|r| r.merchant.clone()).collect(),
        accounts,
        recurring,
        fees,
    }
}

/// A bank's exported CSV, read by its header row: the date, description and
/// amount columns are found by name, and a layout with none of the known
/// names is refused, naming its headers, so no file is ever misread.
/// `charges_negative` is the sign of a charge in a single amount column
/// (Chase writes purchases as negative); Debit/Credit columns need none.
pub fn read_csv(account: &str, text: &str, charges_negative: bool) -> Result<Vec<Txn>> {
    let mut r = csv::ReaderBuilder::new().flexible(true).trim(csv::Trim::All).from_reader(text.as_bytes());
    let headers: Vec<String> = r.headers()?.iter().map(|h| h.to_lowercase()).collect();
    let find = |names: &[&str]| headers.iter().position(|h| names.contains(&h.as_str()));
    let date = find(&["transaction date", "trans. date", "date", "posting date", "post date", "posted date"]);
    let desc = find(&["description", "merchant", "payee", "name"]);
    let amount = find(&["amount"]);
    let (debit, credit) = (find(&["debit"]), find(&["credit"]));
    let category = find(&["category"]);
    let (Some(date), Some(desc)) = (date, desc) else {
        bail!("{account}: no date or description column among {:?}", headers);
    };
    if amount.is_none() && debit.is_none() {
        bail!("{account}: no amount or debit column among {:?}", headers);
    }
    let num = |s: &str| -> Option<f64> {
        let t = s.replace(['$', ','], "");
        let t = t.trim();
        if t.is_empty() {
            return None;
        }
        if let Some(inner) = t.strip_prefix('(').and_then(|x| x.strip_suffix(')')) {
            return inner.parse::<f64>().ok().map(|v| -v);
        }
        t.parse::<f64>().ok()
    };
    let mut out = vec![];
    for (i, row) in r.records().enumerate() {
        let row = row.with_context(|| format!("{account}: row {}", i + 2))?;
        let get = |c: usize| row.get(c).unwrap_or("");
        let when = get(date);
        let parsed = ["%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y"]
            .iter()
            .find_map(|f| NaiveDate::parse_from_str(when, f).ok())
            .with_context(|| format!("{account}: row {}: the date {when:?}", i + 2))?;
        let value = match (amount, debit, credit) {
            (Some(a), _, _) => {
                let v = num(get(a)).unwrap_or(0.0);
                if charges_negative { -v } else { v }
            }
            (None, Some(d), c) => {
                num(get(d)).unwrap_or(0.0) - c.and_then(|c| num(get(c))).unwrap_or(0.0)
            }
            _ => 0.0,
        };
        out.push(Txn {
            account: account.to_string(),
            date: parsed,
            description: get(desc).to_string(),
            amount: value,
            category: category.map(|c| get(c).to_string()).filter(|c| !c.is_empty()),
        });
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(s: &str) -> NaiveDate {
        NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
    }

    #[test]
    fn merchants_read_the_same_across_lines() {
        assert_eq!(merchant("NETFLIX.COM 866-579-7172 CA"), "NETFLIX");
        assert_eq!(merchant("SQ *BLUE BOTTLE COFFEE 0412 OAKLAND CA"), "BLUE BOTTLE COFFEE");
        assert_eq!(merchant("SPOTIFY USA 877-778-1161 NY"), "SPOTIFY USA");
        assert_eq!(merchant("AMAZON PRIME*1A2B3C4D5 AMZN.COM/BILL WA"), "AMAZON PRIME");
    }

    #[test]
    fn single_amount_and_debit_credit_layouts_both_read() {
        let chase = "Transaction Date,Post Date,Description,Category,Type,Amount,Memo\n\
                     10/01/2026,10/02/2026,NETFLIX.COM 866-579-7172 CA,Entertainment,Sale,-15.49,\n\
                     10/05/2026,10/05/2026,Payment Thank You-Mobile,,Payment,200.00,\n";
        let t = read_csv("chase-sapphire", chase, true).unwrap();
        assert_eq!((t[0].amount, t[1].amount), (15.49, -200.0));
        let cap = "Transaction Date,Posted Date,Card No.,Description,Category,Debit,Credit\n\
                   2026-10-03,2026-10-04,1234,SPOTIFY USA 877-778-1161 NY,Entertainment,11.99,\n\
                   2026-10-09,2026-10-09,1234,CAPITAL ONE MOBILE PYMT,Payment/Credit,,50.00\n";
        let t = read_csv("capital-one-venture-x", cap, false).unwrap();
        assert_eq!((t[0].amount, t[1].amount), (11.99, -50.0));
        assert!(read_csv("x", "When,What\n1,2\n", true).is_err(), "an unknown layout is refused");
    }

    #[test]
    fn the_audit_finds_recurring_duplicates_fees_and_what_to_move() {
        let t = |a: &str, day: &str, desc: &str, amt: f64| Txn {
            account: a.into(),
            date: d(day),
            description: desc.into(),
            amount: amt,
            category: None,
        };
        let txns = vec![
            t("chase", "2026-08-01", "NETFLIX.COM 866-579-7172 CA", 15.49),
            t("chase", "2026-09-01", "NETFLIX.COM 866-579-7172 CA", 15.49),
            t("mercury-media", "2026-10-01", "NETFLIX.COM 866-579-7172 CA", 15.49),
            t("chase", "2026-08-15", "SPOTIFY USA 877-778-1161 NY", 11.99),
            t("chase", "2026-09-15", "SPOTIFY USA 877-778-1161 NY", 11.99),
            t("chase", "2026-10-15", "SPOTIFY USA 877-778-1161 NY", 11.99),
            t("credit-one", "2026-10-20", "ANNUAL FEE", 95.0),
            t("chase", "2026-10-05", "Payment Thank You-Mobile", -200.0),
            t("chase", "2026-10-07", "BLUE BOTTLE COFFEE", 6.5),
        ];
        let closing: BTreeSet<String> = ["chase".to_string(), "credit-one".to_string()].into();
        let a = audit(&txns, &closing);
        let names: Vec<&str> = a.recurring.iter().map(|r| r.merchant.as_str()).collect();
        assert_eq!(names, vec!["NETFLIX", "SPOTIFY USA"]);
        assert_eq!(a.recurring[0].rests_on, "mercury-media");
        assert_eq!(a.on_several_accounts, vec!["NETFLIX".to_string()]);
        assert_eq!(a.to_move, vec!["SPOTIFY USA".to_string()], "Netflix already moved to Mercury");
        assert_eq!(a.fees.len(), 1);
        assert_eq!(a.accounts["credit-one"].fees, 95.0);
    }
}
