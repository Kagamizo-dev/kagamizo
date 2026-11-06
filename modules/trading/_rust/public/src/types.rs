//! Serde types for Public's API: requests and responses are typed structs
//! and enums, matching _public.py field for field.

use serde::{Deserialize, Serialize};

// ── Constants ────────────────────────────────────────────────────────────

/// NautilusTrader's bar steps, as Public's aggregation and the longest period
/// Public serves at that aggregation.
pub static AGGREGATIONS: &[(&str, &str, &str)] = &[
    ("1-MINUTE",    "ONE_MINUTE",    "DAY"),
    ("5-MINUTE",    "FIVE_MINUTES",  "WEEK"),
    ("10-MINUTE",   "TEN_MINUTES",   "WEEK"),
    ("15-MINUTE",   "FIFTEEN_MINUTES", "MONTH"),
    ("30-MINUTE",   "THIRTY_MINUTES","MONTH"),
    ("1-HOUR",      "ONE_HOUR",      "QUARTER"),
    ("1-DAY",       "ONE_DAY",       "FIVE_YEARS"),
    ("1-WEEK",      "ONE_WEEK",      "TEN_YEARS"),
];

/// Event sorting mode names.
pub static EVENT_SORTING_MODES: &[&str] = &["VOLUME", "EXPIRATION", "RECENTLY_ADDED"];

/// Event frequency names.
pub static EVENT_FREQUENCIES: &[&str] = &[
    "ALL", "ONCE", "FIFTEEN_MINUTES", "ONE_HOUR", "ONE_DAY", "ONE_WEEK",
    "ONE_MONTH", "ONE_YEAR",
];

/// Event contract period names.
pub static EVENT_CONTRACT_PERIODS: &[&str] = &["DAY", "WEEK", "MONTH", "ALL"];

/// Max event contract symbols per request.
pub static EVENT_CONTRACT_MAX_SYMBOLS: usize = 8;

/// Instrument type names.
pub static INSTRUMENT_TYPES: &[&str] = &[
    "EQUITY", "OPTION", "MULTI_LEG_INSTRUMENT", "CRYPTO", "ALT",
    "TREASURY", "BOND", "INDEX", "EVENTCONTRACT",
];

// ── Auth ─────────────────────────────────────────────────────────────────

/// Request body for POST /userapiauthservice/personal/access-tokens.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessTokenRequest {
    pub secret: String,
    #[serde(rename = "validityInMinutes")]
    pub validity_in_minutes: u32,
}

/// Response from POST /userapiauthservice/personal/access-tokens.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessTokenResponse {
    #[serde(rename = "accessToken")]
    pub access_token: String,
}

// ── Account ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountEntry {
    #[serde(rename = "accountId")]
    pub account_id: String,
    #[serde(rename = "accountType")]
    pub account_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountResponse {
    pub accounts: Vec<AccountEntry>,
}

// ── Instrument ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Instrument {
    pub symbol: String,
    #[serde(rename = "type")]
    pub kind: String,
}

// ── Bars ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bar {
    pub timestamp: String,
    pub open: String,
    pub high: String,
    pub low: String,
    pub close: String,
    pub volume: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BarSession {
    #[serde(rename = "expectedBars")]
    pub expected_bars: u64,
    pub bars: Vec<Bar>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BarsResponse {
    pub symbol: String,
    pub period: String,
    #[serde(rename = "totalExpectedBars")]
    pub total_expected_bars: Option<u64>,
    #[serde(rename = "regularMarket")]
    pub regular_market: Option<BarSession>,
    #[serde(rename = "preMarket")]
    pub pre_market: Option<BarSession>,
    #[serde(rename = "afterMarket")]
    pub after_market: Option<BarSession>,
}

/// A row from bars() as the backtest consumes them.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct BarRow {
    pub timestamp: String,
    pub open: String,
    pub high: String,
    pub low: String,
    pub close: String,
    pub volume: u64,
}

