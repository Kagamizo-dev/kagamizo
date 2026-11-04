# What is measured, per module. A build target is rebuilt from scratch
# (`nix build --rebuild`) and timed; a runtime target is a flake app that
# prints its own milliseconds. Each method names what moves the number.
#
# The sources the methods rest on: Nix's `--rebuild` (a deterministic
# re-execution of one derivation, so the time is the build alone, not its
# dependencies); Lean's `decide` and `decide +kernel` (a proof by kernel
# evaluation: its cost is the size of the decided term, so smaller facts
# or `native_decide` move it; Mathlib's own benchmarking is per-file on
# its speedcenter, http://speed.lean-fro.org); criterion.rs for Rust
# runtimes (statistically bounded, outliers reported).
{
  perf.targets = {
    tokens-graph = {
      module = "tokens";
      kind = "build";
      attr = "checks.x86_64-linux.tokens-graph";
      method = "Lean deciding the credential graph (every child's scope within its parent's, by List.contains); moves with nodes × scope sizes";
    };
    inventory-build = {
      module = "inventory";
      kind = "build";
      attr = "packages.x86_64-linux.inventory";
      method = "cargo build --release of the inventory CLI (std only) and its statestore wrapper; moves with the schema";
    };
    inventory-lean = {
      module = "inventory";
      kind = "build";
      attr = "checks.x86_64-linux.inventory-lean";
      method = "Lean proving use, restock and low (omega) and deciding the schema well formed";
    };
    scout-build = {
      module = "scout";
      kind = "build";
      attr = "packages.x86_64-linux.scout";
      method = "cargo build --release of the discovery CLI (std only, facts as Rust source) and its gh wrapper; moves with the candidates";
    };
    scout-lean = {
      module = "scout";
      kind = "build";
      attr = "checks.x86_64-linux.scout-lean";
      method = "Lean deciding exits, no new cost and evidence over every candidate (decide +kernel); grows with roles times candidates";
    };
    project-build = {
      module = "project";
      kind = "build";
      attr = "packages.x86_64-linux.project";
      method = "cargo build --release of the project CLI (std only, facts as Rust source); moves with the number of epics and decisions";
    };
    project-lean = {
      module = "project";
      kind = "build";
      attr = "checks.x86_64-linux.project-lean";
      method = "Lean deciding the plan coherent, cycle search included (decide +kernel); grows with epics squared";
    };
    team-build = {
      module = "team";
      kind = "build";
      attr = "packages.x86_64-linux.team";
      method = "cargo build --release of the agent-identity CLI (std only, facts as Rust source); moves with the number of agents";
    };
    team-lean = {
      module = "team";
      kind = "build";
      attr = "checks.x86_64-linux.team-lean";
      method = "Lean deciding the identity rules over every agent (decide +kernel); grows with agents times teams";
    };
    statestore-build = {
      module = "statestore";
      kind = "build";
      attr = "packages.x86_64-linux.statestore";
      method = "cargo build --release of the Proton Pass state backend (std-only HTTP, serde, sha2); moves with the dependency set";
    };
    statestore-lean = {
      module = "statestore";
      kind = "build";
      attr = "checks.x86_64-linux.statestore-lean";
      method = "Lean checking the write protocol's safety and liveness and chunking's proofs (induction, no decide); moves with the proofs' tactic search";
    };
    migrate-build = {
      module = "migration";
      kind = "build";
      attr = "packages.x86_64-linux.migrate-run";
      method = "cargo build --release of the runner; crates vendored by Nix; moves with the dependency set and codegen settings (LTO, codegen-units)";
    };
    mailbox-build = {
      module = "mailbox";
      kind = "build";
      attr = "packages.x86_64-linux.mailbox-run";
      method = "cargo build --release of the IMAP reader and keychain stand-in; moves with native-tls/openssl linking";
    };
    lean-api-rclone = {
      module = "lean";
      kind = "build";
      attr = "checks.x86_64-linux.lean-api-rclone";
      method = "Lean deciding rclone's model closed (101 commands, 1100 global flags on one operation); moves with the catalog's size and the proof's shape";
    };
    lean-api-pyicloud = {
      module = "lean";
      kind = "build";
      attr = "checks.x86_64-linux.lean-api-pyicloud";
      method = "Lean deciding pyicloud's model (184 classes); moves with the catalog";
    };
    catalog-coverage = {
      module = "catalog";
      kind = "build";
      attr = "checks.x86_64-linux.catalog-coverage";
      method = "Python walking every source file against 7 catalogs; moves with the number of sources and the regexes";
    };
    governance-cedar = {
      module = "governance";
      kind = "build";
      attr = "checks.x86_64-linux.governance-cedar";
      method = "Cedar's test runner over every generated test (6169); moves with accounts × actions × agents";
    };
    migration-lean = {
      module = "migration";
      kind = "build";
      attr = "checks.x86_64-linux.migration";
      method = "Lean deciding closedRightly over the declared sources";
    };
    lean-governance = {
      module = "lean";
      kind = "build";
      attr = "checks.x86_64-linux.lean-governance";
      method = "Lean deciding every governed action typed and every grant allowed (decide +kernel)";
    };
    ci-pipeline = {
      module = "ci";
      kind = "build";
      attr = "checks.x86_64-linux.ci-pipeline";
      method = "Lean deciding every workflow sound";
    };
    operations-boundary = {
      module = "operations";
      kind = "build";
      attr = "checks.x86_64-linux.operations-boundary";
      method = "Lean deciding every declared secret well-formed";
    };
    trading-risk = {
      module = "trading";
      kind = "build";
      attr = "checks.x86_64-linux.trading-risk";
      method = "Lean proving what admissible guarantees (omega over Nat) and deciding the declared limits sane";
    };
    trading-stages = {
      module = "trading";
      kind = "build";
      attr = "checks.x86_64-linux.trading-stages";
      method = "Lean deciding every strategy's stage carries its evidence";
    };
    organization-areas = {
      module = "organization";
      kind = "build";
      attr = "checks.x86_64-linux.organization-areas";
      method = "Lean deciding every area separated, scoped and every mergeable class covered; moves with areas × classes";
    };
    governance-changes = {
      module = "governance";
      kind = "build";
      attr = "checks.x86_64-linux.governance-changes";
      method = "Lean deciding the change-class table's shape, plus the Rust tool's tests; moves with the table";
    };
    agents-budget = {
      module = "agents";
      kind = "build";
      attr = "checks.x86_64-linux.agents-budget";
      method = "Lean deciding every task's tier frugal and the keys' caps within the card (decide +kernel over the rendered lists); moves with tasks × keys";
    };
  };
}
