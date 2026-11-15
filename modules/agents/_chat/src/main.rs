//! chat-gateway: the chat pages, on the loopback (./lib.rs).
//!
//!   chat-gateway PORT PREFIX HOMESERVER_URL AS_TOKEN_FILE OWNER_ADDRESS ACCESS_TEAM
//!
//! It serves only the owner, as Cloudflare Access vouches for them
//! (./access.rs), and reaches the homeserver with the application
//! service's token read from a file. The rooms are compiled in.
use chat_gateway::access::Access;
use chat_gateway::serve::serve;
use chat_gateway::Chat;
use matrix_rooms::http::Http;
use matrix_rooms::Declared;
use std::process::ExitCode;

fn run(args: &[String]) -> Result<(), String> {
    let [port, prefix, homeserver, token_file, owner, team] = args else {
        return Err("usage: chat-gateway PORT PREFIX HOMESERVER_URL AS_TOKEN_FILE OWNER_ADDRESS ACCESS_TEAM".into());
    };
    let port: u16 = port.parse().map_err(|_| format!("{port} is not a port"))?;
    let declared = Declared::compiled()?;
    let token = std::fs::read_to_string(token_file).map_err(|e| format!("{token_file}: {e}"))?;
    let server = Http::new(homeserver, &declared.server, &token);
    let chat = Chat { declared, owner: owner.clone(), prefix: prefix.trim_end_matches('/').to_owned(), server };
    let mut access = Access::new(team);
    serve(port, chat, move |assertion| access.who(assertion?), None)
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("chat-gateway: {e}");
            ExitCode::FAILURE
        }
    }
}
