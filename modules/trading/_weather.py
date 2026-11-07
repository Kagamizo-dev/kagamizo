"""The weather signal engine for event contracts: deterministic rules
(tier 0, never a model that talks), standard library only.

A contract on Public asks a question in its event's title and its
outcome's title ("Rain in Chicago in November?" / "Above 3 inches"). The
engine parses the few shapes it understands into a typed Question, turns
forecasts and observations into a probability for it, and the edge is
that probability minus the contract's price. A shape it does not
understand is None, never a guess.

  parse_question(event_title, outcome_title, as_of, resolution_time)
      -> Question | None
  probability(question, data, as_of) -> float | None
  edge(probability, price) -> float

Shapes handled (QUESTIONS):
  rain-month      "Rain in <City> in <Month>?"  / "Above 3 inches",
                  "3 inches or more", "Below 1 inch", "1 to 2 inches"
  snow-month      "Snow in <City> in <Month>?"  / the same thresholds
  high-temp-day   "Highest temperature in <City> on <Mon> <D>?" /
                  "72° or above", "65° or below", "66° to 71°"
Everything else ("Where will it rain this weekend?") is skipped.

Data is one typed structure, from a file (--forecasts, the checks' fixture)
or fetched live from Open-Meteo or the NWS (api.weather.gov, which needs
a User-Agent):

  {"as_of": "YYYY-MM-DD",
   "cities": {"<City>": {
      "daily": [{"date", "kind": "observed"|"forecast", "high_f",
                 "precip_in", "snow_in"}, ...],
      "climatology": {"<month 1-12>": {"precip_in_per_day_mean",
                      "precip_in_per_day_sd", "snow_in_per_day_mean",
                      "snow_in_per_day_sd"}}}}}

The rules (all declared here, so a change is a code change):
  high temp   the day's forecast high is the mean of a normal whose
              standard deviation grows with the lead: SIGMA_F(lead days);
              an observed day is certain. Kalshi's bands are whole
              degrees, so "72 or above" is T >= 71.5.
  rain, snow  the month's total is the sum of observed days (certain),
              forecast days (mean the amount, sd 0.6 x amount + 0.03) and,
              for days past the forecast, the month's climatology per day;
              the sum is taken normal. Without climatology for a day the
              window needs, the probability is None.
"""

import calendar
import datetime
import json
import math
import re
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

USER_AGENT = "kagamizo-trade/1 (https://github.com/Kagamizo-dev/kagamizo; modules/trading/_weather.py)"
NWS_BASE = "https://api.weather.gov"
OPEN_METEO_BASE = "https://api.open-meteo.com/v1/forecast"

QUESTIONS = ("rain-month", "snow-month", "high-temp-day")

# The cities Kalshi lists weather on, as their names appear in titles; the
# coordinates are the cities' NWS reporting stations' neighbourhoods, close
# enough for a forecast grid. An unknown city is an unparsed question.
CITIES = {
    "New York": {"lat": 40.78, "lon": -73.97, "tz": "America/New_York", "aliases": ["NYC", "New York City"]},
    "Chicago": {"lat": 41.96, "lon": -87.93, "tz": "America/Chicago", "aliases": []},
    "Miami": {"lat": 25.79, "lon": -80.32, "tz": "America/New_York", "aliases": []},
    "Austin": {"lat": 30.18, "lon": -97.68, "tz": "America/Chicago", "aliases": []},
    "Los Angeles": {"lat": 33.94, "lon": -118.41, "tz": "America/Los_Angeles", "aliases": ["LA"]},
    "Denver": {"lat": 39.85, "lon": -104.66, "tz": "America/Denver", "aliases": []},
    "Philadelphia": {"lat": 39.87, "lon": -75.23, "tz": "America/New_York", "aliases": ["Philly"]},
    "Seattle": {"lat": 47.45, "lon": -122.31, "tz": "America/Los_Angeles", "aliases": []},
    "Boston": {"lat": 42.36, "lon": -71.01, "tz": "America/New_York", "aliases": []},
    "Atlanta": {"lat": 33.63, "lon": -84.44, "tz": "America/New_York", "aliases": []},
    "Houston": {"lat": 29.98, "lon": -95.36, "tz": "America/Chicago", "aliases": []},
    "Dallas": {"lat": 32.90, "lon": -97.02, "tz": "America/Chicago", "aliases": ["Dallas-Fort Worth"]},
    "Washington": {"lat": 38.85, "lon": -77.04, "tz": "America/New_York", "aliases": ["Washington DC", "Washington, DC", "DC"]},
    "Phoenix": {"lat": 33.43, "lon": -112.01, "tz": "America/Phoenix", "aliases": []},
    "Las Vegas": {"lat": 36.08, "lon": -115.15, "tz": "America/Los_Angeles", "aliases": []},
    "Minneapolis": {"lat": 44.88, "lon": -93.22, "tz": "America/Chicago", "aliases": []},
    "San Francisco": {"lat": 37.62, "lon": -122.38, "tz": "America/Los_Angeles", "aliases": ["SF"]},
}

