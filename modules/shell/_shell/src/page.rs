//! shell-page: writes the browser target's page, the only thing it needs
//! beside the WebAssembly and wasm-bindgen's generated module: a title, and
//! the one-line import that starts the shell (a browser loads WebAssembly
//! only from a module script).
//!
//!   shell-page <out-dir>     writes <out-dir>/index.html
fn main() {
    let out = std::env::args()
        .nth(1)
        .expect("usage: shell-page <out-dir>");
    let page = concat!(
        "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n",
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n",
        "<meta name=\"theme-color\" content=\"#121418\">\n",
        "<title>Kagamizo</title>\n",
        "<style>html,body{margin:0;height:100%;background:#121418;overflow:hidden}</style>\n",
        "</head>\n<body>\n",
        "<script type=\"module\">import init from './kagamizo_shell.js'; init();</script>\n",
        "</body>\n</html>\n"
    );
    std::fs::write(format!("{out}/index.html"), page).expect("write index.html");
}
