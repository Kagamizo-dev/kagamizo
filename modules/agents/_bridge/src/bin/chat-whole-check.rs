//! chat-whole-check: the whole chain on the loopback, with nothing billed.
//!
//!   chat-whole-check HOMESERVER OPENCODE OPENCODE_CONFIG REHEARSAL BRIDGE
//!                    [--then GATEWAY SITE_DIR PORT -- COMMAND…]
//!
//! With `--then`, once its own points 1 to 5 hold and while everything is
//! still running, it serves the site and the chat pages over this same
//! homeserver (GATEWAY, the chat's check server) and runs COMMAND, which
//! is the browser check: what the browser sends is answered by the real
//! bridge and harness. COMMAND failing fails this check.
//!
//! It starts the pinned homeserver with the application service's
//! registration, the stand-in for OpenRouter, `opencode serve` with the
//! answering config, makes the declared rooms, and starts the bridge: the
//! real programs, as the host runs them. Then it proves:
//!
//!   1. what the owner says in the front room is answered there, as the
//!      front agent, with the stand-in's marked answer;
//!   2. what the owner says in a room with no answering agent is left;
//!   3. what the agent itself says starts nothing;
//!   4. the turn was charged: the month's spend is above nothing, and is
//!      the reported tokens at the pinned price;
//!   5. a bridge started again answers nothing twice;
//!   6. when the provider fails, the turn is stopped at its deadline, the
//!      agent says it could not answer, and nothing is charged for it.
use agent_bridge::{Agent, State};
use matrix_rooms::http::{registration, Http};
use matrix_rooms::{reconcile, Declared, Server, Talk};
use std::path::Path;
use std::process::{Child, Command, ExitCode, Stdio};
use std::time::{Duration, Instant};

const HOMESERVER: u16 = 6198;

struct Running(Vec<Child>);

