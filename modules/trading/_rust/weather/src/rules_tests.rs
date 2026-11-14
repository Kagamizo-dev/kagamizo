//! The ported weather rules' tests (from the first pass), kept beside the replay's.
use crate::data::{self, WeatherData};
use crate::weather;
use data::{month_days, month_number, Question};
use weather::{parse_question, probability, edge, canonical_city, normal_cdf, sigma_f};
use std::collections::HashMap;

/// Load the bundled fixture.
fn load_fixture() -> WeatherData {
    // Try env var first, then look relative to crate root, then current dir
    let path = std::env::var("FIXTURE_PATH").unwrap_or_else(|_| {
        // Try relative to the crate src directory
        let candidates: Vec<String> = vec![
            // relative to cargo run / the crate directory
            "../../_json/forecasts.json".into(),
            "../_json/forecasts.json".into(),
            "_json/forecasts.json".into(),
            "modules/trading/_json/forecasts.json".into(),
        ];
        for c in candidates {
            if std::path::Path::new(&c).exists() {
                return c;
            }
        }
        // Last resort: the path expected when run from crate root
        "../../_json/forecasts.json".into()
    });
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| {
        panic!("cannot read fixture at {}: {}", path, e)
    });
    serde_json::from_str::<WeatherData>(&text).unwrap_or_else(|e| {
        panic!("cannot parse fixture: {}", e)
    })
}

// -----------------------------------------------------------------------
// data module tests
// -----------------------------------------------------------------------

#[test]
fn test_month_days() {
    assert_eq!(month_days(2024, 2), 29);
    assert_eq!(month_days(2025, 2), 28);
    assert_eq!(month_days(2026, 4), 30);
    assert_eq!(month_days(2026, 1), 31);
}

#[test]
fn test_month_number() {
    assert_eq!(month_number("jan"), Some(1));
    assert_eq!(month_number("January"), Some(1));
    assert_eq!(month_number("dec"), Some(12));
    assert_eq!(month_number("sept"), Some(9));
    assert_eq!(month_number("x"), None);
}

#[test]
fn test_struct_creation() {
    let q = Question {
        shape: "high-temp-day".into(),
        city: "New York".into(), variable: "high-temp".into(),
        low: Some(72.0), high: None,
        year: 2026, month: 11, start_day: 6, end_day: 6,
    };
    assert_eq!(q.shape, "high-temp-day");
    assert_eq!(q.city, "New York");
}

// -----------------------------------------------------------------------
// canonical_city tests
// -----------------------------------------------------------------------

#[test]
fn test_canonical_city() {
    assert_eq!(canonical_city("New York"), Some("New York".into()));
    assert_eq!(canonical_city("NYC"), Some("New York".into()));
    assert_eq!(canonical_city("LA"), Some("Los Angeles".into()));
    assert_eq!(canonical_city("Washington DC"), Some("Washington".into()));
    assert_eq!(canonical_city("Narnia"), None);
}

// -----------------------------------------------------------------------
// parse_question tests (mapped from _weather_test.py's Parse class)
// -----------------------------------------------------------------------

#[test]
fn test_parse_high_temp_day() {
    let q1 = parse_question("Highest temperature in New York on Nov 6?", "72° or above", "2026-11-04", None);
    assert!(q1.is_some());
    let q1v = q1.as_ref().unwrap();
    assert_eq!(q1v.shape, "high-temp-day");
    assert_eq!(q1v.city, "New York");
    assert_eq!(q1v.low, Some(72.0));
    assert_eq!(q1v.high, None);
    assert_eq!(q1v.start_day, 6);

    let q2 = parse_question("High temp in NYC on November 6?", "66° to 71°", "2026-11-04", None);
    assert!(q2.is_some());
    assert_eq!(q2.as_ref().unwrap().city, "New York");
    assert_eq!(q2.as_ref().unwrap().low, Some(66.0));
    assert_eq!(q2.as_ref().unwrap().high, Some(71.0));

    let q3 = parse_question("Highest temperature in Chicago on Nov 6?", "65° or below", "2026-11-04", Some("2026-11-07T04:59:00Z"));
    assert!(q3.is_some());
    assert_eq!(q3.as_ref().unwrap().low, None);
    assert_eq!(q3.as_ref().unwrap().high, Some(65.0));
    assert_eq!(q3.as_ref().unwrap().year, 2026);
}

