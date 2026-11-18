//! chat-check-server: the whole site on one loopback port, for the browser
//! check (../../../shell/_e2e).
//!
//!   chat-check-server SITE_DIR PORT
//!
//! The static pages are served from SITE_DIR at /next/, and the chat pages
//! at /next/chat/ by the same code the gateway runs, against a homeserver
//! kept in memory with every declared room made. There is no Access in
//! front of a check, so every request is the owner's. This program is
//! never on the host.
use chat_gateway::serve::serve;
use chat_gateway::Chat;
use matrix_rooms::memory::Fake;
use matrix_rooms::{reconcile, Declared};
use std::path::Path;
use std::process::ExitCode;

fn run(args: &[String]) -> Result<(), String> {
    let [site, port] = args else {
        return Err("usage: chat-check-server SITE_DIR PORT".into());
    };
    let port: u16 = port.parse().map_err(|_| format!("{port} is not a port"))?;
    let declared = Declared::compiled()?;
    let mut server = Fake::named(&declared.server);
    reconcile(&declared, &mut server, false)?;
    let chat = Chat { declared, owner: "the-check".into(), prefix: "/next/chat".into(), server };
    serve(port, chat, |_| Some("the-check".into()), Some((Path::new(site), "/next")))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("chat-check-server: {e}");
            ExitCode::FAILURE
        }
    }
}
