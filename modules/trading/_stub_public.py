"""A stand-in for Public's API, for checks.trading-backtest: the endpoints
_public.py calls, answering from BARS.csv. It accepts BUY preflights and
refuses SELLs (no shares held), so both paths are exercised. Prints its port.

  python3 _stub_public.py BARS.csv
"""

import csv
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

with open(sys.argv[1], newline="") as f:
    BARS = [
        {**r, "value": r["close"], "volume": int(r["volume"])}
        for r in csv.DictReader(f)
    ]
SECRET, TOKEN, ACCOUNT = "stub-secret", "stub-token", "5LA00001"
ORDERS = {}

# A chain around the last close: strikes every dollar, asks falling from
# $1.00 at the money by ten cents a dollar out (so a $25 cap fits from
# eight dollars out), deltas from 0.5 at the money by 0.04 a dollar (0.18
# eight dollars out), expirations 3, 10, 17 and 45 days past the last bar.
import datetime

LAST = float(BARS[-1]["close"])
LAST_DAY = datetime.date.fromisoformat(BARS[-1]["timestamp"][:10])
EXPIRATIONS = [(LAST_DAY + datetime.timedelta(days=d)).isoformat() for d in (3, 10, 17, 45)]


def osi(symbol, expiration, kind, strike):
    d = datetime.date.fromisoformat(expiration)
    return f"{symbol:<6}{d.strftime('%y%m%d')}{kind}{int(round(strike * 1000)):08d}"


def greeks_of(sym):
    # Delta from the symbol's distance to the money; the stub is deterministic.
    kind, strike = sym[12], int(sym[13:]) / 1000
    away = (strike - LAST) if kind == "C" else (LAST - strike)
    delta = max(0.05, min(0.9, 0.5 - away * 0.04))
    return {"delta": round(delta if kind == "C" else -delta, 3), "gamma": 0.02, "theta": -0.05, "vega": 0.1, "rho": 0.01, "impliedVolatility": 0.2}


def chain(symbol, expiration):
    def quote(kind, strike):
        away = (strike - LAST) if kind == "C" else (LAST - strike)
        ask = round(max(0.05, 1.0 - away * 0.1), 2)
        sym = osi(symbol, expiration, kind, strike)
        return {
            "instrument": {"symbol": sym, "type": "OPTION"},
            "bid": f"{max(0.01, ask - 0.05):.2f}",
            "ask": f"{ask:.2f}",
            "last": f"{ask:.2f}",
            "optionDetails": {"strikePrice": f"{strike:.2f}", "greeks": greeks_of(sym)},
        }

    strikes = [round(LAST) + i for i in range(-8, 9)]
    return {"baseSymbol": symbol, "calls": [quote("C", k) for k in strikes], "puts": [quote("P", k) for k in strikes]}


# A few weather event contracts, shaped as the details endpoint's DTOs
# (eventSymbol, outcomes with YES and NO contracts, prices in dollars
# 0.00-1.00): two open events and one resolved. The dates are fixed to the
# checks' forecasts fixture (modules/trading/_json/forecasts.json, as of
# 2026-11-04). The subcategory of a daily-temperature market is a name the
# stub makes up; Public's real ones come from `event-contracts categories`.
WEATHER = "Climate and Weather"


def contract(outcome_id, yes_ask, no_ask):
    return [
        {"symbol": f"{outcome_id}.Y", "predictedOutcome": "YES", "bid": f"{yes_ask - 0.02:.2f}", "ask": f"{yes_ask:.2f}", "last": f"{yes_ask - 0.01:.2f}", "openInterest": "120", "probability": f"{yes_ask - 0.01:.2f}"},
        {"symbol": f"{outcome_id}.N", "predictedOutcome": "NO", "bid": f"{no_ask - 0.02:.2f}", "ask": f"{no_ask:.2f}", "last": f"{no_ask - 0.01:.2f}", "openInterest": "120", "probability": f"{1 - (yes_ask - 0.01):.2f}"},
    ]


def outcome(outcome_id, title, yes_ask, no_ask, state="STATE_OPEN", trading="BUY_AND_SELL", close="2026-11-07T04:59:00Z", settled="SETTLED_OUTCOME_UNSPECIFIED"):
    return {
        "outcomeId": outcome_id,
        "title": title,
        "rules": f"Resolves YES if the question's observation falls in the band: {title}.",
        "volume": "4000",
        "state": state,
        "timeline": {"openTime": "2026-10-30T14:00:00Z", "closeTime": close, "expectedExpirationTime": close},
        "settledOutcome": settled,
        "trading": trading,
        "contracts": contract(outcome_id, yes_ask, no_ask),
    }


