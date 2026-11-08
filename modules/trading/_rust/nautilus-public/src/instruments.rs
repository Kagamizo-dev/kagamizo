//! Public's instruments as Nautilus's: a coin is a `CurrencyPair` against
//! USD (Public sizes crypto orders in dollars, which Nautilus calls a quote
//! quantity), a stock or ETF an `Equity`, and a Kalshi contract listed on
//! Public a `BinaryOption` priced between 0 and 1.

use nautilus_core::UnixNanos;
use nautilus_model::{
    enums::AssetClass,
    identifiers::{InstrumentId, Symbol},
    instruments::{BinaryOption, CurrencyPair, Equity, InstrumentAny},
    types::{Currency, Price, Quantity},
};

use crate::VENUE;

/// One of Public's instruments, as its API names it: a symbol and a type.
#[derive(Debug, Clone, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
pub struct PublicInstrument {
    pub symbol: String,
    /// Public's instrument type: CRYPTO, EQUITY or EVENTCONTRACT.
    pub kind: String,
}

impl PublicInstrument {
    pub fn new(symbol: &str, kind: &str) -> Self {
        Self {
            symbol: symbol.to_uppercase(),
            kind: kind.to_uppercase(),
        }
    }

    /// The Nautilus identifier: BTC/USD.PUBLIC, SPY.PUBLIC, or the contract's
    /// symbol on PUBLIC.
    pub fn instrument_id(&self) -> InstrumentId {
        match self.kind.as_str() {
            "CRYPTO" => InstrumentId::from(format!("{}/USD.{VENUE}", self.symbol).as_str()),
            _ => InstrumentId::from(format!("{}.{VENUE}", self.symbol).as_str()),
        }
    }

    /// The Public instrument a Nautilus identifier names, given the kinds
    /// the node was configured with.
    pub fn of(id: &InstrumentId, known: &[PublicInstrument]) -> Option<PublicInstrument> {
        known.iter().find(|p| p.instrument_id() == *id).cloned()
    }

    /// The precisions quotes and fills use: (price, size).
    pub fn precisions(&self) -> (u8, u8) {
        match self.kind.as_str() {
            "CRYPTO" => (2, 8),
            "EVENTCONTRACT" => (2, 0),
            _ => (2, 0),
        }
    }

    /// The instrument's definition.
    pub fn definition(&self, ts: UnixNanos) -> anyhow::Result<InstrumentAny> {
        let usd = Currency::USD();
        let id = self.instrument_id();
        let raw = Symbol::from(self.symbol.as_str());
        Ok(match self.kind.as_str() {
            "CRYPTO" => InstrumentAny::CurrencyPair(
                CurrencyPair::builder()
                    .instrument_id(id)
                    .raw_symbol(raw)
                    .base_currency(Currency::from(self.symbol.as_str()))
                    .quote_currency(usd)
                    .price_precision(2)
                    .size_precision(8)
                    .price_increment(Price::from("0.01"))
                    .size_increment(Quantity::from("0.00000001"))
                    .min_price(Price::from("0.01"))
                    .ts_event(ts)
                    .ts_init(ts)
                    .build()?,
            ),
            "EQUITY" => InstrumentAny::Equity(
                Equity::builder()
                    .instrument_id(id)
                    .raw_symbol(raw)
                    .currency(usd)
                    .price_precision(2)
                    .price_increment(Price::from("0.01"))
                    .ts_event(ts)
                    .ts_init(ts)
                    .build()?,
            ),
            "EVENTCONTRACT" => InstrumentAny::BinaryOption(
                BinaryOption::builder()
                    .instrument_id(id)
                    .raw_symbol(raw)
                    .asset_class(AssetClass::Alternative)
                    .currency(usd)
                    .activation_ns(UnixNanos::default())
                    .expiration_ns(UnixNanos::from(u64::MAX / 2))
                    .price_precision(2)
                    .size_precision(0)
                    .price_increment(Price::from("0.01"))
                    .size_increment(Quantity::from("1"))
                    .ts_event(ts)
                    .ts_init(ts)
                    .build()?,
            ),
            other => anyhow::bail!("Public instrument type {other} is not mapped yet"),
        })
    }
}
