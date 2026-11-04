"""The agent-option strategy: the day's research decision into one
defined-risk option order within the declared limits (modules/trading/
limits.nix; the rule is _lean/Risk.lean's `admissible`), then Public's
preflight. Nothing here places an order: `trade place` does, after running
this again.

  decision     research/<date>/<ticker>.json: {"decision": "BUY"|"SELL"|"HOLD",
               "rationale": ..., "as_of": ...}; BUY means a call, SELL a put,
               HOLD no trade
  contract     the nearest expiration expiryDaysMin..expiryDaysMax out; among
               its calls (or puts) with ask × 100 ≤ maxPremiumUsd and
               |delta| ≥ minAbsDelta, the cheapest ask (the plan of 2026-11-02)
  risk         admissible(limits, day, order): the kind allowed, the premium
               within the cap, the book below its limit, the day below its stop
  proposal     the order body (LIMIT at the ask, DAY, OPEN), its worst case,
               the preflight, and why: proposal.json
"""

import datetime
import json
import uuid

import _public

KINDS = {"BUY": ("C", "long-call"), "SELL": ("P", "long-put")}


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
    return (not why), why


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
    out["proposal"] = {
        "kind": kind,
        "contract": pick,
        "expiration": expiration,
        "days_out": days,
        "quantity": quantity,
        "max_loss_usd": max_loss,
        "admissible": ok,
        "refused_because": why,
        "order": order,
    }
    if ok:
        try:
            out["proposal"]["preflight"] = api.preflight(order)
            out["proposal"]["accepted"] = True
        except _public.PublicError as e:
            out["proposal"].update(accepted=False, refused_by="public", status=e.status, reason=e.body)
    return out
