//! matrix-rooms: the declared rooms (../rooms.nix), made on the homeserver.
//!
//!   matrix-rooms look  BASE_URL VAULT    reads only; says what a run would do
//!   matrix-rooms apply BASE_URL VAULT    does it
//!
//! Each account signs in with the login the host keeps for it in VAULT
//! (item `matrix-<localpart>`, read through pass-cli straight into this
//! program; no password is printed, logged or put in an argument), and is
//! signed out again when the run ends. The rooms are compiled in
//! (MATRIX_ROOMS, from Nix), so the program cannot make a room that is not
//! declared.
use matrix_rooms::{reconcile, Declared, Room, Server};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::process::{Command, ExitCode, Stdio};

struct Http {
    base: String,
    server: String,
    vault: String,
    tokens: BTreeMap<String, String>,
}

/// A path segment, percent-encoded.
fn seg(s: &str) -> String {
    s.bytes().map(|b| if b.is_ascii_alphanumeric() || b"-._~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect()
}

fn failure(what: &str, e: ureq::Error) -> String {
    match e {
        ureq::Error::Status(code, r) => {
            let body: Value = r.into_json().unwrap_or(Value::Null);
            format!("{what}: {code} {}", body["errcode"].as_str().unwrap_or(""))
        }
        ureq::Error::Transport(t) => format!("{what}: {t}"),
    }
}

/// The first non-empty string under `key`, wherever the item keeps it.
fn find(v: &Value, key: &str) -> Option<String> {
    match v {
        Value::Object(o) => o.get(key).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_owned).or_else(|| o.values().find_map(|c| find(c, key))),
        Value::Array(a) => a.iter().find_map(|c| find(c, key)),
        _ => None,
    }
}

impl Http {
    fn password(&self, localpart: &str) -> Result<String, String> {
        let out = Command::new("pass-cli")
            .args(["item", "view", "--vault-name", &self.vault, "--item-title", &format!("matrix-{localpart}"), "--output", "json"])
            .stderr(Stdio::null())
            .output()
            .map_err(|e| format!("pass-cli: {e}"))?;
        let item: Value = serde_json::from_slice(&out.stdout).unwrap_or(Value::Null);
        match (out.status.success(), find(&item, "password")) {
            (true, Some(value)) => Ok(value),
            _ => Err(format!("no login for {localpart} in {}", self.vault)),
        }
    }

    fn token(&mut self, localpart: &str) -> Result<String, String> {
        if let Some(t) = self.tokens.get(localpart) {
            return Ok(t.clone());
        }
        let body = json!({
            "type": "m.login.password",
            "identifier": { "type": "m.id.user", "user": localpart },
            "password": self.password(localpart)?,
            "initial_device_display_name": "matrix-rooms",
        });
        let got: Value = ureq::post(&format!("{}/_matrix/client/v3/login", self.base))
            .send_json(body)
            .map_err(|e| failure(&format!("signing in as {localpart}"), e))?
            .into_json()
            .map_err(|e| e.to_string())?;
        let token = got["access_token"].as_str().ok_or("the homeserver gave no access token")?.to_owned();
        self.tokens.insert(localpart.to_owned(), token.clone());
        Ok(token)
    }

    fn call(&mut self, by: &str, method: &str, path: &str, body: Option<Value>) -> Result<Value, ureq::Error> {
        let token = self.token(by).map_err(|e| ureq::Error::from(std::io::Error::other(e)))?;
        let request = ureq::request(method, &format!("{}/_matrix/client/v3{path}", self.base)).set("Authorization", &format!("Bearer {token}"));
        let response = match body {
            Some(b) => request.send_json(b)?,
            None => request.call()?,
        };
        Ok(response.into_json().unwrap_or(Value::Null))
    }

    fn sign_out(&mut self) {
        for token in std::mem::take(&mut self.tokens).into_values() {
            let _ = ureq::post(&format!("{}/_matrix/client/v3/logout", self.base)).set("Authorization", &format!("Bearer {token}")).call();
        }
    }
}

