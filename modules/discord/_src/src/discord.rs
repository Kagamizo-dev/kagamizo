//! The Discord side: the gateway (one websocket, identified with the
//! GUILD_MESSAGES and MESSAGE_CONTENT intents, heartbeat kept from the one
//! thread) and the REST call that posts into the channel. The bot token
//! lives only in the headers it signs; nothing here prints it.

use crate::relay::Message;
use serde_json::{json, Value};
use std::io::ErrorKind;
use std::net::TcpStream;
use std::time::{Duration, Instant};
use tungstenite::stream::MaybeTlsStream;
use tungstenite::{Message as Ws, WebSocket};

const GATEWAY: &str = "wss://gateway.discord.gg/?v=10&encoding=json";
const API: &str = "https://discord.com/api/v10";
const GUILD_MESSAGES: u64 = 1 << 9;
const MESSAGE_CONTENT: u64 = 1 << 15;

pub fn post(token: &str, channel: &str, content: &str) -> Result<(), String> {
    ureq::post(&format!("{API}/channels/{channel}/messages"))
        .set("Authorization", &format!("Bot {token}"))
        .send_json(json!({ "content": content, "allowed_mentions": { "parse": [] } }))
        .map(|_| ())
        .map_err(|e| match e {
            ureq::Error::Status(code, _) => format!("discord post: HTTP {code}"),
            ureq::Error::Transport(t) => format!("discord post: transport: {}", t.kind()),
        })
}

fn read_timeout(ws: &mut WebSocket<MaybeTlsStream<TcpStream>>, d: Duration) {
    let tcp = match ws.get_ref() {
        MaybeTlsStream::Plain(s) => Some(s),
        MaybeTlsStream::Rustls(t) => Some(t.get_ref()),
        _ => None,
    };
    if let Some(tcp) = tcp {
        let _ = tcp.set_read_timeout(Some(d));
    }
}

/// One gateway session, until Discord closes it or asks for a new one:
/// every MESSAGE_CREATE goes to `on_message`. Returns why it ended.
pub fn session(token: &str, on_message: &mut dyn FnMut(Message)) -> String {
    let (mut ws, _) = match tungstenite::connect(GATEWAY) {
        Ok(c) => c,
        Err(e) => return format!("connect: {e}"),
    };
    read_timeout(&mut ws, Duration::from_secs(1));
    let mut interval: Option<Duration> = None;
    let mut last_beat = Instant::now();
    let mut seq: Option<u64> = None;
    let send = |ws: &mut WebSocket<MaybeTlsStream<TcpStream>>, v: Value| -> Result<(), String> {
        ws.send(Ws::Text(v.to_string().into())).map_err(|e| format!("send: {e}"))
    };
    loop {
        if let Some(i) = interval {
            if last_beat.elapsed() >= i {
                if let Err(e) = send(&mut ws, json!({ "op": 1, "d": seq })) {
                    return e;
                }
                last_beat = Instant::now();
            }
        }
        let text = match ws.read() {
            Ok(Ws::Text(t)) => t.to_string(),
            Ok(Ws::Close(f)) => return format!("closed by Discord: {}", f.map(|f| f.code.to_string()).unwrap_or_default()),
            Ok(Ws::Ping(p)) => {
                if let Err(e) = ws.send(Ws::Pong(p)) {
                    return format!("pong: {e}");
                }
                continue;
            }
            Ok(_) => continue,
            Err(tungstenite::Error::Io(e)) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => continue,
            Err(e) => return format!("read: {e}"),
        };
        let v: Value = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if let Some(s) = v["s"].as_u64() {
            seq = Some(s);
        }
        match v["op"].as_u64() {
            // Hello: heartbeat at the given interval, then identify.
            Some(10) => {
                let ms = v["d"]["heartbeat_interval"].as_u64().unwrap_or(41250);
                interval = Some(Duration::from_millis(ms));
                last_beat = Instant::now();
                let identify = json!({ "op": 2, "d": {
                    "token": token,
                    "intents": GUILD_MESSAGES | MESSAGE_CONTENT,
                    "properties": { "os": "linux", "browser": "discord-relay", "device": "discord-relay" },
                }});
                if let Err(e) = send(&mut ws, identify) {
                    return e;
                }
            }
            // A heartbeat asked for now.
            Some(1) => {
                if let Err(e) = send(&mut ws, json!({ "op": 1, "d": seq })) {
                    return e;
                }
                last_beat = Instant::now();
            }
            Some(7) => return "reconnect requested".into(),
            Some(9) => return "session invalidated".into(),
            Some(0) => match v["t"].as_str() {
                Some("READY") => eprintln!("discord-relay: gateway ready"),
                Some("MESSAGE_CREATE") => {
                    if let Ok(m) = serde_json::from_value::<Message>(v["d"].clone()) {
                        on_message(m);
                    }
                }
                _ => {}
            },
            _ => {}
        }
    }
}
