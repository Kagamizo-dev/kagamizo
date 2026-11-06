//! `trade-run`: the trading module's engine, ported from _trade.py and
//! _propose.py. The same commands, environment, files and JSON, so the Nix
//! wrapper (`trade`, modules/trading/strategies.nix) and the agents' daily
//! jobs are unchanged.
//!
//!   trade-run strategies                    the declared strategies
//!   trade-run account                       the BROKERAGE account's id
//!   trade-run bars SYMBOL STEP [PERIOD]     Public's bars as CSV
//!   trade-run propose STRATEGY [DATE] [--forecasts FILE]
//!   trade-run paper-day STRATEGY [DATE] [--forecasts FILE]
//!   trade-run paper-settle STRATEGY         settle the recorded paper days
//!   trade-run place PROPOSAL.json           the one spend
//!
//! The agent-option strategy turns the day's research decision into one
//! option order; the event-rule strategy prices every open weather contract
//! with the weather rules and proposes the best edge. Both go through
//! `admissible` (Kagamizo.Risk.admissible in _lean/Risk.lean) and Public's
//! preflight, which places nothing. Only `place` places, and only for a
//! live strategy, after the risk check and a fresh preflight.
//!
//! `backtest` and `paper` run NautilusTrader over bars; they stay with the
//! Python engine until they move onto the Rust crates (nautilus-probe).

use chrono::NaiveDate;
use kagamizo_public::client::{event_contract_order_body, option_order_body, Public};
use kagamizo_public::endpoints::{OrderStatus, SettledOutcome};
use kagamizo_public::types::OrderBody;
use kagamizo_weather::data::{Question, WeatherData};
use kagamizo_weather::live::{live_data, Source};
use kagamizo_weather::weather::{edge, parse_question, probability, round_to};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

// ── The declarations, as the wrapper renders them ─────────────────────────

#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "kebab-case")]
enum Kind {
    EmaCross,
    AgentOption,
    EventRule,
}

#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "kebab-case")]
enum Stage {
    Research,
    Backtest,
    Paper,
    Live,
}

impl Stage {
    fn name(self) -> &'static str {
        match self {
            Stage::Research => "research",
            Stage::Backtest => "backtest",
            Stage::Paper => "paper",
            Stage::Live => "live",
        }
    }
}

#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct OptionParams {
    expiry_days_min: i64,
    expiry_days_max: i64,
    min_abs_delta: f64,
}

#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct EventParams {
    category: String,
    subcategory: Option<String>,
    min_edge: f64,
    max_contracts: u32,
    questions: Vec<String>,
    source: String,
}

#[derive(Deserialize, Clone, Debug)]
struct Strategy {
    name: String,
    kind: Kind,
    backend: String,
    symbol: String,
    stage: Stage,
    decisions: Option<String>,
    option: Option<OptionParams>,
    event: Option<EventParams>,
}

/// trading.limits.<backend> (modules/trading/limits.nix).
#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct Limits {
    allowed: Vec<String>,
    daily_loss_stop_usd: f64,
    daily_take_profit_usd: f64,
    max_contract_price_usd: f64,
    max_open_positions: f64,
    max_premium_usd: f64,
}

/// Where the day stands (Kagamizo.Risk.Day): <decisions>/state.json.
#[derive(Clone, Debug)]
struct Day {
    open_positions: f64,
    loss_usd: f64,
    gain_usd: f64,
    /// As read, echoed in the output.
    raw: Map<String, Value>,
}

#[derive(Deserialize, Debug)]
struct Decision {
    decision: Option<String>,
    rationale: Option<Value>,
}

// ── Errors: a message, and the exit code _trade.py's die() used ──────────

struct Die(String, u8);

type R<T> = Result<T, Die>;

fn die<T>(msg: impl Into<String>) -> R<T> {
    Err(Die(msg.into(), 1))
}

fn usage<T>() -> R<T> {
    Err(Die(USAGE.into(), 2))
}

const USAGE: &str = "usage: trade <backtest STRATEGY BARS.csv | strategies | bars SYMBOL STEP [PERIOD] | paper STRATEGY [BARS.csv] [--all] | propose STRATEGY [DATE] [--forecasts FILE] | paper-day STRATEGY [DATE] [--forecasts FILE] | paper-settle STRATEGY | place PROPOSAL.json>";

// ── Reading the environment and the files ─────────────────────────────────

fn env_json(var: &str) -> R<Value> {
    std::env::var(var)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .ok_or_else(|| Die(format!("{var} is not set; run trade through its wrapper"), 2))
}

fn strategies_raw() -> R<Map<String, Value>> {
    match env_json("TRADE_STRATEGIES")? {
        Value::Object(m) => Ok(m),
        _ => Err(Die("TRADE_STRATEGIES is not set; run trade through its wrapper".into(), 2)),
    }
}

fn declared(name: &str) -> R<Strategy> {
    let all = strategies_raw()?;
    let raw = all.get(name).ok_or_else(|| {
        let names: Vec<&str> = all.keys().map(String::as_str).collect();
        Die(format!("no strategy {name}; declared: {}", names.join(", ")), 2)
    })?;
    serde_json::from_value(raw.clone()).map_err(|e| Die(format!("TRADE_STRATEGIES.{name}: {e}"), 2))
}

