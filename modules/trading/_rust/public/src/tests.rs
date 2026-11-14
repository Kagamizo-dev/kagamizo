//! Tests for kagamizo-public: order body constructors, serialization,
//! and validation logic (no network dependency).

use crate::client::{order_body, option_order_body, event_contract_order_body};
use crate::types::*;

fn assert_eq<T: PartialEq>(a: T, b: T, msg: &str) -> Result<(), String> {
    if a == b { Result::Ok(()) } else { Result::Err(msg.to_string()) }
}

fn assert_true(v: bool, msg: &str) -> Result<(), String> {
    if v { Result::Ok(()) } else { Result::Err(msg.to_string()) }
}

// ── order_body tests ────────────────────────────────────────────────────

#[test]
pub fn test_equity_market_buy() -> Result<(), String> {
    let body = order_body("SPY", "BUY", "MARKET", "10", "DAY", None, None, None);
    if body.is_err() { return Result::Err("order_body failed".to_string()); }
    let b = body.unwrap();
    assert_eq(b.order_side, "BUY".to_string(), "side")
    .and_then(|_| assert_eq(b.order_type, "MARKET".to_string(), "type"))
    .and_then(|_| assert_eq(b.quantity, "10".to_string(), "qty"))
    .and_then(|_| assert_eq(b.expiration.time_in_force, "DAY".to_string(), "tif"))
}

#[test]
pub fn test_equity_limit_sell() -> Result<(), String> {
    let body = order_body("AAPL", "SELL", "LIMIT", "5", "DAY", Some("150.50"), None, None);
    if body.is_err() { return Result::Err("limit sell failed".to_string()); }
    let b = body.unwrap();
    assert_eq(b.order_side, "SELL".to_string(), "side")
    .and_then(|_| assert_eq(b.limit_price.unwrap_or("".to_string()), "150.50".to_string(), "limit"))
}

#[test]
pub fn test_equity_stop_order() -> Result<(), String> {
    let body = order_body("TSLA", "SELL", "STOP", "3", "DAY", None, Some("200.00"), None);
    if body.is_err() { return Result::Err("stop order failed".to_string()); }
    assert_eq(body.unwrap().stop_price.unwrap_or("".to_string()), "200.00".to_string(), "stop")
}

#[test]
pub fn test_equity_stop_limit() -> Result<(), String> {
    let body = order_body("MSFT", "BUY", "STOP_LIMIT", "7", "DAY", Some("185.00"), Some("190.00"), None);
    if body.is_err() { return Result::Err("stop limit failed".to_string()); }
    let b = body.unwrap();
    assert_eq(b.limit_price.unwrap_or("".to_string()), "185.00".to_string(), "limit")
    .and_then(|_| assert_eq(b.stop_price.unwrap_or("".to_string()), "190.00".to_string(), "stop"))
}

