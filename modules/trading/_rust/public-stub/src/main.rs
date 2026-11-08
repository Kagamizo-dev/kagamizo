//! A stand-in for Public's API (stub), for tests.
//! Ported from _stub_public.py: every route, every fixture, every response.
//! Prints its port on stdout then serves forever.

use std::net::{TcpListener, TcpStream, Ipv4Addr, SocketAddrV4};
use std::io::{Write, Read};

const SECRET: &str = "stub-secret";
const TOKEN: &str = "stub-token";
const ACCOUNT: &str = "5LA00001";

static mut ORDER_COUNTER: u32 = 0;

// In-memory order store: a simple Vec of (id, body_json) pairs.
static mut ORDER_IDS: Vec<String> = Vec::new();
static mut ORDER_BODIES: Vec<String> = Vec::new();
// Orders cancelled by DELETE: read back as CANCELLED.
static mut CANCELLED: Vec<String> = Vec::new();

fn store_order(id: &str, body: &str) {
    unsafe {
        ORDER_IDS.push(id.to_string());
        ORDER_BODIES.push(body.to_string());
    }
}

fn find_order(id: &str) -> Option<&str> {
    unsafe {
        for i in 0..ORDER_IDS.len() {
            if ORDER_IDS[i] == id {
                return Some(ORDER_BODIES[i].as_str());
            }
        }
    }
    None
}

// ── Bars fixture (7 bars for SPY, matching _stub_public.py's CSV) ───────

static BARS: &[(&str, &str, &str, &str, &str, u64)] = &[
    ("2026-10-28T14:00:00Z", "150.00", "151.00", "149.50", "150.50", 1000),
    ("2026-10-29T14:00:00Z", "150.50", "152.00", "150.00", "151.00", 1200),
    ("2026-10-30T14:00:00Z", "151.00", "153.00", "150.50", "152.00", 1100),
    ("2026-10-31T14:00:00Z", "152.00", "154.00", "151.00", "153.00", 1300),
    ("2026-11-01T14:00:00Z", "153.00", "155.00", "152.00", "154.00", 900),
    ("2026-11-02T14:00:00Z", "154.00", "156.00", "153.00", "155.00", 800),
    ("2026-11-03T14:00:00Z", "155.00", "157.00", "154.00", "156.00", 1100),
];

fn last_close() -> f64 { 156.00 }

static EXPIRATIONS: &[&str] = &["2026-11-06", "2026-11-13", "2026-11-20", "2026-12-18"];

// ── Option chain helpers ────────────────────────────────────────────────

fn osi(symbol: &str, expiration: &str, kind: char, strike: f64) -> String {
    // Match Python _stub_public.py: d.strftime('%y%m%d') gives 6-char date
    let d = &expiration[0..10];
    let y = d.chars().skip(2).take(2).collect::<String>();
    let m = d.chars().skip(5).take(2).collect::<String>();
    let day = d.chars().skip(8).take(2).collect::<String>();
    let date_part = format!("{}{}{}", y, m, day); // %y%m%d: 6 chars
    let sym_part = if symbol.len() >= 6 { &symbol[0..6] } else { symbol };
    let strike_int = (strike * 1000.0).round() as i64;
    format!("{:<6}{}{}{:08}", sym_part, date_part, kind, strike_int)
}

