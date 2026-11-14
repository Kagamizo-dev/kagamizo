"""`trade`: NautilusTrader from the command line, driven by declared strategies.

  trade backtest STRATEGY BARS.csv   run a declared strategy over bars and
                                     print the result as JSON
  trade strategies                   the declared strategies, as JSON
  trade account                      the one BROKERAGE account's id
  trade bars SYMBOL STEP [PERIOD]    Public's bars as BARS.csv (STEP like
                                     1-DAY; PERIOD as Public names it)
  trade paper STRATEGY [BARS.csv] [--all]
                                     run the strategy over Public's latest
                                     bars (or BARS.csv) on the simulated
                                     venue, and preflight at Public the
                                     orders of its last bar (--all: every
                                     order), which places nothing
  trade propose STRATEGY [DATE] [--forecasts FILE]
                                     an agent-option strategy: the day's
                                     research decision into one option order
                                     within the limits, preflighted; an
                                     event-rule strategy: Public's open event
                                     contracts in its category, each question
                                     the weather rules answer (_weather.py)
                                     priced against its forecast, the best
                                     edge into one order within the limits,
                                     preflighted; the proposal as JSON
                                     (nothing placed). --forecasts reads the
                                     typed forecasts file instead of fetching
                                     the declared source (paper runs, checks)
  trade paper-day STRATEGY [DATE] [--forecasts FILE]
                                     propose, and record the day as paper
                                     evidence under <decisions>/paper/
  trade place PROPOSAL.json          the one spend: the risk check and the
                                     preflight again, then the order, then
                                     its status; the controller's only

BARS.csv has a header and one bar per row: timestamp (ISO 8601, UTC), open,
high, low, close, volume. Strategies come from TRADE_STRATEGIES (JSON, made
by modules/trading/strategies.nix): each names its kind, instrument, venue,
bar step and parameters. Backtests touch no account: they run on a
simulated venue with a simulated balance. `bars` and `paper` read Public
(./_public.py) and never place an order; the wrapper authorizes them.
"""

import csv
import json
import os
import sys
from decimal import Decimal

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _propose  # noqa: E402
import _public  # noqa: E402
import _weather  # noqa: E402

from nautilus_trader.backtest.engine import BacktestEngine, BacktestEngineConfig
from nautilus_trader.config import LoggingConfig
from nautilus_trader.model.currencies import USD
from nautilus_trader.model.data import Bar, BarType
from nautilus_trader.model.enums import (
    AccountType,
    OmsType,
    order_side_to_str,
    order_status_to_str,
    order_type_to_str,
    time_in_force_to_str,
)
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


COLUMNS = ["timestamp", "open", "high", "low", "close", "volume"]


def read_bars(path):
    with open(path, newline="") as f:
        return bars_frame(list(csv.DictReader(f)), path)


def bars_frame(rows, source):
    if not rows:
        die(f"{source}: no bars")
    missing = set(COLUMNS) - set(rows[0])
    if missing:
        die(f"{source}: missing columns {', '.join(sorted(missing))}")
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


def declared(name):
    return strategies().get(name) or die(f"no strategy {name}; declared: {', '.join(strategies())}", 2)


def run(name, bars):
    """The strategy over a frame of bars on the simulated venue: (engine, result)."""
    decl = declared(name)
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
    engine.add_data(BarDataWrangler(bar_type, instrument).process(bars))
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
    return engine, result


def emit(result):
    json.dump(result, sys.stdout, indent=2)
    print()


def backtest(name, bars_path):
    engine, result = run(name, read_bars(bars_path))
    engine.dispose()
    emit(result)


def bars_csv(symbol, step, period=None):
    try:
        rows = _public.Public().bars(symbol, step, period)
    except (_public.PublicError, RuntimeError) as e:
        die(f"{e} {getattr(e, 'body', '')}".strip())
    out = csv.DictWriter(sys.stdout, fieldnames=COLUMNS)
    out.writeheader()
    out.writerows(rows)


def public_order(order, symbol):
    """A simulated order as Public's order body (see _public.order_body)."""
    return _public.order_body(
        symbol,
        order_side_to_str(order.side),
        order_type_to_str(order.order_type),
        order.quantity,
        time_in_force_to_str(order.time_in_force),
        limit_price=order.price if order.has_price else None,
        stop_price=order.trigger_price if order.has_trigger_price else None,
        expire_time=getattr(order, "expire_time", None) and order.expire_time.isoformat(),
    )