#[test]
pub fn test_invalid_side() -> Result<(), String> {
    let body = order_body("SPY", "INVALID", "MARKET", "10", "DAY", None, None, None);
    if body.is_ok() { return Result::Err("expected error for invalid side".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_invalid_type() -> Result<(), String> {
    let body = order_body("SPY", "BUY", "INVALID", "10", "DAY", None, None, None);
    if body.is_ok() { return Result::Err("expected error for invalid type".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_limit_needs_limit() -> Result<(), String> {
    let body = order_body("SPY", "BUY", "LIMIT", "10", "DAY", None, None, None);
    if body.is_ok() { return Result::Err("limit order needs limit price".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_gtd_without_expiry() -> Result<(), String> {
    let body = order_body("SPY", "BUY", "LIMIT", "10", "GTD", Some("100.00"), None, None);
    if body.is_ok() { return Result::Err("GTD needs expire_time".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_gtd_with_expiry() -> Result<(), String> {
    let body = order_body("SPY", "BUY", "LIMIT", "10", "GTD", Some("100.00"), None, Some("2026-11-10T00:00:00Z"));
    if body.is_err() { return Result::Err("GTD with expiry should work".to_string()); }
    let b = body.unwrap();
    assert_eq(b.expiration.time_in_force, "GTD".to_string(), "tif gtd")
    .and_then(|_| assert_eq(b.expiration.expiration_time.unwrap_or("".to_string()), "2026-11-10T00:00:00Z".to_string(), "expiry"))
}

#[test]
pub fn test_symbol_uppercased() -> Result<(), String> {
    let body = order_body("spy", "BUY", "MARKET", "10", "DAY", None, None, None);
    if body.is_err() { return Result::Err("lowercase symbol".to_string()); }
    assert_eq(body.unwrap().instrument.symbol, "SPY".to_string(), "uppercased")
}

// ── option_order_body tests ──────────────────────────────────────────────

#[test]
pub fn test_option_buy_open() -> Result<(), String> {
    let body = option_order_body("SPY241106C00100000", "BUY", "1.50", "10", "OPEN", None);
    if body.is_err() { return Result::Err("option buy open".to_string()); }
    let b = body.unwrap();
    assert_eq(b.instrument.kind, "OPTION".to_string(), "option type")
    .and_then(|_| assert_eq(b.order_type, "LIMIT".to_string(), "limit type"))
    .and_then(|_| assert_eq(b.open_close_indicator.unwrap_or("".to_string()), "OPEN".to_string(), "open close"))
}

#[test]
pub fn test_option_sell_close() -> Result<(), String> {
    let body = option_order_body("SPY241106P00200000", "SELL", "2.00", "5", "CLOSE", Some("order-123"));
    if body.is_err() { return Result::Err("option sell close".to_string()); }
    let b = body.unwrap();
    assert_eq(b.order_side, "SELL".to_string(), "side")
    .and_then(|_| assert_eq(b.open_close_indicator.unwrap_or("".to_string()), "CLOSE".to_string(), "close"))
    .and_then(|_| assert_eq(b.order_id.unwrap_or("".to_string()), "order-123".to_string(), "order id"))
}

#[test]
pub fn test_option_invalid_side() -> Result<(), String> {
    let body = option_order_body("SPY241106C00100000", "HOLD", "1.00", "10", "OPEN", None);
    if body.is_ok() { return Result::Err("invalid option side".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_option_invalid_open_close() -> Result<(), String> {
    let body = option_order_body("SPY241106C00100000", "BUY", "1.00", "10", "HOLD", None);
    if body.is_ok() { return Result::Err("invalid open close".to_string()); }
    Result::Ok(())
}

// ── event_contract_order_body tests ──────────────────────────────────────

#[test]
pub fn test_event_buy() -> Result<(), String> {
    let body = event_contract_order_body("KALSHI.KXHIGHNY-26NOV06-T72.Y", "BUY", "0.50", "10", None);
    if body.is_err() { return Result::Err("event buy".to_string()); }
    let b = body.unwrap();
    assert_eq(b.instrument.kind, "EVENTCONTRACT".to_string(), "event type")
    .and_then(|_| assert_eq(b.quantity, "10".to_string(), "qty"))
    .and_then(|_| assert_eq(b.limit_price.unwrap_or("".to_string()), "0.50".to_string(), "price"))
}

#[test]
pub fn test_event_sell() -> Result<(), String> {
    let body = event_contract_order_body("KALSHI.KXHIGHNY-26NOV06-T72.N", "SELL", "0.30", "5", Some("evt-1"));
    if body.is_err() { return Result::Err("event sell".to_string()); }
    let b = body.unwrap();
    assert_eq(b.order_side, "SELL".to_string(), "side")
    .and_then(|_| assert_eq(b.order_id.unwrap_or("".to_string()), "evt-1".to_string(), "order id"))
}

#[test]
pub fn test_event_price_too_low() -> Result<(), String> {
    let body = event_contract_order_body("TEST.Y", "BUY", "0.00", "10", None);
    if body.is_ok() { return Result::Err("price 0 should fail".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_event_price_too_high() -> Result<(), String> {
    let body = event_contract_order_body("TEST.Y", "BUY", "1.00", "10", None);
    if body.is_ok() { return Result::Err("price 1 should fail".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_event_fractional_quantity() -> Result<(), String> {
    let body = event_contract_order_body("TEST.Y", "BUY", "0.50", "10.5", None);
    if body.is_ok() { return Result::Err("fractional qty should fail".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_event_symbol_uppercased() -> Result<(), String> {
    let body = event_contract_order_body("test.y", "BUY", "0.50", "10", None);
    if body.is_err() { return Result::Err("lowercase symbol".to_string()); }
    assert_eq(body.unwrap().instrument.symbol, "TEST.Y".to_string(), "uppercased")
}

// ── Serialization tests ─────────────────────────────────────────────────

#[test]
pub fn test_order_body_serializes() -> Result<(), String> {
    let body = order_body("SPY", "BUY", "MARKET", "10", "DAY", None, None, None);
    if body.is_err() { return Result::Err("create".to_string()); }
    let json = serde_json::to_string(&body.unwrap()).expect("serialize");
    if !json.contains("SPY") { return Result::Err("json has symbol".to_string()); }
    if !json.contains("BUY") { return Result::Err("json has side".to_string()); }
    if !json.contains("orderType") { return Result::Err("json has type".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_instrument_serializes() -> Result<(), String> {
    let inst = Instrument { symbol: "SPY".to_string(), kind: "EQUITY".to_string() };
    let json = serde_json::to_string(&inst).expect("serialize");
    if !json.contains("SPY") { return Result::Err("json has symbol".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_bars_response_deserializes() -> Result<(), String> {
    let json = r#"{"symbol":"SPY","period":"FIVE_YEARS","totalExpectedBars":2,"regularMarket":{"expectedBars":2,"bars":[{"timestamp":"2026-10-28T14:00:00Z","open":"150.00","high":"151.00","low":"149.50","close":"150.50","volume":1000}]}}"#;
    let parsed = serde_json::from_str::<BarsResponse>(json).expect("parse");
    if parsed.symbol != "SPY".to_string() { return Result::Err("symbol".to_string()); }
    if parsed.regular_market.is_none() { return Result::Err("no regularMarket".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_event_summary_response_deserializes() -> Result<(), String> {
    let json = r#"{"content":[{"title":"Test","eventSymbol":"KALSHI.TEST","volume":"100","category":"Weather","subcategories":["Rain"],"symbols":["TEST.Y"],"resolutionTime":"2026-11-07T00:00:00Z","resolved":false,"halted":false}],"nextToken":null}"#;
    let parsed = serde_json::from_str::<EventSummaryResponse>(json).expect("parse");
    if parsed.content.is_none() { return Result::Err("no content".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_event_details_response_deserializes() -> Result<(), String> {
    let json = r#"{"eventSymbol":"KALSHI.TEST","exchange":"KALSHI","title":"Test","category":"Weather","volume":"100","subcategories":["Rain"],"cftcContract":{"prohibitions":[],"resolutionSources":[],"contractTermsUrl":"https://kalshi.com/terms"},"outcomeCount":1,"outcomes":[{"outcomeId":"T1","title":"Yes","rules":"...","volume":"100","state":"STATE_OPEN","timeline":{"openTime":"2026-10-30T14:00:00Z","closeTime":"2026-11-07T04:59:00Z","expectedExpirationTime":"2026-11-07T04:59:00Z"},"settledOutcome":"UNSETTLED","trading":"BUY_AND_SELL","contracts":[{"symbol":"T1.Y","predictedOutcome":"YES","bid":"0.18","ask":"0.20","last":"0.19","openInterest":"120","probability":"0.19"}]}],"resolved":false,"halted":false}"#;
    let _ = serde_json::from_str::<EventDetailsResponse>(json).expect("parse");
    Result::Ok(())
}

#[test]
pub fn test_option_chain_response_deserializes() -> Result<(), String> {
    let json = r#"{"baseSymbol":"SPY","calls":[],"puts":[]}"#;
    let _ = serde_json::from_str::<OptionChainResponse>(json).expect("parse");
    Result::Ok(())
}

#[test]
pub fn test_quotes_response_deserializes() -> Result<(), String> {
    let json = r#"{"quotes":[{"instrument":{"symbol":"SPY","type":"EQUITY"},"outcome":"SUCCESS","last":"150.00","bid":"149.50","ask":"150.50","bidSize":100,"askSize":100,"volume":500}]}"#;
    let _ = serde_json::from_str::<QuotesResponse>(json).expect("parse");
    Result::Ok(())
}

#[test]
pub fn test_greeks_response_deserializes() -> Result<(), String> {
    let json = r#"{"greeks":[{"instrument":{"symbol":"SPY241106C00100000","type":"OPTION"},"delta":0.5,"gamma":0.02}]}"#;
    let _ = serde_json::from_str::<GreeksResponse>(json).expect("parse");
    Result::Ok(())
}

#[test]
pub fn test_event_contract_bars_response_deserializes() -> Result<(), String> {
    let json = r#"{"period":"WEEK","charts":[{"symbol":"TEST.Y","previousClosePrice":"0.50","currentPrice":"0.55","bars":[{"timestamp":"2026-11-03T00:00:00Z","open":"0.50","high":"0.55","low":"0.48","close":"0.52","value":"0.52","volume":10}]}]}"#;
    let _ = serde_json::from_str::<EventContractBarsResponse>(json).expect("parse");
    Result::Ok(())
}

#[test]
pub fn test_preflight_response_deserializes() -> Result<(), String> {
    let json = r#"{"instrument":{"symbol":"SPY","type":"EQUITY"},"orderValue":"1000.00","estimatedCost":"1000.00"}"#;
    let _ = serde_json::from_str::<PreflightResponse>(json).expect("parse");
    Result::Ok(())
}

#[test]
pub fn test_order_response_deserializes() -> Result<(), String> {
    let json = r#"{"orderId":"stub-1","status":"FILLED"}"#;
    let _ = serde_json::from_str::<OrderResponse>(json).expect("parse");
    Result::Ok(())
}

#[test]
pub fn test_place_response_deserializes() -> Result<(), String> {
    let json = r#"{"orderId":"stub-1"}"#;
    let p = serde_json::from_str::<PlaceOrderResponse>(json).expect("parse");
    if p.order_id != "stub-1".to_string() { return Result::Err("bad order_id".to_string()); }
    Result::Ok(())
}

#[test]
pub fn test_error_body_deserializes() -> Result<(), String> {
    let json = r#"{"message":"bad request"}"#;
    let eb = serde_json::from_str::<PublicErrorBody>(json).expect("parse");
    if eb.message.unwrap_or("".to_string()) != "bad request".to_string() {
        return Result::Err("bad message".to_string());
    }
    Result::Ok(())
}

#[test]
pub fn test_option_expirations_response_deserializes() -> Result<(), String> {
    let json = r#"{"expirations":["2026-11-06","2026-11-13"]}"#;
    let r = serde_json::from_str::<OptionExpirationsResponse>(json).expect("parse");
    if r.expirations.is_none() { return Result::Err("no expirations".to_string()); }
    Result::Ok(())
}
