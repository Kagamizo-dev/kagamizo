//! Weather signal engine ported from modules/trading/_weather.py.
use crate::data::{WeatherData, CityData, Question, month_number, month_days, DailyRecord};
use std::collections::HashMap;

// ---------------------------------------------------------------------------
// Normal CDF
// ---------------------------------------------------------------------------

/// The normal distribution's CDF, through the error function exactly as
/// _weather.py computes it (math.erf; libm's erf is the same function).
pub fn normal_cdf(x: f64, mu: f64, sigma: f64) -> f64 {
    if sigma <= 0.0 {
        return if x >= mu { 1.0 } else { 0.0 };
    }
    0.5 * (1.0 + libm::erf((x - mu) / (sigma * std::f64::consts::SQRT_2)))
}

pub fn band_probability(mu: f64, sigma: f64, low: Option<f64>, high: Option<f64>) -> f64 {
    let upper = if high.is_some() { normal_cdf(high.unwrap(), mu, sigma) } else { 1.0 };
    let lower = if low.is_some() { normal_cdf(low.unwrap(), mu, sigma) } else { 0.0 };
    (upper - lower).max(0.0).min(1.0)
}

pub fn sigma_f(lead_days: i32) -> f64 {
    let raw = 2.5 + 0.75 * (0.max(lead_days) as f64);
    raw.min(7.0)
}

pub fn forecast_precip_sd(amount: f64) -> f64 {
    0.6 * amount + 0.03
}

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------

pub fn days_between(from: &str, to: &str) -> i32 {
    fn jday(iso: &str) -> i32 {
        let s = iso.chars().take(10).collect::<String>();
        let y = s.chars().take(4).collect::<String>().parse::<i32>().ok().unwrap_or(0);
        let m = s.chars().skip(5).take(2).collect::<String>().parse::<u32>().ok().unwrap_or(0);
        let d = s.chars().skip(8).take(2).collect::<String>().parse::<u32>().ok().unwrap_or(0);
        (y - 2000) * 365 + (y - 2000) / 4 + mo(m) + d as i32
    }
    fn mo(m: u32) -> i32 {
        match m { 1 => 0, 2 => 31, 3 => 59, 4 => 90, 5 => 120, 6 => 151,
            7 => 181, 8 => 212, 9 => 243, 10 => 273, 11 => 304, 12 => 334, _ => 0 }
    }
    jday(to) - jday(from)
}

pub fn date_key(year: i32, month: u32, day: u32) -> String {
    format!("{}-{:02}-{:02}", year, month, day)
}

// ---------------------------------------------------------------------------
// City matching
// ---------------------------------------------------------------------------

pub fn canonical_city(name: &str) -> Option<String> {
    let t = name.trim_end_matches("?").trim();
    // Simple if-chain avoids Vec<(String, Vec<String>)> issues
    fn check(city: &str, aliases: Vec<String>, name: &str) -> Option<String> {
        if name.eq_ignore_ascii_case(city) { return Some(city.to_string()); }
        for a in aliases {
            if name.eq_ignore_ascii_case(&a) { return Some(city.to_string()); }
        }
        None
    }
    let r = check("New York", vec!["NYC".to_string(), "New York City".to_string()], &t).or_else(||
        check("Chicago", vec![], &t)).or_else(||
        check("Miami", vec![], &t)).or_else(||
        check("Austin", vec![], &t)).or_else(||
        check("Los Angeles", vec!["LA".to_string()], &t)).or_else(||
        check("Denver", vec![], &t)).or_else(||
        check("Philadelphia", vec!["Philly".to_string()], &t)).or_else(||
        check("Seattle", vec![], &t)).or_else(||
        check("Boston", vec![], &t)).or_else(||
        check("Atlanta", vec![], &t)).or_else(||
        check("Houston", vec![], &t)).or_else(||
        check("Dallas", vec!["Dallas-Fort Worth".to_string()], &t)).or_else(||
        check("Washington", vec!["Washington DC".to_string(), "Washington, DC".to_string(), "DC".to_string()], &t)).or_else(||
        check("Phoenix", vec![], &t)).or_else(||
        check("Las Vegas", vec![], &t)).or_else(||
        check("Minneapolis", vec![], &t)).or_else(||
        check("San Francisco", vec!["SF".to_string()], &t));
    r
}

