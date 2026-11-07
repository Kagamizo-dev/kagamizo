//! HTTP client for Public's API: uses ureq for HTTPS or HTTP transport,
//! taking the base URL from PUBLIC_API_BASE_URL (default https://api.public.com).

use std::env;
use serde::Deserialize;

use ureq::{self, AgentBuilder, Error};

use crate::endpoints::{Bound, Endpoint};
use crate::types::{
    AGGREGATIONS, EVENT_SORTING_MODES, EVENT_CONTRACT_PERIODS,
    EVENT_CONTRACT_MAX_SYMBOLS, INSTRUMENT_TYPES,
    AccessTokenRequest, AccessTokenResponse,
    AccountResponse,
    Instrument,
    BarsResponse, BarRow,
    PreflightResponse,
    OptionInstrument, OptionExpirationsRequest, OptionExpirationsResponse,
    OptionChainRequest, OptionChainResponse,
    GreeksResponse,
    QuoteInstrument, QuotesRequest, Quote, QuotesResponse,
    EventSummaryRequest, EventSummaryResponse, EventSummary, EventSummaryFilters,
    EventDetailsResponse,
    EventContractBarsResponse,
    OrderBody, OrderExpiration, PlaceOrderResponse, OrderResponse,
    PublicErrorBody,
};

/// Resolve the base URL from PUBLIC_API_BASE_URL (default https://api.public.com).
pub fn base_url_from_env() -> String {
    let raw = env::var("PUBLIC_API_BASE_URL").unwrap_or("https://api.public.com".to_string());
    raw.trim_end_matches("/").to_string()
}

// ── helpers ──────────────────────────────────────────────────────────────

fn url_encode(v: &str) -> String {
    let mut out = String::new();
    for b in v.as_bytes() {
        let val = *b;
        if (val >= b'a' && val <= b'z') || (val >= b'A' && val <= b'Z')
            || (val >= b'0' && val <= b'9') || val == b'-' || val == b'_'
            || val == b'.' || val == b'~'
        {
            out.push(char::from_u32(val as u32).expect("char"));
        } else if val == b' ' {
            out.push('+');
        } else {
            let hi = (val >> 4) & 0x0F;
            let lo = val & 0x0F;
            out.push('%');
            out.push(hex_digit(hi));
            out.push(hex_digit(lo));
        }
    }
    out
}

fn hex_digit(v: u8) -> char {
    if v < 10 {
        char::from_u32(('0' as u8 + v) as u32).expect("hex")
    } else {
        char::from_u32(('A' as u8 + (v - 10)) as u32).expect("hex")
    }
}

/// Send an HTTP request via ureq and return (status, body_string).
/// Handles Status errors from ureq (4xx/5xx) as regular responses.
fn ureq_http(
    method: &str, base_url: &str, path: &str, extra_headers: &str, body: Option<&str>,
) -> Result<(u32, String), String> {
    let url = format!("{}{}", base_url, path);
    let agent = AgentBuilder::new().build();
    let mut req = agent.request(method, &url)
        .set("Accept", "application/json");

    // Apply custom headers
    for line in extra_headers.split("\r\n") {
        if line.is_empty() { continue; }
        let colon = line.find(":");
        if colon.is_some() {
            let k = (&line[0..colon.unwrap()]).trim();
            let v = (&line[colon.unwrap() + 1..]).trim();
            if !k.is_empty() && !v.is_empty() {
                req = req.set(&k, &v);
            }
        }
    }

    // Send with body if present
    let resp_result = if body.is_some() {
        let b = body.unwrap();
        if !b.is_empty() {
            req = req.set("Content-Length", &b.len().to_string());
        }
        req.send_string(b)
    } else {
        req.call()
    };

    // Handle both Ok and Status errors (Status means 4xx/5xx response)
    let resp = if resp_result.is_ok() {
        resp_result.unwrap()
    } else {
        let err = resp_result.unwrap_err();
        match err {
            // Status errors carry the response body; extract it
            Error::Status(_code, response) => response,
            // Real transport/IO errors
            Error::Transport(t) => {
                return Result::Err(format!("{} {}: transport error: {:?}", method, &url, t.kind()));
            }
        }
    };

    let status: u32 = resp.status() as u32;
    let body_str = resp.into_string().unwrap_or("".to_string());
    Result::Ok((status, body_str))
}

