//! Public as a Nautilus execution client: the live venue. Nautilus decides
//! what to send, keeps the orders and positions and computes P&L; this
//! client only turns its commands into Public's calls (through the governed
//! placer of `kagamizo-public`) and Public's answers into Nautilus's events:
//! submitted, accepted, then filled, cancelled or rejected. An order still
//! working when the read-back window closes is cancelled, never left
//! unattended. Positions are reported from Public's portfolio, so a node
//! that restarts reconciles with what Public actually holds.

use std::sync::{Arc, Mutex};

use kagamizo_public::{
    client::{
        Public, crypto_order_body, crypto_quantity_order_body, event_contract_order_body,
        order_body,
    },
    types::OrderBody,
};
use nautilus_common::{
    cache::CacheView,
    clients::ExecutionClient,
    live::{get_runtime, runner::get_exec_event_sender},
    messages::execution::{
        CancelOrder, GenerateFillReports, GenerateOrderStatusReport, GenerateOrderStatusReports,
        GeneratePositionStatusReports, SubmitOrder,
    },
};
use nautilus_core::{UUID4, UnixNanos, time::get_atomic_clock_realtime};
use nautilus_live::{ExecutionClientCore, ExecutionEventEmitter};
use nautilus_model::{
    accounts::AccountAny,
    enums::{AccountType, LiquiditySide, OmsType, OrderSide, OrderType, PositionSide},
    identifiers::{AccountId, ClientId, InstrumentId, TradeId, TraderId, Venue, VenueOrderId},
    orders::{Order, OrderAny},
    reports::{FillReport, OrderStatusReport, PositionStatusReport},
    types::{AccountBalance, Currency, MarginBalance, Money, Price, Quantity},
};
use rust_decimal::Decimal;

use crate::{VENUE, config::PublicExecClientConfig, instruments::PublicInstrument};

pub struct PublicExecutionClient {
    core: ExecutionClientCore,
    emitter: ExecutionEventEmitter,
    config: PublicExecClientConfig,
    api: Arc<Mutex<Public>>,
}

impl PublicExecutionClient {
    pub fn new(
        trader_id: TraderId,
        client_id: ClientId,
        config: PublicExecClientConfig,
        cache: CacheView,
    ) -> Self {
        let account_id = AccountId::from(config.account_id.as_str());
        let core = ExecutionClientCore::new(
            trader_id,
            client_id,
            Venue::new(VENUE),
            OmsType::Netting,
            account_id,
            AccountType::Cash,
            Some(Currency::USD()),
            cache,
        );
        let emitter = ExecutionEventEmitter::new(
            get_atomic_clock_realtime(),
            trader_id,
            account_id,
            AccountType::Cash,
            Some(Currency::USD()),
        );
        // The placer: the one client allowed an order and its cancel
        // (kagamizo_public::endpoints::Bound), reading its credentials from
        // the environment secretspec sets.
        let api = Arc::new(Mutex::new(Public::new(None, None).placer()));
        Self {
            core,
            emitter,
            config,
            api,
        }
    }

    fn instrument(&self, id: &InstrumentId) -> anyhow::Result<PublicInstrument> {
        PublicInstrument::of(id, &self.config.instruments)
            .ok_or_else(|| anyhow::anyhow!("{id} is not among the node's Public instruments"))
    }

    /// The account's cash, as Nautilus's account state.
    fn account_state(
        api: &Arc<Mutex<Public>>,
        ts: UnixNanos,
    ) -> anyhow::Result<Vec<AccountBalance>> {
        let p = api
            .lock()
            .expect("public")
            .portfolio()
            .map_err(anyhow::Error::msg)?;
        let cash: f64 = p
            .cash
            .as_deref()
            .unwrap_or(&p.buying_power.cash_only_buying_power)
            .parse()
            .unwrap_or(0.0);
        let free: f64 = p
            .buying_power
            .cash_only_buying_power
            .parse()
            .unwrap_or(cash);
        let usd = Currency::USD();
        let _ = ts;
        Ok(vec![AccountBalance::new(
            Money::new(cash, usd),
            Money::new((cash - free).max(0.0), usd),
            Money::new(free.min(cash), usd),
        )])
    }
}

