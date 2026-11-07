//! The live forecasts (ported from _weather.py's `live_data`): one source,
//! Open-Meteo or the National Weather Service, fetched for every city the
//! rules know, as the typed WeatherData the rules read. Climatology is not
//! fetched: a monthly question past the forecast horizon has no
//! probability until a data file declares one.
use crate::data::{CityData, DailyRecord, WeatherData};
use chrono::{DateTime, NaiveDate};
use chrono_tz::Tz;
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};

pub const USER_AGENT: &str =
    "kagamizo-trade/1 (https://github.com/Kagamizo-dev/kagamizo; modules/trading/_rust/weather)";
pub const NWS_BASE: &str = "https://api.weather.gov";
pub const OPEN_METEO_BASE: &str = "https://api.open-meteo.com/v1/forecast";

/// A city the rules know: its NWS reporting station's neighbourhood and
/// its time zone, which decides what a local day is.
pub struct City {
    pub name: &'static str,
    pub lat: f64,
    pub lon: f64,
    pub tz: &'static str,
}

/// The cities Kalshi lists weather on (the same as canonical_city's).
pub const CITIES: &[City] = &[
    City { name: "New York", lat: 40.78, lon: -73.97, tz: "America/New_York" },
    City { name: "Chicago", lat: 41.96, lon: -87.93, tz: "America/Chicago" },
    City { name: "Miami", lat: 25.79, lon: -80.32, tz: "America/New_York" },
    City { name: "Austin", lat: 30.18, lon: -97.68, tz: "America/Chicago" },
    City { name: "Los Angeles", lat: 33.94, lon: -118.41, tz: "America/Los_Angeles" },
    City { name: "Denver", lat: 39.85, lon: -104.66, tz: "America/Denver" },
    City { name: "Philadelphia", lat: 39.87, lon: -75.23, tz: "America/New_York" },
    City { name: "Seattle", lat: 47.45, lon: -122.31, tz: "America/Los_Angeles" },
    City { name: "Boston", lat: 42.36, lon: -71.01, tz: "America/New_York" },
    City { name: "Atlanta", lat: 33.63, lon: -84.44, tz: "America/New_York" },
    City { name: "Houston", lat: 29.98, lon: -95.36, tz: "America/Chicago" },
    City { name: "Dallas", lat: 32.90, lon: -97.02, tz: "America/Chicago" },
    City { name: "Washington", lat: 38.85, lon: -77.04, tz: "America/New_York" },
    City { name: "Phoenix", lat: 33.43, lon: -112.01, tz: "America/Phoenix" },
    City { name: "Las Vegas", lat: 36.08, lon: -115.15, tz: "America/Los_Angeles" },
    City { name: "Minneapolis", lat: 44.88, lon: -93.22, tz: "America/Chicago" },
    City { name: "San Francisco", lat: 37.62, lon: -122.38, tz: "America/Los_Angeles" },
];

/// The two sources a strategy may declare.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Source {
    OpenMeteo,
    Nws,
}

impl std::str::FromStr for Source {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, String> {
        match s {
            "open-meteo" => Ok(Source::OpenMeteo),
            "nws" => Ok(Source::Nws),
            _ => Err(format!("source is open-meteo or nws, not {s}")),
        }
    }
}

impl Source {
    pub fn name(self) -> &'static str {
        match self {
            Source::OpenMeteo => "open-meteo",
            Source::Nws => "nws",
        }
    }
}

fn fetch(url: &str, query: &[(&str, String)]) -> Result<Value, String> {
    let mut req = ureq::get(url)
        .set("User-Agent", USER_AGENT)
        .set("Accept", "application/geo+json, application/json")
        .timeout(std::time::Duration::from_secs(30));
    for (k, v) in query {
        req = req.query(k, v);
    }
    req.call()
        .map_err(|e| format!("{url}: {e}"))?
        .into_json::<Value>()
        .map_err(|e| format!("{url}: {e}"))
}

