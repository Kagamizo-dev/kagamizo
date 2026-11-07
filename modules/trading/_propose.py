"""Proposals within the declared limits (modules/trading/limits.nix; the
rule is _lean/Risk.lean's `admissible`), then Public's preflight. Nothing
here places an order: `trade place` does, after running this again.

The agent-option strategy (`propose`):
  decision     research/<date>/<ticker>.json: {"decision": "BUY"|"SELL"|"HOLD",
               "rationale": ..., "as_of": ...}; BUY means a call, SELL a put,
               HOLD no trade
  contract     the nearest expiration expiryDaysMin..expiryDaysMax out; among
               its calls (or puts) with ask × 100 ≤ maxPremiumUsd and
               |delta| ≥ minAbsDelta, the cheapest ask (the plan of 2026-11-02)

The event-rule strategy (`propose_event`, the owner's framing of 2026-11-04):
  contracts    every open outcome of every unresolved event Public lists in
               the declared category (and subcategory), with its YES and NO
               contracts and asks
  question     each outcome's question parsed by _weather.py; shapes not
               declared in the strategy, or not understood, are skipped
  edge         the rule's probability of the side minus its ask; the best
               edge at or above minEdge is proposed, as a BUY of whole
               contracts: as many as maxContracts, maxContractPriceUsd and
               the premium cap allow

Both:
  risk         admissible(limits, day, order): the kind allowed, the worst
               case within the cap, the book below its limit, the day below
               its stop and below its take-profit
  proposal     the order body (LIMIT, DAY), its worst case, the preflight,
               and why: proposal.json
"""

import datetime
import math
import uuid

import _public
import _weather

KINDS = {"BUY": ("C", "long-call"), "SELL": ("P", "long-put")}
EVENT_KINDS = {"YES": "event-yes", "NO": "event-no"}


def admissible(limits, day, kind, max_loss_usd):
    """Mirrors Kagamizo.Risk.admissible; the reasons are for the owner."""
    why = []
    if kind not in limits["allowed"]:
        why.append(f"{kind} is not an allowed kind ({', '.join(limits['allowed'])})")
    if max_loss_usd > limits["maxPremiumUsd"]:
        why.append(f"worst case ${max_loss_usd:.2f} is over the ${limits['maxPremiumUsd']} cap")
    if day["openPositions"] >= limits["maxOpenPositions"]:
        why.append(f"{day['openPositions']} position(s) open; the limit is {limits['maxOpenPositions']}")
    if day["lossUsd"] >= limits["dailyLossStopUsd"]:
        why.append(f"the day has lost ${day['lossUsd']:.2f}; the stop is ${limits['dailyLossStopUsd']}")
    if day.get("gainUsd", 0) >= limits["dailyTakeProfitUsd"]:
        why.append(f"the day has gained ${day.get('gainUsd', 0):.2f}; the take-profit is ${limits['dailyTakeProfitUsd']}")
    return (not why), why


def preflighted(proposal, api):
    """The proposal with Public's answer, when it is admissible."""
    if proposal["admissible"]:
        try:
            proposal["preflight"] = api.preflight(proposal["order"])
            proposal["accepted"] = True
        except _public.PublicError as e:
            proposal.update(accepted=False, refused_by="public", status=e.status, reason=e.body)
    return proposal


def pick_expiration(expirations, today, lo, hi):
    for e in sorted(expirations):
        days = (datetime.date.fromisoformat(e) - today).days
        if lo <= days <= hi:
            return e, days
    return None, None


def contracts(chain, api, side_kind):
    """Each call (or put) with its ask, strike and delta, greeks fetched when
    the chain carries none."""
    quotes = chain["calls" if side_kind == "C" else "puts"]
    missing = [q["instrument"]["symbol"] for q in quotes if not (q.get("optionDetails") or {}).get("greeks")]
    fetched = api.greeks(missing) if missing else {}
    out = []
    for q in quotes:
        sym = q["instrument"]["symbol"]
        details = q.get("optionDetails") or {}
        greeks = details.get("greeks") or fetched.get(sym) or {}
        ask = q.get("ask")
        if ask in (None, "") or greeks.get("delta") is None:
            continue
        out.append(
            {
                "symbol": sym,
                "strike": float(details.get("strikePrice") or 0),
                "ask": float(ask),
                "bid": float(q.get("bid") or 0),
                "delta": float(greeks["delta"]),
            }
        )
    return out


