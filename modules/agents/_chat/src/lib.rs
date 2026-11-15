//! The chat pages: the owner talks to a team on the shell's own site.
//!
//! The browser speaks only to this gateway, which Cloudflare Access already
//! guards, and the gateway speaks to the homeserver as its application
//! service (../_rooms). So there is one sign-in, Access, and no second
//! one: no homeserver password, no client to sign in to.
//!
//!   GET  <prefix>/           the teams, each a link to its room
//!   GET  <prefix>/<team>/    what was said, oldest first, and the box to
//!                            answer in
//!   POST <prefix>/<team>/    says it as the owner, then shows the room again
//!
//! Every page is a whole document built with the site's own parts
//! (kagamizo_site), works with no script, and passes the same audit the
//! static pages pass (the tests below). `Chat::handle` is a function of
//! the request and the homeserver, so all of it is tested against the
//! homeserver kept in memory; ./serve.rs is the part that listens.
pub mod access;
pub mod serve;

use kagamizo_site::html::{document, el, Node};
use kagamizo_site::pages::{frame, Here};
use matrix_rooms::{Declared, Message, Room, Talk};

/// The longest message taken, in bytes.
pub const LONGEST: usize = 8000;
/// How many messages a room's page shows.
pub const SHOWN: usize = 50;

pub struct Request<'a> {
    pub method: &'a str,
    pub path: &'a str,
    /// The body of a form, as the browser sent it.
    pub form: &'a str,
    /// The address Cloudflare Access vouched for, if it vouched for one.
    pub who: Option<&'a str>,
    /// The browser says the request came from a page of this site.
    pub same_origin: bool,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Response {
    pub status: u16,
    pub body: String,
    pub location: Option<String>,
}

pub struct Chat<S: Talk> {
    pub declared: Declared,
    /// The one address that may talk here.
    pub owner: String,
    /// Where the pages are served, with no slash at the end.
    pub prefix: String,
    pub server: S,
}

fn title_case(s: &str) -> String {
    s.split('-').map(|w| w.chars().next().map(|c| c.to_uppercase().collect::<String>() + &w[c.len_utf8()..]).unwrap_or_default()).collect::<Vec<_>>().join(" ")
}

/// A moment, as a person reads it: 2026-11-15 21:16 UTC.
pub fn moment(ms: u64) -> String {
    let (days, rest) = ((ms / 86_400_000) as i64, ms % 86_400_000);
    // Days since 1970 to a civil date (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let (d, m) = (doy - (153 * mp + 2) / 5 + 1, if mp < 10 { mp + 3 } else { mp - 9 });
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02} {:02}:{:02} UTC", rest / 3_600_000, rest % 3_600_000 / 60_000)
}

/// One field of a form body, decoded.
pub fn field(form: &str, name: &str) -> Option<String> {
    let raw = form.split('&').find_map(|pair| pair.strip_prefix(name)?.strip_prefix('='))?;
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' => {
                let hex = raw.get(i + 1..i + 3)?;
                out.push(u8::from_str_radix(hex, 16).ok()?);
                i += 2;
            }
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8(out).ok()
}

fn page(status: u16, root: &Node) -> Response {
    Response { status, body: document(root), location: None }
}

fn plain(here: Here, status: u16, heading: &str, said: &str) -> Response {
    page(status, &frame(here, &format!("{heading} · Kagamizo"), vec![el("h1").text(heading), el("p").class("lede").text(said)]))
}

impl<S: Talk> Chat<S> {
    fn local(&self, account: &str) -> String {
        account.strip_prefix('@').and_then(|a| a.strip_suffix(&format!(":{}", self.declared.server))).unwrap_or(account).to_owned()
    }

    pub fn teams(&self) -> Node {
        let rooms = &self.declared.rooms;
        let list = el("ul").class("index").children(rooms.iter().map(|r| el("li").child(el("a").attr("href", format!("{}/", r.team)).text(title_case(&r.team)))));
        let body = vec![
            el("h1").text("Chat"),
            el("p").class("lede").text("Every team has one room, holding you and that team. Choose a team to read its room and talk to it."),
            el("h2").attr("id", "teams").text(format!("Teams ({})", rooms.len())),
            el("nav").attr("aria-labelledby", "teams").child(list),
        ];
        frame(Here::Chat, "Chat · Kagamizo", body)
    }

