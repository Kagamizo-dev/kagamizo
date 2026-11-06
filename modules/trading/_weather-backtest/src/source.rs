//! Source trait and fixture implementation for weather backtest.
//!
//! The `Source` trait abstracts over forecast, observed, and market data sources.
//! `FixtureSource` reads a JSON fixture file in the format documented below.
//!
//! ## Fixture JSON format (backtest-days.json)
//!
//! ```json
//! {
//!   "days": [
//!     {
//!       "date": "2026-11-05",
//!       "markets": [
//!         {
//!           "ticker": "NYHIGHT1105A",
//!           "question": "Highest temperature in New York on Nov 5?",
//!           "outcome": "72° or above",
//!           "close_time": "2026-11-04T18:00:00Z",
//!           "yes_price": 0.65,
//!           "no_price": 0.35,
//!           "settled": null
//!         }
//!       ],
//!       "forecasts": {
//!         "New York": { "high_f": 72, "kind": "forecast" }
//!       },
//!       "observed": {
//!         "New York": { "high_f": 72, "low_f": 55, "precip_in": 0.0 }
//!       }
//!     }
//!   ]
//! }
//! ```
//!
//! `forecasts` and `observed` are keyed by canonical city name. A `forecast`
//! gives the prediction made before close; `observed` gives what actually happened.
//! `settled` is `"YES"`, `"NO"`, or `null` (if not yet known/recorded).

use std::collections::HashMap;
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

/// A forecast for a city on a particular day, as it existed before market close.
#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct Forecast {
    pub high_f: f64,
    pub kind: Option<String>, // "observed" or "forecast"
}

/// The official observed values a market settles on.
#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct Observed {
    pub high_f: f64,
    pub low_f: f64,
    pub precip_in: f64,
}

/// A traded market on Kalshi.
#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct Market {
    pub ticker: String,
    pub question: String,
    pub outcome: String,      // e.g. "72° or above"
    pub close_time: String,   // ISO 8601 timestamp
    pub yes_price: f64,       // price of a YES contract in dollars
    pub no_price: f64,        // price of a NO contract in dollars
    pub settled: Option<String>, // "YES", "NO", or null
}

/// A single day in the fixture: markets that closed, the forecasts used,
/// and the observed values.
#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct FixtureDay {
    pub date: String,
    pub markets: Vec<Market>,
    pub forecasts: HashMap<String, Forecast>,
    pub observed: HashMap<String, Observed>,
}

/// Top-level fixture structure.
#[derive(Deserialize, Serialize, Clone, PartialEq, Debug)]
pub struct FixtureData {
    pub note: Option<String>,
    pub days: Vec<FixtureDay>,
}

// ---------------------------------------------------------------------------
// Source trait
// ---------------------------------------------------------------------------

/// Abstract source of forecast, observed, and market data.
pub trait Source {
    /// Return the forecast for `city` on `day` as it existed at `as_of`.
    fn forecast(&self, city: &str, day: &str, as_of: &str) -> Option<Forecast>;
    /// Return the observed values for `city` on `day`.
    fn observed(&self, city: &str, day: &str) -> Option<Observed>;
    /// Return all markets that closed on `day`.
    fn prices(&self, day: &str) -> Vec<Market>;
    /// Return all day strings the source knows about, unsorted.
    fn day_keys(&self) -> Vec<String>;
}

// ---------------------------------------------------------------------------
// FixtureSource: reads from a JSON fixture file
// ---------------------------------------------------------------------------

/// A source that reads from a local JSON fixture file.
pub struct FixtureSource {
    pub data: FixtureData, // public so main.rs can iterate days
}

impl FixtureSource {
    /// Load a fixture from a JSON string.
    pub fn from_json(json_text: &str) -> Option<FixtureSource> {
        let d = serde_json::from_str::<FixtureData>(json_text).ok();
        if d.is_some() {
            Some(FixtureSource { data: d.unwrap() })
        } else {
            None
        }
    }

    /// Load a fixture from a file path.
    pub fn from_path(path: &str) -> Option<FixtureSource> {
        let text = std::fs::read_to_string(path).ok();
        if text.is_some() {
            let t: String = text.unwrap();
            FixtureSource::from_json(&t)
        } else {
            None
        }
    }

    /// Convenience: build from the test fixture.
    pub fn from_package_fixture() -> Option<FixtureSource> {
        let candidates: Vec<String> = vec![
            "../../_json/backtest-days.json".into(),
            "../_json/backtest-days.json".into(),
            "_json/backtest-days.json".into(),
            "modules/trading/_json/backtest-days.json".into(),
        ];
        for c in candidates {
            if std::path::Path::new(&c).exists() {
                return FixtureSource::from_path(&c);
            }
        }
        None
    }
}

impl Source for FixtureSource {
    fn forecast(&self, city: &str, day: &str, _as_of: &str) -> Option<Forecast> {
        for d in &self.data.days {
            if d.date == day {
                return d.forecasts.get(city).map(|f| f.clone());
            }
        }
        None
    }

    fn observed(&self, city: &str, day: &str) -> Option<Observed> {
        for d in &self.data.days {
            if d.date == day {
                return d.observed.get(city).map(|o| o.clone());
            }
        }
        None
    }

    fn prices(&self, day: &str) -> Vec<Market> {
        for d in &self.data.days {
            if d.date == day {
                return d.markets.clone();
            }
        }
        vec![]
    }

    fn day_keys(&self) -> Vec<String> {
        let mut keys: Vec<String> = vec![];
        for d in &self.data.days {
            keys.push(d.date.clone());
        }
        keys
    }
}