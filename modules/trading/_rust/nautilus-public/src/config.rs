//! The clients' configuration: which of Public's instruments the node trades
//! and how often it reads them. Credentials are never here: the Public
//! client reads them from the environment `secretspec run` sets.

use std::any::Any;

use nautilus_common::factories::ClientConfig;

use crate::instruments::PublicInstrument;

#[derive(Debug, Clone)]
pub struct PublicDataClientConfig {
    pub instruments: Vec<PublicInstrument>,
    /// How often the subscribed quotes are read from Public.
    pub poll_ms: u64,
}

impl ClientConfig for PublicDataClientConfig {
    fn as_any(&self) -> &dyn Any {
        self
    }
}

#[derive(Debug, Clone)]
pub struct PublicExecClientConfig {
    pub instruments: Vec<PublicInstrument>,
    /// Nautilus's name for the brokerage account (PUBLIC-<id>).
    pub account_id: String,
    /// How often a working order is read back, and for how long before it
    /// is left to reconciliation.
    pub poll_ms: u64,
    pub readback_secs: u64,
    /// zerohash's fee on an API crypto trade, a fraction of the notional,
    /// charged as the commission on crypto fills (Public's fee schedule).
    pub crypto_fee_rate: f64,
}

impl ClientConfig for PublicExecClientConfig {
    fn as_any(&self) -> &dyn Any {
        self
    }
}
