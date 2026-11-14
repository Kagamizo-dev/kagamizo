"""Renders one research paper (modules/research/papers.nix) from its
public facts, standard library only.

  python3 -I _paper.py public.json paper.md

The input is {"strategy": ..., "facts": [{"field", "value"}, ...]}: the
public facts and nothing else (Lean proves the filter, _lean/Papers.lean),
so whatever this script prints was declared public. The output is Pandoc
Markdown with a YAML header; papers.nix turns it into Typst and PDF, and
into HTML. Each declared section is the team's prose (prose.<section>)
followed by the generated part for that section: the data sources, the
signal model as the engine describes itself, the algorithm and the
strategy's parameters, the Lean theorems with their docstrings and
statements, the backtest record, the limits.
"""

import json
import re
import sys

TITLES = {
    "motivation": "Motivation",
    "data": "Data",
    "model": "Model",
    "algorithm": "Algorithm",
    "proofs": "Proofs",
    "backtest": "Backtest",
    "limits": "Limits",
    "risks": "Risks",
}

LIMITS = (
    ("seedUsd", "Seed", "What the account is funded with; nothing above it is ever at risk."),
    ("maxPremiumUsd", "Trade cap", "The most one trade may cost, and so lose."),
    ("maxContractPriceUsd", "Event-contract cap", "The most one event-contract order may cost (price × quantity)."),
    ("maxOpenPositions", "Open positions", "How many positions may be open at once."),
    ("dailyLossStopUsd", "Daily stop", "Once the day has lost this much, nothing more is proposed."),
    ("dailyTakeProfitUsd", "Daily take-profit", "Once the day has gained this much, nothing more is proposed."),
    ("allowed", "Allowed kinds", "Defined-risk kinds only: each has a known worst case at entry."),
)

STRATEGY = (
    ("strategy.kind", "Kind"),
    ("strategy.symbol", "Instrument"),
    ("strategy.bar", "Bar"),
    ("strategy.backend", "Venue"),
    ("backend.adapter", "Adapter"),
    ("strategy.startingUsd", "Simulated balance (backtests)"),
    ("strategy.event.category", "Event category"),
    ("strategy.event.subcategory", "Event subcategory"),
    ("strategy.event.questions", "Question shapes traded"),
    ("strategy.event.minEdge", "Minimum edge"),
    ("strategy.event.maxContracts", "Most contracts per proposal"),
    ("strategy.event.source", "Forecast source"),
    ("strategy.option.expiryDaysMin", "Expiry, at least (days)"),
    ("strategy.option.expiryDaysMax", "Expiry, at most (days)"),
    ("strategy.option.minAbsDelta", "Minimum |delta|"),
    ("strategy.params.tradeSize", "Trade size"),
    ("strategy.params.fastPeriod", "Fast period"),
    ("strategy.params.slowPeriod", "Slow period"),
)

RESEARCH = (
    ("research.deepModel", "Managers' model (deep)"),
    ("research.quickModel", "Analysts', researchers' and trader's model (quick)"),
    ("research.debateRounds", "Bull/bear debate rounds"),
    ("research.riskRounds", "Risk discussion rounds"),
    ("research.maxTokens", "Output cap per call (tokens)"),
    ("research.dataVendors", "Data vendors by category"),
)

BACKTEST = (
    ("recorded", "Recorded"),
    ("from", "From"),
    ("to", "To"),
    ("benchmark", "Benchmark"),
    ("alpha", "Annualised alpha"),
    ("maxDrawdownPct", "Maximum drawdown (%)"),
    ("hitRate", "Hit rate"),
    ("trades", "Trades"),
    ("grid", "Grid"),
)

# `/-- doc -/ theorem name statement :=`: the docstring may not cross a
# `-/`, the statement runs to the first `:=`.
THEOREM = re.compile(r"/--\s*((?:(?!-/).)*?)\s*-/\s*(theorem|example)\s+((?:(?!:=).)*?)\s*:=", re.S)


def cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    out += ["| " + " | ".join(cell(c) for c in r) + " |" for r in rows]
    return "\n".join(out) + "\n"


def pretty(value):
    """A JSON list as a comma list, a JSON object as key: value lines, else as is."""
    try:
        v = json.loads(value)
    except (ValueError, TypeError):
        return value
    if isinstance(v, list):
        return ", ".join(str(x) for x in v)
    if isinstance(v, dict):
        return "; ".join(f"{k}: {pretty(json.dumps(x))}" for k, x in v.items())
    return str(v)


def theorems(text):
    for doc, kw, stmt in THEOREM.findall(text):
        doc = " ".join(line.strip() for line in doc.splitlines())
        name = stmt.split()[0] if kw == "theorem" else "(example)"
        yield name, doc, f"{kw} {stmt}"