def propose(decl, limits, decision, day, api, today=None, quantity=1):
    today = today or datetime.date.today()
    params = decl["option"]
    out = {
        "strategy": decl["name"],
        "symbol": decl["symbol"],
        "as_of": today.isoformat(),
        "decision": decision.get("decision"),
        "rationale": decision.get("rationale"),
        "limits": limits,
        "day": day,
        "proposal": None,
    }
    if decision.get("decision") not in KINDS:
        out["why"] = f"decision {decision.get('decision')}: no trade"
        return out
    side_kind, kind = KINDS[decision["decision"]]
    expiration, days = pick_expiration(api.option_expirations(decl["symbol"]), today, params["expiryDaysMin"], params["expiryDaysMax"])
    if expiration is None:
        out["why"] = f"no expiration {params['expiryDaysMin']}..{params['expiryDaysMax']} days out"
        return out
    chain = api.option_chain(decl["symbol"], expiration)
    fitting = [
        c
        for c in contracts(chain, api, side_kind)
        if c["ask"] * 100 * quantity <= limits["maxPremiumUsd"] and abs(c["delta"]) >= params["minAbsDelta"]
    ]
    if not fitting:
        out["why"] = f"no {('call', 'put')[side_kind == 'P']} expiring {expiration} fits: ask × 100 ≤ ${limits['maxPremiumUsd']} and |delta| ≥ {params['minAbsDelta']}"
        return out
    pick = min(fitting, key=lambda c: (c["ask"], -abs(c["delta"])))
    max_loss = round(pick["ask"] * 100 * quantity, 2)
    ok, why = admissible(limits, day, kind, max_loss)
    order = _public.option_order_body(pick["symbol"], "BUY", pick["ask"], quantity, "OPEN", order_id=str(uuid.uuid4()))
    out["proposal"] = preflighted(
        {
            "kind": kind,
            "contract": pick,
            "expiration": expiration,
            "days_out": days,
            "quantity": quantity,
            "max_loss_usd": max_loss,
            "admissible": ok,
            "refused_because": why,
            "order": order,
        },
        api,
    )
    return out


def _ask(contract):
    ask = contract.get("ask")
    if ask in (None, ""):
        return None
    ask = float(ask)
    return ask if 0.0 < ask < 1.0 else None


def event_candidates(decl, data, api, today):
    """Every open contract in the declared category with a question the
    engine answers, its probability, price and edge; and what was skipped."""
    params = decl["event"]
    considered, skipped = [], []
    for ev in api.event_contracts(category=params["category"], subcategory=params["subcategory"], include_resolved=False):
        if ev.get("resolved") or ev.get("halted"):
            skipped.append({"event": ev["eventSymbol"], "why": "resolved or halted"})
            continue
        details = api.event_contract_details(ev["eventSymbol"])
        for oc in details.get("outcomes") or []:
            where = {"event": ev["eventSymbol"], "outcome": oc["outcomeId"], "title": f"{details['title']} / {oc['title']}"}
            if oc.get("state") != "STATE_OPEN" or oc.get("trading") != "BUY_AND_SELL":
                skipped.append({**where, "why": f"{oc.get('state')}, trading {oc.get('trading')}"})
                continue
            close = (oc.get("timeline") or {}).get("closeTime") or ev.get("resolutionTime")
            q = _weather.parse_question(details["title"], oc["title"], today, close)
            if q is None:
                skipped.append({**where, "why": "a question shape the rules do not handle"})
                continue
            if q.shape not in params["questions"]:
                skipped.append({**where, "why": f"{q.shape} is not a declared question shape"})
                continue
            p = _weather.probability(q, data, today)
            if p is None:
                skipped.append({**where, "why": f"no data for {q.city} over {q.start}..{q.end}"})
                continue
            for c in oc.get("contracts") or []:
                ask = _ask(c)
                if ask is None or c.get("predictedOutcome") not in EVENT_KINDS:
                    skipped.append({**where, "contract": c.get("symbol"), "why": "no ask between 0 and 1"})
                    continue
                side_p = p if c["predictedOutcome"] == "YES" else 1.0 - p
                considered.append(
                    {
                        **where,
                        "contract": c["symbol"],
                        "side": c["predictedOutcome"],
                        "question": q.as_dict(),
                        "probability": round(side_p, 4),
                        "ask": ask,
                        "edge": _weather.edge(side_p, ask),
                    }
                )
    return considered, skipped


def propose_event(decl, limits, data, day, api, today=None):
    today = today or datetime.date.today()
    params = decl["event"]
    out = {
        "strategy": decl["name"],
        "as_of": today.isoformat(),
        "category": params["category"],
        "subcategory": params["subcategory"],
        "data_as_of": data.get("as_of"),
        "data_source": data.get("source"),
        "limits": limits,
        "day": day,
        "proposal": None,
    }
    considered, skipped = event_candidates(decl, data, api, today)
    out["considered"] = sorted(considered, key=lambda c: -c["edge"])
    out["skipped"] = skipped
    fitting = [c for c in considered if c["edge"] >= params["minEdge"]]
    if not fitting:
        out["why"] = f"no contract with edge ≥ {params['minEdge']} among {len(considered)} considered"
        return out
    pick = max(fitting, key=lambda c: (c["edge"], -c["ask"]))
    quantity = min(params["maxContracts"], math.floor(limits["maxContractPriceUsd"] / pick["ask"]), math.floor(limits["maxPremiumUsd"] / pick["ask"]))
    if quantity < 1:
        out["why"] = f"{pick['contract']} at ${pick['ask']:.2f} does not fit one contract within ${limits['maxContractPriceUsd']}"
        return out
    cost = round(pick["ask"] * quantity, 2)
    kind = EVENT_KINDS[pick["side"]]
    ok, why = admissible(limits, day, kind, cost)
    order = _public.event_contract_order_body(pick["contract"], "BUY", pick["ask"], quantity, order_id=str(uuid.uuid4()))
    out["proposal"] = preflighted(
        {
            "kind": kind,
            "contract": pick,
            "quantity": quantity,
            "max_loss_usd": cost,
            "admissible": ok,
            "refused_because": why,
            "order": order,
        },
        api,
    )
    return out
