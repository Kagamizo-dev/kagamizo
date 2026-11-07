//! The media pipeline's first half (modules/media): the clip catalog, the
//! cut-list rule and the tools behind the indexer and the renderer.
//!
//! Every time is a whole number of milliseconds, so the catalog, the cut
//! list and `../_lean/Clips.lean` speak the same numbers: the rule here
//! (`validate`) is the Lean `valid`, clause for clause, and the test
//! `validator_mirrors_lean` walks the same cases.
//!
//! ffmpeg, ffprobe and whisper-cli are the pinned ones from nixpkgs, their
//! paths baked in at build (`FFMPEG`, `FFPROBE`, `WHISPER_CLI`), as are the
//! declared limits (`MEDIA_MAX_MS`, `MEDIA_TOLERANCE_MS`,
//! `MEDIA_SCENE_THRESHOLD`).

use serde::{Deserialize, Serialize};
use std::fmt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const FFMPEG: &str = env!("FFMPEG");
pub const FFPROBE: &str = env!("FFPROBE");
pub const WHISPER_CLI: &str = env!("WHISPER_CLI");

/// The declared limits (media.maxClipSeconds, media.toleranceMs,
/// media.sceneThreshold), as the Nix module rendered them.
pub fn max_ms() -> u64 {
    env!("MEDIA_MAX_MS").parse().expect("MEDIA_MAX_MS")
}
pub fn tolerance_ms() -> u64 {
    env!("MEDIA_TOLERANCE_MS").parse().expect("MEDIA_TOLERANCE_MS")
}
pub fn scene_threshold() -> f64 {
    env!("MEDIA_SCENE_THRESHOLD").parse().expect("MEDIA_SCENE_THRESHOLD")
}

/// One line of a transcript.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Line {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

/// One catalogued clip: `/var/lib/media/catalog/<id>.json`, typed as
/// `media.clips` in Nix and `Clip` in Lean.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Clip {
    pub id: String,
    /// The file under the incoming directory: `<date>/<name>`.
    pub source: String,
    /// The incoming folder's date, `YYYY-MM-DD`.
    pub date: String,
    pub duration_ms: u64,
    pub width: u32,
    pub height: u32,
    pub codec: String,
    pub fps: f64,
    pub has_audio: bool,
    /// ffmpeg's scene-change threshold the cuts were found with.
    pub scene_threshold: f64,
    /// Where a scene changes, in milliseconds from the start, ascending.
    pub scenes: Vec<u64>,
    /// The whisper model file the transcript came from; null when the
    /// clip was indexed without one.
    pub whisper_model: Option<String>,
    pub transcript: Vec<Line>,
}

/// One segment of a source clip, `[start_ms, end_ms)`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Segment {
    pub start_ms: u64,
    pub end_ms: u64,
}

impl Segment {
    pub fn len_ms(&self) -> u64 {
        self.end_ms.saturating_sub(self.start_ms)
    }
}

/// A cut list: the clip to cut from, the segments in order, and the length
/// asked for. What the renderer takes; what the LLM step (another team)
/// writes.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CutList {
    pub source: String,
    pub segments: Vec<Segment>,
    pub target_ms: u64,
}

impl CutList {
    pub fn total_ms(&self) -> u64 {
        self.segments.iter().map(Segment::len_ms).sum()
    }
}

/// Why a cut list is refused; each variant is one clause of the Lean rule.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Invalid {
    /// A segment is empty or runs past the clip's end.
    OutsideClip { index: usize, segment: Segment, duration_ms: u64 },
    /// A segment starts before the previous one ends.
    Unordered { index: usize },
    /// The segments add up to something off the target by more than the
    /// tolerance.
    OffTarget { total_ms: u64, target_ms: u64, tolerance_ms: u64 },
    /// The target, or the total, is longer than the longest clip allowed.
    TooLong { ms: u64, max_ms: u64 },
    NoSegments,
}

impl fmt::Display for Invalid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Invalid::OutsideClip { index, segment, duration_ms } => write!(
                f,
                "segment {index} [{}, {}) is not within the clip (0 to {duration_ms} ms)",
                segment.start_ms, segment.end_ms
            ),
            Invalid::Unordered { index } => {
                write!(f, "segment {index} starts before segment {} ends", index - 1)
            }
            Invalid::OffTarget { total_ms, target_ms, tolerance_ms } => write!(
                f,
                "the segments add up to {total_ms} ms, not {target_ms} ms within {tolerance_ms} ms"
            ),
            Invalid::TooLong { ms, max_ms } => {
                write!(f, "{ms} ms is longer than the {max_ms} ms allowed")
            }
            Invalid::NoSegments => write!(f, "no segments"),
        }
    }
}

