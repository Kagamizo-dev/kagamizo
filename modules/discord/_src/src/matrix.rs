//! The Matrix side: a password login as the agents' user, sending into the
//! one room, and a long-poll sync of what that user says there. The access
//! token stays in this struct; nothing here prints it.

use serde_json::{json, Value};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub struct Matrix {
    base: String,
    room: String,
    token: String,
    pub user_id: String,
    txn: AtomicU64,
}

/// A message the agents' user posted in the room.
pub struct Reply {
    pub event_id: String,
    pub body: String,
}

fn auth(req: ureq::Request, token: &str) -> ureq::Request {
    req.set("Authorization", &format!("Bearer {token}"))
}

fn describe(e: ureq::Error) -> String {
    match e {
        ureq::Error::Status(code, _) => format!("HTTP {code}"),
        ureq::Error::Transport(t) => format!("transport: {}", t.kind()),
    }
}

impl Matrix {
    pub fn login(base: &str, user: &str, password: &str, room: &str, invite: Option<&str>) -> Result<Matrix, String> {
        let base = base.trim_end_matches('/').to_owned();
        let body = json!({
            "type": "m.login.password",
            "identifier": { "type": "m.id.user", "user": user },
            "password": password,
            "initial_device_display_name": "discord-relay",
        });
        let v: Value = ureq::post(&format!("{base}/_matrix/client/v3/login"))
            .send_json(body)
            .map_err(|e| format!("matrix login: {}", describe(e)))?
            .into_json()
            .map_err(|e| format!("matrix login: {e}"))?;
        let token = v["access_token"].as_str().ok_or("matrix login: no access_token")?.to_owned();
        let user_id = v["user_id"].as_str().ok_or("matrix login: no user_id")?.to_owned();
        let txn = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0);
        let mut mx = Matrix { base, room: String::new(), token, user_id, txn: AtomicU64::new(txn) };
        mx.room = mx.resolve(room, invite)?;
        Ok(mx)
    }

    /// A room id as given, or an alias resolved, made if it is missing
    /// (private, the owner invited) so the shares always have a room.
    fn resolve(&self, room: &str, invite: Option<&str>) -> Result<String, String> {
        if !room.starts_with('#') {
            return Ok(room.to_owned());
        }
        let encoded = room.replace('#', "%23");
        match auth(ureq::get(&format!("{}/_matrix/client/v3/directory/room/{encoded}", self.base)), &self.token).call() {
            Ok(r) => {
                let v: Value = r.into_json().map_err(|e| format!("matrix alias: {e}"))?;
                return v["room_id"].as_str().map(str::to_owned).ok_or_else(|| "matrix alias: no room_id".to_owned());
            }
            Err(ureq::Error::Status(404, _)) => {}
            Err(e) => return Err(format!("matrix alias: {}", describe(e))),
        }
        let local = room[1..].split(':').next().unwrap_or("");
        let invite: Vec<&str> = invite.into_iter().collect();
        let v: Value = auth(ureq::post(&format!("{}/_matrix/client/v3/createRoom", self.base)), &self.token)
            .send_json(json!({
                "preset": "private_chat",
                "name": "Shares",
                "topic": "What the owner shares from the phone (discord-relay)",
                "room_alias_name": local,
                "invite": invite,
            }))
            .map_err(|e| format!("matrix createRoom: {}", describe(e)))?
            .into_json()
            .map_err(|e| format!("matrix createRoom: {e}"))?;
        eprintln!("discord-relay: made the room {room}");
        v["room_id"].as_str().map(str::to_owned).ok_or_else(|| "matrix createRoom: no room_id".to_owned())
    }

    /// Posts a text message; returns its event id.
    pub fn send(&self, body: &str) -> Result<String, String> {
        let txn = self.txn.fetch_add(1, Ordering::SeqCst);
        let url = format!("{}/_matrix/client/v3/rooms/{}/send/m.room.message/relay{txn}", self.base, self.room);
        let v: Value = auth(ureq::put(&url), &self.token)
            .send_json(json!({ "msgtype": "m.text", "body": body }))
            .map_err(|e| format!("matrix send: {}", describe(e)))?
            .into_json()
            .map_err(|e| format!("matrix send: {e}"))?;
        v["event_id"].as_str().map(str::to_owned).ok_or_else(|| "matrix send: no event_id".to_owned())
    }

    /// One sync step: the room's new messages from the agents' user since
    /// `since` (None skips the backlog), and the next token.
    pub fn sync(&self, since: Option<&str>) -> Result<(Vec<Reply>, String), String> {
        let filter = json!({ "room": { "rooms": [self.room], "timeline": { "limit": if since.is_some() { 50 } else { 1 } } } });
        let mut req = auth(ureq::get(&format!("{}/_matrix/client/v3/sync", self.base)), &self.token)
            .query("filter", &filter.to_string())
            .query("timeout", if since.is_some() { "30000" } else { "0" })
            .timeout(Duration::from_secs(60));
        if let Some(s) = since {
            req = req.query("since", s);
        }
        let v: Value = req
            .call()
            .map_err(|e| format!("matrix sync: {}", describe(e)))?
            .into_json()
            .map_err(|e| format!("matrix sync: {e}"))?;
        let next = v["next_batch"].as_str().ok_or("matrix sync: no next_batch")?.to_owned();
        let mut out = Vec::new();
        if since.is_some() {
            let events = v["rooms"]["join"][&self.room]["timeline"]["events"].as_array();
            for e in events.into_iter().flatten() {
                if e["type"] == "m.room.message" && e["sender"] == self.user_id.as_str() {
                    if let (Some(id), Some(body)) = (e["event_id"].as_str(), e["content"]["body"].as_str()) {
                        out.push(Reply { event_id: id.to_owned(), body: body.to_owned() });
                    }
                }
            }
        }
        Ok((out, next))
    }
}
