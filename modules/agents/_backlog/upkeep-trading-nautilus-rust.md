# upkeep: backtest and paper on NautilusTrader's Rust crates

Read CLAUDE.md and the trading module's paper first. `trade-run backtest`
and `trade-run paper` (modules/trading/_trade.py `run`, `backtest`,
`paper`) move into modules/trading/_rust/trade on NautilusTrader's Rust
crates (0.67, mapped in modules/trading/_json/nautilus-rust-api.json; the
probe in modules/trading/_rust/nautilus-probe runs the engine to fills):
bars from CSV or Public into a BacktestEngine with a cash venue, the
EMA-cross strategy with the declared parameters, the same result JSON, and
`paper`'s preflight of the last bar's orders. Then the wrapper calls only
the Rust binary, the bars scenarios of checks.trading-backtest become Rust
tests, and _trade.py, _propose.py, _public.py, _stub_public.py, _weather.py
and _weather_test.py are deleted with their exceptions, lowering the
baseline. The Python wheel (packages.nautilus-trader) goes with them.