/// Deserialize JSON response, checking for errors.
fn parse_json<T: for<'a> Deserialize<'a> + std::fmt::Debug>(
    status: u32, body_str: &str, method: &str, path: &str,
) -> Result<T, String> {
    if status >= 400 {
        let parsed = serde_json::from_str::<PublicErrorBody>(body_str);
        let detail = if parsed.is_ok() {
            parsed.unwrap().message.unwrap_or(body_str.to_string())
        } else {
            body_str.to_string()
        };
        return Result::Err(format!("{} {}: HTTP {} {}", method, path, status, detail));
    }
    if body_str.is_empty() {
        return Result::Err("empty response body".to_string());
    }
    let parsed = serde_json::from_str::<T>(body_str);
    if parsed.is_err() {
        return Result::Err(format!("json parse error: {:?}", parsed.unwrap_err()));
    }
    Result::Ok(parsed.unwrap())
}

/// Helper: build auth header value from token.
fn auth_header(token: &str) -> String {
    format!("Bearer {}", token)
}

/// Helper: build common headers string (without auth).
fn common_headers(body_json: bool) -> String {
    let mut h = String::new();
    h.push_str("Accept: application/json\r\n");
    if body_json {
        h.push_str("Content-Type: application/json\r\n");
    }
    h
}

// ── Public client ────────────────────────────────────────────────────────

pub struct Public {
    pub secret: String,
    pub token_value: Option<String>,
    pub account_id: Option<String>,
    pub base_url: String,
    /// The endpoints this client may call (crate::endpoints).
    pub bound: Bound,
}

impl Public {
    pub fn new(
        secret: Option<String>, account_id: Option<String>,
    ) -> Self {
        let s = secret.unwrap_or(
            env::var("PUBLIC_PERSONAL_SECRET").unwrap_or("".to_string())
        );
        let acct_str = account_id.unwrap_or(
            env::var("PUBLIC_ACCOUNT_ID").unwrap_or("".to_string())
        );
        let base = base_url_from_env();
        Self::new_with_url(&s, &acct_str, &base)
    }

    pub fn new_with_url(
        secret: &str, account_id: &str, base_url: &str,
    ) -> Self {
        Self {
            secret: secret.to_string(),
            token_value: None,
            account_id: if account_id.is_empty() { None } else { Some(account_id.to_string()) },
            base_url: base_url.to_string(),
            bound: Bound::Reader,
        }
    }

    /// The same client, allowed the one single-leg order: `trade place`'s.
    pub fn placer(mut self) -> Self {
        self.bound = Bound::Placer;
        self
    }

    /// Low-level: send a request, ensure auth token first.
    fn do_req<T: for<'b> Deserialize<'b> + std::fmt::Debug>(
        &mut self, endpoint: Endpoint, path: &str, body_json: Option<&str>,
    ) -> Result<T, String> {
        let method = endpoint.spec().method.as_str();
        self.bound.check(endpoint, method, path)?;
        // Ensure token if we have a secret
        if self.token_value.is_none() && !self.secret.is_empty()
            && self.bound.check(Endpoint::CreatePersonalAccessToken, "POST", "/userapiauthservice/personal/access-tokens").is_ok()
        {
            let req_body = AccessTokenRequest {
                secret: self.secret.clone(),
                validity_in_minutes: 15,
            };
            let json = serde_json::to_string(&req_body).expect("ser");
            let (status, resp_body) = ureq_http(
                "POST", &self.base_url, "/userapiauthservice/personal/access-tokens",
                "Accept: application/json\r\nContent-Type: application/json\r\n",
                Some(&json),
            ).unwrap_or((0, "".to_string()));
            if status == 200 && !resp_body.is_empty() {
                let parsed = serde_json::from_str::<AccessTokenResponse>(&resp_body);
                if parsed.is_ok() {
                    self.token_value = Some(parsed.unwrap().access_token);
                }
            }
        }

        let mut headers = common_headers(body_json.is_some());
        if self.token_value.is_some() {
            let tok = self.token_value.as_ref().unwrap();
            headers.push_str("Authorization: ");
            headers.push_str(&auth_header(tok));
            headers.push_str("\r\n");
        }

        let (status, resp_body) = ureq_http(
            method, &self.base_url, path, &headers, body_json,
        ).unwrap_or((0, "".to_string()));

        parse_json::<T>(status, &resp_body, method, path)
    }

