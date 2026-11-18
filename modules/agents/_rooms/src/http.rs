//! The homeserver over HTTP, as its one application service.
//!
//! There is no password and no session: every call carries the application
//! service's token and names the account it is made as (`user_id`), which
//! the homeserver allows because that account is in the service's
//! namespace (`registration`). An account is registered the first time it
//! is used.
use crate::{Declared, Message, Room, Server, Talk};
use serde_json::{json, Value};
use std::collections::BTreeSet;

pub struct Http {
    base: String,
    server: String,
    token: String,
    known: BTreeSet<String>,
    sent: u64,
}

/// A path segment or query value, percent-encoded.
pub fn seg(s: &str) -> String {
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

/// A literal, as a regular expression.
fn literal(s: &str) -> String {
    s.chars().flat_map(|c| if c.is_ascii_alphanumeric() || c == '-' { vec![c] } else { vec!['\\', c] }).collect()
}

/// The application service's registration, in the form homeservers read:
/// its namespace is exactly the declared accounts and the declared aliases,
/// and it is pushed nothing (no url).
pub fn registration(d: &Declared, as_token: &str, hs_token: &str) -> String {
    let mut users: BTreeSet<&str> = d.rooms.iter().flat_map(|r| r.members.iter().map(String::as_str)).collect();
    users.insert(&d.owner);
    let any = |names: Vec<&str>| names.iter().map(|n| literal(n)).collect::<Vec<_>>().join("|");
    let server = literal(&d.server);
    let registration = json!({
        "id": "kagamizo",
        "url": null,
        "as_token": as_token,
        "hs_token": hs_token,
        "sender_localpart": "kagamizo-service",
        "rate_limited": false,
        "namespaces": {
            "users": [{ "exclusive": true, "regex": format!("^@({}):{server}$", any(users.into_iter().collect())) }],
            "aliases": [{ "exclusive": true, "regex": format!("^#({}):{server}$", any(d.rooms.iter().map(|r| r.alias.as_str()).collect())) }],
            "rooms": [],
        },
    });
    // JSON is YAML: no second writer to keep in step.
    registration.to_string()
}

impl Http {
    pub fn new(base: &str, server: &str, token: &str) -> Self {
        Http { base: base.trim_end_matches('/').to_owned(), server: server.to_owned(), token: token.trim().to_owned(), known: BTreeSet::new(), sent: 0 }
    }

    /// The account exists: registered now, or already there.
    fn ensure(&mut self, localpart: &str) -> Result<(), String> {
        if self.known.contains(localpart) {
            return Ok(());
        }
        let body = json!({ "type": "m.login.application_service", "username": localpart, "inhibit_login": true });
        let sent = ureq::post(&format!("{}/_matrix/client/v3/register", self.base)).set("Authorization", &format!("Bearer {}", self.token)).send_json(body);
        match sent {
            Ok(_) => {}
            Err(ureq::Error::Status(400, r)) => {
                let body: Value = r.into_json().unwrap_or(Value::Null);
                if body["errcode"] != "M_USER_IN_USE" {
                    return Err(format!("registering {localpart}: 400 {}", body["errcode"].as_str().unwrap_or("")));
                }
            }
            Err(e) => return Err(failure(&format!("registering {localpart}"), e)),
        }
        self.known.insert(localpart.to_owned());
        Ok(())
    }

    fn call(&mut self, by: &str, method: &str, path: &str, body: Option<Value>) -> Result<Value, ureq::Error> {
        self.ensure(by).map_err(|e| ureq::Error::from(std::io::Error::other(e)))?;
        let user = format!("@{by}:{}", self.server);
        let join = if path.contains('?') { '&' } else { '?' };
        let request = ureq::request(method, &format!("{}/_matrix/client/v3{path}{join}user_id={}", self.base, seg(&user))).set("Authorization", &format!("Bearer {}", self.token));
        let response = match body {
            Some(b) => request.send_json(b)?,
            None => request.call()?,
        };
        Ok(response.into_json().unwrap_or(Value::Null))
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

impl Talk for Http {
    fn messages(&mut self, by: &str, room_id: &str, limit: usize) -> Result<Vec<Message>, String> {
        let got = self.call(by, "GET", &format!("/rooms/{}/messages?dir=b&limit={limit}", seg(room_id)), None).map_err(|e| failure("reading the messages", e))?;
        let mut found: Vec<Message> = got["chunk"]
            .as_array()
            .map(|events| {
                events
                    .iter()
                    .filter(|e| e["type"] == "m.room.message")
                    .filter_map(|e| {
                        Some(Message {
                            id: e["event_id"].as_str()?.to_owned(),
                            from: e["sender"].as_str()?.to_owned(),
                            body: e["content"]["body"].as_str()?.to_owned(),
                            at: e["origin_server_ts"].as_u64().unwrap_or(0),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        found.reverse();
        Ok(found)
    }
    fn say(&mut self, by: &str, room_id: &str, body: &str) -> Result<(), String> {
        self.sent += 1;
        let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
        let path = format!("/rooms/{}/send/m.room.message/{nanos}-{}", seg(room_id), self.sent);
        self.call(by, "PUT", &path, Some(json!({ "msgtype": "m.text", "body": body }))).map(drop).map_err(|e| failure("sending the message", e))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn declared() -> Declared {
        let room = |t: &str| Room { team: t.into(), alias: t.into(), topic: String::new(), members: vec!["zach".into(), t.into()] };
        Declared { server: "jingzo.org".into(), owner: "zach".into(), rooms: vec![room("design"), room("research-jingzo")] }
    }

    #[test]
    fn an_alias_is_one_path_segment() {
        assert_eq!(seg("#design:jingzo.org"), "%23design%3Ajingzo.org");
        assert_eq!(seg("!a/b:c"), "%21a%2Fb%3Ac");
    }

    #[test]
    fn the_namespace_is_exactly_the_declared_accounts_and_aliases() {
        let r: Value = serde_json::from_str(&registration(&declared(), "a", "h")).unwrap();
        assert_eq!(r["namespaces"]["users"][0]["regex"], r"^@(design|research-jingzo|zach):jingzo\.org$");
        assert_eq!(r["namespaces"]["aliases"][0]["regex"], r"^#(design|research-jingzo):jingzo\.org$");
        assert_eq!(r["namespaces"]["users"][0]["exclusive"], true);
        assert_eq!(r["url"], Value::Null);
        assert_eq!((r["as_token"].as_str(), r["hs_token"].as_str()), (Some("a"), Some("h")));
    }
}