/// The backend's limits, typed, and as declared (echoed in the output).
fn limits_for(decl: &Strategy) -> R<(Limits, Value)> {
    let all = env_json("TRADE_LIMITS")?;
    let raw = all
        .get(&decl.backend)
        .cloned()
        .ok_or_else(|| Die(format!("no trading.limits.{}", decl.backend), 2))?;
    let typed = serde_json::from_value(raw.clone()).map_err(|e| Die(format!("trading.limits.{}: {e}", decl.backend), 2))?;
    Ok((typed, raw))
}

fn decisions_dir(decl: &Strategy) -> R<PathBuf> {
    decl.decisions
        .as_ref()
        .map(PathBuf::from)
        .ok_or_else(|| Die(format!("{} declares no decisions directory", decl.name), 2))
}

fn read_json(path: &Path) -> R<Value> {
    let text = std::fs::read_to_string(path).map_err(|e| Die(format!("{}: {e}", path.display()), 1))?;
    serde_json::from_str(&text).map_err(|e| Die(format!("{}: {e}", path.display()), 1))
}

fn day_state(decl: &Strategy) -> R<Day> {
    let path = decisions_dir(decl)?.join("state.json");
    let mut raw = Map::new();
    raw.insert("openPositions".into(), json!(0));
    raw.insert("lossUsd".into(), json!(0));
    raw.insert("gainUsd".into(), json!(0));
    if path.exists() {
        if let Value::Object(m) = read_json(&path)? {
            raw.extend(m);
        }
    }
    let num = |k: &str| raw.get(k).and_then(Value::as_f64).unwrap_or(0.0);
    Ok(Day { open_positions: num("openPositions"), loss_usd: num("lossUsd"), gain_usd: num("gainUsd"), raw: raw.clone() })
}

fn decision_for(decl: &Strategy, date: NaiveDate) -> R<Decision> {
    let path = decisions_dir(decl)?.join(date.to_string()).join(format!("{}.json", decl.symbol));
    if !path.exists() {
        return die(format!("no research decision at {}", path.display()));
    }
    serde_json::from_value(read_json(&path)?).map_err(|e| Die(format!("{}: {e}", path.display()), 1))
}

fn forecasts_for(params: &EventParams, today: NaiveDate, path: Option<&str>) -> R<WeatherData> {
    if let Some(p) = path {
        let raw = read_json(Path::new(p))?;
        if raw.get("cities").is_none() {
            return die(format!("{p}: not a forecasts file (no cities)"));
        }
        return serde_json::from_value(raw).map_err(|e| Die(format!("{p}: {e}"), 1));
    }
    let source: Source = params.source.parse().map_err(|e: String| Die(e, 1))?;
    live_data(today, source).map_err(|e| Die(format!("fetching forecasts from {}: {e}", params.source), 1))
}

// ── Numbers as Python prints them ─────────────────────────────────────────

/// A declared number as `f"{x}"` prints it: 25, not 25.0.
fn num(v: f64) -> String {
    if v.fract() == 0.0 && v.abs() < 1e15 {
        format!("{}", v as i64)
    } else {
        format!("{v}")
    }
}

fn round2(x: f64) -> f64 {
    round_to(x, 2)
}

fn round4(x: f64) -> f64 {
    round_to(x, 4)
}

// ── The risk rule and the preflight ───────────────────────────────────────

/// Mirrors Kagamizo.Risk.admissible; the reasons are for the owner.
fn admissible(l: &Limits, day: &Day, kind: &str, max_loss_usd: f64) -> (bool, Vec<String>) {
    let mut why = Vec::new();
    if !l.allowed.iter().any(|k| k == kind) {
        why.push(format!("{kind} is not an allowed kind ({})", l.allowed.join(", ")));
    }
    if max_loss_usd > l.max_premium_usd {
        why.push(format!("worst case ${max_loss_usd:.2} is over the ${} cap", num(l.max_premium_usd)));
    }
    if day.open_positions >= l.max_open_positions {
        why.push(format!(
            "{} position(s) open; the limit is {}",
            num(day.open_positions),
            num(l.max_open_positions)
        ));
    }
    if day.loss_usd >= l.daily_loss_stop_usd {
        why.push(format!("the day has lost ${:.2}; the stop is ${}", day.loss_usd, num(l.daily_loss_stop_usd)));
    }
    if day.gain_usd >= l.daily_take_profit_usd {
        why.push(format!(
            "the day has gained ${:.2}; the take-profit is ${}",
            day.gain_usd,
            num(l.daily_take_profit_usd)
        ));
    }
    (why.is_empty(), why)
}

/// Public's error, split as _public.PublicError carries it: the HTTP
/// status and the body.
fn public_error(e: &str) -> (Option<u32>, String) {
    match e.split_once(": HTTP ") {
        Some((_, rest)) => {
            let (status, body) = rest.split_once(' ').unwrap_or((rest, ""));
            (status.parse().ok(), body.to_string())
        }
        None => (None, e.to_string()),
    }
}

