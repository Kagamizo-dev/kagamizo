//! media-index: catalog every clip under the incoming directory.
//!
//!   media-index --incoming DIR --catalog DIR [--whisper-model FILE] [--threads N] [--force]
//!
//! Each `DIR/<date>/<file>` (a video file; dates are `YYYY-MM-DD`) becomes
//! `catalog/<id>.json` (a `media::Clip`): duration, resolution, codec and
//! frame rate from ffprobe, scene cuts from ffmpeg at the declared
//! threshold, and a transcript from whisper.cpp when a model is given.
//! A clip already in the catalog is left alone unless --force. The exit
//! status is non-zero when any clip failed; the others are still written.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

const VIDEO: &[&str] = &["mp4", "mov", "mkv", "m4v", "webm", "avi"];
const USAGE: &str = "usage: media-index --incoming DIR --catalog DIR [--whisper-model FILE] [--threads N] [--force]";

fn flags(args: &[String]) -> Result<(HashMap<String, String>, bool), String> {
    let mut out = HashMap::new();
    let mut force = false;
    let mut it = args.iter();
    while let Some(k) = it.next() {
        if k == "--force" {
            force = true;
            continue;
        }
        let k = k.strip_prefix("--").ok_or_else(|| format!("unexpected argument {k}\n{USAGE}"))?;
        let v = it.next().ok_or_else(|| format!("--{k} needs a value\n{USAGE}"))?;
        out.insert(k.to_owned(), v.clone());
    }
    Ok((out, force))
}

fn is_date(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 10
        && b.iter().enumerate().all(|(i, c)| if i == 4 || i == 7 { *c == b'-' } else { c.is_ascii_digit() })
}

fn index_one(
    incoming: &Path,
    catalog: &Path,
    date: &str,
    file: &Path,
    model: Option<&Path>,
    threads: u32,
) -> Result<media::Clip, String> {
    let name = file.file_name().and_then(|n| n.to_str()).ok_or("a file name that is not UTF-8")?;
    let p = media::probe(file)?;
    let threshold = media::scene_threshold();
    let scenes = media::scenes(file, threshold)?;
    let (whisper_model, transcript) = match model {
        Some(m) => {
            let work = catalog.join(format!(".work-{}", std::process::id()));
            std::fs::create_dir_all(&work).map_err(|e| format!("{}: {e}", work.display()))?;
            let t = media::transcribe(file, m, &work, threads);
            let _ = std::fs::remove_dir_all(&work);
            (Some(m.file_name().unwrap_or_default().to_string_lossy().into_owned()), t?)
        }
        None => (None, vec![]),
    };
    let rel = file.strip_prefix(incoming).unwrap_or(file).to_string_lossy().into_owned();
    Ok(media::Clip {
        id: media::clip_id(date, name),
        source: rel,
        date: date.to_owned(),
        duration_ms: p.duration_ms,
        width: p.width,
        height: p.height,
        codec: p.codec,
        fps: p.fps,
        has_audio: p.has_audio,
        scene_threshold: threshold,
        scenes,
        whisper_model,
        transcript,
    })
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (f, force) = match flags(&args) {
        Ok(x) => x,
        Err(e) => {
            eprintln!("media-index: {e}");
            std::process::exit(2);
        }
    };
    let need = |k: &str| f.get(k).map(PathBuf::from).unwrap_or_else(|| {
        eprintln!("media-index: --{k} is required\n{USAGE}");
        std::process::exit(2);
    });
    let incoming = need("incoming");
    let catalog = need("catalog");
    let model = f.get("whisper-model").map(PathBuf::from);
    let threads: u32 = f.get("threads").map(|t| t.parse().unwrap_or(2)).unwrap_or(2);
    if let Err(e) = std::fs::create_dir_all(&catalog) {
        eprintln!("media-index: {}: {e}", catalog.display());
        std::process::exit(1);
    }
    if model.is_none() {
        eprintln!("media-index: no --whisper-model, so no transcripts");
    }

    let mut failed = 0;
    let mut days: Vec<_> = match std::fs::read_dir(&incoming) {
        Ok(d) => d.filter_map(Result::ok).map(|e| e.path()).collect(),
        Err(e) => {
            eprintln!("media-index: {}: {e}", incoming.display());
            std::process::exit(1);
        }
    };
    days.sort();
    for day in days {
        let date = day.file_name().and_then(|n| n.to_str()).unwrap_or_default().to_owned();
        if !day.is_dir() || !is_date(&date) {
            eprintln!("media-index: skipping {}: not a YYYY-MM-DD folder", day.display());
            continue;
        }
        let mut files: Vec<_> = match std::fs::read_dir(&day) {
            Ok(d) => d.filter_map(Result::ok).map(|e| e.path()).collect(),
            Err(e) => {
                eprintln!("media-index: {}: {e}", day.display());
                failed += 1;
                continue;
            }
        };
        files.sort();
        for file in files {
            let ext = file.extension().and_then(|e| e.to_str()).map(|e| e.to_ascii_lowercase());
            if !file.is_file() || !ext.is_some_and(|e| VIDEO.contains(&e.as_str())) {
                continue;
            }
            let name = file.file_name().and_then(|n| n.to_str()).unwrap_or_default();
            let id = media::clip_id(&date, name);
            if !force && catalog.join(format!("{id}.json")).exists() {
                continue;
            }
            match index_one(&incoming, &catalog, &date, &file, model.as_deref(), threads) {
                Ok(clip) => match media::write_clip(&catalog, &clip) {
                    Ok(path) => println!(
                        "{}: {} ms, {}x{} {}, {} scene cuts, {} transcript lines -> {}",
                        clip.id,
                        clip.duration_ms,
                        clip.width,
                        clip.height,
                        clip.codec,
                        clip.scenes.len(),
                        clip.transcript.len(),
                        path.display()
                    ),
                    Err(e) => {
                        eprintln!("media-index: {id}: {e}");
                        failed += 1;
                    }
                },
                Err(e) => {
                    eprintln!("media-index: {}: {e}", file.display());
                    failed += 1;
                }
            }
        }
    }
    if failed > 0 {
        eprintln!("media-index: {failed} clip(s) failed");
        std::process::exit(1);
    }
}
