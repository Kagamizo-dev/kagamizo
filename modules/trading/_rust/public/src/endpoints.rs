//! Public's whole API, bounded. Every endpoint the pinned publicdotcom-cli's
//! generated client knows (../api-endpoints.json, read at compile time) is
//! an `Endpoint`, with its method, path template, the CLI command it is and
//! that command's effect (session, read, write or spend; the same effects
//! governance.actions.public types, which modules/public/endpoints.nix
//! checks in Lean). A client is built with a `Bound`, the endpoints it may
//! call; every request is refused unless its endpoint is in the bound and
//! its path is that endpoint's template. The reader bound has no write and
//! no spend; only the placer adds one endpoint, the single-leg order.
use serde::Deserialize;
use std::collections::BTreeMap;
use std::sync::OnceLock;

const TABLE: &str = include_str!("../api-endpoints.json");

#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "lowercase")]
pub enum Effect {
    /// Mints the short-lived access token.
    Session,
    /// Reads, quotes and preflights: nothing changes at Public.
    Read,
    /// Changes an order without spending (cancel).
    Write,
    /// Moves money: places or replaces an order.
    Spend,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Spec {
    pub group: String,
    pub method: String,
    pub path: String,
    pub command: String,
    pub effect: Effect,
}

#[derive(Deserialize)]
struct Client {
    endpoints: Vec<String>,
}

#[derive(Deserialize)]
struct Table {
    endpoints: BTreeMap<String, Spec>,
    clients: BTreeMap<String, Client>,
}

fn table() -> &'static Table {
    static T: OnceLock<Table> = OnceLock::new();
    T.get_or_init(|| serde_json::from_str(TABLE).expect("api-endpoints.json is a valid table"))
}

macro_rules! endpoints {
    ($($variant:ident => $name:literal),* $(,)?) => {
        /// Every endpoint of Public's API.
        #[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
        pub enum Endpoint { $($variant),* }

        impl Endpoint {
            pub const ALL: &'static [Endpoint] = &[$(Endpoint::$variant),*];

            /// The generated client's function name, the table's key.
            pub fn name(self) -> &'static str {
                match self { $(Endpoint::$variant => $name),* }
            }
        }
    };
}

endpoints! {
    CreatePersonalAccessToken => "create_personal_access_token",
    GetAccountPortfolioV2 => "get_account_portfolio_v2",
    GetHistory => "get_history",
    GetAccounts => "get_accounts",
    GetAllInstruments => "get_all_instruments",
    GetInstrument => "get_instrument",
    SearchBonds => "search_bonds",
    GetBarsV2 => "get_bars_v2",
    GetBarsV2WithAggregation => "get_bars_v2_with_aggregation",
    GetBondDetails => "get_bond_details",
    GetEventContractBars => "get_event_contract_bars",
    GetOptionChain => "get_option_chain",
    GetOptionExpirations => "get_option_expirations",
    GetQuotes => "get_quotes",
    GetOptionGreeks => "get_option_greeks",
    GetStrategyQuote => "get_strategy_quote",
    GetEventCategories => "get_event_categories",
    GetEventDetails => "get_event_details",
    GetEventSummary => "get_event_summary",
    CancelOrder => "cancel_order",
    GetOrder => "get_order",
    PlaceMultilegOrder => "place_multileg_order",
    PlaceOrder => "place_order",
    PreflightMultiLeg => "preflight_multi_leg",
    PreflightSingleLeg => "preflight_single_leg",
    ReplaceOrder => "replace_order",
    SearchOrders => "search_orders",
    GetUnrealizedTaxLots => "get_unrealized_tax_lots",
    GetUnrealizedTaxLotsCsv => "get_unrealized_tax_lots_csv",
    GetUnrealizedTaxLotsForSymbol => "get_unrealized_tax_lots_for_symbol",
}

impl Endpoint {
    pub fn spec(self) -> &'static Spec {
        &table().endpoints[self.name()]
    }

    pub fn effect(self) -> Effect {
        self.spec().effect
    }

    /// Whether `path` (its query aside) is this endpoint's template, each
    /// `{name}` standing for one non-empty segment.
    pub fn matches(self, path: &str) -> bool {
        let path = path.split('?').next().unwrap_or("");
        let want: Vec<&str> = self.spec().path.split('/').collect();
        let got: Vec<&str> = path.split('/').collect();
        want.len() == got.len()
            && want.iter().zip(&got).all(|(w, g)| {
                if w.starts_with('{') && w.ends_with('}') { !g.is_empty() } else { w == g }
            })
    }

    fn by_name(name: &str) -> Option<Endpoint> {
        Endpoint::ALL.iter().copied().find(|e| e.name() == name)
    }
}

/// The endpoints a client may call.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Bound {
    /// Every trade-run command but place: reads, quotes and preflights.
    Reader,
    /// trade-run place: the reader's endpoints and the single-leg order.
    Placer,
}

