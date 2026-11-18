//! A stand-in for OpenRouter, so the whole stack runs and nothing is
//! billed (the owner's rule, 2026-11-17: credit is the last step, after
//! everything is tested and shown).
//!
//! The real homeserver, gateway, bridge and harness run against it; only
//! the model behind them is rehearsed. It answers the call a harness makes
//! for a turn:
//!
//!   POST <any prefix>/chat/completions    streamed or whole
//!
//! What it says is fixed and plainly marked ("Rehearsal: you said: …"), so
//! no one can take it for a model. What it reports as the cost is what the
//! pinned prices give for the tokens it counts (REHEARSAL_PRICES, the
//! price table the spend tools use), so every ledger and cap is exercised
//! on real numbers.
//!
//! It can be told to misbehave, one fault for the run, so each failure is
//! seen to end in a refusal and not in silence: `error` (the provider
//! fails), `no-cost` (an answer with no cost reported), `dear` (an answer
//! billed a thousand times over).
//!
//! `answer` and `stream` are pure, so what is sent is tested without a
//! socket; ./main.rs listens.
use serde_json::{json, Value};

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Fault {
    None,
    Error,
    NoCost,
    Dear,
}

impl Fault {
    pub fn named(name: &str) -> Option<Fault> {
        Some(match name {
            "" | "none" => Fault::None,
            "error" => Fault::Error,
            "no-cost" => Fault::NoCost,
            "dear" => Fault::Dear,
            _ => return None,
        })
    }
}

/// A model's pinned price, dollars per million tokens in and out.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Price {
    pub input: f64,
    pub output: f64,
}

/// The price a model is rehearsed at: its dearest pinned provider, so a
/// rehearsal never flatters a cap.
pub fn price(table: &Value, model: &str) -> Option<Price> {
    let rows = table["models"][model].as_array()?;
    let most = |field: &str| rows.iter().filter_map(|r| r[field].as_f64()).fold(None, |m: Option<f64>, x| Some(m.map_or(x, |m| m.max(x))));
    Some(Price { input: most("input")?, output: most("output")? })
}

/// The text of a message, whether it is a string or a list of parts.
fn text(content: &Value) -> String {
    match content {
        Value::String(s) => s.clone(),
        Value::Array(parts) => parts.iter().filter_map(|p| p["text"].as_str()).collect::<Vec<_>>().join("\n"),
        _ => String::new(),
    }
}

/// Tokens, counted the one way a rehearsal can: four bytes to a token.
fn tokens(s: &str) -> u64 {
    (s.len() as u64).div_ceil(4)
}

pub struct Answer {
    pub model: String,
    pub text: String,
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
    /// Dollars, as the pinned price gives them; nothing under `NoCost`.
    pub cost: Option<f64>,
}

/// What is answered to a chat request, or why not.
pub fn answer(request: &Value, table: &Value, fault: Fault) -> Result<Answer, (u16, String)> {
    if fault == Fault::Error {
        return Err((502, "the rehearsed provider fails".into()));
    }
    let model = request["model"].as_str().ok_or((400, "no model".to_owned()))?;
    let price = price(table, model).ok_or((404, format!("{model} is not a pinned model")))?;
    let messages = request["messages"].as_array().ok_or((400, "no messages".to_owned()))?;
    let said = messages.iter().rev().find(|m| m["role"] == "user").map(|m| text(&m["content"])).unwrap_or_default();
    let reply = format!("Rehearsal: you said: {}", said.trim());
    let prompt_tokens = messages.iter().map(|m| tokens(&text(&m["content"]))).sum();
    let completion_tokens = tokens(&reply);
    let usd = (prompt_tokens as f64 * price.input + completion_tokens as f64 * price.output) / 1_000_000.0;
    let cost = match fault {
        Fault::NoCost => None,
        Fault::Dear => Some(usd * 1000.0),
        _ => Some(usd),
    };
    Ok(Answer { model: model.to_owned(), text: reply, prompt_tokens, completion_tokens, cost })
}

fn usage(a: &Answer) -> Value {
    let mut u = json!({ "prompt_tokens": a.prompt_tokens, "completion_tokens": a.completion_tokens, "total_tokens": a.prompt_tokens + a.completion_tokens });
    if let Some(cost) = a.cost {
        u["cost"] = json!(cost);
    }
    u
}

/// The answer whole, as a chat completion.
pub fn whole(a: &Answer) -> Value {
    json!({
        "id": "rehearsal", "object": "chat.completion", "created": 0, "model": a.model, "provider": "Rehearsal",
        "choices": [{ "index": 0, "finish_reason": "stop", "message": { "role": "assistant", "content": a.text } }],
        "usage": usage(a),
    })
}

