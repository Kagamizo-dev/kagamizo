use kagamizo_weather::data;
mod source;
mod replay;

use std::fs;
use data::BacktestLimits;
use source::FixtureSource;
use source::Source;
use replay::run_replay;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        eprintln!("usage: weather-backtest --days <file> --limits <json> --recorded <YYYY-MM-DD>");
        std::process::exit(2);
    }
    let mut days_path: Option<String> = None;
    let mut limits_json: Option<String> = None;
    let mut recorded: Option<String> = None;
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--days" && i + 1 < args.len() {
            days_path = Some(args[i + 1].clone());
            i += 2;
        } else if args[i] == "--limits" && i + 1 < args.len() {
            limits_json = Some(args[i + 1].clone());
            i += 2;
        } else if args[i] == "--recorded" && i + 1 < args.len() {
            recorded = Some(args[i + 1].clone());
            i += 2;
        } else {
            eprintln!("weather-backtest: unexpected argument: {}", args[i]);
            std::process::exit(2);
        }
    }
    if days_path.is_none() {
        eprintln!("weather-backtest: --days <file> is required");
        std::process::exit(2);
    }
    if limits_json.is_none() {
        eprintln!("weather-backtest: --limits <json> is required");
        std::process::exit(2);
    }
    if recorded.is_none() {
        eprintln!("weather-backtest: --recorded <YYYY-MM-DD> is required");
        std::process::exit(2);
    }

    let dp = days_path.unwrap();
    let text = fs::read_to_string(&dp).unwrap_or_else(|e| {
        eprintln!("weather-backtest: reading {}: {}", dp, e);
        std::process::exit(1);
    });
    let source = FixtureSource::from_json(&text).unwrap_or_else(|| {
        eprintln!("weather-backtest: parsing days file");
        std::process::exit(1);
    });

    let limits_j = limits_json.unwrap();
    let limits: BacktestLimits = serde_json::from_str(&limits_j).unwrap_or_else(|e| {
        eprintln!("weather-backtest: parsing limits JSON: {}", e);
        std::process::exit(1);
    });

    let rec = recorded.unwrap();

    // Collect day keys from the fixture, sorted.
    let mut day_keys = source.day_keys();
    day_keys.sort();

    let result = run_replay(&source as &dyn Source, &limits, day_keys, &rec);
    let output = serde_json::to_string_pretty(&result).unwrap_or_else(|e| {
        eprintln!("weather-backtest: serialising result: {}", e);
        std::process::exit(1);
    });
    println!("{}", output);
}

#[cfg(test)]
mod tests {
    use super::*;
    use kagamizo_weather::data::BacktestLimits;
    use kagamizo_weather::weather::parse_question;
    use crate::source::{FixtureSource, Source};
    use crate::replay::{observed_in_band, run_replay};

    /// Load the backtest-days fixture.
    fn load_days() -> FixtureSource {
        let mut candidates: Vec<String> = std::env::var("DAYS_PATH").into_iter().collect();
        candidates.extend([
            "../../_json/backtest-days.json".into(),
            "../_json/backtest-days.json".into(),
            "_json/backtest-days.json".into(),
            "modules/trading/_json/backtest-days.json".into(),
        ]);
        for c in candidates {
            if std::path::Path::new(&c).exists() {
                let s = FixtureSource::from_path(&c);
                if s.is_some() {
                    return s.unwrap();
                }
            }
        }
        // Last resort
        let text = std::fs::read_to_string("../../_json/backtest-days.json").ok().or_else(||
            std::fs::read_to_string("../_json/backtest-days.json").ok()
        ).or_else(||
            std::fs::read_to_string("modules/trading/_json/backtest-days.json").ok()
        );
        if text.is_some() {
            let t = text.unwrap();
            let s = FixtureSource::from_json(&t);
            if s.is_some() {
                return s.unwrap();
            }
        }
        panic!("cannot load fixture")
    }

    fn default_limits() -> BacktestLimits {
        BacktestLimits {
            seed_usd: 1000.0,
            max_premium_usd: 25.0,
            max_contract_price_usd: 1.0,
            max_open_positions: 1,
            daily_loss_stop_usd: 1000.0,
            daily_take_profit_usd: 1000.0,
            min_edge: 0.0,  // allow all non-negative edges
            max_contracts: 10,
        }
    }

    // -----------------------------------------------------------------------
    // Settlement tests
    // -----------------------------------------------------------------------

    /// Settlement: NY on Nov 5, observed high=72, "72° or above" → YES (72 >= 71.5)
    #[test]
    fn test_settlement_yes_on_band_edge() {
        let src = load_days();
        let obs = src.observed("New York", "2026-11-05").unwrap();
        let q = parse_question("Highest temperature in New York on Nov 5?", "72° or above", "2026-11-04", None).unwrap();
        assert!(observed_in_band(&q, &obs));
    }

    /// Settlement: NY on Nov 5, "65° or below" → NO (observed 72 > 65.5)
    #[test]
    fn test_settlement_no_outside_band() {
        let src = load_days();
        let obs = src.observed("New York", "2026-11-05").unwrap();
        let q = parse_question("Highest temperature in New York on Nov 5?", "65° or below", "2026-11-04", None).unwrap();
        assert!(!observed_in_band(&q, &obs));
    }

