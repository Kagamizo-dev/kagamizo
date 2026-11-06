# Performance records

Per module, the best time known for each measured target and the
latest measurement, in milliseconds (`_json/records.json`, moved by
`perf-record` from CI's `perf-measure`). `checks.perf` has Lean
decide that every latest measurement is within its record's
tolerance; a slower build fails. Rendered by `nix run .#perf-readme`.

| Module | Target | Kind | Record (ms) | Latest (ms) | Tolerance | Method |
|---|---|---|---|---|---|---|
| agents | `agents-budget` | build | none yet | none yet | 10% | Lean deciding every task's tier frugal and the keys' caps within the card (decide +kernel over the rendered lists); moves with tasks × keys |
| android | `android-twin` | build | none yet | none yet | 10% | Lean deciding every base, app and setting pinned and typed, plus the rendered AVD config read back |
| mercury | `cards-declared` | build | none yet | none yet | 10% | Lean deciding the committed card discovery against the declarations |
| catalog | `catalog-coverage` | build | none yet | none yet | 10% | Python walking every source file against 7 catalogs; moves with the number of sources and the regexes |
| ci | `ci-pipeline` | build | none yet | none yet | 10% | Lean deciding every workflow sound |
| cloudflare | `cloudflare-access` | build | none yet | none yet | 10% | Lean deciding every agent's Access token policy attached only to apps its tools justify, the owner first, none on status (decide +kernel over the rendered lists); moves with agents × tools |
| compliance | `compliance-rules` | build | none yet | none yet | 10% | Lean deciding every strategy against the day-trade rule and its options level on its observed account |
| discord | `discord-relay` | build | none yet | none yet | 10% | Lean deciding the relay rule on the declared ids, plus the crate's tests |
| gamedev | `gamedev-profile` | build | none yet | none yet | 10% | Lean deciding the profile open source but its declared platform, plus the versions listing |
| governance | `governance-cedar` | build | none yet | none yet | 10% | Cedar's test runner over every generated test (6169); moves with accounts × actions × agents |
| governance | `governance-changes` | build | none yet | none yet | 10% | Lean deciding the change-class table's shape, plus the Rust tool's tests; moves with the table |
| repo | `languages` | build | none yet | none yet | 10% | lang-scan walking the tree against the typed policy and its exceptions; moves with the number of files |
| repo | `languages-ratchet` | build | none yet | none yet | 10% | Lean deciding every language exception owned, dated and within the baseline (decide +kernel); moves with the exceptions |
| lean | `lean-api-pyicloud` | build | none yet | none yet | 10% | Lean deciding pyicloud's model (184 classes); moves with the catalog |
| lean | `lean-api-rclone` | build | none yet | none yet | 10% | Lean deciding rclone's model closed (101 commands, 1100 global flags on one operation); moves with the catalog's size and the proof's shape |
| lean | `lean-governance` | build | none yet | none yet | 10% | Lean deciding every governed action typed and every grant allowed (decide +kernel) |
| legal | `legal-record` | build | none yet | none yet | 10% | Lean deciding each legal record complete for its status, plus eleven Typst renders with placeholders |
| mailbox | `mailbox-build` | build | none yet | none yet | 10% | cargo build --release of the IMAP reader and keychain stand-in; moves with native-tls/openssl linking |
| media | `media-clips` | build | none yet | none yet | 10% | Lean proving a cut list's bounds and deciding the declared maximum, plus the crate's tests (a synthetic index and a byte-identical double render) |
| migration | `migrate-build` | build | none yet | none yet | 10% | cargo build --release of the runner; crates vendored by Nix; moves with the dependency set and codegen settings (LTO, codegen-units) |
| migration | `migration-lean` | build | none yet | none yet | 10% | Lean deciding closedRightly over the declared sources |
| money | `money-flows` | build | none yet | none yet | 10% | Lean deciding every flow booked and none executable without approval |
| operations | `operations-boundary` | build | none yet | none yet | 10% | Lean deciding every declared secret well-formed |
| organization | `organization-areas` | build | none yet | none yet | 10% | Lean deciding every area separated, scoped and every mergeable class covered; moves with areas × classes |
| public | `public-endpoints` | build | none yet | none yet | 10% | The declared endpoints held against the pinned client's generated modules |
| research | `research-papers` | build | none yet | none yet | 10% | Lean deciding every paper's facts allowed, then Pandoc and Typst renders scanned for the denylist; moves with the prose and the Lean files' size |
| statestore | `statestore-build` | build | none yet | none yet | 10% | cargo build --release of the Proton Pass state backend (std-only HTTP, serde, sha2); moves with the dependency set |
| statestore | `statestore-lean` | build | none yet | none yet | 10% | Lean checking the write protocol's safety and liveness and chunking's proofs (induction, no decide); moves with the proofs' tactic search |
| tokens | `tokens-graph` | build | none yet | none yet | 10% | Lean deciding the credential graph (every child's scope within its parent's, by List.contains); moves with nodes × scope sizes |
| trading | `trading-risk` | build | none yet | none yet | 10% | Lean proving what admissible guarantees (omega over Nat) and deciding the declared limits sane |
| trading | `trading-stages` | build | none yet | none yet | 10% | Lean deciding every strategy's stage carries its evidence |
| trading | `trading-weather` | build | none yet | none yet | 10% | The weather signal engine's unit tests over forecast fixtures (parsers, probabilities, edge) |
| twin | `twin-world` | build | none yet | none yet | 10% | Lean deciding the world's shape: every module has a building, every agent a character, every recipe's action declared |

## Baseline

Measured on the cloud container, 4 jobs, 2026-11-01 (not records: CI's runner sets those); a first look, before CI's records exist.

| Target | ms |
|---|---|
| `catalog-coverage` | 3038 |
| `ci-pipeline` | 993 |
| `governance-cedar` | 918 |
| `lean-api-rclone` | 37377 |
| `migrate-build` | 20591 |
| `migration-lean` | 1360 |
| `operations-boundary` | 2848 |

- `governance-cedar`: 305613 ms with `cedar run-tests` (entities inside each of 6289 tests, 70 MB); 918 ms with the in-process runner (modules/governance/_src), the same tests, 2.4 MB

What stands out, in order of cost: `lean-api-rclone` (one `decide`
over 1200 operations; splitting the closedness proof per chunk,
or `native_decide`, is the cut), `migrate-build` (the Rust
release build; LTO off and `codegen-units` up for CI, the cache
serving it otherwise), `catalog-coverage` (Python over every
source file; a Rust walker, or scanning only changed files).

