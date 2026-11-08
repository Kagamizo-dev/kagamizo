mod common;

/// Paper: Nautilus's sandbox fills the orders against Public's quotes, with
/// zerohash's 0.60% fee on each side.
#[tokio::test(flavor = "multi_thread")]
async fn paper_buys_holds_and_sells_through_nautilus() {
    let o = common::round_trip(nautilus_public::node::Mode::Paper).await;
    assert_eq!(
        (o.closed, o.open),
        (1, 0),
        "one round trip, nothing left open"
    );
    // Bought at the 87,505 ask, sold at the 87,495 bid, 0.60% a side on
    // ~$24.85: the spread (~$0.003) and two fees (~$0.30) lost.
    assert!(
        o.realized_usd < -0.25 && o.realized_usd > -0.35,
        "realized {}",
        o.realized_usd
    );
}