    pub fn token(&mut self) -> Result<String, String> {
        if self.token_value.is_some() {
            return Result::Ok(self.token_value.as_ref().unwrap().clone());
        }
        self.bound.check(Endpoint::CreatePersonalAccessToken, "POST", "/userapiauthservice/personal/access-tokens")?;
        let req_body = AccessTokenRequest {
            secret: self.secret.clone(),
            validity_in_minutes: 15,
        };
        let json = serde_json::to_string(&req_body).expect("ser");
        let (status, resp_body) = ureq_http(
            "POST", &self.base_url, "/userapiauthservice/personal/access-tokens",
            "Accept: application/json\r\nContent-Type: application/json\r\n",
            Some(&json),
        ).unwrap_or((0, "".to_string()));
        if status >= 400 {
            let parsed = serde_json::from_str::<PublicErrorBody>(&resp_body);
            let detail = if parsed.is_ok() {
                parsed.unwrap().message.unwrap_or(resp_body.to_string())
            } else {
                resp_body.to_string()
            };
            return Result::Err(format!("auth failed: HTTP {} {}", status, detail));
        }
        let parsed = parse_json::<AccessTokenResponse>(status, &resp_body, "POST", "/userapiauthservice/personal/access-tokens");
        if parsed.is_err() { return Result::Err(parsed.unwrap_err()); }
        let tok = parsed.unwrap().access_token;
        self.token_value = Some(tok.clone());
        Result::Ok(tok)
    }

    pub fn account(&mut self) -> Result<String, String> {
        if self.account_id.is_some() {
            return Result::Ok(self.account_id.as_ref().unwrap().clone());
        }
        let resp = self.do_req::<AccountResponse>(Endpoint::GetAccounts, "/userapigateway/trading/account", None);
        if resp.is_err() { return Result::Err(resp.unwrap_err()); }
        let accounts = resp.unwrap().accounts;
        let mut brokerage: Vec<String> = Vec::new();
        for a in accounts {
            if a.account_type.unwrap_or("".to_string()) == "BROKERAGE" {
                brokerage.push(a.account_id);
            }
        }
        if brokerage.len() != 1 {
            return Result::Err(format!(
                "expected one BROKERAGE account, found {}; set PUBLIC_ACCOUNT_ID",
                brokerage.len(),
            ));
        }
        let acct = brokerage[0].clone();
        self.account_id = Some(acct.clone());
        Result::Ok(acct)
    }

    pub fn instrument(&mut self, symbol: &str, kind: &str) -> Result<serde_json::Value, String> {
        let path = format!("/userapigateway/trading/instruments/{}/{}", symbol.to_uppercase(), kind);
        self.do_req::<serde_json::Value>(Endpoint::GetInstrument, &path, None)
    }

    pub fn bars(
        &mut self, symbol: &str, step: &str, period: Option<&str>,
        kind: &str, _session: &str,
    ) -> Result<Vec<BarRow>, String> {
        let mut aggregation: Option<&str> = None;
        let mut longest: Option<&str> = None;
        for (s, agg, lp) in AGGREGATIONS {
            if *s == step {
                aggregation = Some(agg);
                longest = Some(lp);
                break;
            }
        }
        if aggregation.is_none() {
            let mut valid: Vec<&str> = Vec::new();
            for (s, _, _) in AGGREGATIONS { valid.push(s); }
            return Result::Err(format!(
                "Public serves no {} bars; it serves {}", step, valid.join(", "),
            ));
        }
        let p = period.unwrap_or(longest.unwrap());
        let path = format!("/userapigateway/historicdata/{}/{}/{}/{}", kind, symbol.to_uppercase(), p, aggregation.unwrap());
        let resp = self.do_req::<BarsResponse>(Endpoint::GetBarsV2WithAggregation, &path, None);
        if resp.is_err() { return Result::Err(resp.unwrap_err()); }
        let br = resp.unwrap();
        let session_opt = br.regular_market;
        if session_opt.is_none() {
            return Result::Ok(Vec::new());
        }
        let session = session_opt.unwrap();
        let mut rows: Vec<BarRow> = Vec::new();
        for b in session.bars {
            rows.push(BarRow {
                timestamp: b.timestamp,
                open: b.open,
                high: b.high,
                low: b.low,
                close: b.close,
                volume: b.volume,
            });
        }
        rows.sort();
        Result::Ok(rows)
    }

