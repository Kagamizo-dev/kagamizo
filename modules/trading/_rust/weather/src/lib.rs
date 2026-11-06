//! The weather rules (ported from _weather.py): the probability that a
//! question about a city's weather resolves YES, given a forecast and the
//! month's climatology, and the edge against a contract's price. Shared by
//! the backtest and the trade binary.
pub mod data;
pub mod weather;

#[cfg(test)]
mod rules_tests;
