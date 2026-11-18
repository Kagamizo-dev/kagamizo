//! The bridge: what the owner says in a room becomes one turn of that
//! room's agent, and what the agent answers is said back in the room.
//!
//! The rooms are the declared ones (../rooms.nix) and the agents that
//! answer are the declared ones whose harness the bridge can drive
//! (BRIDGE_AGENTS, from Nix). It holds to these:
//!
//!   * only the owner starts work: what an agent says, here or in another
//!     room, never starts a turn, so two agents cannot set each other off;
//!   * an answer is said only in the room that was spoken in, and as that
//!     room's own agent;
//!   * an agent's month has a cap in dollars. Every turn is charged at the
//!     dearest pinned price of the agent's model for the tokens the
//!     harness reports, never at the harness's own figure for the cost
//!     (a harness prices by its own table, which is not what the provider
//!     bills; seen 2026-11-17). The charge is added to the month's sum; at
//!     the cap the agent answers nothing more that month and says so, once;
//!   * what was already there when the bridge first sees a room is not
//!     answered, and nothing is answered twice: the last message handled
//!     in each room is kept in the bridge's state;
//!   * nothing the owner says is lost. A pass handles the messages it
//!     read at its start and marks its place at the last of those, never
//!     at whatever the room holds by its end: what the owner says while a
//!     turn runs is new to the next pass (a later reading of the room once
//!     marked such a message as handled, found by the whole-chain check,
//!     2026-11-18);
//!   * a refusal is never silent: if saying that the cap is reached
//!     fails, the message it answers is kept for the next pass.
//!
//! `Bridge::step` is one pass over the rooms, a function of the homeserver,
//! the harness and the state, so it is tested whole against the homeserver
//! kept in memory and a harness that only echoes (the tests below).
//! ./opencode.rs is the harness that speaks to `opencode serve`.
pub mod opencode;

use matrix_rooms::{Declared, Talk};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// How many of a room's latest messages one pass reads.
const WINDOW: usize = 30;
/// The longest single message said in a room, in bytes.
const LONGEST: usize = 8000;

/// An agent that answers in its room.
#[derive(Deserialize, Clone, Debug)]
pub struct Agent {
    /// Its name: its account's localpart and its room's team.
    pub name: String,
    /// The model it runs on, as OpenRouter names it.
    pub model: String,
    /// Where its harness listens, on the loopback.
    pub port: u16,
    /// The most it may spend in a month, in dollars.
    #[serde(rename = "capUsd")]
    pub cap_usd: f64,
    /// The dearest pinned price of its model, dollars per million tokens.
    #[serde(rename = "inputUsdPerMillion")]
    pub input_usd_per_million: f64,
    #[serde(rename = "outputUsdPerMillion")]
    pub output_usd_per_million: f64,
}

impl Agent {
    /// What a turn is charged: its tokens at the dearest pinned price.
    pub fn charge(&self, reply: &Reply) -> f64 {
        (reply.tokens_in as f64 * self.input_usd_per_million + reply.tokens_out as f64 * self.output_usd_per_million) / 1_000_000.0
    }
}

pub struct Reply {
    pub text: String,
    /// The tokens the turn read, cached ones included, as the harness
    /// reports them.
    pub tokens_in: u64,
    /// The tokens it wrote, reasoning included.
    pub tokens_out: u64,
}

/// What the bridge needs of a harness: one turn in a room's own thread.
pub trait Harness {
    /// `session` is the thread to continue, if the room has one; the thread
    /// used is returned, to be kept for the next turn.
    fn turn(&mut self, agent: &Agent, session: Option<&str>, said: &str) -> Result<(String, Reply), String>;
}

/// What the bridge keeps between passes and across restarts.
#[derive(Serialize, Deserialize, Default, Debug, Clone, PartialEq)]
pub struct State {
    /// The last message handled, per room alias.
    pub seen: BTreeMap<String, String>,
    /// The harness's thread, per room alias.
    pub sessions: BTreeMap<String, String>,
    /// Dollars spent, per agent, in `month`.
    pub spent: BTreeMap<String, f64>,
    /// The month `spent` counts, as YYYY-MM.
    pub month: String,
    /// The agents already told this month that their cap is reached.
    pub told: Vec<String>,
}

/// One thing a pass did.
#[derive(Debug, Clone, PartialEq)]
pub enum Did {
    Answered { room: String, cost_usd: f64 },
    Refused { room: String },
    Failed { room: String, why: String },
}