fn year_for(month: u32, as_of: &str, resolution_time: Option<&str>) -> i32 {
    if let Some(rt) = resolution_time {
        let ys = rt.chars().take(4).collect::<String>();
        return ys.parse::<i32>().ok().unwrap_or(2026);
    }
    let ys = as_of.chars().take(4).collect::<String>();
    let ms = as_of.chars().skip(5).take(2).collect::<String>();
    let y = ys.parse::<i32>().ok().unwrap_or(2026);
    let m = ms.parse::<u32>().ok().unwrap_or(1);
    y + (if month < m { 1 } else { 0 })
}

// ---------------------------------------------------------------------------
// Band parsing
// ---------------------------------------------------------------------------

fn extract_number(s: &str) -> Option<f64> {
    let mut acc = String::new();
    let mut dots = 0;
    for c in s.chars() {
        if c.is_digit(10) { acc.push(c); }
        else if c == '.' && dots == 0 { acc.push('.'); dots = 1; }
        else if c == '-' && acc.is_empty() { acc.push('-'); }
        else if acc.is_empty() { continue; }
        else { break; }
    }
    if acc.is_empty() { None } else { acc.parse::<f64>().ok() }
}

fn parse_temp_band(outcome: &str) -> Option<(Option<f64>, Option<f64>)> {
    let t = outcome.trim();
    let lower = t.to_lowercase();
    let cleaned = lower.replace("°", "").replace("deg", "").replace("f", "");

    if cleaned.contains(" or above") || cleaned.contains(" or higher") || cleaned.contains(" or more") {
        let before = cleaned.split(" or ").next().unwrap_or("");
        let v = extract_number(&before);
        if v.is_some() { return Some((Some(v.unwrap()), None)); }
    }
    if cleaned.contains(" or below") || cleaned.contains(" or lower") || cleaned.contains(" or less") {
        let before = cleaned.split(" or ").next().unwrap_or("");
        let v = extract_number(&before);
        if v.is_some() { return Some((None, Some(v.unwrap()))); }
    }
    if cleaned.contains(" to ") {
        let parts = cleaned.split(" to ").collect::<Vec<_>>();
        if parts.len() >= 2 {
            let lo = extract_number(parts[0]);
            let hi = extract_number(parts[1]);
            if lo.is_some() && hi.is_some() && lo.unwrap() <= hi.unwrap() {
                return Some((lo, hi));
            }
        }
    }
    None
}

fn parse_precip_band(outcome: &str) -> Option<(Option<f64>, Option<f64>)> {
    let t = outcome.trim();
    let lower = t.to_lowercase();

    for prefix in ["above ", "over ", "more than "] {
        if lower.starts_with(prefix) {
            let rest = &lower[prefix.len()..];
            let v = extract_number(rest);
            if v.is_some() { return Some((Some(v.unwrap()), None)); }
        }
    }
    if lower.contains(" or more") || lower.contains(" or above") {
        let before = lower.split(" or ").next().unwrap_or("");
        let v = extract_number(&before);
        if v.is_some() { return Some((Some(v.unwrap()), None)); }
    }
    for prefix in ["below ", "under ", "less than "] {
        if lower.starts_with(prefix) {
            let rest = &lower[prefix.len()..];
            let v = extract_number(rest);
            if v.is_some() { return Some((None, Some(v.unwrap()))); }
        }
    }
    if lower.contains(" to ") {
        let parts = lower.split(" to ").collect::<Vec<_>>();
        if parts.len() >= 2 {
            let lo = extract_number(parts[0]);
            let hi = extract_number(parts[1]);
            if lo.is_some() && hi.is_some() && lo.unwrap() <= hi.unwrap() {
                return Some((lo, hi));
            }
        }
    }
    None
}

