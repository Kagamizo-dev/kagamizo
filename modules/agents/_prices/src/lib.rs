//! What OpenRouter charges for an image and for a video, pinned from its
//! own API (the owner's rule, 2026-11-17: every fact from its source of
//! authority, typed, without exception). Reading these lists needs no key
//! and costs nothing.
//!
//!   images   GET /api/v1/images/models/<model>/endpoints, for each model a
//!            sheet names: every provider's price with what is billed and
//!            its unit (an image, a megapixel, an output token), and the
//!            parameters the provider takes
//!   videos   GET /api/v1/videos/models: every model's durations,
//!            resolutions and price codes, as OpenRouter gives them
//!
//! `pin` shapes what was read into the pinned file's form; it is a pure
//! function, so the same answers always give the same bytes. A price is
//! kept twice: as OpenRouter wrote it, and as whole millionths of a dollar
//! for the proofs, which is refused if it would round.
use serde_json::{json, Map, Value};

pub const IMAGES: &str = "https://openrouter.ai/api/v1/images/models/<model>/endpoints";
pub const VIDEOS: &str = "https://openrouter.ai/api/v1/videos/models";

/// Dollars as whole millionths, exactly, or nothing.
pub fn micro(usd: f64) -> Option<u64> {
    let scaled = usd * 1_000_000.0;
    let whole = scaled.round();
    (usd >= 0.0 && (scaled - whole).abs() < 1e-6).then_some(whole as u64)
}

fn image(model: &str, answer: &Value) -> Result<Value, String> {
    let endpoints = answer["endpoints"].as_array().filter(|e| !e.is_empty()).ok_or(format!("{model}: no endpoint"))?;
    let mut out = Vec::new();
    for e in endpoints {
        let provider = e["provider_tag"].as_str().ok_or(format!("{model}: an endpoint has no provider"))?;
        let prices = e["pricing"].as_array().filter(|p| !p.is_empty()).ok_or(format!("{model} at {provider}: no price"))?;
        let mut pinned = Vec::new();
        for p in prices {
            let usd = p["cost_usd"].as_f64().ok_or(format!("{model} at {provider}: a price is not a number"))?;
            let micro = micro(usd).ok_or(format!("{model} at {provider}: {usd} is not whole millionths of a dollar"))?;
            pinned.push(json!({
                "billable": p["billable"].as_str().ok_or(format!("{model} at {provider}: a price bills nothing"))?,
                "unit": p["unit"].as_str().ok_or(format!("{model} at {provider}: a price has no unit"))?,
                "usd": p["cost_usd"],
                "microUsd": micro,
            }));
        }
        out.push(json!({ "provider": provider, "prices": pinned, "parameters": e["supported_parameters"] }));
    }
    out.sort_by(|a, b| a["provider"].as_str().cmp(&b["provider"].as_str()));
    Ok(Value::Array(out))
}

fn video(model: &Value) -> Result<(String, Value), String> {
    let id = model["id"].as_str().ok_or("a video model has no id")?;
    let codes = model["pricing_skus"].as_object().filter(|s| !s.is_empty()).ok_or(format!("{id}: no price code"))?;
    Ok((
        id.to_owned(),
        json!({
            "durations": model["supported_durations"],
            "resolutions": model["supported_resolutions"],
            "aspectRatios": model["supported_aspect_ratios"],
            "audio": model["generate_audio"],
            "priceCodes": codes,
        }),
    ))
}

/// The pinned file, from what was read: each wanted image model's answer,
/// and the video list.
pub fn pin(date: &str, images: &[(String, Value)], videos: &Value) -> Result<Value, String> {
    let mut pinned_images = Map::new();
    for (model, answer) in images {
        pinned_images.insert(model.clone(), image(model, answer)?);
    }
    let mut pinned_videos = Map::new();
    for model in videos["data"].as_array().filter(|d| !d.is_empty()).ok_or("the video list is empty")? {
        let (id, entry) = video(model)?;
        pinned_videos.insert(id, entry);
    }
    Ok(json!({
        "asOf": date,
        "sources": { "images": IMAGES, "videos": VIDEOS },
        "images": pinned_images,
        "videos": pinned_videos,
    }))
}

