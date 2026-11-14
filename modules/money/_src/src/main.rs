//! `money-report RULES.json OUT-DIR [ACCOUNT=TRANSACTIONS.jsonl ...]`
//!
//! A tax year's report for one return, from Mercury's own transactions
//! (`mercury-cli transactions list --format jsonl`) and the rules
//! modules/money declares (RULES.json): an hledger journal, each business's
//! Schedule C, the transactions that need a decision, the obligations, and
//! an index saying which sources were read and which were not.
//!
//! Amounts are kept in cents. Nothing is guessed: a transaction whose
//! treatment is not settled by the rules goes to review.md.

use serde::Deserialize;
use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::fs;
use std::path::Path;

#[derive(Deserialize, Debug, Clone)]
struct Treatment {
    kind: String,
    line: Option<String>,
    percent: u32,
    why: String,
}

#[derive(Deserialize, Debug, Clone)]
struct Decision {
    #[serde(rename = "as")]
    as_: String,
    line: Option<String>,
    percent: u32,
    why: String,
}

#[derive(Deserialize, Debug)]
struct Account {
    entity: String,
    #[serde(rename = "legalName")]
    legal_name: String,
    personal: bool,
}

#[derive(Deserialize, Debug)]
struct Obligation {
    entity: String,
    form: String,
    what: String,
    due: Option<String>,
    source: String,
    when: Option<String>,
}

#[derive(Deserialize, Debug)]
struct Unread {
    source: String,
    why: String,
}

#[derive(Deserialize, Debug)]
struct Rules {
    #[serde(rename = "return")]
    return_of: String,
    year: i32,
    accounts: BTreeMap<String, Account>,
    treatment: BTreeMap<String, Treatment>,
    #[serde(default)]
    decisions: BTreeMap<String, Decision>,
    obligations: Vec<Obligation>,
    #[serde(default)]
    unread: Vec<Unread>,
}

#[derive(Deserialize, Debug, Default)]
#[serde(rename_all = "camelCase", default)]
struct Txn {
    id: String,
    amount: f64,
    status: String,
    kind: String,
    counterparty_name: String,
    mercury_category: Option<String>,
    posted_at: Option<String>,
    created_at: String,
}

/// Where one transaction lands.
#[derive(Debug, PartialEq)]
enum Lands {
    /// Schedule C line, and the cents deductible.
    ScheduleC(String, i64),
    Personal,
    OwnerDraw,
    Contribution,
    GrossReceipts,
    Nondeductible(String),
    Interest,
    Transfer,
    Review(String),
}

fn cents(a: f64) -> i64 {
    (a * 100.0).round() as i64
}

fn money(c: i64) -> String {
    let sign = if c < 0 { "-" } else { "" };
    format!("{sign}{}.{:02}", c.abs() / 100, c.abs() % 100)
}

fn classify(t: &Txn, acct: &Account, rules: &Rules) -> Lands {
    let c = cents(t.amount);
    // The owner's decision on this transaction settles it first.
    if let Some(d) = rules.decisions.get(&t.id) {
        return match d.as_.as_str() {
            "schedule-c" => Lands::ScheduleC(d.line.clone().unwrap_or_default(), -c * i64::from(d.percent) / 100),
            "owner-draw" => Lands::OwnerDraw,
            "contribution" => Lands::Contribution,
            "transfer" => Lands::Transfer,
            "gross-receipts" => Lands::GrossReceipts,
            "personal" => Lands::Personal,
            other => Lands::Review(format!("decision {other} ({}) is not one this report knows", d.why)),
        };
    }
    match t.kind.as_str() {
        "internalTransfer" | "treasuryTransfer" => return Lands::Transfer,
        "interestPayment" => return Lands::Interest,
        _ => {}
    }
    if c > 0 {
        return Lands::Review(if acct.personal {
            "money in to a personal account: a transfer from your own account, or income (wages, a sale)".into()
        } else {
            "money in: gross receipts (Schedule C line 1), an owner's contribution, or a refund".into()
        });
    }
    if acct.personal {
        return Lands::Personal;
    }
    let Some(cat) = t.mercury_category.as_deref() else {
        return Lands::Review("Mercury gave it no category".into());
    };
    let Some(tr) = rules.treatment.get(cat) else {
        return Lands::Review(format!("category {cat} has no treatment"));
    };
    match tr.kind.as_str() {
        "schedule-c" => Lands::ScheduleC(
            tr.line.clone().unwrap_or_default(),
            -c * i64::from(tr.percent) / 100,
        ),
        // A personal cost paid from the business is a draw by its owner.
        "personal" => Lands::OwnerDraw,
        "nondeductible" => Lands::Nondeductible(tr.why.clone()),
        _ => Lands::Review(tr.why.clone()),
    }
}

fn date(t: &Txn) -> String {
    t.posted_at.as_deref().unwrap_or(&t.created_at).chars().take(10).collect()
}

