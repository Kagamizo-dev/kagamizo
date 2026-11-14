//! A crypto round trip on a live Nautilus node against public-stub: the
//! strategy buys $24.85 of BTC at the ask, holds, and sells at the bid.
//! Nautilus owns the position and its P&L; the test only reads them.

use std::{
    io::Read,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
};

use nautilus_model::{
    identifiers::{InstrumentId, StrategyId},
    types::Currency,
};
use nautilus_public::{
    instruments::PublicInstrument,
    node::{Mode, NodeSpec, PaperModels, build},
    strategy::{AgentCrypto, AgentCryptoConfig},
};
use nautilus_trading::strategy::StrategyConfig;
use rust_decimal::Decimal;

pub struct Stub(Child);

impl Drop for Stub {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

/// Starts public-stub and points the Public client at it.
pub fn stub() -> Stub {
    // Beside the test binary's directory (target/<profile>/deps/..), where
    // cargo and the Nix build both put the workspace's binaries.
    let bin = std::env::var("PUBLIC_STUB_BIN")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let exe = std::env::current_exe().expect("the test binary");
            exe.parent()
                .and_then(Path::parent)
                .expect("target/<profile>")
                .join("public-stub")
        });
    let mut child = Command::new(&bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap_or_else(|e| panic!("{}: {e}", bin.display()));
    let mut out = child.stdout.take().expect("stdout");
    let (mut line, mut b) = (Vec::new(), [0u8; 1]);
    while out.read(&mut b).unwrap_or(0) == 1 && b[0] != b'\n' {
        line.push(b[0]);
    }
    let port = String::from_utf8_lossy(&line).trim().to_string();
    // SAFETY: set before the node starts any thread that reads them.
    unsafe {
        std::env::set_var("PUBLIC_API_BASE_URL", format!("http://127.0.0.1:{port}"));
        std::env::set_var("PUBLIC_PERSONAL_SECRET", "stub-secret");
        std::env::set_var("PUBLIC_ACCOUNT_ID", "5LA00001");
    }
    Stub(child)
}

/// What the run left: closed positions' realized P&L in dollars, and how
/// many positions are still open.
pub struct Outcome {
    pub closed: usize,
    pub open: usize,
    pub realized_usd: f64,
}

pub async fn round_trip(mode: Mode) -> Outcome {
    let _stub = stub();
    run(mode, true, 1_000_000_000).await
}

/// One node run against the stub already started: the strategy buys (or
/// not) and holds for `hold_ns`, and the node stops after five seconds.
pub async fn run(mode: Mode, buy: bool, hold_ns: u64) -> Outcome {
    let btc = PublicInstrument::new("BTC", "CRYPTO");
    let id: InstrumentId = btc.instrument_id();
    let spec = NodeSpec {
        trader_id: "KAGAMIZO-001".into(),
        mode,
        instruments: vec![btc],
        poll_ms: 100,
        paper: PaperModels {
            seed_usd: 100.0,
            fee_rate: Decimal::new(6, 3),
            fill: None,
            latency: None,
        },
        account_id: "PUBLIC-5LA00001".into(),
    };
    let mut node = build(&spec).expect("the node builds");
    node.add_strategy(AgentCrypto::new(AgentCryptoConfig {
        base: StrategyConfig {
            strategy_id: Some(StrategyId::from("AGENT_CRYPTO-001")),
            ..Default::default()
        },
        instrument_id: id,
        buy,
        amount_usd: 24.85,
        hold_ns,
    }))
    .expect("the strategy is added");
    let handle = node.handle();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(5));
        handle.stop();
    });
    node.run().await.expect("the node runs");
    let cache = node.kernel().cache();
    let cache = cache.borrow();
    let closed = cache.positions_closed_refs(None, Some(&id), None, None, None);
    let realized = closed
        .iter()
        .filter_map(|p| p.realized_pnl)
        .filter(|m| m.currency == Currency::USD())
        .map(|m| m.as_f64())
        .sum();
    Outcome {
        closed: closed.len(),
        open: cache
            .positions_open(None, Some(&id), None, None, None)
            .len(),
        realized_usd: realized,
    }
}
