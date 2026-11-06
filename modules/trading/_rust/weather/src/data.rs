//! Data models: the typed structures from forecasts.json and the backtest result.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct DailyRecord {
    pub date: String,
    pub kind: String,
    pub high_f: Option<f64>,
    pub precip_in: Option<f64>,
    pub snow_in: Option<f64>,
}

#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct MonthClimatology {
    pub precip_in_per_day_mean: Option<f64>,
    pub precip_in_per_day_sd: Option<f64>,
    pub snow_in_per_day_mean: Option<f64>,
    pub snow_in_per_day_sd: Option<f64>,
}

#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct CityData {
    pub daily: Option<Vec<DailyRecord>>,
    pub climatology: Option<HashMap<String, MonthClimatology>>,
}

#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct WeatherData {
    pub as_of: String,
    pub source: Option<String>,
    pub note: Option<String>,
    pub cities: HashMap<String, CityData>,
}

#[derive(Serialize, Clone, PartialEq, Debug)]
pub struct BacktestResult {
    pub recorded: String,
    pub days: Vec<DayResult>,
    pub trades: Vec<Trade>,
    pub total_trades: u64,
    pub pnl: f64,
    pub alpha: f64,
    pub max_drawdown_pct: f64,
    pub hit_rate: f64,
    pub benchmark_pnl: f64,
}

/// Backtest limits matching the declaration keys exactly.
/// JSON uses camelCase: seedUsd, maxPremiumUsd, maxContractPriceUsd,
/// maxOpenPositions, dailyLossStopUsd, dailyTakeProfitUsd, minEdge, maxContracts.
#[derive(Deserialize, Clone, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub struct BacktestLimits {
    pub seed_usd: f64,
    pub max_premium_usd: f64,
    pub max_contract_price_usd: f64,
    pub max_open_positions: u32,
    pub daily_loss_stop_usd: f64,
    pub daily_take_profit_usd: f64,
    pub min_edge: f64,
    pub max_contracts: u32,
}

/// A single executed trade in the backtest replay.
#[derive(Serialize, Clone, PartialEq, Debug)]
pub struct Trade {
    pub day: String,
    pub ticker: String,
    pub city: String,
    pub question: String,
    pub outcome: String,
    /// The ask price for the traded side (YES or NO).
    pub price: f64,
    pub probability: f64,
    pub edge: f64,
    /// The side traded: "YES" or "NO".
    pub side: String,
    /// How the trade settled: "YES" or "NO".
    pub settled: String,
    /// Contract P&L in dollars (positive = win, negative = loss).
    pub pnl: f64,
}

/// A per-day breakdown in the backtest result.
#[derive(Serialize, Clone, PartialEq, Debug)]
pub struct DayResult {
    pub date: String,
    pub trades: u64,
    pub pnl: f64,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Question {
    pub shape: String,
    pub city: String,
    pub variable: String,
    pub low: Option<f64>,
    pub high: Option<f64>,
    pub year: i32,
    pub month: u32,
    pub start_day: u32,
    pub end_day: u32,
}

/// The last day of a given month (1-12) and year.
pub fn month_days(year: i32, month: u32) -> u32 {
    match month {
        2 => if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) { 29 } else { 28 },
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// Month names as lowercase -> 1-12.
pub fn month_number(name: &str) -> Option<u32> {
    let lower = name.to_lowercase();
    if lower == "january" || lower == "jan" { return Some(1); }
    if lower == "february" || lower == "feb" { return Some(2); }
    if lower == "march" || lower == "mar" { return Some(3); }
    if lower == "april" || lower == "apr" { return Some(4); }
    if lower == "may" { return Some(5); }
    if lower == "june" || lower == "jun" { return Some(6); }
    if lower == "july" || lower == "jul" { return Some(7); }
    if lower == "august" || lower == "aug" { return Some(8); }
    if lower == "september" || lower == "sep" || lower == "sept" { return Some(9); }
    if lower == "october" || lower == "oct" { return Some(10); }
    if lower == "november" || lower == "nov" { return Some(11); }
    if lower == "december" || lower == "dec" { return Some(12); }
    None
}