//! media-render: apply a cut list to its source clip.
//!
//!   media-render CUTLIST.json --incoming DIR --catalog DIR --out FILE.mp4
//!   media-render CUTLIST.json --catalog DIR --check
//!
//! The cut list (a `media::CutList`) names a catalogued clip; it is checked
//! against the rule `../_lean/Clips.lean` states (within the clip, ordered,
//! on target within the declared tolerance, no longer than
//! media.maxClipSeconds) and refused with the failing clause otherwise.
//! --check stops there. The render is deterministic: the same cut list
//! over the same source gives the same bytes.

use std::collections::HashMap;
use std::path::PathBuf;

const USAGE: &str =
    "usage: media-render CUTLIST.json --catalog DIR (--check | --incoming DIR --out FILE.mp4)";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut f: HashMap<String, String> = HashMap::new();
    let mut cut_path = None;
    let mut check = false;
    let mut it = args.iter();
    while let Some(k) = it.next() {
        if k == "--check" {
            check = true;
        } else if let Some(k) = k.strip_prefix("--") {
            match it.next() {
                Some(v) => {
                    f.insert(k.to_owned(), v.clone());
                }
                None => fail(2, &format!("--{k} needs a value\n{USAGE}")),
            }
        } else if cut_path.is_none() {
            cut_path = Some(PathBuf::from(k));
        } else {
            fail(2, &format!("unexpected argument {k}\n{USAGE}"));
        }
    }
    let cut_path = cut_path.unwrap_or_else(|| fail(2, USAGE));
    let catalog = f.get("catalog").map(PathBuf::from).unwrap_or_else(|| fail(2, USAGE));

    let bytes = std::fs::read(&cut_path).unwrap_or_else(|e| fail(1, &format!("{}: {e}", cut_path.display())));
    let cut: media::CutList =
        serde_json::from_slice(&bytes).unwrap_or_else(|e| fail(1, &format!("{}: {e}", cut_path.display())));
    let clip = media::read_clip(&catalog, &cut.source).unwrap_or_else(|e| fail(1, &e));
    if let Err(why) = media::validate(&cut, clip.duration_ms, media::max_ms(), media::tolerance_ms()) {
        fail(1, &format!("{}: refused: {why}", cut_path.display()));
    }
    println!(
        "{}: {} segments of {}, {} ms (target {} ms)",
        cut_path.display(),
        cut.segments.len(),
        clip.id,
        cut.total_ms(),
        cut.target_ms
    );
    if check {
        return;
    }
    let incoming = f.get("incoming").map(PathBuf::from).unwrap_or_else(|| fail(2, USAGE));
    let out = f.get("out").map(PathBuf::from).unwrap_or_else(|| fail(2, USAGE));
    if let Some(dir) = out.parent() {
        std::fs::create_dir_all(dir).unwrap_or_else(|e| fail(1, &format!("{}: {e}", dir.display())));
    }
    let source = incoming.join(&clip.source);
    let tmp = out.with_extension("part.mp4");
    media::render(&source, &cut, clip.has_audio, &tmp).unwrap_or_else(|e| fail(1, &e));
    std::fs::rename(&tmp, &out).unwrap_or_else(|e| fail(1, &format!("{}: {e}", out.display())));
    println!("{}", out.display());
}

fn fail(code: i32, msg: &str) -> ! {
    eprintln!("media-render: {msg}");
    std::process::exit(code)
}
