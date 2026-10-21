"""`trade`: NautilusTrader from the command line, driven by declared strategies.

  trade backtest STRATEGY BARS.csv   run a declared strategy over bars and
                                     print the result as JSON
  trade strategies                   the declared strategies, as JSON

BARS.csv has a header and one bar per row: timestamp (ISO 8601, UTC), open,
high, low, close, volume. Strategies come from TRADE_STRATEGIES (JSON, made
by modules/trading/strategies.nix): each names its kind, instrument, venue,
bar step and parameters. Nothing here touches an account: backtests run on
a simulated venue with a simulated balance.
"""

import csv
import json
import os
import sys
from decimal import Decimal

import pandas as pd

from nautilus_trader.backtest.engine import BacktestEngine, BacktestEngineConfig
from nautilus_trader.config import LoggingConfig
from nautilus_trader.model.currencies import USD
from nautilus_trader.model.data import Bar, BarType
from nautilus_trader.model.enums import AccountType, OmsType
from nautilus_trader.model.identifiers import InstrumentId, Symbol, TraderId, Venue
from nautilus_trader.model.instruments import Equity
from nautilus_trader.model.objects import Money, Price, Quantity
from nautilus_trader.persistence.wranglers import BarDataWrangler


def die(msg, code=1):
    print(f"trade: {msg}", file=sys.stderr)
    sys.exit(code)


def strategies():
    try:
        return json.loads(os.environ["TRADE_STRATEGIES"])
    except (KeyError, json.JSONDecodeError):
        die("TRADE_STRATEGIES is not set; run trade through its wrapper", 2)


def equity(symbol, venue):
    return Equity(
        instrument_id=InstrumentId(Symbol(symbol), Venue(venue)),
        raw_symbol=Symbol(symbol),
        currency=USD,
        price_precision=2,
        price_increment=Price.from_str("0.01"),
        lot_size=Quantity.from_int(1),
        ts_event=0,
        ts_init=0,
    )


def read_bars(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        die(f"{path}: no bars")
    missing = {"timestamp", "open", "high", "low", "close", "volume"} - set(rows[0])
    if missing:
        die(f"{path}: missing columns {', '.join(sorted(missing))}")
    df = pd.DataFrame(rows)
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    df = df.set_index("timestamp").sort_index()
    return df[["open", "high", "low", "close", "volume"]].astype(float)


def strategy_for(kind, instrument, bar_type, params):
    if kind == "ema-cross":
        from nautilus_trader.examples.strategies.ema_cross import EMACross, EMACrossConfig

        return EMACross(
            EMACrossConfig(
                instrument_id=instrument.id,
                bar_type=bar_type,
                trade_size=Decimal(str(params["tradeSize"])),
                fast_ema_period=params["fastPeriod"],
                slow_ema_period=params["slowPeriod"],
                request_bars=False,
                subscribe_trade_ticks=False,
            )
        )
    die(f"no strategy kind {kind}")


def backtest(name, bars_path):
    decl = strategies().get(name) or die(f"no strategy {name}; declared: {', '.join(strategies())}", 2)
    venue = decl["venue"]
    instrument = equity(decl["symbol"], venue)
    bar_type = BarType.from_str(f"{instrument.id}-{decl['bar']}-LAST-EXTERNAL")

    engine = BacktestEngine(
        BacktestEngineConfig(
            trader_id=TraderId("KAGAMIZO-001"),
            logging=LoggingConfig(log_level=os.environ.get("TRADE_LOG", "ERROR")),
        )
    )
    engine.add_venue(
        venue=Venue(venue),
        oms_type=OmsType.NETTING,
        account_type=AccountType.CASH,
        base_currency=USD,
        starting_balances=[Money(decl["startingUsd"], USD)],
    )
    engine.add_instrument(instrument)
    engine.add_data(BarDataWrangler(bar_type, instrument).process(read_bars(bars_path)))
    engine.add_strategy(strategy_for(decl["kind"], instrument, bar_type, decl["params"]))
    engine.run()

    account = engine.trader.generate_account_report(Venue(venue))
    fills = engine.trader.generate_order_fills_report()
    positions = engine.trader.generate_positions_report()
    result = {
        "strategy": name,
        "instrument": str(instrument.id),
        "bars": engine.iteration,
        "orders_filled": len(fills),
        "positions": len(positions),
        "starting_usd": decl["startingUsd"],
        "ending_usd": float(account["total"].iloc[-1]) if len(account) else decl["startingUsd"],
        "realized_pnl_usd": float(positions["realized_pnl"].map(lambda m: float(str(m).split()[0])).sum())
        if len(positions)
        else 0.0,
    }
    engine.dispose()
    json.dump(result, sys.stdout, indent=2)
    print()


def main(argv):
    if not argv:
        die("usage: trade <backtest STRATEGY BARS.csv | strategies>", 2)
    if argv[0] == "strategies":
        json.dump(strategies(), sys.stdout, indent=2)
        print()
    elif argv[0] == "backtest" and len(argv) == 3:
        backtest(argv[1], argv[2])
    else:
        die("usage: trade <backtest STRATEGY BARS.csv | strategies>", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
