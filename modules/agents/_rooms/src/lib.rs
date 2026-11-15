//! The declared rooms (../rooms.nix), made true on the homeserver.
//!
//! What a room should be is declared: its alias, its topic and its members
//! (the owner and one team). `reconcile` reads what the homeserver has and
//! does only what is missing, so running it twice changes nothing the
//! second time. It never removes a member, a room or a message: a room
//! that holds someone undeclared is reported, not changed.
//!
//! The homeserver is behind `Server`, so the whole of `reconcile` is tested
//! against one kept in memory (the tests below); ./http.rs is the one that
//! speaks HTTP, as the homeserver's application service.
pub mod http;

use serde::Deserialize;
use std::collections::BTreeSet;

#[derive(Deserialize, Clone, Debug)]
pub struct Room {
    pub team: String,
    pub alias: String,
    pub topic: String,
    pub members: Vec<String>,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Declared {
    /// The homeserver's name, the part after the colon.
    pub server: String,
    /// The owner's localpart: the one who creates every room.
    pub owner: String,
    pub rooms: Vec<Room>,
}

impl Declared {
    /// The rooms this build was given (MATRIX_ROOMS, from Nix).
    pub fn compiled() -> Result<Declared, String> {
        serde_json::from_str(include_str!(env!("MATRIX_ROOMS"))).map_err(|e| format!("the declared rooms do not read: {e}"))
    }

    pub fn user(&self, localpart: &str) -> String {
        format!("@{localpart}:{}", self.server)
    }
    pub fn alias(&self, room: &Room) -> String {
        format!("#{}:{}", room.alias, self.server)
    }
}

/// What the tool needs of a homeserver. `by` is always a localpart: the
/// account the call is made as.
pub trait Server {
    fn resolve(&mut self, by: &str, alias: &str) -> Result<Option<String>, String>;
    fn create(&mut self, by: &str, room: &Room, invite: &[String]) -> Result<String, String>;
    fn joined(&mut self, by: &str, room_id: &str) -> Result<BTreeSet<String>, String>;
    fn invite(&mut self, by: &str, room_id: &str, user: &str) -> Result<(), String>;
    fn join(&mut self, by: &str, room_id: &str) -> Result<(), String>;
    fn topic(&mut self, by: &str, room_id: &str) -> Result<Option<String>, String>;
    fn set_topic(&mut self, by: &str, room_id: &str, topic: &str) -> Result<(), String>;
}

/// One thing done, or (when only looking) one thing that would be.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    Created { alias: String },
    Invited { alias: String, user: String },
    Joined { alias: String, user: String },
    Topic { alias: String },
    /// Someone is in the room who is not declared. Nothing is done about it.
    Undeclared { alias: String, user: String },
}

impl Step {
    pub fn is_finding(&self) -> bool {
        matches!(self, Step::Undeclared { .. })
    }
}

impl std::fmt::Display for Step {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Step::Created { alias } => write!(f, "{alias}: created"),
            Step::Invited { alias, user } => write!(f, "{alias}: {user} invited"),
            Step::Joined { alias, user } => write!(f, "{alias}: {user} joined"),
            Step::Topic { alias } => write!(f, "{alias}: topic set"),
            Step::Undeclared { alias, user } => write!(f, "{alias}: {user} is in the room and not declared"),
        }
    }
}