def paper(name, bars_path=None, every=False):
    """One step of paper trading on Public.

    The strategy runs over the bars on the simulated venue, which fills its
    orders; then the orders it submitted on the last bar (what it would do
    now), or with --all every order, go to Public's preflight against the
    live account. Orders the simulated venue denied or rejected are left
    out. Preflight places nothing: it prices the order and says
    whether Public would take it. Run once per bar to paper-trade.
    """
    decl = declared(name)
    api = _public.Public()
    if bars_path:
        bars = read_bars(bars_path)
    else:
        try:
            bars = bars_frame(api.bars(decl["symbol"], decl["bar"]), f"Public {decl['symbol']} {decl['bar']}")
        except (_public.PublicError, RuntimeError) as e:
            die(f"{e} {getattr(e, 'body', '')}".strip())
    engine, result = run(name, bars)
    last = int(bars.index[-1].value)
    checked = []
    for order in sorted(engine.cache.orders(), key=lambda o: o.ts_init):
        # The simulated venue's own refusals never reach Public.
        status = order_status_to_str(order.status)
        if status in ("DENIED", "REJECTED") or (not every and order.ts_init < last):
            continue
        entry = {
            "order": str(order.client_order_id),
            "simulated": status,
            "side": order_side_to_str(order.side),
            "type": order_type_to_str(order.order_type),
            "quantity": str(order.quantity),
        }
        try:
            entry["preflight"] = api.preflight(public_order(order, decl["symbol"]))
            entry["accepted"] = True
        except ValueError as e:
            entry.update(accepted=False, refused_by="mapping", reason=str(e))
        except _public.PublicError as e:
            entry.update(accepted=False, refused_by="public", status=e.status, reason=e.body)
        checked.append(entry)
    engine.dispose()
    result["as_of"] = bars.index[-1].isoformat()
    result["preflight"] = checked
    emit(result)


def limits_for(decl):
    try:
        limits = json.loads(os.environ["TRADE_LIMITS"])
    except (KeyError, json.JSONDecodeError):
        die("TRADE_LIMITS is not set; run trade through its wrapper", 2)
    return limits.get(decl["backend"]) or die(f"no trading.limits.{decl['backend']}", 2)


def day_state(decl):
    """Where the day stands: <decisions>/state.json, written by `place` and
    the day's close ({"openPositions", "lossUsd", "gainUsd"}, the shape of
    Kagamizo.Risk.Day); zeros when there is none yet."""
    path = os.path.join(decl["decisions"], "state.json")
    day = {"openPositions": 0, "lossUsd": 0, "gainUsd": 0}
    if os.path.exists(path):
        with open(path) as f:
            day.update(json.load(f))
    return day


def decision_for(decl, date):
    path = os.path.join(decl["decisions"], date, f"{decl['symbol']}.json")
    if not os.path.exists(path):
        die(f"no research decision at {path}")
    with open(path) as f:
        return json.load(f)


def forecasts_for(decl, today, path=None):
    """The event-rule strategy's data: the typed file when given, else the
    declared source, fetched live for the cities the rules know."""
    if path:
        try:
            return _weather.load_data(path)
        except (OSError, ValueError) as e:
            die(str(e))
    try:
        return _weather.live_data(list(_weather.CITIES), today, decl["event"]["source"])
    except (OSError, RuntimeError, ValueError) as e:
        die(f"fetching forecasts from {decl['event']['source']}: {e}")


def propose(name, date=None, record=False, forecasts=None):
    decl = declared(name)
    import datetime

    today = datetime.date.fromisoformat(date) if date else datetime.date.today()
    if decl["kind"] == "agent-option":
        if forecasts:
            die(f"{name} is agent-option; --forecasts is for an event-rule strategy")
        out = _propose.propose(decl, limits_for(decl), decision_for(decl, today.isoformat()), day_state(decl), _public.Public(), today)
        record_as = decl["symbol"]
    elif decl["kind"] == "event-rule":
        out = _propose.propose_event(decl, limits_for(decl), forecasts_for(decl, today, forecasts), day_state(decl), _public.Public(), today)
        record_as = name
    else:
        die(f"{name} is {decl['kind']}, which proposes nothing (agent-option and event-rule do)")
    if record:
        folder = os.path.join(decl["decisions"], "paper")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, f"{today.isoformat()}-{record_as}.json"), "w") as f:
            json.dump(out, f, indent=2)
        out["recorded"] = True
    emit(out)


