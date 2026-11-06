# upkeep: the trade binary in Rust

Read CLAUDE.md and the trading module's paper first. After
upkeep/trading-public-rust lands: a `trade` binary in modules/trading/_rust
replacing modules/trading/_trade.py and _propose.py command for command
(strategies, account, bars, propose, paper-day, place), on the
kagamizo-public and kagamizo-weather crates, with propose_event and the
agent-option proposal ported exactly, `admissible` included. The checks in
modules/trading/strategies.nix that run the Python against the stub become
Rust integration tests against public-stub, with no shell in Nix. Then
delete the six Python files and their language exceptions, and lower the
baseline. `backtest` and `paper` over bars wait on
reverse-engineering/nautilus-rust.