    pub fn preflight(&mut self, order_json: &str) -> Result<PreflightResponse, String> {
        let a = self.account();
        if a.is_err() { return Result::Err(a.unwrap_err()); }
        let path = format!("/userapigateway/trading/{}/preflight/single-leg", a.unwrap());
        self.do_req::<PreflightResponse>(Endpoint::PreflightSingleLeg, &path, Some(order_json))
    }

    pub fn option_expirations(&mut self, symbol: &str, kind: &str) -> Result<Vec<String>, String> {
        let a = self.account();
        if a.is_err() { return Result::Err(a.unwrap_err()); }
        let path = format!("/userapigateway/marketdata/{}/option-expirations", a.unwrap());
        let body = OptionExpirationsRequest {
            instrument: OptionInstrument { symbol: symbol.to_uppercase(), kind: kind.to_string() },
        };
        let json = serde_json::to_string(&body).expect("ser");
        let resp = self.do_req::<OptionExpirationsResponse>(Endpoint::GetOptionExpirations, &path, Some(&json));
        if resp.is_err() { return Result::Err(resp.unwrap_err()); }
        let r = resp.unwrap();
        let mut result: Vec<String> = Vec::new();
        if r.expirations.is_some() { for e in r.expirations.unwrap() { result.push(e); } }
        if r.expiration_dates.is_some() { for e in r.expiration_dates.unwrap() { result.push(e); } }
        result.sort();
        Result::Ok(result)
    }

    pub fn option_chain(
        &mut self, symbol: &str, expiration: &str, kind: &str,
    ) -> Result<OptionChainResponse, String> {
        let a = self.account();
        if a.is_err() { return Result::Err(a.unwrap_err()); }
        let path = format!("/userapigateway/marketdata/{}/option-chain", a.unwrap());
        let body = OptionChainRequest {
            instrument: OptionInstrument { symbol: symbol.to_uppercase(), kind: kind.to_string() },
            expiration_date: expiration.to_string(),
        };
        let json = serde_json::to_string(&body).expect("ser");
        self.do_req::<OptionChainResponse>(Endpoint::GetOptionChain, &path, Some(&json))
    }

    pub fn greeks(
        &mut self, osi_symbols: Vec<String>,
    ) -> Result<std::collections::HashMap<String, std::collections::HashMap<String, Option<f64>>>, String> {
        let a = self.account();
        if a.is_err() { return Result::Err(a.unwrap_err()); }
        let mut qparts: Vec<String> = Vec::new();
        for s in osi_symbols {
            qparts.push(format!("osiSymbols={}", url_encode(&s)));
        }
        let query = qparts.join("&");
        let path = format!("/userapigateway/option-details/{}/greeks?{}", a.unwrap(), query);
        let resp = self.do_req::<GreeksResponse>(Endpoint::GetOptionGreeks, &path, None);
        if resp.is_err() { return Result::Err(resp.unwrap_err()); }
        let gr = resp.unwrap();
        let mut found: std::collections::HashMap<String, std::collections::HashMap<String, Option<f64>>> = std::collections::HashMap::new();
        if gr.greeks.is_some() {
            for g in gr.greeks.unwrap() {
                let sym = if g.instrument.is_some() {
                    g.instrument.unwrap().symbol
                } else if g.osi_symbol.is_some() {
                    g.osi_symbol.unwrap()
                } else if g.symbol.is_some() {
                    g.symbol.unwrap()
                } else {
                    "".to_string()
                };
                let mut fields: std::collections::HashMap<String, Option<f64>> = std::collections::HashMap::new();
                fields.insert("delta".to_string(), g.delta);
                fields.insert("gamma".to_string(), g.gamma);
                fields.insert("theta".to_string(), g.theta);
                fields.insert("vega".to_string(), g.vega);
                fields.insert("rho".to_string(), g.rho);
                fields.insert("impliedVolatility".to_string(), g.implied_volatility);
                found.insert(sym, fields);
            }
        }
        Result::Ok(found)
    }

