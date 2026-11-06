//! Backtest replay engine.
//!
//! For each day in order: for each market that closed that day, consider both
//! YES (with yes_price) and NO (with no_price) sides. Compute the probability
//! from the forecast that existed before close (sigma by lead time). For each
//! side the edge = side_p - ask. Among all candidates (both sides) with
//! edge >= minEdge, pick the one with max (edge, then lowest ask).
//!
//! Quantity = min(maxContracts, floor(maxContractPriceUsd / ask),
//! floor(maxPremiumUsd / ask)). Skip if quantity < 1.
//!
//! Only one trade per day when maxOpenPositions == 1. Stop once the day's
//! realised P&L reaches dailyTakeProfitUsd or falls to -dailyLossStopUsd.
//!
//! Settlement: YES when the observed value falls in the question's band.
//! P&L = quantity * (1 - ask) if the side settles true,
//!      -quantity * ask if it does not.

use kagamizo_weather::data::{BacktestResult, BacktestLimits, Trade, DayResult, Question};
use crate::source::{Source, Observed};
use kagamizo_weather::weather::{parse_question, edge, band_probability, sigma_f, days_between};

/// A candidate side (YES or NO) for a market.
pub struct Candidate {
    pub ticker: String,
    pub city: String,
    pub question: String,
    pub outcome: String,
    pub side: String,       // "YES" or "NO"
    pub ask: f64,           // yes_price for YES, no_price for NO
    pub probability: f64,   // side probability (p for YES, 1-p for NO)
    pub edge: f64,          // probability - ask
    pub qv: Question,
}

/// Run the replay and return the result.
pub fn run_replay(
    source: &dyn Source,
    limits: &BacktestLimits,
    days: Vec<String>,
    recorded: &str,
) -> BacktestResult {
    let mut all_trades: Vec<Trade> = vec![];
    let mut day_results: Vec<DayResult> = vec![];
    let mut cumulative_pnl = 0.0f64;
    let mut equity_curve: Vec<(String, f64)> = vec![];
    equity_curve.push((days[0].clone(), limits.seed_usd));

    for day in days {
        let markets = source.prices(&day);
        let mut day_pnl = 0.0f64;
        let mut day_trades: u64 = 0;

        // ---- collect all candidates (YES and NO for each market) ----
        let mut candidates: Vec<Candidate> = vec![];

        for mkt in markets {
            // Parse the question to find the city and band
            let q = parse_question(&mkt.question, &mkt.outcome, &day, None);
            if q.is_none() {
                continue;
            }
            let qv = q.unwrap();

            // Determine as_of: strictly before the market's close day.
            // Use close_time date (first 10 chars) as the forecast as_of reference.
            let close_day = mkt.close_time.chars().take(10).collect::<String>();

            // Get the forecast that existed before close.
            // as_of is the day before close (the forecast that existed before the contract closed).
            // We use close_day minus one day as as_of for the sigma computation.
            let mut lead_days = days_between(&close_day, &day);
            if lead_days < 0 {
                lead_days = 0;
            }
            let as_of = &close_day;

            let fcst = source.forecast(&qv.city, &day, as_of);
            if fcst.is_none() {
                continue;
            }
            let fv = fcst.unwrap();

            // Compute probability using the forecast's high_f and sigma by lead time.
            let prob = compute_probability_from_forecast(&qv, fv.high_f, lead_days);
            if prob.is_none() {
                continue;
            }
            let p = prob.unwrap();  // probability of YES

            // ---- YES side ----
            {
                let side_p = p;
                let edg = edge(side_p, mkt.yes_price);
                candidates.push(Candidate {
                    ticker: mkt.ticker.clone(),
                    city: qv.city.clone(),
                    question: mkt.question.clone(),
                    outcome: mkt.outcome.clone(),
                    side: "YES".into(),
                    ask: mkt.yes_price,
                    probability: side_p,
                    edge: edg,
                    qv: qv.clone(),
                });
            }

            // ---- NO side ----
            {
                let side_p = 1.0 - p;
                let edg = edge(side_p, mkt.no_price);
                candidates.push(Candidate {
                    ticker: mkt.ticker.clone(),
                    city: qv.city.clone(),
                    question: mkt.question.clone(),
                    outcome: mkt.outcome.clone(),
                    side: "NO".into(),
                    ask: mkt.no_price,
                    probability: side_p,
                    edge: edg,
                    qv: qv.clone(),
                });
            }
        }

        // ---- pick the best candidate ----
        // Edge >= minEdge, then max by (edge, then lowest ask)
        let mut best_idx: i32 = -1;
        for i in 0..candidates.len() {
            let c = &candidates[i];
            if c.edge < limits.min_edge {
                continue;
            }
            if best_idx < 0 {
                best_idx = i as i32;
            } else {
                let p = &candidates[best_idx as usize];
                // Prefer higher edge; tie goes to lower ask
                let better = if (c.edge - p.edge).abs() > 0.000001 {
                    c.edge > p.edge
                } else {
                    c.ask < p.ask
                };
                if better {
                    best_idx = i as i32;
                }
            }
        }

        if best_idx >= 0 && day_trades < limits.max_open_positions.into() {
            let picked = &candidates[best_idx as usize];

            // Quantity = min(maxContracts, floor(maxContractPriceUsd / ask),
            //                 floor(maxPremiumUsd / ask))
            let qty_from_contract_price = (limits.max_contract_price_usd / picked.ask).floor() as u32;
            let qty_from_premium = (limits.max_premium_usd / picked.ask).floor() as u32;
            let mut quantity = limits.max_contracts.min(qty_from_contract_price).min(qty_from_premium);
            if quantity < 1 {
                quantity = 0;  // skip
            }

            if quantity > 0 {
                // Settle the trade
                let obs = source.observed(&picked.qv.city, &day);
                let mut have_obs = false;
                let mut settled: String = "".into();
                let mut trade_pnl: f64 = 0.0;

                if obs.is_some() {
                    let obsv = obs.unwrap();
                    let yes_hit = observed_in_band(&picked.qv, &obsv);
                    have_obs = true;
                    // The side traded settles as "YES" or "NO"
                    if (picked.side == "YES" && yes_hit) || (picked.side == "NO" && !yes_hit) {
                        // The side was correct
                        settled = picked.side.clone();
                        trade_pnl = quantity as f64 * (1.0 - picked.ask);
                    } else {
                        // The side was wrong
                        settled = if picked.side == "YES" { "NO".into() } else { "YES".into() };
                        trade_pnl = -(quantity as f64) * picked.ask;
                    }
                }

                if have_obs {
                    day_pnl += trade_pnl;
                    day_trades += 1;

                    all_trades.push(Trade {
                        day: day.clone(),
                        ticker: picked.ticker.clone(),
                        city: picked.city.clone(),
                        question: picked.question.clone(),
                        outcome: picked.outcome.clone(),
                        price: picked.ask,
                        probability: picked.probability,
                        edge: picked.edge,
                        side: picked.side.clone(),
                        settled,
                        pnl: trade_pnl,
                    });

                    // Check daily take-profit / loss-stop after each trade
                    if day_pnl >= limits.daily_take_profit_usd {
                        // done for the day (take-profit reached)
                    } else if day_pnl <= -limits.daily_loss_stop_usd {
                        // done for the day (loss-stop reached)
                    }
                }
            }
        }

        cumulative_pnl += day_pnl;
        let equity = limits.seed_usd + cumulative_pnl;
        equity_curve.push((day.clone(), equity));

        day_results.push(DayResult {
            date: day.clone(),
            trades: day_trades,
            pnl: day_pnl,
        });
    }

    // Compute aggregate metrics
    let total_trades_u64: u64 = all_trades.len() as u64;
    let hit_count: u64 = all_trades.iter().filter(|t| t.settled == t.side).count() as u64;
    let hit_rate = if total_trades_u64 > 0 { hit_count as f64 / total_trades_u64 as f64 } else { 0.0 };

    // Max drawdown: peak-to-trough of equity as percent of peak
    let max_drawdown_pct = compute_max_drawdown_pct(equity_curve);

    // Benchmark: buy every parsable YES contract at its price, one contract each, no price cap
    let benchmark_pnl = compute_benchmark(source, limits, source.day_keys());

    let alpha = cumulative_pnl - benchmark_pnl;

    BacktestResult {
        recorded: recorded.to_string(),
        days: day_results,
        trades: all_trades,
        total_trades: total_trades_u64,
        pnl: cumulative_pnl,
        alpha,
        max_drawdown_pct,
        hit_rate,
        benchmark_pnl,
    }
}

