//! The agent-crypto strategy as a Nautilus strategy: the day's research
//! decision opens one spot position sized in dollars (a quote-quantity
//! limit at the ask: Public's crypto is dealer-quoted, so there is no
//! resting maker side to join), and the declared hold closes it (a
//! reduce-only limit at the bid). Nautilus owns the orders, the position,
//! its P&L and the fees; the strategy only decides when.

use nautilus_common::actor::DataActor;
use nautilus_core::UnixNanos;
use nautilus_model::{
    data::QuoteTick,
    enums::{OrderSide, TimeInForce},
    identifiers::InstrumentId,
    types::Quantity,
};
use nautilus_trading::{
    nautilus_strategy,
    strategy::{Strategy, StrategyConfig, StrategyCore},
};

#[derive(Debug, Clone)]
pub struct AgentCryptoConfig {
    pub base: StrategyConfig,
    pub instrument_id: InstrumentId,
    /// The research decision for the day: true opens, false leaves the day flat.
    pub buy: bool,
    /// Dollars one buy spends (already cut to the cap, fee included).
    pub amount_usd: f64,
    /// How long the position is held before the exit.
    pub hold_ns: u64,
}

pub struct AgentCrypto {
    core: StrategyCore,
    config: AgentCryptoConfig,
    entry_sent: bool,
    exit_sent: bool,
    opened_at: Option<UnixNanos>,
}

impl AgentCrypto {
    pub fn new(config: AgentCryptoConfig) -> Self {
        Self {
            core: StrategyCore::new(config.base.clone()),
            config,
            entry_sent: false,
            exit_sent: false,
            opened_at: None,
        }
    }

    /// The open position's quantity, if the strategy holds one.
    fn held(&self) -> Option<Quantity> {
        let cache = self.cache();
        let open = cache.positions_open(None, Some(&self.config.instrument_id), None, None, None);
        open.first().map(|p| p.quantity)
    }
}

nautilus_strategy!(AgentCrypto);

impl std::fmt::Debug for AgentCrypto {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AgentCrypto")
            .field("instrument_id", &self.config.instrument_id)
            .finish()
    }
}

impl DataActor for AgentCrypto {
    fn on_start(&mut self) -> anyhow::Result<()> {
        self.subscribe_quotes(self.config.instrument_id, None, None);
        Ok(())
    }

    fn on_quote(&mut self, quote: &QuoteTick) -> anyhow::Result<()> {
        let id = self.config.instrument_id;
        if self.config.buy && !self.entry_sent {
            self.entry_sent = true;
            let amount = Quantity::new(self.config.amount_usd, 8);
            let order = self.order().limit(
                id,
                OrderSide::Buy,
                amount,
                quote.ask_price,
                Some(TimeInForce::Day),
                None,
                None,
                None,
                Some(true),
                None,
                None,
                None,
                None,
                None,
                None,
                None,
            );
            return self.submit_order(order, None, None, None);
        }
        let Some(qty) = self.held() else {
            return Ok(());
        };
        let opened = *self.opened_at.get_or_insert(quote.ts_event);
        if !self.exit_sent && quote.ts_event.as_u64() >= opened.as_u64() + self.config.hold_ns {
            self.exit_sent = true;
            let order = self.order().limit(
                id,
                OrderSide::Sell,
                qty,
                quote.bid_price,
                Some(TimeInForce::Day),
                None,
                None,
                Some(true),
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
            );
            return self.submit_order(order, None, None, None);
        }
        Ok(())
    }
}