/// The proposal with Public's answer, when it is admissible.
fn preflighted(mut proposal: Map<String, Value>, order: &OrderBody, api: &mut Public) -> Map<String, Value> {
    if proposal.get("admissible") == Some(&Value::Bool(true)) {
        let body = serde_json::to_string(order).expect("an order body serialises");
        match api.preflight(&body) {
            Ok(p) => {
                proposal.insert("preflight".into(), json!(p));
                proposal.insert("accepted".into(), json!(true));
            }
            Err(e) => {
                let (status, body) = public_error(&e);
                proposal.insert("accepted".into(), json!(false));
                proposal.insert("refused_by".into(), json!("public"));
                proposal.insert("status".into(), json!(status));
                proposal.insert("reason".into(), json!(body));
            }
        }
    }
    proposal
}

fn api_die(e: String) -> Die {
    Die(e, 1)
}

// ── The agent-option strategy ─────────────────────────────────────────────

/// BUY means a call, SELL a put, HOLD no trade.
fn option_kind(decision: Option<&str>) -> Option<(&'static str, &'static str)> {
    match decision {
        Some("BUY") => Some(("C", "long-call")),
        Some("SELL") => Some(("P", "long-put")),
        _ => None,
    }
}

fn pick_expiration(expirations: &[String], today: NaiveDate, lo: i64, hi: i64) -> Option<(String, i64)> {
    let mut sorted = expirations.to_vec();
    sorted.sort();
    sorted.into_iter().find_map(|e| {
        let d = NaiveDate::parse_from_str(&e, "%Y-%m-%d").ok()?;
        let days = (d - today).num_days();
        (lo <= days && days <= hi).then_some((e, days))
    })
}

struct OptionContract {
    symbol: String,
    strike: f64,
    ask: f64,
    bid: f64,
    delta: f64,
}

/// Each call (or put) with its ask, strike and delta, greeks fetched when
/// the chain carries none.
fn contracts(chain: &kagamizo_public::types::OptionChainResponse, api: &mut Public, side: &str) -> R<Vec<OptionContract>> {
    let quotes = if side == "C" { &chain.calls } else { &chain.puts };
    let chain_delta = |q: &kagamizo_public::types::OptionQuote| {
        q.option_details.as_ref().and_then(|d| d.greeks.as_ref()).and_then(|g| g.delta)
    };
    let missing: Vec<String> =
        quotes.iter().filter(|q| chain_delta(q).is_none()).map(|q| q.instrument.symbol.clone()).collect();
    let fetched = if missing.is_empty() { HashMap::new() } else { api.greeks(missing).map_err(api_die)? };
    let mut out = Vec::new();
    for q in quotes {
        let sym = &q.instrument.symbol;
        let delta = chain_delta(q).or_else(|| fetched.get(sym).and_then(|g| g.get("delta").copied().flatten()));
        let (Some(delta), Ok(ask)) = (delta, q.ask.parse::<f64>()) else { continue };
        if q.ask.is_empty() {
            continue;
        }
        out.push(OptionContract {
            symbol: sym.clone(),
            strike: q.option_details.as_ref().and_then(|d| d.strike_price.parse().ok()).unwrap_or(0.0),
            ask,
            bid: q.bid.parse().unwrap_or(0.0),
            delta,
        });
    }
    Ok(out)
}

fn propose_option(
    decl: &Strategy,
    (limits, limits_raw): &(Limits, Value),
    decision: &Decision,
    day: &Day,
    api: &mut Public,
    today: NaiveDate,
) -> R<Map<String, Value>> {
    let params = decl.option.as_ref().ok_or_else(|| Die(format!("{} declares no option parameters", decl.name), 2))?;
    let quantity = 1u32;
    let mut out = Map::new();
    out.insert("strategy".into(), json!(decl.name));
    out.insert("symbol".into(), json!(decl.symbol));
    out.insert("as_of".into(), json!(today.to_string()));
    out.insert("decision".into(), json!(decision.decision));
    out.insert("rationale".into(), decision.rationale.clone().unwrap_or(Value::Null));
    out.insert("limits".into(), limits_raw.clone());
    out.insert("day".into(), Value::Object(day.raw.clone()));
    out.insert("proposal".into(), Value::Null);
    let Some((side, kind)) = option_kind(decision.decision.as_deref()) else {
        out.insert("why".into(), json!(format!("decision {}: no trade", decision.decision.as_deref().unwrap_or("None"))));
        return Ok(out);
    };
    let expirations = api.option_expirations(&decl.symbol, "EQUITY").map_err(api_die)?;
    let Some((expiration, days)) = pick_expiration(&expirations, today, params.expiry_days_min, params.expiry_days_max)
    else {
        out.insert(
            "why".into(),
            json!(format!("no expiration {}..{} days out", params.expiry_days_min, params.expiry_days_max)),
        );
        return Ok(out);
    };
    let chain = api.option_chain(&decl.symbol, &expiration, "EQUITY").map_err(api_die)?;
    let fitting: Vec<OptionContract> = contracts(&chain, api, side)?
        .into_iter()
        .filter(|c| c.ask * 100.0 * quantity as f64 <= limits.max_premium_usd && c.delta.abs() >= params.min_abs_delta)
        .collect();
    // The cheapest ask, then the largest |delta|.
    let Some(pick) = fitting.iter().min_by(|a, b| {
        a.ask.partial_cmp(&b.ask).unwrap().then(b.delta.abs().partial_cmp(&a.delta.abs()).unwrap())
    }) else {
        out.insert(
            "why".into(),
            json!(format!(
                "no {} expiring {expiration} fits: ask × 100 ≤ ${} and |delta| ≥ {}",
                if side == "P" { "put" } else { "call" },
                num(limits.max_premium_usd),
                params.min_abs_delta
            )),
        );
        return Ok(out);
    };
    let max_loss = round2(pick.ask * 100.0 * quantity as f64);
    let (ok, why) = admissible(limits, day, kind, max_loss);
    let order = option_order_body(
        &pick.symbol,
        "BUY",
        &pick.ask.to_string(),
        &quantity.to_string(),
        "OPEN",
        Some(&uuid::Uuid::new_v4().to_string()),
    )
    .map_err(api_die)?;
    let mut p = Map::new();
    p.insert("kind".into(), json!(kind));
    p.insert(
        "contract".into(),
        json!({"symbol": pick.symbol, "strike": pick.strike, "ask": pick.ask, "bid": pick.bid, "delta": pick.delta}),
    );
    p.insert("expiration".into(), json!(expiration));
    p.insert("days_out".into(), json!(days));
    p.insert("quantity".into(), json!(quantity));
    p.insert("max_loss_usd".into(), json!(max_loss));
    p.insert("admissible".into(), json!(ok));
    p.insert("refused_because".into(), json!(why));
    p.insert("order".into(), json!(order));
    out.insert("proposal".into(), Value::Object(preflighted(p, &order, api)));
    Ok(out)
}