/// The answer as the events of a stream: the text in pieces, then the end
/// with what was used.
pub fn stream(a: &Answer) -> String {
    let chunk = |delta: Value, finish: Value, usage: Option<Value>| {
        let mut c = json!({ "id": "rehearsal", "object": "chat.completion.chunk", "created": 0, "model": a.model, "provider": "Rehearsal", "choices": [{ "index": 0, "delta": delta, "finish_reason": finish }] });
        if let Some(u) = usage {
            c["usage"] = u;
        }
        format!("data: {c}\n\n")
    };
    let mut out = chunk(json!({ "role": "assistant", "content": "" }), Value::Null, None);
    let mut rest = a.text.as_str();
    while !rest.is_empty() {
        let mut at = rest.len().min(24);
        while !rest.is_char_boundary(at) {
            at += 1;
        }
        out.push_str(&chunk(json!({ "content": &rest[..at] }), Value::Null, None));
        rest = &rest[at..];
    }
    out.push_str(&chunk(json!({}), json!("stop"), Some(usage(a))));
    out.push_str("data: [DONE]\n\n");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table() -> Value {
        json!({ "models": { "m/one": [{ "provider": "cheap", "input": 0.05, "output": 0.2 }, { "provider": "dear", "input": 0.3, "output": 1.2 }] } })
    }

    fn request(said: Value) -> Value {
        json!({ "model": "m/one", "stream": true, "messages": [{ "role": "system", "content": "be brief" }, { "role": "user", "content": said }] })
    }

    #[test]
    fn it_says_what_it_was_told_and_says_it_is_a_rehearsal() {
        let a = answer(&request(json!("hello there")), &table(), Fault::None).unwrap();
        assert_eq!(a.text, "Rehearsal: you said: hello there");
        let parts = answer(&request(json!([{ "type": "text", "text": "in" }, { "type": "text", "text": "parts" }])), &table(), Fault::None).unwrap();
        assert_eq!(parts.text, "Rehearsal: you said: in\nparts");
    }

    #[test]
    fn the_cost_is_the_dearest_pinned_price_for_the_tokens_counted() {
        let a = answer(&request(json!("hello there")), &table(), Fault::None).unwrap();
        // "be brief" 2 + "hello there" 3 tokens in; the 32-byte reply is 8 out.
        assert_eq!((a.prompt_tokens, a.completion_tokens), (5, 8));
        let want = (5.0 * 0.3 + 8.0 * 1.2) / 1_000_000.0;
        assert!((a.cost.unwrap() - want).abs() < 1e-15);
        assert_eq!(price(&table(), "m/one"), Some(Price { input: 0.3, output: 1.2 }));
    }

    #[test]
    fn a_model_that_is_not_pinned_is_refused() {
        let mut r = request(json!("x"));
        r["model"] = json!("m/unknown");
        assert_eq!(answer(&r, &table(), Fault::None).err().map(|e| e.0), Some(404));
    }

    #[test]
    fn each_fault_is_what_it_says() {
        assert_eq!(answer(&request(json!("x")), &table(), Fault::Error).err().map(|e| e.0), Some(502));
        assert_eq!(answer(&request(json!("x")), &table(), Fault::NoCost).unwrap().cost, None);
        let (fair, dear) = (answer(&request(json!("x")), &table(), Fault::None).unwrap(), answer(&request(json!("x")), &table(), Fault::Dear).unwrap());
        assert!((dear.cost.unwrap() - fair.cost.unwrap() * 1000.0).abs() < 1e-12);
        assert_eq!(Fault::named("bogus"), None);
        assert_eq!(Fault::named(""), Some(Fault::None));
    }

    #[test]
    fn a_stream_carries_the_whole_text_then_the_usage_then_the_end() {
        let a = answer(&request(json!("a longer thing to say, so that it is sent in more than one piece")), &table(), Fault::None).unwrap();
        let sent = stream(&a);
        let events: Vec<Value> = sent.split("\n\n").filter_map(|e| e.strip_prefix("data: ")).filter(|e| *e != "[DONE]").map(|e| serde_json::from_str(e).unwrap()).collect();
        let text: String = events.iter().filter_map(|e| e["choices"][0]["delta"]["content"].as_str()).collect();
        assert_eq!(text, a.text);
        let last = events.last().unwrap();
        assert_eq!(last["choices"][0]["finish_reason"], "stop");
        assert_eq!(last["usage"]["completion_tokens"], a.completion_tokens);
        assert!(sent.ends_with("data: [DONE]\n\n") && events.len() > 3);
    }

    #[test]
    fn with_no_cost_reported_the_usage_has_none() {
        let a = answer(&request(json!("x")), &table(), Fault::NoCost).unwrap();
        assert!(whole(&a)["usage"].get("cost").is_none());
        assert!(!stream(&a).contains("\"cost\""));
    }
}