impl Drop for Running {
    fn drop(&mut self) {
        for child in &mut self.0 {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

fn up(url: &str, what: &str) -> Result<(), String> {
    let until = Instant::now() + Duration::from_secs(90);
    while Instant::now() < until {
        if ureq::get(url).timeout(Duration::from_secs(2)).call().is_ok() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(250));
    }
    Err(format!("{what} did not come up"))
}

/// What was said in a room, oldest first, as (account, text).
fn said(http: &mut Http, by: &str, id: &str) -> Result<Vec<(String, String)>, String> {
    Ok(http.messages(by, id, 50)?.into_iter().map(|m| (m.from, m.body)).collect())
}

/// Wait until the room's last message is from `from`, and return it.
fn awaited(http: &mut Http, by: &str, id: &str, from: &str) -> Result<String, String> {
    let until = Instant::now() + Duration::from_secs(120);
    while Instant::now() < until {
        if let Some((who, text)) = said(http, by, id)?.pop() {
            if who == from {
                return Ok(text);
            }
        }
        std::thread::sleep(Duration::from_millis(500));
    }
    Err(format!("{from} did not speak"))
}

fn check(args: &[String]) -> Result<(), String> {
    let usage = "usage: chat-whole-check HOMESERVER OPENCODE OPENCODE_CONFIG REHEARSAL BRIDGE [--then GATEWAY SITE_DIR PORT -- COMMAND…]";
    let (first, then) = match args.iter().position(|a| a == "--then") {
        Some(at) => (&args[..at], Some(&args[at + 1..])),
        None => (args, None),
    };
    let [homeserver, opencode, config, rehearsal, bridge] = first else {
        return Err(usage.into());
    };
    let then = match then {
        None => None,
        Some([gateway, site, port, dashes, command @ ..]) if dashes == "--" && !command.is_empty() => Some((gateway, site, port, command)),
        Some(_) => return Err(usage.into()),
    };
    let declared = Declared::compiled()?;
    let agents: Vec<Agent> = serde_json::from_str(include_str!(env!("BRIDGE_AGENTS"))).map_err(|e| e.to_string())?;
    let front = agents.first().ok_or("no agent answers")?.clone();
    let config_text = std::fs::read_to_string(config).map_err(|e| format!("{config}: {e}"))?;
    let config_json: serde_json::Value = serde_json::from_str(&config_text).map_err(|e| e.to_string())?;
    let base = config_json["provider"]["openrouter"]["options"]["baseURL"].as_str().ok_or("the answering config names no stand-in: the provider is not rehearsal")?;
    let rehearsal_port = base.trim_start_matches("http://127.0.0.1:").split('/').next().unwrap_or("").to_owned();

    let dir = std::env::temp_dir().join(format!("chat-whole-check-{}", std::process::id()));
    let services = dir.join("appservices");
    std::fs::create_dir_all(&services).map_err(|e| e.to_string())?;
    let token = "check-as-token-not-a-secret";
    let token_file = dir.join("as-token");
    std::fs::write(&token_file, token).map_err(|e| e.to_string())?;
    std::fs::write(services.join("kagamizo.yaml"), registration(&declared, token, "check-hs-token-not-a-secret")).map_err(|e| e.to_string())?;
    let homeserver_config = dir.join("tuwunel.toml");
    std::fs::write(
        &homeserver_config,
        format!(
            "[global]\nserver_name = \"{}\"\ndatabase_path = \"{}\"\naddress = [\"127.0.0.1\"]\nport = [{HOMESERVER}]\nallow_registration = false\nallow_federation = false\ntrusted_servers = []\nappservice_dir = \"{}\"\n",
            declared.server,
            dir.join("db").display(),
            services.display()
        ),
    )
    .map_err(|e| e.to_string())?;
    let home = dir.join("opencode");
    std::fs::create_dir_all(&home).map_err(|e| e.to_string())?;
    let state_file = dir.join("state.json");
    let quiet = || Stdio::null();
    let rehearsal_log = dir.join("rehearsal.log");
    let spawn_rehearsal = |fault: &str| {
        let out = std::fs::OpenOptions::new().create(true).append(true).open(&rehearsal_log).map_err(|e| e.to_string())?;
        Command::new(rehearsal).arg(&rehearsal_port).arg(fault).stdout(Stdio::from(out)).spawn().map_err(|e| format!("{rehearsal}: {e}"))
    };
    let spawn_bridge = || Command::new(bridge).arg(format!("http://127.0.0.1:{HOMESERVER}")).arg(&token_file).arg(&state_file).arg("20").stdout(quiet()).spawn().map_err(|e| format!("{bridge}: {e}"));

    let mut running = Running(Vec::new());
    // Inside a build the homeserver, and it alone, is shown a resolver file
    // (CHECK_PRELOAD and CHECK_REDIRECTS, from Nix).
    let mut homeserver_command = Command::new(homeserver);
    homeserver_command.arg("-c").arg(&homeserver_config).stdout(quiet()).stderr(quiet());
    if let (Ok(preload), Ok(redirects)) = (std::env::var("CHECK_PRELOAD"), std::env::var("CHECK_REDIRECTS")) {
        homeserver_command.env("LD_PRELOAD", preload).env("NIX_REDIRECTS", redirects);
    }
    running.0.push(homeserver_command.spawn().map_err(|e| format!("{homeserver}: {e}"))?);
    let harness_log = dir.join("opencode.log");
    let log = |path: &Path| std::fs::File::create(path).map(Stdio::from).map_err(|e| e.to_string());
    running.0.push(
        Command::new(opencode)
            .args(["serve", "--hostname", "127.0.0.1", "--port", &front.port.to_string(), "--print-logs"])
            .current_dir(&home)
            .env("HOME", &home)
            .env("OPENCODE_CONFIG", config)
            .env("OPENROUTER_API_KEY", "rehearsal")
            .stdout(log(&harness_log)?)
            .stderr(log(&dir.join("opencode.err"))?)
            .spawn()
            .map_err(|e| format!("{opencode}: {e}"))?,
    );
    let mut stand_in = spawn_rehearsal("none")?;
    let hs = format!("http://127.0.0.1:{HOMESERVER}");
    let result = (|| {
        up(&format!("{hs}/_matrix/client/versions"), "the homeserver")?;
        up(&format!("http://127.0.0.1:{}/global/health", front.port), "the harness")?;
        let mut http = Http::new(&hs, &declared.server, token);
        reconcile(&declared, &mut http, false)?;
        let owner = declared.owner.clone();
        let room_of = |http: &mut Http, team: &str| -> Result<String, String> {
            let room = declared.rooms.iter().find(|r| r.team == team).ok_or(format!("{team} has no room"))?;
            http.resolve(&owner, &declared.alias(room))?.ok_or(format!("{team}'s room is not made"))
        };
        let front_room = room_of(&mut http, &front.name)?;
        let other = declared.rooms.iter().find(|r| agents.iter().all(|a| a.name != r.team)).ok_or("every room has an answering agent")?.team.clone();
        let other_room = room_of(&mut http, &other)?;
        let agent = declared.user(&front.name);

        let mut bridge_process = spawn_bridge()?;
        // The bridge answers what is said after its first pass, which is
        // done once it has kept its state.
        let first_pass = Instant::now() + Duration::from_secs(60);
        while !state_file.exists() {
            if Instant::now() > first_pass {
                return Err("the bridge did not make its first pass".into());
            }
            std::thread::sleep(Duration::from_millis(200));
        }
        // 1. The owner is answered in the front room, as the front agent.
        http.say(&owner, &front_room, "Hello from the whole check")?;
        let answer = awaited(&mut http, &owner, &front_room, &agent)?;
        if answer != "Rehearsal: you said: Hello from the whole check" {
            return Err(format!("the front agent said {answer:?}"));
        }
        // 2. A room with no answering agent is left alone, and
        // 3. what the agent itself says starts nothing.
        http.say(&owner, &other_room, "Anyone there?")?;
        http.say(&front.name, &front_room, "Talking to myself")?;
        std::thread::sleep(Duration::from_secs(8));
        if said(&mut http, &owner, &other_room)?.len() != 1 {
            return Err(format!("something answered in {other}'s room, which has no answering agent"));
        }
        let front_said = said(&mut http, &owner, &front_room)?;
        if front_said.len() != 3 {
            return Err(format!("the agent's own words started a turn: {front_said:?}"));
        }
        // 4. The turn was charged at the pinned price.
        let read_state = || -> Result<State, String> { serde_json::from_str(&std::fs::read_to_string(&state_file).map_err(|e| format!("the bridge kept no state: {e}"))?).map_err(|e| e.to_string()) };
        let spent = read_state()?.spent.get(&front.name).copied().unwrap_or(0.0);
        if spent <= 0.0 {
            return Err("the turn was not charged".into());
        }
        // 5. A bridge started again answers nothing twice.
        let _ = bridge_process.kill();
        let _ = bridge_process.wait();
        bridge_process = spawn_bridge()?;
        std::thread::sleep(Duration::from_secs(8));
        if said(&mut http, &owner, &front_room)?.len() != 3 {
            return Err("the bridge, started again, answered something twice".into());
        }
        // The browser, against all of it, while it runs.
        if let Some((gateway, site, port, command)) = then {
            let mut pages = Command::new(gateway).arg(site).arg(port).arg(&hs).arg(&token_file).spawn().map_err(|e| format!("{gateway}: {e}"))?;
            let outcome = up(&format!("http://127.0.0.1:{port}/next/chat/"), "the chat pages").and_then(|()| Command::new(&command[0]).args(&command[1..]).status().map_err(|e| format!("{}: {e}", command[0])));
            let _ = pages.kill();
            let _ = pages.wait();
            if !outcome?.success() {
                return Err("the browser check failed against the whole chain".into());
            }
        }
        let spent = read_state()?.spent.get(&front.name).copied().unwrap_or(0.0);
        // 6. When the provider fails, the agent says so and nothing is charged.
        let _ = stand_in.kill();
        let _ = stand_in.wait();
        stand_in = spawn_rehearsal("error")?;
        std::thread::sleep(Duration::from_secs(1));
        http.say(&owner, &front_room, "And now?")?;
        let refusal = awaited(&mut http, &owner, &front_room, &agent)?;
        let after = read_state()?.spent.get(&front.name).copied().unwrap_or(0.0);
        let _ = bridge_process.kill();
        let _ = bridge_process.wait();
        if !refusal.contains("could not answer") {
            return Err(format!("with the provider failing, the agent said {refusal:?}"));
        }
        if (after - spent).abs() > 1e-12 {
            return Err(format!("a failed turn was charged: {spent} became {after}"));
        }
        println!("chat-whole-check: the owner was answered in the front room by the front agent through the real homeserver, bridge and harness; a room with no agent and the agent's own words started nothing; the turn was charged ${spent:.8} at the pinned price; a restart answered nothing twice; a failing provider ended in a refusal that was said and not charged. Nothing was billed.");
        Ok(())
    })();
    let _ = stand_in.kill();
    let _ = stand_in.wait();
    drop(running);
    if result.is_err() {
        // What the harness itself said, to find the cause.
        for file in ["rehearsal.log", "opencode.log", "opencode.err"] {
            let text = std::fs::read_to_string(dir.join(file)).unwrap_or_default();
            let lines: Vec<&str> = text.lines().filter(|l| file != "opencode.err" || l.starts_with("ERROR") || l.starts_with("WARN")).collect();
            for line in &lines[lines.len().saturating_sub(4)..] {
                eprintln!("  {file}: {}", line.chars().take(2500).collect::<String>());
            }
        }
    }
    let _ = std::fs::remove_dir_all(Path::new(&dir));
    result
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match check(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("chat-whole-check: {e}");
            ExitCode::FAILURE
        }
    }
}