// ── The event-rule strategy ───────────────────────────────────────────────

/// A contract's ask, when it is a price strictly between 0 and 1.
fn ask_of(ask: &str) -> Option<f64> {
    let a: f64 = ask.parse().ok()?;
    (0.0 < a && a < 1.0).then_some(a)
}

fn question_json(q: &Question) -> Value {
    json!({
        "shape": q.shape,
        "city": q.city,
        "variable": q.variable,
        "low": q.low,
        "high": q.high,
        "start": format!("{}-{:02}-{:02}", q.year, q.month, q.start_day),
        "end": format!("{}-{:02}-{:02}", q.year, q.month, q.end_day),
    })
}

/// Every open contract in the declared category with a question the
/// rules answer, its probability, price and edge; and what was skipped.
fn event_candidates(
    params: &EventParams,
    data: &WeatherData,
    api: &mut Public,
    today: NaiveDate,
) -> R<(Vec<Map<String, Value>>, Vec<Value>)> {
    let (mut considered, mut skipped) = (Vec::new(), Vec::new());
    let today_s = today.to_string();
    let events = api
        .event_contracts(20, Some(&params.category), params.subcategory.as_deref(), &vec![], Some(false), None, None, &vec![], None)
        .map_err(api_die)?;
    for ev in events {
        if ev.resolved || ev.halted {
            skipped.push(json!({"event": ev.event_symbol, "why": "resolved or halted"}));
            continue;
        }
        let details = api.event_contract_details(&ev.event_symbol, true).map_err(api_die)?;
        for oc in &details.outcomes {
            let mut place = Map::new();
            place.insert("event".into(), json!(ev.event_symbol));
            place.insert("outcome".into(), json!(oc.outcome_id));
            place.insert("title".into(), json!(format!("{} / {}", details.title, oc.title)));
            let skip = |why: String| {
                let mut s = place.clone();
                s.insert("why".into(), json!(why));
                Value::Object(s)
            };
            if oc.state != "STATE_OPEN" || oc.trading != "BUY_AND_SELL" {
                skipped.push(skip(format!("{}, trading {}", oc.state, oc.trading)));
                continue;
            }
            let close = if oc.timeline.close_time.is_empty() { &ev.resolution_time } else { &oc.timeline.close_time };
            let close = (!close.is_empty()).then_some(close.as_str());
            let Some(q) = parse_question(&details.title, &oc.title, &today_s, close) else {
                skipped.push(skip("a question shape the rules do not handle".into()));
                continue;
            };
            if !params.questions.contains(&q.shape) {
                skipped.push(skip(format!("{} is not a declared question shape", q.shape)));
                continue;
            }
            let Some(p) = probability(&q, data, &today_s) else {
                let qj = question_json(&q);
                skipped.push(skip(format!(
                    "no data for {} over {}..{}",
                    q.city,
                    qj["start"].as_str().unwrap_or(""),
                    qj["end"].as_str().unwrap_or("")
                )));
                continue;
            };
            for c in &oc.contracts {
                let side = c.predicted_outcome.as_str();
                let Some(ask) = ask_of(&c.ask).filter(|_| side == "YES" || side == "NO") else {
                    let mut s = place.clone();
                    s.insert("contract".into(), json!(c.symbol));
                    s.insert("why".into(), json!("no ask between 0 and 1"));
                    skipped.push(Value::Object(s));
                    continue;
                };
                let side_p = if side == "YES" { p } else { 1.0 - p };
                let mut cand = place.clone();
                cand.insert("contract".into(), json!(c.symbol));
                cand.insert("side".into(), json!(side));
                cand.insert("question".into(), question_json(&q));
                cand.insert("probability".into(), json!(round4(side_p)));
                cand.insert("ask".into(), json!(ask));
                cand.insert("edge".into(), json!(edge(side_p, ask)));
                considered.push(cand);
            }
        }
    }
    Ok((considered, skipped))
}