fn parse_band(outcome: &str) -> Option<(Option<f64>, Option<f64>)> {
    let lower = outcome.trim().to_lowercase();
    if lower.contains("inch") || lower.contains("\"") {
        parse_precip_band(outcome)
    } else {
        parse_temp_band(outcome)
    }
}

// ---------------------------------------------------------------------------
// Question parsing
// ---------------------------------------------------------------------------

pub fn parse_question(
    event_title: &str,
    outcome_title: &str,
    as_of: &str,
    resolution_time: Option<&str>,
) -> Option<Question> {
    let et = event_title.trim().trim_end_matches("?").trim();
    let lower = et.to_lowercase();

    // ---- Month event ----
    let mut variable: Option<String> = None;
    if lower.starts_with("rain") || lower.starts_with("rainfall") { variable = Some("rain".into()); }
    else if lower.starts_with("snow") || lower.starts_with("snowfall") { variable = Some("snow".into()); }

    if variable.is_some() {
        let v = variable.unwrap();
        let after_var = &et[v.len()..].trim();
        if !after_var.to_lowercase().starts_with("in ") { return None; }
        let rest = &after_var[3..].trim();
        let in_pos_opt = rest.to_lowercase().find(" in ");
        if in_pos_opt.is_none() { return None; }
        let in_pos = in_pos_opt.unwrap();
        if in_pos >= rest.len() { return None; }
        let city_raw = rest[..in_pos].trim();
        let after_city = &rest[(in_pos + 4)..].trim();
        let words = after_city.split_whitespace().collect::<Vec<_>>();
        if words.is_empty() { return None; }
        let month_name = words[0].trim_end_matches("?").trim_end_matches(".").trim_end_matches(",");
        let year_str = if words.len() > 1 { Some(words[1].trim_end_matches("?").trim_end_matches(".")) } else { None };

        let city = canonical_city(city_raw);
        if city.is_none() { return None; }
        let mn = month_number(month_name);
        if mn.is_none() { return None; }
        let band = parse_band(outcome_title);
        if band.is_none() { return None; }
        let (low, high) = band.unwrap();
        let m = mn.unwrap();
        let y = if let Some(ys) = year_str {
            let parsed = ys.parse::<i32>().ok();
            if parsed.is_some() { parsed.unwrap() } else { year_for(m, as_of, resolution_time) }
        } else { year_for(m, as_of, resolution_time) };
        let days = month_days(y, m);
        return Some(Question {
            shape: format!("{}-month", v), city: city.unwrap(), variable: v,
            low, high, year: y, month: m, start_day: 1, end_day: days,
        });
    }

    // ---- Day event ----
    for prefix in ["highest temperature", "high temp", "highest temp"] {
        if lower.starts_with(prefix) {
            let after = &et[prefix.len()..].trim();
            if !after.to_lowercase().starts_with("in ") { continue; }
            let rest = &after[3..].trim();
            let on_pos_opt = rest.to_lowercase().find(" on ");
            if on_pos_opt.is_none() { return None; }
            let on_pos = on_pos_opt.unwrap();
            if on_pos >= rest.len() { return None; }
            let city_raw = rest[..on_pos].trim();
            let after_on = &rest[(on_pos + 4)..].trim();
            let words = after_on.split_whitespace().collect::<Vec<_>>();
            if words.len() < 2 { return None; }
            let month_name = words[0].trim_end_matches(".").trim_end_matches(",");
            let day_str = words[1].trim_end_matches(",").trim_end_matches(".").trim_end_matches("?");
            let year_str = if words.len() > 2 { Some(words[2].trim_end_matches(".").trim_end_matches(",").trim_end_matches("?")) } else { None };

            let city = canonical_city(city_raw);
            if city.is_none() { return None; }
            let mn = month_number(month_name);
            if mn.is_none() { return None; }
            let day = day_str.parse::<u32>().ok();
            if day.is_none() { return None; }
            let d = day.unwrap();
            let band = parse_band(outcome_title);
            if band.is_none() { return None; }
            let (low, high) = band.unwrap();
            let m = mn.unwrap();
            let y = if let Some(ys) = year_str {
                let parsed = ys.parse::<i32>().ok();
                if parsed.is_some() { parsed.unwrap() } else { year_for(m, as_of, resolution_time) }
            } else { year_for(m, as_of, resolution_time) };
            if d > month_days(y, m) { return None; }
            return Some(Question {
                shape: "high-temp-day".into(), city: city.unwrap(), variable: "high-temp".into(),
                low, high, year: y, month: m, start_day: d, end_day: d,
            });
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Probability
// ---------------------------------------------------------------------------

fn daily_by_date(cd: &CityData) -> HashMap<String, &DailyRecord> {
    let mut m: HashMap<String, &DailyRecord> = HashMap::new();
    if cd.daily.is_some() {
        let daily = cd.daily.as_ref().unwrap();
        for d in daily {
            let dk = d.date.chars().take(10).collect::<String>();
            m.insert(dk, d);
        }
    }
    m
}

pub fn probability(question: &Question, data: &WeatherData, as_of: &str) -> Option<f64> {
    let city_entry = data.cities.get(&question.city);
    if city_entry.is_none() { return None; }
    let cd = city_entry.unwrap();
    let daily = daily_by_date(cd);

    if question.shape == "high-temp-day" {
        let dk = date_key(question.year, question.month, question.start_day);
        let d = daily.get(&dk);
        if d.is_none() { return None; }
        let rec = d.unwrap();
        if rec.high_f.is_none() { return None; }
        let sigma = if rec.kind == "observed" { 0.0 } else {
            let lead = days_between(as_of, &dk);
            sigma_f(lead)
        };
        let low = if question.low.is_some() { Some(question.low.unwrap() - 0.5) } else { None };
        let high = if question.high.is_some() { Some(question.high.unwrap() + 0.5) } else { None };
        Some(band_probability(rec.high_f.unwrap(), sigma, low, high))
    } else {
        let key = if question.variable == "rain" { "precip_in" } else { "snow_in" };
        let clim = if cd.climatology.is_some() {
            let cl_map = cd.climatology.as_ref().unwrap();
            let mk = format!("{}", question.month);
            cl_map.get(&mk)
        } else { None };

        let mut mu = 0.0f64;
        let mut var = 0.0f64;
        for day_num in question.start_day..=question.end_day {
            let dk = date_key(question.year, question.month, day_num);
            let d = daily.get(&dk);
            if d.is_some() {
                let rec = d.unwrap();
                let amount = if key == "precip_in" { rec.precip_in } else { rec.snow_in };
                if let Some(a) = amount {
                    mu += a;
                    if rec.kind != "observed" {
                        let sd = forecast_precip_sd(a);
                        var += sd * sd;
                    }
                    continue;
                }
            }
            if clim.is_none() { return None; }
            let c = clim.unwrap();
            let (mean, sd) = if key == "precip_in" {
                (c.precip_in_per_day_mean, c.precip_in_per_day_sd)
            } else {
                (c.snow_in_per_day_mean, c.snow_in_per_day_sd)
            };
            if mean.is_none() || sd.is_none() { return None; }
            mu += mean.unwrap();
            var += sd.unwrap() * sd.unwrap();
        }
        Some(band_probability(mu, var.sqrt(), question.low, question.high))
    }
}

// ---------------------------------------------------------------------------
// Edge
// ---------------------------------------------------------------------------

/// What the rules say the contract is worth over what it costs, as a
/// probability, to four places as _weather.py's `round(p - price, 4)`.
pub fn edge(prob: f64, price: f64) -> f64 {
    round_to(prob - price, 4)
}

/// Python's round(x, places): the float's exact decimal value, ties to even,
/// which is how Rust formats a float to a precision.
pub fn round_to(x: f64, places: usize) -> f64 {
    format!("{x:.places$}").parse().unwrap_or(x)
}