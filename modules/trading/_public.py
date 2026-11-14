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
  option_expirations, option_chain, greeks
              an underlying's listed expirations, one expiration's chain
              (calls and puts, each with its OSI symbol, bid, ask, strike
              and, when Public has them, greeks), and greeks by OSI symbol
  event_contract_summary, event_contracts, event_contract_details,
  event_contract_bars, quotes
              the event contracts Public lists (Kalshi's, as
              KALSHI.<series>-<event>): one page of event summaries by
              category and subcategory, every page, one event's outcomes
              with their YES and NO contracts and prices, a contract's
              price bars, and quotes by instrument
  place       one single-leg order, as `trade place` sends it (a spend
              action: the controller's, after the risk check and a fresh
              preflight); order() reads it back by its id

Only `place` places; nothing replaces or cancels.
"""

import json
import os
import urllib.error
import urllib.parse
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

# The event-contract enums, as the CLI's cli.py and the generated request
# models spell them (EVENT_SORTING_MODES, EVENT_FREQUENCIES,
# EVENT_CONTRACT_PERIODS, EVENT_CONTRACT_MAX_SYMBOLS).
EVENT_SORTING_MODES = ("VOLUME", "EXPIRATION", "RECENTLY_ADDED")
EVENT_FREQUENCIES = ("ALL", "ONCE", "FIFTEEN_MINUTES", "ONE_HOUR", "ONE_DAY", "ONE_WEEK", "ONE_MONTH", "ONE_YEAR")
EVENT_CONTRACT_PERIODS = ("DAY", "WEEK", "MONTH", "ALL")
EVENT_CONTRACT_MAX_SYMBOLS = 8
INSTRUMENT_TYPES = ("EQUITY", "OPTION", "MULTI_LEG_INSTRUMENT", "CRYPTO", "ALT", "TREASURY", "BOND", "INDEX", "EVENTCONTRACT")


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

    def _request(self, method, path, body=None, auth=True, params=None):
        headers = {"Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if auth:
            headers["Authorization"] = f"Bearer {self.token()}"
        if params:
            query = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
            path = f"{path}?{query}"
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

    def option_expirations(self, symbol, kind="EQUITY"):
        """The expiration dates (YYYY-MM-DD) listed on an underlying."""
        out = self._request(
            "POST",
            f"/userapigateway/marketdata/{self.account()}/option-expirations",
            {"instrument": {"symbol": symbol.upper(), "type": kind}},
        )
        return sorted(out.get("expirations") or out.get("expirationDates") or [])

    def option_chain(self, symbol, expiration, kind="EQUITY"):
        """One expiration's chain: {"calls": [...], "puts": [...]}, each quote
        with instrument.symbol (OSI), bid, ask and optionDetails.strikePrice."""
        return self._request(
            "POST",
            f"/userapigateway/marketdata/{self.account()}/option-chain",
            {"instrument": {"symbol": symbol.upper(), "type": kind}, "expirationDate": expiration},
        )

    def greeks(self, osi_symbols):
        """Greeks by OSI symbol: {symbol: {"delta": ..., ...}}."""
        query = "&".join("osiSymbols=" + urllib.parse.quote(s) for s in osi_symbols)
        out = self._request("GET", f"/userapigateway/option-details/{self.account()}/greeks?{query}")
        found = {}
        for g in out.get("greeks") or []:
            sym = (g.get("instrument") or {}).get("symbol") or g.get("osiSymbol") or g.get("symbol")
            if sym:
                found[sym] = {k: g.get(k) for k in ("delta", "gamma", "theta", "vega", "rho", "impliedVolatility")}
        return found

    def quotes(self, instruments):
        """Quotes by instrument, as `market quotes` asks: instruments are
        (symbol, type) pairs or {"symbol", "type"} dicts; an event contract's
        type is EVENTCONTRACT. Each quote carries instrument, outcome
        (SUCCESS or UNKNOWN), last, bid, ask, bidSize, askSize, volume."""
        body = []
        for i in instruments:
            symbol, kind = (i["symbol"], i["type"]) if isinstance(i, dict) else i
            if kind not in INSTRUMENT_TYPES:
                raise ValueError(f"Public has no instrument type {kind}")
            body.append({"symbol": symbol.upper(), "type": kind})
        out = self._request("POST", f"/userapigateway/marketdata/{self.account()}/quotes", {"instruments": body})
        return out.get("quotes") or []

    def event_contract_summary(
        self,
        category=None,
        subcategory=None,
        frequencies=None,
        include_resolved=None,
        resolution_start=None,
        resolution_end=None,
        event_symbols=None,
        created_within_days=None,
        next_token=None,
        sort="VOLUME",
    ):
        """One page (up to 100) of event summaries: {"content": [{title,
        eventSymbol, volume, category, subcategories, symbols,
        resolutionTime, resolved, halted}], "nextToken"}. The body is built
        as the CLI's `event-contracts summary` builds it: sortingMode
        always; `filters` (eventSymbols, frequencies, resolution window)
        only when one of them is given, with the lists the spec marks
        required defaulted to [] and ["ALL"]."""
        if sort not in EVENT_SORTING_MODES:
            raise ValueError(f"sort is one of {', '.join(EVENT_SORTING_MODES)}, not {sort}")
        body = {"sortingMode": sort}
        if category is not None:
            body["category"] = category
        if subcategory is not None:
            body["subcategory"] = subcategory
        if next_token is not None:
            body["nextToken"] = next_token
        if include_resolved is not None:
            body["displayResolvedEvents"] = bool(include_resolved)
        if created_within_days is not None:
            body["createdWithinDays"] = int(created_within_days)
        for f in frequencies or []:
            if f not in EVENT_FREQUENCIES:
                raise ValueError(f"frequency is one of {', '.join(EVENT_FREQUENCIES)}, not {f}")
        if event_symbols or frequencies or resolution_start or resolution_end:
            filters = {
                "eventSymbols": [s.upper() for s in event_symbols or []],
                "frequencies": list(frequencies) or ["ALL"],
            }
            if resolution_start is not None:
                filters["resolutionTimeStart"] = resolution_start
            if resolution_end is not None:
                filters["resolutionTimeEnd"] = resolution_end
            body["filters"] = filters
        return self._request("POST", "/userapigateway/eventcontract/summary", body)

    def event_contracts(self, max_pages=20, **kwargs):
        """Every event summary matching the filters, page after page."""
        out, token = [], None
        for _ in range(max_pages):
            page = self.event_contract_summary(next_token=token, **kwargs)
            out.extend(page.get("content") or [])
            token = page.get("nextToken")
            if not token:
                break
        return out

    def event_contract_details(self, event_symbol, all_outcomes=True):
        """One event: eventSymbol, exchange, title, category, subcategories,
        cftcContract (prohibitions, resolutionSources, contractTermsUrl),
        outcomeCount, outcomes [{outcomeId, title, rules, volume, state
        (STATE_OPEN...), timeline {openTime, closeTime,
        expectedExpirationTime...}, settledOutcome, trading (BUY_AND_SELL,
        DISABLED, LIQUIDATION_ONLY), contracts [{symbol (ending .Y or .N),
        predictedOutcome YES|NO, bid, ask, last, openInterest,
        probability}]}], resolved, halted."""
        return self._request(
            "GET",
            f"/userapigateway/eventcontract/details/{event_symbol.strip().upper()}",
            params={"includeAllOutcomes": "true" if all_outcomes else "false"},
        )

    def event_contract_bars(self, event_id, period, symbols):
        """Price bars (dollars 0.00-1.00, the implied probability of the
        side the symbol names) for up to 8 contracts of one event, whose id
        is the -EVENT grouping id (e.g. KALSHI.KXBALANCESHEET-EO26-EVENT):
        {"period", "charts": [{symbol, currentPrice, bars: [{timestamp,
        open, high, low, close, value, volume}]}]}; a symbol without a
        price in the period is left out."""
        if period not in EVENT_CONTRACT_PERIODS:
            raise ValueError(f"period is one of {', '.join(EVENT_CONTRACT_PERIODS)}, not {period}")
        symbols = [s.strip().upper() for s in symbols if s.strip()]
        if not symbols or len(symbols) > EVENT_CONTRACT_MAX_SYMBOLS:
            raise ValueError(f"1 to {EVENT_CONTRACT_MAX_SYMBOLS} symbols per request")
        return self._request(
            "GET",
            f"/userapigateway/historicdata/event-contracts/{event_id.upper()}/bars/{period}",
            params={"symbols": ",".join(symbols)},
        )

    def place(self, order):
        """Places one single-leg order; the one call here that moves money."""
        return self._request("POST", f"/userapigateway/trading/{self.account()}/order", order)

    def order(self, order_id):
        return self._request("GET", f"/userapigateway/trading/{self.account()}/order/{order_id}")


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


def option_order_body(osi_symbol, side, limit_price, quantity, open_close="OPEN", order_id=None):
    """One single-leg option order, LIMIT and DAY: what the limits allow.

    side is BUY or SELL; open_close OPEN to enter, CLOSE to exit. A market
    order on an option is never built: the limit is the risk check's
    premium, and Public takes limit orders on options.
    """
    if side not in ("BUY", "SELL"):
        raise ValueError(f"Public has no order side {side}")
    if open_close not in ("OPEN", "CLOSE"):
        raise ValueError(f"openCloseIndicator is OPEN or CLOSE, not {open_close}")
    body = {
        "instrument": {"symbol": osi_symbol, "type": "OPTION"},
        "orderSide": side,
        "orderType": "LIMIT",
        "expiration": {"timeInForce": "DAY"},
        "quantity": str(quantity),
        "limitPrice": f"{float(limit_price):.2f}",
        "openCloseIndicator": open_close,
    }
    if order_id:
        body["orderId"] = order_id
    return body


def event_contract_order_body(symbol, side, limit_price, quantity, order_id=None):
    """One single-leg event-contract order, LIMIT and DAY.

    Mapped from the CLI's generated order request (OrderApiOrderRequest):
    the instrument is {symbol, type: "EVENTCONTRACT"} (the instrument type
    enum lists EVENTCONTRACT; the symbol itself names the side, ending .Y
    for YES and .N for NO, as the details endpoint's contracts carry them),
    orderSide is BUY or SELL (the request has no YES/NO side), orderType
    LIMIT with limitPrice, expiration DAY, quantity whole contracts. The
    price is in dollars from 0.00 to 1.00, as the bars endpoint states
    event-contract prices; the request model does not say otherwise, and
    the preflight (which places nothing) is the check. openCloseIndicator
    is left out: the model documents it for options and shorting only, and
    a buy defaults to OPEN. Whether Public takes GTD on event contracts is
    not stated by the client, so only DAY is built.
    """
    if side not in ("BUY", "SELL"):
        raise ValueError(f"Public has no order side {side}")
    price = float(limit_price)
    if not 0.0 < price < 1.0:
        raise ValueError(f"an event contract's price is between 0.00 and 1.00, not {price}")
    if int(quantity) < 1 or int(quantity) != quantity:
        raise ValueError(f"an event-contract order is for whole contracts, not {quantity}")
    body = {
        "instrument": {"symbol": symbol.strip().upper(), "type": "EVENTCONTRACT"},
        "orderSide": side,
        "orderType": "LIMIT",
        "expiration": {"timeInForce": "DAY"},
        "quantity": str(int(quantity)),
        "limitPrice": f"{price:.2f}",
    }
    if order_id:
        body["orderId"] = order_id
    return body