fn f(c: &Map<String, Value>, k: &str) -> f64 {
    c.get(k).and_then(Value::as_f64).unwrap_or(0.0)
}

fn propose_event(
    decl: &Strategy,
    (limits, limits_raw): &(Limits, Value),
    data: &WeatherData,
    day: &Day,
    api: &mut Public,
    today: NaiveDate,
) -> R<Map<String, Value>> {
    let params = decl.event.as_ref().ok_or_else(|| Die(format!("{} declares no event parameters", decl.name), 2))?;
    let mut out = Map::new();
    out.insert("strategy".into(), json!(decl.name));
    out.insert("as_of".into(), json!(today.to_string()));
    out.insert("category".into(), json!(params.category));
    out.insert("subcategory".into(), json!(params.subcategory));
    out.insert("data_as_of".into(), json!(data.as_of));
    out.insert("data_source".into(), json!(data.source));
    out.insert("limits".into(), limits_raw.clone());
    out.insert("day".into(), Value::Object(day.raw.clone()));
    out.insert("proposal".into(), Value::Null);
    let (considered, skipped) = event_candidates(params, data, api, today)?;
    let mut by_edge = considered.clone();
    by_edge.sort_by(|a, b| f(b, "edge").partial_cmp(&f(a, "edge")).unwrap());
    out.insert("considered".into(), json!(by_edge));
    out.insert("skipped".into(), json!(skipped));
    // The best edge at or above minEdge; ties to the cheaper ask, then the
    // first considered (Python's max).
    let mut pick: Option<&Map<String, Value>> = None;
    for c in considered.iter().filter(|c| f(c, "edge") >= params.min_edge) {
        let better = match pick {
            None => true,
            Some(p) => (f(c, "edge"), -f(c, "ask")) > (f(p, "edge"), -f(p, "ask")),
        };
        if better {
            pick = Some(c);
        }
    }
    let Some(pick) = pick else {
        out.insert(
            "why".into(),
            json!(format!("no contract with edge ≥ {} among {} considered", params.min_edge, considered.len())),
        );
        return Ok(out);
    };
    let ask = f(pick, "ask");
    let contract = pick["contract"].as_str().unwrap_or_default().to_string();
    let quantity = (params.max_contracts as f64)
        .min((limits.max_contract_price_usd / ask).floor())
        .min((limits.max_premium_usd / ask).floor());
    if quantity < 1.0 {
        out.insert(
            "why".into(),
            json!(format!(
                "{contract} at ${ask:.2} does not fit one contract within ${}",
                num(limits.max_contract_price_usd)
            )),
        );
        return Ok(out);
    }
    let quantity = quantity as u32;
    let cost = round2(ask * quantity as f64);
    let kind = if pick["side"] == "YES" { "event-yes" } else { "event-no" };
    let (ok, why) = admissible(limits, day, kind, cost);
    let order = event_contract_order_body(
        &contract,
        "BUY",
        &ask.to_string(),
        &quantity.to_string(),
        Some(&uuid::Uuid::new_v4().to_string()),
    )
    .map_err(api_die)?;
    let mut p = Map::new();
    p.insert("kind".into(), json!(kind));
    p.insert("contract".into(), Value::Object(pick.clone()));
    p.insert("quantity".into(), json!(quantity));
    p.insert("max_loss_usd".into(), json!(cost));
    p.insert("admissible".into(), json!(ok));
    p.insert("refused_because".into(), json!(why));
    p.insert("order".into(), json!(order));
    out.insert("proposal".into(), Value::Object(preflighted(p, &order, api)));
    Ok(out)
}

// ── The commands ──────────────────────────────────────────────────────────

fn emit(v: &Value) {
    println!("{}", serde_json::to_string_pretty(v).expect("JSON serialises"));
}

fn today() -> NaiveDate {
    chrono::Local::now().date_naive()
}

fn propose(name: &str, date: Option<&str>, record: bool, forecasts: Option<&str>) -> R<()> {
    let decl = declared(name)?;
    let today = match date {
        Some(d) => NaiveDate::parse_from_str(d, "%Y-%m-%d").map_err(|e| Die(format!("{d}: {e}"), 2))?,
        None => today(),
    };
    let mut api = Public::new(None, None);
    let (mut out, record_as) = match decl.kind {
        Kind::AgentOption => {
            if forecasts.is_some() {
                return die(format!("{name} is agent-option; --forecasts is for an event-rule strategy"));
            }
            let out = propose_option(&decl, &limits_for(&decl)?, &decision_for(&decl, today)?, &day_state(&decl)?, &mut api, today)?;
            (out, decl.symbol.clone())
        }
        Kind::EventRule => {
            let params = decl.event.as_ref().ok_or_else(|| Die(format!("{name} declares no event parameters"), 2))?;
            let data = forecasts_for(params, today, forecasts)?;
            let out = propose_event(&decl, &limits_for(&decl)?, &data, &day_state(&decl)?, &mut api, today)?;
            (out, name.to_string())
        }
        Kind::EmaCross => {
            return die(format!("{name} is ema-cross, which proposes nothing (agent-option and event-rule do)"));
        }
    };
    if record {
        let folder = decisions_dir(&decl)?.join("paper");
        std::fs::create_dir_all(&folder).map_err(|e| Die(format!("{}: {e}", folder.display()), 1))?;
        let path = folder.join(format!("{today}-{record_as}.json"));
        let text = serde_json::to_string_pretty(&out).expect("JSON serialises");
        std::fs::write(&path, text).map_err(|e| Die(format!("{}: {e}", path.display()), 1))?;
        out.insert("recorded".into(), json!(true));
    }
    emit(&Value::Object(out));
    Ok(())
}

