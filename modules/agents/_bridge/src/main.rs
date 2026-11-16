//! agent-bridge: what the owner says in a room becomes a turn of that
//! room's agent (./lib.rs).
//!
//!   agent-bridge HOMESERVER_URL AS_TOKEN_FILE STATE_FILE
//!
//! It reaches the homeserver with the application service's token, each
//! agent's harness on the loopback, and keeps its state (what was handled,
//! each room's thread, the month's spend) in STATE_FILE. The rooms and the
//! agents are compiled in.
use agent_bridge::opencode::OpenCode;
use agent_bridge::{Agent, Bridge, Did, State};
use matrix_rooms::http::Http;
use matrix_rooms::Declared;
use std::process::ExitCode;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// The month now, as YYYY-MM (UTC).
fn month() -> String {
    let days = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() / 86_400).unwrap_or(0) as i64;
    let z = days + 719_468;
    let (era, doe) = (z.div_euclid(146_097), z.rem_euclid(146_097));
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let mp = (5 * (doe - (365 * yoe + yoe / 4 - yoe / 100)) + 2) / 153;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    format!("{:04}-{m:02}", yoe + era * 400 + i64::from(m <= 2))
}

fn run(args: &[String]) -> Result<(), String> {
    let [homeserver, token_file, state_file] = args else {
        return Err("usage: agent-bridge HOMESERVER_URL AS_TOKEN_FILE STATE_FILE".into());
    };
    let declared = Declared::compiled()?;
    let agents: Vec<Agent> = serde_json::from_str(include_str!(env!("BRIDGE_AGENTS"))).map_err(|e| format!("the declared agents do not read: {e}"))?;
    let token = std::fs::read_to_string(token_file).map_err(|e| format!("{token_file}: {e}"))?;
    let state: State = std::fs::read_to_string(state_file).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default();
    let server = Http::new(homeserver, &declared.server, &token);
    let harness = OpenCode { patience: Duration::from_secs(600) };
    let mut bridge = Bridge { declared, agents, server, harness, state };
    println!("agent-bridge: {} agent(s) answering", bridge.agents.len());
    loop {
        let before = bridge.state.clone();
        for did in bridge.step(&month()) {
            match did {
                Did::Answered { room, cost_usd } => println!("agent-bridge: {room}: answered, ${cost_usd:.4}"),
                Did::Refused { room } => println!("agent-bridge: {room}: at its cap, not answered"),
                Did::Failed { room, why } => eprintln!("agent-bridge: {room}: {why}"),
            }
        }
        if bridge.state != before {
            let text = serde_json::to_string(&bridge.state).map_err(|e| e.to_string())?;
            let tmp = format!("{state_file}.new");
            std::fs::write(&tmp, text).and_then(|()| std::fs::rename(&tmp, state_file)).map_err(|e| format!("{state_file}: {e}"))?;
        }
        std::thread::sleep(Duration::from_secs(2));
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("agent-bridge: {e}");
            ExitCode::FAILURE
        }
    }
}
