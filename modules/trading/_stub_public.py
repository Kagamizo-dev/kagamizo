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
        if self.path == "/userapigateway/trading/account":
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
            if body["orderSide"] == "SELL":
                self.reply(400, {"message": "insufficient shares"})
            else:
                self.reply(200, {"instrument": body["instrument"], "orderValue": "1000.00", "estimatedCost": "1000.00"})
        else:
            self.reply(404, {"message": f"no {self.path}"})


server = HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