/// The spend. The proposal is checked again against the limits and the
/// day, preflighted again, placed, then read back until it is no longer
/// NEW. The day's state records the open position.
fn place(proposal_path: &str) -> R<()> {
    let proposal = read_json(Path::new(proposal_path))?;
    let name = proposal["strategy"].as_str().ok_or_else(|| Die("the proposal names no strategy".into(), 1))?;
    let decl = declared(name)?;
    // The stage is the declaration's (modules/trading/stages.nix, proved by
    // Lean to carry its evidence): only a live strategy places.
    if decl.stage != Stage::Live {
        return die(format!("{name} is at stage {}, not live: nothing is placed", decl.stage.name()));
    }
    let p = proposal.get("proposal").filter(|p| !p.is_null()).ok_or_else(|| Die("the proposal holds no order".into(), 1))?;
    let (limits, _) = limits_for(&decl)?;
    let day = day_state(&decl)?;
    let kind = p["kind"].as_str().unwrap_or_default();
    let (ok, why) = admissible(&limits, &day, kind, p["max_loss_usd"].as_f64().unwrap_or(f64::INFINITY));
    if !ok {
        return die(format!("refused: {}", why.join("; ")));
    }
    let order: OrderBody =
        serde_json::from_value(p["order"].clone()).map_err(|e| Die(format!("the proposal's order: {e}"), 1))?;
    let body = serde_json::to_string(&order).expect("an order body serialises");
    // The one client allowed an order (kagamizo_public::endpoints::Bound).
    let mut api = Public::new(None, None).placer();
    let preflight = api.preflight(&body).map_err(|e| Die(format!("Public refused the preflight: {e}"), 1))?;
    // The one call that moves money.
    let placed = api.place(&body).map_err(|e| Die(format!("Public refused the order: {e}"), 1))?;
    let order_id = if placed.order_id.is_empty() { order.order_id.clone().unwrap_or_default() } else { placed.order_id.clone() };
    // Read back until the order has ended (OrderStatus::terminal): a partial
    // fill is still working. At most a minute; an order still working then
    // is reported as it stands.
    let mut status = None;
    for _ in 0..20 {
        let s = api.order(&order_id).map_err(api_die)?;
        let ended = s.status.as_deref().and_then(OrderStatus::parse).is_some_and(OrderStatus::terminal);
        status = Some(s);
        if ended {
            break;
        }
        std::thread::sleep(std::time::Duration::from_secs(3));
    }
    let mut day_raw = day.raw.clone();
    day_raw.insert("openPositions".into(), json!(day.open_positions as i64 + 1));
    let dir = decisions_dir(&decl)?;
    std::fs::create_dir_all(&dir).map_err(|e| Die(format!("{}: {e}", dir.display()), 1))?;
    let state = dir.join("state.json");
    std::fs::write(&state, serde_json::to_string_pretty(&day_raw).expect("JSON serialises"))
        .map_err(|e| Die(format!("{}: {e}", state.display()), 1))?;
    emit(&json!({
        "strategy": name, "order_id": order_id, "preflight": preflight,
        "placed": placed, "status": status, "day": day_raw,
    }));
    Ok(())
}


// ── Paper trading: settling the recorded days ─────────────────────────────

/// How one recorded paper day stands.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum PaperStatus {
    /// Nothing proposed, or the proposal was not admissible.
    NoTrade,
    /// Proposed and admissible; the contract has not settled.
    Open,
    Won,
    Lost,
    /// Settled neither YES nor NO (SETTLED_OUTCOME_OTHER): no P&L.
    Void,
}

impl PaperStatus {
    fn name(self) -> &'static str {
        match self {
            PaperStatus::NoTrade => "no-trade",
            PaperStatus::Open => "open",
            PaperStatus::Won => "won",
            PaperStatus::Lost => "lost",
            PaperStatus::Void => "void",
        }
    }
}

/// An event contract bought at `ask` pays 1 - ask a contract if its side
/// settles true and loses the ask if not.
fn settle_event(side: &str, ask: f64, quantity: f64, settled: SettledOutcome) -> (PaperStatus, f64) {
    let yes = match settled {
        SettledOutcome::SettledOutcomeUnspecified => return (PaperStatus::Open, 0.0),
        SettledOutcome::SettledOutcomeOther => return (PaperStatus::Void, 0.0),
        SettledOutcome::SettledOutcomeYes => true,
        SettledOutcome::SettledOutcomeNo => false,
    };
    if (side == "YES") == yes {
        (PaperStatus::Won, round2(quantity * (1.0 - ask)))
    } else {
        (PaperStatus::Lost, round2(-quantity * ask))
    }
}

