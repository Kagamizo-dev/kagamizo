//! shell-page: writes the browser target's page, the only thing it needs
//! beside the WebAssembly and wasm-bindgen's generated module: a title, the
//! one-line import that starts the shell (a browser loads WebAssembly only
//! from a module script), and what lets a phone install it to its home
//! screen as an app: a web app manifest and its icons, drawn here.
//!
//!   shell-page <out-dir>     writes index.html, manifest.webmanifest,
//!                            icon-192.png and icon-512.png
use std::fs::File;
use std::io::BufWriter;

const INK: [u8; 3] = [0x12, 0x14, 0x18];
const CARD: [u8; 3] = [0x26, 0x2c, 0x36];
const ACCENT: [u8; 3] = [0x6f, 0xc3, 0xb2];

/// The icon: three cards stacked in a column on ink, the first one lit,
/// which is the shell's home.
fn icon(size: u32) -> Vec<u8> {
    let s = size as f32;
    let (left, right) = (0.2 * s, 0.8 * s);
    let height = 0.16 * s;
    let tops = [0.22 * s, 0.42 * s, 0.62 * s];
    let radius = 0.04 * s;
    let inside = |x: f32, y: f32, top: f32| {
        let (x0, x1, y0, y1) = (left, right, top, top + height);
        if x < x0 || x > x1 || y < y0 || y > y1 {
            return false;
        }
        // Round the corners.
        let cx = x.clamp(x0 + radius, x1 - radius);
        let cy = y.clamp(y0 + radius, y1 - radius);
        (x - cx).powi(2) + (y - cy).powi(2) <= radius * radius
    };
    let mut px = Vec::with_capacity((size * size * 3) as usize);
    for y in 0..size {
        for x in 0..size {
            let (fx, fy) = (x as f32 + 0.5, y as f32 + 0.5);
            let colour = match tops.iter().position(|t| inside(fx, fy, *t)) {
                Some(0) => ACCENT,
                Some(_) => CARD,
                None => INK,
            };
            px.extend_from_slice(&colour);
        }
    }
    px
}

fn write_icon(out: &str, size: u32) {
    let path = format!("{out}/icon-{size}.png");
    let file = File::create(&path).expect("create the icon");
    let mut enc = png::Encoder::new(BufWriter::new(file), size, size);
    enc.set_color(png::ColorType::Rgb);
    enc.set_depth(png::BitDepth::Eight);
    let mut w = enc.write_header().expect("the icon's header");
    w.write_image_data(&icon(size)).expect("the icon's pixels");
}

fn main() {
    let out = std::env::args()
        .nth(1)
        .expect("usage: shell-page <out-dir>");
    let page = concat!(
        "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n",
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n",
        "<meta name=\"theme-color\" content=\"#121418\">\n",
        "<title>Kagamizo</title>\n",
        "<link rel=\"manifest\" href=\"manifest.webmanifest\">\n",
        "<link rel=\"icon\" href=\"icon-192.png\">\n",
        "<link rel=\"apple-touch-icon\" href=\"icon-192.png\">\n",
        "<style>html,body{margin:0;height:100%;background:#121418;overflow:hidden}</style>\n",
        "</head>\n<body>\n",
        "<script type=\"module\">import init from './kagamizo_shell.js'; init();</script>\n",
        "</body>\n</html>\n"
    );
    std::fs::write(format!("{out}/index.html"), page).expect("write index.html");
    let manifest = serde_json::json!({
        "name": "Kagamizo",
        "short_name": "Kagamizo",
        "description": "The Kagamizo shell: every module of the repository as an app, on every device",
        "start_url": "./",
        "scope": "./",
        "display": "fullscreen",
        "orientation": "any",
        "background_color": "#121418",
        "theme_color": "#121418",
        "icons": [
            { "src": "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any maskable" },
            { "src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable" }
        ]
    });
    std::fs::write(
        format!("{out}/manifest.webmanifest"),
        serde_json::to_string_pretty(&manifest).expect("the manifest"),
    )
    .expect("write manifest.webmanifest");
    write_icon(&out, 192);
    write_icon(&out, 512);
}