/// Open-Meteo's daily block (fahrenheit, inch): days before `as_of`
/// observed, the rest forecast.
pub fn open_meteo_daily(payload: &Value, as_of: NaiveDate) -> Vec<DailyRecord> {
    let daily = &payload["daily"];
    let at = |key: &str, i: usize| daily[key].get(i).and_then(Value::as_f64);
    daily["time"]
        .as_array()
        .map(|times| {
            times
                .iter()
                .enumerate()
                .filter_map(|(i, t)| {
                    let date = t.as_str()?;
                    let d = NaiveDate::parse_from_str(date, "%Y-%m-%d").ok()?;
                    Some(DailyRecord {
                        date: date.to_string(),
                        kind: if d < as_of { "observed" } else { "forecast" }.to_string(),
                        high_f: at("temperature_2m_max", i),
                        precip_in: at("precipitation_sum", i),
                        snow_in: at("snowfall_sum", i),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

fn open_meteo_city(c: &City, as_of: NaiveDate) -> Result<CityData, String> {
    let payload = fetch(
        OPEN_METEO_BASE,
        &[
            ("latitude", c.lat.to_string()),
            ("longitude", c.lon.to_string()),
            ("daily", "temperature_2m_max,precipitation_sum,snowfall_sum".into()),
            ("temperature_unit", "fahrenheit".into()),
            ("precipitation_unit", "inch".into()),
            ("timezone", c.tz.into()),
            ("past_days", "31".into()),
            ("forecast_days", "16".into()),
        ],
    )?;
    Ok(CityData { daily: Some(open_meteo_daily(&payload, as_of)), climatology: None })
}

/// An NWS gridpoint forecast's maxTemperature (°C), quantitativePrecipitation
/// and snowfallAmount (mm), by the city's local date; all forecast (the NWS
/// serves no past days).
pub fn nws_daily(gridpoint: &Value, tz: Tz) -> Vec<DailyRecord> {
    let props = &gridpoint["properties"];
    let local_date = |valid: &str| -> Option<String> {
        let start = valid.split('/').next()?;
        let t = DateTime::parse_from_rfc3339(&start.replace('Z', "+00:00")).ok()?;
        Some(t.with_timezone(&tz).date_naive().to_string())
    };
    let values = |key: &str| -> Vec<(String, f64)> {
        props[key]["values"]
            .as_array()
            .map(|vs| {
                vs.iter()
                    .filter_map(|v| Some((local_date(v["validTime"].as_str()?)?, v["value"].as_f64()?)))
                    .collect()
            })
            .unwrap_or_default()
    };
    // date -> (high °F, precipitation in, snow in)
    let mut days: BTreeMap<String, (Option<f64>, f64, f64)> = BTreeMap::new();
    for (d, c) in values("maxTemperature") {
        let day = days.entry(d).or_insert((None, 0.0, 0.0));
        let f = c * 9.0 / 5.0 + 32.0;
        day.0 = Some(day.0.map_or(f, |h| h.max(f)));
    }
    for (d, mm) in values("quantitativePrecipitation") {
        days.entry(d).or_insert((None, 0.0, 0.0)).1 += mm / 25.4;
    }
    for (d, mm) in values("snowfallAmount") {
        days.entry(d).or_insert((None, 0.0, 0.0)).2 += mm / 25.4;
    }
    days.into_iter()
        .map(|(date, (high_f, precip, snow))| DailyRecord {
            date,
            kind: "forecast".into(),
            high_f,
            precip_in: Some(precip),
            snow_in: Some(snow),
        })
        .collect()
}

fn nws_city(c: &City) -> Result<CityData, String> {
    let tz: Tz = c.tz.parse().map_err(|e| format!("{}: {e}", c.tz))?;
    let points = fetch(&format!("{NWS_BASE}/points/{},{}", c.lat, c.lon), &[])?;
    let grid = points["properties"]["forecastGridData"]
        .as_str()
        .ok_or_else(|| format!("NWS /points gave no forecastGridData for {}", c.name))?;
    Ok(CityData { daily: Some(nws_daily(&fetch(grid, &[])?, tz)), climatology: None })
}

/// The typed data for every city the rules know, from one source.
pub fn live_data(as_of: NaiveDate, source: Source) -> Result<WeatherData, String> {
    let mut cities = HashMap::new();
    for c in CITIES {
        let data = match source {
            Source::OpenMeteo => open_meteo_city(c, as_of)?,
            Source::Nws => nws_city(c)?,
        };
        cities.insert(c.name.to_string(), data);
    }
    Ok(WeatherData {
        as_of: as_of.to_string(),
        source: Some(source.name().to_string()),
        note: None,
        cities,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn open_meteo_splits_observed_from_forecast() {
        let p = json!({"daily": {"time": ["2026-11-03", "2026-11-04"],
            "temperature_2m_max": [61.0, 64.5], "precipitation_sum": [0.1, null], "snowfall_sum": [0.0, 0.0]}});
        let d = open_meteo_daily(&p, NaiveDate::from_ymd_opt(2026, 11, 4).unwrap());
        assert_eq!(d[0].kind, "observed");
        assert_eq!(d[1].kind, "forecast");
        assert_eq!(d[1].high_f, Some(64.5));
        assert_eq!(d[1].precip_in, None);
    }

    #[test]
    fn nws_takes_the_local_day_and_converts_units() {
        // 03:00Z on the 5th is the evening of the 4th in New York.
        let g = json!({"properties": {
            "maxTemperature": {"values": [
                {"validTime": "2026-11-05T03:00:00+00:00/PT6H", "value": 20.0},
                {"validTime": "2026-11-05T15:00:00+00:00/PT6H", "value": 10.0}]},
            "quantitativePrecipitation": {"values": [{"validTime": "2026-11-05T15:00:00+00:00/PT6H", "value": 25.4}]},
            "snowfallAmount": {"values": []}}});
        let d = nws_daily(&g, "America/New_York".parse().unwrap());
        assert_eq!(d.len(), 2);
        assert_eq!(d[0].date, "2026-11-04");
        assert_eq!(d[0].high_f, Some(68.0));
        assert_eq!(d[1].date, "2026-11-05");
        assert_eq!(d[1].high_f, Some(50.0));
        assert_eq!(d[1].precip_in, Some(1.0));
    }

    #[test]
    fn every_city_has_a_zone() {
        for c in CITIES {
            assert!(c.tz.parse::<Tz>().is_ok(), "{}", c.name);
            assert!(crate::weather::canonical_city(c.name).as_deref() == Some(c.name));
        }
    }
}
