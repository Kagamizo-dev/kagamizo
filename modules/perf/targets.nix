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
  };
}
