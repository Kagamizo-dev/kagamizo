//! A NautilusTrader adapter for Public (public.com).
//!
//! NautilusTrader has no Public adapter; this crate is that gap and nothing
//! more. Nautilus owns orders, positions, P&L, risk, fees, fills, slippage
//! and latency; this crate maps Public's instruments onto Nautilus's, feeds
//! Public's quotes in as a data client, and places, reads and cancels orders
//! as an execution client, all through `kagamizo-public` (whose governed
//! reader and placer bounds still apply). Paper trading attaches Nautilus's
//! own sandbox execution client (nautilus-sandbox) to the same data;
//! live attaches ours. Nothing else changes between the two.

pub mod config;
pub mod data;
pub mod execution;
pub mod factories;
pub mod instruments;
pub mod node;
pub mod strategy;

/// The venue every Public instrument trades on, in Nautilus's identifiers.
pub const VENUE: &str = "PUBLIC";
