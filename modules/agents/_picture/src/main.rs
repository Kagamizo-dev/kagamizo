//! picture: the harness around an image model (../sheets.nix). A unit of
//! work never calls a model's API itself: it names a sheet, and this tool
//! makes the one call the sheet allows, holds the answer to the sheet's
//! time, cost and format, and publishes what passes.
//!
//!   picture SHEET --prompt-file FILE --out DIR [--ref IMAGE]... [--n N]
//!           [--aspect RATIO]
//!
//! The call is OpenRouter's `POST /api/v1/images`, as its own OpenAPI states
//! it (../_json/openrouter-images.json): model, prompt, n, aspect_ratio,
//! output_format and input_references in; data[].b64_json with a media type
//! and usage.cost out. The key is read from OPENROUTER_API_KEY and is never
//! printed; errors name their kind, never a header.
//!
//! What is published: each image as `<sha256>.<ext>` in DIR, and
//! `manifest.json` naming the sheet, the model, the prompt's hash, every
//! file's hash and size, the seconds the call took and what it cost. A run
//! that reports no cost, costs more than the sheet allows, or returns
//! anything but the sheet's kind of output publishes nothing.
use base64::Engine;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{Duration, Instant};

const SHEETS: &str = include_str!(env!("PICTURE_SHEETS"));

/// The most references OpenRouter's schema takes (`maxItems`).
const MAX_REFERENCES: usize = 16;

type R<T> = Result<T, String>;

#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Sheet {
    pub host: String,
    pub endpoint: String,
    pub model: String,
    /// What the model must return: `image` (raster) or `svg`.
    pub output: String,
    pub max_seconds: u64,
    pub max_cents: u64,
}

pub fn sheets() -> std::collections::BTreeMap<String, Sheet> {
    serde_json::from_str(SHEETS).expect("the sheets are rendered by sheets.nix")
}

pub struct Ask {
    pub prompt: String,
    pub references: Vec<Vec<u8>>,
    pub n: u64,
    pub aspect: Option<String>,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Published {
    pub name: String,
    pub sha256: String,
    pub bytes: usize,
    pub media_type: String,
}

#[derive(Serialize, Debug)]
pub struct Manifest {
    pub sheet: String,
    pub model: String,
    pub prompt_sha256: String,
    pub seconds: u64,
    pub cents: u64,
    pub files: Vec<Published>,
}

pub fn hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

/// A raster image's media type and extension, by its first bytes.
pub fn raster(bytes: &[u8]) -> Option<(&'static str, &'static str)> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some(("image/png", "png"))
    } else if bytes.starts_with(b"\xff\xd8\xff") {
        Some(("image/jpeg", "jpg"))
    } else if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some(("image/webp", "webp"))
    } else {
        None
    }
}

/// A drawing is SVG markup that holds no embedded raster and loads nothing.
pub fn drawing(bytes: &[u8]) -> R<()> {
    let text = std::str::from_utf8(bytes).map_err(|_| "the drawing is not text".to_string())?;
    let lower = text.to_ascii_lowercase();
    if !lower.contains("<svg") {
        return Err("the drawing is not SVG".into());
    }
    for banned in ["<image", "data:", "<script", "<foreignobject", "href=\"http", "href='http"] {
        if lower.contains(banned) {
            return Err(format!("the drawing holds `{banned}`"));
        }
    }
    Ok(())
}

/// Hold one returned item to the sheet's kind of output.
pub fn admit(sheet: &Sheet, bytes: &[u8]) -> R<(&'static str, &'static str)> {
    match sheet.output.as_str() {
        "svg" => drawing(bytes).map(|()| ("image/svg+xml", "svg")),
        "image" => raster(bytes).ok_or_else(|| "the output is not a PNG, JPEG or WebP image".to_string()),
        other => Err(format!("no harness for `{other}` output")),
    }
}

/// Dollars as OpenRouter reports them, in whole cents, rounded up.
pub fn cents(usd: f64) -> u64 {
    (usd * 100.0 - 1e-9).ceil().max(0.0) as u64
}

fn reference(bytes: &[u8]) -> R<serde_json::Value> {
    let (media, _) = raster(bytes).ok_or("a reference is not a PNG, JPEG or WebP image")?;
    let b64 = base64::engine::general_purpose::STANDARD.encode(bytes);
    Ok(serde_json::json!({ "type": "image_url", "image_url": { "url": format!("data:{media};base64,{b64}") } }))
}