impl Server for Http {
    fn resolve(&mut self, by: &str, alias: &str) -> Result<Option<String>, String> {
        match self.call(by, "GET", &format!("/directory/room/{}", seg(alias)), None) {
            Ok(v) => Ok(v["room_id"].as_str().map(str::to_owned)),
            Err(ureq::Error::Status(404, _)) => Ok(None),
            Err(e) => Err(failure(&format!("looking up {alias}"), e)),
        }
    }
    fn create(&mut self, by: &str, room: &Room, invite: &[String]) -> Result<String, String> {
        let body = json!({
            "preset": "private_chat",
            "visibility": "private",
            "room_alias_name": room.alias,
            "name": room.team,
            "topic": room.topic,
            "invite": invite,
        });
        let got = self.call(by, "POST", "/createRoom", Some(body)).map_err(|e| failure(&format!("creating #{}:{}", room.alias, self.server), e))?;
        got["room_id"].as_str().map(str::to_owned).ok_or_else(|| "the homeserver gave no room id".into())
    }
    fn joined(&mut self, by: &str, room_id: &str) -> Result<BTreeSet<String>, String> {
        let got = self.call(by, "GET", &format!("/rooms/{}/joined_members", seg(room_id)), None).map_err(|e| failure("reading the members", e))?;
        Ok(got["joined"].as_object().map(|o| o.keys().cloned().collect()).unwrap_or_default())
    }
    fn invite(&mut self, by: &str, room_id: &str, user: &str) -> Result<(), String> {
        self.call(by, "POST", &format!("/rooms/{}/invite", seg(room_id)), Some(json!({ "user_id": user }))).map(drop).map_err(|e| failure(&format!("inviting {user}"), e))
    }
    fn join(&mut self, by: &str, room_id: &str) -> Result<(), String> {
        self.call(by, "POST", &format!("/join/{}", seg(room_id)), Some(json!({}))).map(drop).map_err(|e| failure(&format!("joining as {by}"), e))
    }
    fn topic(&mut self, by: &str, room_id: &str) -> Result<Option<String>, String> {
        match self.call(by, "GET", &format!("/rooms/{}/state/m.room.topic", seg(room_id)), None) {
            Ok(v) => Ok(v["topic"].as_str().map(str::to_owned)),
            Err(ureq::Error::Status(404, _)) => Ok(None),
            Err(e) => Err(failure("reading the topic", e)),
        }
    }
    fn set_topic(&mut self, by: &str, room_id: &str, topic: &str) -> Result<(), String> {
        self.call(by, "PUT", &format!("/rooms/{}/state/m.room.topic", seg(room_id)), Some(json!({ "topic": topic }))).map(drop).map_err(|e| failure("setting the topic", e))
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (look, base, vault) = match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["look", base, vault] => (true, *base, *vault),
        ["apply", base, vault] => (false, *base, *vault),
        _ => {
            eprintln!("usage: matrix-rooms look|apply BASE_URL VAULT");
            return ExitCode::from(2);
        }
    };
    let declared: Declared = match serde_json::from_str(include_str!(env!("MATRIX_ROOMS"))) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("matrix-rooms: the declared rooms do not read: {e}");
            return ExitCode::FAILURE;
        }
    };
    let mut http = Http { base: base.trim_end_matches('/').to_owned(), server: declared.server.clone(), vault: vault.to_owned(), tokens: BTreeMap::new() };
    let result = reconcile(&declared, &mut http, look);
    http.sign_out();
    match result {
        Ok(steps) => {
            for step in &steps {
                println!("matrix-rooms: {}{step}", if look && !step.is_finding() { "would: " } else { "" });
            }
            println!("matrix-rooms: {} rooms declared, {} step(s){}", declared.rooms.len(), steps.len(), if look { " to take" } else { "" });
            if steps.iter().any(|s| s.is_finding()) {
                return ExitCode::FAILURE;
            }
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("matrix-rooms: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_password_is_found_wherever_the_item_keeps_it() {
        let item = json!({ "item": { "title": "matrix-x", "content": { "content": { "Login": { "username": "x", "password": "p" } } } } });
        assert_eq!(find(&item, "password").as_deref(), Some("p"));
        assert_eq!(find(&json!({ "password": "" }), "password"), None);
        assert_eq!(find(&json!([1, "password"]), "password"), None);
    }

    #[test]
    fn an_alias_is_one_path_segment() {
        assert_eq!(seg("#design:jingzo.org"), "%23design%3Ajingzo.org");
        assert_eq!(seg("!a/b:c"), "%21a%2Fb%3Ac");
    }
}
