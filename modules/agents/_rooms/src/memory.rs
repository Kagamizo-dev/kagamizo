//! A homeserver kept in memory, with the rules that matter here: only a
//! member reads, invites or speaks, and only an invited account joins. The
//! tests of this crate and of the chat gateway run against it, and so does
//! the browser check of the chat pages.
use crate::{Message, Room, Server, Talk};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Default)]
pub struct Kept {
    pub topic: Option<String>,
    pub joined: BTreeSet<String>,
    pub invited: BTreeSet<String>,
    pub messages: Vec<Message>,
}

#[derive(Default)]
pub struct Fake {
    pub rooms: BTreeMap<String, Kept>,
    pub aliases: BTreeMap<String, String>,
    pub writes: usize,
    /// The homeserver's name, as accounts carry it.
    pub server: String,
}

impl Fake {
    fn member(&self, by: &str, id: &str) -> Result<&Kept, String> {
        let room = self.rooms.get(id).ok_or("no such room")?;
        if room.joined.contains(&format!("@{by}:{}", self.server)) {
            Ok(room)
        } else {
            Err(format!("{by} is not in {id}"))
        }
    }
}

impl Server for Fake {
    fn resolve(&mut self, _by: &str, alias: &str) -> Result<Option<String>, String> {
        Ok(self.aliases.get(alias).cloned())
    }
    fn create(&mut self, by: &str, room: &Room, invite: &[String]) -> Result<String, String> {
        self.writes += 1;
        let id = format!("!{}:{}", room.alias, self.server);
        let kept = Kept {
            topic: Some(room.topic.clone()),
            joined: BTreeSet::from([format!("@{by}:{}", self.server)]),
            invited: invite.iter().cloned().collect(),
            messages: Vec::new(),
        };
        self.rooms.insert(id.clone(), kept);
        self.aliases.insert(format!("#{}:{}", room.alias, self.server), id.clone());
        Ok(id)
    }
    fn joined(&mut self, by: &str, id: &str) -> Result<BTreeSet<String>, String> {
        Ok(self.member(by, id)?.joined.clone())
    }
    fn invite(&mut self, by: &str, id: &str, user: &str) -> Result<(), String> {
        self.member(by, id)?;
        self.writes += 1;
        let room = self.rooms.get_mut(id).unwrap();
        if !room.invited.insert(user.to_owned()) {
            return Err("already invited".into());
        }
        Ok(())
    }
    fn join(&mut self, by: &str, id: &str) -> Result<(), String> {
        self.writes += 1;
        let user = format!("@{by}:{}", self.server);
        let room = self.rooms.get_mut(id).ok_or("no such room")?;
        if !room.invited.contains(&user) {
            return Err(format!("{by} was not invited"));
        }
        room.joined.insert(user);
        Ok(())
    }
    fn topic(&mut self, by: &str, id: &str) -> Result<Option<String>, String> {
        Ok(self.member(by, id)?.topic.clone())
    }
    fn set_topic(&mut self, by: &str, id: &str, topic: &str) -> Result<(), String> {
        self.member(by, id)?;
        self.writes += 1;
        self.rooms.get_mut(id).unwrap().topic = Some(topic.to_owned());
        Ok(())
    }
}


impl Fake {
    pub fn named(server: &str) -> Self {
        Fake { server: server.to_owned(), ..Fake::default() }
    }
}

impl Talk for Fake {
    fn messages(&mut self, by: &str, id: &str, limit: usize) -> Result<Vec<Message>, String> {
        let all = &self.member(by, id)?.messages;
        Ok(all[all.len().saturating_sub(limit)..].to_vec())
    }
    fn say(&mut self, by: &str, id: &str, body: &str) -> Result<(), String> {
        self.member(by, id)?;
        self.writes += 1;
        let from = format!("@{by}:{}", self.server);
        let room = self.rooms.get_mut(id).unwrap();
        let n = room.messages.len() as u64;
        room.messages.push(Message { id: format!("${n}"), from, body: body.to_owned(), at: 1_700_000_000_000 + n * 60_000 });
        Ok(())
    }
}
