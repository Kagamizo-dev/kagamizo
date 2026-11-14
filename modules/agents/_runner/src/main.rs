//! `agent-runner`: run a team's dsh headless session on jingzo-host from a
//! typed request (team, topic, brief), committing the result to an
//! `agents/<team>/<topic>` branch and pushing with the GitHub App's token.
//!
//! Usage:
//!   agent-runner <request-file>
//!
//! The request shape (serde, deny_unknown_fields):
//!   { "team": "<agent-name>", "topic": "<topic-slug>", "brief": "<brief-text>" }
//!
//! Environment (set by the systemd unit):
//!   WORKTREE_ROOT   -- /var/lib/dsh/work
//!   TEAMS_JSON_FILE -- path to teams.json (name -> model, key, tools, ...)
//!   OPENROUTER_API_KEY -- the team's key (from the host's secret env)
use std::fs;
use std::fs::OpenOptions;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json;

// -- Types --------------------------------------------------------------------

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    team: String,
    topic: String,
    brief: String,
}

#[derive(Deserialize)]
struct TeamEntry {
    model: String,
    key: Option<String>,
    purpose: Option<String>,
    personas: Option<Vec<String>>,
    tools: Option<Vec<String>>,
    change_classes: Option<Vec<String>>,
    #[serde(rename = "budgetUsdPerMonth")]
    budget: Option<u32>,
    charter: Option<serde_json::Value>,
}

const VALID_TEAMS: &[&str] = &[
    "research-jingzo",
    "legal-mirazo",
    "accounting-mirazo",
    "governance-mirazo",
    "legal-jingzo",
    "accounting-jingzo",
    "governance-jingzo",
    "security",
    "reverse-engineering",
    "browser",
    "review",
    "upkeep",
    "design",
    "twin",
    "builders",
];

fn validate_team(team: &str) -> bool {
    VALID_TEAMS.iter().any(|t| *t == team)
}

fn validate_topic(topic: &str) -> bool {
    if topic.len() == 0 || topic.len() > 128 {
        return false;
    }
    let first = topic.chars().next().expect("already checked len > 0");
    if !first.is_alphanumeric() {
        return false;
    }
    topic.chars().all(|c| c.is_alphanumeric() || c == '-')
}

// -- Helpers ------------------------------------------------------------------

fn bail(msg: String) -> ! {
    eprintln!("agent-runner: {}", msg);
    std::process::exit(1)
}

// -- Request reader ----------------------------------------------------------

fn read_request(path: &Path) -> Request {
    let text = fs::read_to_string(path).unwrap_or_else(|e| {
        bail(format!("cannot read {}: {}", path.to_string_lossy(), e));
    });
    let req = serde_json::from_str::<Request>(&text).unwrap_or_else(|e| {
        bail(format!("invalid request JSON: {}", e));
    });
    if !validate_team(&req.team) {
        bail(format!("team \"{}\" is not in agents.charters", req.team));
    }
    if !validate_topic(&req.topic) {
        bail(format!("topic \"{}\" is not a valid kebab-case slug", req.topic));
    }
    req
}

// -- Teams.json reader -------------------------------------------------------

fn load_model(team: &str, teams_path: &Path) -> String {
    let text = fs::read_to_string(teams_path).unwrap_or_else(|e| {
        bail(format!("cannot read teams.json: {}", e));
    });
    let all: BTreeMap<String, TeamEntry> =
        serde_json::from_str::<BTreeMap<String, TeamEntry>>(&text).unwrap_or_else(|e| {
            bail(format!("invalid teams.json: {}", e));
        });
    all.get(team).map(|e| e.model.clone()).unwrap_or_else(|| {
        bail(format!("team \"{}\" not found in teams.json", team));
    })
}

// -- Git helpers -------------------------------------------------------------