pub struct Bridge<S: Talk, H: Harness> {
    pub declared: Declared,
    pub agents: Vec<Agent>,
    pub server: S,
    pub harness: H,
    pub state: State,
}

/// A long answer in pieces a room takes, cut at line ends where it can be.
pub fn pieces(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = text.trim();
    while rest.len() > LONGEST {
        let mut at = LONGEST;
        while !rest.is_char_boundary(at) {
            at -= 1;
        }
        let cut = rest[..at].rfind('\n').filter(|n| *n > 0).unwrap_or(at);
        out.push(rest[..cut].trim_end().to_owned());
        rest = rest[cut..].trim_start();
    }
    if !rest.is_empty() {
        out.push(rest.to_owned());
    }
    out
}

impl<S: Talk, H: Harness> Bridge<S, H> {
    /// One pass over every room an agent answers in. `month` is the
    /// current month, YYYY-MM.
    pub fn step(&mut self, month: &str) -> Vec<Did> {
        if self.state.month != month {
            self.state.month = month.to_owned();
            self.state.spent.clear();
            self.state.told.clear();
        }
        let mut did = Vec::new();
        let owner = self.declared.user(&self.declared.owner);
        for agent in self.agents.clone() {
            let Some(room) = self.declared.rooms.iter().find(|r| r.team == agent.name).cloned() else {
                continue;
            };
            let alias = self.declared.alias(&room);
            let fail = |why: String| Did::Failed { room: alias.clone(), why };
            let id = match self.server.resolve(&agent.name, &alias) {
                Ok(Some(id)) => id,
                Ok(None) => continue,
                Err(e) => {
                    did.push(fail(e));
                    continue;
                }
            };
            let said = match self.server.messages(&agent.name, &id, WINDOW) {
                Ok(said) => said,
                Err(e) => {
                    did.push(fail(e));
                    continue;
                }
            };
            let Some(latest) = said.last().map(|m| m.id.clone()) else {
                // An empty room is seen from its beginning: the first
                // thing said in it is new.
                self.state.seen.entry(alias).or_default();
                continue;
            };
            // What is new: everything after the last message handled. A
            // room seen for the first time, or one whose marker has left
            // the window, starts from its latest message: old talk is not
            // answered.
            let new = match self.state.seen.get(&alias) {
                Some(seen) if seen.is_empty() => said.clone(),
                Some(seen) => said.iter().position(|m| &m.id == seen).map(|at| said[at + 1..].to_vec()).unwrap_or_default(),
                None => Vec::new(),
            };
            // The place kept is the last message this pass read. What the
            // agent says below, and what the owner says meanwhile, come
            // after it and are new to the next pass, where the agent's own
            // words start nothing.
            let before = self.state.seen.get(&alias).cloned();
            self.state.seen.insert(alias.clone(), latest);
            let mut handled = before;
            for message in new.iter() {
                if message.from != owner {
                    handled = Some(message.id.clone());
                    continue;
                }
                if self.state.spent.get(&agent.name).copied().unwrap_or(0.0) >= agent.cap_usd {
                    if !self.state.told.contains(&agent.name) {
                        let notice = format!("I have reached this month's cap of ${:.2} and answer nothing more until it resets or is raised.", agent.cap_usd);
                        if let Err(e) = self.server.say(&agent.name, &id, &notice) {
                            // Not said: this message waits for the next pass.
                            match &handled {
                                Some(place) => self.state.seen.insert(alias.clone(), place.clone()),
                                None => self.state.seen.remove(&alias),
                            };
                            did.push(fail(e));
                            break;
                        }
                        self.state.told.push(agent.name.clone());
                    }
                    did.push(Did::Refused { room: alias.clone() });
                    handled = Some(message.id.clone());
                    continue;
                }
                handled = Some(message.id.clone());
                let session = self.state.sessions.get(&alias).cloned();
                match self.harness.turn(&agent, session.as_deref(), &message.body) {
                    Ok((session, reply)) => {
                        self.state.sessions.insert(alias.clone(), session);
                        let cost_usd = agent.charge(&reply);
                        *self.state.spent.entry(agent.name.clone()).or_insert(0.0) += cost_usd;
                        let parts = pieces(&reply.text);
                        let parts = if parts.is_empty() { vec!["(The agent answered nothing.)".to_owned()] } else { parts };
                        for part in parts {
                            if let Err(e) = self.server.say(&agent.name, &id, &part) {
                                did.push(fail(e));
                            }
                        }
                        did.push(Did::Answered { room: alias.clone(), cost_usd });
                    }
                    Err(why) => {
                        let _ = self.server.say(&agent.name, &id, "I could not answer that just now. Nothing was done; say it again to retry.");
                        did.push(fail(why));
                    }
                }
            }
        }
        did
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use matrix_rooms::memory::Fake;
    use matrix_rooms::{reconcile, Room, Server};

    /// A harness that answers with what it was told. Every turn reports a
    /// million tokens read, so a turn is charged the agent's input price.
    #[derive(Default)]
    struct Echo {
        turns: Vec<(String, Option<String>, String)>,
        broken: bool,
    }

    impl Harness for Echo {
        fn turn(&mut self, agent: &Agent, session: Option<&str>, said: &str) -> Result<(String, Reply), String> {
            if self.broken {
                return Err("the harness is down".into());
            }
            self.turns.push((agent.name.clone(), session.map(str::to_owned), said.to_owned()));
            Ok((format!("ses-{}", agent.name), Reply { text: format!("{} heard: {said}", agent.name), tokens_in: 1_000_000, tokens_out: 0 }))
        }
    }

    /// A homeserver on which the owner says something more at the moment
    /// the agent first speaks: that is, while a pass is under way. It can
    /// also refuse what an agent says, a number of times.
    struct Busy {
        inner: Fake,
        interject: Option<String>,
        refuse: usize,
    }

    impl Server for Busy {
        fn resolve(&mut self, by: &str, alias: &str) -> Result<Option<String>, String> {
            self.inner.resolve(by, alias)
        }
        fn create(&mut self, by: &str, room: &Room, invite: &[String]) -> Result<String, String> {
            self.inner.create(by, room, invite)
        }
        fn joined(&mut self, by: &str, id: &str) -> Result<std::collections::BTreeSet<String>, String> {
            self.inner.joined(by, id)
        }
        fn invite(&mut self, by: &str, id: &str, user: &str) -> Result<(), String> {
            self.inner.invite(by, id, user)
        }
        fn join(&mut self, by: &str, id: &str) -> Result<(), String> {
            self.inner.join(by, id)
        }
        fn topic(&mut self, by: &str, id: &str) -> Result<Option<String>, String> {
            self.inner.topic(by, id)
        }
        fn set_topic(&mut self, by: &str, id: &str, topic: &str) -> Result<(), String> {
            self.inner.set_topic(by, id, topic)
        }
    }

    impl Talk for Busy {
        fn messages(&mut self, by: &str, id: &str, limit: usize) -> Result<Vec<matrix_rooms::Message>, String> {
            self.inner.messages(by, id, limit)
        }
        fn say(&mut self, by: &str, id: &str, body: &str) -> Result<(), String> {
            if by != "zach" && self.refuse > 0 {
                self.refuse -= 1;
                return Err("the homeserver refused it".into());
            }
            self.inner.say(by, id, body)?;
            if by != "zach" {
                if let Some(more) = self.interject.take() {
                    self.inner.say("zach", id, &more)?;
                }
            }
            Ok(())
        }
    }

    fn busy(price: f64) -> Bridge<Busy, Echo> {
        let b = started(price);
        Bridge { declared: b.declared, agents: b.agents, server: Busy { inner: b.server, interject: None, refuse: 0 }, harness: b.harness, state: b.state }
    }

    #[test]
    fn what_the_owner_says_while_a_turn_runs_is_answered_next() {
        let mut b = busy(0.01);
        let id = b.server.inner.aliases["#front:example.org"].clone();
        b.server.interject = Some("and another thing".into());
        b.server.say("zach", &id, "first").unwrap();
        assert!(matches!(b.step("2026-11")[..], [Did::Answered { .. }]));
        // The second message arrived as the agent answered the first.
        assert!(matches!(b.step("2026-11")[..], [Did::Answered { .. }]));
        let heard: Vec<&str> = b.harness.turns.iter().map(|t| t.2.as_str()).collect();
        assert_eq!(heard, ["first", "and another thing"]);
        assert_eq!(b.step("2026-11"), vec![]);
        assert_eq!(b.harness.turns.len(), 2);
    }

    #[test]
    fn a_cap_notice_that_could_not_be_said_is_said_on_the_next_pass() {
        let mut b = busy(2.0);
        let id = b.server.inner.aliases["#front:example.org"].clone();
        b.server.say("zach", &id, "one").unwrap();
        b.step("2026-11");
        // The cap of 1.00 is now spent. The next refusal cannot be said once.
        b.server.refuse = 1;
        b.server.say("zach", &id, "two").unwrap();
        assert!(matches!(b.step("2026-11")[..], [Did::Failed { .. }]));
        assert!(b.state.told.is_empty());
        assert_eq!(b.step("2026-11"), vec![Did::Refused { room: "#front:example.org".into() }]);
        let all = b.server.inner.messages("zach", &id, 99).unwrap();
        assert_eq!(all.iter().filter(|m| m.body.contains("this month's cap")).count(), 1);
        assert_eq!(b.step("2026-11"), vec![]);
    }

    fn bridge(price: f64) -> Bridge<Fake, Echo> {
        let room = |team: &str| Room { team: team.into(), alias: team.into(), topic: String::new(), members: vec!["zach".into(), team.into()] };
        let declared = Declared { server: "example.org".into(), owner: "zach".into(), rooms: vec![room("front"), room("design"), room("review")] };
        let mut server = Fake::named("example.org");
        reconcile(&declared, &mut server, false).unwrap();
        let agent = |name: &str| Agent { name: name.into(), model: "m".into(), port: 1, cap_usd: 1.0, input_usd_per_million: price, output_usd_per_million: 0.0 };
        // review has a room and no answering agent.
        Bridge { declared, agents: vec![agent("front"), agent("design")], server, harness: Echo::default(), state: State::default() }
    }

    fn room(b: &Bridge<Fake, Echo>, team: &str) -> String {
        b.server.aliases[&format!("#{team}:example.org")].clone()
    }

    fn said(b: &mut Bridge<Fake, Echo>, team: &str) -> Vec<(String, String)> {
        let id = room(b, team);
        b.server.messages("zach", &id, 99).unwrap().into_iter().map(|m| (m.from, m.body)).collect()
    }

    /// The first pass only marks where each room stands.
    fn started(price: f64) -> Bridge<Fake, Echo> {
        let mut b = bridge(price);
        for team in ["front", "design", "review"] {
            let id = room(&b, team);
            b.server.say("zach", &id, "before the bridge").unwrap();
        }
        assert_eq!(b.step("2026-11"), vec![]);
        b
    }

    #[test]
    fn what_was_there_before_the_bridge_is_not_answered() {
        let mut b = started(0.01);
        assert!(b.harness.turns.is_empty());
        assert_eq!(said(&mut b, "front").len(), 1);
    }

    #[test]
    fn the_owner_is_answered_once_in_the_room_spoken_in_and_as_its_agent() {
        let mut b = started(0.01);
        let id = room(&b, "front");
        b.server.say("zach", &id, "hello").unwrap();
        assert_eq!(b.step("2026-11"), vec![Did::Answered { room: "#front:example.org".into(), cost_usd: 0.01 }]);
        assert_eq!(said(&mut b, "front")[1..], [("@zach:example.org".into(), "hello".into()), ("@front:example.org".into(), "front heard: hello".into())]);
        assert_eq!(said(&mut b, "design").len(), 1);
        assert_eq!(b.step("2026-11"), vec![]);
        assert_eq!(b.harness.turns.len(), 1);
    }

    #[test]
    fn the_first_thing_said_in_an_empty_room_is_answered() {
        let mut b = bridge(0.01);
        assert_eq!(b.step("2026-11"), vec![]);
        let id = room(&b, "front");
        b.server.say("zach", &id, "first words").unwrap();
        assert!(matches!(b.step("2026-11")[..], [Did::Answered { .. }]));
        assert_eq!(said(&mut b, "front").last().unwrap().1, "front heard: first words");
        assert_eq!(b.step("2026-11"), vec![]);
    }

    #[test]
    fn what_an_agent_says_never_starts_a_turn() {
        let mut b = started(0.01);
        let id = room(&b, "design");
        b.server.say("design", &id, "talking to myself").unwrap();
        assert_eq!(b.step("2026-11"), vec![]);
        assert!(b.harness.turns.is_empty());
    }

    #[test]
    fn a_room_with_no_answering_agent_is_left_alone() {
        let mut b = started(0.01);
        let id = room(&b, "review");
        b.server.say("zach", &id, "anyone?").unwrap();
        assert_eq!(b.step("2026-11"), vec![]);
        assert_eq!(said(&mut b, "review").len(), 2);
    }

    #[test]
    fn a_room_keeps_its_own_thread() {
        let mut b = started(0.01);
        for text in ["one", "two"] {
            let id = room(&b, "front");
            b.server.say("zach", &id, text).unwrap();
            b.step("2026-11");
        }
        let id = room(&b, "design");
        b.server.say("zach", &id, "three").unwrap();
        b.step("2026-11");
        let threads: Vec<Option<&str>> = b.harness.turns.iter().map(|t| t.1.as_deref()).collect();
        assert_eq!(threads, [None, Some("ses-front"), None]);
    }

    #[test]
    fn at_its_cap_an_agent_stops_and_says_so_once_and_a_new_month_starts_it_again() {
        let mut b = started(0.6);
        let id = room(&b, "front");
        for text in ["one", "two", "three", "four"] {
            b.server.say("zach", &id, text).unwrap();
            b.step("2026-11");
        }
        // 0.6 + 0.6 reaches the cap of 1.00: two answered, two refused.
        assert_eq!(b.harness.turns.len(), 2);
        let notices = said(&mut b, "front").iter().filter(|(_, body)| body.contains("this month's cap")).count();
        assert_eq!(notices, 1);
        // Another agent's month is its own.
        let other = room(&b, "design");
        b.server.say("zach", &other, "still there?").unwrap();
        assert!(matches!(b.step("2026-11")[..], [Did::Answered { .. }]));
        b.server.say("zach", &id, "five").unwrap();
        assert!(matches!(b.step("2026-12")[..], [Did::Answered { .. }]));
    }

    #[test]
    fn a_harness_that_fails_says_so_and_is_not_charged_or_retried() {
        let mut b = started(0.01);
        b.harness.broken = true;
        let id = room(&b, "front");
        b.server.say("zach", &id, "hello").unwrap();
        assert!(matches!(b.step("2026-11")[..], [Did::Failed { .. }]));
        assert!(said(&mut b, "front").last().unwrap().1.contains("could not answer"));
        assert_eq!(b.state.spent.get("front"), None);
        assert_eq!(b.step("2026-11"), vec![]);
    }

    #[test]
    fn the_state_survives_a_restart() {
        let mut b = started(0.01);
        let id = room(&b, "front");
        b.server.say("zach", &id, "hello").unwrap();
        b.step("2026-11");
        let kept: State = serde_json::from_str(&serde_json::to_string(&b.state).unwrap()).unwrap();
        assert_eq!(kept, b.state);
        b.harness.turns.clear();
        b.state = kept;
        assert_eq!(b.step("2026-11"), vec![]);
        assert!(b.harness.turns.is_empty());
    }

    #[test]
    fn a_turn_is_charged_its_tokens_at_the_pinned_price() {
        let agent = Agent { name: "a".into(), model: "m".into(), port: 1, cap_usd: 1.0, input_usd_per_million: 0.3, output_usd_per_million: 1.2 };
        let reply = Reply { text: String::new(), tokens_in: 2245, tokens_out: 11 };
        assert!((agent.charge(&reply) - (2245.0 * 0.3 + 11.0 * 1.2) / 1_000_000.0).abs() < 1e-15);
    }

    #[test]
    fn a_long_answer_is_said_in_pieces_and_none_is_lost() {
        let text = format!("{}\n{}", "a".repeat(LONGEST - 10), "b".repeat(LONGEST));
        let parts = pieces(&text);
        assert_eq!(parts.len(), 2);
        assert!(parts.iter().all(|p| p.len() <= LONGEST));
        assert_eq!(parts.concat().replace('\n', "").len(), 2 * LONGEST - 10);
        assert_eq!(pieces("  short  "), ["short"]);
        assert_eq!(pieces("   "), Vec::<String>::new());
    }

    #[test]
    fn a_room_the_homeserver_has_not_made_is_skipped() {
        let mut b = bridge(0.01);
        b.server.aliases.clear();
        assert_eq!(b.step("2026-11"), vec![]);
        let _ = b.server.resolve("zach", "#front:example.org");
    }
}