pub fn body(sheet: &Sheet, ask: &Ask) -> R<serde_json::Value> {
    if ask.prompt.trim().is_empty() {
        return Err("the prompt is empty".into());
    }
    if ask.n == 0 {
        return Err("n is zero".into());
    }
    if ask.references.len() > MAX_REFERENCES {
        return Err(format!("more than {MAX_REFERENCES} references"));
    }
    let mut body = serde_json::json!({ "model": sheet.model, "prompt": ask.prompt, "n": ask.n });
    if sheet.output == "svg" {
        body["output_format"] = "svg".into();
    }
    if let Some(a) = &ask.aspect {
        body["aspect_ratio"] = a.clone().into();
    }
    if !ask.references.is_empty() {
        body["input_references"] = ask.references.iter().map(|r| reference(r)).collect::<R<Vec<_>>>()?.into();
    }
    Ok(body)
}

/// Make the one call, and return what passes with what it took and cost.
/// `base` is `https://<host>` except under test.
pub fn generate(name: &str, sheet: &Sheet, ask: &Ask, base: &str, key: &str) -> R<(Manifest, Vec<Vec<u8>>)> {
    let request = body(sheet, ask)?;
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(sheet.max_seconds)).build();
    let started = Instant::now();
    let answer: serde_json::Value = match agent
        .post(&format!("{base}{}", sheet.endpoint))
        .set("Authorization", &format!("Bearer {key}"))
        .send_json(request)
    {
        Ok(r) => r.into_json().map_err(|_| "the answer is not JSON".to_string())?,
        Err(ureq::Error::Status(code, _)) => return Err(format!("HTTP {code}")),
        // By kind only: the message can quote the Authorization header.
        Err(ureq::Error::Transport(t)) => return Err(format!("transport error ({:?}) within {} s", t.kind(), sheet.max_seconds)),
    };
    let seconds = started.elapsed().as_secs();
    if seconds > sheet.max_seconds {
        return Err(format!("took {seconds} s, over the sheet's {} s", sheet.max_seconds));
    }
    let usd = answer["usage"]["cost"].as_f64().ok_or("the answer reports no cost, so it cannot be held to the sheet's")?;
    let spent = cents(usd);
    let allowed = sheet.max_cents * ask.n;
    if spent > allowed {
        return Err(format!("cost {spent} cents, over the sheet's {allowed} for {} image(s)", ask.n));
    }
    let items = answer["data"].as_array().filter(|a| !a.is_empty()).ok_or("the answer holds no image")?;
    let mut files = Vec::new();
    let mut blobs = Vec::new();
    for item in items {
        let b64 = item["b64_json"].as_str().ok_or("an item holds no image data")?;
        let bytes = base64::engine::general_purpose::STANDARD.decode(b64).map_err(|_| "an item is not base64".to_string())?;
        let (media_type, ext) = admit(sheet, &bytes)?;
        let sha256 = hex(&bytes);
        files.push(Published { name: format!("{sha256}.{ext}"), sha256, bytes: bytes.len(), media_type: media_type.into() });
        blobs.push(bytes);
    }
    let manifest = Manifest {
        sheet: name.into(),
        model: sheet.model.clone(),
        prompt_sha256: hex(ask.prompt.as_bytes()),
        seconds,
        cents: spent,
        files,
    };
    Ok((manifest, blobs))
}

/// Write every file, then the manifest: a directory with a manifest is whole.
pub fn publish(dir: &Path, manifest: &Manifest, blobs: &[Vec<u8>]) -> R<()> {
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    for (file, bytes) in manifest.files.iter().zip(blobs) {
        std::fs::write(dir.join(&file.name), bytes).map_err(|e| format!("{}: {e}", file.name))?;
    }
    let text = serde_json::to_string_pretty(manifest).map_err(|e| e.to_string())?;
    std::fs::write(dir.join("manifest.json"), text).map_err(|e| format!("manifest.json: {e}"))
}