fn git(args: &[&str], cwd: &Path) -> ExitCode {
    let r = Command::new("git").args(args).current_dir(cwd).status();
    r.map(|s| if s.success() { ExitCode::SUCCESS } else { ExitCode::FAILURE })
     .unwrap_or(ExitCode::FAILURE)
}

fn git_output(args: &[&str], cwd: &Path) -> Option<String> {
    let r = Command::new("git").args(args).current_dir(cwd).output();
    if r.is_ok() {
        let out = r.unwrap().stdout;
        Some(String::from_utf8(out).unwrap())
    } else {
        None
    }
}

fn worktree_dir(workroot: &Path, branch: &str) -> PathBuf {
    let slug = branch.replace("/", "-");
    let p: PathBuf = workroot.join("..").join(&slug);
    p
}

fn ensure_worktree(workroot: &Path, branch: &str) -> PathBuf {
    let wt = worktree_dir(workroot, branch);
    // Remove any lingering worktree first.
    git(&["worktree", "remove", wt.to_str().expect("worktree path")], workroot);
    // Try adding; if branch does not exist yet, create it at HEAD.
    let code = git(&["worktree", "add", wt.to_str().expect("worktree path"), branch], workroot);
    if code != ExitCode::SUCCESS {
        let code2 = git(&["worktree", "add", "-B", branch, wt.to_str().expect("worktree path"), "HEAD"], workroot);
        if code2 != ExitCode::SUCCESS {
            bail(format!("could not create or reuse worktree at {}", wt.to_string_lossy()));
        }
    }
    wt
}

fn commit_and_push(worktree: &Path, team: &str, topic: &str, branch: &str) {
    let base = git_output(&["rev-parse", "HEAD"], worktree).unwrap_or("unknown".to_string());

    let code = git(&["add", "-A"], worktree);
    if code != ExitCode::SUCCESS {
        bail("git add failed".to_string());
    }

    let status = git_output(&["status", "--porcelain"], worktree).unwrap_or("".to_string());
    if status.trim().is_empty() {
        eprintln!("agent-runner: nothing to commit");
        return;
    }

    let msg = format!("agents({}): {}\n\nAutomated dsh headless session from jingzo-host.\n", team, topic);
    let code2 = git(&["commit", "-m", &msg], worktree);
    if code2 != ExitCode::SUCCESS {
        bail("git commit failed".to_string());
    }

    let push_code = git(&["push", "origin", branch], worktree);
    if push_code != ExitCode::SUCCESS {
        bail(format!("git push to {} failed", branch));
    }

    eprintln!("agent-runner: pushed {} (base {})", branch, base);
}

// -- dsh patch ---------------------------------------------------------------

fn render_patch(model: &str, worktree: &str) -> String {
    format!(
        r#"[
  {{"id":"llm-pi-ai","config":{{"providers":{{"openrouter":{{"displayName":"OpenRouter (Jingzo's agent key)","api":"openai-completions","baseURL":"https://openrouter.ai/api/v1","apiKeyEnv":"OPENROUTER_API_KEY","models":[{{"id":"{}","name":"{}"}}],"compat":{{"thinkingFormat":"openrouter"}}}}}}}}}},
  {{"id":"agent-default-model","config":{{"provider":"openrouter","model":"{}"}}}},
  {{"id":"sandbox-policy","config":{{"mode":"workspace-write","workspaceRoot":"{}"}}}},
  {{"id":"tool-bash","disabled":false}},
  {{"id":"web-search-deepseek","disabled":true}},
  {{"id":"web-deepseek-api","disabled":true}}
]"#,
        model, model, model, worktree
    )
}

// -- dsh runner --------------------------------------------------------------