#[test]
fn test_parse_month_totals() {
    let q1 = parse_question("Rain in Chicago in November?", "Above 3 inches", "2026-11-04", None);
    assert!(q1.is_some());
    let q1v = q1.as_ref().unwrap();
    assert_eq!(q1v.shape, "rain-month");
    assert_eq!(q1v.variable, "rain");
    assert_eq!(q1v.low, Some(3.0));
    assert_eq!(q1v.high, None);
    assert_eq!(q1v.start_day, 1);
    assert_eq!(q1v.end_day, 30);

    let q2 = parse_question("Snow in Chicago in December?", "1 to 2 inches", "2026-11-04", None);
    assert!(q2.is_some());
    assert_eq!(q2.as_ref().unwrap().shape, "snow-month");
    assert_eq!(q2.as_ref().unwrap().low, Some(1.0));
    assert_eq!(q2.as_ref().unwrap().high, Some(2.0));
    assert_eq!(q2.as_ref().unwrap().year, 2026);

    let q3 = parse_question("Rain in Miami in January?", "Below 1 inch", "2026-11-04", None);
    assert!(q3.is_some());
    assert_eq!(q3.as_ref().unwrap().high, Some(1.0));
    assert_eq!(q3.as_ref().unwrap().year, 2027);
}

#[test]
fn test_unknown_shapes_are_none() {
    assert!(parse_question("Where will it rain this weekend?", "New York", "2026-11-04", None).is_none());
    assert!(parse_question("Rain in Narnia in November?", "Above 1 inch", "2026-11-04", None).is_none());
    assert!(parse_question("Rain in Chicago in November?", "A lot", "2026-11-04", None).is_none());
    assert!(parse_question("Highest temperature in New York on Nov 31?", "72° or above", "2026-11-04", None).is_none());
    assert!(parse_question("Hurricane landfall in Florida in 2026?", "Yes", "2026-11-04", None).is_none());
}

// -----------------------------------------------------------------------
// probability tests (mapped from _weather_test.py's Probability class)
// -----------------------------------------------------------------------

#[test]
fn test_high_temp_bands_sum_to_one() {
    let data = load_fixture();
    let q_above = parse_question("Highest temperature in New York on Nov 6?", "72° or above", "2026-11-04", None).unwrap();
    let q_mid = parse_question("Highest temperature in New York on Nov 6?", "66° to 71°", "2026-11-04", None).unwrap();
    let q_below = parse_question("Highest temperature in New York on Nov 6?", "65° or below", "2026-11-04", None).unwrap();
    let above = probability(&q_above, &data, "2026-11-04");
    let mid = probability(&q_mid, &data, "2026-11-04");
    let below = probability(&q_below, &data, "2026-11-04");
    assert!(above.is_some() && mid.is_some() && below.is_some());
    let sum = above.unwrap() + mid.unwrap() + below.unwrap();
    assert!((sum - 1.0).abs() < 0.001);
    assert!(above.unwrap() > 0.9);
}

#[test]
fn test_observed_day_is_certain() {
    let data = load_fixture();
    let q60 = parse_question("Highest temperature in New York on Nov 2?", "60° or above", "2026-11-04", None).unwrap();
    let q62 = parse_question("Highest temperature in New York on Nov 2?", "62° or above", "2026-11-04", None).unwrap();
    let p60 = probability(&q60, &data, "2026-11-04");
    let p62 = probability(&q62, &data, "2026-11-04");
    assert_eq!(p60, Some(1.0));
    assert_eq!(p62, Some(0.0));
}

#[test]
fn test_month_total_near_its_price() {
    let data = load_fixture();
    let q = parse_question("Rain in Chicago in November?", "Above 3 inches", "2026-11-04", None).unwrap();
    let p = probability(&q, &data, "2026-11-04");
    assert!(p.is_some());
    let pv = p.unwrap();
    assert!(pv > 0.5 && pv < 0.65);
}

#[test]
fn test_none_without_data() {
    let data = load_fixture();
    let q = parse_question("Highest temperature in Miami on Nov 6?", "80° or above", "2026-11-04", None).unwrap();
    assert!(probability(&q, &data, "2026-11-04").is_none());
    let q2 = parse_question("Highest temperature in New York on Nov 20?", "50° or above", "2026-11-04", None).unwrap();
    assert!(probability(&q2, &data, "2026-11-04").is_none());
}

#[test]
fn test_none_without_climatology() {
    let data = load_fixture();
    // Remove climatology from Chicago
    let mut new_cities: HashMap<String, data::CityData> = HashMap::new();
    for item in data.cities.iter() {
        let (name, cd) = item;
        if name == "Chicago" {
            let mut cd2 = cd.clone();
            cd2.climatology = None;
            new_cities.insert(name.clone(), cd2);
        } else {
            new_cities.insert(name.clone(), cd.clone());
        }
    }
    let mut data2 = data.clone();
    data2.cities = new_cities;
    let q = parse_question("Rain in Chicago in November?", "Above 3 inches", "2026-11-04", None).unwrap();
    assert!(probability(&q, &data2, "2026-11-04").is_none());
}

#[test]
fn test_edge() {
    assert!((edge(0.75, 0.20) - 0.55).abs() < 0.0001);
    assert!((edge(0.2, 0.25) + 0.05).abs() < 0.0001);
}

#[test]
fn test_normal_cdf() {
    assert!((normal_cdf(0.0, 0.0, 1.0) - 0.5).abs() < 0.01);
}

#[test]
fn test_sigma_f() {
    assert_eq!(sigma_f(0), 2.5);
    assert_eq!(sigma_f(6), 7.0);
}