    pub fn quotes(
        &mut self, instruments: Vec<(&str, &str)>,
    ) -> Result<Vec<Quote>, String> {
        let a = self.account();
        if a.is_err() { return Result::Err(a.unwrap_err()); }
        let path = format!("/userapigateway/marketdata/{}/quotes", a.unwrap());
        let mut body_instruments: Vec<QuoteInstrument> = Vec::new();
        for (symbol, kind) in instruments {
            let mut found = false;
            for t in INSTRUMENT_TYPES {
                if *t == kind { found = true; break; }
            }
            if !found {
                return Result::Err(format!("Public has no instrument type {}", kind));
            }
            body_instruments.push(QuoteInstrument { symbol: symbol.to_uppercase(), kind: kind.to_string() });
        }
        let json = serde_json::to_string(&QuotesRequest { instruments: body_instruments }).expect("ser");
        let resp = self.do_req::<QuotesResponse>(Endpoint::GetQuotes, &path, Some(&json));
        if resp.is_err() { return Result::Err(resp.unwrap_err()); }
        Result::Ok(resp.unwrap().quotes.unwrap_or(Vec::new()))
    }

    pub fn event_contract_summary(
        &mut self,
        category: Option<&str>, subcategory: Option<&str>,
        frequencies: &Vec<String>, include_resolved: Option<bool>,
        resolution_start: Option<&str>, resolution_end: Option<&str>,
        event_symbols: &Vec<String>, created_within_days: Option<u32>,
        next_token: Option<&str>, sort: &str,
    ) -> Result<EventSummaryResponse, String> {
        let mut sort_ok = false;
        for m in EVENT_SORTING_MODES { if *m == sort { sort_ok = true; break; } }
        if !sort_ok {
            return Result::Err(format!("sort is one of {}, not {}", EVENT_SORTING_MODES.join(", "), sort));
        }

        let has_filters = event_symbols.len() > 0 || frequencies.len() > 0
            || resolution_start.is_some() || resolution_end.is_some();

        let filters: Option<EventSummaryFilters> = if has_filters {
            let freq_list: Vec<String> = if frequencies.len() > 0 {
                frequencies.clone()
            } else {
                ["ALL".to_string()].to_vec()
            };
            let syms: Vec<String> = event_symbols.into_iter().map(|s| s.to_uppercase()).collect::<Vec<String>>();
            Some(EventSummaryFilters {
                event_symbols: if syms.is_empty() { None } else { Some(syms) },
                frequencies: freq_list,
                resolution_time_start: if resolution_start.is_some() { Some(resolution_start.unwrap().to_string()) } else { None },
                resolution_time_end: if resolution_end.is_some() { Some(resolution_end.unwrap().to_string()) } else { None },
            })
        } else { None };

        let req = EventSummaryRequest {
            sorting_mode: sort.to_string(),
            category: if category.is_some() { Some(category.unwrap().to_string()) } else { None },
            subcategory: if subcategory.is_some() { Some(subcategory.unwrap().to_string()) } else { None },
            next_token: if next_token.is_some() { Some(next_token.unwrap().to_string()) } else { None },
            display_resolved_events: if include_resolved.is_some() { Some(include_resolved.unwrap()) } else { None },
            created_within_days: if created_within_days.is_some() { Some(created_within_days.unwrap()) } else { None },
            filters: filters,
        };
        let json = serde_json::to_string(&req).expect("ser");
        self.do_req::<EventSummaryResponse>(Endpoint::GetEventSummary, "/userapigateway/eventcontract/summary", Some(&json))
    }

