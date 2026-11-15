//! matrix-rooms-check: the tool against a real homeserver, on the loopback.
//!
//!   matrix-rooms-check HOMESERVER_BINARY
//!
//! Starts the pinned homeserver in a scratch directory with the
//! application service's registration and nothing else (registration
//! closed, no federation), then proves what ../http.rs relies on:
//!   * with the service's token alone, every declared room is made, with
//!     its topic, holding the owner and its team: no password exists;
//!   * a second run does nothing;
//!   * the same calls with a wrong token are refused.
use matrix_rooms::http::{registration, Http};
use matrix_rooms::{reconcile, Declared, Server};
use std::process::{Command, ExitCode};

const PORT: u16 = 6199;

fn check(binary: &str) -> Result<(), String> {
    let declared = Declared::compiled()?;
    let dir = std::env::temp_dir().join(format!("matrix-rooms-check-{}", std::process::id()));
    let services = dir.join("appservices");
    std::fs::create_dir_all(&services).map_err(|e| e.to_string())?;
    let (as_token, hs_token) = ("check-as-token-not-a-secret", "check-hs-token-not-a-secret");
    std::fs::write(services.join("kagamizo.yaml"), registration(&declared, as_token, hs_token)).map_err(|e| e.to_string())?;
    let config = format!(
        "[global]\nserver_name = \"{}\"\ndatabase_path = \"{}\"\naddress = [\"127.0.0.1\"]\nport = [{PORT}]\nallow_registration = false\nallow_federation = false\ntrusted_servers = []\nappservice_dir = \"{}\"\n",
        declared.server,
        dir.join("db").display(),
        services.display()
    );
    let config_file = dir.join("tuwunel.toml");
    std::fs::write(&config_file, config).map_err(|e| e.to_string())?;
    let mut server = Command::new(binary).arg("-c").arg(&config_file).spawn().map_err(|e| format!("{binary}: {e}"))?;
    let base = format!("http://127.0.0.1:{PORT}");
    let result = (|| {
        let mut up = false;
        for _ in 0..150 {
            if ureq::get(&format!("{base}/_matrix/client/versions")).call().is_ok() {
                up = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(200));
        }
        if !up {
            return Err("the homeserver did not come up".to_owned());
        }
        let mut wrong = Http::new(&base, &declared.server, "not-the-token");
        if reconcile(&declared, &mut wrong, false).is_ok() {
            return Err("a wrong token was accepted".into());
        }
        let mut http = Http::new(&base, &declared.server, as_token);
        let first = reconcile(&declared, &mut http, false)?;
        if first.iter().any(|s| s.is_finding()) || first.is_empty() {
            return Err(format!("the first run: {first:?}"));
        }
        let second = reconcile(&declared, &mut Http::new(&base, &declared.server, as_token), false)?;
        if !second.is_empty() {
            return Err(format!("the second run was not empty: {second:?}"));
        }
        for room in &declared.rooms {
            let id = http.resolve(&declared.owner, &declared.alias(room))?.ok_or("a declared room is missing")?;
            let want: std::collections::BTreeSet<String> = room.members.iter().map(|m| declared.user(m)).collect();
            if http.joined(&declared.owner, &id)? != want {
                return Err(format!("{}: not exactly its declared members", room.alias));
            }
            if http.topic(&declared.owner, &id)?.as_deref() != Some(room.topic.as_str()) {
                return Err(format!("{}: not its declared topic", room.alias));
            }
        }
        println!("matrix-rooms-check: {} rooms made with the service's token alone; the second run did nothing; a wrong token was refused", declared.rooms.len());
        Ok(())
    })();
    let _ = server.kill();
    let _ = server.wait();
    let _ = std::fs::remove_dir_all(&dir);
    result
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [binary] = args.as_slice() else {
        eprintln!("usage: matrix-rooms-check HOMESERVER_BINARY");
        return ExitCode::from(2);
    };
    match check(binary) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("matrix-rooms-check: {e}");
            ExitCode::FAILURE
        }
    }
}
