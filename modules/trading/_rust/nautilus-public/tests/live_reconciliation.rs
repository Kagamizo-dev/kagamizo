mod common;

use nautilus_public::node::Mode;

/// A node that stops holding a position, and a fresh node started after
/// it: the second learns the position from Public's portfolio
/// (reconciliation), not from anything the first left behind.
#[tokio::test(flavor = "multi_thread")]
async fn a_restarted_node_reconciles_the_position_public_holds() {
    let _stub = common::stub();
    let first = common::run(Mode::Live, true, u64::MAX / 2).await;
    assert_eq!(first.open, 1, "the first run leaves its position open");
    let second = common::run(Mode::Live, false, u64::MAX / 2).await;
    assert_eq!(second.open, 1, "the restarted node holds what Public holds");
}