    pub fn event_contracts(
        &mut self, max_pages: u32,
        category: Option<&str>, subcategory: Option<&str>,
        frequencies: &Vec<String>, include_resolved: Option<bool>,
        resolution_start: Option<&str>, resolution_end: Option<&str>,
        event_symbols: &Vec<String>, created_within_days: Option<u32>,
    ) -> Result<Vec<EventSummary>, String> {
        let mut all: Vec<EventSummary> = Vec::new();
        let mut token: Option<String> = None;
        for _ in 0..max_pages {
            let nt: Option<String> = if token.is_some() {
                Some(token.as_ref().unwrap().clone())
            } else { None };
            let page = self.event_contract_summary(
                category, subcategory, frequencies, include_resolved,
                resolution_start, resolution_end, event_symbols,
                created_within_days,
                if nt.is_some() { Some(nt.as_ref().unwrap()) } else { None },
                "VOLUME",
            );
            if page.is_err() { return Result::Err(page.unwrap_err()); }
            let p = page.unwrap();
            if p.content.is_some() {
                for item in p.content.unwrap() { all.push(item); }
            }
            if p.next_token.is_some() {
                token = Some(p.next_token.unwrap());
            } else { break; }
        }
        Result::Ok(all)
    }

    pub fn event_contract_details(
        &mut self, event_symbol: &str, all_outcomes: bool,
    ) -> Result<EventDetailsResponse, String> {
        let sym = event_symbol.trim().to_uppercase();
        let path = format!("/userapigateway/eventcontract/details/{}?includeAllOutcomes={}", sym, if all_outcomes { "true" } else { "false" });
        self.do_req::<EventDetailsResponse>(Endpoint::GetEventDetails, &path, None)
    }

    pub fn event_contract_bars(
        &mut self, event_id: &str, period: &str, symbols: Vec<&str>,
    ) -> Result<EventContractBarsResponse, String> {
        let mut period_ok = false;
        for p in EVENT_CONTRACT_PERIODS { if *p == period { period_ok = true; break; } }
        if !period_ok {
            return Result::Err(format!("period is one of {}, not {}", EVENT_CONTRACT_PERIODS.join(", "), period));
        }
        let mut cleaned: Vec<String> = Vec::new();
        for s in symbols { let t = s.trim().to_uppercase(); if !t.is_empty() { cleaned.push(t); } }
        if cleaned.is_empty() || cleaned.len() > EVENT_CONTRACT_MAX_SYMBOLS {
            return Result::Err(format!("1 to {} symbols per request", EVENT_CONTRACT_MAX_SYMBOLS));
        }
        let path = format!("/userapigateway/historicdata/event-contracts/{}/bars/{}?symbols={}",
            event_id.to_uppercase(), period, url_encode(&cleaned.join(",")));
        self.do_req::<EventContractBarsResponse>(Endpoint::GetEventContractBars, &path, None)
    }

    /// Places one single-leg order; the one call here that moves money.
    pub fn place(&mut self, order_json: &str) -> Result<PlaceOrderResponse, String> {
        let a = self.account();
        if a.is_err() { return Result::Err(a.unwrap_err()); }
        let path = format!("/userapigateway/trading/{}/order", a.unwrap());
        self.do_req::<PlaceOrderResponse>(Endpoint::PlaceOrder, &path, Some(order_json))
    }

    /// Cancels a working order (the placer's one write): what ends an order
    /// still working after place's read-back. An empty reply is success.
    pub fn cancel(&mut self, order_id: &str) -> Result<(), String> {
        let a = self.account();
        if a.is_err() { return Result::Err(a.unwrap_err()); }
        let path = format!("/userapigateway/trading/{}/order/{}", a.unwrap(), order_id);
        match self.do_req::<serde_json::Value>(Endpoint::CancelOrder, &path, None) {
            Ok(_) => Ok(()),
            Err(e) if e == "empty response body" => Ok(()),
            Err(e) => Err(e),
        }
    }

    pub fn order(&mut self, order_id: &str) -> Result<OrderResponse, String> {
        let a = self.account();
        if a.is_err() { return Result::Err(a.unwrap_err()); }
        let path = format!("/userapigateway/trading/{}/order/{}", a.unwrap(), order_id);
        self.do_req::<OrderResponse>(Endpoint::GetOrder, &path, None)
    }
}

// ── Order body constructors ──────────────────────────────────────────────