    /// Settlement: "66° to 71°" → NO (observed 72 > 71.5)
    #[test]
    fn test_settlement_mid_band_no() {
        let src = load_days();
        let obs = src.observed("New York", "2026-11-05").unwrap();
        let q = parse_question("Highest temperature in New York on Nov 5?", "66° to 71°", "2026-11-04", None).unwrap();
        assert!(!observed_in_band(&q, &obs));
    }

    // -----------------------------------------------------------------------
    // Loss stop: day stops after P&L reaches -dailyLossStopUsd
    // -----------------------------------------------------------------------

    #[test]
    fn test_loss_stop_halt_day() {
        let limits = BacktestLimits {
            seed_usd: 1000.0,
            max_premium_usd: 10.0,
            max_contract_price_usd: 1.0,
            max_open_positions: 1,
            daily_loss_stop_usd: 0.10,  // stop after -$0.10
            daily_take_profit_usd: 1000.0,
            min_edge: -1.0,  // allow all edges
            max_contracts: 10,
        };
        // Day 2026-11-07: NYHIGHT1107A (yes_price=0.60, "70° or above").
        // NY on Nov 7, forecast high=70, as_of=2026-11-06, lead=1.
        // sigma = sigma_f(1) = 3.25
        // P(high >= 69.5 | mu=70, sigma=3.25)
        //   z = (69.5-70)/3.25 = -0.154, P = 1-CDF(-0.154) ≈ 0.561
        // YES edge = 0.561-0.60 = -0.039
        // NO edge = (1-0.561)-0.95 = -0.511
        // YES is picked (higher edge: -0.039 > -0.511)
        // qty = min(10, floor(1/0.60)=1, floor(10/0.60)=16) = 1
        // observed high=68, 68 < 69.5 -> NO -> YES was wrong
        // P&L = -1 * 0.60 = -0.60 < -0.10 -> stop triggered
        let src = load_days();
        let result = run_replay(&src as &dyn Source, &limits, vec!["2026-11-07".into()], "2026-11-08");
        // Should have 1 trade
        assert_eq!(result.total_trades, 1);
        // The day P&L should be -0.60 (one losing trade)
        assert!((result.days[0].pnl - (-0.60)).abs() < 0.01);
    }

    // -----------------------------------------------------------------------
    // Quantity < 1: skipped when the ask makes quantity < 1 under maxContractPriceUsd
    // -----------------------------------------------------------------------

    #[test]
    fn test_quantity_less_than_one_skips() {
        let limits = BacktestLimits {
            seed_usd: 1000.0,
            max_premium_usd: 10.0,
            max_contract_price_usd: 0.04,  // below every ask in the fixture
            max_open_positions: 1,
            daily_loss_stop_usd: 1000.0,
            daily_take_profit_usd: 1000.0,
            min_edge: -1.0,  // allow all edges
            max_contracts: 10,
        };
        // On Nov 5 the cheapest ask is yes_price=0.05 (NYHIGHT1105C).
        // floor(0.04/0.05) = 0 -> quantity < 1, skipped for every candidate.
        let src = load_days();
        let result = run_replay(&src as &dyn Source, &limits, vec!["2026-11-05".into()], "2026-11-08");
        // No trade should happen because quantity < 1 for all candidates
        assert_eq!(result.total_trades, 0);
    }

    // -----------------------------------------------------------------------
    // Full fixture result
    // -----------------------------------------------------------------------

    #[test]
    fn test_full_fixture_result() {
        let limits = default_limits();
        let src = load_days();
        let result = run_replay(&src as &dyn Source, &limits, vec!["2026-11-05".into(), "2026-11-06".into(), "2026-11-07".into()], "2026-11-08");
        // At least some trades happened
        assert!(result.total_trades > 0);
        // P&L should be non-zero (something traded)
        assert!(result.pnl != 0.0);
        // Hit rate should be between 0 and 1
        assert!(result.hit_rate >= 0.0 && result.hit_rate <= 1.0);
        // alpha = pnl - benchmark_pnl
        assert!((result.alpha - (result.pnl - result.benchmark_pnl)).abs() < 0.001);
        // Day results
        assert_eq!(result.days.len(), 3);
    }

    // -----------------------------------------------------------------------
    // Both sides trade: YES wins on Nov 5 with positive edge
    // -----------------------------------------------------------------------

    #[test]
    fn test_nov5_trades_yes_wins() {
        let limits = default_limits();
        let src = load_days();
        let result = run_replay(&src as &dyn Source, &limits, vec!["2026-11-05".into()], "2026-11-08");
        // Should pick one trade (maxOpenPositions=1)
        assert_eq!(result.total_trades, 1);
        // The picked trade should have edge >= 0
        assert!(result.trades[0].edge >= 0.0);
        // Should be side YES (higher edge)
        assert_eq!(result.trades[0].side, "YES");
        // P&L: qty=5, yes_price=0.20, observed=72, YES settles true
        // P&L = 5 * (1-0.20) = 4.0
        assert!((result.days[0].pnl - 4.0).abs() < 0.01);
    }
}