def place(proposal_path):
    """The spend. The proposal is checked again against the limits and the
    day, preflighted again, placed, then read back until it is no longer
    NEW. The day's state records the open position."""
    with open(proposal_path) as f:
        proposal = json.load(f)
    name = proposal["strategy"]
    decl = declared(name)
    # The stage is the declaration's (modules/trading/stages.nix, proved by
    # Lean to carry its evidence): only a live strategy places.
    if decl.get("stage") != "live":
        die(f"{name} is at stage {decl.get('stage')}, not live: nothing is placed")
    p = proposal.get("proposal") or die("the proposal holds no order")
    limits = limits_for(decl)
    day = day_state(decl)
    ok, why = _propose.admissible(limits, day, p["kind"], p["max_loss_usd"])
    if not ok:
        die("refused: " + "; ".join(why))
    api = _public.Public()
    order = p["order"]
    try:
        preflight = api.preflight(order)
    except _public.PublicError as e:
        die(f"Public refused the preflight: {e} {e.body}")
    try:
        placed = api.place(order)
    except _public.PublicError as e:
        die(f"Public refused the order: {e} {e.body}")
    order_id = placed.get("orderId") or order.get("orderId")
    import time

    status = None
    for _ in range(20):
        status = api.order(order_id)
        if status.get("status") not in (None, "NEW", "PENDING"):
            break
        time.sleep(3)
    day["openPositions"] = day.get("openPositions", 0) + 1
    os.makedirs(decl["decisions"], exist_ok=True)
    with open(os.path.join(decl["decisions"], "state.json"), "w") as f:
        json.dump(day, f, indent=2)
    emit({"strategy": name, "order_id": order_id, "preflight": preflight, "placed": placed, "status": status, "day": day})


USAGE = (
    "usage: trade <backtest STRATEGY BARS.csv | strategies | bars SYMBOL STEP [PERIOD]"
    " | paper STRATEGY [BARS.csv] [--all] | propose STRATEGY [DATE] [--forecasts FILE]"
    " | paper-day STRATEGY [DATE] [--forecasts FILE] | place PROPOSAL.json>"
)


def propose_args(argv):
    """STRATEGY [DATE] [--forecasts FILE] -> (strategy, date, forecasts)."""
    rest, forecasts = [], None
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--forecasts":
            if not args or forecasts:
                die(USAGE, 2)
            forecasts = args.pop(0)
        else:
            rest.append(a)
    if not 1 <= len(rest) <= 2:
        die(USAGE, 2)
    return rest[0], (rest[1] if len(rest) == 2 else None), forecasts


def main(argv):
    if not argv:
        die(USAGE, 2)
    if argv[0] == "strategies":
        emit(strategies())
    elif argv[0] == "backtest" and len(argv) == 3:
        backtest(argv[1], argv[2])
    elif argv[0] == "account" and len(argv) == 1:
        # The brokerage account's id (an identifier, not a secret): piped
        # into its vault item once, so Public's CLI knows which account.
        try:
            print(_public.Public().account())
        except (_public.PublicError, RuntimeError) as e:
            die(f"{e} {getattr(e, 'body', '')}".strip())
    elif argv[0] == "bars" and len(argv) in (3, 4):
        bars_csv(*argv[1:])
    elif argv[0] == "paper" and 2 <= len(argv) <= 4:
        every = "--all" in argv[2:]
        rest = [a for a in argv[2:] if a != "--all"]
        if len(rest) > 1:
            die(USAGE, 2)
        paper(argv[1], rest[0] if rest else None, every)
    elif argv[0] in ("propose", "paper-day") and len(argv) >= 2:
        name, date, forecasts = propose_args(argv[1:])
        propose(name, date, record=argv[0] == "paper-day", forecasts=forecasts)
    elif argv[0] == "place" and len(argv) == 2:
        place(argv[1])
    else:
        die(USAGE, 2)


if __name__ == "__main__":
    main(sys.argv[1:])
