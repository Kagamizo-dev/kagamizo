//! chat-rehearsal-server: the site and the chat pages on one loopback
//! port, over a real homeserver, for the whole-chain check
//! (../../../_bridge/src/bin/chat-whole-check.rs).
//!
//!   chat-rehearsal-server SITE_DIR PORT HOMESERVER_URL AS_TOKEN_FILE
//!
//! The static pages are served from SITE_DIR at /next/, and the chat pages
//! at /next/chat/ by the same code the gateway runs, speaking to the
//! homeserver given with the application service's token: so what is sent
//! from the page is in a real room, where the bridge and an agent answer
//! it. There is no Access in front of a check, so every request is the
//! owner's. This program is never on the host.
use chat_gateway::serve::serve;
use chat_gateway::Chat;
use matrix_rooms::http::Http;
use matrix_rooms::Declared;
use std::path::Path;
use std::process::ExitCode;

fn run(args: &[String]) -> Result<(), String> {
    let [site, port, homeserver, token_file] = args else {
        return Err("usage: chat-rehearsal-server SITE_DIR PORT HOMESERVER_URL AS_TOKEN_FILE".into());
    };
    let port: u16 = port.parse().map_err(|_| format!("{port} is not a port"))?;
    let declared = Declared::compiled()?;
    let token = std::fs::read_to_string(token_file).map_err(|e| format!("{token_file}: {e}"))?;
    let server = Http::new(homeserver, &declared.server, &token);
    let chat = Chat { declared, owner: "the-check".into(), prefix: "/next/chat".into(), server };
    serve(port, chat, |_| Some("the-check".into()), Some((Path::new(site), "/next")))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("chat-rehearsal-server: {e}");
            ExitCode::FAILURE
        }
    }
}
