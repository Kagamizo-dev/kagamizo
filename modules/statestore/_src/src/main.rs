//! statestore: Proton Pass as an OpenTofu state backend.
//!
//!   statestore serve --vault V --name N --chunk-size B --port P
//!       OpenTofu's `http` backend on 127.0.0.1:P: GET and POST /state,
//!       LOCK and UNLOCK /lock. Prints `ready` once listening.
//!   statestore get  --vault V --name N           the state to stdout
//!   statestore put  --vault V --name N --chunk-size B   stdin as the state
//!   statestore show --vault V --name N           the manifest (no value)
//!
//! Every write follows the protocol ../_lean/Store.lean proves never loses a
//! state. Values never reach stderr.

mod store;

use anyhow::{anyhow, bail, Context, Result};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use store::Store;

fn flags(args: &[String]) -> Result<HashMap<String, String>> {
    let mut out = HashMap::new();
    let mut it = args.iter();
    while let Some(k) = it.next() {
        let k = k.strip_prefix("--").ok_or_else(|| anyhow!("unexpected argument {k}"))?;
        let v = it.next().ok_or_else(|| anyhow!("--{k} needs a value"))?;
        out.insert(k.to_owned(), v.clone());
    }
    Ok(out)
}

fn need<'a>(f: &'a HashMap<String, String>, k: &str) -> Result<&'a str> {
    f.get(k).map(String::as_str).ok_or_else(|| anyhow!("--{k} is required"))
}

fn store(f: &HashMap<String, String>) -> Result<Store> {
    let chunk_size = f.get("chunk-size").map(|s| s.parse()).transpose()?.unwrap_or(8000);
    if chunk_size < 64 {
        bail!("--chunk-size must be at least 64");
    }
    Ok(Store { vault: need(f, "vault")?.into(), name: need(f, "name")?.into(), chunk_size })
}

fn respond(s: &mut TcpStream, code: u16, reason: &str, body: &[u8]) -> Result<()> {
    write!(
        s,
        "HTTP/1.1 {code} {reason}\r\nContent-Length: {}\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n",
        body.len()
    )?;
    s.write_all(body)?;
    Ok(())
}

/// One request: method, path, body. OpenTofu's client sends a Content-Length.
fn request(s: &TcpStream) -> Result<(String, String, Vec<u8>)> {
    let mut r = BufReader::new(s);
    let mut line = String::new();
    r.read_line(&mut line)?;
    let mut parts = line.split_whitespace();
    let method = parts.next().unwrap_or_default().to_owned();
    let path = parts.next().unwrap_or_default().split('?').next().unwrap_or_default().to_owned();
    let mut len = 0usize;
    loop {
        let mut h = String::new();
        r.read_line(&mut h)?;
        let h = h.trim_end();
        if h.is_empty() {
            break;
        }
        if let Some((k, v)) = h.split_once(':') {
            if k.eq_ignore_ascii_case("content-length") {
                len = v.trim().parse()?;
            }
            if k.eq_ignore_ascii_case("transfer-encoding") {
                bail!("chunked bodies are not accepted");
            }
        }
    }
    let mut body = vec![0; len];
    r.read_exact(&mut body)?;
    Ok((method, path, body))
}

fn serve(st: &Store, port: u16) -> Result<()> {
    let listener = TcpListener::bind(("127.0.0.1", port)).context("binding the loopback port")?;
    println!("ready");
    std::io::stdout().flush()?;
    for conn in listener.incoming() {
        let mut s = conn?;
        let (method, path, body) = match request(&s) {
            Ok(r) => r,
            Err(e) => {
                respond(&mut s, 400, "Bad Request", e.to_string().as_bytes())?;
                continue;
            }
        };
        let outcome: Result<()> = (|| match (method.as_str(), path.as_str()) {
            ("GET", "/state") => match st.read()? {
                Some((_, v)) => respond(&mut s, 200, "OK", v.as_bytes()),
                None => respond(&mut s, 404, "Not Found", b""),
            },
            ("POST", "/state") => {
                let v = String::from_utf8(body).context("the state is not UTF-8")?;
                let m = st.write(&v)?;
                eprintln!("statestore: wrote generation {} ({} bytes, {} chunks)", m.generation, m.bytes, m.count);
                respond(&mut s, 200, "OK", b"")
            }
            ("LOCK", "/lock") => match st.lock(&String::from_utf8_lossy(&body))? {
                Ok(()) => respond(&mut s, 200, "OK", b""),
                Err(held) => respond(&mut s, 423, "Locked", held.as_bytes()),
            },
            ("UNLOCK", "/lock") => {
                st.unlock()?;
                respond(&mut s, 200, "OK", b"")
            }
            _ => respond(&mut s, 405, "Method Not Allowed", b""),
        })();
        if let Err(e) = outcome {
            eprintln!("statestore: {method} {path}: {e:#}");
            let _ = respond(&mut s, 500, "Internal Server Error", format!("{e:#}").as_bytes());
        }
    }
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (cmd, rest) = args.split_first().ok_or_else(|| anyhow!("usage: statestore <serve|get|put|show> --vault V --name N"))?;
    let f = flags(rest)?;
    let st = store(&f)?;
    match cmd.as_str() {
        "serve" => serve(&st, need(&f, "port")?.parse()?),
        "get" => match st.read()? {
            Some((_, v)) => Ok(std::io::stdout().write_all(v.as_bytes())?),
            None => bail!("no state under {} in {}", st.name, st.vault),
        },
        "put" => {
            let mut v = String::new();
            std::io::stdin().read_to_string(&mut v)?;
            if v.is_empty() {
                bail!("refusing to write an empty state");
            }
            let m = st.write(&v)?;
            eprintln!("statestore: wrote generation {} ({} bytes, {} chunks)", m.generation, m.bytes, m.count);
            Ok(())
        }
        "show" => match st.read()? {
            Some((m, _)) => Ok(println!("{}", serde_json::to_string(&m)?)),
            None => bail!("no state under {} in {}", st.name, st.vault),
        },
        other => bail!("unknown command {other}"),
    }
}