MONTHS = {m.lower(): i for i, m in enumerate(calendar.month_name) if m}
MONTHS.update({m.lower(): i for i, m in enumerate(calendar.month_abbr) if m})
MONTHS["sept"] = 9


class Question:
    """One parsed question: a city, a variable, a band and a window.

    shape     one of QUESTIONS
    variable  rain | snow (inches over the window) | high-temp (°F on the day)
    low, high the band the YES contract pays in, inclusive on whole degrees
              and open-ended when None: "72 or above" is (72, None),
              "66 to 71" is (66, 71), "Above 3 inches" is (3.0, None)
    start, end the window's first and last day (inclusive)
    """

    def __init__(self, shape, city, variable, low, high, start, end):
        self.shape, self.city, self.variable = shape, city, variable
        self.low, self.high, self.start, self.end = low, high, start, end

    def as_dict(self):
        return {
            "shape": self.shape,
            "city": self.city,
            "variable": self.variable,
            "low": self.low,
            "high": self.high,
            "start": self.start.isoformat(),
            "end": self.end.isoformat(),
        }


def canonical_city(name):
    name = name.strip().rstrip("?").strip()
    for city, c in CITIES.items():
        if name.lower() == city.lower() or name.lower() in (a.lower() for a in c["aliases"]):
            return city
    return None


def _year_for(month, as_of, resolution_time):
    """The year a month in a title means: the resolution's year when known,
    else this year, or next year for a month already past (a day earlier
    in this month stays this year: its market may still be listed)."""
    if resolution_time:
        return datetime.datetime.fromisoformat(resolution_time.replace("Z", "+00:00")).year
    return as_of.year + (1 if month < as_of.month else 0)


_NUM = r"(\d+(?:\.\d+)?)"
_UNIT = r"(?:\s*(?:inches|inch|in|\"))"
_MONTH_EVENT = re.compile(r"^(rain|snow)(?:fall)?\s+in\s+(.+?)\s+in\s+([A-Za-z]+)(?:\s+(\d{4}))?\s*\??$", re.I)
_BAND_ABOVE = re.compile(rf"^(?:above|over|more than)\s+{_NUM}{_UNIT}?$", re.I)
_BAND_OR_MORE = re.compile(rf"^{_NUM}{_UNIT}?\s+or\s+(?:more|above)$", re.I)
_BAND_BELOW = re.compile(rf"^(?:below|under|less than)\s+{_NUM}{_UNIT}?$", re.I)
_BAND_RANGE = re.compile(rf"^{_NUM}{_UNIT}?\s+(?:to|-)\s+{_NUM}{_UNIT}?$", re.I)
_DAY_EVENT = re.compile(r"^(?:highest|high)\s+temp(?:erature)?\s+in\s+(.+?)\s+on\s+([A-Za-z]+)\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?\s*\??$", re.I)
_DEG = r"(-?\d+)\s*°?\s*F?"
_TEMP_ABOVE = re.compile(rf"^{_DEG}\s+or\s+(?:above|higher|more)$", re.I)
_TEMP_BELOW = re.compile(rf"^{_DEG}\s+or\s+(?:below|lower|less)$", re.I)
_TEMP_RANGE = re.compile(rf"^{_DEG}\s*(?:to|-)\s*{_DEG}$", re.I)


