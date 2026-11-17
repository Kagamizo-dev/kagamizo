//! media-prices: OpenRouter's image and video prices, pinned (./lib.rs).
//!
//!   media-prices pin OUT DATE     read the lists and write the pinned file
//!   media-prices check PINNED     read them again; fail, naming each model
//!                                 that differs, if the pin is stale
//!
//! The image models read are the ones the sheets name (MEDIA_MODELS, from
//! Nix). Neither command needs a key or spends anything.
use media_prices::{differences, pin, IMAGES, VIDEOS};
use serde_json::Value;
use std::process::ExitCode;
use std::time::Duration;

fn get(url: &str) -> Result<Value, String> {
    ureq::get(url).timeout(Duration::from_secs(30)).call().map_err(|e| format!("{url}: {e}"))?.into_json().map_err(|e| format!("{url}: {e}"))
}

fn read(date: &str) -> Result<Value, String> {
    let wanted: Vec<String> = serde_json::from_str(include_str!(env!("MEDIA_MODELS"))).map_err(|e| format!("the wanted models do not read: {e}"))?;
    let mut images = Vec::new();
    for model in wanted {
        images.push((model.clone(), get(&IMAGES.replace("<model>", &model))?));
    }
    pin(date, &images, &get(VIDEOS)?)
}

fn run(args: &[&str]) -> Result<bool, String> {
    match args {
        ["pin", out, date] => {
            let text = serde_json::to_string_pretty(&read(date)?).map_err(|e| e.to_string())?;
            std::fs::write(out, text + "\n").map_err(|e| format!("{out}: {e}"))?;
            Ok(true)
        }
        ["check", pinned] => {
            let text = std::fs::read_to_string(pinned).map_err(|e| format!("{pinned}: {e}"))?;
            let old: Value = serde_json::from_str(&text).map_err(|e| format!("{pinned}: {e}"))?;
            let found = differences(&old, &read("now")?);
            for f in &found {
                println!("media-prices: {f}");
            }
            println!("media-prices: pinned {}, {} difference(s)", old["asOf"].as_str().unwrap_or("?"), found.len());
            Ok(found.is_empty())
        }
        _ => Err("usage: media-prices pin OUT DATE | check PINNED".into()),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args.iter().map(String::as_str).collect::<Vec<_>>()) {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(e) => {
            eprintln!("media-prices: {e}");
            ExitCode::FAILURE
        }
    }
}
