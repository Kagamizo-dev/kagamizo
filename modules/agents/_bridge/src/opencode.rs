//! `opencode serve` as a harness: one server per agent on the loopback,
//! spoken to over its own HTTP API (the calls below are the ones the
//! pinned server's OpenAPI document declares; ../_json/opencode-serve.json
//! keeps them, ../bridge.nix admits only calls that are in it, and the
//! test below holds this file to what is declared).
//!
//!   POST /session                          a new thread
//!   POST /session/{sessionID}/message      one turn, answered whole
//!   POST /session/{sessionID}/abort        stop a turn that outlasts its
//!                                          deadline
//!
//! The harness retries a failing provider with growing waits and no end
//! (seen 2026-11-17), so a turn has a deadline here: when it passes, the
//! turn is stopped in the harness and reported as failed.
use crate::{Agent, Harness, Reply};
use serde_json::{json, Value};
use std::time::Duration;

/// The calls this file makes, as the catalog names them.
pub const CALLS: [&str; 3] = ["POST /session", "POST /session/{sessionID}/message", "POST /session/{sessionID}/abort"];

pub struct OpenCode {
    /// The longest a turn may take.
    pub patience: Duration,
}

/// The text of an answer: its text parts, without what the harness wrote
/// to itself.
pub fn text(answer: &Value) -> String {
    answer["parts"]
        .as_array()
        .map(|parts| parts.iter().filter(|p| p["type"] == "text" && p["synthetic"] != true && p["ignored"] != true).filter_map(|p| p["text"].as_str()).collect::<Vec<_>>().join("\n\n"))
        .unwrap_or_default()
}

/// The tokens a turn read and wrote, as the harness reports them: cached
/// reads and writes count as read, reasoning as written. Nothing if the
/// harness reports none, so an uncounted turn is never taken as free.
pub fn tokens(answer: &Value) -> Option<(u64, u64)> {
    let t = &answer["info"]["tokens"];
    let n = |v: &Value| v.as_u64().unwrap_or(0);
    let read = t["input"].as_u64()? + n(&t["cache"]["read"]) + n(&t["cache"]["write"]);
    let written = t["output"].as_u64()? + n(&t["reasoning"]);
    (read + written > 0).then_some((read, written))
}

fn failure(what: &str, e: ureq::Error) -> String {
    match e {
        ureq::Error::Status(code, _) => format!("{what}: {code}"),
        ureq::Error::Transport(t) => format!("{what}: {t}"),
    }
}

impl Harness for OpenCode {
    fn turn(&mut self, agent: &Agent, session: Option<&str>, said: &str) -> Result<(String, Reply), String> {
        let base = format!("http://127.0.0.1:{}", agent.port);
        let session = match session {
            Some(s) => s.to_owned(),
            None => {
                let made: Value = ureq::post(&format!("{base}/session")).timeout(Duration::from_secs(30)).send_json(json!({ "title": agent.name })).map_err(|e| failure("a new thread", e))?.into_json().map_err(|e| e.to_string())?;
                made["id"].as_str().ok_or("the harness gave no thread")?.to_owned()
            }
        };
        let body = json!({
            "model": { "providerID": "openrouter", "modelID": agent.model },
            "parts": [{ "type": "text", "text": said }],
        });
        let sent = ureq::post(&format!("{base}/session/{session}/message")).timeout(self.patience).send_json(body);
        let answer: Value = match sent {
            Ok(response) => response.into_json().map_err(|e| e.to_string())?,
            Err(e) => {
                // Whatever went wrong, the turn must not go on by itself.
                let _ = ureq::post(&format!("{base}/session/{session}/abort")).timeout(Duration::from_secs(10)).call();
                return Err(failure("the turn, now stopped", e));
            }
        };
        if !answer["info"]["error"].is_null() {
            return Err(format!("the harness reports {}", answer["info"]["error"]["name"].as_str().unwrap_or("an error")));
        }
        let (tokens_in, tokens_out) = tokens(&answer).ok_or("the harness reported no tokens for the turn, so it cannot be charged")?;
        Ok((session, Reply { text: text(&answer), tokens_in, tokens_out }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_calls_made_are_the_calls_declared() {
        let declared: Vec<String> = serde_json::from_str(include_str!(env!("BRIDGE_CALLS"))).unwrap();
        assert_eq!(declared, CALLS);
    }

    #[test]
    fn an_answer_is_its_text_parts_only() {
        let answer = json!({ "info": { "cost": 0.002 }, "parts": [
            { "type": "step-start" },
            { "type": "reasoning", "text": "thinking" },
            { "type": "text", "text": "First." },
            { "type": "tool", "tool": "bash" },
            { "type": "text", "text": "to itself", "synthetic": true },
            { "type": "text", "text": "Second." },
        ] });
        assert_eq!(text(&answer), "First.\n\nSecond.");
        assert_eq!(text(&json!({})), "");
    }

    #[test]
    fn the_tokens_charged_are_all_that_was_read_and_written() {
        // As the pinned server answered a rehearsed turn, 2026-11-17.
        let answer = json!({ "info": { "cost": 0.000120732, "tokens": { "total": 2256, "input": 2245, "output": 11, "reasoning": 0, "cache": { "write": 0, "read": 0 } } } });
        assert_eq!(tokens(&answer), Some((2245, 11)));
        let cached = json!({ "info": { "tokens": { "input": 10, "output": 5, "reasoning": 7, "cache": { "write": 3, "read": 100 } } } });
        assert_eq!(tokens(&cached), Some((113, 12)));
        assert_eq!(tokens(&json!({ "info": {} })), None);
        assert_eq!(tokens(&json!({ "info": { "tokens": { "input": 0, "output": 0 } } })), None);
    }
}
