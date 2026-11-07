//! checks.trading-backtest's scenarios (modules/trading/strategies.nix),
//! run against public-stub: every proposal, the stage gate, placing and
//! reading back, and the paper day. Each test has its own directory, so
//! one test's day state never leaks into another's.
//!
//! The stub is the workspace's public-stub binary: PUBLIC_STUB_BIN, or
//! beside this package's own binary in the same target directory.

use serde_json::{json, Value};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};

struct Stub {
    child: Child,
    url: String,
}

impl Drop for Stub {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn stub() -> Stub {
    let bin = std::env::var("PUBLIC_STUB_BIN").map(PathBuf::from).unwrap_or_else(|_| {
        Path::new(env!("CARGO_BIN_EXE_trade-run")).with_file_name("public-stub")
    });
    let mut child = Command::new(&bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap_or_else(|e| panic!("{}: {e}", bin.display()));
    let mut out = child.stdout.take().expect("stdout");
    let mut line = Vec::new();
    let mut b = [0u8; 1];
    while out.read(&mut b).unwrap_or(0) == 1 && b[0] != b'\n' {
        line.push(b[0]);
    }
    let port: u16 = String::from_utf8_lossy(&line).trim().parse().expect("the stub's port");
    Stub { child, url: format!("http://127.0.0.1:{port}") }
}

/// trading.limits as limits.nix declares them.
fn limits() -> Value {
    json!({"public": {"allowed": ["long-call", "long-put", "debit-spread", "event-yes", "event-no"],
        "dailyLossStopUsd": 25, "dailyTakeProfitUsd": 25, "maxContractPriceUsd": 10,
        "maxOpenPositions": 1, "maxPremiumUsd": 25, "seedUsd": 100}})
}

/// The declared strategies as the wrapper renders them, deciding in `dir`.
fn strategies(dir: &Path, stage: &str) -> Value {
    let d = dir.join("research").display().to_string();
    json!({
        "spy-agents": {"backend": "public", "bar": "1-DAY", "decisions": d, "event": null, "holdDays": 1,
            "kind": "agent-option", "name": "spy-agents",
            "option": {"expiryDaysMax": 21, "expiryDaysMin": 7, "minAbsDelta": 0.15},
            "params": null, "stage": stage, "startingUsd": 10000, "symbol": "SPY", "venue": "PUBLIC"},
        "weather-rules": {"backend": "public", "bar": "1-DAY", "decisions": d,
            "event": {"category": "Climate and Weather", "maxContracts": 10, "minEdge": 0.15,
                "questions": ["rain-month", "snow-month", "high-temp-day"], "source": "open-meteo", "subcategory": null},
            "holdDays": 1, "kind": "event-rule", "name": "weather-rules", "option": null, "params": null,
            "stage": stage, "startingUsd": 10000, "symbol": "KALSHI", "venue": "PUBLIC"}
    })
}

struct Case {
    dir: PathBuf,
    stub: Stub,
    stage: &'static str,
}

impl Case {
    fn new(name: &str) -> Case {
        Case::at_stage(name, "research")
    }

