//! discord-relay: the owner's private Discord channel, relayed into the
//! agents' Matrix room and back.
//!
//! Inbound: every message the declared owner posts in the declared channel
//! (text, links, and each attachment's URL: videos, voice notes) is posted
//! into the Matrix room as the agents' user. Nothing else from Discord is
//! read past the rule (../_lean/Relay.lean), and the bot posts nowhere but
//! that one channel.
//!
//! Outbound: what the agents' user says in the room (by any other session
//! of that account) is posted back into the channel; what this relay posted
//! itself is skipped by its event id.
//!
//! Configuration is the environment, each value checked at start:
//!   DISCORD_BOT_TOKEN, DISCORD_CHANNEL_ID, DISCORD_OWNER_ID,
//!   MATRIX_URL, MATRIX_USER, MATRIX_PASSWORD, MATRIX_ROOM (an id or an
//!   alias; an alias the relay makes if missing), MATRIX_INVITE (optional:
//!   a user invited into a room the relay makes)
//! No token or password is ever printed.

mod discord;
mod matrix;
mod relay;

use matrix::Matrix;
use relay::Id;
use std::collections::HashSet;
use std::process::exit;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

struct Config {
    bot_token: String,
    channel: Id,
    owner: Id,
    matrix_url: String,
    matrix_user: String,
    matrix_password: String,
    matrix_room: String,
    matrix_invite: Option<String>,
}

fn var(name: &str) -> Result<String, String> {
    match std::env::var(name) {
        Ok(v) if !v.trim().is_empty() => Ok(v.trim().to_owned()),
        _ => Err(format!("{name} is not set")),
    }
}

impl Config {
    fn from_env() -> Result<Config, String> {
        let room = var("MATRIX_ROOM")?;
        if !(room.starts_with('!') || room.starts_with('#')) || !room.contains(':') {
            return Err("MATRIX_ROOM: a room id (!...:server) or alias (#...:server)".into());
        }
        Ok(Config {
            bot_token: var("DISCORD_BOT_TOKEN")?,
            channel: Id::parse("DISCORD_CHANNEL_ID", &var("DISCORD_CHANNEL_ID")?)?,
            owner: Id::parse("DISCORD_OWNER_ID", &var("DISCORD_OWNER_ID")?)?,
            matrix_url: var("MATRIX_URL")?,
            matrix_user: var("MATRIX_USER")?,
            matrix_password: var("MATRIX_PASSWORD")?,
            matrix_room: room,
            matrix_invite: std::env::var("MATRIX_INVITE").ok().filter(|s| s.starts_with('@')),
        })
    }
}

fn main() {
    let cfg = match Config::from_env() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("discord-relay: {e}");
            exit(2);
        }
    };
    let mx = loop {
        match Matrix::login(
            &cfg.matrix_url,
            &cfg.matrix_user,
            &cfg.matrix_password,
            &cfg.matrix_room,
            cfg.matrix_invite.as_deref(),
        ) {
            Ok(m) => break Arc::new(m),
            Err(e) => {
                eprintln!("discord-relay: {e}; retrying in 10s");
                thread::sleep(Duration::from_secs(10));
            }
        }
    };
    eprintln!("discord-relay: signed in to Matrix as {}", mx.user_id);
    // Event ids this relay posted: never echoed back to Discord.
    let own: Arc<Mutex<HashSet<String>>> = Arc::new(Mutex::new(HashSet::new()));

    // Matrix to Discord.
    {
        let mx = Arc::clone(&mx);
        let own = Arc::clone(&own);
        let token = cfg.bot_token.clone();
        let channel = cfg.channel.clone();
        thread::spawn(move || {
            let mut since: Option<String> = None;
            loop {
                match mx.sync(since.as_deref()) {
                    Ok((replies, next)) => {
                        since = Some(next);
                        for r in replies {
                            if own.lock().map(|s| s.contains(&r.event_id)).unwrap_or(false) {
                                continue;
                            }
                            for chunk in relay::discord_chunks(&r.body) {
                                if let Err(e) = discord::post(&token, channel.as_str(), &chunk) {
                                    eprintln!("discord-relay: {e}");
                                    thread::sleep(Duration::from_secs(2));
                                }
                            }
                        }
                    }
                    Err(e) => {
                        eprintln!("discord-relay: {e}; retrying in 10s");
                        thread::sleep(Duration::from_secs(10));
                    }
                }
            }
        });
    }

    // Discord to Matrix: one gateway session after another.
    let mut on_message = |m: relay::Message| {
        if !relay::relayed(&m, &cfg.owner, &cfg.channel) {
            return;
        }
        let Some(body) = relay::matrix_body(&m) else { return };
        match mx.send(&body) {
            Ok(id) => {
                if let Ok(mut s) = own.lock() {
                    s.insert(id);
                }
                eprintln!("discord-relay: relayed a message ({} attachments)", m.attachments.len());
            }
            Err(e) => eprintln!("discord-relay: {e}"),
        }
    };
    loop {
        let why = discord::session(&cfg.bot_token, &mut on_message);
        eprintln!("discord-relay: gateway session ended ({why}); reconnecting in 5s");
        thread::sleep(Duration::from_secs(5));
    }
}
