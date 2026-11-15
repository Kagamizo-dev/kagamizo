//! matrix-rooms: the declared rooms (../rooms.nix), made on the homeserver.
//!
//!   matrix-rooms registration OUT AS_TOKEN_FILE HS_TOKEN_FILE
//!       writes the application service's registration for the homeserver
//!       to read at its start: a namespace of exactly the declared accounts
//!       and aliases
//!   matrix-rooms look  BASE_URL AS_TOKEN_FILE   reads only; says what a run would do
//!   matrix-rooms apply BASE_URL AS_TOKEN_FILE   does it
//!
//! The one credential is the application service's token, read from a
//! file: no password, no sign-in and no session. The rooms are compiled in
//! (MATRIX_ROOMS, from Nix), so the program cannot make a room that is not
//! declared.
use matrix_rooms::http::{registration, Http};
use matrix_rooms::{reconcile, Declared};
use std::process::ExitCode;

fn read(path: &str) -> Result<String, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    if text.trim().is_empty() {
        return Err(format!("{path}: empty"));
    }
    Ok(text.trim().to_owned())
}

fn run(args: &[&str]) -> Result<bool, String> {
    let declared = Declared::compiled()?;
    let (look, base, token) = match args {
        ["registration", out, as_file, hs_file] => {
            std::fs::write(out, registration(&declared, &read(as_file)?, &read(hs_file)?)).map_err(|e| format!("{out}: {e}"))?;
            return Ok(true);
        }
        ["look", base, token] => (true, base, token),
        ["apply", base, token] => (false, base, token),
        _ => return Err("usage: matrix-rooms registration OUT AS_TOKEN_FILE HS_TOKEN_FILE | look|apply BASE_URL AS_TOKEN_FILE".into()),
    };
    let mut http = Http::new(base, &declared.server, &read(token)?);
    let steps = reconcile(&declared, &mut http, look)?;
    for step in &steps {
        println!("matrix-rooms: {}{step}", if look && !step.is_finding() { "would: " } else { "" });
    }
    println!("matrix-rooms: {} rooms declared, {} step(s){}", declared.rooms.len(), steps.len(), if look { " to take" } else { "" });
    Ok(!steps.iter().any(|s| s.is_finding()))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args.iter().map(String::as_str).collect::<Vec<_>>()) {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(e) => {
            eprintln!("matrix-rooms: {e}");
            ExitCode::FAILURE
        }
    }
}