class Paper:
    def __init__(self, facts):
        self.f = {x["field"]: x["value"] for x in facts}

    def get(self, field, default=None):
        return self.f.get(field, default)

    def lean_files(self):
        return sorted((k[len("lean."):], v) for k, v in self.f.items() if k.startswith("lean."))

    def header(self):
        authors = [a.strip() for a in self.get("paper.authors", "").split(",") if a.strip()]
        meta = {
            "title": self.get("paper.title"),
            "author": [f"{a} (an agent team)" for a in authors],
            "abstract": self.get("paper.abstract"),
            "subtitle": f"Strategy {self.get('paper.strategy')}, at the {self.get('paper.stage')} stage",
        }
        return "---\n" + json.dumps(meta, indent=2, ensure_ascii=False) + "\n---\n\n"

    def generated(self, kind):
        return getattr(self, f"gen_{kind}")()

    def gen_motivation(self):
        return ""

    def gen_data(self):
        sources = sorted((k[len("data.source."):], v) for k, v in self.f.items() if k.startswith("data.source."))
        out = "### Sources\n\nEach source is a public API read over HTTPS; the hosts are the ones the engine reads from.\n\n"
        out += table(["Source", "Hosts"], [(s, h.replace(" ", ", ")) for s, h in sources])
        return out

    def gen_model(self):
        out = ""
        if "signal.doc" in self.f:
            out += "### The rules, as the engine states them\n\nThe signal engine is a deterministic script, standard library only; its module docstring is the specification, reproduced verbatim:\n\n"
            out += "```text\n" + self.get("signal.doc").strip() + "\n```\n\n"
            out += "### Constants\n\n"
            out += table(
                ["Constant", "Definition"],
                [
                    ("σ of a daily-high forecast by lead (°F)", f"`sigma_f(lead_days) = {self.get('signal.sigmaF')}`"),
                    ("σ of a forecast day's precipitation (inches)", f"`forecast_precip_sd(amount) = {self.get('signal.precipSd')}`"),
                    ("Question shapes handled", self.get("signal.questions", "").replace('"', "")),
                    ("Cities known", self.get("signal.cities", "")),
                ],
            )
        if "research.deepModel" in self.f:
            out += "### The research loop\n\nTradingAgents (TauricResearch, Apache-2.0, pinned at a release) on an OpenAI-compatible endpoint, with the declared open-weight models:\n\n"
            out += table(["Setting", "Value"], [(label, pretty(self.get(k))) for k, label in RESEARCH if k in self.f])
        return out

    def gen_algorithm(self):
        out = "### The proposal, as the engine states it\n\nThe proposal script's module docstring, reproduced verbatim:\n\n"
        out += "```text\n" + self.get("algorithm.doc", "").strip() + "\n```\n\n"
        out += "### Declared parameters\n\n"
        out += table(["Parameter", "Value"], [(label, pretty(self.get(k))) for k, label in STRATEGY if k in self.f])
        return out

    def gen_proofs(self):
        out = ""
        for name, text in self.lean_files():
            head = re.match(r"\s*/-\s*(.*?)\s*-/", text, re.S)
            out += f"### {name}.lean\n\n"
            if head:
                out += " ".join(line.strip() for line in head.group(1).splitlines()) + "\n\n"
            for thm, doc, stmt in theorems(text):
                out += f"**{thm}.** {doc}\n\n```lean\n{stmt}\n```\n\n"
        return out

    def gen_backtest(self):
        if self.get("backtest.status") != "recorded":
            return "*No backtest recorded yet.* The strategy stays at the research stage until one is recorded with positive alpha and a drawdown within the threshold; this section then shows the record.\n"
        rows = [(label, pretty(self.get(f"backtest.{k}"))) for k, label in BACKTEST if f"backtest.{k}" in self.f]
        return "### The latest record\n\n" + table(["Field", "Value"], rows)

    def gen_limits(self):
        rows = [(label, pretty(self.get(f"limits.{k}")), why) for k, label, why in LIMITS if f"limits.{k}" in self.f]
        out = "### The declared limits\n\nEvery proposal is held to `admissible` (Risk.lean) over these values before the venue's preflight, and again before anything is placed. Amounts are US dollars.\n\n"
        out += table(["Limit", "Value", "Meaning"], rows)
        return out

    def gen_risks(self):
        stage = self.get("paper.stage")
        evidence = (
            f"backtest recorded: {self.get('promotion.backtested')}; paper days: {self.get('promotion.paperDays')}; "
            f"the owner's decision to go live: {self.get('promotion.decided')}"
        )
        return f"### Stage\n\nThe strategy is at the **{stage}** stage ({evidence}). Stages.lean proves nothing reaches live without every piece of evidence.\n"

    def render(self):
        out = self.header()
        for kind in [s.strip() for s in self.get("paper.sections", "").split(",") if s.strip()]:
            out += f"# {TITLES[kind]}\n\n"
            out += self.get(f"prose.{kind}", "").strip() + "\n\n"
            gen = self.generated(kind)
            if gen:
                out += gen + "\n"
        return out


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1]) as f:
        public = json.load(f)
    with open(sys.argv[2], "w") as f:
        f.write(Paper(public["facts"]).render())


if __name__ == "__main__":
    main()
