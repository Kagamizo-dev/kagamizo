//! The factories the live node builds the clients from.

use std::{cell::RefCell, rc::Rc};

use nautilus_common::{
    cache::CacheView,
    clients::{DataClient, ExecutionClient},
    clock::Clock,
    factories::{ClientConfig, DataClientFactory, ExecutionClientFactory},
};
use nautilus_model::identifiers::{ClientId, TraderId};

use crate::{
    config::{PublicDataClientConfig, PublicExecClientConfig},
    data::PublicDataClient,
    execution::PublicExecutionClient,
};

#[derive(Debug, Clone, Default)]
pub struct PublicDataClientFactory;

impl DataClientFactory for PublicDataClientFactory {
    fn create(
        &self,
        name: &str,
        config: &dyn ClientConfig,
        _cache: CacheView,
        _clock: Rc<RefCell<dyn Clock>>,
    ) -> anyhow::Result<Box<dyn DataClient>> {
        let config = config
            .as_any()
            .downcast_ref::<PublicDataClientConfig>()
            .ok_or_else(|| {
                anyhow::anyhow!("PublicDataClientFactory takes a PublicDataClientConfig")
            })?;
        Ok(Box::new(PublicDataClient::new(
            ClientId::from(name),
            config.clone(),
        )))
    }
    fn name(&self) -> &'static str {
        crate::VENUE
    }
    fn config_type(&self) -> &'static str {
        "PublicDataClientConfig"
    }
}

#[derive(Debug, Clone, Default)]
pub struct PublicExecutionClientFactory;

impl ExecutionClientFactory for PublicExecutionClientFactory {
    fn create(
        &self,
        trader_id: TraderId,
        name: &str,
        config: &dyn ClientConfig,
        cache: CacheView,
        _clock: Rc<RefCell<dyn Clock>>,
    ) -> anyhow::Result<Box<dyn ExecutionClient>> {
        let config = config
            .as_any()
            .downcast_ref::<PublicExecClientConfig>()
            .ok_or_else(|| {
                anyhow::anyhow!("PublicExecutionClientFactory takes a PublicExecClientConfig")
            })?;
        Ok(Box::new(PublicExecutionClient::new(
            trader_id,
            ClientId::from(name),
            config.clone(),
            cache,
        )))
    }
    fn name(&self) -> &'static str {
        crate::VENUE
    }
    fn config_type(&self) -> &'static str {
        "PublicExecClientConfig"
    }
}
