# Performance records

Per module, the best time known for each measured target and the
latest measurement, in milliseconds (`_json/records.json`, moved by
`perf-record` from CI's `perf-measure`). `checks.perf` has Lean
decide that every latest measurement is within its record's
tolerance; a slower build fails. Rendered by `nix run .#perf-readme`.

| Module | Target | Kind | Record (ms) | Latest (ms) | Tolerance | Method |
|---|---|---|---|---|---|---|
| agents | `agents-budget` | build | none yet | none yet | 10% | Lean deciding every task's tier frugal and the keys' caps within the card (decide +kernel over the rendered lists); moves with tasks × keys |
| catalog | `catalog-coverage` | build | none yet | none yet | 10% | Python walking every source file against 7 catalogs; moves with the number of sources and the regexes |
| ci | `ci-pipeline` | build | none yet | none yet | 10% | Lean deciding every workflow sound |
| governance | `governance-cedar` | build | none yet | none yet | 10% | Cedar's test runner over every generated test (6169); moves with accounts × actions × agents |
| inventory | `inventory-build` | build | none yet | none yet | 10% | cargo build --release of the inventory CLI (std only) and its statestore wrapper; moves with the schema |
| inventory | `inventory-lean` | build | none yet | none yet | 10% | Lean proving use, restock and low (omega) and deciding the schema well formed |
| lean | `lean-api-pyicloud` | build | none yet | none yet | 10% | Lean deciding pyicloud's model (184 classes); moves with the catalog |
| lean | `lean-api-rclone` | build | none yet | none yet | 10% | Lean deciding rclone's model closed (101 commands, 1100 global flags on one operation); moves with the catalog's size and the proof's shape |
| lean | `lean-governance` | build | none yet | none yet | 10% | Lean deciding every governed action typed and every grant allowed (decide +kernel) |
| mailbox | `mailbox-build` | build | none yet | none yet | 10% | cargo build --release of the IMAP reader and keychain stand-in; moves with native-tls/openssl linking |
| migration | `migrate-build` | build | none yet | none yet | 10% | cargo build --release of the runner; crates vendored by Nix; moves with the dependency set and codegen settings (LTO, codegen-units) |
| migration | `migration-lean` | build | none yet | none yet | 10% | Lean deciding closedRightly over the declared sources |
| operations | `operations-boundary` | build | none yet | none yet | 10% | Lean deciding every declared secret well-formed |
| project | `project-build` | build | none yet | none yet | 10% | cargo build --release of the project CLI (std only, facts as Rust source); moves with the number of epics and decisions |
| project | `project-lean` | build | none yet | none yet | 10% | Lean deciding the plan coherent, cycle search included (decide +kernel); grows with epics squared |
| scout | `scout-build` | build | none yet | none yet | 10% | cargo build --release of the discovery CLI (std only, facts as Rust source) and its gh wrapper; moves with the candidates |
| scout | `scout-lean` | build | none yet | none yet | 10% | Lean deciding exits, no new cost and evidence over every candidate (decide +kernel); grows with roles times candidates |
| statestore | `statestore-build` | build | none yet | none yet | 10% | cargo build --release of the Proton Pass state backend (std-only HTTP, serde, sha2); moves with the dependency set |
| statestore | `statestore-lean` | build | none yet | none yet | 10% | Lean checking the write protocol's safety and liveness and chunking's proofs (induction, no decide); moves with the proofs' tactic search |
| team | `team-build` | build | none yet | none yet | 10% | cargo build --release of the agent-identity CLI (std only, facts as Rust source); moves with the number of agents |
| team | `team-lean` | build | none yet | none yet | 10% | Lean deciding the identity rules over every agent (decide +kernel); grows with agents times teams |
| tokens | `tokens-graph` | build | none yet | none yet | 10% | Lean deciding the credential graph (every child's scope within its parent's, by List.contains); moves with nodes × scope sizes |

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