/// The cut-list rule, as `../_lean/Clips.lean` states it:
///   every segment is non-empty and ends within the clip,
///   each segment ends no later than the next starts,
///   the segments' total is within `tolerance_ms` of the target,
///   the target and the total are at most `max_ms`.
pub fn validate(
    cut: &CutList,
    duration_ms: u64,
    max_ms: u64,
    tolerance_ms: u64,
) -> Result<(), Invalid> {
    if cut.segments.is_empty() {
        return Err(Invalid::NoSegments);
    }
    for (index, s) in cut.segments.iter().enumerate() {
        if !(s.start_ms < s.end_ms && s.end_ms <= duration_ms) {
            return Err(Invalid::OutsideClip { index, segment: *s, duration_ms });
        }
    }
    for (index, w) in cut.segments.windows(2).enumerate() {
        if w[0].end_ms > w[1].start_ms {
            return Err(Invalid::Unordered { index: index + 1 });
        }
    }
    let total_ms = cut.total_ms();
    if total_ms + tolerance_ms < cut.target_ms || total_ms > cut.target_ms + tolerance_ms {
        return Err(Invalid::OffTarget { total_ms, target_ms: cut.target_ms, tolerance_ms });
    }
    if cut.target_ms > max_ms {
        return Err(Invalid::TooLong { ms: cut.target_ms, max_ms });
    }
    if total_ms > max_ms {
        return Err(Invalid::TooLong { ms: total_ms, max_ms });
    }
    Ok(())
}

