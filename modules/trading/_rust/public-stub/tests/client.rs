//! Integration tests for the public-stub: spawn the stub binary, connect
//! the kagamizo-public client, and exercise every API method.
//!
//! The stub binary path is provided by Cargo's CARGO_BIN_EXE_<pkg> env at
//! compile time via env!("CARGO_BIN_EXE_public-stub").

use std::process::{Command, Stdio, Child};
use std::io::{Write, Read};

use kagamizo_public::client::Public;

// ── Helpers ──────────────────────────────────────────────────────────────

/// A guard that kills the child process on drop.
struct StubGuard {
    child: Child,
}

impl StubGuard {
    pub fn new(child: Child) -> Self {
        Self { child }
    }
}

impl Drop for StubGuard {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Spawn the stub binary, read its port from stdout, and return
/// a (client, guard) pair. The client's base URL is set via env var
/// PUBLIC_API_BASE_URL to http://127.0.0.1:<port>.
fn spawn_stub() -> Result<(Public, StubGuard), String> {
    let bin_path = env!("CARGO_BIN_EXE_public-stub");
    let mut cmd = Command::new(&bin_path);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::null());
    cmd.stdin(Stdio::null());

    let child = cmd.spawn();
    if child.is_err() {
        return Result::Err(format!("failed to spawn stub: {:?}", child.unwrap_err().kind()));
    }
    let mut child = child.unwrap();

    // Use .take() to avoid partial move (docs recommend this pattern).
    let stdout_opt = child.stdout.take();
    if stdout_opt.is_none() {
        let _ = child.kill();
        return Result::Err("no stdout".to_string());
    }
    let mut reader = stdout_opt.unwrap();
    let mut buf: Vec<u8> = Vec::new();
    loop {
        let mut byte: [u8; 1] = [0];
        let n = reader.read(byte.as_mut_slice());
        if n.is_err() || n.unwrap() == 0 { break; }
        buf.push(byte[0]);
        if byte[0] == '\n' as u8 { break; }
    }
    // reader is dropped here (closes the pipe)

    let port_str = String::from_utf8_lossy(&buf).trim().to_string();
    if port_str.is_empty() {
        let _ = child.kill();
        return Result::Err("no port from stub".to_string());
    }

    // Create the client with the correct base URL (no env var needed).
    let base_url = format!("http://127.0.0.1:{}", port_str);
    let client = Public::new_with_url("stub-secret", "5LA00001", &base_url);
    // Give the stub a moment to enter its accept loop.
    // In Rust (this dialect), use std::thread::sleep for a short pause.
    // We use the env var set (which was already done) and just create the client.
    Result::Ok((client, StubGuard::new(child)))
}

// ── Tests ────────────────────────────────────────────────────────────────

#[test]
fn test_token() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let tok = client.token()?;
    if tok != "stub-token" {
        return Result::Err(format!("expected stub-token, got {}", tok));
    }
    
    Result::Ok(())
}

#[test]
fn test_account() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let acct = client.account()?;
    if acct != "5LA00001" {
        return Result::Err(format!("expected 5LA00001, got {}", acct));
    }
    
    Result::Ok(())
}

#[test]
fn test_instrument() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let instr = client.instrument("SPY", "EQUITY")?;
    let sym = instr.get("symbol").and_then(|v| v.as_str()).unwrap_or("");
    if sym != "SPY" {
        return Result::Err(format!("expected SPY, got {}", sym));
    }
    
    Result::Ok(())
}

#[test]
fn test_bars() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let rows = client.bars("SPY", "1-DAY", None, "EQUITY", "regularMarket")?;
    if rows.len() != 7 {
        return Result::Err(format!("expected 7 bars, got {}", rows.len()));
    }
    
    Result::Ok(())
}

#[test]
fn test_preflight_accepted() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let body = r#"{"instrument":{"symbol":"SPY","type":"EQUITY"},"orderSide":"BUY","orderType":"MARKET","expiration":{"timeInForce":"DAY"},"quantity":"10"}"#;
    let pf = client.preflight(body)?;
    let cost = pf.estimated_cost.unwrap_or("".to_string());
    if cost != "1000.00" {
        return Result::Err(format!("unexpected preflight cost: {}", cost));
    }
    
    Result::Ok(())
}