def _band(title, above, or_more, below, rng, number):
    t = title.strip()
    m = above.match(t) or or_more.match(t)
    if m:
        return number(m.group(1)), None
    m = below.match(t)
    if m:
        return None, number(m.group(1))
    m = rng.match(t)
    if m:
        lo, hi = number(m.group(1)), number(m.group(2))
        return (lo, hi) if lo <= hi else None
    return None


def parse_question(event_title, outcome_title, as_of, resolution_time=None):
    """The typed question a contract asks, or None for a shape not handled."""
    m = _MONTH_EVENT.match(event_title.strip())
    if m:
        variable, city, month, year = m.group(1).lower(), canonical_city(m.group(2)), MONTHS.get(m.group(3).lower()), m.group(4)
        band = _band(outcome_title, _BAND_ABOVE, _BAND_OR_MORE, _BAND_BELOW, _BAND_RANGE, float)
        if city is None or month is None or band is None:
            return None
        y = int(year) if year else _year_for(month, as_of, resolution_time)
        return Question(
            f"{variable}-month", city, variable, band[0], band[1], datetime.date(y, month, 1), datetime.date(y, month, calendar.monthrange(y, month)[1])
        )
    m = _DAY_EVENT.match(event_title.strip())
    if m:
        city, month, day, year = canonical_city(m.group(1)), MONTHS.get(m.group(2).lower()), int(m.group(3)), m.group(4)
        band = _band(outcome_title, _TEMP_ABOVE, _TEMP_ABOVE, _TEMP_BELOW, _TEMP_RANGE, int)
        if city is None or month is None or band is None:
            return None
        y = int(year) if year else _year_for(month, as_of, resolution_time)
        try:
            d = datetime.date(y, month, day)
        except ValueError:
            return None
        return Question("high-temp-day", city, "high-temp", band[0], band[1], d, d)
    return None


def normal_cdf(x, mu, sigma):
    if sigma <= 0:
        return 1.0 if x >= mu else 0.0
    return 0.5 * (1.0 + math.erf((x - mu) / (sigma * math.sqrt(2.0))))


def band_probability(mu, sigma, low, high):
    """P(low <= X <= high) for X ~ N(mu, sigma); an open end is unbounded."""
    upper = 1.0 if high is None else normal_cdf(high, mu, sigma)
    lower = 0.0 if low is None else normal_cdf(low, mu, sigma)
    return max(0.0, min(1.0, upper - lower))


def sigma_f(lead_days):
    """The standard deviation of a daily-high forecast, °F, by lead."""
    return min(7.0, 2.5 + 0.75 * max(0, lead_days))


def forecast_precip_sd(amount):
    return 0.6 * amount + 0.03


def _daily_by_date(city_data):
    return {d["date"]: d for d in city_data.get("daily") or []}


def probability(question, data, as_of):
    """The model probability of the YES contract, or None without the data."""
    city_data = (data.get("cities") or {}).get(question.city)
    if city_data is None:
        return None
    daily = _daily_by_date(city_data)
    if question.shape == "high-temp-day":
        d = daily.get(question.start.isoformat())
        if d is None or d.get("high_f") is None:
            return None
        sigma = 0.0 if d.get("kind") == "observed" else sigma_f((question.start - as_of).days)
        low = None if question.low is None else question.low - 0.5
        high = None if question.high is None else question.high + 0.5
        return band_probability(float(d["high_f"]), sigma, low, high)
    key = "precip_in" if question.variable == "rain" else "snow_in"
    climatology = (city_data.get("climatology") or {}).get(str(question.start.month)) or {}
    mu, var = 0.0, 0.0
    day = question.start
    while day <= question.end:
        d = daily.get(day.isoformat())
        if d is not None and d.get(key) is not None:
            amount = float(d[key])
            mu += amount
            if d.get("kind") != "observed":
                var += forecast_precip_sd(amount) ** 2
        else:
            mean, sd = climatology.get(f"{key}_per_day_mean"), climatology.get(f"{key}_per_day_sd")
            if mean is None or sd is None:
                return None
            mu += float(mean)
            var += float(sd) ** 2
        day += datetime.timedelta(days=1)
    return band_probability(mu, math.sqrt(var), question.low, question.high)