struct Report {
    journal: String,
    review: Vec<String>,
    schedule_c: BTreeMap<String, BTreeMap<String, i64>>,
    read: Vec<String>,
}

fn build(rules: &Rules, sources: &[(String, Vec<Txn>)]) -> Report {
    let mut r = Report {
        journal: String::new(),
        review: Vec::new(),
        schedule_c: BTreeMap::new(),
        read: Vec::new(),
    };
    for (acc, txns) in sources {
        let a = &rules.accounts[acc];
        r.read.push(format!("{acc} ({}): {} transactions", a.entity, txns.len()));
        for t in txns {
            if matches!(t.status.as_str(), "failed" | "cancelled" | "blocked" | "reversed") {
                continue;
            }
            let c = cents(t.amount);
            let e = &a.entity;
            let other = match classify(t, a, rules) {
                Lands::ScheduleC(line, deductible) => {
                    *r.schedule_c.entry(e.clone()).or_default().entry(line.clone()).or_default() +=
                        deductible;
                    format!("expenses:{e}:schedule-c:line-{line}")
                }
                Lands::Personal => format!("expenses:{e}:personal"),
                Lands::OwnerDraw => format!("equity:{e}:owner-draw"),
                Lands::Contribution => format!("equity:{e}:contribution"),
                Lands::GrossReceipts => {
                    *r.schedule_c.entry(e.clone()).or_default().entry("1".into()).or_default() += c;
                    format!("income:{e}:gross-receipts")
                }
                Lands::Nondeductible(_) => format!("expenses:{e}:nondeductible"),
                Lands::Interest => format!("income:{e}:interest"),
                Lands::Transfer => format!("assets:{e}:transfers"),
                Lands::Review(why) => {
                    r.review.push(format!(
                        "| {} | {acc} | {} | {} | {} | {why} |",
                        date(t),
                        money(c),
                        t.counterparty_name,
                        t.id
                    ));
                    format!("{}:{e}:review", if c > 0 { "income" } else { "expenses" })
                }
            };
            let pending = if t.status == "pending" { "! " } else { "" };
            let _ = writeln!(
                r.journal,
                "{} {pending}{}  ; id:{}\n    assets:{e}:mercury:{acc}  {} USD\n    {other}\n",
                date(t),
                t.counterparty_name.replace(';', ","),
                t.id,
                money(c)
            );
        }
    }
    r
}

fn render(rules: &Rules, r: &Report, out: &Path) -> std::io::Result<()> {
    fs::create_dir_all(out)?;
    fs::write(out.join("ledger.journal"), &r.journal)?;

    let mut sc = String::new();
    for (e, lines) in &r.schedule_c {
        let name = rules.accounts.values().find(|a| &a.entity == e).map(|a| a.legal_name.as_str());
        let _ = writeln!(sc, "# Schedule C, {} ({}), {}\n", name.unwrap_or(e), e, rules.year);
        let _ = writeln!(sc, "Line 1 is gross receipts; the rest are Part II expense lines, deductible share applied. Anything in review.md is not counted yet.\n");
        let _ = writeln!(sc, "| Line | Deductible |\n|---|---|");
        let mut total = 0;
        for (l, v) in lines {
            if l != "1" {
                total += v;
            }
            let _ = writeln!(sc, "| {l} | {} |", money(*v));
        }
        let _ = writeln!(sc, "| **28 (total expenses)** | **{}** |\n", money(total));
    }
    if sc.is_empty() {
        sc = format!("No business expenses read for {}.\n", rules.year);
    }
    fs::write(out.join("schedule-c.md"), sc)?;

    let mut rv = format!("# Needs a decision ({})\n\n", r.review.len());
    rv.push_str("| Date | Account | Amount | Counterparty | Id | Why |\n|---|---|---|---|---|---|\n");
    for l in &r.review {
        rv.push_str(l);
        rv.push('\n');
    }
    fs::write(out.join("review.md"), rv)?;

    let mut ob = format!("# Obligations for tax year {}\n\n| Due | Entity | Form | What | When | Source |\n|---|---|---|---|---|---|\n", rules.year);
    for o in &rules.obligations {
        let _ = writeln!(
            ob,
            "| {} | {} | {} | {} | {} | {} |",
            o.due.as_deref().unwrap_or("not yet known"),
            o.entity,
            o.form,
            o.what,
            o.when.as_deref().unwrap_or("always"),
            o.source
        );
    }
    fs::write(out.join("obligations.md"), ob)?;

    let complete = rules.unread.is_empty();
    let mut ix = format!(
        "# Tax report: {}'s return, {}\n\n**{}**\n\n## Read\n\n",
        rules.return_of,
        rules.year,
        if complete { "Every declared source was read." } else { "Incomplete: some sources were not read (below)." }
    );
    for s in &r.read {
        let _ = writeln!(ix, "- {s}");
    }
    if !complete {
        ix.push_str("\n## Not read\n\n");
        for u in &rules.unread {
            let _ = writeln!(ix, "- {}: {}", u.source, u.why);
        }
    }
    ix.push_str("\n## Files\n\n- ledger.journal (hledger)\n- schedule-c.md\n- review.md\n- obligations.md\n");
    fs::write(out.join("README.md"), ix)
}

