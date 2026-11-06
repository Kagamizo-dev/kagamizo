//! Public's API for `trade`: the adapter NautilusTrader does not have.
//!
//! The same endpoints the pinned publicdotcom-cli calls (its generated client
//! names them), through blocking TCP sockets, so it runs inside the
//! NautilusTrader Python:
//!
//!   token       a short-lived access token minted from PUBLIC_PERSONAL_SECRET
//!   account     PUBLIC_ACCOUNT_ID, else the one BROKERAGE account
//!   instrument  an equity's trading details
//!   bars        historic bars of one session, as rows for the backtest CSV
//!   preflight   what an order would cost and whether Public would take it;
//!               Public places nothing for a preflight
//!   option_expirations, option_chain, greeks
//!               an underlying's listed expirations, one expiration's chain
//!               (calls and puts, each with its OSI symbol, bid, ask, strike
//!               and, when Public has them, greeks), and greeks by OSI symbol
//!   event_contract_summary, event_contracts, event_contract_details,
//!   event_contract_bars, quotes
//!               the event contracts Public lists (Kalshi's, as
//!               KALSHI.<series>-<event>): one page of event summaries by
//!               category and subcategory, every page, one event's outcomes
//!               with their YES and NO contracts and prices, a contract's
//!               price bars, and quotes by instrument
//!   place       one single-leg order, as `trade place` sends it (a spend
//!               action: the controller's, after the risk check and a fresh
//!               preflight); order() reads it back by its id
//!
//! Only `place` places; nothing replaces or cancels.

pub mod types;
pub mod client;

pub use client::Public;
pub use types::*;

#[cfg(test)]
mod tests;