fn greeks_of(sym: &str) -> String {
    let LAST = last_close();
    // The OSI symbol: 6-char root, 6-char date, kind at 12, strike from 13.
    let kind: char = if sym.len() > 12 { sym.chars().nth(12).unwrap_or('C') } else { 'C' };
    let strike_str = if sym.len() > 13 { &sym[13..] } else { "0" };
    let strike: f64 = strike_str.parse::<f64>().unwrap_or(0.0) / 1000.0;
    let away: f64 = if kind == 'C' { strike - LAST } else { LAST - strike };
    let delta_raw: f64 = 0.5 - away * 0.04;
    let delta: f64 = if delta_raw < 0.05 { 0.05 } else if delta_raw > 0.9 { 0.9 } else { delta_raw };
    let delta_signed: f64 = if kind == 'C' { delta } else { -delta };
    format!(r#"{{"delta":{:.3},"gamma":0.02,"theta":-0.05,"vega":0.1,"rho":0.01,"impliedVolatility":0.2}}"#, delta_signed)
}

fn chain(symbol: &str, expiration: &str) -> String {
    let LAST = last_close();

    fn quote(kind: char, strike: f64, symbol: &str, expiration: &str, LAST: f64) -> String {
        let away: f64 = if kind == 'C' { strike - LAST } else { LAST - strike };
        let ask_raw: f64 = 1.0 - away * 0.1;
        let ask: f64 = if ask_raw < 0.05 { 0.05 } else { ask_raw };
        let sym = osi(symbol, expiration, kind, strike);
        let bid = if (0.01) < (ask - 0.05) { ask - 0.05 } else { 0.01 };
        let g = greeks_of(&sym);
        format!(
            r#"{{"instrument":{{"symbol":"{}","type":"OPTION"}},"bid":"{:.2}","ask":"{:.2}","last":"{:.2}","optionDetails":{{"strikePrice":"{:.2}","greeks":{}}}}}"#,
            sym, bid, ask, ask, strike, g
        )
    }

    let base = LAST.round() as i32;
    let mut calls: Vec<String> = Vec::new();
    let mut puts: Vec<String> = Vec::new();
    for i in (-8)..=8 {
        let k = (base + i) as f64;
        calls.push(quote('C', k, symbol, expiration, LAST));
        puts.push(quote('P', k, symbol, expiration, LAST));
    }
    format!(r#"{{"baseSymbol":"{}","calls":[{}],"puts":[{}]}}"#, symbol, calls.join(","), puts.join(","))
}

// ── Event Contract fixtures ─────────────────────────────────────────────

const WEATHER: &str = "Climate and Weather";

fn contract_str(outcome_id: &str, yes_ask: f64, no_ask: f64) -> String {
    let y_bid = yes_ask - 0.02;
    let y_last = yes_ask - 0.01;
    let n_bid = no_ask - 0.02;
    let n_last = no_ask - 0.01;
    let y_bid_r = if y_bid < 0.0 { 0.0 } else { y_bid };
    let n_bid_r = if n_bid < 0.0 { 0.0 } else { n_bid };
    format!(
        r#"{{"symbol":"{}.Y","predictedOutcome":"YES","bid":"{:.2}","ask":"{:.2}","last":"{:.2}","openInterest":"120","probability":"{:.2}"}},{{"symbol":"{}.N","predictedOutcome":"NO","bid":"{:.2}","ask":"{:.2}","last":"{:.2}","openInterest":"120","probability":"{:.2}"}}"#,
        outcome_id, y_bid_r, yes_ask, y_last, y_last,
        outcome_id, n_bid_r, no_ask, n_last, 1.0 - y_last
    )
}

fn outcome_str(
    outcome_id: &str, title: &str, yes_ask: f64, no_ask: f64,
    state: &str, trading: &str, close: &str, settled: &str,
) -> String {
    let c = contract_str(outcome_id, yes_ask, no_ask);
    format!(
        r#"{{"outcomeId":"{}","title":"{}","rules":"Resolves YES if the question's observation falls in the band: {}.","volume":"4000","state":"{}","timeline":{{"openTime":"2026-10-30T14:00:00Z","closeTime":"{}","expectedExpirationTime":"{}"}},"settledOutcome":"{}","trading":"{}","contracts":[{}]}}"#,
        outcome_id, title, title, state, close, close, settled, trading, c
    )
}

// Known event contract symbols for preflight lookups
fn is_known_contract(sym: &str) -> bool {
    sym == "KALSHI.KXHIGHNY-26NOV06-T72.Y" || sym == "KALSHI.KXHIGHNY-26NOV06-T72.N" ||
    sym == "KALSHI.KXHIGHNY-26NOV06-B66.Y" || sym == "KALSHI.KXHIGHNY-26NOV06-B66.N" ||
    sym == "KALSHI.KXHIGHNY-26NOV06-T65.Y" || sym == "KALSHI.KXHIGHNY-26NOV06-T65.N" ||
    sym == "KALSHI.KXRAINCHI-26NOV-3.Y" || sym == "KALSHI.KXRAINCHI-26NOV-3.N" ||
    sym == "KALSHI.KXRAINMIA-26OCT-5.Y" || sym == "KALSHI.KXRAINMIA-26OCT-5.N"
}

fn contract_price(sym: &str) -> f64 {
    match sym {
        "KALSHI.KXHIGHNY-26NOV06-T72.Y" => 0.19,
        "KALSHI.KXHIGHNY-26NOV06-T72.N" => 0.81,
        "KALSHI.KXHIGHNY-26NOV06-B66.Y" => 0.49,
        "KALSHI.KXHIGHNY-26NOV06-B66.N" => 0.51,
        "KALSHI.KXHIGHNY-26NOV06-T65.Y" => 0.29,
        "KALSHI.KXHIGHNY-26NOV06-T65.N" => 0.71,
        "KALSHI.KXRAINCHI-26NOV-3.Y" => 0.54,
        "KALSHI.KXRAINCHI-26NOV-3.N" => 0.46,
        "KALSHI.KXRAINMIA-26OCT-5.Y" => 0.98,
        "KALSHI.KXRAINMIA-26OCT-5.N" => 0.02,
        _ => 0.50,
    }
}

/// The coins the stub quotes, at a fixed last price: Public names a coin by
/// its symbol alone, with type CRYPTO.
fn coin_price(sym: &str) -> Option<f64> {
    match sym {
        "BTC" => Some(87500.00),
        "ETH" => Some(3200.00),
        _ => None,
    }
}

// ── HTTP helpers ─────────────────────────────────────────────────────────

fn reply(mut stream: &TcpStream, status: u32, body: &str) {
    let r = match status {
        200u32 => "OK",
        400u32 => "Bad Request",
        401u32 => "Unauthorized",
        404u32 => "Not Found",
        _ => "Error",
    };
    let resp = format!("HTTP/1.1 {} {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        status, r, body.len(), body);
    let _ = stream.write_all(resp.as_bytes());
}

/// Helper: reply with a format-generated string (returns String, borrows as &str).
fn reply_fmt(mut stream: &TcpStream, status: u32, body: String) {
    reply(stream, status, &body);
}

fn bars_json() -> String {
    let mut parts: Vec<String> = Vec::new();
    for (ts, o, h, l, c, v) in BARS {
        parts.push(format!(
            r#"{{"timestamp":"{}","open":"{}","high":"{}","low":"{}","close":"{}","volume":{}}}"#,
            ts, o, h, l, c, v
        ));
    }
    format!(
        r#"{{"symbol":"SPY","period":"FIVE_YEARS","totalExpectedBars":{},"preMarket":{{"expectedBars":0,"bars":[]}},"regularMarket":{{"expectedBars":{},"bars":[{}]}},"afterMarket":{{"expectedBars":0,"bars":[]}}}}"#,
        BARS.len(), BARS.len(), parts.join(",")
    )
}

/// Read one HTTP/1.1 request in full, or None if the peer closed early.
fn read_request(stream: &mut std::net::TcpStream) -> Option<String> {
    let mut data: Vec<u8> = Vec::new();
    let mut chunk = [0u8; 8192];
    let header_end = loop {
        if let Some(i) = data.windows(4).position(|w| w == b"\r\n\r\n") {
            break i + 4;
        }
        let n = stream.read(&mut chunk).ok()?;
        if n == 0 {
            return None;
        }
        data.extend_from_slice(&chunk[..n]);
    };
    let head = String::from_utf8_lossy(&data[..header_end]).to_string();
    let length = head
        .lines()
        .find_map(|l| {
            let (k, v) = l.split_once(':')?;
            k.trim().eq_ignore_ascii_case("content-length").then(|| v.trim().parse::<usize>().ok())?
        })
        .unwrap_or(0);
    while data.len() < header_end + length {
        let n = stream.read(&mut chunk).ok()?;
        if n == 0 {
            return None;
        }
        data.extend_from_slice(&chunk[..n]);
    }
    Some(String::from_utf8_lossy(&data[..header_end + length]).to_string())
}

fn main() {
    let addr = Ipv4Addr::new(127, 0, 0, 1);
    let sock_addr = SocketAddrV4::new(addr, 0);
    let listener = TcpListener::bind(sock_addr).expect("bind");
    let port = listener.local_addr().expect("local_addr").port();
    println!("{}", port);

    loop {
        let (mut stream, _peer) = listener.accept().expect("accept");
        // The whole request: headers through the blank line, then exactly
        // Content-Length bytes of body. One read is not enough: a client
        // may write the headers and the body separately.
        let request = read_request(&mut stream);
        if request.is_none() { continue; }
        let request = request.unwrap();
        let raw = request.as_str();

        let lines = raw.split("\r\n").collect::<Vec<&str>>();
        if lines.len() < 1 { continue; }
        let req_parts = lines[0].split(" ").collect::<Vec<&str>>();
        if req_parts.len() < 2 { continue; }
        let method = req_parts[0];
        let path = req_parts[1];
        // Strip query string for route matching.
        let route_path = path.split_once("?").map(|(p, _)| p).unwrap_or(path).to_string();

        let mut i = 1;
        let mut found_auth = false;
        while i < lines.len() {
            let line = lines[i];
            if line.is_empty() { i += 1; break; }
            let colon = line.find(":");
            if colon.is_some() {
                let k = (&line[0..colon.unwrap()]).trim();
                if k == "Authorization" {
                    let v = (&line[colon.unwrap() + 1..]).trim();
                    let expected = format!("Bearer {}", TOKEN);
                    if v == expected { found_auth = true; }
                }
            }
            i += 1;
        }
        let body_str = lines[i..].join("\r\n");
        let body = serde_json::from_str::<serde_json::Value>(&body_str).unwrap_or(
            serde_json::from_str::<serde_json::Value>("{}").expect("{}")
        );

        // Auth route (no auth needed)
        if route_path == "/userapiauthservice/personal/access-tokens" && method == "POST" {
            let secret_field = body.get("secret");
            let secret_val = if secret_field.is_some() { secret_field.unwrap().as_str().unwrap_or("") } else { "" };
            if secret_val == SECRET {
                reply(&stream, 200, r#"{"accessToken":"stub-token"}"#);
            } else {
                reply(&stream, 401, r#"{"message":"bad secret"}"#);
            }
            continue;
        }

        // All other routes need auth
        if !found_auth {
            reply(&stream, 401, r#"{"message":"unauthorized"}"#);
            continue;
        }

        // ── Route dispatch ────────────────────────────────────────────

        if route_path == "/userapigateway/trading/account" {
            reply(&stream, 200, r#"{"accounts":[{"accountId":"5LA00001","accountType":"BROKERAGE"}]}"#);

        // ── Bars (SPY historic data, one_day/five_years, matching Python stub) ──
        } else if route_path.starts_with("/userapigateway/historicdata/") && !route_path.contains("event-contracts") {
            reply(&stream, 200, &bars_json());

        // ── Event contract bars ───────────────────────────────────────
        } else if route_path.starts_with("/userapigateway/historicdata/event-contracts/") {
            let period = path.rsplit("/").last().unwrap_or("WEEK");
            let query_part = path.split("?").last().unwrap_or("");
            let syms_raw = query_part.split("=").last().unwrap_or("");
            let symbols = syms_raw.split(",");
            let mut charts: Vec<String> = Vec::new();
            for s in symbols {
                let sym = s.trim();
                if sym.is_empty() { continue; }
                let price = contract_price(&sym);
                charts.push(format!(
                    r#"{{"symbol":"{}","previousClosePrice":"{:.2}","currentPrice":"{:.2}","bars":[{{"timestamp":"2026-11-03T00:00:00Z","open":"{:.2}","high":"{:.2}","low":"{:.2}","close":"{:.2}","value":"{:.2}","volume":10}}]}}"#,
                    sym, price, price, price, price, price, price, price
                ));
            }
            reply_fmt(&stream, 200, format!(r#"{{"period":"{}","charts":[{}]}}"#, period, charts.join(",")));

        // ── Event contract details ────────────────────────────────────
        } else if route_path.starts_with("/userapigateway/eventcontract/details/") {
            // Extract the last segment after the last /
            let route_str = route_path.as_str();
            let last_slash = route_str.rfind("/");
            let symbol = if last_slash.is_some() {
                (&route_str[last_slash.unwrap() + 1..]).to_string()
            } else { route_str.to_string() };
            if symbol.is_empty() {
                reply_fmt(&stream, 404, format!("{{\"message\":\"no event\"}}"));
            } else if symbol == "KALSHI.KXHIGHNY-26NOV06" {
                let o1 = outcome_str("KALSHI.KXHIGHNY-26NOV06-T72", "72\u{00b0} or above", 0.20, 0.82, "STATE_OPEN", "BUY_AND_SELL", "2026-11-07T04:59:00Z", "SETTLED_OUTCOME_UNSPECIFIED");
                let o2 = outcome_str("KALSHI.KXHIGHNY-26NOV06-B66", "66\u{00b0} to 71\u{00b0}", 0.50, 0.52, "STATE_OPEN", "BUY_AND_SELL", "2026-11-07T04:59:00Z", "SETTLED_OUTCOME_UNSPECIFIED");
                let o3 = outcome_str("KALSHI.KXHIGHNY-26NOV06-T65", "65\u{00b0} or below", 0.30, 0.72, "STATE_OPEN", "BUY_AND_SELL", "2026-11-07T04:59:00Z", "SETTLED_OUTCOME_UNSPECIFIED");
                reply_fmt(&stream, 200, format!(
                    r#"{{"eventSymbol":"KALSHI.KXHIGHNY-26NOV06","exchange":"KALSHI","title":"Highest temperature in New York on Nov 6?","category":"Climate and Weather","volume":"12000","subcategories":["Temperature"],"cftcContract":{{"prohibitions":[],"resolutionSources":[{{"name":"NWS","url":"https://www.weather.gov"}}],"contractTermsUrl":"https://kalshi.com/terms"}},"outcomeCount":3,"outcomes":[{}],"resolved":false,"halted":false}}"#,
                    [o1, o2, o3].join(",")
                ));
            } else if symbol == "KALSHI.KXRAINCHI-26NOV" {
                let o1 = outcome_str("KALSHI.KXRAINCHI-26NOV-3", "Above 3 inches", 0.55, 0.50, "STATE_OPEN", "BUY_AND_SELL", "2026-12-01T05:59:00Z", "SETTLED_OUTCOME_UNSPECIFIED");
                reply_fmt(&stream, 200, format!(
                    r#"{{"eventSymbol":"KALSHI.KXRAINCHI-26NOV","exchange":"KALSHI","title":"Rain in Chicago in November?","category":"Climate and Weather","volume":"4000","subcategories":["Snow and rain"],"cftcContract":{{"prohibitions":[],"resolutionSources":[{{"name":"NWS","url":"https://www.weather.gov"}}],"contractTermsUrl":"https://kalshi.com/terms"}},"outcomeCount":1,"outcomes":[{}],"resolved":false,"halted":false}}"#,
                    o1
                ));
            } else if symbol == "KALSHI.KXRAINMIA-26OCT" {
                let o1 = outcome_str("KALSHI.KXRAINMIA-26OCT-5", "Above 5 inches", 0.99, 0.01, "STATE_SETTLED", "DISABLED", "2026-11-01T04:59:00Z", "SETTLED_OUTCOME_YES");
                reply_fmt(&stream, 200, format!(
                    r#"{{"eventSymbol":"KALSHI.KXRAINMIA-26OCT","exchange":"KALSHI","title":"Rain in Miami in October?","category":"Climate and Weather","volume":"4000","subcategories":["Snow and rain"],"cftcContract":{{"prohibitions":[],"resolutionSources":[{{"name":"NWS","url":"https://www.weather.gov"}}],"contractTermsUrl":"https://kalshi.com/terms"}},"outcomeCount":1,"outcomes":[{}],"resolved":true,"halted":false}}"#,
                    o1
                ));
            } else {
                reply_fmt(&stream, 404, format!("{{\"message\":\"no event {}\"}}", symbol));
            }

        // ── Event contract summary ────────────────────────────────────
        } else if route_path == "/userapigateway/eventcontract/summary" && method == "POST" {
            let sort = body.get("sortingMode").and_then(|v| v.as_str()).unwrap_or("");
            if sort != "VOLUME" && sort != "EXPIRATION" && sort != "RECENTLY_ADDED" {
                reply(&stream, 400, r#"{"message":"sortingMode is required"}"#);
                continue;
            }
            let cat = body.get("category").and_then(|v| v.as_str());
            let subcat = body.get("subcategory").and_then(|v| v.as_str());
            let display_resolved = body.get("displayResolvedEvents").and_then(|v| v.as_bool()).unwrap_or(false);

            let mut content: Vec<String> = Vec::new();
            let cat_match = cat.is_none() || cat.unwrap() == WEATHER;

            // NY event (not resolved)
            if cat_match && (subcat.is_none() || subcat.unwrap() == "Temperature") {
                content.push(format!(
                    r#"{{"title":"Highest temperature in New York on Nov 6?","eventSymbol":"KALSHI.KXHIGHNY-26NOV06","volume":"12000","category":"Climate and Weather","subcategories":["Temperature"],"symbols":["KALSHI.KXHIGHNY-26NOV06-T72.Y","KALSHI.KXHIGHNY-26NOV06-T72.N","KALSHI.KXHIGHNY-26NOV06-B66.Y","KALSHI.KXHIGHNY-26NOV06-B66.N","KALSHI.KXHIGHNY-26NOV06-T65.Y","KALSHI.KXHIGHNY-26NOV06-T65.N"],"resolutionTime":"2026-11-07T04:59:00Z","resolved":false,"halted":false}}"#
                ));
            }
            // Chicago event (not resolved)
            if cat_match && (subcat.is_none() || subcat.unwrap() == "Snow and rain") {
                content.push(format!(
                    r#"{{"title":"Rain in Chicago in November?","eventSymbol":"KALSHI.KXRAINCHI-26NOV","volume":"4000","category":"Climate and Weather","subcategories":["Snow and rain"],"symbols":["KALSHI.KXRAINCHI-26NOV-3.Y","KALSHI.KXRAINCHI-26NOV-3.N"],"resolutionTime":"2026-12-01T05:59:00Z","resolved":false,"halted":false}}"#
                ));
            }
            // Miami event (resolved, only if display_resolved)
            if display_resolved && cat_match && (subcat.is_none() || subcat.unwrap() == "Snow and rain") {
                content.push(format!(
                    r#"{{"title":"Rain in Miami in October?","eventSymbol":"KALSHI.KXRAINMIA-26OCT","volume":"4000","category":"Climate and Weather","subcategories":["Snow and rain"],"symbols":["KALSHI.KXRAINMIA-26OCT-5.Y","KALSHI.KXRAINMIA-26OCT-5.N"],"resolutionTime":"2026-11-01T04:59:00Z","resolved":true,"halted":false}}"#
                ));
            }
            reply_fmt(&stream, 200, format!(r#"{{"content":[{}],"nextToken":null}}"#, content.join(",")));

        // ── Instrument ────────────────────────────────────────────────
        } else if route_path.starts_with("/userapigateway/trading/instruments/") {
            reply(&stream, 200, r#"{"symbol":"SPY","type":"EQUITY","status":"ACTIVE"}"#);

        // ── Preflight ─────────────────────────────────────────────────
        } else if route_path.ends_with("/preflight/single-leg") {
            let instrument = body.get("instrument");
            let instr_type = if instrument.is_some() {
                instrument.unwrap().get("type").and_then(|v| v.as_str()).unwrap_or("")
            } else { "" };
            let side = body.get("orderSide").and_then(|v| v.as_str()).unwrap_or("");

            if instr_type == "OPTION" {
                let lps = body.get("limitPrice").and_then(|v| v.as_str()).unwrap_or("0");
                let qs = body.get("quantity").and_then(|v| v.as_str()).unwrap_or("0");
                let cost = lps.parse::<f64>().unwrap_or(0.0) * 100.0 * qs.parse::<f64>().unwrap_or(0.0);
                reply_fmt(&stream, 200, format!(
                    r#"{{"instrument":{},"orderValue":"{:.2}","estimatedCost":"{:.2}"}}"#,
                    if instrument.is_some() { instrument.unwrap().to_string() } else { "{}".to_string() },
                    cost, cost
                ));
            } else if instr_type == "EVENTCONTRACT" {
                let sym = if instrument.is_some() {
                    instrument.unwrap().get("symbol").and_then(|s| s.as_str()).unwrap_or("")
                } else { "" };
                if !is_known_contract(&sym) {
                    reply(&stream, 400, r#"{"message":"unknown event contract"}"#);
                } else if side == "SELL" {
                    reply(&stream, 400, r#"{"message":"no contracts held"}"#);
                } else {
                    let lps = body.get("limitPrice").and_then(|v| v.as_str()).unwrap_or("0");
                    let qs = body.get("quantity").and_then(|v| v.as_str()).unwrap_or("0");
                    let cost = lps.parse::<f64>().unwrap_or(0.0) * qs.parse::<f64>().unwrap_or(0.0);
                    reply_fmt(&stream, 200, format!(
                        r#"{{"instrument":{},"orderValue":"{:.2}","estimatedCost":"{:.2}","estimatedQuantity":"{}"}}"#,
                        if instrument.is_some() { instrument.unwrap().to_string() } else { "{}".to_string() },
                        cost, cost, qs
                    ));
                }
            } else if instr_type == "CRYPTO" {
                // A crypto order is sized by a dollar amount, never a quantity.
                let sym = instrument.and_then(|i| i.get("symbol")).and_then(|s| s.as_str()).unwrap_or("");
                let amount = body.get("amount").and_then(|v| v.as_str()).and_then(|a| a.parse::<f64>().ok());
                let limit = body.get("limitPrice").and_then(|v| v.as_str()).and_then(|p| p.parse::<f64>().ok());
                let has_qty = body.get("quantity").and_then(|v| v.as_str()).map(|q| !q.is_empty()).unwrap_or(false);
                if coin_price(sym).is_none() {
                    reply(&stream, 400, r#"{"message":"unknown coin"}"#);
                } else if has_qty || amount.is_none() || limit.is_none() {
                    reply(&stream, 400, r#"{"message":"a crypto order takes an amount and a limit price, not a quantity"}"#);
                } else if side == "SELL" {
                    reply(&stream, 400, r#"{"message":"no coins held"}"#);
                } else {
                    let (a, p) = (amount.unwrap(), limit.unwrap());
                    reply_fmt(&stream, 200, format!(
                        r#"{{"instrument":{},"orderValue":"{:.2}","estimatedCost":"{:.2}","estimatedQuantity":"{:.8}"}}"#,
                        instrument.unwrap(), a, a, a / p
                    ));
                }
            } else if side == "SELL" {
                reply(&stream, 400, r#"{"message":"insufficient shares"}"#);
            } else {
                reply(&stream, 200, r#"{"instrument":{"symbol":"SPY","type":"EQUITY"},"orderValue":"1000.00","estimatedCost":"1000.00"}"#);
            }

        // ── Option expirations ────────────────────────────────────────
        } else if route_path.ends_with("/option-expirations") {
            reply(&stream, 200, r#"{"expirations":["2026-11-06","2026-11-13","2026-11-20","2026-12-18"]}"#);

        // ── Option chain ──────────────────────────────────────────────
        } else if route_path.ends_with("/option-chain") {
            let sym = body.get("instrument").and_then(|i| i.get("symbol").and_then(|s| s.as_str())).unwrap_or("SPY");
            let exp = body.get("expirationDate").and_then(|v| v.as_str()).unwrap_or("2026-11-13");
            reply(&stream, 200, &chain(&sym, &exp));

        // ── Greeks ────────────────────────────────────────────────────
        } else if route_path.ends_with("/greeks") {
            let query_part = path.split("?").last().unwrap_or("");
            let params = query_part.split("&");
            let mut greeks_list: Vec<String> = Vec::new();
            for param in params {
                let kv = param.split("=").collect::<Vec<&str>>();
                if kv.len() == 2 && kv[0] == "osiSymbols" {
                    let sym = kv[1];
                    if !sym.is_empty() {
                        let g = greeks_of(&sym);
                        // The greeks JSON starts with {, so embed it directly
                        greeks_list.push(format!(
                            r#"{{"instrument":{{"symbol":"{}","type":"OPTION"}},{}"#, sym, &g[1..g.len()]
                        ));
                    }
                }
            }
            reply_fmt(&stream, 200, format!(r#"{{"greeks":[{}]}}"#, greeks_list.join(",")));

        // ── Quotes ────────────────────────────────────────────────────
        } else if route_path.ends_with("/quotes") {
            let instruments_val = body.get("instruments").and_then(|v| v.as_array());
            let instruments: Vec<serde_json::Value> = if instruments_val.is_some() {
                instruments_val.unwrap().clone()
            } else { Vec::new() };
            let mut quotes: Vec<String> = Vec::new();
            for instr in instruments {
                let sym = instr.get("symbol").and_then(|s| s.as_str()).unwrap_or("");
                let kind = instr.get("type").and_then(|t| t.as_str()).unwrap_or("");
                if kind == "EVENTCONTRACT" && is_known_contract(&sym) {
                    let price = contract_price(&sym);
                    let bid = if price - 0.02 < 0.0 { 0.0 } else { price - 0.02 };
                    let ask_ = price + 0.02;
                    quotes.push(format!(
                        r#"{{"instrument":{{"symbol":"{}","type":"{}"}},"outcome":"SUCCESS","last":"{:.2}","bid":"{:.2}","ask":"{:.2}","bidSize":50,"askSize":50,"volume":100}}"#,
                        sym, kind, price, bid, ask_
                    ));
                } else if kind == "CRYPTO" && coin_price(sym).is_some() {
                    let price = coin_price(sym).unwrap();
                    quotes.push(format!(
                        r#"{{"instrument":{{"symbol":"{}","type":"CRYPTO"}},"outcome":"SUCCESS","last":"{:.2}","bid":"{:.2}","ask":"{:.2}","bidSize":1,"askSize":1,"volume":1000}}"#,
                        sym, price, price - 5.0, price + 5.0
                    ));
                } else {
                    quotes.push(format!(
                        r#"{{"instrument":{{"symbol":"{}","type":"{}"}},"outcome":"UNKNOWN"}}"#,
                        sym, kind
                    ));
                }
            }
            reply_fmt(&stream, 200, format!(r#"{{"quotes":[{}]}}"#, quotes.join(",")));

        // ── Place order (POST) ────────────────────────────────────────
        } else if route_path.ends_with("/order") && method == "POST" {
            let oid = body.get("orderId").and_then(|v| v.as_str()).unwrap_or("");
            let final_id = if oid.is_empty() {
                let mut counter: u32;
                unsafe { ORDER_COUNTER += 1; counter = ORDER_COUNTER; }
                format!("stub-{}", counter)
            } else {
                oid.to_string()
            };
            store_order(&final_id, &body_str);
            reply_fmt(&stream, 200, format!(r#"{{"orderId":"{}"}}"#, final_id));

        // ── Cancel order (DELETE): an empty reply, as Public gives ────
        } else if route_path.contains("/order/") && method == "DELETE" {
            let order_id = route_path.rsplit('/').next().unwrap_or("").to_string();
            if find_order(&order_id).is_some() {
                unsafe { CANCELLED.push(order_id); }
                reply(&stream, 200, "");
            } else {
                reply(&stream, 404, r#"{"message":"no such order"}"#);
            }

        // ── Read order by id (GET) ────────────────────────────────────
        } else if route_path.contains("/order/") && method == "GET" {
            let route_str = route_path.as_str();
            let last_slash = route_str.rfind("/");
            let order_id = if last_slash.is_some() {
                (&route_str[last_slash.unwrap() + 1..]).to_string()
            } else { route_str.to_string() };
            let found = find_order(&order_id);
            if found.is_some() {
                let ob = found.unwrap();
                let parsed = serde_json::from_str::<serde_json::Value>(ob).unwrap_or(
                    serde_json::from_str::<serde_json::Value>("{}").expect("{}")
                );
                let side = parsed.get("orderSide").and_then(|v| v.as_str()).unwrap_or("");
                // A crypto order sized by amount fills for amount / limit coins.
                let sized = parsed.get("amount").and_then(|v| v.as_str()).and_then(|a| a.parse::<f64>().ok())
                    .zip(parsed.get("limitPrice").and_then(|v| v.as_str()).and_then(|p| p.parse::<f64>().ok()))
                    .map(|(a, p)| format!("{:.8}", a / p));
                let qty_owned = sized.unwrap_or_else(|| parsed.get("quantity").and_then(|v| v.as_str()).unwrap_or("").to_string());
                let qty = qty_owned.as_str();
                let instr = parsed.get("instrument");
                let instr_str = if instr.is_some() { instr.unwrap().to_string() } else { r#"{"symbol":"SPY","type":"EQUITY"}"#.to_string() };
                // A cancelled order reads CANCELLED; a limit of 0.01 rests far
                // from the market and stays NEW; anything else fills.
                let cancelled = unsafe { CANCELLED.contains(&order_id) };
                let resting = parsed.get("limitPrice").and_then(|v| v.as_str()) == Some("0.01");
                let status = if cancelled { "CANCELLED" } else if resting { "NEW" } else { "FILLED" };
                reply_fmt(&stream, 200, format!(
                    r#"{{"orderId":"{}","instrument":{},"side":"{}","quantity":"{}","status":"{}"}}"#,
                    order_id, instr_str, side, qty, status
                ));
            } else {
                reply(&stream, 404, r#"{"message":"no such order"}"#);
            }

        // ── 404 fallback ──────────────────────────────────────────────
        } else {
            reply_fmt(&stream, 404, format!("{{\"message\":\"no {}\"}}", path));
        }
    }
}