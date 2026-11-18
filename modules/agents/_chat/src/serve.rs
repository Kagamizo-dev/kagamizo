//! The listening part: one request at a time, on the loopback only. Who is
//! asking is decided by the caller (`identify`), so the gateway proper
//! asks Cloudflare Access and the browser check answers for itself.
use crate::{Chat, Request, Response};
use matrix_rooms::Talk;
use std::io::Read;
use std::path::{Path, PathBuf};

fn header<'a>(r: &'a tiny_http::Request, name: &str) -> Option<&'a str> {
    r.headers().iter().find(|h| h.field.as_str().as_str().eq_ignore_ascii_case(name)).map(|h| h.value.as_str())
}

fn kind(path: &Path) -> &'static str {
    match path.extension().and_then(|e| e.to_str()) {
        Some("html") => "text/html; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("png") => "image/png",
        Some("wasm") => "application/wasm",
        Some("js") => "text/javascript; charset=utf-8",
        _ => "application/octet-stream",
    }
}

/// A file of the static site, for the browser check: `under` is the
/// address the site is served at.
fn file(site: &Path, under: &str, path: &str) -> Option<(Vec<u8>, &'static str)> {
    let rest = path.split(['?', '#']).next()?.strip_prefix(under)?;
    if rest.split('/').any(|part| part == "..") {
        return None;
    }
    let mut to: PathBuf = site.join(rest.trim_start_matches('/'));
    if to.is_dir() {
        to = to.join("index.html");
    }
    Some((std::fs::read(&to).ok()?, kind(&to)))
}

fn send(request: tiny_http::Request, status: u16, content: &str, location: Option<&str>, body: Vec<u8>) {
    let mut response = tiny_http::Response::from_data(body).with_status_code(status);
    let mut add = |name: &str, value: &str| {
        if let Ok(h) = tiny_http::Header::from_bytes(name.as_bytes(), value.as_bytes()) {
            response.add_header(h);
        }
    };
    add("Content-Type", content);
    add("Cache-Control", "no-store");
    add("X-Content-Type-Options", "nosniff");
    add("Referrer-Policy", "same-origin");
    if let Some(to) = location {
        add("Location", to);
    }
    let _ = request.respond(response);
}

/// Serve until the process ends. With `site`, everything under `under`
/// that is not the chat's is a file of the static site.
pub fn serve<S: Talk>(port: u16, mut chat: Chat<S>, mut identify: impl FnMut(Option<&str>) -> Option<String>, site: Option<(&Path, &str)>) -> Result<(), String> {
    let server = tiny_http::Server::http(("127.0.0.1", port)).map_err(|e| format!("port {port}: {e}"))?;
    for mut request in server.incoming_requests() {
        let path = request.url().to_owned();
        if !path.starts_with(chat.prefix.as_str()) {
            match site.and_then(|(dir, under)| file(dir, under, &path)) {
                Some((bytes, content)) => send(request, 200, content, None, bytes),
                None => send(request, 404, "text/plain; charset=utf-8", None, b"Not found".to_vec()),
            }
            continue;
        }
        let mut form = String::new();
        let _ = request.as_reader().take(4 * crate::LONGEST as u64).read_to_string(&mut form);
        let who = identify(header(&request, "Cf-Access-Jwt-Assertion"));
        let same_origin = header(&request, "Sec-Fetch-Site") == Some("same-origin");
        let method = request.method().as_str().to_owned();
        let Response { status, body, location } = chat.handle(&Request { method: &method, path: &path, form: &form, who: who.as_deref(), same_origin });
        send(request, status, "text/html; charset=utf-8", location.as_deref(), body.into_bytes());
    }
    Ok(())
}