EVENTS = {
    "KALSHI.KXHIGHNY-26NOV06": {
        "title": "Highest temperature in New York on Nov 6?",
        "subcategories": ["Temperature"],
        "resolutionTime": "2026-11-07T04:59:00Z",
        "resolved": False,
        "outcomes": [
            outcome("KALSHI.KXHIGHNY-26NOV06-T72", "72° or above", 0.20, 0.82),
            outcome("KALSHI.KXHIGHNY-26NOV06-B66", "66° to 71°", 0.50, 0.52),
            outcome("KALSHI.KXHIGHNY-26NOV06-T65", "65° or below", 0.30, 0.72),
        ],
    },
    "KALSHI.KXRAINCHI-26NOV": {
        "title": "Rain in Chicago in November?",
        "subcategories": ["Snow and rain"],
        "resolutionTime": "2026-12-01T05:59:00Z",
        "resolved": False,
        "outcomes": [outcome("KALSHI.KXRAINCHI-26NOV-3", "Above 3 inches", 0.55, 0.50, close="2026-12-01T05:59:00Z")],
    },
    "KALSHI.KXRAINMIA-26OCT": {
        "title": "Rain in Miami in October?",
        "subcategories": ["Snow and rain"],
        "resolutionTime": "2026-11-01T04:59:00Z",
        "resolved": True,
        "outcomes": [outcome("KALSHI.KXRAINMIA-26OCT-5", "Above 5 inches", 0.99, 0.01, state="STATE_SETTLED", trading="DISABLED", close="2026-11-01T04:59:00Z", settled="SETTLED_OUTCOME_YES")],
    },
}


def event_summary(symbol, e):
    return {
        "title": e["title"],
        "eventSymbol": symbol,
        "volume": str(sum(int(o["volume"]) for o in e["outcomes"])),
        "category": WEATHER,
        "subcategories": e["subcategories"],
        "symbols": [c["symbol"] for o in e["outcomes"] for c in o["contracts"]],
        "resolutionTime": e["resolutionTime"],
        "resolved": e["resolved"],
        "halted": False,
    }


def event_details(symbol, e):
    return {
        "eventSymbol": symbol,
        "exchange": "KALSHI",
        "title": e["title"],
        "category": WEATHER,
        "volume": event_summary(symbol, e)["volume"],
        "subcategories": e["subcategories"],
        "cftcContract": {"prohibitions": [], "resolutionSources": [{"name": "NWS", "url": "https://www.weather.gov"}], "contractTermsUrl": "https://kalshi.com/terms"},
        "outcomeCount": len(e["outcomes"]),
        "outcomes": e["outcomes"],
        "resolved": e["resolved"],
        "halted": False,
    }


