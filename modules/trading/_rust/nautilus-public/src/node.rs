//! The node: one Nautilus live node per run, with Public's data, and either
//! Nautilus's sandbox (paper) or our Public execution client (live) as the
//! venue. The mode is the one setting that separates paper from live.

use nautilus_common::enums::Environment;
use nautilus_execution::models::{
    fee::{FeeModelAny, MakerTakerFeeModel},
    fill::FillModelAny,
    latency::LatencyModelAny,
};
use nautilus_live::node::LiveNode;
use nautilus_model::{
    enums::{AccountType, OmsType},
    identifiers::{AccountId, TraderId, Venue},
    types::{Currency, Money},
};
use nautilus_sandbox::{SandboxExecutionClientConfig, SandboxExecutionClientFactory};
use rust_decimal::Decimal;

use crate::{
    VENUE,
    config::{PublicDataClientConfig, PublicExecClientConfig},
    factories::{PublicDataClientFactory, PublicExecutionClientFactory},
    instruments::PublicInstrument,
};

/// Paper or live: which execution client the node attaches.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Paper,
    Live,
}

/// What the paper venue models: the seed, the fee on each fill, how fills
/// slip and how long Public takes to answer. Declared, not guessed: the fee
/// from Public's fee schedule, slippage and latency from measured reads.
#[derive(Debug, Clone)]
pub struct PaperModels {
    pub seed_usd: f64,
    pub fee_rate: Decimal,
    pub fill: Option<FillModelAny>,
    pub latency: Option<LatencyModelAny>,
}

pub struct NodeSpec {
    pub trader_id: String,
    pub mode: Mode,
    pub instruments: Vec<PublicInstrument>,
    pub poll_ms: u64,
    pub paper: PaperModels,
    pub account_id: String,
}

pub fn build(spec: &NodeSpec) -> anyhow::Result<LiveNode> {
    let trader = TraderId::from(spec.trader_id.as_str());
    let data = PublicDataClientConfig {
        instruments: spec.instruments.clone(),
        poll_ms: spec.poll_ms,
    };
    let env = match spec.mode {
        Mode::Paper => Environment::Sandbox,
        Mode::Live => Environment::Live,
    };
    let builder = LiveNode::builder(trader, env)?
        .with_name(format!("{}-{:?}", spec.trader_id, spec.mode))
        .with_load_state(false)
        .with_save_state(false)
        .with_delay_post_stop_secs(0)
        .add_data_client(
            Some(VENUE.into()),
            Box::new(PublicDataClientFactory),
            Box::new(data),
        )?;
    let builder = match spec.mode {
        Mode::Paper => {
            let usd = Currency::USD();
            let sandbox = SandboxExecutionClientConfig::builder()
                .account_id(AccountId::from(spec.account_id.as_str()))
                .venue(Venue::new(VENUE))
                .starting_balances(vec![Money::new(spec.paper.seed_usd, usd)])
                .base_currency(usd)
                .oms_type(OmsType::Netting)
                .account_type(AccountType::Cash)
                .maybe_fill_model(spec.paper.fill.clone())
                .fee_model(FeeModelAny::MakerTaker(MakerTakerFeeModel::new(
                    spec.paper.fee_rate,
                    spec.paper.fee_rate,
                )))
                .maybe_latency_model(spec.paper.latency.clone())
                .bar_execution(false)
                .trade_execution(false)
                .build();
            builder.add_simulated_exec_client(
                Some(VENUE.into()),
                Box::new(SandboxExecutionClientFactory::new()),
                Box::new(sandbox),
            )?
        }
        Mode::Live => {
            let exec = PublicExecClientConfig {
                instruments: spec.instruments.clone(),
                account_id: spec.account_id.clone(),
                poll_ms: spec.poll_ms,
                readback_secs: 60,
                crypto_fee_rate: spec.paper.fee_rate.try_into().unwrap_or(0.0),
            };
            builder.add_exec_client(
                Some(VENUE.into()),
                Box::new(PublicExecutionClientFactory),
                Box::new(exec),
            )?
        }
    };
    builder.build()
}