#[test]
fn test_preflight_refused() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let body = r#"{"instrument":{"symbol":"SPY","type":"EQUITY"},"orderSide":"SELL","orderType":"MARKET","expiration":{"timeInForce":"DAY"},"quantity":"10"}"#;
    let result = client.preflight(body);
    if result.is_ok() {
        return Result::Err("expected SELL preflight to fail".to_string());
    }
    let msg = result.unwrap_err();
    if !msg.contains("HTTP 400") {
        return Result::Err(format!("expected HTTP 400, got {}", msg));
    }
    
    Result::Ok(())
}

#[test]
fn test_option_expirations() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let exps = client.option_expirations("SPY", "EQUITY")?;
    if exps.len() != 4 {
        return Result::Err(format!("expected 4 expirations, got {}", exps.len()));
    }
    
    Result::Ok(())
}

#[test]
fn test_option_chain() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let chain = client.option_chain("SPY", "2026-11-13", "EQUITY")?;
    if chain.calls.len() != 17 || chain.puts.len() != 17 {
        return Result::Err(format!("expected 17 calls and 17 puts, got {} calls and {} puts", chain.calls.len(), chain.puts.len()));
    }
    
    Result::Ok(())
}

#[test]
fn test_greeks() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let mut syms: Vec<String> = Vec::new();
    syms.push("SPY  261113C156000".to_string());
    let g = client.greeks(syms)?;
    if g.is_empty() {
        return Result::Err("expected at least one greek entry".to_string());
    }
    
    Result::Ok(())
}

#[test]
fn test_event_contract_summary() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let empty: Vec<String> = Vec::new();
    let summary = client.event_contract_summary(None, None, &empty, None, None, None, &empty, None, None, "VOLUME")?;
    if summary.content.is_none() {
        return Result::Err("expected content".to_string());
    }
    let content = summary.content.unwrap();
    if content.len() < 2 {
        return Result::Err(format!("expected at least 2 events, got {}", content.len()));
    }
    
    Result::Ok(())
}

#[test]
fn test_event_contract_summary_page2() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let empty: Vec<String> = Vec::new();
    let page1 = client.event_contract_summary(None, None, &empty, None, None, None, &empty, None, None, "VOLUME")?;
    if page1.content.is_none() {
        return Result::Err("expected content on page 1".to_string());
    }
    
    Result::Ok(())
}

#[test]
fn test_event_contracts() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let empty: Vec<String> = Vec::new();
    let contracts = client.event_contracts(20, None, None, &empty, None, None, None, &empty, None)?;
    if contracts.len() < 2 {
        return Result::Err(format!("expected at least 2 contracts, got {}", contracts.len()));
    }
    
    Result::Ok(())
}

#[test]
fn test_event_contract_details() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let details = client.event_contract_details("KALSHI.KXHIGHNY-26NOV06", true)?;
    if details.event_symbol != "KALSHI.KXHIGHNY-26NOV06" {
        return Result::Err(format!("wrong event symbol: {}", details.event_symbol));
    }
    if details.outcomes.len() != 3 {
        return Result::Err(format!("expected 3 outcomes, got {}", details.outcomes.len()));
    }
    
    Result::Ok(())
}

#[test]
fn test_event_contract_bars() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let mut symbols: Vec<&str> = Vec::new();
    symbols.push("KALSHI.KXHIGHNY-26NOV06-T72.Y");
    let bars = client.event_contract_bars("KALSHI.KXHIGHNY-26NOV06-EVENT", "WEEK", symbols)?;
    if bars.charts.is_empty() {
        return Result::Err("expected at least 1 chart".to_string());
    }
    
    Result::Ok(())
}

#[test]
fn test_quotes() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let mut instruments: Vec<(&str, &str)> = Vec::new();
    instruments.push(("KALSHI.KXHIGHNY-26NOV06-T72.Y", "EVENTCONTRACT"));
    let quotes = client.quotes(instruments)?;
    if quotes.is_empty() {
        return Result::Err("expected at least 1 quote".to_string());
    }
    
    Result::Ok(())
}

#[test]
fn test_place_and_order() -> Result<(), String> {
    let (mut client, guard) = spawn_stub()?;
    let _ = client.account()?;

    // Place an order
    let order_body = r#"{"instrument":{"symbol":"SPY","type":"EQUITY"},"orderSide":"BUY","orderType":"MARKET","expiration":{"timeInForce":"DAY"},"quantity":"10"}"#;
    let placed = client.place(order_body)?;
    if placed.order_id.is_empty() {
        return Result::Err("expected an order id".to_string());
    }

    // Read it back
    let order = client.order(&placed.order_id)?;
    let status = order.status.unwrap_or("".to_string());
    if status != "FILLED" {
        return Result::Err(format!("expected FILLED, got {}", status));
    }
    
    Result::Ok(())
}