def contracts_by_symbol():
    return {c["symbol"]: c for e in EVENTS.values() for o in e["outcomes"] for c in o["contracts"]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, status, body):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def authed(self):
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            self.reply(401, {"message": "unauthorized"})
            return False
        return True

    def do_GET(self):
        if not self.authed():
            return
        from urllib.parse import parse_qs, urlparse

        url = urlparse(self.path)
        query = parse_qs(url.query)
        if url.path == f"/userapigateway/option-details/{ACCOUNT}/greeks":
            syms = query.get("osiSymbols", [])
            self.reply(200, {"greeks": [{"instrument": {"symbol": s, "type": "OPTION"}, **greeks_of(s)} for s in syms]})
        elif url.path.startswith(f"/userapigateway/trading/{ACCOUNT}/order/"):
            order_id = url.path.rsplit("/", 1)[-1]
            o = ORDERS.get(order_id)
            if o is None:
                self.reply(404, {"message": "no such order"})
            else:
                self.reply(200, {**o, "status": "FILLED"})
        elif url.path == "/userapigateway/trading/account":
            self.reply(200, {"accounts": [{"accountId": ACCOUNT, "accountType": "BROKERAGE"}]})
        elif url.path == "/userapigateway/historicdata/EQUITY/SPY/FIVE_YEARS/ONE_DAY":
            empty = {"expectedBars": 0, "bars": []}
            self.reply(
                200,
                {
                    "symbol": "SPY",
                    "period": "FIVE_YEARS",
                    "totalExpectedBars": len(BARS),
                    "preMarket": empty,
                    "regularMarket": {"expectedBars": len(BARS), "bars": list(reversed(BARS))},
                    "afterMarket": empty,
                },
            )
        elif url.path.startswith("/userapigateway/eventcontract/details/"):
            symbol = url.path.rsplit("/", 1)[-1]
            if symbol not in EVENTS:
                self.reply(404, {"message": f"no event {symbol}"})
            else:
                self.reply(200, event_details(symbol, EVENTS[symbol]))
        elif url.path.startswith("/userapigateway/historicdata/event-contracts/") and "/bars/" in url.path:
            period = url.path.rsplit("/", 1)[-1]
            known = contracts_by_symbol()
            charts = []
            for s in query.get("symbols", [""])[0].split(","):
                if s in known:
                    price = float(known[s]["last"])
                    charts.append(
                        {
                            "symbol": s,
                            "previousClosePrice": f"{price:.2f}",
                            "currentPrice": f"{price:.2f}",
                            "bars": [{"timestamp": "2026-11-03T00:00:00Z", "open": f"{price:.2f}", "high": f"{price:.2f}", "low": f"{price:.2f}", "close": f"{price:.2f}", "value": f"{price:.2f}", "volume": 10}],
                        }
                    )
            self.reply(200, {"period": period, "charts": charts})
        else:
            self.reply(404, {"message": f"no {self.path}"})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/userapiauthservice/personal/access-tokens":
            if body.get("secret") != SECRET:
                self.reply(401, {"message": "bad secret"})
            else:
                self.reply(200, {"accessToken": TOKEN})
        elif self.path == f"/userapigateway/trading/{ACCOUNT}/preflight/single-leg":
            if not self.authed():
                return
            if body["instrument"]["type"] == "OPTION":
                cost = f'{float(body["limitPrice"]) * 100 * int(body["quantity"]):.2f}'
                self.reply(200, {"instrument": body["instrument"], "orderValue": cost, "estimatedCost": cost})
            elif body["instrument"]["type"] == "EVENTCONTRACT":
                known = contracts_by_symbol()
                if body["instrument"]["symbol"] not in known:
                    self.reply(400, {"message": "unknown event contract"})
                elif body["orderSide"] == "SELL":
                    self.reply(400, {"message": "no contracts held"})
                else:
                    cost = f'{float(body["limitPrice"]) * int(body["quantity"]):.2f}'
                    self.reply(200, {"instrument": body["instrument"], "orderValue": cost, "estimatedCost": cost, "estimatedQuantity": body["quantity"]})
            elif body["orderSide"] == "SELL":
                self.reply(400, {"message": "insufficient shares"})
            else:
                self.reply(200, {"instrument": body["instrument"], "orderValue": "1000.00", "estimatedCost": "1000.00"})
        elif self.path == f"/userapigateway/marketdata/{ACCOUNT}/option-expirations":
            if not self.authed():
                return
            self.reply(200, {"expirations": EXPIRATIONS})
        elif self.path == f"/userapigateway/marketdata/{ACCOUNT}/option-chain":
            if not self.authed():
                return
            self.reply(200, chain(body["instrument"]["symbol"], body["expirationDate"]))
        elif self.path == f"/userapigateway/marketdata/{ACCOUNT}/quotes":
            if not self.authed():
                return
            known = contracts_by_symbol()
            quotes = []
            for i in body.get("instruments", []):
                c = known.get(i["symbol"]) if i["type"] == "EVENTCONTRACT" else None
                if c is None:
                    quotes.append({"instrument": i, "outcome": "UNKNOWN"})
                else:
                    quotes.append({"instrument": i, "outcome": "SUCCESS", "last": c["last"], "bid": c["bid"], "ask": c["ask"], "bidSize": 50, "askSize": 50, "volume": 100})
            self.reply(200, {"quotes": quotes})
        elif self.path == "/userapigateway/eventcontract/summary":
            if not self.authed():
                return
            if body.get("sortingMode") not in ("VOLUME", "EXPIRATION", "RECENTLY_ADDED"):
                self.reply(400, {"message": "sortingMode is required"})
                return
            content = [
                event_summary(s, e)
                for s, e in EVENTS.items()
                if body.get("category") in (None, WEATHER)
                and (body.get("subcategory") is None or body["subcategory"] in e["subcategories"])
                and (body.get("displayResolvedEvents") or not e["resolved"])
            ]
            self.reply(200, {"content": content})
        elif self.path == f"/userapigateway/trading/{ACCOUNT}/order":
            if not self.authed():
                return
            order_id = body.get("orderId") or f"stub-{len(ORDERS) + 1}"
            ORDERS[order_id] = {"orderId": order_id, "instrument": body["instrument"], "side": body["orderSide"], "quantity": body["quantity"], "limitPrice": body.get("limitPrice")}
            self.reply(200, {"orderId": order_id})
        else:
            self.reply(404, {"message": f"no {self.path}"})


server = HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