impl Bound {
    pub fn name(self) -> &'static str {
        match self {
            Bound::Reader => "reader",
            Bound::Placer => "placer",
        }
    }

    pub fn endpoints(self) -> Vec<Endpoint> {
        table().clients[self.name()]
            .endpoints
            .iter()
            .map(|n| Endpoint::by_name(n).unwrap_or_else(|| panic!("clients.{}: no endpoint {n}", self.name())))
            .collect()
    }

    pub fn allows(self, e: Endpoint) -> bool {
        self.endpoints().contains(&e)
    }

    /// The request, or why it is refused.
    pub fn check(self, e: Endpoint, method: &str, path: &str) -> Result<(), String> {
        if !self.allows(e) {
            return Err(format!("public: the {} client may not call {} ({})", self.name(), e.name(), e.spec().command));
        }
        if e.spec().method != method || !e.matches(path) {
            return Err(format!("public: {method} {path} is not {} ({} {})", e.name(), e.spec().method, e.spec().path));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_enum_is_exactly_the_table() {
        let names: Vec<&str> = Endpoint::ALL.iter().map(|e| e.name()).collect();
        let keys: Vec<&str> = table().endpoints.keys().map(String::as_str).collect();
        let mut sorted = names.clone();
        sorted.sort();
        assert_eq!(sorted, keys);
        assert_eq!(names.len(), 30);
    }

    #[test]
    fn only_orders_spend_and_only_cancel_writes() {
        let of = |eff| -> Vec<&str> { Endpoint::ALL.iter().filter(|e| e.effect() == eff).map(|e| e.name()).collect() };
        assert_eq!(of(Effect::Spend), vec!["place_multileg_order", "place_order", "replace_order"]);
        assert_eq!(of(Effect::Write), vec!["cancel_order"]);
        assert_eq!(of(Effect::Session), vec!["create_personal_access_token"]);
    }

    #[test]
    fn the_reader_neither_writes_nor_spends() {
        assert!(Bound::Reader.endpoints().iter().all(|e| matches!(e.effect(), Effect::Read | Effect::Session)));
    }

    #[test]
    fn the_placer_adds_exactly_the_single_leg_order_and_its_cancel() {
        let r = Bound::Reader.endpoints();
        let extra: Vec<Endpoint> = Bound::Placer.endpoints().into_iter().filter(|e| !r.contains(e)).collect();
        assert_eq!(extra, vec![Endpoint::CancelOrder, Endpoint::PlaceOrder]);
        assert!(!Bound::Reader.allows(Endpoint::CancelOrder));
        assert!(!Bound::Placer.allows(Endpoint::ReplaceOrder));
        assert!(!Bound::Placer.allows(Endpoint::PlaceMultilegOrder));
    }

    #[test]
    fn a_path_must_be_its_endpoints_template() {
        assert!(Endpoint::GetOrder.matches("/userapigateway/trading/5LA00001/order/abc"));
        assert!(!Endpoint::GetOrder.matches("/userapigateway/trading/5LA00001/order"));
        assert!(Bound::Reader.check(Endpoint::PlaceOrder, "POST", "/userapigateway/trading/5LA00001/order").is_err());
        assert!(Bound::Placer.check(Endpoint::PlaceOrder, "POST", "/userapigateway/trading/5LA00001/order").is_ok());
        assert!(Bound::Placer.check(Endpoint::PlaceOrder, "PUT", "/userapigateway/trading/5LA00001/order").is_err());
    }
}

/// An order's life at Public (the generated client's GatewayOrderStatus):
/// working until it ends, and once ended it never changes again.
#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum OrderStatus {
    New,
    PartiallyFilled,
    PendingCancel,
    PendingReplace,
    QueuedCancelled,
    Filled,
    Cancelled,
    Expired,
    Rejected,
    Replaced,
}

impl OrderStatus {
    pub const ALL: &'static [OrderStatus] = &[
        OrderStatus::New, OrderStatus::PartiallyFilled, OrderStatus::PendingCancel,
        OrderStatus::PendingReplace, OrderStatus::QueuedCancelled, OrderStatus::Filled,
        OrderStatus::Cancelled, OrderStatus::Expired, OrderStatus::Rejected, OrderStatus::Replaced,
    ];

    pub fn parse(s: &str) -> Option<OrderStatus> {
        serde_json::from_value(serde_json::Value::String(s.to_string())).ok()
    }

    /// Ended: filled, cancelled, expired, rejected or replaced.
    pub fn terminal(self) -> bool {
        matches!(self, OrderStatus::Filled | OrderStatus::Cancelled | OrderStatus::Expired
            | OrderStatus::Rejected | OrderStatus::Replaced)
    }
}

/// How an event contract's outcome settled (SettledOutcome).
#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SettledOutcome {
    SettledOutcomeUnspecified,
    SettledOutcomeYes,
    SettledOutcomeNo,
    SettledOutcomeOther,
}

impl SettledOutcome {
    pub fn parse(s: &str) -> Option<SettledOutcome> {
        serde_json::from_value(serde_json::Value::String(s.to_string())).ok()
    }
}

#[cfg(test)]
mod lifecycle_tests {
    use super::*;

    #[test]
    fn a_partial_fill_is_still_working() {
        assert!(!OrderStatus::parse("PARTIALLY_FILLED").unwrap().terminal());
        assert!(!OrderStatus::parse("NEW").unwrap().terminal());
        assert!(OrderStatus::parse("FILLED").unwrap().terminal());
        assert_eq!(OrderStatus::parse("PENDING"), None, "Public has no PENDING status");
        assert_eq!(OrderStatus::ALL.iter().filter(|s| s.terminal()).count(), 5);
    }

    #[test]
    fn settlements_parse() {
        assert_eq!(SettledOutcome::parse("SETTLED_OUTCOME_YES"), Some(SettledOutcome::SettledOutcomeYes));
        assert_eq!(SettledOutcome::parse("UNSETTLED"), None);
    }
}