fn main() -> std::process::ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 2 {
        eprintln!("usage: money-report RULES.json OUT-DIR [ACCOUNT=TRANSACTIONS.jsonl ...]");
        return 2.into();
    }
    let rules: Rules = match fs::read(&args[0]).map_err(|e| e.to_string()).and_then(|b| serde_json::from_slice(&b).map_err(|e| e.to_string())) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("money-report: {}: {e}", args[0]);
            return 2.into();
        }
    };
    let mut sources = Vec::new();
    for a in &args[2..] {
        let Some((acc, file)) = a.split_once('=') else {
            eprintln!("money-report: {a}: expected ACCOUNT=FILE");
            return 2.into();
        };
        if !rules.accounts.contains_key(acc) {
            eprintln!("money-report: {acc} is not an account of this return");
            return 2.into();
        }
        let text = match fs::read_to_string(file) {
            Ok(t) => t,
            Err(e) => {
                eprintln!("money-report: {file}: {e}");
                return 2.into();
            }
        };
        let mut txns = Vec::new();
        for (n, line) in text.lines().enumerate().filter(|(_, l)| !l.trim().is_empty()) {
            match serde_json::from_str::<Txn>(line) {
                Ok(t) => txns.push(t),
                Err(e) => {
                    eprintln!("money-report: {file}:{}: {e}", n + 1);
                    return 2.into();
                }
            }
        }
        sources.push((acc.to_string(), txns));
    }
    let r = build(&rules, &sources);
    if let Err(e) = render(&rules, &r, Path::new(&args[1])) {
        eprintln!("money-report: {e}");
        return 1.into();
    }
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rules() -> Rules {
        serde_json::from_str(include_str!("../_test/rules.json")).unwrap()
    }

    fn txn(kind: &str, amount: f64, cat: Option<&str>) -> Txn {
        Txn {
            id: "t".into(),
            amount,
            status: "sent".into(),
            kind: kind.into(),
            counterparty_name: "X".into(),
            mercury_category: cat.map(String::from),
            posted_at: Some("2026-03-01T00:00:00Z".into()),
            created_at: "2026-03-01T00:00:00Z".into(),
        }
    }

    #[test]
    fn software_is_line_18() {
        let r = rules();
        let a = &r.accounts["biz"];
        assert_eq!(classify(&txn("debitCardTransaction", -12.5, Some("Software")), a, &r), Lands::ScheduleC("18".into(), 1250));
    }

    #[test]
    fn meals_half() {
        let r = rules();
        let a = &r.accounts["biz"];
        assert_eq!(classify(&txn("debitCardTransaction", -40.0, Some("Restaurants")), a, &r), Lands::ScheduleC("24b".into(), 2000));
    }

    #[test]
    fn personal_on_business_is_a_draw() {
        let r = rules();
        assert_eq!(classify(&txn("debitCardTransaction", -9.0, Some("Grocery")), &r.accounts["biz"], &r), Lands::OwnerDraw);
        assert_eq!(classify(&txn("debitCardTransaction", -9.0, Some("Software")), &r.accounts["me"], &r), Lands::Personal);
    }

    #[test]
    fn money_in_is_reviewed_and_interest_is_interest() {
        let r = rules();
        let a = &r.accounts["biz"];
        assert!(matches!(classify(&txn("incomingDomesticWire", 100.0, None), a, &r), Lands::Review(_)));
        assert_eq!(classify(&txn("interestPayment", 0.3, None), a, &r), Lands::Interest);
        assert_eq!(classify(&txn("internalTransfer", -50.0, None), a, &r), Lands::Transfer);
    }

    #[test]
    fn decision_settles_first() {
        let mut r = rules();
        r.decisions.insert(
            "t".into(),
            Decision { as_: "owner-draw".into(), line: None, percent: 100, why: "w".into() },
        );
        assert_eq!(classify(&txn("outgoingPayment", -60.0, None), &r.accounts["biz"], &r), Lands::OwnerDraw);
    }

    #[test]
    fn report_totals_and_skips_failed() {
        let r = rules();
        let mut failed = txn("debitCardTransaction", -1000.0, Some("Software"));
        failed.status = "failed".into();
        let rep = build(&r, &[("biz".into(), vec![txn("debitCardTransaction", -12.5, Some("Software")), failed])]);
        assert_eq!(rep.schedule_c["jingzo"]["18"], 1250);
    }
}
