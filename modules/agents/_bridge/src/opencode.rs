//! `opencode serve` as a harness: one server per agent on the loopback,
//! spoken to over its own HTTP API (the calls below are the ones the
//! pinned server's OpenAPI document declares; ../_json/opencode-serve.json
//! keeps them, ../bridge.nix admits only calls that are in it, and the
//! test below holds this file to what is declared).
//!
//!   POST /session                          a new thread
//!   POST /session/{sessionID}/message      one turn, answered whole
use crate::{Agent, Harness, Reply};
use serde_json::{json, Value};
use std::time::Duration;

/// The calls this file makes, as the catalog names them.
pub const CALLS: [&str; 2] = ["POST /session", "POST /session/{sessionID}/message"];

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
        let answer: Value = ureq::post(&format!("{base}/session/{session}/message")).timeout(self.patience).send_json(body).map_err(|e| failure("the turn", e))?.into_json().map_err(|e| e.to_string())?;
        if !answer["info"]["error"].is_null() {
            return Err(format!("the harness reports {}", answer["info"]["error"]["name"].as_str().unwrap_or("an error")));
        }
        Ok((session, Reply { text: text(&answer), cost_usd: answer["info"]["cost"].as_f64().unwrap_or(0.0) }))
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
}