    pub fn room(&self, room: &Room, said: &[Message]) -> Node {
        let name = title_case(&room.team);
        let last = said.len().saturating_sub(1);
        let lines = said.iter().enumerate().map(|(i, m)| {
            let line = el("li").child(el("span").class("who").text(format!("{} · {}", self.local(&m.from), moment(m.at)))).child(el("p").text(m.body.clone()));
            if i == last {
                line.attr("id", "latest")
            } else {
                line
            }
        });
        let talk = if said.is_empty() {
            el("p").class("none").attr("id", "latest").text("Nothing has been said here yet.")
        } else {
            el("ol").class("said").children(lines)
        };
        let form = el("form")
            .class("say")
            .attr("method", "post")
            .attr("action", "./")
            .attr("aria-label", format!("Say something to {name}"))
            .child(el("label").attr("for", "say").text(format!("Message to {name}")))
            .child(el("textarea").attr("id", "say").attr("name", "body").attr("rows", "3").attr("required", "").attr("maxlength", LONGEST.to_string()))
            .child(el("button").attr("type", "submit").text("Send"));
        let body = vec![
            el("h1").text(name.clone()),
            el("p").class("lede").text(room.topic.clone()),
            el("h2").attr("id", "said").text(format!("What was said ({})", said.len())),
            el("section").attr("aria-labelledby", "said").child(talk),
            form,
            el("p").child(el("a").class("again").attr("href", "./").text("Check for new messages")),
        ];
        frame(Here::Room, &format!("{name} · Chat · Kagamizo"), body)
    }