/// Peak-to-trough of the equity curve from the seed, as a percent of the
/// peak.
fn max_drawdown_pct(seed: f64, pnls: &[f64]) -> f64 {
    let (mut equity, mut peak, mut worst) = (seed, seed, 0.0f64);
    for p in pnls {
        equity += p;
        peak = peak.max(equity);
        if peak > 0.0 {
            worst = worst.max((peak - equity) / peak * 100.0);
        }
    }
    round2(worst)
}

/// Every recorded paper day of the strategy, settled where Public has
/// settled its contract; the ledger written beside the records.
fn paper_settle(name: &str) -> R<()> {
    let decl = declared(name)?;
    if decl.kind != Kind::EventRule {
        return die(format!(
            "{name} is {:?}: paper-settle settles event contracts; an option settles at expiry, which it does not price yet",
            decl.kind
        ));
    }
    let (_, limits_raw) = limits_for(&decl)?;
    let seed = limits_raw.get("seedUsd").and_then(Value::as_f64).unwrap_or(0.0);
    let folder = decisions_dir(&decl)?.join("paper");
    let suffix = format!("-{name}.json");
    let mut records: Vec<PathBuf> = std::fs::read_dir(&folder)
        .map(|d| d.filter_map(|e| e.ok().map(|e| e.path())).collect())
        .unwrap_or_default();
    records.retain(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.ends_with(&suffix) && n.len() == 10 + suffix.len()));
    records.sort();
    let mut api = Public::new(None, None);
    let mut details: HashMap<String, kagamizo_public::types::EventDetailsResponse> = HashMap::new();
    let (mut days, mut pnls) = (Vec::new(), Vec::new());
    let (mut trades, mut won, mut lost, mut open) = (0u32, 0u32, 0u32, 0u32);
    for path in &records {
        let rec = read_json(path)?;
        let date = rec["as_of"].as_str().unwrap_or_default().to_string();
        let p = &rec["proposal"];
        if p.is_null() || p["admissible"] != Value::Bool(true) {
            days.push(json!({"date": date, "status": PaperStatus::NoTrade.name(), "why": rec.get("why").cloned().unwrap_or(json!(p["refused_because"]))}));
            continue;
        }
        trades += 1;
        let c = &p["contract"];
        let (event, outcome, side) = (c["event"].as_str().unwrap_or(""), c["outcome"].as_str().unwrap_or(""), c["side"].as_str().unwrap_or(""));
        let (ask, quantity) = (c["ask"].as_f64().unwrap_or(0.0), p["quantity"].as_f64().unwrap_or(0.0));
        if !details.contains_key(event) {
            details.insert(event.to_string(), api.event_contract_details(event, true).map_err(api_die)?);
        }
        let settled = details[event]
            .outcomes
            .iter()
            .find(|o| o.outcome_id == outcome)
            .and_then(|o| SettledOutcome::parse(&o.settled_outcome))
            .unwrap_or(SettledOutcome::SettledOutcomeUnspecified);
        let (status, pnl) = settle_event(side, ask, quantity, settled);
        match status {
            PaperStatus::Won => won += 1,
            PaperStatus::Lost => lost += 1,
            PaperStatus::Open => open += 1,
            _ => {}
        }
        if matches!(status, PaperStatus::Won | PaperStatus::Lost) {
            pnls.push(pnl);
        }
        days.push(json!({"date": date, "status": status.name(), "contract": c["contract"], "side": side,
            "ask": ask, "quantity": quantity, "pnl_usd": pnl}));
    }
    let pnl: f64 = round2(pnls.iter().sum());
    let settled = won + lost;
    let ledger = json!({
        "strategy": name,
        "seed_usd": seed,
        "days": records.len(),
        "trades": trades,
        "settled": settled,
        "open": open,
        "won": won,
        "lost": lost,
        "pnl_usd": pnl,
        "hit_rate": if settled > 0 { round4(won as f64 / settled as f64) } else { 0.0 },
        "max_drawdown_pct": max_drawdown_pct(seed, &pnls),
        "from": days.first().map(|d| d["date"].clone()).unwrap_or(Value::Null),
        "to": days.last().map(|d| d["date"].clone()).unwrap_or(Value::Null),
        "record": days,
    });
    let out = folder.join(format!("ledger-{name}.json"));
    std::fs::create_dir_all(&folder).map_err(|e| Die(format!("{}: {e}", folder.display()), 1))?;
    std::fs::write(&out, serde_json::to_string_pretty(&ledger).expect("JSON serialises"))
        .map_err(|e| Die(format!("{}: {e}", out.display()), 1))?;
    emit(&ledger);
    Ok(())
}

fn bars(symbol: &str, step: &str, period: Option<&str>) -> R<()> {
    let rows = Public::new(None, None).bars(symbol, step, period, "EQUITY", "regularMarket").map_err(api_die)?;
    println!("timestamp,open,high,low,close,volume");
    for r in rows {
        println!("{},{},{},{},{},{}", r.timestamp, r.open, r.high, r.low, r.close, r.volume);
    }
    Ok(())
}

