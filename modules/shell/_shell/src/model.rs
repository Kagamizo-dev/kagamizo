//! The shell's state, apart from drawing it: what is declared, where the
//! focus is, and what a key does. Pure, so it is tested without a screen.
use serde::Deserialize;
use std::collections::BTreeMap;

#[derive(Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Native,
    Web,
    Builtin,
}

#[derive(Deserialize, Clone, Debug)]
pub struct App {
    pub name: String,
    pub category: String,
    pub kind: Kind,
    pub command: Option<String>,
    pub url: Option<String>,
    pub targets: Vec<String>,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Entry {
    pub title: String,
    pub detail: String,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Declared {
    pub apps: BTreeMap<String, App>,
    pub sections: BTreeMap<String, Vec<Entry>>,
}

/// The settings sections, in the order the shell lists them.
pub const SECTIONS: &[(&str, &str)] = &[
    ("system", "System"),
    ("apps", "Apps"),
    ("accounts", "Accounts"),
    ("teams", "Teams"),
];

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Screen {
    Home,
    Settings,
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
    /// The apps this target shows, in order: built-ins first, then by category and name.
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
        let mut apps: Vec<(String, App)> = declared
            .apps
            .iter()
            .filter(|(_, a)| a.targets.iter().any(|t| t == target))
            .map(|(id, a)| (id.clone(), a.clone()))
            .collect();
        apps.sort_by(|(_, a), (_, b)| {
            (
                a.kind != Kind::Builtin,
                a.category.as_str(),
                a.name.as_str(),
            )
                .cmp(&(
                    b.kind != Kind::Builtin,
                    b.category.as_str(),
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
        let key = SECTIONS[self.section].0;
        self.declared
            .sections
            .get(key)
            .map(Vec::as_slice)
            .unwrap_or(&[])
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
        if i < SECTIONS.len() {
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
                        self.section = Self::step(self.section, SECTIONS.len(), k == Key::Up);
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
            "apps": {
              "settings": {"name": "Settings", "category": "system", "kind": "builtin", "command": null, "url": null, "targets": ["yoga", "web"]},
              "browser": {"name": "Firefox", "category": "browse", "kind": "native", "command": "firefox", "url": null, "targets": ["yoga"]},
              "chat": {"name": "Chat", "category": "chat", "kind": "web", "command": null, "url": "https://chat.jingzo.org", "targets": ["yoga", "web"]}
            },
            "sections": {"system": [{"title": "yoga", "detail": "nixos"}], "apps": [], "accounts": [{"title": "a", "detail": ""}, {"title": "b", "detail": ""}], "teams": []}
          }"#,
        )
        .unwrap()
    }

    #[test]
    fn a_target_shows_its_own_apps_settings_first() {
        let s = Shell::new(declared(), "web");
        let ids: Vec<&str> = s.apps.iter().map(|(id, _)| id.as_str()).collect();
        assert_eq!(ids, vec!["settings", "chat"]);
        let s = Shell::new(declared(), "yoga");
        assert_eq!(s.apps[0].0, "settings");
        assert_eq!(s.apps.len(), 3);
    }

    #[test]
    fn the_column_stops_at_its_ends() {
        let mut s = Shell::new(declared(), "yoga");
        s.key(Key::Up, false);
        assert_eq!(s.focus, 0);
        for _ in 0..10 {
            s.key(Key::Down, false);
        }
        assert_eq!(s.focus, 2);
    }

    #[test]
    fn apps_open_by_their_kind() {
        let mut s = Shell::new(declared(), "yoga");
        let at = |s: &Shell, id: &str| s.apps.iter().position(|(i, _)| i == id).unwrap();
        s.focus = at(&s, "browser");
        assert_eq!(s.key(Key::Enter, false), Effect::Run("firefox".into()));
        s.focus = at(&s, "chat");
        assert_eq!(
            s.key(Key::Enter, false),
            Effect::Run("firefox --new-window https://chat.jingzo.org".into())
        );
        let mut w = Shell::new(declared(), "web");
        w.focus = 1;
        assert_eq!(
            w.key(Key::Enter, true),
            Effect::Open("https://chat.jingzo.org".into())
        );
    }

    #[test]
    fn settings_moves_between_sections_and_rows_and_back_home() {
        let mut s = Shell::new(declared(), "yoga");
        s.key(Key::Enter, false);
        assert_eq!(s.screen, Screen::Settings);
        s.key(Key::Down, false);
        s.key(Key::Down, false);
        assert_eq!(SECTIONS[s.section].0, "accounts");
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
        let chat = s.apps.iter().position(|(i, _)| i == "chat").unwrap();
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
