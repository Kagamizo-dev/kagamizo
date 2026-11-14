mod common;

/// Live, against the stub only: our Public execution client places, reads
/// back and fills the same two orders; Nautilus keeps the position.
#[tokio::test(flavor = "multi_thread")]
async fn live_buys_holds_and_sells_through_public() {
    let o = common::round_trip(nautilus_public::node::Mode::Live).await;
    assert_eq!(
        (o.closed, o.open),
        (1, 0),
        "one round trip, nothing left open"
    );
    assert!(
        o.realized_usd < -0.25 && o.realized_usd > -0.35,
        "realized {}",
        o.realized_usd
    );
}