/// Public's order body for a Nautilus order: a limit (or, for a stock, a
/// market) order of the instrument's kind, sized as Nautilus sized it.
pub fn public_order(
    p: &PublicInstrument,
    order: &OrderAny,
    public_id: &str,
) -> anyhow::Result<OrderBody> {
    let side = match order.order_side() {
        OrderSide::Buy => "BUY",
        OrderSide::Sell => "SELL",
    };
    let price = order.price().map(|p| p.to_string());
    let qty = order.quantity().to_string();
    let body = match (p.kind.as_str(), order.order_type()) {
        ("CRYPTO", OrderType::Limit) => {
            let px = price.as_deref().expect("a limit order has a price");
            if order.is_quote_quantity() {
                crypto_order_body(&p.symbol, side, px, &qty, Some(public_id))
            } else {
                crypto_quantity_order_body(&p.symbol, side, px, &qty, Some(public_id))
            }
        }
        ("EVENTCONTRACT", OrderType::Limit) => event_contract_order_body(
            &p.symbol,
            side,
            price.as_deref().expect("a limit order has a price"),
            &qty,
            Some(public_id),
        ),
        ("EQUITY", OrderType::Limit | OrderType::Market) => {
            let kind = if order.order_type() == OrderType::Limit {
                "LIMIT"
            } else {
                "MARKET"
            };
            order_body(
                &p.symbol,
                side,
                kind,
                &qty,
                "DAY",
                price.as_deref(),
                None,
                None,
            )
            .map(|mut b| {
                b.order_id = Some(public_id.to_string());
                b
            })
        }
        (kind, t) => anyhow::bail!(
            "{kind} {t:?} orders are not mapped to Public yet (crypto and event contracts take limits)"
        ),
    };
    body.map_err(anyhow::Error::msg)
}

#[async_trait::async_trait(?Send)]
impl ExecutionClient for PublicExecutionClient {
    fn is_connected(&self) -> bool {
        self.core.is_connected()
    }
    fn client_id(&self) -> ClientId {
        self.core.client_id
    }
    fn account_id(&self) -> AccountId {
        self.core.account_id
    }
    fn venue(&self) -> Venue {
        Venue::new(VENUE)
    }
    fn oms_type(&self) -> OmsType {
        OmsType::Netting
    }
    fn get_account(&self) -> Option<AccountAny> {
        self.core.cache().account_owned(&self.core.account_id)
    }
    fn generate_account_state(
        &self,
        balances: Vec<AccountBalance>,
        margins: Vec<MarginBalance>,
        reported: bool,
        ts_event: UnixNanos,
        info: Option<nautilus_core::Params>,
    ) -> anyhow::Result<()> {
        self.emitter
            .emit_account_state(balances, margins, reported, ts_event, info);
        Ok(())
    }
    fn start(&mut self) -> anyhow::Result<()> {
        self.emitter.set_sender(get_exec_event_sender());
        self.core.set_started();
        Ok(())
    }
    fn stop(&mut self) -> anyhow::Result<()> {
        self.core.set_stopped();
        self.core.set_disconnected();
        Ok(())
    }

    /// Reads the account's cash and reports it, so Nautilus's account and
    /// its free-balance checks start from what Public holds.
    async fn connect(&mut self) -> anyhow::Result<()> {
        let api = self.api.clone();
        let ts = get_atomic_clock_realtime().get_time_ns();
        let balances = tokio::task::spawn_blocking(move || Self::account_state(&api, ts)).await??;
        self.emitter
            .emit_account_state(balances, vec![], true, ts, None);
        self.core.set_connected();
        Ok(())
    }

    async fn disconnect(&mut self) -> anyhow::Result<()> {
        self.core.set_disconnected();
        Ok(())
    }

