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
        if self.path.startswith(f"/userapigateway/option-details/{ACCOUNT}/greeks?"):
            from urllib.parse import parse_qs, urlparse

            syms = parse_qs(urlparse(self.path).query).get("osiSymbols", [])
            self.reply(200, {"greeks": [{"instrument": {"symbol": s, "type": "OPTION"}, **greeks_of(s)} for s in syms]})
        elif self.path.startswith(f"/userapigateway/trading/{ACCOUNT}/order/"):
            order_id = self.path.rsplit("/", 1)[-1]
            o = ORDERS.get(order_id)
            if o is None:
                self.reply(404, {"message": "no such order"})
            else:
                self.reply(200, {**o, "status": "FILLED"})
        elif self.path == "/userapigateway/trading/account":
            self.reply(200, {"accounts": [{"accountId": ACCOUNT, "accountType": "BROKERAGE"}]})
        elif self.path == "/userapigateway/historicdata/EQUITY/SPY/FIVE_YEARS/ONE_DAY":
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