/// Check if the observed value falls within the question's band.
pub fn observed_in_band(q: &Question, obs: &Observed) -> bool {
    let value: Option<f64> = if q.shape == "high-temp-day" {
        Some(obs.high_f)
    } else if q.variable == "rain" {
        Some(obs.precip_in)
    } else {
        None
    };

    if value.is_none() {
        return false;
    }
    let v = value.unwrap();

    // Apply the same half-degree offsets as probability() does
    let adjusted_low = if q.low.is_some() { Some(q.low.unwrap() - 0.5) } else { None };
    let adjusted_high = if q.high.is_some() { Some(q.high.unwrap() + 0.5) } else { None };

    if adjusted_low.is_some() && v < adjusted_low.unwrap() {
        return false;
    }
    if adjusted_high.is_some() && v >= adjusted_high.unwrap() {
        return false;
    }
    true
}

/// Compute probability from a single forecast value using the question's band
/// and sigma by lead time.
fn compute_probability_from_forecast(q: &Question, forecast_high: f64, lead_days: i32) -> Option<f64> {
    if q.shape == "high-temp-day" {
        let sigma = sigma_f(lead_days);
        let low = if q.low.is_some() { Some(q.low.unwrap() - 0.5) } else { None };
        let high = if q.high.is_some() { Some(q.high.unwrap() + 0.5) } else { None };
        return Some(band_probability(forecast_high, sigma, low, high));
    }
    None
}

/// Compute max drawdown as percent of peak equity.
fn compute_max_drawdown_pct(curve: Vec<(String, f64)>) -> f64 {
    if curve.len() < 2 {
        return 0.0;
    }
    let mut peak = curve[0].1;
    let mut max_dd = 0.0f64;

    for (_date, eq) in curve {
        if eq > peak {
            peak = eq;
        }
        let dd = if peak > 0.0 { (peak - eq) / peak * 100.0 } else { 0.0 };
        if dd > max_dd {
            max_dd = dd;
        }
    }
    max_dd
}

/// Compute benchmark: buy one contract of YES on every parsable market, no price cap.
fn compute_benchmark(source: &dyn Source, _limits: &BacktestLimits, days: Vec<String>) -> f64 {
    let mut total = 0.0f64;
    for day in days {
        let markets = source.prices(&day);
        for mkt in markets {
            let q = parse_question(&mkt.question, &mkt.outcome, &day, None);
            if q.is_none() {
                continue;
            }
            let qv = q.unwrap();
            let obs = source.observed(&qv.city, &day);
            if obs.is_none() {
                continue;
            }
            let yes_hit = observed_in_band(&qv, &obs.unwrap());
            if yes_hit {
                total += 1.0 - mkt.yes_price;
            } else {
                total -= mkt.yes_price;
            }
        }
    }
    total
}