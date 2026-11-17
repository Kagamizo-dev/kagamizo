//! rehearsal: a stand-in for OpenRouter on the loopback (./lib.rs).
//!
//!   rehearsal PORT [FAULT]
//!
//! FAULT is none (the default), error, no-cost or dear. Every call it
//! answers is printed as one line, with no content: the path, the model
//! and the cost reported. It holds no key and reaches nothing.
use rehearsal::{answer, stream, whole, Fault};
use serde_json::Value;
use std::io::Read;
use std::process::ExitCode;

fn respond(request: tiny_http::Request, status: u16, content: &str, body: String) {
    let mut response = tiny_http::Response::from_string(body).with_status_code(status);
    for (name, value) in [("Content-Type", content), ("Cache-Control", "no-store")] {
        if let Ok(h) = tiny_http::Header::from_bytes(name.as_bytes(), value.as_bytes()) {
            response.add_header(h);
        }
    }
    let _ = request.respond(response);
}

fn run(args: &[String]) -> Result<(), String> {
    let (port, fault) = match args {
        [port] => (port, "none"),
        [port, fault] => (port, fault.as_str()),
        _ => return Err("usage: rehearsal PORT [none|error|no-cost|dear]".into()),
    };
    let port: u16 = port.parse().map_err(|_| format!("{port} is not a port"))?;
    let fault = Fault::named(fault).ok_or(format!("{fault} is not a fault"))?;
    let table: Value = serde_json::from_str(include_str!(env!("REHEARSAL_PRICES"))).map_err(|e| format!("the pinned prices do not read: {e}"))?;
    let server = tiny_http::Server::http(("127.0.0.1", port)).map_err(|e| format!("port {port}: {e}"))?;
    println!("rehearsal: listening on 127.0.0.1:{port}, fault {fault:?}; nothing here is billed");
    for mut request in server.incoming_requests() {
        let path = request.url().split('?').next().unwrap_or("").to_owned();
        if request.method().as_str() != "POST" || !path.ends_with("/chat/completions") {
            println!("rehearsal: {} {path}: not a rehearsed call", request.method());
            respond(request, 404, "application/json", r#"{"error":{"message":"not a rehearsed call","code":404}}"#.into());
            continue;
        }
        let mut body = String::new();
        let _ = request.as_reader().take(8 << 20).read_to_string(&mut body);
        let asked: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        match answer(&asked, &table, fault) {
            Ok(a) => {
                println!("rehearsal: {path}: {} answered, cost {}", a.model, a.cost.map_or("not reported".to_owned(), |c| format!("${c:.8}")));
                if asked["stream"] == true {
                    respond(request, 200, "text/event-stream", stream(&a));
                } else {
                    respond(request, 200, "application/json", whole(&a).to_string());
                }
            }
            Err((status, why)) => {
                println!("rehearsal: {path}: refused, {why}");
                respond(request, status, "application/json", serde_json::json!({ "error": { "message": why, "code": status } }).to_string());
            }
        }
    }
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("rehearsal: {e}");
            ExitCode::FAILURE
        }
    }
}
