# research-jingzo: a backtest the weather strategy can count

Read CLAUDE.md first. Kind: strategy (review, security, legal-mirazo and accounting-mirazo pass it; the owner signs off).

`trading.strategies.weather-rules` is at `research`. Paper days count only after a recorded backtest with alpha above zero and a drawdown of at most 20% (modules/trading/stages.nix). The existing `trade backtest` replays price bars through NautilusTrader, which cannot test contracts that settle on observed weather.

Build a Rust crate `modules/trading/_rust/weather-backtest` (no Python; the language rule) that, for each declared city and each past day:
1. reads the forecast that existed before the contract closed (Open-Meteo's historical forecast API);
2. reads the official observed high and low (the National Weather Service's climate reports, which Kalshi's weather contracts settle on);
3. reads the contract's traded prices from Kalshi's public market data. Map the endpoints from the API itself before using them;
4. applies the declared rules unchanged (modules/trading/_weather.py's probability and edge, ported to Rust with the same test fixtures, `_json/forecasts.json`), within the declared limits: maxContractPrice, daily take-profit and loss stop;
5. writes a typed result: days, trades, P&L, alpha, maximum drawdown and hit rate. Record it under research/backtests, and set `stages.weather-rules.backtest` from it.

It runs on jingzo-host: this session's allowlist does not reach the weather or Kalshi hosts (upkeep/host-runner). Lean: the backtest's limits are the strategy's declared limits, and the result counts only under backtestCounts.