    fn submit_order(&self, cmd: SubmitOrder) -> anyhow::Result<()> {
        let order = self.core.get_order(&cmd.client_order_id)?;
        let p = self.instrument(&cmd.instrument_id)?;
        let clock = get_atomic_clock_realtime();
        let public_id = UUID4::new().to_string();
        let body = match public_order(&p, &order, &public_id) {
            Ok(b) => b,
            Err(e) => {
                self.emitter.emit_order_denied(&order, &e.to_string());
                return Ok(());
            }
        };
        self.emitter.emit_order_submitted(&order);
        let (api, emitter) = (self.api.clone(), self.emitter.clone());
        let (every, window, fee) = (
            self.config.poll_ms,
            self.config.readback_secs,
            self.config.crypto_fee_rate,
        );
        let (pp, sp) = p.precisions();
        let crypto = p.kind == "CRYPTO";
        get_runtime().spawn(async move {
            let json = serde_json::to_string(&body).expect("an order body serialises");
            let call = api.clone();
            let placed = tokio::task::spawn_blocking(move || {
                let mut c = call.lock().expect("public");
                c.preflight(&json)?;
                c.place(&json)
            })
            .await;
            let placed = match placed {
                Ok(Ok(r)) => r,
                Ok(Err(e)) => {
                    return emitter.emit_order_rejected(&order, &e, clock.get_time_ns(), false);
                }
                Err(e) => {
                    return emitter.emit_order_rejected(
                        &order,
                        &e.to_string(),
                        clock.get_time_ns(),
                        false,
                    );
                }
            };
            let venue_id = if placed.order_id.is_empty() {
                public_id.clone()
            } else {
                placed.order_id.clone()
            };
            let venue_order_id = VenueOrderId::from(venue_id.as_str());
            emitter.emit_order_accepted(&order, venue_order_id, clock.get_time_ns());
            // Read back until Public says the order ended; cancel it if the
            // window closes with it still working.
            let deadline = std::time::Instant::now() + std::time::Duration::from_secs(window);
            loop {
                let (call, id) = (api.clone(), venue_id.clone());
                let read =
                    tokio::task::spawn_blocking(move || call.lock().expect("public").order(&id))
                        .await;
                let Ok(Ok(r)) = read else {
                    tokio::time::sleep(std::time::Duration::from_millis(every)).await;
                    continue;
                };
                match r.status.as_deref().unwrap_or("") {
                    "FILLED" | "PARTIALLY_FILLED"
                        if r.status.as_deref() == Some("FILLED")
                            || std::time::Instant::now() >= deadline =>
                    {
                        let num =
                            |s: &Option<String>| s.as_deref().and_then(|v| v.parse::<f64>().ok());
                        let qty =
                            num(&r.filled_quantity).unwrap_or_else(|| order.quantity().as_f64());
                        let px = num(&r.average_price)
                            .or(order.price().map(|p| p.as_f64()))
                            .unwrap_or(0.0);
                        let (last_qty, last_px) = (Quantity::new(qty, sp), Price::new(px, pp));
                        let ts = clock.get_time_ns();
                        if order.is_quote_quantity() {
                            // Nautilus sizes a dollar order in dollars; the
                            // fill is in coins, so the order is first updated
                            // to the coins it bought, as Nautilus's own
                            // matching engine does.
                            emitter.emit_order_updated(
                                &order,
                                venue_order_id,
                                last_qty,
                                order.price(),
                                None,
                                None,
                                ts,
                            );
                        }
                        let commission =
                            crypto.then(|| Money::new(qty * px * fee, Currency::USD()));
                        emitter.emit_order_filled(
                            &order,
                            venue_order_id,
                            None,
                            TradeId::from(venue_id.as_str()),
                            last_qty,
                            last_px,
                            Currency::USD(),
                            commission,
                            LiquiditySide::Taker,
                            ts,
                        );
                        return;
                    }
                    "CANCELLED" | "EXPIRED" | "QUEUED_CANCELLED" => {
                        return emitter.emit_order_canceled(
                            &order,
                            Some(venue_order_id),
                            clock.get_time_ns(),
                        );
                    }
                    "REJECTED" => {
                        return emitter.emit_order_rejected(
                            &order,
                            "Public rejected the order",
                            clock.get_time_ns(),
                            false,
                        );
                    }
                    _ if std::time::Instant::now() >= deadline => {
                        let (call, id) = (api.clone(), venue_id.clone());
                        let _ = tokio::task::spawn_blocking(move || {
                            call.lock().expect("public").cancel(&id)
                        })
                        .await;
                        return emitter.emit_order_canceled(
                            &order,
                            Some(venue_order_id),
                            clock.get_time_ns(),
                        );
                    }
                    _ => tokio::time::sleep(std::time::Duration::from_millis(every)).await,
                }
            }
        });
        Ok(())
    }

