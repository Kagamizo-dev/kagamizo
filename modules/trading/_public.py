"""Public's API for `trade`: the adapter NautilusTrader does not have.

The same endpoints the pinned publicdotcom-cli calls (its generated client
names them), through the standard library only, so it runs inside the
NautilusTrader Python:

  token       a short-lived access token minted from PUBLIC_PERSONAL_SECRET
  account     PUBLIC_ACCOUNT_ID, else the one BROKERAGE account
  instrument  an equity's trading details
  bars        historic bars of one session, as rows for the backtest CSV
  preflight   what an order would cost and whether Public would take it;
              Public places nothing for a preflight

Nothing here places, replaces or cancels an order.
"""

import json
import os
import urllib.error
import urllib.request

BASE_URL = os.environ.get("PUBLIC_API_BASE_URL", "https://api.public.com").rstrip("/")

# NautilusTrader's bar steps, as Public's aggregation and the longest period
# Public serves at that aggregation.
AGGREGATIONS = {
    "1-MINUTE": ("ONE_MINUTE", "DAY"),
    "5-MINUTE": ("FIVE_MINUTES", "WEEK"),
    "10-MINUTE": ("TEN_MINUTES", "WEEK"),
    "15-MINUTE": ("FIFTEEN_MINUTES", "MONTH"),
    "30-MINUTE": ("THIRTY_MINUTES", "MONTH"),
    "1-HOUR": ("ONE_HOUR", "QUARTER"),
    "1-DAY": ("ONE_DAY", "FIVE_YEARS"),
    "1-WEEK": ("ONE_WEEK", "TEN_YEARS"),
}


class PublicError(RuntimeError):
    def __init__(self, method, path, status, body):
        super().__init__(f"{method} {path}: HTTP {status}")
        self.status = status
        self.body = body


class Public:
    def __init__(self, secret=None, account_id=None):
        self.secret = secret or os.environ.get("PUBLIC_PERSONAL_SECRET")
        if not self.secret:
            raise RuntimeError("PUBLIC_PERSONAL_SECRET is not set; run through `trade`, which reads it from Proton Pass")
        self._token = None
        self._account = account_id or os.environ.get("PUBLIC_ACCOUNT_ID") or None

    def _request(self, method, path, body=None, auth=True):
        headers = {"Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if auth:
            headers["Authorization"] = f"Bearer {self.token()}"
        req = urllib.request.Request(
            BASE_URL + path,
            data=None if body is None else json.dumps(body).encode(),
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                detail = json.loads(raw)
            except ValueError:
                detail = raw.decode(errors="replace")
            raise PublicError(method, path, e.code, detail) from None
        return json.loads(raw) if raw else None

    def token(self):
        # Fifteen minutes covers one run; nothing is stored.
        if self._token is None:
            out = self._request(
                "POST",
                "/userapiauthservice/personal/access-tokens",
                {"secret": self.secret, "validityInMinutes": 15},
                auth=False,
            )
            self._token = out["accessToken"]
        return self._token

    def account(self):
        if self._account is None:
            accounts = self._request("GET", "/userapigateway/trading/account").get("accounts", [])
            brokerage = [a["accountId"] for a in accounts if a.get("accountType") == "BROKERAGE"]
            if len(brokerage) != 1:
                raise RuntimeError(f"expected one BROKERAGE account, found {len(brokerage)}; set PUBLIC_ACCOUNT_ID")
            self._account = brokerage[0]
        return self._account

    def instrument(self, symbol, kind="EQUITY"):
        return self._request("GET", f"/userapigateway/trading/instruments/{symbol.upper()}/{kind}")

    def bars(self, symbol, step, period=None, kind="EQUITY", session="regularMarket"):
        """Rows of timestamp, open, high, low, close, volume, oldest first."""
        if step not in AGGREGATIONS:
            raise RuntimeError(f"Public serves no {step} bars; it serves {', '.join(AGGREGATIONS)}")
        aggregation, longest = AGGREGATIONS[step]
        path = f"/userapigateway/historicdata/{kind}/{symbol.upper()}/{period or longest}/{aggregation}"
        out = self._request("GET", path)
        bars = (out.get(session) or {}).get("bars", [])
        rows = [
            {
                "timestamp": b["timestamp"],
                "open": b["open"],
                "high": b["high"],
                "low": b["low"],
                "close": b["close"],
                "volume": b["volume"],
            }
            for b in bars
        ]
        return sorted(rows, key=lambda r: r["timestamp"])

    def preflight(self, order):
        """Public's preflight of one single-leg order body; places nothing."""
        return self._request("POST", f"/userapigateway/trading/{self.account()}/preflight/single-leg", order)


def order_body(symbol, side, order_type, quantity, time_in_force, limit_price=None, stop_price=None, expire_time=None):
    """One single-leg equity order as Public's API takes it.

    Plain values, so the mapping is checked without an engine: side is BUY or
    SELL, order_type MARKET, LIMIT, STOP or STOP_LIMIT, time_in_force one of
    NautilusTrader's names. Public has DAY and GTD; a market order is always
    DAY, and GTC is refused rather than guessed at.
    """
    if side not in ("BUY", "SELL"):
        raise ValueError(f"Public has no order side {side}")
    if order_type not in ("MARKET", "LIMIT", "STOP", "STOP_LIMIT"):
        raise ValueError(f"Public has no {order_type} orders")
    if order_type == "MARKET" or time_in_force == "DAY":
        expiration = {"timeInForce": "DAY"}
    elif time_in_force == "GTD" and expire_time:
        expiration = {"timeInForce": "GTD", "expirationTime": expire_time}
    else:
        raise ValueError(f"Public takes DAY or GTD (with an expiry), not {time_in_force}")
    body = {
        "instrument": {"symbol": symbol.upper(), "type": "EQUITY"},
        "orderSide": side,
        "orderType": order_type,
        "expiration": expiration,
        "quantity": str(quantity),
    }
    if order_type in ("LIMIT", "STOP_LIMIT"):
        if limit_price is None:
            raise ValueError(f"a {order_type} order needs a limit price")
        body["limitPrice"] = str(limit_price)
    if order_type in ("STOP", "STOP_LIMIT"):
        if stop_price is None:
            raise ValueError(f"a {order_type} order needs a stop price")
        body["stopPrice"] = str(stop_price)
    return body
