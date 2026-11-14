// nautilus-probe: a pure-Rust proof that the weather and equity strategies can
// run on NautilusTrader's Rust crates alone, with no Python.
//
// Builds a BacktestEngine, adds a simulated venue, one equity instrument and a
// handful of bars, runs a trivial strategy that buys once, and prints the fills.
//
// Run with: cargo run -p nautilus-probe

#![deny(unsafe_code)]

use std::io::Write;

use nautilus_backtest::{
    config::{BacktestEngineConfig, SimulatedVenueConfig},
    engine::BacktestEngine,
};
use nautilus_execution::models::fee::{FeeModelAny, MakerTakerFeeModel};
use nautilus_model::{
    data::{Data, QuoteTick},
    enums::{AccountType, BookType, OmsType},
    identifiers::{InstrumentId, Symbol, Venue},
    instruments::{Equity, Instrument, InstrumentAny},
    types::{Currency, Money, Price, Quantity},
};
use nautilus_trading::examples::strategies::EmaCross;

const VENUE: &str = "SIM";
const SYMBOL: &str = "SPY";
const STARTING_BALANCE: &str = "100_000 USD";
const TRADE_SIZE: &str = "1000";

fn main() -> anyhow::Result<()> {
    eprintln!("=== nautilus-probe: pure-Rust backtest probe ===");

    // 1. Create the backtest engine
    let mut engine = BacktestEngine::new(BacktestEngineConfig::default())?;

    // 2. Add a simulated venue (MARGIN account, NETTING, L1_MBP book, with bar execution)
    engine.add_venue(
        SimulatedVenueConfig::builder()
            .venue(Venue::from(VENUE))
            .oms_type(OmsType::Netting)
            .account_type(AccountType::Margin)
            .book_type(BookType::L1_MBP)
            .starting_balances(vec![Money::from(STARTING_BALANCE)])
            .fee_model(FeeModelAny::MakerTaker(MakerTakerFeeModel::zero()).into())
            .build()?,
    )?;
    eprintln!("  venue SIM added");

    // 3. Create an Equity instrument (like SPY ETF)
    let instrument = InstrumentAny::Equity(
        Equity::builder()
            .instrument_id(InstrumentId::from(format!("{SYMBOL}.{VENUE}")))
            .raw_symbol(Symbol::from(SYMBOL))
            .currency(Currency::USD())
            .price_precision(2)
            .price_increment(Price::from("0.01"))
            .lot_size(Quantity::from("1"))
            .max_quantity(Quantity::from("100000"))
            .min_quantity(Quantity::from("1"))
            .max_price(Price::from("999999.99"))
            .min_price(Price::from("0.01"))
            .ts_event(0.into())
            .ts_init(0.into())
            .build()?,
    );
    let instrument_id = instrument.id();
    engine.add_instrument(&instrument)?;
    eprintln!("  instrument {} added", instrument_id);

    // 4. Generate quote tick data (the EmaCross strategy subscribes to quotes, not bars)
    let quotes = generate_quotes(instrument_id);
    eprintln!("  generated {} quote ticks", quotes.len());

    // Convert to Data::Quote wrapped values for the engine
    let data: Vec<Data> = quotes.into_iter().map(|q| Data::Quote(q)).collect();
    engine.add_data(data, None, true, true)?;
    eprintln!("  data added to engine");

    // 5. Add a trivial strategy that buys once (EMA cross)
    engine.add_strategy(EmaCross::new(
        instrument_id,
        Quantity::from(TRADE_SIZE),
        10,  // fast EMA period
        20,  // slow EMA period
    ))?;
    eprintln!("  EmaCross strategy added");

    // 6. Run the backtest
    engine.run(None, None, None, false)?;
    eprintln!("  backtest run complete");
    eprintln!("  iterations: {}", engine.iteration());

    // 7. Print fills from the result
    let result = engine.get_result();
    eprintln!("\n=== Backtest Result ===");
    eprintln!("  trader_id: {}", result.trader_id);
    eprintln!("  total_orders: {}", result.total_orders);
    eprintln!("  total_positions: {}", result.total_positions);
    eprintln!("  iterations: {}", result.iterations);
    eprintln!("  elapsed_time_secs: {:.4}", result.elapsed_time_secs);

    eprintln!("\n=== Summary ===");
    eprintln!("  {}", serde_json::to_string(&result.summary)?);

    eprintln!("\n=== PnLs ===");
    eprintln!("  {}", serde_json::to_string(&result.stats_pnls)?);

    eprintln!("\n=== General Stats ===");
    eprintln!("  {}", serde_json::to_string(&result.stats_general)?);

    // Print the result as JSON to stdout.
    let _ = print_json(&result);

    // As a check's builder: $out exists only when every order filled and
    // none was rejected, so the derivation is the proof the engine runs.
    if let Ok(out) = std::env::var("out") {
        let filled = result.total_orders > 0
            && result.summary.get("orders.closed").map(String::as_str)
                == Some(result.total_orders.to_string().as_str());
        anyhow::ensure!(filled, "not every order filled: {:?}", result.summary);
        std::fs::write(&out, serde_json::to_string_pretty(&result.stats_pnls)?)?;
    }

    engine.dispose();
    eprintln!("\n=== Probe completed successfully ===");
    Ok(())
}

/// Generate synthetic quote ticks for the EMA cross strategy.
fn generate_quotes(instrument_id: InstrumentId) -> Vec<QuoteTick> {
    let base_ts: u64 = 1_756_800_000_000_000_000; // 2025-09-01T00:00:00Z
    let interval: u64 = 1_000_000_000; // 1 second in nanos

    let mut quotes = Vec::new();
    let mut tick: u64 = 0;

    // Generate price series with crossovers
    let mut add = |mid: f64, ts: u64| {
        // At the instrument's price precision (2): the matching engine
        // drops quotes of any other precision, and then has no market.
        let bid = format!("{:.2}", mid * 1000.0);
        let ask = format!("{:.2}", mid * 1000.0 + 0.01);
        quotes.push(QuoteTick::new(
            instrument_id,
            Price::from(&bid),
            Price::from(&ask),
            Quantity::from("100000"),
            Quantity::from("100000"),
            ts.into(),
            ts.into(),
        ));
    };

    // Flat initialization - both EMAs converge around 0.65000
    for _ in 0..25 {
        add(0.65000, base_ts + tick * interval);
        tick += 1;
    }

    // Repeated up/down cycles to generate multiple crossovers
    let cycles = 6;
    for cycle in 0..cycles {
        let base = 0.65000 + (cycle as f64 * 0.00100);

        // Ramp up - fast EMA crosses above slow -> BUY signal
        for i in 0..40 {
            add(base + (i as f64 * 0.00050), base_ts + tick * interval);
            tick += 1;
        }

        // Ramp down - fast EMA crosses below slow -> SELL signal
        for i in 0..80 {
            let peak = base + 39.0 * 0.00050;
            add(peak - (i as f64 * 0.00050), base_ts + tick * interval);
            tick += 1;
        }
    }

    quotes
}

/// A fast, deterministic pseudo-random for synthetic data.
fn fast_rng(seed: i32) -> i32 {
    ((seed as i64 * 1103515245 + 12345) & 0x7fffffff) as i32
}

fn print_json<T: serde::Serialize>(val: &T) -> anyhow::Result<()> {
    let json = serde_json::to_string(val)?;
    let bytes = format!("{}\n", json).into_bytes();
    std::io::stdout().write(&bytes)?;
    Ok(())
}