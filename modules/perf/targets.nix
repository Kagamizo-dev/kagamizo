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
    media-clips = {
      module = "media";
      kind = "build";
      attr = "checks.x86_64-linux.media-clips";
      method = "Lean proving a cut list's bounds and deciding the declared maximum, plus the crate's tests (a synthetic index and a byte-identical double render)";
    };
    discord-relay = {
      module = "discord";
      kind = "build";
      attr = "checks.x86_64-linux.discord-relay";
      method = "Lean deciding the relay rule on the declared ids, plus the crate's tests";
    };
    android-twin = {
      module = "android";
      kind = "build";
      attr = "checks.x86_64-linux.android-twin";
      method = "Lean deciding every base, app and setting pinned and typed, plus the rendered AVD config read back";
    };
    gamedev-profile = {
      module = "gamedev";
      kind = "build";
      attr = "checks.x86_64-linux.gamedev-profile";
      method = "Lean deciding the profile open source but its declared platform, plus the versions listing";
    };
    trading-weather = {
      module = "trading";
      kind = "build";
      attr = "checks.x86_64-linux.trading-weather";
      method = "The weather signal engine's unit tests over forecast fixtures (parsers, probabilities, edge)";
    };
    compliance-rules = {
      module = "compliance";
      kind = "build";
      attr = "checks.x86_64-linux.compliance-rules";
      method = "Lean deciding every strategy against the day-trade rule and its options level on its observed account";
    };
    legal-record = {
      module = "legal";
      kind = "build";
      attr = "checks.x86_64-linux.legal-record";
      method = "Lean deciding each legal record complete for its status, plus eleven Typst renders with placeholders";
    };
    research-papers = {
      module = "research";
      kind = "build";
      attr = "checks.x86_64-linux.research-papers";
      method = "Lean deciding every paper's facts allowed, then Pandoc and Typst renders scanned for the denylist; moves with the prose and the Lean files' size";
    };
    public-endpoints = {
      module = "public";
      kind = "build";
      attr = "checks.x86_64-linux.public-endpoints";
      method = "The declared endpoints held against the pinned client's generated modules";
    };
    money-flows = {
      module = "money";
      kind = "build";
      attr = "checks.x86_64-linux.money-flows";
      method = "Lean deciding every flow booked and none executable without approval";
    };
    cards-declared = {
      module = "mercury";
      kind = "build";
      attr = "checks.x86_64-linux.cards-declared";
      method = "Lean deciding the committed card discovery against the declarations";
    };
    agents-budget = {
      module = "agents";
      kind = "build";
      attr = "checks.x86_64-linux.agents-budget";
      method = "Lean deciding every task's tier frugal and the keys' caps within the card (decide +kernel over the rendered lists); moves with tasks × keys";
    };
    cloudflare-access = {
      module = "cloudflare";
      kind = "build";
      attr = "checks.x86_64-linux.cloudflare-access";
      method = "Lean deciding every agent's Access token policy attached only to apps its tools justify, the owner first, none on status (decide +kernel over the rendered lists); moves with agents × tools";
    };
    twin-world = {
      module = "twin";
      kind = "build";
      attr = "checks.x86_64-linux.twin-world";
      method = "Lean deciding the world's shape: every module has a building, every agent a character, every recipe's action declared";
    };
    languages = {
      module = "repo";
      kind = "build";
      attr = "checks.x86_64-linux.languages";
      method = "lang-scan walking the tree against the typed policy and its exceptions; moves with the number of files";
    };
    languages-ratchet = {
      module = "repo";
      kind = "build";
      attr = "checks.x86_64-linux.languages-ratchet";
      method = "Lean deciding every language exception owned, dated and within the baseline (decide +kernel); moves with the exceptions";
    };
    agents-charters = {
      module = "agents";
      kind = "build";
      attr = "checks.x86_64-linux.agents-charters";
      method = "Lean deciding the lifecycles separated, trades reviewed by legal and accounting, and money and going live owner-gated (decide +kernel); moves with kinds x reviewers";
    };
    twin-adoptions = {
      module = "twin";
      kind = "build";
      attr = "checks.x86_64-linux.twin-adoptions";
      method = "Lean deciding every adoption licensed for its use, Rust where it runs, and tested before it is trusted (decide +kernel); moves with the adoptions";
    };
    open-webui = {
      module = "hetzner";
      kind = "build";
      attr = "checks.x86_64-linux.open-webui";
      method = "Lean deciding every Open WebUI switch decided, the forbidden ones off and every variable known to the pinned version (decide +kernel over the catalog); moves with the catalog";
    };
  };
}
