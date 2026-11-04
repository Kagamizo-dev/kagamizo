"""`research`: TradingAgents (pinned, modules/research) on OpenRouter, from
the declarations, into the decision files `trade propose` reads.

  research run TICKER DATE [--out DIR]     one decision: DIR/DATE/TICKER.json
  research sweep TICKERS FROM TO [--out DIR] [--jobs N]
                                           every ticker on every trading day
                                           in the range, each its own process
  research backtest TICKERS FROM TO        TradingAgents' own run_backtest over
                                           the grid: alpha and drawdown as JSON

The configuration comes from RESEARCH_CONFIG (JSON, made by Nix): the
OpenRouter endpoint and the deep and quick models from the declared
open-weight list, the debate rounds, the data vendors. The key is
OPENROUTER_API_KEY (secretspec profile `research`), handed to the OpenAI-
compatible client as OPENAI_API_KEY. A decision file holds the signal
(BUY, SELL or HOLD), the final decision text, every analyst's report and
the debate, so the proposal that follows can show its reasons.
"""

import datetime
import json
import os
import subprocess
import sys


def die(msg, code=1):
    print(f"research: {msg}", file=sys.stderr)
    sys.exit(code)


def config():
    try:
        made = json.loads(os.environ["RESEARCH_CONFIG"])
    except (KeyError, json.JSONDecodeError):
        die("RESEARCH_CONFIG is not set; run research through its wrapper", 2)
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        die("OPENROUTER_API_KEY is not set; run research through its wrapper (profile research)", 2)
    os.environ["OPENAI_API_KEY"] = key
    from tradingagents.default_config import DEFAULT_CONFIG

    cfg = DEFAULT_CONFIG.copy()
    cfg.update(
        {
            "llm_provider": "openai",
            "backend_url": made["backendUrl"],
            "deep_think_llm": made["deepModel"],
            "quick_think_llm": made["quickModel"],
            "max_debate_rounds": made["debateRounds"],
            "max_risk_discuss_rounds": made["riskRounds"],
            "max_tokens": made["maxTokens"],
            "results_dir": os.path.join(made["home"], "logs"),
            "data_cache_dir": os.path.join(made["home"], "cache"),
            "memory_log_path": os.path.join(made["home"], "memory", "trading_memory.md"),
            "data_vendors": made["dataVendors"],
        }
    )
    return cfg


def signal_of(decision_text):
    """The signal in the final decision: BUY, SELL or HOLD, the last one named."""
    found = None
    for word in ("BUY", "SELL", "HOLD"):
        i = str(decision_text).upper().rfind(word)
        if i >= 0 and (found is None or i > found[1]):
            found = (word, i)
    return found[0] if found else "HOLD"


def run(ticker, date, out_dir):
    from tradingagents.graph.trading_graph import TradingAgentsGraph

    cfg = config()
    graph = TradingAgentsGraph(debug=False, config=cfg)
    state, decision = graph.propagate(ticker, date)
    signal = graph.process_signal(decision) if hasattr(graph, "process_signal") else signal_of(decision)
    if signal not in ("BUY", "SELL", "HOLD"):
        signal = signal_of(signal)
    record = {
        "ticker": ticker,
        "as_of": date,
        "decision": signal,
        "rationale": decision,
        "models": {"deep": cfg["deep_think_llm"], "quick": cfg["quick_think_llm"]},
        "reports": {
            k: state.get(k)
            for k in ("market_report", "sentiment_report", "news_report", "fundamentals_report")
            if state.get(k)
        },
        "debate": {
            "investment": (state.get("investment_debate_state") or {}).get("judge_decision"),
            "risk": (state.get("risk_debate_state") or {}).get("judge_decision"),
        },
        "made": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    }
    folder = os.path.join(out_dir, date)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{ticker.upper()}.json")
    with open(path, "w") as f:
        json.dump(record, f, indent=2, default=str)
    print(json.dumps({"ticker": ticker, "as_of": date, "decision": signal, "path": path}))


def trading_days(start, end):
    d = datetime.date.fromisoformat(start)
    stop = datetime.date.fromisoformat(end)
    while d <= stop:
        if d.weekday() < 5:
            yield d.isoformat()
        d += datetime.timedelta(days=1)


def sweep(tickers, start, end, out_dir, jobs):
    """Each ticker-day its own process, `jobs` at a time, all on the one
    capped key: a cell that fails fails alone."""
    cells = [(t, d) for d in trading_days(start, end) for t in tickers]
    running, results = [], []
    for cell in cells:
        if os.path.exists(os.path.join(out_dir, cell[1], f"{cell[0].upper()}.json")):
            results.append({"ticker": cell[0], "as_of": cell[1], "skipped": "exists"})
            continue
        running.append((cell, subprocess.Popen([sys.executable, "-I", sys.argv[0], "run", cell[0], cell[1], "--out", out_dir])))
        while len(running) >= jobs:
            (c, p), running = running[0], running[1:]
            results.append({"ticker": c[0], "as_of": c[1], "exit": p.wait()})
    for c, p in running:
        results.append({"ticker": c[0], "as_of": c[1], "exit": p.wait()})
    print(json.dumps(results, indent=2))


def backtest(tickers, start, end):
    from tradingagents.backtest import run_backtest, summarize

    cfg = config()
    result = run_backtest(tickers, list(trading_days(start, end)), cfg)
    summary = summarize(result) if callable(summarize) else result
    print(json.dumps(summary, indent=2, default=str))


USAGE = "usage: research <run TICKER DATE [--out DIR] | sweep T1,T2 FROM TO [--out DIR] [--jobs N] | backtest T1,T2 FROM TO>"


def main(argv):
    out_dir, jobs, rest = "research", 2, []
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_dir = next(it, out_dir)
        elif a == "--jobs":
            jobs = int(next(it, jobs))
        else:
            rest.append(a)
    if len(rest) == 3 and rest[0] == "run":
        run(rest[1], rest[2], out_dir)
    elif len(rest) == 4 and rest[0] == "sweep":
        sweep(rest[1].split(","), rest[2], rest[3], out_dir, jobs)
    elif len(rest) == 4 and rest[0] == "backtest":
        backtest(rest[1].split(","), rest[2], rest[3])
    else:
        die(USAGE, 2)


if __name__ == "__main__":
    main(sys.argv[1:])
