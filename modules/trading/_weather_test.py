"""Unit tests for _weather.py over the checks' fixture: no network.

  python3 -I _weather_test.py [forecasts.json]
"""

import datetime
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _weather as w  # noqa: E402

FIXTURE = sys.argv.pop(1) if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "_json", "forecasts.json")
AS_OF = datetime.date(2026, 11, 4)


class Parse(unittest.TestCase):
    def test_high_temp_day(self):
        q = w.parse_question("Highest temperature in New York on Nov 6?", "72° or above", AS_OF)
        self.assertEqual((q.shape, q.city, q.low, q.high, q.start), ("high-temp-day", "New York", 72, None, datetime.date(2026, 11, 6)))
        q = w.parse_question("High temp in NYC on November 6?", "66° to 71°", AS_OF)
        self.assertEqual((q.city, q.low, q.high), ("New York", 66, 71))
        q = w.parse_question("Highest temperature in Chicago on Nov 6?", "65° or below", AS_OF, "2026-11-07T04:59:00Z")
        self.assertEqual((q.low, q.high, q.start.year), (None, 65, 2026))

    def test_month_totals(self):
        q = w.parse_question("Rain in Chicago in November?", "Above 3 inches", AS_OF)
        self.assertEqual((q.shape, q.variable, q.low, q.high, q.start, q.end), ("rain-month", "rain", 3.0, None, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30)))
        q = w.parse_question("Snow in Chicago in December?", "1 to 2 inches", AS_OF)
        self.assertEqual((q.shape, q.low, q.high, q.start.year), ("snow-month", 1.0, 2.0, 2026))
        q = w.parse_question("Rain in Miami in January?", "Below 1 inch", AS_OF)
        self.assertEqual((q.high, q.start.year), (1.0, 2027))

    def test_unknown_shapes_are_none(self):
        self.assertIsNone(w.parse_question("Where will it rain this weekend?", "New York", AS_OF))
        self.assertIsNone(w.parse_question("Rain in Narnia in November?", "Above 1 inch", AS_OF))
        self.assertIsNone(w.parse_question("Rain in Chicago in November?", "A lot", AS_OF))
        self.assertIsNone(w.parse_question("Highest temperature in New York on Nov 31?", "72° or above", AS_OF))
        self.assertIsNone(w.parse_question("Hurricane landfall in Florida in 2026?", "Yes", AS_OF))


class Probability(unittest.TestCase):
    def setUp(self):
        self.data = w.load_data(FIXTURE)

    def p(self, event, outcome):
        return w.probability(w.parse_question(event, outcome, AS_OF), self.data, AS_OF)

    def test_high_temp_bands_sum_to_one(self):
        above, mid, below = (self.p("Highest temperature in New York on Nov 6?", o) for o in ("72° or above", "66° to 71°", "65° or below"))
        self.assertAlmostEqual(above + mid + below, 1.0, places=6)
        self.assertGreater(above, 0.9)

    def test_observed_day_is_certain(self):
        self.assertEqual(self.p("Highest temperature in New York on Nov 2?", "60° or above"), 1.0)
        self.assertEqual(self.p("Highest temperature in New York on Nov 2?", "62° or above"), 0.0)

    def test_month_total_near_its_price(self):
        p = self.p("Rain in Chicago in November?", "Above 3 inches")
        self.assertTrue(0.5 < p < 0.65, p)

    def test_none_without_data(self):
        self.assertIsNone(self.p("Highest temperature in Miami on Nov 6?", "80° or above"))
        self.assertIsNone(self.p("Highest temperature in New York on Nov 20?", "50° or above"))
        self.data["cities"]["Chicago"].pop("climatology")
        self.assertIsNone(self.p("Rain in Chicago in November?", "Above 3 inches"))

    def test_edge(self):
        self.assertEqual(w.edge(0.75, 0.20), 0.55)
        self.assertEqual(w.edge(0.2, 0.25), -0.05)


class Sources(unittest.TestCase):
    def test_open_meteo_daily(self):
        payload = {"daily": {"time": ["2026-11-03", "2026-11-04"], "temperature_2m_max": [63.1, 66.0], "precipitation_sum": [0.0, 0.1], "snowfall_sum": [0.0, 0.0]}}
        out = w.open_meteo_daily(payload, AS_OF)
        self.assertEqual([d["kind"] for d in out], ["observed", "forecast"])
        self.assertEqual(out[1]["high_f"], 66.0)

    def test_nws_daily(self):
        grid = {
            "properties": {
                "maxTemperature": {"values": [{"validTime": "2026-11-06T11:00:00+00:00/PT13H", "value": 25.0}]},
                "quantitativePrecipitation": {"values": [{"validTime": "2026-11-06T12:00:00+00:00/PT6H", "value": 2.54}, {"validTime": "2026-11-06T18:00:00+00:00/PT6H", "value": 2.54}]},
                "snowfallAmount": {"values": []},
            }
        }
        out = w.nws_daily(grid, "America/New_York")
        self.assertEqual(out[0]["date"], "2026-11-06")
        self.assertAlmostEqual(out[0]["high_f"], 77.0)
        self.assertAlmostEqual(out[0]["precip_in"], 0.2)

    def test_live_fetch_is_offline_here(self):
        seen = []

        def fetch(url, params=None, timeout=30):
            seen.append(url)
            return {"daily": {"time": [], "temperature_2m_max": []}}

        data = w.live_data(["Chicago"], AS_OF, "open-meteo", fetch)
        self.assertEqual(seen, [w.OPEN_METEO_BASE])
        self.assertEqual(data["cities"]["Chicago"]["daily"], [])
        with self.assertRaises(ValueError):
            w.live_data(["Chicago"], AS_OF, "guess", fetch)


if __name__ == "__main__":
    unittest.main()