/// Make every declared room true. With `look` set, only reads are made and
/// the steps are the ones a run would take.
pub fn reconcile(d: &Declared, s: &mut impl Server, look: bool) -> Result<Vec<Step>, String> {
    let mut steps = Vec::new();
    for room in &d.rooms {
        let alias = d.alias(room);
        let others: Vec<&String> = room.members.iter().filter(|m| **m != d.owner).collect();
        let room_id = match s.resolve(&d.owner, &alias)? {
            Some(id) => id,
            None => {
                steps.push(Step::Created { alias: alias.clone() });
                for m in &others {
                    steps.push(Step::Invited { alias: alias.clone(), user: d.user(m) });
                    steps.push(Step::Joined { alias: alias.clone(), user: d.user(m) });
                }
                if !look {
                    let invite: Vec<String> = others.iter().map(|m| d.user(m)).collect();
                    let id = s.create(&d.owner, room, &invite)?;
                    for m in &others {
                        s.join(m, &id)?;
                    }
                }
                continue;
            }
        };
        let joined = s.joined(&d.owner, &room_id)?;
        for m in &others {
            let user = d.user(m);
            if joined.contains(&user) {
                continue;
            }
            // An invitation already sent is refused by the homeserver as a
            // repeat; joining is what counts, so the refusal is let pass.
            steps.push(Step::Invited { alias: alias.clone(), user: user.clone() });
            steps.push(Step::Joined { alias: alias.clone(), user: user.clone() });
            if !look {
                let _ = s.invite(&d.owner, &room_id, &user);
                s.join(m, &room_id)?;
            }
        }
        let declared: BTreeSet<String> = room.members.iter().map(|m| d.user(m)).collect();
        for user in joined.difference(&declared) {
            steps.push(Step::Undeclared { alias: alias.clone(), user: user.clone() });
        }
        if s.topic(&d.owner, &room_id)?.as_deref() != Some(room.topic.as_str()) {
            steps.push(Step::Topic { alias: alias.clone() });
            if !look {
                s.set_topic(&d.owner, &room_id, &room.topic)?;
            }
        }
    }
    Ok(steps)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    #[derive(Default)]
    struct Kept {
        topic: Option<String>,
        joined: BTreeSet<String>,
        invited: BTreeSet<String>,
    }

    /// A homeserver kept in memory, with the rules that matter here: only a
    /// member reads or invites, and only an invited account joins.
    #[derive(Default)]
    struct Fake {
        rooms: BTreeMap<String, Kept>,
        aliases: BTreeMap<String, String>,
        writes: usize,
    }

    impl Fake {
        fn member(&self, by: &str, id: &str) -> Result<&Kept, String> {
            let room = self.rooms.get(id).ok_or("no such room")?;
            if room.joined.contains(&format!("@{by}:example.org")) {
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
            let id = format!("!{}:example.org", room.alias);
            let kept = Kept {
                topic: Some(room.topic.clone()),
                joined: BTreeSet::from([format!("@{by}:example.org")]),
                invited: invite.iter().cloned().collect(),
            };
            self.rooms.insert(id.clone(), kept);
            self.aliases.insert(format!("#{}:example.org", room.alias), id.clone());
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
            let user = format!("@{by}:example.org");
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

    fn declared() -> Declared {
        let room = |team: &str| Room {
            team: team.into(),
            alias: team.into(),
            topic: format!("the {team} team"),
            members: vec!["owner".into(), team.into()],
        };
        Declared { server: "example.org".into(), owner: "owner".into(), rooms: vec![room("design"), room("review")] }
    }

    #[test]
    fn an_empty_server_gets_every_room_with_its_two_members() {
        let (d, mut s) = (declared(), Fake::default());
        let steps = reconcile(&d, &mut s, false).unwrap();
        assert_eq!(steps.iter().filter(|s| matches!(s, Step::Created { .. })).count(), 2);
        for room in &d.rooms {
            let kept = &s.rooms[&s.aliases[&d.alias(room)]];
            assert_eq!(kept.joined, BTreeSet::from([d.user("owner"), d.user(&room.team)]));
            assert_eq!(kept.topic.as_deref(), Some(room.topic.as_str()));
        }
    }

    #[test]
    fn a_second_run_does_nothing() {
        let (d, mut s) = (declared(), Fake::default());
        reconcile(&d, &mut s, false).unwrap();
        let writes = s.writes;
        assert_eq!(reconcile(&d, &mut s, false).unwrap(), vec![]);
        assert_eq!(s.writes, writes);
    }

    #[test]
    fn looking_writes_nothing_and_says_what_a_run_would_do() {
        let (d, mut s) = (declared(), Fake::default());
        let looked = reconcile(&d, &mut s, true).unwrap();
        assert_eq!(s.writes, 0);
        assert_eq!(looked, reconcile(&d, &mut s, false).unwrap());
    }

    #[test]
    fn a_team_missing_from_its_room_is_brought_in_even_when_already_invited() {
        let (d, mut s) = (declared(), Fake::default());
        reconcile(&d, &mut s, false).unwrap();
        let id = s.aliases["#design:example.org"].clone();
        s.rooms.get_mut(&id).unwrap().joined.remove("@design:example.org");
        let steps = reconcile(&d, &mut s, false).unwrap();
        assert_eq!(
            steps,
            vec![
                Step::Invited { alias: "#design:example.org".into(), user: "@design:example.org".into() },
                Step::Joined { alias: "#design:example.org".into(), user: "@design:example.org".into() },
            ]
        );
        assert!(s.rooms[&id].joined.contains("@design:example.org"));
    }

    #[test]
    fn a_changed_topic_is_set_back() {
        let (d, mut s) = (declared(), Fake::default());
        reconcile(&d, &mut s, false).unwrap();
        let id = s.aliases["#review:example.org"].clone();
        s.rooms.get_mut(&id).unwrap().topic = Some("something else".into());
        assert_eq!(reconcile(&d, &mut s, false).unwrap(), vec![Step::Topic { alias: "#review:example.org".into() }]);
        assert_eq!(s.rooms[&id].topic.as_deref(), Some("the review team"));
    }

    #[test]
    fn someone_undeclared_is_reported_and_left() {
        let (d, mut s) = (declared(), Fake::default());
        reconcile(&d, &mut s, false).unwrap();
        let id = s.aliases["#design:example.org"].clone();
        s.rooms.get_mut(&id).unwrap().joined.insert("@review:example.org".into());
        let steps = reconcile(&d, &mut s, false).unwrap();
        assert_eq!(steps, vec![Step::Undeclared { alias: "#design:example.org".into(), user: "@review:example.org".into() }]);
        assert!(steps[0].is_finding());
        assert!(s.rooms[&id].joined.contains("@review:example.org"));
    }

    #[test]
    fn no_team_is_ever_put_in_another_teams_room() {
        let (d, mut s) = (declared(), Fake::default());
        reconcile(&d, &mut s, false).unwrap();
        for room in &d.rooms {
            let kept = &s.rooms[&s.aliases[&d.alias(room)]];
            for other in d.rooms.iter().filter(|o| o.team != room.team) {
                assert!(!kept.joined.contains(&d.user(&other.team)));
                assert!(!kept.invited.contains(&d.user(&other.team)));
            }
        }
    }
}