fn run_dsh(worktree: &Path, request: &Request, patch_json: &str) -> ExitCode {
    let logdir = Path::new("/var/lib/dsh/log");
    let _ = fs::create_dir_all(&logdir);
    let logfile = logdir.join(format!("{}-{}.jsonl", request.team, request.topic));

    // Write the request file into the worktree so the session agent sees it.
    let request_file = worktree.join(".github/agents.request");
    let _ = fs::create_dir_all(&request_file);
    let _ = fs::write(&request_file, serde_json::to_string_pretty(&request).unwrap());

    // Open the log file with create+append options.
    let mut opts = OpenOptions::new();
    opts.create(true).append(true);
    let log_handle = opts.open(&logfile).unwrap_or_else(|e| {
        bail(format!("cannot open log file {}: {}", logfile.to_string_lossy(), e));
    });

    // Run dsh headless with the patch piped as a file descriptor.
    let r = Command::new("dsh")
        .args(&[
            "--profile", "headless",
            "--patch", patch_json,
            "--json",
            &request.brief,
        ])
        .current_dir(worktree)
        .env("DSH_HOME", "/var/lib/dsh")
        .stdout(Stdio::from(log_handle))
        .stderr(Stdio::inherit())
        .status();

    let status = r.unwrap_or_else(|e| {
        bail(format!("failed to start dsh: {}", e));
    });
    if !status.success() {
        eprintln!("agent-runner: dsh exited with status {}", status);
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

// -- Main --------------------------------------------------------------------

/// usage: agent-runner <request-file>
///        agent-runner --create-request <request-file> <team> <topic> <brief>
fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    let usage = "usage: agent-runner [--create-request OUTFILE team topic brief] <request-file>";

    if args.len() < 2 {
        eprintln!("{}", usage);
        return ExitCode::FAILURE;
    }

    if args.len() >= 2 && args[1] == "--create-request" {
        // --create-request <file> <team> <topic> <brief>
        if args.len() < 6 {
            eprintln!("usage: agent-runner --create-request <file> <team> <topic> <brief>");
            return ExitCode::FAILURE;
        }
        let outfile = Path::new(&args[2]);
        let req = Request {
            team: args[3].clone(),
            topic: args[4].clone(),
            brief: args[5].clone(),
        };
        if !validate_team(&req.team) {
            eprintln!("agent-runner: team \"{}\" is not in agents.charters", req.team);
            return ExitCode::FAILURE;
        }
        if !validate_topic(&req.topic) {
            eprintln!("agent-runner: topic \"{}\" is not a valid kebab-case slug", req.topic);
            return ExitCode::FAILURE;
        }
        let json = serde_json::to_string_pretty(&req).unwrap();
        // Write atomically: write to .new then rename.
        let tmp_str = format!("{}.new", outfile.to_string_lossy());
        let tmp_path = Path::new(&tmp_str);
        fs::write(&tmp_path, json).unwrap_or_else(|e| {
            bail(format!("cannot write {}: {}", tmp_str, e));
        });
        fs::rename(&tmp_path, outfile).unwrap_or_else(|e| {
            bail(format!("cannot rename {} -> {}: {}", tmp_str, outfile.to_string_lossy(), e));
        });
        return ExitCode::SUCCESS;
    }

    let request_path = Path::new(&args[1]);
    let request = read_request(&request_path);

    let workroot_str = std::env::var("WORKTREE_ROOT").unwrap_or("/var/lib/dsh/work".to_string());
    let workroot = Path::new(&workroot_str);
    let teams_file_str = std::env::var("TEAMS_JSON_FILE").unwrap_or("/var/lib/dsh/teams.json".to_string());

    let branch = format!("agents/{}/{}", request.team, request.topic);

    // Look up the team's model from the baked teams.json.
    let model = load_model(&request.team, Path::new(&teams_file_str));

    // Ensure the worktree exists.
    let wt = ensure_worktree(&workroot, &branch);

    // Render the dsh patch at runtime with the worktree path.
    let patch_json = render_patch(&model, wt.to_str().expect("worktree path"));

    // Run the session.
    let _ = run_dsh(&wt, &request, &patch_json);

    // Commit and push the result.
    commit_and_push(&wt, &request.team, &request.topic, &branch);

    ExitCode::SUCCESS
}