/// STRATEGY [DATE] [--forecasts FILE].
fn propose_args(args: &[String]) -> R<(String, Option<String>, Option<String>)> {
    let (mut rest, mut forecasts) = (Vec::new(), None);
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == "--forecasts" {
            match (it.next(), &forecasts) {
                (Some(f), None) => forecasts = Some(f.clone()),
                _ => return usage(),
            }
        } else {
            rest.push(a.clone());
        }
    }
    match rest.len() {
        1 => Ok((rest[0].clone(), None, forecasts)),
        2 => Ok((rest[0].clone(), Some(rest[1].clone()), forecasts)),
        _ => usage(),
    }
}

fn run(args: &[String]) -> R<()> {
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    match a.as_slice() {
        ["strategies"] => {
            emit(&Value::Object(strategies_raw()?));
            Ok(())
        }
        ["account"] => {
            // The brokerage account's id (an identifier, not a secret).
            println!("{}", Public::new(None, None).account().map_err(api_die)?);
            Ok(())
        }
        ["bars", symbol, step] => bars(symbol, step, None),
        ["bars", symbol, step, period] => bars(symbol, step, Some(period)),
        [cmd @ ("propose" | "paper-day"), rest @ ..] if !rest.is_empty() => {
            let (name, date, forecasts) = propose_args(&args[1..])?;
            propose(&name, date.as_deref(), *cmd == "paper-day", forecasts.as_deref())
        }
        ["place", path] => place(path),
        ["paper-settle", name] => paper_settle(name),
        ["backtest", ..] | ["paper", ..] => {
            die("backtest and paper run on the Python engine until they move onto NautilusTrader's Rust crates")
        }
        _ => usage(),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(Die(msg, code)) => {
            eprintln!("trade: {msg}");
            ExitCode::from(code)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn limits() -> Limits {
        Limits {
            allowed: vec!["long-call".into(), "event-yes".into()],
            daily_loss_stop_usd: 25.0,
            daily_take_profit_usd: 25.0,
            max_contract_price_usd: 10.0,
            max_open_positions: 1.0,
            max_premium_usd: 25.0,
        }
    }

    fn day(open: f64, loss: f64, gain: f64) -> Day {
        Day { open_positions: open, loss_usd: loss, gain_usd: gain, raw: Map::new() }
    }

    #[test]
    fn admissible_names_every_reason() {
        let (ok, why) = admissible(&limits(), &day(1.0, 25.0, 25.0), "long-put", 30.0);
        assert!(!ok);
        assert_eq!(
            why,
            vec![
                "long-put is not an allowed kind (long-call, event-yes)",
                "worst case $30.00 is over the $25 cap",
                "1 position(s) open; the limit is 1",
                "the day has lost $25.00; the stop is $25",
                "the day has gained $25.00; the take-profit is $25",
            ]
        );
        assert!(admissible(&limits(), &day(0.0, 0.0, 0.0), "event-yes", 2.0).0);
    }

    #[test]
    fn expirations_pick_the_nearest_in_the_window() {
        let e: Vec<String> = ["2026-11-20", "2026-11-06", "2026-11-13"].map(String::from).to_vec();
        let today = NaiveDate::from_ymd_opt(2026, 11, 4).unwrap();
        assert_eq!(pick_expiration(&e, today, 7, 21), Some(("2026-11-13".into(), 9)));
        assert_eq!(pick_expiration(&e, today, 30, 40), None);
    }

    #[test]
    fn public_errors_split_into_status_and_body() {
        assert_eq!(public_error("POST /x: HTTP 400 sell side refused"), (Some(400), "sell side refused".into()));
        assert_eq!(public_error("connect failed"), (None, "connect failed".into()));
    }

    #[test]
    fn asks_are_prices_strictly_inside_zero_and_one() {
        assert_eq!(ask_of("0.20"), Some(0.2));
        assert_eq!(ask_of("1.00"), None);
        assert_eq!(ask_of(""), None);
    }

    #[test]
    fn event_contracts_settle_on_their_side() {
        assert_eq!(settle_event("YES", 0.2, 10.0, SettledOutcome::SettledOutcomeYes), (PaperStatus::Won, 8.0));
        assert_eq!(settle_event("NO", 0.3, 10.0, SettledOutcome::SettledOutcomeYes), (PaperStatus::Lost, -3.0));
        assert_eq!(settle_event("YES", 0.2, 10.0, SettledOutcome::SettledOutcomeUnspecified).0, PaperStatus::Open);
        assert_eq!(settle_event("YES", 0.2, 10.0, SettledOutcome::SettledOutcomeOther), (PaperStatus::Void, 0.0));
    }

    #[test]
    fn drawdown_is_from_the_peak() {
        // 100 -> 110 -> 99 -> 104: the trough is 11 below the 110 peak.
        assert_eq!(max_drawdown_pct(100.0, &[10.0, -11.0, 5.0]), 10.0);
        assert_eq!(max_drawdown_pct(100.0, &[]), 0.0);
    }

    #[test]
    fn numbers_print_as_python_prints_them() {
        assert_eq!(num(25.0), "25");
        assert_eq!(num(0.15), "0.15");
    }
}