fn run(args: &[String]) -> R<()> {
    let usage = "picture SHEET --prompt-file FILE --out DIR [--ref IMAGE]... [--n N] [--aspect RATIO]";
    let mut it = args.iter();
    let name = it.next().ok_or(usage)?;
    let all = sheets();
    let sheet = all
        .get(name)
        .ok_or_else(|| format!("no sheet `{name}`; declared: {}", all.keys().cloned().collect::<Vec<_>>().join(", ")))?;
    let (mut prompt, mut out, mut references, mut n, mut aspect) = (None, None, Vec::new(), 1u64, None);
    while let Some(flag) = it.next() {
        let mut value = || it.next().ok_or_else(|| format!("{flag} needs a value"));
        match flag.as_str() {
            "--prompt-file" => prompt = Some(std::fs::read_to_string(value()?).map_err(|e| format!("the prompt: {e}"))?),
            "--out" => out = Some(PathBuf::from(value()?)),
            "--ref" => references.push(std::fs::read(value()?).map_err(|e| format!("a reference: {e}"))?),
            "--n" => n = value()?.parse().map_err(|_| "--n is not a number".to_string())?,
            "--aspect" => aspect = Some(value()?.clone()),
            other => return Err(format!("unknown argument `{other}`\n{usage}")),
        }
    }
    let ask = Ask { prompt: prompt.ok_or(usage)?, references, n, aspect };
    let out = out.ok_or(usage)?;
    let key = std::env::var("OPENROUTER_API_KEY").map_err(|_| "OPENROUTER_API_KEY is not set (run under secretspec)".to_string())?;
    let (manifest, blobs) = generate(name, sheet, &ask, &format!("https://{}", sheet.host), &key)?;
    publish(&out, &manifest, &blobs)?;
    for f in &manifest.files {
        println!("{}  {} bytes  {}", f.name, f.bytes, f.media_type);
    }
    println!("{} s, {} cents, sheet {name} ({})", manifest.seconds, manifest.cents, manifest.model);
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("picture: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    const PNG: &[u8] = b"\x89PNG\r\n\x1a\nrest-of-a-picture";

    fn sheet(output: &str) -> Sheet {
        Sheet { host: "example.invalid".into(), endpoint: "/api/v1/images".into(), model: "maker/model".into(), output: output.into(), max_seconds: 5, max_cents: 10 }
    }

    fn ask() -> Ask {
        Ask { prompt: "a vest with four pockets".into(), references: vec![], n: 1, aspect: None }
    }

    /// One answer from a local stand-in for the endpoint; returns its base
    /// address and, once the call is made, the request it received.
    fn stub(answer: serde_json::Value) -> (String, std::thread::JoinHandle<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let handle = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut seen = Vec::new();
            let mut buf = [0u8; 4096];
            loop {
                let n = stream.read(&mut buf).unwrap();
                seen.extend_from_slice(&buf[..n]);
                let text = String::from_utf8_lossy(&seen).to_string();
                if let Some(head) = text.find("\r\n\r\n") {
                    let length: usize = text[..head]
                        .lines()
                        .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse().unwrap()))
                        .unwrap_or(0);
                    if seen.len() >= head + 4 + length || n == 0 {
                        break;
                    }
                }
            }
            let body = answer.to_string();
            write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
            String::from_utf8_lossy(&seen).to_string()
        });
        (base, handle)
    }

    fn b64(bytes: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    #[test]
    fn every_declared_sheet_has_a_harness() {
        for (name, s) in sheets() {
            assert!(matches!(s.output.as_str(), "image" | "svg"), "{name}: no harness for {}", s.output);
            assert_eq!(s.endpoint, "/api/v1/images", "{name}");
            assert!(s.max_seconds > 0 && s.max_cents > 0, "{name}");
        }
    }

    #[test]
    fn rasters_are_told_by_their_first_bytes() {
        assert_eq!(raster(PNG), Some(("image/png", "png")));
        assert_eq!(raster(b"\xff\xd8\xff\xe0jfif"), Some(("image/jpeg", "jpg")));
        assert_eq!(raster(b"RIFF\x00\x00\x00\x00WEBPVP8 "), Some(("image/webp", "webp")));
        assert_eq!(raster(b"<svg/>"), None);
        assert_eq!(raster(b""), None);
    }

    #[test]
    fn a_drawing_holds_no_raster_and_loads_nothing() {
        assert!(drawing(b"<svg xmlns='http://www.w3.org/2000/svg'><path d='M0 0'/></svg>").is_ok());
        assert!(drawing(b"<svg><image href='x.png'/></svg>").is_err());
        assert!(drawing(b"<svg><rect fill='url(data:image/png;base64,AA)'/></svg>").is_err());
        assert!(drawing(b"<svg><script>1</script></svg>").is_err());
        assert!(drawing(PNG).is_err());
    }

    #[test]
    fn cents_round_up() {
        assert_eq!(cents(0.0), 0);
        assert_eq!(cents(0.04), 4);
        assert_eq!(cents(0.041), 5);
        assert_eq!(cents(0.10), 10);
    }

    #[test]
    fn the_request_is_the_schema_s() {
        let mut a = ask();
        a.references.push(PNG.to_vec());
        a.aspect = Some("3:4".into());
        let b = body(&sheet("image"), &a).unwrap();
        assert_eq!(b["model"], "maker/model");
        assert_eq!(b["n"], 1);
        assert_eq!(b["aspect_ratio"], "3:4");
        assert_eq!(b["input_references"][0]["type"], "image_url");
        assert!(b["input_references"][0]["image_url"]["url"].as_str().unwrap().starts_with("data:image/png;base64,"));
        assert!(b.get("output_format").is_none());
        assert_eq!(body(&sheet("svg"), &ask()).unwrap()["output_format"], "svg");
        a.references = vec![PNG.to_vec(); 17];
        assert!(body(&sheet("image"), &a).is_err());
        a.references = vec![b"not a picture".to_vec()];
        assert!(body(&sheet("image"), &a).is_err());
    }

    #[test]
    fn a_passing_run_is_published_whole() {
        let (base, seen) = stub(serde_json::json!({ "data": [{ "b64_json": b64(PNG), "media_type": "image/png" }], "usage": { "cost": 0.04 } }));
        let (manifest, blobs) = generate("concept-image", &sheet("image"), &ask(), &base, "the-key").unwrap();
        let request = seen.join().unwrap();
        assert!(request.starts_with("POST /api/v1/images "));
        assert!(request.to_ascii_lowercase().contains("authorization: bearer the-key"));
        assert_eq!(manifest.cents, 4);
        assert_eq!(manifest.files[0].sha256, hex(PNG));
        assert_eq!(manifest.files[0].name, format!("{}.png", hex(PNG)));
        let dir = std::env::temp_dir().join(format!("picture-test-{}", std::process::id()));
        publish(&dir, &manifest, &blobs).unwrap();
        assert_eq!(std::fs::read(dir.join(&manifest.files[0].name)).unwrap(), PNG);
        let written: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(dir.join("manifest.json")).unwrap()).unwrap();
        assert_eq!(written["sheet"], "concept-image");
        assert_eq!(written["prompt_sha256"], hex(b"a vest with four pockets"));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_run_over_its_cost_publishes_nothing() {
        let (base, seen) = stub(serde_json::json!({ "data": [{ "b64_json": b64(PNG) }], "usage": { "cost": 0.11 } }));
        let err = generate("concept-image", &sheet("image"), &ask(), &base, "k").unwrap_err();
        seen.join().unwrap();
        assert!(err.contains("over the sheet's 10"), "{err}");
    }

    #[test]
    fn a_run_with_no_cost_publishes_nothing() {
        let (base, seen) = stub(serde_json::json!({ "data": [{ "b64_json": b64(PNG) }], "usage": { "cost": null } }));
        let err = generate("concept-image", &sheet("image"), &ask(), &base, "k").unwrap_err();
        seen.join().unwrap();
        assert!(err.contains("no cost"), "{err}");
    }

    #[test]
    fn the_wrong_kind_of_output_publishes_nothing() {
        let (base, seen) = stub(serde_json::json!({ "data": [{ "b64_json": b64(PNG) }], "usage": { "cost": 0.01 } }));
        let err = generate("line-art", &sheet("svg"), &ask(), &base, "k").unwrap_err();
        seen.join().unwrap();
        assert!(err.contains("drawing"), "{err}");
    }

    #[test]
    fn an_error_never_quotes_the_key() {
        let err = generate("concept-image", &sheet("image"), &ask(), "http://127.0.0.1:1", "the-secret-key").unwrap_err();
        assert!(!err.contains("the-secret-key"), "{err}");
    }
}