pub fn order_body(
    symbol: &str, side: &str, order_type: &str, quantity: &str,
    time_in_force: &str, limit_price: Option<&str>, stop_price: Option<&str>,
    expire_time: Option<&str>,
) -> Result<OrderBody, String> {
    if side != "BUY" && side != "SELL" {
        return Result::Err(format!("Public has no order side {}", side));
    }
    if order_type != "MARKET" && order_type != "LIMIT" && order_type != "STOP" && order_type != "STOP_LIMIT" {
        return Result::Err(format!("Public has no {} orders", order_type));
    }

    let expiration: OrderExpiration;
    if order_type == "MARKET" || time_in_force == "DAY" {
        expiration = OrderExpiration { time_in_force: "DAY".to_string(), expiration_time: None };
    } else if time_in_force == "GTD" && expire_time.is_some() {
        expiration = OrderExpiration {
            time_in_force: "GTD".to_string(),
            expiration_time: Some(expire_time.unwrap().to_string()),
        };
    } else {
        return Result::Err(format!("Public takes DAY or GTD (with an expiry), not {}", time_in_force));
    }

    let mut body = OrderBody {
        instrument: Instrument { symbol: symbol.to_uppercase(), kind: "EQUITY".to_string() },
        order_side: side.to_string(), order_type: order_type.to_string(),
        expiration: expiration, quantity: quantity.to_string(),
        limit_price: None, stop_price: None, open_close_indicator: None, order_id: None,
    };
    if order_type == "LIMIT" || order_type == "STOP_LIMIT" {
        if limit_price.is_none() { return Result::Err(format!("a {} order needs a limit price", order_type)); }
        body.limit_price = Some(limit_price.unwrap().to_string());
    }
    if order_type == "STOP" || order_type == "STOP_LIMIT" {
        if stop_price.is_none() { return Result::Err(format!("a {} order needs a stop price", order_type)); }
        body.stop_price = Some(stop_price.unwrap().to_string());
    }
    Result::Ok(body)
}

pub fn option_order_body(
    osi_symbol: &str, side: &str, limit_price: &str, quantity: &str,
    open_close: &str, order_id: Option<&str>,
) -> Result<OrderBody, String> {
    if side != "BUY" && side != "SELL" { return Result::Err(format!("Public has no order side {}", side)); }
    if open_close != "OPEN" && open_close != "CLOSE" { return Result::Err(format!("openCloseIndicator is OPEN or CLOSE, not {}", open_close)); }
    let price_f: f64 = limit_price.parse::<f64>().unwrap_or(0.0);
    let mut body = OrderBody {
        instrument: Instrument { symbol: osi_symbol.to_string(), kind: "OPTION".to_string() },
        order_side: side.to_string(), order_type: "LIMIT".to_string(),
        expiration: OrderExpiration { time_in_force: "DAY".to_string(), expiration_time: None },
        quantity: quantity.to_string(),
        limit_price: Some(format!("{:.2}", price_f)),
        stop_price: None, open_close_indicator: Some(open_close.to_string()), order_id: None,
    };
    if order_id.is_some() { body.order_id = Some(order_id.unwrap().to_string()); }
    Result::Ok(body)
}

pub fn event_contract_order_body(
    symbol: &str, side: &str, limit_price: &str, quantity: &str,
    order_id: Option<&str>,
) -> Result<OrderBody, String> {
    if side != "BUY" && side != "SELL" { return Result::Err(format!("Public has no order side {}", side)); }
    let price_f: f64 = limit_price.parse::<f64>().unwrap_or(0.0);
    if price_f <= 0.0 || price_f >= 1.0 { return Result::Err(format!("an event contract's price is between 0.00 and 1.00, not {}", limit_price)); }
    let qty_f: f64 = quantity.parse::<f64>().unwrap_or(0.0);
    if qty_f < 1.0 || qty_f != (qty_f as u32 as f64) { return Result::Err(format!("an event-contract order is for whole contracts, not {}", quantity)); }
    let body = OrderBody {
        instrument: Instrument { symbol: symbol.trim().to_uppercase(), kind: "EVENTCONTRACT".to_string() },
        order_side: side.to_string(), order_type: "LIMIT".to_string(),
        expiration: OrderExpiration { time_in_force: "DAY".to_string(), expiration_time: None },
        quantity: (qty_f as u32).to_string(),
        limit_price: Some(format!("{:.2}", price_f)),
        stop_price: None, open_close_indicator: None,
        order_id: if order_id.is_some() { Some(order_id.unwrap().to_string()) } else { None },
    };
    Result::Ok(body)
}