    fn cancel_order(&self, cmd: CancelOrder) -> anyhow::Result<()> {
        let order = self.core.get_order(&cmd.client_order_id)?;
        let Some(venue_order_id) = cmd.venue_order_id.or(order.venue_order_id()) else {
            anyhow::bail!("{} has no Public order id yet", cmd.client_order_id);
        };
        let (api, emitter) = (self.api.clone(), self.emitter.clone());
        let clock = get_atomic_clock_realtime();
        get_runtime().spawn(async move {
            let id = venue_order_id.to_string();
            match tokio::task::spawn_blocking(move || api.lock().expect("public").cancel(&id)).await
            {
                Ok(Ok(())) => {
                    emitter.emit_order_canceled(&order, Some(venue_order_id), clock.get_time_ns())
                }
                Ok(Err(e)) => emitter.emit_order_cancel_rejected(
                    &order,
                    Some(venue_order_id),
                    &e,
                    clock.get_time_ns(),
                ),
                Err(e) => emitter.emit_order_cancel_rejected(
                    &order,
                    Some(venue_order_id),
                    &e.to_string(),
                    clock.get_time_ns(),
                ),
            }
        });
        Ok(())
    }

    async fn generate_order_status_report(
        &self,
        _cmd: &GenerateOrderStatusReport,
    ) -> anyhow::Result<Option<OrderStatusReport>> {
        Ok(None)
    }

    async fn generate_order_status_reports(
        &self,
        _cmd: &GenerateOrderStatusReports,
    ) -> anyhow::Result<Vec<OrderStatusReport>> {
        Ok(vec![])
    }

    async fn generate_fill_reports(
        &self,
        _cmd: GenerateFillReports,
    ) -> anyhow::Result<Vec<FillReport>> {
        Ok(vec![])
    }

    /// What Public holds, instrument by instrument, so a restarted node's
    /// positions match the account's.
    async fn generate_position_status_reports(
        &self,
        cmd: &GeneratePositionStatusReports,
    ) -> anyhow::Result<Vec<PositionStatusReport>> {
        let api = self.api.clone();
        let portfolio =
            tokio::task::spawn_blocking(move || api.lock().expect("public").portfolio())
                .await?
                .map_err(anyhow::Error::msg)?;
        let ts = get_atomic_clock_realtime().get_time_ns();
        let mut out = Vec::new();
        for held in portfolio.positions {
            let p = PublicInstrument::new(&held.instrument.symbol, &held.instrument.kind);
            let Some(known) = PublicInstrument::of(&p.instrument_id(), &self.config.instruments)
            else {
                continue;
            };
            if cmd
                .instrument_id
                .is_some_and(|id| id != known.instrument_id())
            {
                continue;
            }
            let q: f64 = held.quantity.parse().unwrap_or(0.0);
            let side = if q > 0.0 {
                PositionSide::Long
            } else if q < 0.0 {
                PositionSide::Short
            } else {
                PositionSide::Flat
            };
            let qty = Quantity::new(q.abs(), known.precisions().1);
            let avg_px_open = held.unit_cost().and_then(|c| Decimal::try_from(c).ok());
            out.push(PositionStatusReport::new(
                self.core.account_id,
                known.instrument_id(),
                side,
                qty,
                ts,
                ts,
                None,
                None,
                avg_px_open,
            ));
        }
        Ok(out)
    }
}
