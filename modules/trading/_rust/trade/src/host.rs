//! `trading-host`: how jingzo-host's paper-trading units start `trade`,
//! with no shell. It signs pass-cli in with the host's agent token, handed
//! to pass-cli in its environment only (never an argument, never printed),
//! then runs the command in its place.
//!
//!   trading-host <token-file> <program> [args...]
//!
//! With no token file the host is not provisioned yet: it says so and exits
//! 0, so a timer firing before then is idle, not failed.
use std::os::unix::process::CommandExt;
use std::process::{Command, ExitCode, Stdio};

fn signed_in() -> bool {
    Command::new("pass-cli")
        .arg("info")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [token_file, program, rest @ ..] = args.as_slice() else {
        eprintln!("usage: trading-host <token-file> <program> [args...]");
        return ExitCode::from(2);
    };
    if !signed_in() {
        let Ok(token) = std::fs::read_to_string(token_file) else {
            eprintln!("trading-host: no host token at {token_file}; idle");
            return ExitCode::SUCCESS;
        };
        let login = Command::new("pass-cli")
            .arg("login")
            .env("PROTON_PASS_PERSONAL_ACCESS_TOKEN", token.trim())
            .stdout(Stdio::null())
            .status();
        if !login.is_ok_and(|s| s.success()) {
            eprintln!("trading-host: pass-cli login with the host token failed");
            return ExitCode::FAILURE;
        }
    }
    let err = Command::new(program).args(rest).exec();
    eprintln!("trading-host: {program}: {err}");
    ExitCode::FAILURE
}