    fn at_stage(name: &str, stage: &'static str) -> Case {
        let dir = std::env::temp_dir().join(format!("trade-checks-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("research/2026-11-04")).unwrap();
        Case { dir, stub: stub(), stage }
    }

    fn write(&self, rel: &str, v: Value) {
        std::fs::write(self.dir.join(rel), v.to_string()).unwrap();
    }

    /// The fixture forecasts, with New York's high on 2026-11-06 set.
    fn forecasts(&self, ny_high: Option<f64>) -> String {
        let path = std::env::var("FIXTURE_PATH").unwrap_or_else(|_| "../_json/forecasts.json".into());
        let mut f: Value = serde_json::from_str(&std::fs::read_to_string(&path).expect("FIXTURE_PATH")).unwrap();
        if let Some(h) = ny_high {
            for d in f["cities"]["New York"]["daily"].as_array_mut().unwrap() {
                if d["date"] == "2026-11-06" {
                    d["high_f"] = json!(h);
                }
            }
        }
        let out = self.dir.join("forecasts.json");
        std::fs::write(&out, f.to_string()).unwrap();
        out.display().to_string()
    }

    fn run(&self, args: &[&str]) -> (i32, Value, String) {
        let out = Command::new(env!("CARGO_BIN_EXE_trade-run"))
            .args(args)
            .current_dir(&self.dir)
            .env("PUBLIC_API_BASE_URL", &self.stub.url)
            .env("PUBLIC_PERSONAL_SECRET", "stub-secret")
            .env("PUBLIC_ACCOUNT_ID", "5LA00001")
            .env("TRADE_STRATEGIES", strategies(&self.dir, self.stage).to_string())
            .env("TRADE_LIMITS", limits().to_string())
            .output()
            .expect("trade-run");
        let stdout = String::from_utf8_lossy(&out.stdout);
        let v = serde_json::from_str(&stdout).unwrap_or(Value::Null);
        (out.status.code().unwrap_or(-1), v, String::from_utf8_lossy(&out.stderr).into())
    }

    fn propose(&self, args: &[&str]) -> Value {
        let (code, v, err) = self.run(args);
        assert_eq!(code, 0, "{args:?}: {err}");
        v
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

#[test]
fn buy_is_one_call_within_the_cap() {
    let c = Case::new("buy");
    c.write("research/2026-11-04/SPY.json", json!({"decision": "BUY", "rationale": "the check"}));
    let v = c.propose(&["propose", "spy-agents", "2026-11-04"]);
    let p = &v["proposal"];
    assert_eq!(p["kind"], "long-call");
    assert_eq!(p["admissible"], true);
    assert_eq!(p["accepted"], true, "{p}");
    assert!(p["max_loss_usd"].as_f64().unwrap() <= 25.0);
    assert!(p["contract"]["delta"].as_f64().unwrap().abs() >= 0.15);
    assert_eq!(p["order"]["instrument"]["type"], "OPTION");
    assert_eq!(p["order"]["orderType"], "LIMIT");
}

#[test]
fn hold_proposes_nothing() {
    let c = Case::new("hold");
    c.write("research/2026-11-04/SPY.json", json!({"decision": "HOLD"}));
    let v = c.propose(&["propose", "spy-agents", "2026-11-04"]);
    assert!(v["proposal"].is_null());
    assert_eq!(v["why"], "decision HOLD: no trade");
}

#[test]
fn a_stopped_day_refuses_the_put() {
    let c = Case::new("stopped");
    c.write("research/2026-11-04/SPY.json", json!({"decision": "SELL", "rationale": "the check"}));
    c.write("research/state.json", json!({"openPositions": 0, "lossUsd": 25}));
    let v = c.propose(&["propose", "spy-agents", "2026-11-04"]);
    assert_eq!(v["proposal"]["kind"], "long-put");
    assert_eq!(v["proposal"]["admissible"], false);
    assert!(v["proposal"].get("preflight").is_none(), "an inadmissible proposal is not preflighted");
}

#[test]
fn place_refuses_a_strategy_not_live() {
    let c = Case::new("gate");
    c.write("research/2026-11-04/SPY.json", json!({"decision": "BUY", "rationale": "the check"}));
    let v = c.propose(&["propose", "spy-agents", "2026-11-04"]);
    c.write("proposal.json", v);
    let (code, _, err) = c.run(&["place", "proposal.json"]);
    assert_ne!(code, 0);
    assert!(err.contains("not live: nothing is placed"), "{err}");
}

#[test]
fn a_live_strategy_places_reads_back_and_records_the_position() {
    let c = Case::at_stage("live", "live");
    c.write("research/2026-11-04/SPY.json", json!({"decision": "BUY", "rationale": "the check"}));
    let v = c.propose(&["propose", "spy-agents", "2026-11-04"]);
    c.write("proposal.json", v.clone());
    let (code, placed, err) = c.run(&["place", "proposal.json"]);
    assert_eq!(code, 0, "{err}");
    assert_eq!(placed["status"]["status"], "FILLED", "{placed}");
    assert_eq!(placed["placed"]["orderId"], placed["status"]["orderId"]);
    assert_eq!(placed["day"]["openPositions"], 1);
    let state: Value = serde_json::from_str(&std::fs::read_to_string(c.dir.join("research/state.json")).unwrap()).unwrap();
    assert_eq!(state["openPositions"], 1);
    // The book is now full: the same proposal is refused.
    let (code, _, err) = c.run(&["place", "proposal.json"]);
    assert_ne!(code, 0);
    assert!(err.contains("position(s) open"), "{err}");
}

#[test]
fn the_weather_rules_buy_new_york_above_72() {
    let c = Case::new("weather");
    let f = c.forecasts(None);
    let v = c.propose(&["propose", "weather-rules", "2026-11-04", "--forecasts", &f]);
    let p = &v["proposal"];
    assert_eq!(p["kind"], "event-yes");
    assert_eq!(p["admissible"], true);
    assert_eq!(p["accepted"], true, "{p}");
    assert!(p["max_loss_usd"].as_f64().unwrap() <= 10.0);
    assert!(p["contract"]["edge"].as_f64().unwrap() >= 0.5);
    assert_eq!(p["contract"]["contract"], "KALSHI.KXHIGHNY-26NOV06-T72.Y");
    assert_eq!(p["order"]["instrument"]["type"], "EVENTCONTRACT");
    assert_eq!(p["order"]["orderType"], "LIMIT");
    assert_eq!(p["order"]["orderSide"], "BUY");
    assert_eq!(p["order"]["limitPrice"], "0.20");
    let cost: f64 = p["preflight"]["estimatedCost"].as_str().unwrap().parse().unwrap();
    assert_eq!(cost, p["max_loss_usd"].as_f64().unwrap());
    assert_eq!(v["considered"].as_array().unwrap().len(), 8);
    assert!(v["skipped"].as_array().unwrap().iter().all(|s| s["why"] != "a question shape the rules do not handle"));
}

#[test]
fn at_68_degrees_nothing_clears_min_edge() {
    let c = Case::new("cool");
    let f = c.forecasts(Some(68.0));
    let v = c.propose(&["propose", "weather-rules", "2026-11-04", "--forecasts", &f]);
    assert!(v["proposal"].is_null());
    let max = v["considered"].as_array().unwrap().iter().map(|c| c["edge"].as_f64().unwrap()).fold(f64::MIN, f64::max);
    assert!(max < 0.15, "{max}");
}

#[test]
fn a_day_at_its_take_profit_refuses() {
    let c = Case::new("takeprofit");
    let f = c.forecasts(None);
    c.write("research/state.json", json!({"openPositions": 0, "lossUsd": 0, "gainUsd": 25}));
    let v = c.propose(&["propose", "weather-rules", "2026-11-04", "--forecasts", &f]);
    assert_eq!(v["proposal"]["admissible"], false);
    let why = v["proposal"]["refused_because"].as_array().unwrap();
    assert!(why.iter().any(|w| w.as_str().unwrap().contains("take-profit")), "{why:?}");
}

#[test]
fn the_paper_day_is_recorded() {
    let c = Case::new("paperday");
    let f = c.forecasts(None);
    let v = c.propose(&["paper-day", "weather-rules", "2026-11-04", "--forecasts", &f]);
    assert_eq!(v["recorded"], true);
    let rec: Value = serde_json::from_str(
        &std::fs::read_to_string(c.dir.join("research/paper/2026-11-04-weather-rules.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(rec["proposal"]["kind"], "event-yes");
    assert!(rec.get("recorded").is_none(), "the record is the proposal, written before it is marked");
}

#[test]
fn an_agent_option_strategy_takes_no_forecasts() {
    let c = Case::new("noforecasts");
    let (code, _, err) = c.run(&["propose", "spy-agents", "2026-11-04", "--forecasts", "x.json"]);
    assert_eq!(code, 1);
    assert!(err.contains("--forecasts is for an event-rule strategy"), "{err}");
}

#[test]
fn the_declared_strategies_are_echoed() {
    let c = Case::new("strategies");
    let (code, v, _) = c.run(&["strategies"]);
    assert_eq!(code, 0);
    assert_eq!(v, strategies(&c.dir, "research"));
}

/// A recorded paper day, as `paper-day` writes it, for a contract and side.
fn paper_record(c: &Case, date: &str, event: &str, outcome: &str, contract: &str, side: &str, ask: f64, admissible: bool) {
    std::fs::create_dir_all(c.dir.join("research/paper")).unwrap();
    let rec = json!({"strategy": "weather-rules", "as_of": date, "proposal": {
        "kind": if side == "YES" { "event-yes" } else { "event-no" },
        "contract": {"event": event, "outcome": outcome, "contract": contract, "side": side, "ask": ask},
        "quantity": 10, "max_loss_usd": ask * 10.0, "admissible": admissible}});
    c.write(&format!("research/paper/{date}-weather-rules.json"), rec);
}

#[test]
fn paper_days_settle_into_the_ledger() {
    let c = Case::new("settle");
    // Miami's October rain settled YES: the YES at 0.40 wins 6.00, the NO
    // at 0.30 loses 3.00; New York's Nov 6 high is still open; a refused
    // day is no trade.
    paper_record(&c, "2026-10-28", "KALSHI.KXRAINMIA-26OCT", "KALSHI.KXRAINMIA-26OCT-5", "KALSHI.KXRAINMIA-26OCT-5.Y", "YES", 0.40, true);
    paper_record(&c, "2026-10-29", "KALSHI.KXRAINMIA-26OCT", "KALSHI.KXRAINMIA-26OCT-5", "KALSHI.KXRAINMIA-26OCT-5.N", "NO", 0.30, true);
    paper_record(&c, "2026-10-30", "KALSHI.KXRAINMIA-26OCT", "KALSHI.KXRAINMIA-26OCT-5", "KALSHI.KXRAINMIA-26OCT-5.Y", "YES", 0.40, false);
    paper_record(&c, "2026-11-04", "KALSHI.KXHIGHNY-26NOV06", "KALSHI.KXHIGHNY-26NOV06-T72", "KALSHI.KXHIGHNY-26NOV06-T72.Y", "YES", 0.20, true);
    let v = c.propose(&["paper-settle", "weather-rules"]);
    assert_eq!(v["days"], 4);
    assert_eq!(v["trades"], 3);
    assert_eq!((v["won"].as_u64(), v["lost"].as_u64(), v["open"].as_u64()), (Some(1), Some(1), Some(1)));
    assert_eq!(v["pnl_usd"], 3.0);
    assert_eq!(v["hit_rate"], 0.5);
    // 100 -> 106 -> 103: 3 below the 106 peak.
    assert_eq!(v["max_drawdown_pct"], 2.83);
    let statuses: Vec<&str> = v["record"].as_array().unwrap().iter().map(|d| d["status"].as_str().unwrap()).collect();
    assert_eq!(statuses, vec!["won", "lost", "no-trade", "open"]);
    assert!(c.dir.join("research/paper/ledger-weather-rules.json").exists());
}

#[test]
fn the_ledger_is_not_read_as_a_paper_day() {
    let c = Case::new("settle-again");
    paper_record(&c, "2026-10-28", "KALSHI.KXRAINMIA-26OCT", "KALSHI.KXRAINMIA-26OCT-5", "KALSHI.KXRAINMIA-26OCT-5.Y", "YES", 0.40, true);
    let first = c.propose(&["paper-settle", "weather-rules"]);
    let again = c.propose(&["paper-settle", "weather-rules"]);
    assert_eq!(first["days"], 1);
    assert_eq!(again["days"], 1);
}