    pub fn handle(&mut self, r: &Request) -> Response {
        if r.who != Some(self.owner.as_str()) {
            return plain(Here::Chat, 403, "Not yours", "This page talks only for the owner, and Cloudflare Access did not vouch for the owner on this request.");
        }
        let Some(rest) = r.path.strip_prefix(self.prefix.as_str()) else {
            return plain(Here::Chat, 404, "No such page", "Nothing is served here.");
        };
        let rest = rest.split(['?', '#']).next().unwrap_or("");
        if rest.is_empty() {
            return Response { status: 308, body: String::new(), location: Some(format!("{}/", self.prefix)) };
        }
        if rest == "/" {
            return match r.method {
                "GET" | "HEAD" => page(200, &self.teams()),
                _ => plain(Here::Chat, 405, "Not that way", "This page is only read."),
            };
        }
        let Some(room) = rest.strip_prefix('/').and_then(|t| t.strip_suffix('/')).and_then(|t| self.declared.rooms.iter().find(|room| room.team == t)).cloned() else {
            return plain(Here::Chat, 404, "No such room", "No team of that name is declared.");
        };
        let owner = self.declared.owner.clone();
        let id = match self.server.resolve(&owner, &self.declared.alias(&room)) {
            Ok(Some(id)) => id,
            Ok(None) => return plain(Here::Room, 503, "Not made yet", "This team's room is declared, and the homeserver has not made it yet."),
            Err(_) => return plain(Here::Room, 502, "The homeserver did not answer", "The room could not be read just now. Nothing was sent."),
        };
        match r.method {
            "GET" | "HEAD" => match self.server.messages(&owner, &id, SHOWN) {
                Ok(said) => page(200, &self.room(&room, &said)),
                Err(_) => plain(Here::Room, 502, "The homeserver did not answer", "The room could not be read just now."),
            },
            "POST" => {
                if !r.same_origin {
                    return plain(Here::Room, 403, "Not from here", "A message is taken only from this site's own page. Nothing was sent.");
                }
                let text = field(r.form, "body").unwrap_or_default();
                let text = text.trim();
                if text.len() > LONGEST {
                    return plain(Here::Room, 413, "Too long", "That message is longer than a room takes. Nothing was sent.");
                }
                if !text.is_empty() && self.server.say(&owner, &id, text).is_err() {
                    return plain(Here::Room, 502, "The homeserver did not answer", "Your message was not sent. Go back and send it again.");
                }
                Response { status: 303, body: String::new(), location: Some(format!("{}/{}/#latest", self.prefix, room.team)) }
            }
            _ => plain(Here::Room, 405, "Not that way", "A room is read, or a message is sent to it."),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kagamizo_site::a11y;
    use matrix_rooms::memory::Fake;
    use matrix_rooms::reconcile;

    const OWNER: &str = "owner@example.org";

    fn chat() -> Chat<Fake> {
        let room = |team: &str| Room { team: team.into(), alias: team.into(), topic: format!("What the {team} team is for"), members: vec!["zach".into(), team.into()] };
        let declared = Declared { server: "example.org".into(), owner: "zach".into(), rooms: vec![room("design"), room("research-jingzo")] };
        let mut server = Fake::named("example.org");
        reconcile(&declared, &mut server, false).unwrap();
        Chat { declared, owner: OWNER.into(), prefix: "/next/chat".into(), server }
    }

    fn get(path: &str) -> Request<'_> {
        Request { method: "GET", path, form: "", who: Some(OWNER), same_origin: true }
    }

    fn post<'a>(path: &'a str, form: &'a str) -> Request<'a> {
        Request { method: "POST", path, form, who: Some(OWNER), same_origin: true }
    }

    #[test]
    fn every_page_passes_the_audit_the_static_pages_pass() {
        let mut c = chat();
        c.handle(&post("/next/chat/design/", "body=hello"));
        for path in ["/next/chat/", "/next/chat/design/", "/next/chat/research-jingzo/", "/next/chat/nobody/"] {
            let page = match path {
                "/next/chat/" => c.teams(),
                "/next/chat/nobody/" => frame(Here::Chat, "x · Kagamizo", vec![el("h1").text("No such room"), el("p").text("…")]),
                _ => {
                    let room = c.declared.rooms.iter().find(|r| path.contains(&r.team)).unwrap().clone();
                    let id = c.server.aliases[&c.declared.alias(&room)].clone();
                    let said = c.server.messages("zach", &id, SHOWN).unwrap();
                    c.room(&room, &said)
                }
            };
            assert_eq!(a11y::problems(&page), Vec::<String>::new(), "{path}");
        }
    }

    #[test]
    fn the_teams_page_links_every_declared_room() {
        let body = chat().handle(&get("/next/chat/")).body;
        assert!(body.contains(r#"<a href="design/">Design</a>"#) && body.contains(r#"<a href="research-jingzo/">Research Jingzo</a>"#));
    }

    #[test]
    fn what_the_owner_sends_is_said_as_the_owner_and_shown() {
        let mut c = chat();
        let sent = c.handle(&post("/next/chat/design/", "body=Hello%2C+team+%26+%3Cb%3Eall%3C%2Fb%3E"));
        assert_eq!((sent.status, sent.location.as_deref()), (303, Some("/next/chat/design/#latest")));
        let id = c.server.aliases["#design:example.org"].clone();
        let kept = &c.server.rooms[&id].messages;
        assert_eq!((kept.len(), kept[0].from.as_str(), kept[0].body.as_str()), (1, "@zach:example.org", "Hello, team & <b>all</b>"));
        let shown = c.handle(&get("/next/chat/design/")).body;
        assert!(shown.contains("Hello, team &amp; &lt;b&gt;all&lt;/b&gt;") && !shown.contains("<b>all"));
        assert!(shown.contains(r#"<li id="latest">"#) && shown.contains("zach · 2023-11-14 22:13 UTC"));
    }

    #[test]
    fn a_message_goes_only_to_its_own_room() {
        let mut c = chat();
        c.handle(&post("/next/chat/design/", "body=for+design"));
        assert!(!c.handle(&get("/next/chat/research-jingzo/")).body.contains("for design"));
    }

    #[test]
    fn nobody_but_the_owner_reads_or_sends() {
        let mut c = chat();
        for who in [None, Some("someone@example.org"), Some("")] {
            for (method, path) in [("GET", "/next/chat/"), ("GET", "/next/chat/design/"), ("POST", "/next/chat/design/")] {
                let got = c.handle(&Request { method, path, form: "body=x", who, same_origin: true });
                assert_eq!(got.status, 403, "{who:?} {method} {path}");
                assert!(!got.body.contains("What was said"));
            }
        }
        assert_eq!(c.server.rooms.values().map(|r| r.messages.len()).sum::<usize>(), 0);
    }

    #[test]
    fn a_form_posted_from_another_site_sends_nothing() {
        let mut c = chat();
        let got = c.handle(&Request { method: "POST", path: "/next/chat/design/", form: "body=x", who: Some(OWNER), same_origin: false });
        assert_eq!(got.status, 403);
        assert_eq!(c.server.rooms.values().map(|r| r.messages.len()).sum::<usize>(), 0);
    }

    #[test]
    fn nothing_and_too_much_are_not_sent() {
        let mut c = chat();
        assert_eq!(c.handle(&post("/next/chat/design/", "body=++%0A")).status, 303);
        let long = format!("body={}", "a".repeat(LONGEST + 1));
        assert_eq!(c.handle(&post("/next/chat/design/", &long)).status, 413);
        assert_eq!(c.server.rooms.values().map(|r| r.messages.len()).sum::<usize>(), 0);
    }

    #[test]
    fn only_declared_rooms_and_known_ways_answer() {
        let mut c = chat();
        assert_eq!(c.handle(&get("/next/chat/nobody/")).status, 404);
        assert_eq!(c.handle(&get("/next/chat/design/../research-jingzo/")).status, 404);
        assert_eq!(c.handle(&get("/elsewhere/")).status, 404);
        assert_eq!(c.handle(&get("/next/chat")).location.as_deref(), Some("/next/chat/"));
        assert_eq!(c.handle(&Request { method: "DELETE", path: "/next/chat/design/", form: "", who: Some(OWNER), same_origin: true }).status, 405);
    }

    #[test]
    fn a_room_the_homeserver_has_not_made_says_so() {
        let mut c = chat();
        c.server.aliases.clear();
        assert_eq!(c.handle(&get("/next/chat/design/")).status, 503);
    }

    #[test]
    fn a_form_field_decodes_and_a_broken_one_is_refused() {
        assert_eq!(field("a=1&body=x+y%21", "body").as_deref(), Some("x y!"));
        assert_eq!(field("body=%zz", "body"), None);
        assert_eq!(field("nobody=1", "body"), None);
    }

    #[test]
    fn a_moment_reads_as_a_date() {
        assert_eq!(moment(0), "1970-01-01 00:00 UTC");
        assert_eq!(moment(1_794_000_000_000), "2026-11-06 21:20 UTC");
        assert_eq!(moment(951_782_400_000), "2000-02-29 00:00 UTC");
    }
}
