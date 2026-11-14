//! Public's quotes as a Nautilus data client. Public has no streaming feed
//! for this API, so subscribed instruments are read on a timer and each
//! read is sent to the data engine as a `QuoteTick`.

use std::{
    collections::HashSet,
    sync::{Arc, Mutex},
};

use kagamizo_public::client::Public;
use nautilus_common::{
    clients::DataClient,
    live::{get_runtime, runner::get_data_event_sender},
    messages::{
        DataEvent,
        data::{SubscribeQuotes, UnsubscribeQuotes},
    },
};
use nautilus_core::time::get_atomic_clock_realtime;
use nautilus_model::{
    data::{Data, QuoteTick},
    identifiers::{ClientId, InstrumentId, Venue},
    types::{Price, Quantity},
};

use crate::{VENUE, config::PublicDataClientConfig, instruments::PublicInstrument};

pub struct PublicDataClient {
    client_id: ClientId,
    config: PublicDataClientConfig,
    subscribed: Arc<Mutex<HashSet<InstrumentId>>>,
    connected: bool,
    poller: Option<tokio::task::JoinHandle<()>>,
}

impl std::fmt::Debug for PublicDataClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PublicDataClient")
            .field("client_id", &self.client_id)
            .finish()
    }
}

impl PublicDataClient {
    pub fn new(client_id: ClientId, config: PublicDataClientConfig) -> Self {
        Self {
            client_id,
            config,
            subscribed: Arc::default(),
            connected: false,
            poller: None,
        }
    }
}

/// One quote read from Public, as a tick, when Public quotes both sides.
pub fn quote_tick(p: &PublicInstrument, q: &kagamizo_public::types::Quote) -> Option<QuoteTick> {
    let (pp, sp) = p.precisions();
    let num = |s: &Option<String>| {
        s.as_deref()
            .and_then(|v| v.parse::<f64>().ok())
            .filter(|v| *v > 0.0)
    };
    let (bid, ask) = (num(&q.bid)?, num(&q.ask)?);
    let size = |s: Option<u64>| Quantity::new(s.unwrap_or(1).max(1) as f64, sp);
    let ts = get_atomic_clock_realtime().get_time_ns();
    QuoteTick::new_checked(
        p.instrument_id(),
        Price::new(bid, pp),
        Price::new(ask, pp),
        size(q.bid_size),
        size(q.ask_size),
        ts,
        ts,
    )
    .ok()
}

#[async_trait::async_trait(?Send)]
impl DataClient for PublicDataClient {
    fn client_id(&self) -> ClientId {
        self.client_id
    }
    fn venue(&self) -> Option<Venue> {
        Some(Venue::new(VENUE))
    }
    fn start(&mut self) -> anyhow::Result<()> {
        Ok(())
    }
    fn stop(&mut self) -> anyhow::Result<()> {
        if let Some(p) = self.poller.take() {
            p.abort();
        }
        self.connected = false;
        Ok(())
    }
    fn reset(&mut self) -> anyhow::Result<()> {
        self.subscribed.lock().expect("subscriptions").clear();
        Ok(())
    }
    fn dispose(&mut self) -> anyhow::Result<()> {
        self.stop()
    }
    fn is_connected(&self) -> bool {
        self.connected
    }
    fn is_disconnected(&self) -> bool {
        !self.connected
    }

    /// Sends every configured instrument's definition, then reads the
    /// subscribed quotes on a timer.
    async fn connect(&mut self) -> anyhow::Result<()> {
        let sender = get_data_event_sender();
        let ts = get_atomic_clock_realtime().get_time_ns();
        for p in &self.config.instruments {
            sender
                .send(DataEvent::Data(Data::Instrument(Box::new(
                    p.definition(ts)?,
                ))))
                .map_err(|e| anyhow::anyhow!("the data engine refused an instrument: {e}"))?;
        }
        let (instruments, subscribed, every) = (
            self.config.instruments.clone(),
            self.subscribed.clone(),
            self.config.poll_ms,
        );
        self.poller = Some(get_runtime().spawn(async move {
            let api = Arc::new(Mutex::new(Public::new(None, None)));
            let mut tick = tokio::time::interval(std::time::Duration::from_millis(every));
            loop {
                tick.tick().await;
                let wanted: Vec<PublicInstrument> = {
                    let s = subscribed.lock().expect("subscriptions");
                    instruments
                        .iter()
                        .filter(|p| s.contains(&p.instrument_id()))
                        .cloned()
                        .collect()
                };
                if wanted.is_empty() {
                    continue;
                }
                let api = api.clone();
                let ask = wanted.clone();
                let read = tokio::task::spawn_blocking(move || {
                    let pairs: Vec<(&str, &str)> = ask
                        .iter()
                        .map(|p| (p.symbol.as_str(), p.kind.as_str()))
                        .collect();
                    api.lock().expect("public").quotes(pairs)
                })
                .await;
                let Ok(Ok(quotes)) = read else { continue };
                for q in quotes.iter().filter(|q| q.outcome == "SUCCESS") {
                    let found = wanted
                        .iter()
                        .find(|p| p.symbol == q.instrument.symbol && p.kind == q.instrument.kind);
                    if let Some(tick) = found.and_then(|p| quote_tick(p, q)) {
                        if sender.send(DataEvent::Data(Data::Quote(tick))).is_err() {
                            return;
                        }
                    }
                }
            }
        }));
        self.connected = true;
        Ok(())
    }

    async fn disconnect(&mut self) -> anyhow::Result<()> {
        self.stop()
    }

    fn subscribe_quotes(&mut self, cmd: SubscribeQuotes) -> anyhow::Result<()> {
        for id in &cmd.instrument_ids {
            if PublicInstrument::of(id, &self.config.instruments).is_none() {
                anyhow::bail!("{id} is not among the node's Public instruments");
            }
        }
        self.subscribed
            .lock()
            .expect("subscriptions")
            .extend(cmd.instrument_ids);
        Ok(())
    }

    fn unsubscribe_quotes(&mut self, cmd: &UnsubscribeQuotes) -> anyhow::Result<()> {
        let mut s = self.subscribed.lock().expect("subscriptions");
        for id in &cmd.instrument_ids {
            s.remove(id);
        }
        Ok(())
    }
}
