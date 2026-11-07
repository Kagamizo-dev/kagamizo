//! `money-ledger ACCOUNT ACCOUNT-ID AS-OF PORTFOLIO.json HISTORY.jsonl ORDERS.json TAXLOTS.json OUT.json`
//!
//! Types one day's reads of a Public brokerage account into one ledger
//! record (`money.ledger.public.<date>.json`, modules/money). The inputs
//! are what `brokerage --json` printed: `portfolio show`, every page of
//! `history list` (one JSON page per line), `order search` and `taxlots
//! list`. Every enum is held to the pinned CLI's generated models
//! (publicdotcom_cli/_generated/models, 1.3.7); a value the model does not
//! name fails the run and names the field, so nothing is guessed into the
//! books. Amounts stay the decimal strings Public sends.

use serde::{Deserialize, Serialize};
use std::fs;

// publicdotcom_cli/_generated/models/*_portfolio_equity_v2_type.py
const EQUITY_TYPES: &[&str] = &["BONDS", "CASH", "CRYPTO", "JIKO_ACCOUNT", "OPTIONS_LONG", "OPTIONS_SHORT", "STOCK"];
// *_portfolio_instrument_type.py
const INSTRUMENT_TYPES: &[&str] = &["ALT", "BOND", "CRYPTO", "EQUITY", "EVENTCONTRACT", "INDEX", "OPTION", "TREASURY"];
// *_history_transaction_type.py, *_sub_type.py, *_security_type.py, *_side.py, *_direction.py
const HISTORY_TYPES: &[&str] = &["MONEY_MOVEMENT", "POSITION_ADJUSTMENT", "TRADE"];
const HISTORY_SUB_TYPES: &[&str] = &[
    "DEPOSIT", "DEPOSIT_RETURNED", "DIVIDEND", "FEE", "INTEREST", "MISC", "REWARD", "TRADE", "TRANSFER",
    "TREASURY_BILL_TRANSFER", "WITHDRAWAL", "WITHDRAWAL_RETURNED",
];
const HISTORY_SECURITY_TYPES: &[&str] = &["ALT", "BOND", "CRYPTO", "EQUITY", "EVENTCONTRACT", "OPTION", "TREASURY"];
const SIDES: &[&str] = &["BUY", "SELL"];
const DIRECTIONS: &[&str] = &["INCOMING", "OUTGOING"];
// *_order_v2_gateway_order_v2_status.py, *_order_gateway_order_type.py
const ORDER_STATUSES: &[&str] = &[
    "CANCELLED", "EXPIRED", "FILLED", "NEW", "PARTIALLY_FILLED", "PENDING_CANCEL", "PENDING_REPLACE",
    "QUEUED_CANCELLED", "REJECTED", "REPLACED",
];
const ORDER_TYPES: &[&str] = &["LIMIT", "MARKET", "STOP", "STOP_LIMIT"];

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct BuyingPower {
    cash_only_buying_power: String,
    buying_power: String,
    options_buying_power: String,
    #[serde(default)]
    day_trade_buying_power: Option<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct Instrument {
    symbol: String,
    #[serde(rename = "type")]
    kind: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct Equity {
    #[serde(rename = "type")]
    kind: String,
    value: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct Position {
    instrument: Instrument,
    quantity: String,
    #[serde(default)]
    cost_basis: Option<serde_json::Value>,
    #[serde(default)]
    last_price: Option<serde_json::Value>,
    #[serde(default)]
    current_value: Option<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct Portfolio {
    account_id: String,
    account_type: String,
    buying_power: BuyingPower,
    equity: Vec<Equity>,
    positions: Vec<Position>,
    #[serde(default)]
    cash: Option<String>,
    #[serde(default)]
    total_account_value: Option<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct Transaction {
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    timestamp: Option<String>,
    #[serde(rename = "type", default)]
    kind: Option<String>,
    #[serde(default)]
    sub_type: Option<String>,
    #[serde(default)]
    symbol: Option<String>,
    #[serde(default)]
    security_type: Option<String>,
    #[serde(default)]
    side: Option<String>,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    net_amount: Option<String>,
    #[serde(default)]
    principal_amount: Option<String>,
    #[serde(default)]
    quantity: Option<String>,
    #[serde(default)]
    direction: Option<String>,
    #[serde(default)]
    fees: Option<String>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
struct HistoryPage {
    #[serde(default)]
    transactions: Option<Vec<Transaction>>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct Trade {
    #[serde(default)]
    trade_id: Option<String>,
    #[serde(default)]
    timestamp: Option<String>,
    #[serde(default)]
    quantity: Option<String>,
    #[serde(default)]
    price: Option<String>,
    #[serde(default)]
    side: Option<String>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct Order {
    #[serde(default)]
    order_id: Option<String>,
    #[serde(default)]
    instrument: Option<Instrument>,
    #[serde(default)]
    created_at: Option<String>,
    #[serde(rename = "type", default)]
    kind: Option<String>,
    #[serde(default)]
    side: Option<String>,
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    quantity: Option<String>,
    #[serde(default)]
    notional_value: Option<String>,
    #[serde(default)]
    limit_price: Option<String>,
    #[serde(default)]
    stop_price: Option<String>,
    #[serde(default)]
    filled_quantity: Option<String>,
    #[serde(default)]
    average_price: Option<String>,
    #[serde(default)]
    filled_at: Option<String>,
    #[serde(default)]
    closed_at: Option<String>,
    #[serde(default)]
    trades: Option<Vec<Trade>>,
    #[serde(default)]
    reject_reason: Option<String>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
struct Orders {
    #[serde(default)]
    orders: Option<Vec<Order>>,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct Lot {
    symbol: String,
    #[serde(default)]
    cusip: Option<String>,
    #[serde(default)]
    company_name: Option<String>,
    quantity: String,
    cost_basis: String,
    unit_cost: String,
    current_price: String,
    current_value: String,
    gain_loss: String,
    short_term_gain_loss: String,
    long_term_gain_loss: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct TaxLots {
    as_of: String,
    lots: Vec<Lot>,
    short_term: String,
    long_term: String,
    sixty_forty_term: String,
    total_profit_loss: String,
}

#[derive(Serialize, Debug)]
#[serde(rename_all = "camelCase")]
struct Record {
    schema: &'static str,
    account: String,
    account_id: String,
    as_of: String,
    portfolio: Portfolio,
    /// Every transaction Public's history lists, oldest first.
    history: Vec<Transaction>,
    /// `order search`: the orders of the last 30 days (up to 500), as the
    /// pinned CLI states it.
    orders: Vec<Order>,
    tax_lots: TaxLots,
}

fn check(field: &str, value: &Option<String>, allowed: &[&str]) -> Result<(), String> {
    match value {
        Some(v) if !allowed.contains(&v.as_str()) => {
            Err(format!("{field}: {v:?} is not a value the pinned client names ({})", allowed.join(", ")))
        }
        _ => Ok(()),
    }
}

fn decimal(field: &str, v: &str) -> Result<(), String> {
    let s = v.strip_prefix('-').unwrap_or(v);
    let ok = !s.is_empty() && s.chars().all(|c| c.is_ascii_digit() || c == '.') && s.matches('.').count() <= 1;
    if ok { Ok(()) } else { Err(format!("{field}: {v:?} is not a decimal amount")) }
}

fn read<T: for<'a> Deserialize<'a>>(what: &str, path: &str) -> Result<T, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{what}: {path}: {e}"))?;
    serde_json::from_str(&text).map_err(|e| format!("{what}: {path}: {e}"))
}

fn build(account: &str, account_id: &str, as_of: &str, p: Portfolio, pages: Vec<HistoryPage>, o: Orders, t: TaxLots) -> Result<Record, String> {
    if p.account_id != account_id {
        return Err(format!("portfolio: account {} is not {account_id}", p.account_id));
    }
    for e in &p.equity {
        check("portfolio.equity.type", &Some(e.kind.clone()), EQUITY_TYPES)?;
        decimal("portfolio.equity.value", &e.value)?;
    }
    for x in &p.positions {
        check("portfolio.positions.instrument.type", &Some(x.instrument.kind.clone()), INSTRUMENT_TYPES)?;
        decimal("portfolio.positions.quantity", &x.quantity)?;
    }
    decimal("portfolio.buyingPower.buyingPower", &p.buying_power.buying_power)?;
    if let Some(c) = &p.cash {
        decimal("portfolio.cash", c)?;
    }
    let mut history: Vec<Transaction> = pages.into_iter().flat_map(|pg| pg.transactions.unwrap_or_default()).collect();
    for h in &history {
        check("history.type", &h.kind, HISTORY_TYPES)?;
        check("history.subType", &h.sub_type, HISTORY_SUB_TYPES)?;
        check("history.securityType", &h.security_type, HISTORY_SECURITY_TYPES)?;
        check("history.side", &h.side, SIDES)?;
        check("history.direction", &h.direction, DIRECTIONS)?;
        for (f, v) in [("netAmount", &h.net_amount), ("principalAmount", &h.principal_amount), ("fees", &h.fees)] {
            if let Some(v) = v {
                decimal(&format!("history.{f}"), v)?;
            }
        }
    }
    history.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
    let orders = o.orders.unwrap_or_default();
    for x in &orders {
        check("orders.status", &x.status, ORDER_STATUSES)?;
        check("orders.type", &x.kind, ORDER_TYPES)?;
        check("orders.side", &x.side, SIDES)?;
        if let Some(i) = &x.instrument {
            check("orders.instrument.type", &Some(i.kind.clone()), INSTRUMENT_TYPES)?;
        }
        for tr in x.trades.iter().flatten() {
            check("orders.trades.side", &tr.side, SIDES)?;
        }
    }
    for l in &t.lots {
        for (f, v) in [("quantity", &l.quantity), ("costBasis", &l.cost_basis), ("gainLoss", &l.gain_loss)] {
            decimal(&format!("taxLots.lots.{f}"), v)?;
        }
    }
    decimal("taxLots.totalProfitLoss", &t.total_profit_loss)?;
    Ok(Record {
        schema: "money.ledger.public/1",
        account: account.into(),
        account_id: account_id.into(),
        as_of: as_of.into(),
        portfolio: p,
        history,
        orders,
        tax_lots: t,
    })
}

fn run(args: &[String]) -> Result<(), String> {
    let [account, account_id, as_of, portfolio, history, orders, taxlots, out] = args else {
        return Err("usage: money-ledger ACCOUNT ACCOUNT-ID AS-OF PORTFOLIO.json HISTORY.jsonl ORDERS.json TAXLOTS.json OUT.json".into());
    };
    let p: Portfolio = read("portfolio show", portfolio)?;
    let text = fs::read_to_string(history).map_err(|e| format!("history list: {history}: {e}"))?;
    let mut pages = Vec::new();
    for (n, line) in text.lines().enumerate().filter(|(_, l)| !l.trim().is_empty()) {
        pages.push(serde_json::from_str::<HistoryPage>(line).map_err(|e| format!("history list: {history}:{}: {e}", n + 1))?);
    }
    let o: Orders = read("order search", orders)?;
    let t: TaxLots = read("taxlots list", taxlots)?;
    let record = build(account, account_id, as_of, p, pages, o, t)?;
    let json = serde_json::to_string_pretty(&record).map_err(|e| e.to_string())?;
    fs::write(out, json + "\n").map_err(|e| format!("{out}: {e}"))
}

fn main() -> std::process::ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("money-ledger: {e}");
            2.into()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty() -> (Portfolio, Orders, TaxLots) {
        (
            serde_json::from_str(include_str!("../../_test/public/portfolio.json")).unwrap(),
            serde_json::from_str(include_str!("../../_test/public/orders.json")).unwrap(),
            serde_json::from_str(include_str!("../../_test/public/taxlots.json")).unwrap(),
        )
    }

    #[test]
    fn empty_account_records() {
        let (p, o, t) = empty();
        let pages: Vec<HistoryPage> = include_str!("../../_test/public/history.jsonl")
            .lines()
            .map(|l| serde_json::from_str(l).unwrap())
            .collect();
        let r = build("public-mirazo", "5OI41709", "2026-11-04T02:40:00Z", p, pages, o, t).unwrap();
        assert!(r.history.is_empty() && r.orders.is_empty());
        assert_eq!(r.portfolio.cash.as_deref(), Some("0.00"));
    }

    #[test]
    fn unknown_sub_type_refused() {
        let (p, o, t) = empty();
        let page: HistoryPage = serde_json::from_str(
            r#"{"transactions":[{"id":"x","type":"MONEY_MOVEMENT","subType":"GIFT","netAmount":"1.00"}]}"#,
        )
        .unwrap();
        let e = build("public-mirazo", "5OI41709", "t", p, vec![page], o, t).unwrap_err();
        assert!(e.contains("history.subType"));
    }

    #[test]
    fn other_account_refused() {
        let (p, o, t) = empty();
        assert!(build("public-mirazo", "2OP05949", "t", p, vec![], o, t).is_err());
    }
}