def edge(probability, price):
    """What the model says the contract is worth over what it costs, as a
    probability: positive means buy. Pure; the strategy's minEdge is the
    threshold."""
    return round(float(probability) - float(price), 4)


# --- fetching: the live data sources, each a free API ---------------------


def fetch_json(url, params=None, timeout=30):
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/geo+json, application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def open_meteo_daily(payload, as_of):
    """Open-Meteo's daily block (fahrenheit, inch) as the typed daily list:
    days before as_of observed, the rest forecast."""
    daily = payload.get("daily") or {}
    out = []
    for i, date in enumerate(daily.get("time") or []):
        d = datetime.date.fromisoformat(date)

        def at(key):
            values = daily.get(key) or []
            return values[i] if i < len(values) else None

        out.append(
            {
                "date": date,
                "kind": "observed" if d < as_of else "forecast",
                "high_f": at("temperature_2m_max"),
                "precip_in": at("precipitation_sum"),
                "snow_in": at("snowfall_sum"),
            }
        )
    return out


def open_meteo_city(city, as_of, fetch=fetch_json, past_days=31, forecast_days=16):
    c = CITIES[city]
    payload = fetch(
        OPEN_METEO_BASE,
        {
            "latitude": c["lat"],
            "longitude": c["lon"],
            "daily": "temperature_2m_max,precipitation_sum,snowfall_sum",
            "temperature_unit": "fahrenheit",
            "precipitation_unit": "inch",
            "timezone": c["tz"],
            "past_days": past_days,
            "forecast_days": forecast_days,
        },
    )
    return {"daily": open_meteo_daily(payload, as_of)}


def nws_daily(gridpoint, tz):
    """An NWS gridpoint forecast's maxTemperature (°C), quantitativePrecipitation
    and snowfallAmount (mm) as the typed daily list, by the city's local
    date; all forecast (the NWS serves no past days)."""
    zone = ZoneInfo(tz)
    props = gridpoint.get("properties") or {}
    days = {}

    def local_date(valid_time):
        start = valid_time.split("/")[0]
        return datetime.datetime.fromisoformat(start.replace("Z", "+00:00")).astimezone(zone).date().isoformat()

    for v in (props.get("maxTemperature") or {}).get("values") or []:
        if v.get("value") is None:
            continue
        day = days.setdefault(local_date(v["validTime"]), {"high_f": None, "precip_in": 0.0, "snow_in": 0.0})
        f = float(v["value"]) * 9 / 5 + 32
        day["high_f"] = f if day["high_f"] is None else max(day["high_f"], f)
    for key, out in (("quantitativePrecipitation", "precip_in"), ("snowfallAmount", "snow_in")):
        for v in (props.get(key) or {}).get("values") or []:
            if v.get("value") is None:
                continue
            days.setdefault(local_date(v["validTime"]), {"high_f": None, "precip_in": 0.0, "snow_in": 0.0})[out] += float(v["value"]) / 25.4
    return [{"date": d, "kind": "forecast", **vals} for d, vals in sorted(days.items())]


def nws_city(city, fetch=fetch_json):
    c = CITIES[city]
    points = fetch(f"{NWS_BASE}/points/{c['lat']},{c['lon']}")
    grid_url = (points.get("properties") or {}).get("forecastGridData")
    if not grid_url:
        raise RuntimeError(f"NWS /points gave no forecastGridData for {city}")
    return {"daily": nws_daily(fetch(grid_url), c["tz"])}


def live_data(cities, as_of, source="open-meteo", fetch=fetch_json):
    """The typed data for the cities named, from one source. Climatology is
    not fetched: a monthly question past the forecast horizon is None
    until a climatology is declared in a data file."""
    if source not in ("open-meteo", "nws"):
        raise ValueError(f"source is open-meteo or nws, not {source}")
    out = {"as_of": as_of.isoformat(), "source": source, "cities": {}}
    for city in cities:
        out["cities"][city] = open_meteo_city(city, as_of, fetch) if source == "open-meteo" else nws_city(city, fetch)
    return out


def load_data(path):
    with open(path) as f:
        data = json.load(f)
    if "cities" not in data:
        raise ValueError(f"{path}: not a forecasts file (no cities)")
    return data
