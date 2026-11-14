//! The shell's state, apart from drawing it: what is declared, where the
//! focus is, and what a key does. Pure, so it is tested without a screen.
//!
//! The home is a library: every module of the repository is either part of
//! the base (a section of Settings) or registers apps, which the home shows
//! on shelves, one per category, in the declared order.
use serde::Deserialize;
use std::collections::BTreeMap;

#[derive(Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Native,
    Web,
    Builtin,
    /// A module without a screen of its own: its card opens its page.
    Module,
}

#[derive(Deserialize, Clone, Debug)]
pub struct App {
    pub name: String,
    pub category: String,
    pub kind: Kind,
    pub command: Option<String>,
    pub url: Option<String>,
    pub targets: Vec<String>,
    pub module: String,
    #[serde(default)]
    pub description: String,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Entry {
    pub title: String,
    pub detail: String,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Section {
    pub key: String,
    pub title: String,
    pub rows: Vec<Entry>,
}

/// A module's page, generated from its declarations and its paper.
#[derive(Deserialize, Clone, Debug, Default)]
pub struct Page {
    pub title: String,
    #[serde(rename = "abstract")]
    pub summary: String,
    /// What the module's Lean proves, by name (its paper explains each).
    #[serde(default)]
    pub theorems: Vec<String>,
    pub checks: Vec<String>,
    pub packages: Vec<String>,
    pub teams: Vec<String>,
    /// Sections of rows the module generates for its page (the plan's tracks).
    #[serde(default)]
    pub view: Vec<View>,
    /// Where the module sits in the library: an app, the base, or a service.
    #[serde(default)]
    pub place: String,
    /// Why a base module exists, in a sentence.
    #[serde(default)]
    pub why: String,
}

/// A card of the wallet: a Proton Pass item by its type, vault and title.
/// Only what it is; its values are in Pass.
#[derive(Deserialize, Clone, Debug, Default)]
pub struct Card {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub vault: String,
    pub title: String,
    pub mint: String,
    pub target: String,
    pub account: String,
    pub factor: String,
    pub holders: Vec<String>,
}

/// A payment card: its limit per interval and what it is locked to.
#[derive(Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct Payment {
    pub name: String,
    pub nickname: String,
    pub limit_usd: u64,
    pub interval: String,
    pub account: String,
    pub why: String,
    pub lock: String,
}

/// A mailbox card: one address handed to one team, for what it says.
#[derive(Deserialize, Clone, Debug, Default)]
pub struct MailCard {
    pub name: String,
    pub address: String,
    pub from: Vec<String>,
    pub may: Vec<String>,
    pub holder: String,
    pub until: String,
    pub why: String,
}

#[derive(Deserialize, Clone, Debug, Default)]
pub struct Wallet {
    pub cards: Vec<Card>,
    pub payment: Vec<Payment>,
    #[serde(default)]
    pub mailbox: Vec<MailCard>,
}

#[derive(Deserialize, Clone, Debug, Default)]
pub struct View {
    pub title: String,
    pub rows: Vec<Entry>,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Declared {
    pub apps: BTreeMap<String, App>,
    pub sections: Vec<Section>,
    pub categories: Vec<String>,
    pub pages: BTreeMap<String, Page>,
    #[serde(default)]
    pub wallet: Wallet,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Screen {
    Home,
    Settings,
    /// The focused app's module page.
    Detail,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Key {
    Up,
    Down,
    Left,
    Right,
    Enter,
    Back,
}

/// What a key asks the shell to do outside itself.
#[derive(Clone, Debug, PartialEq)]
pub enum Effect {
    None,
    Run(String),
    Open(String),
}

pub struct Shell {
    pub declared: Declared,
    /// The apps this target shows, in shelf order: by the declared
    /// category order, built-ins first within a shelf, then by name.
    pub apps: Vec<(String, App)>,
    pub screen: Screen,
    pub focus: usize,
    pub section: usize,
    pub row: usize,
    /// Whether the settings' focus is in the section list (false) or a section's rows (true).
    pub in_rows: bool,
}

impl Shell {
    pub fn new(declared: Declared, target: &str) -> Shell {
        let shelf = |c: &str| {
            declared
                .categories
                .iter()
                .position(|x| x == c)
                .unwrap_or(usize::MAX)
        };
        let mut apps: Vec<(String, App)> = declared
            .apps
            .iter()
            .filter(|(_, a)| a.targets.iter().any(|t| t == target))
            .map(|(id, a)| (id.clone(), a.clone()))
            .collect();
        apps.sort_by(|(_, a), (_, b)| {
            (shelf(&a.category), a.kind != Kind::Builtin, a.name.as_str()).cmp(&(
                shelf(&b.category),
                b.kind != Kind::Builtin,
                b.name.as_str(),
            ))
        });
        Shell {
            declared,
            apps,
            screen: Screen::Home,
            focus: 0,
            section: 0,
            row: 0,
            in_rows: false,
        }
    }

    pub fn rows(&self) -> &[Entry] {
        self.declared
            .sections
            .get(self.section)
            .map(|s| s.rows.as_slice())
            .unwrap_or(&[])
    }

    /// The page of the focused app's module, when the detail screen shows.
    pub fn page(&self) -> Option<(&App, Page)> {
        let (_, a) = self.apps.get(self.focus)?;
        Some((
            a,
            self.declared
                .pages
                .get(&a.module)
                .cloned()
                .unwrap_or_default(),
        ))
    }

    fn step(i: usize, len: usize, up: bool) -> usize {
        if len == 0 {
            0
        } else if up {
            i.saturating_sub(1)
        } else {
            (i + 1).min(len - 1)
        }
    }

    /// A tap on the home column's i-th card: focus it and open it.
    pub fn tap_app(&mut self, i: usize, web: bool) -> Effect {
        if i >= self.apps.len() {
            return Effect::None;
        }
        self.focus = i;
        self.key(Key::Enter, web)
    }

    /// A tap on the i-th settings section: show its rows.
    pub fn tap_section(&mut self, i: usize) {
        if i < self.declared.sections.len() {
            self.section = i;
            self.row = 0;
            self.in_rows = false;
        }
    }

    /// A tap on the i-th row of the shown section.
    pub fn tap_row(&mut self, i: usize) {
        if i < self.rows().len() {
            self.in_rows = true;
            self.row = i;
        }
    }

    /// Back to the home column, from anywhere.
    pub fn go_home(&mut self) {
        self.screen = Screen::Home;
        self.in_rows = false;
    }

    /// Apply one key; `web` is whether this target is a browser.
    pub fn key(&mut self, k: Key, web: bool) -> Effect {
        match self.screen {
            Screen::Home => match k {
                Key::Up | Key::Down => {
                    self.focus = Self::step(self.focus, self.apps.len(), k == Key::Up);
                    Effect::None
                }
                Key::Enter => {
                    let Some((_, a)) = self.apps.get(self.focus) else {
                        return Effect::None;
                    };
                    match a.kind {
                        Kind::Builtin => {
                            self.screen = Screen::Settings;
                            self.section = 0;
                            self.row = 0;
                            self.in_rows = false;
                            Effect::None
                        }
                        Kind::Module => {
                            self.screen = Screen::Detail;
                            Effect::None
                        }
                        Kind::Native => a.command.clone().map(Effect::Run).unwrap_or(Effect::None),
                        Kind::Web if web => a.url.clone().map(Effect::Open).unwrap_or(Effect::None),
                        // On a device a web app opens in the browser, in its own window.
                        Kind::Web => a
                            .url
                            .clone()
                            .map(|u| Effect::Run(format!("firefox --new-window {u}")))
                            .unwrap_or(Effect::None),
                    }
                }
                _ => Effect::None,
            },
            Screen::Detail => {
                if matches!(k, Key::Back | Key::Left) {
                    self.screen = Screen::Home;
                }
                Effect::None
            }
            Screen::Settings => {
                match k {
                    Key::Back if self.in_rows => self.in_rows = false,
                    Key::Back | Key::Left if !self.in_rows => self.screen = Screen::Home,
                    Key::Left => self.in_rows = false,
                    Key::Right | Key::Enter if !self.in_rows && !self.rows().is_empty() => {
                        self.in_rows = true;
                        self.row = 0;
                    }
                    Key::Up | Key::Down if self.in_rows => {
                        self.row = Self::step(self.row, self.rows().len(), k == Key::Up)
                    }
                    Key::Up | Key::Down => {
                        self.section =
                            Self::step(self.section, self.declared.sections.len(), k == Key::Up);
                        self.row = 0;
                    }
                    _ => {}
                }
                Effect::None
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn declared() -> Declared {
        serde_json::from_str(
            r#"{
            "categories": ["system", "browse", "chat", "money"],
            "apps": {
              "settings": {"name": "Settings", "category": "system", "kind": "builtin", "command": null, "url": null, "targets": ["yoga", "web"], "module": "shell"},
              "browser": {"name": "Firefox", "category": "browse", "kind": "native", "command": "firefox", "url": null, "targets": ["yoga"], "module": "shell"},
              "chat": {"name": "Chat", "category": "chat", "kind": "web", "command": null, "url": "https://chat.jingzo.org", "targets": ["yoga", "web"], "module": "hetzner"},
              "trading": {"name": "Trading", "category": "money", "kind": "module", "command": null, "url": null, "targets": ["yoga", "web"], "module": "trading", "description": "paper first"}
            },
            "sections": [
              {"key": "system", "title": "System", "rows": [{"title": "yoga", "detail": "nixos"}]},
              {"key": "apps", "title": "Apps", "rows": []},
              {"key": "accounts", "title": "Accounts", "rows": [{"title": "a", "detail": ""}, {"title": "b", "detail": ""}]}
            ],
            "pages": {"trading": {"title": "Trading", "abstract": "the engine", "checks": ["trade"], "packages": ["trade"], "teams": ["research-jingzo"]}}
          }"#,
        )
        .unwrap()
    }

    fn at(s: &Shell, id: &str) -> usize {
        s.apps.iter().position(|(i, _)| i == id).unwrap()
    }

    #[test]
    fn a_target_shows_its_own_apps_on_their_shelves() {
        let s = Shell::new(declared(), "web");
        let ids: Vec<&str> = s.apps.iter().map(|(id, _)| id.as_str()).collect();
        assert_eq!(ids, vec!["settings", "chat", "trading"]);
        let s = Shell::new(declared(), "yoga");
        let ids: Vec<&str> = s.apps.iter().map(|(id, _)| id.as_str()).collect();
        assert_eq!(ids, vec!["settings", "browser", "chat", "trading"]);
    }

    #[test]
    fn the_column_stops_at_its_ends() {
        let mut s = Shell::new(declared(), "yoga");
        s.key(Key::Up, false);
        assert_eq!(s.focus, 0);
        for _ in 0..10 {
            s.key(Key::Down, false);
        }
        assert_eq!(s.focus, 3);
    }

    #[test]
    fn apps_open_by_their_kind() {
        let mut s = Shell::new(declared(), "yoga");
        s.focus = at(&s, "browser");
        assert_eq!(s.key(Key::Enter, false), Effect::Run("firefox".into()));
        s.focus = at(&s, "chat");
        assert_eq!(
            s.key(Key::Enter, false),
            Effect::Run("firefox --new-window https://chat.jingzo.org".into())
        );
        let mut w = Shell::new(declared(), "web");
        w.focus = at(&w, "chat");
        assert_eq!(
            w.key(Key::Enter, true),
            Effect::Open("https://chat.jingzo.org".into())
        );
    }

    #[test]
    fn a_module_card_opens_its_page_and_back_returns_home() {
        let mut s = Shell::new(declared(), "web");
        s.focus = at(&s, "trading");
        assert_eq!(s.key(Key::Enter, true), Effect::None);
        assert_eq!(s.screen, Screen::Detail);
        let (a, p) = s.page().unwrap();
        assert_eq!(
            (a.description.as_str(), p.summary.as_str()),
            ("paper first", "the engine")
        );
        s.key(Key::Back, true);
        assert_eq!(s.screen, Screen::Home);
    }

    #[test]
    fn settings_moves_between_sections_and_rows_and_back_home() {
        let mut s = Shell::new(declared(), "yoga");
        s.key(Key::Enter, false);
        assert_eq!(s.screen, Screen::Settings);
        s.key(Key::Down, false);
        s.key(Key::Down, false);
        assert_eq!(s.declared.sections[s.section].key, "accounts");
        s.key(Key::Right, false);
        s.key(Key::Down, false);
        assert_eq!((s.in_rows, s.row), (true, 1));
        s.key(Key::Back, false);
        assert!(!s.in_rows);
        s.key(Key::Back, false);
        assert_eq!(s.screen, Screen::Home);
    }

    #[test]
    fn taps_do_what_keys_do() {
        let mut s = Shell::new(declared(), "yoga");
        let chat = at(&s, "chat");
        assert_eq!(
            s.tap_app(chat, false),
            Effect::Run("firefox --new-window https://chat.jingzo.org".into())
        );
        assert_eq!(s.focus, chat);
        assert_eq!(s.tap_app(99, false), Effect::None);
        s.tap_app(0, false);
        assert_eq!(s.screen, Screen::Settings);
        s.tap_section(2);
        s.tap_row(1);
        assert_eq!((s.section, s.in_rows, s.row), (2, true, 1));
        s.tap_section(1);
        s.tap_row(0); // apps: empty, so nothing to enter
        assert!(!s.in_rows);
        s.go_home();
        assert_eq!(s.screen, Screen::Home);
    }

    #[test]
    fn an_empty_section_is_not_entered() {
        let mut s = Shell::new(declared(), "yoga");
        s.key(Key::Enter, false);
        s.key(Key::Down, false); // apps: empty
        s.key(Key::Right, false);
        assert!(!s.in_rows);
    }
}