/// What differs between two pins, by model, leaving their dates aside.
pub fn differences(pinned: &Value, now: &Value) -> Vec<String> {
    let mut out = Vec::new();
    for kind in ["images", "videos"] {
        let (old, new) = (pinned[kind].as_object(), now[kind].as_object());
        let (Some(old), Some(new)) = (old, new) else {
            out.push(format!("{kind}: missing"));
            continue;
        };
        for (model, entry) in old {
            match new.get(model) {
                None => out.push(format!("{kind}: {model} is no longer listed")),
                Some(n) if n != entry => out.push(format!("{kind}: {model} changed")),
                Some(_) => {}
            }
        }
        for model in new.keys().filter(|m| !old.contains_key(*m)) {
            out.push(format!("{kind}: {model} is new"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn answer() -> Value {
        json!({ "id": "m/one", "endpoints": [
            { "provider_tag": "zeta", "pricing": [{ "billable": "output_image", "unit": "image", "cost_usd": 0.08 }], "supported_parameters": { "n": { "type": "range", "min": 1, "max": 6 } } },
            { "provider_tag": "alpha", "pricing": [{ "billable": "output_image", "unit": "megapixel", "cost_usd": 0.03 }], "supported_parameters": {} },
        ] })
    }

    fn videos() -> Value {
        json!({ "data": [{ "id": "v/one", "supported_durations": [4, 8], "supported_resolutions": ["720p"], "supported_aspect_ratios": ["16:9"], "generate_audio": true, "pricing_skus": { "cents_per_second_output": "12" } }] })
    }

    #[test]
    fn a_price_is_kept_as_written_and_as_whole_millionths() {
        let p = pin("2026-11-17", &[("m/one".into(), answer())], &videos()).unwrap();
        let first = &p["images"]["m/one"][0];
        assert_eq!((first["provider"].as_str(), first["prices"][0]["unit"].as_str(), first["prices"][0]["microUsd"].as_u64()), (Some("alpha"), Some("megapixel"), Some(30_000)));
        assert_eq!(p["images"]["m/one"][1]["prices"][0]["microUsd"], 80_000);
        assert_eq!(p["videos"]["v/one"]["priceCodes"]["cents_per_second_output"], "12");
        assert_eq!(p["asOf"], "2026-11-17");
    }

    #[test]
    fn the_same_answers_give_the_same_bytes() {
        let a = pin("d", &[("m/one".into(), answer())], &videos()).unwrap();
        let b = pin("d", &[("m/one".into(), answer())], &videos()).unwrap();
        assert_eq!(serde_json::to_string(&a).unwrap(), serde_json::to_string(&b).unwrap());
    }

    #[test]
    fn a_price_that_would_round_and_an_answer_with_nothing_are_refused() {
        assert_eq!(micro(0.000066), Some(66));
        assert_eq!(micro(0.0000005), None);
        assert_eq!(micro(-1.0), None);
        assert!(pin("d", &[("m/none".into(), json!({ "endpoints": [] }))], &videos()).is_err());
        assert!(pin("d", &[("m/one".into(), answer())], &json!({ "data": [] })).is_err());
        let unpriced = json!({ "endpoints": [{ "provider_tag": "p", "pricing": [] }] });
        assert!(pin("d", &[("m/x".into(), unpriced)], &videos()).is_err());
    }

    #[test]
    fn a_changed_price_a_new_model_and_a_lost_one_are_each_named() {
        let old = pin("a", &[("m/one".into(), answer())], &videos()).unwrap();
        assert_eq!(differences(&old, &pin("b", &[("m/one".into(), answer())], &videos()).unwrap()), Vec::<String>::new());
        let mut dearer = answer();
        dearer["endpoints"][0]["pricing"][0]["cost_usd"] = json!(0.09);
        let mut more = videos();
        more["data"].as_array_mut().unwrap().push(json!({ "id": "v/two", "pricing_skus": { "x": "1" } }));
        let now = pin("b", &[("m/one".into(), dearer)], &more).unwrap();
        assert_eq!(differences(&old, &now), ["images: m/one changed", "videos: v/two is new"]);
        let none = pin("b", &[], &videos()).unwrap();
        assert_eq!(differences(&old, &none), ["images: m/one is no longer listed"]);
    }
}