// ── Preflight ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreflightResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instrument: Option<Instrument>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "orderValue")]
    pub order_value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "estimatedCost")]
    pub estimated_cost: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "estimatedQuantity")]
    pub estimated_quantity: Option<String>,
}

// ── Options ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptionInstrument {
    pub symbol: String,
    #[serde(rename = "type")]
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptionExpirationsRequest {
    pub instrument: OptionInstrument,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptionExpirationsResponse {
    pub expirations: Option<Vec<String>>,
    #[serde(rename = "expirationDates")]
    pub expiration_dates: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptionChainRequest {
    pub instrument: OptionInstrument,
    #[serde(rename = "expirationDate")]
    pub expiration_date: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptionDetails {
    #[serde(rename = "strikePrice")]
    pub strike_price: String,
    pub greeks: Option<Greeks>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptionQuote {
    pub instrument: OptionInstrument,
    pub bid: String,
    pub ask: String,
    pub last: String,
    #[serde(rename = "optionDetails")]
    pub option_details: Option<OptionDetails>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptionChainResponse {
    #[serde(rename = "baseSymbol")]
    pub base_symbol: String,
    pub calls: Vec<OptionQuote>,
    pub puts: Vec<OptionQuote>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Greeks {
    pub delta: Option<f64>,
    pub gamma: Option<f64>,
    pub theta: Option<f64>,
    pub vega: Option<f64>,
    pub rho: Option<f64>,
    #[serde(rename = "impliedVolatility")]
    pub implied_volatility: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GreeksEntry {
    pub instrument: Option<OptionInstrument>,
    #[serde(rename = "osiSymbol")]
    pub osi_symbol: Option<String>,
    pub symbol: Option<String>,
    pub delta: Option<f64>,
    pub gamma: Option<f64>,
    pub theta: Option<f64>,
    pub vega: Option<f64>,
    pub rho: Option<f64>,
    #[serde(rename = "impliedVolatility")]
    pub implied_volatility: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GreeksResponse {
    pub greeks: Option<Vec<GreeksEntry>>,
}

// ── Quotes ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuoteInstrument {
    pub symbol: String,
    #[serde(rename = "type")]
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuotesRequest {
    pub instruments: Vec<QuoteInstrument>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Quote {
    pub instrument: QuoteInstrument,
    pub outcome: String,
    pub last: Option<String>,
    pub bid: Option<String>,
    pub ask: Option<String>,
    #[serde(rename = "bidSize")]
    pub bid_size: Option<u64>,
    #[serde(rename = "askSize")]
    pub ask_size: Option<u64>,
    pub volume: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuotesResponse {
    pub quotes: Option<Vec<Quote>>,
}

// ── Event Contracts ──────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSummaryFilters {
    #[serde(rename = "eventSymbols")]
    pub event_symbols: Option<Vec<String>>,
    pub frequencies: Vec<String>,
    #[serde(rename = "resolutionTimeStart")]
    pub resolution_time_start: Option<String>,
    #[serde(rename = "resolutionTimeEnd")]
    pub resolution_time_end: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSummaryRequest {
    #[serde(rename = "sortingMode")]
    pub sorting_mode: String,
    pub category: Option<String>,
    pub subcategory: Option<String>,
    #[serde(rename = "nextToken")]
    pub next_token: Option<String>,
    #[serde(rename = "displayResolvedEvents")]
    pub display_resolved_events: Option<bool>,
    #[serde(rename = "createdWithinDays")]
    pub created_within_days: Option<u32>,
    pub filters: Option<EventSummaryFilters>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSummary {
    pub title: String,
    #[serde(rename = "eventSymbol")]
    pub event_symbol: String,
    pub volume: String,
    pub category: String,
    pub subcategories: Vec<String>,
    pub symbols: Vec<String>,
    #[serde(rename = "resolutionTime")]
    pub resolution_time: String,
    pub resolved: bool,
    pub halted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSummaryResponse {
    pub content: Option<Vec<EventSummary>>,
    #[serde(rename = "nextToken")]
    pub next_token: Option<String>,
}

// ── Event Contract Details ───────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResolutionSource {
    pub name: String,
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CftcContract {
    pub prohibitions: Vec<serde_json::Value>,
    #[serde(rename = "resolutionSources")]
    pub resolution_sources: Vec<ResolutionSource>,
    #[serde(rename = "contractTermsUrl")]
    pub contract_terms_url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContractTimeline {
    #[serde(rename = "openTime")]
    pub open_time: String,
    #[serde(rename = "closeTime")]
    pub close_time: String,
    #[serde(rename = "expectedExpirationTime")]
    pub expected_expiration_time: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventContract {
    pub symbol: String,
    #[serde(rename = "predictedOutcome")]
    pub predicted_outcome: String,
    pub bid: String,
    pub ask: String,
    pub last: String,
    #[serde(rename = "openInterest")]
    pub open_interest: String,
    pub probability: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventOutcome {
    #[serde(rename = "outcomeId")]
    pub outcome_id: String,
    pub title: String,
    pub rules: String,
    pub volume: String,
    pub state: String,
    pub timeline: ContractTimeline,
    #[serde(rename = "settledOutcome")]
    pub settled_outcome: String,
    pub trading: String,
    pub contracts: Vec<EventContract>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventDetailsResponse {
    #[serde(rename = "eventSymbol")]
    pub event_symbol: String,
    pub exchange: String,
    pub title: String,
    pub category: String,
    pub volume: String,
    pub subcategories: Vec<String>,
    #[serde(rename = "cftcContract")]
    pub cftc_contract: CftcContract,
    #[serde(rename = "outcomeCount")]
    pub outcome_count: u32,
    pub outcomes: Vec<EventOutcome>,
    pub resolved: bool,
    pub halted: bool,
}

// ── Event Contract Bars ──────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventContractBar {
    pub timestamp: String,
    pub open: String,
    pub high: String,
    pub low: String,
    pub close: String,
    pub value: String,
    pub volume: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventContractChart {
    pub symbol: String,
    #[serde(rename = "previousClosePrice")]
    pub previous_close_price: String,
    #[serde(rename = "currentPrice")]
    pub current_price: String,
    pub bars: Vec<EventContractBar>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventContractBarsResponse {
    pub period: String,
    pub charts: Vec<EventContractChart>,
}

// ── Orders ───────────────────────────────────────────────────────────────

/// Expiration block within an order body.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderExpiration {
    #[serde(rename = "timeInForce")]
    pub time_in_force: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "expirationTime")]
    pub expiration_time: Option<String>,
}

/// The order body sent to POST /userapigateway/trading/{account}/order.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderBody {
    pub instrument: Instrument,
    #[serde(rename = "orderSide")]
    pub order_side: String,
    #[serde(rename = "orderType")]
    pub order_type: String,
    pub expiration: OrderExpiration,
    pub quantity: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "limitPrice")]
    pub limit_price: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "stopPrice")]
    pub stop_price: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "openCloseIndicator")]
    pub open_close_indicator: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "orderId")]
    pub order_id: Option<String>,
}

/// Response from placing an order.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlaceOrderResponse {
    #[serde(rename = "orderId")]
    pub order_id: String,
}

/// Response from GET /userapigateway/trading/{account}/order/{order_id}.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderResponse {
    #[serde(rename = "orderId")]
    pub order_id: String,
    pub instrument: Option<Instrument>,
    pub side: Option<String>,
    pub quantity: Option<String>,
    #[serde(rename = "limitPrice")]
    pub limit_price: Option<String>,
    pub status: Option<String>,
}

// ── Error ────────────────────────────────────────────────────────────────

/// A Public API error body, deserialised from the JSON response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicErrorBody {
    pub message: Option<String>,
}

/// The public error type, stored in the client for reporting.
#[derive(Debug, Clone)]
pub struct PublicError {
    pub method: String,
    pub path: String,
    pub status: u32,
    pub body: String,
}