/// A clip's id from its incoming folder and file name: `<date>-<stem>`,
/// lower case, anything but letters, digits and dashes folded to a dash.
pub fn clip_id(date: &str, file_name: &str) -> String {
    let stem = Path::new(file_name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(file_name);
    let mut id = String::new();
    for c in format!("{date}-{stem}").chars() {
        let c = c.to_ascii_lowercase();
        if c.is_ascii_alphanumeric() || c == '-' {
            id.push(c);
        } else if !id.ends_with('-') {
            id.push('-');
        }
    }
    id.trim_end_matches('-').to_owned()
}

fn run(cmd: &mut Command) -> Result<std::process::Output, String> {
    let out = cmd
        .output()
        .map_err(|e| format!("{}: {e}", cmd.get_program().to_string_lossy()))?;
    if !out.status.success() {
        return Err(format!(
            "{} failed ({}): {}",
            cmd.get_program().to_string_lossy(),
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(out)
}

/// What ffprobe says of a file.
#[derive(Clone, Debug, PartialEq)]
pub struct Probe {
    pub duration_ms: u64,
    pub width: u32,
    pub height: u32,
    pub codec: String,
    pub fps: f64,
    pub has_audio: bool,
}

#[derive(Deserialize)]
struct ProbeOut {
    format: ProbeFormat,
    streams: Vec<ProbeStream>,
}
#[derive(Deserialize)]
struct ProbeFormat {
    duration: String,
}
#[derive(Deserialize)]
struct ProbeStream {
    codec_type: String,
    codec_name: Option<String>,
    width: Option<u32>,
    height: Option<u32>,
    r_frame_rate: Option<String>,
}

fn seconds_to_ms(s: &str) -> Result<u64, String> {
    let secs: f64 = s.trim().parse().map_err(|_| format!("not a time in seconds: {s:?}"))?;
    if !(secs.is_finite() && secs >= 0.0) {
        return Err(format!("not a time in seconds: {s:?}"));
    }
    Ok((secs * 1000.0).round() as u64)
}

fn ratio(s: &str) -> f64 {
    match s.split_once('/') {
        Some((n, d)) => {
            let n: f64 = n.parse().unwrap_or(0.0);
            let d: f64 = d.parse().unwrap_or(1.0);
            if d == 0.0 {
                0.0
            } else {
                n / d
            }
        }
        None => s.parse().unwrap_or(0.0),
    }
}

pub fn probe(file: &Path) -> Result<Probe, String> {
    let out = run(Command::new(FFPROBE).args([
        "-v",
        "error",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
    ])
    .arg(file))?;
    let p: ProbeOut = serde_json::from_slice(&out.stdout).map_err(|e| format!("ffprobe: {e}"))?;
    let video = p
        .streams
        .iter()
        .find(|s| s.codec_type == "video")
        .ok_or_else(|| format!("{}: no video stream", file.display()))?;
    Ok(Probe {
        duration_ms: seconds_to_ms(&p.format.duration)?,
        width: video.width.unwrap_or(0),
        height: video.height.unwrap_or(0),
        codec: video.codec_name.clone().unwrap_or_default(),
        fps: video.r_frame_rate.as_deref().map(ratio).unwrap_or(0.0),
        has_audio: p.streams.iter().any(|s| s.codec_type == "audio"),
    })
}

/// Where the picture changes: ffmpeg's `scene` score over the threshold,
/// each as milliseconds from the start.
pub fn scenes(file: &Path, threshold: f64) -> Result<Vec<u64>, String> {
    let out = run(Command::new(FFMPEG)
        .args(["-nostdin", "-hide_banner", "-loglevel", "info", "-i"])
        .arg(file)
        .args([
            "-vf",
            &format!("select='gt(scene,{threshold})',showinfo"),
            "-an",
            "-sn",
            "-f",
            "null",
            "-",
        ]))?;
    let mut cuts = Vec::new();
    for line in String::from_utf8_lossy(&out.stderr).lines() {
        if let Some(rest) = line.split("pts_time:").nth(1) {
            let t = rest.split_whitespace().next().unwrap_or_default();
            if let Ok(ms) = seconds_to_ms(t) {
                cuts.push(ms);
            }
        }
    }
    cuts.sort_unstable();
    cuts.dedup();
    Ok(cuts)
}

#[derive(Deserialize)]
struct WhisperOut {
    transcription: Vec<WhisperLine>,
}
#[derive(Deserialize)]
struct WhisperLine {
    offsets: WhisperOffsets,
    text: String,
}
#[derive(Deserialize)]
struct WhisperOffsets {
    from: u64,
    to: u64,
}

/// The transcript, by whisper.cpp with the given model: the audio goes out
/// as 16 kHz mono PCM into `work`, which the caller owns.
pub fn transcribe(file: &Path, model: &Path, work: &Path, threads: u32) -> Result<Vec<Line>, String> {
    let wav = work.join("audio.wav");
    run(Command::new(FFMPEG)
        .args(["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i"])
        .arg(file)
        .args(["-vn", "-sn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le"])
        .arg(&wav))?;
    let base = work.join("transcript");
    run(Command::new(WHISPER_CLI)
        .arg("-m")
        .arg(model)
        .arg("-f")
        .arg(&wav)
        .args(["-oj", "-np", "-t", &threads.to_string(), "-of"])
        .arg(&base))?;
    let json = std::fs::read(base.with_extension("json"))
        .map_err(|e| format!("whisper-cli wrote no transcript: {e}"))?;
    let w: WhisperOut = serde_json::from_slice(&json).map_err(|e| format!("whisper-cli: {e}"))?;
    Ok(w.transcription
        .into_iter()
        .map(|l| Line { start_ms: l.offsets.from, end_ms: l.offsets.to, text: l.text.trim().to_owned() })
        .filter(|l| !l.text.is_empty())
        .collect())
}

/// The ffmpeg filter graph that trims each segment and joins them.
pub fn filter_graph(segments: &[Segment], audio: bool) -> String {
    let mut g = Vec::new();
    let mut ins = String::new();
    for (i, s) in segments.iter().enumerate() {
        let (a, b) = (s.start_ms as f64 / 1000.0, s.end_ms as f64 / 1000.0);
        g.push(format!("[0:v]trim=start={a:.3}:end={b:.3},setpts=PTS-STARTPTS[v{i}]"));
        ins.push_str(&format!("[v{i}]"));
        if audio {
            g.push(format!("[0:a]atrim=start={a:.3}:end={b:.3},asetpts=PTS-STARTPTS[a{i}]"));
            ins.push_str(&format!("[a{i}]"));
        }
    }
    g.push(format!(
        "{ins}concat=n={}:v=1:a={}[v]{}",
        segments.len(),
        u8::from(audio),
        if audio { "[a]" } else { "" }
    ));
    g.join(";")
}

/// Render a validated cut list: one encoder thread, bit-exact flags and no
/// metadata, so the same cut list over the same source gives the same
/// bytes.
pub fn render(source: &Path, cut: &CutList, audio: bool, out: &Path) -> Result<(), String> {
    let mut cmd = Command::new(FFMPEG);
    cmd.args(["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i"])
        .arg(source)
        .args(["-filter_complex", &filter_graph(&cut.segments, audio), "-map", "[v]"]);
    if audio {
        cmd.args(["-map", "[a]", "-c:a", "aac", "-b:a", "128k"]);
    }
    cmd.args([
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-crf",
        "20",
        "-pix_fmt",
        "yuv420p",
        "-threads",
        "1",
        "-x264-params",
        "threads=1",
        "-map_metadata",
        "-1",
        "-map_chapters",
        "-1",
        "-fflags",
        "+bitexact",
        "-flags",
        "+bitexact",
        "-movflags",
        "+faststart",
    ])
    .arg(out);
    run(&mut cmd).map(|_| ())
}

/// Read a clip from the catalog.
pub fn read_clip(catalog: &Path, id: &str) -> Result<Clip, String> {
    let path = catalog.join(format!("{id}.json"));
    let bytes = std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    serde_json::from_slice(&bytes).map_err(|e| format!("{}: {e}", path.display()))
}

/// Write a clip to the catalog, whole or not at all.
pub fn write_clip(catalog: &Path, clip: &Clip) -> Result<PathBuf, String> {
    let path = catalog.join(format!("{}.json", clip.id));
    let tmp = catalog.join(format!(".{}.json.tmp", clip.id));
    let mut json = serde_json::to_vec_pretty(clip).map_err(|e| e.to_string())?;
    json.push(b'\n');
    std::fs::write(&tmp, json).map_err(|e| format!("{}: {e}", tmp.display()))?;
    std::fs::rename(&tmp, &path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seg(a: u64, b: u64) -> Segment {
        Segment { start_ms: a, end_ms: b }
    }
    fn cut(segments: Vec<Segment>, target_ms: u64) -> CutList {
        CutList { source: "clip".into(), segments, target_ms }
    }

    /// The same cases `../_lean/Clips.lean` decides, clause for clause.
    #[test]
    fn validator_mirrors_lean() {
        let d = 60_000;
        let max = 120_000;
        let tol = 500;
        let ok = cut(vec![seg(1_000, 3_000), seg(5_000, 6_000)], 3_000);
        assert_eq!(validate(&ok, d, max, tol), Ok(()));
        // Within the tolerance either way.
        assert_eq!(validate(&cut(vec![seg(0, 2_600)], 3_000), d, max, tol), Ok(()));
        assert_eq!(validate(&cut(vec![seg(0, 3_400)], 3_000), d, max, tol), Ok(()));
        // Past the end of the clip.
        assert_eq!(
            validate(&cut(vec![seg(59_000, 60_001)], 1_000), d, max, tol),
            Err(Invalid::OutsideClip { index: 0, segment: seg(59_000, 60_001), duration_ms: d })
        );
        // Empty segment.
        assert!(matches!(
            validate(&cut(vec![seg(5_000, 5_000)], 0), d, max, tol),
            Err(Invalid::OutsideClip { index: 0, .. })
        ));
        // Overlapping, and out of order.
        assert_eq!(
            validate(&cut(vec![seg(1_000, 3_000), seg(2_500, 4_000)], 3_500), d, max, tol),
            Err(Invalid::Unordered { index: 1 })
        );
        assert_eq!(
            validate(&cut(vec![seg(5_000, 6_000), seg(1_000, 3_000)], 3_000), d, max, tol),
            Err(Invalid::Unordered { index: 1 })
        );
        // Touching segments are in order.
        assert_eq!(validate(&cut(vec![seg(1_000, 3_000), seg(3_000, 4_000)], 3_000), d, max, tol), Ok(()));
        // Off the target by more than the tolerance.
        assert_eq!(
            validate(&cut(vec![seg(0, 2_499)], 3_000), d, max, tol),
            Err(Invalid::OffTarget { total_ms: 2_499, target_ms: 3_000, tolerance_ms: tol })
        );
        // Longer than allowed, by the target and by the total.
        assert_eq!(
            validate(&cut(vec![seg(0, 60_000)], 120_001), 200_000, max, 70_000),
            Err(Invalid::TooLong { ms: 120_001, max_ms: max })
        );
        assert_eq!(
            validate(&cut(vec![seg(0, 120_400)], 120_000), 200_000, max, tol),
            Err(Invalid::TooLong { ms: 120_400, max_ms: max })
        );
        assert_eq!(validate(&cut(vec![], 0), d, max, tol), Err(Invalid::NoSegments));
    }

    #[test]
    fn declared_limits_are_numbers() {
        assert!(max_ms() > 0);
        assert!(tolerance_ms() < max_ms());
        assert!(scene_threshold() > 0.0 && scene_threshold() < 1.0);
    }

    #[test]
    fn ids_are_stable() {
        assert_eq!(clip_id("2026-11-04", "DJI_20261104_123456_0001.MP4"), "2026-11-04-dji-20261104-123456-0001");
        assert_eq!(clip_id("2026-11-04", "Ride (morning).mov"), "2026-11-04-ride-morning");
    }

    /// The fixture Nix types as `media.clips.example` parses here too.
    #[test]
    fn example_clip_is_the_schema() {
        let json = include_str!("../fixtures/example-clip.json");
        let clip: Clip = serde_json::from_str(json).unwrap();
        assert_eq!(clip.id, "2026-11-03-dji-20261103-081500-0007");
        let back: serde_json::Value = serde_json::from_str(json).unwrap();
        assert_eq!(serde_json::to_value(&clip).unwrap(), back);
    }

    #[test]
    fn cut_list_round_trips() {
        let json = r#"{"source":"clip","segments":[{"startMs":1000,"endMs":3000}],"targetMs":2000}"#;
        let c: CutList = serde_json::from_str(json).unwrap();
        assert_eq!(c, cut(vec![seg(1_000, 3_000)], 2_000));
        assert!(serde_json::from_str::<CutList>(r#"{"source":"a","segments":[],"targetMs":1,"x":1}"#).is_err());
    }

    #[test]
    fn filter_graph_is_as_expected() {
        assert_eq!(
            filter_graph(&[seg(1_000, 3_000), seg(5_000, 6_000)], false),
            "[0:v]trim=start=1.000:end=3.000,setpts=PTS-STARTPTS[v0];\
             [0:v]trim=start=5.000:end=6.000,setpts=PTS-STARTPTS[v1];\
             [v0][v1]concat=n=2:v=1:a=0[v]"
        );
    }

    /// A synthetic clip (ffmpeg's testsrc and sine), indexed without a
    /// whisper model and rendered twice from one cut list.
    #[test]
    fn index_and_render_synthetic_clip() {
        let work = std::env::temp_dir().join(format!("media-test-{}", std::process::id()));
        let incoming = work.join("incoming/2026-11-04");
        let catalog = work.join("catalog");
        std::fs::create_dir_all(&incoming).unwrap();
        std::fs::create_dir_all(&catalog).unwrap();
        let src = incoming.join("ride.mp4");
        run(Command::new(FFMPEG)
            .args(["-nostdin", "-hide_banner", "-loglevel", "error", "-y"])
            .args(["-f", "lavfi", "-i", "testsrc=duration=10:size=320x240:rate=25"])
            .args(["-f", "lavfi", "-i", "sine=frequency=440:duration=10"])
            .args(["-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest"])
            .arg(&src))
        .unwrap();

        let p = probe(&src).unwrap();
        assert!((9_900..=10_100).contains(&p.duration_ms), "{p:?}");
        assert_eq!((p.width, p.height, p.codec.as_str(), p.has_audio), (320, 240, "h264", true));
        assert!((p.fps - 25.0).abs() < 0.01);
        let cuts = scenes(&src, scene_threshold()).unwrap();
        assert!(cuts.iter().all(|&t| t <= p.duration_ms));

        let clip = Clip {
            id: clip_id("2026-11-04", "ride.mp4"),
            source: "2026-11-04/ride.mp4".into(),
            date: "2026-11-04".into(),
            duration_ms: p.duration_ms,
            width: p.width,
            height: p.height,
            codec: p.codec.clone(),
            fps: p.fps,
            has_audio: p.has_audio,
            scene_threshold: scene_threshold(),
            scenes: cuts,
            whisper_model: None,
            transcript: vec![],
        };
        write_clip(&catalog, &clip).unwrap();
        assert_eq!(read_clip(&catalog, &clip.id).unwrap(), clip);

        let c = cut(vec![seg(1_000, 3_000), seg(5_000, 6_000)], 3_000);
        validate(&c, clip.duration_ms, max_ms(), tolerance_ms()).unwrap();
        let out1 = work.join("out1.mp4");
        let out2 = work.join("out2.mp4");
        render(&src, &c, clip.has_audio, &out1).unwrap();
        render(&src, &c, clip.has_audio, &out2).unwrap();
        let r = probe(&out1).unwrap();
        assert!((2_900..=3_100).contains(&r.duration_ms), "{r:?}");
        assert_eq!((r.width, r.height, r.has_audio), (320, 240, true));
        assert_eq!(std::fs::read(&out1).unwrap(), std::fs::read(&out2).unwrap(), "the render is not deterministic");
        std::fs::remove_dir_all(&work).unwrap();
    }
}
