//! The site, as a pure function of the declarations: one file per screen,
//! each a document built from the same model the shell's state uses
//! (../../_shell/src/model.rs). Nothing here reads a clock, a network or a
//! file, so the same declarations always give the same bytes.
//!
//!   index.html              the catalog: every app on its shelf, then the
//!                           base, one card per Settings section
//!   settings/index.html     the base, section by section
//!   m/<module>/index.html   a module's page: what it shows, its paper, and
//!                           what its Lean proves
//!   shell.css               the one stylesheet (./style.rs)
use crate::html::{document, el, Node};
use crate::model::{App, Declared, Kind, Page, Shell};
use crate::style;
use std::collections::BTreeMap;

/// Where a page sits, as the path back to the site's root.
#[derive(Clone, Copy, PartialEq)]
enum Here {
    Home,
    Settings,
    Module,
}

impl Here {
    fn root(self) -> &'static str {
        match self {
            Here::Home => "",
            Here::Settings => "../",
            Here::Module => "../../",
        }
    }
}

fn frame(here: Here, title: &str, body: Vec<Node>) -> String {
    let root = here.root();
    let link = |to: Here, href: String, label: &str| {
        let a = el("a").attr("href", href).text(label);
        if to == here {
            a.attr("aria-current", "page")
        } else {
            a
        }
    };
    let head = el("head")
        .child(el("meta").attr("charset", "utf-8"))
        .child(el("meta").attr("name", "viewport").attr("content", "width=device-width, initial-scale=1"))
        .child(el("meta").attr("name", "color-scheme").attr("content", "dark"))
        .child(el("title").text(title))
        .child(el("link").attr("rel", "stylesheet").attr("href", format!("{root}shell.css")));
    let top = el("header")
        .class("top")
        .child(el("a").class("brand").attr("href", format!("{root}index.html")).text("Kagamizo"))
        .child(
            el("nav")
                .class("top")
                .attr("aria-label", "Sections")
                .child(link(Here::Home, format!("{root}index.html"), "Catalog"))
                .child(link(Here::Settings, format!("{root}settings/index.html"), "Settings")),
        );
    let page = el("html").attr("lang", "en").child(head).child(
        el("body")
            .child(el("a").class("skip").attr("href", "#main").text("Skip to the content"))
            .child(top)
            .child(el("main").attr("id", "main").children(body))
            .child(el("footer").text("Generated from the repository's declarations. Nothing on this page is typed by hand.")),
    );
    document(&page)
}

fn count(n: usize, one: &str, many: &str) -> Node {
    el("span").class("count").text(format!("{n} {}", if n == 1 { one } else { many }))
}

fn card(colour: &str, kind: &str, corner: &str, name: &str, what: &str, href: Option<String>) -> Node {
    let inner = [
        el("span").class("kind").child(el("span").text(kind)).child(el("span").text(corner)),
        el("span").child(el("span").class("name").text(name)),
        el("span").class("what").text(what),
    ];
    let shell = match href {
        Some(h) if h.starts_with("https://") => el("a").attr("href", h).attr("rel", "noopener"),
        Some(h) => el("a").attr("href", h),
        None => el("div"),
    };
    el("li").child(shell.class("card").attr("style", format!("--shelf:{colour}")).children(inner))
}

fn app_card(app: &App) -> Node {
    let (kind, corner, href) = match app.kind {
        Kind::Module => ("page", format!("modules/{}", app.module), Some(format!("m/{}/index.html", app.module))),
        Kind::Builtin => ("base", "settings".to_string(), Some("settings/index.html".to_string())),
        Kind::Web => ("opens", host(app.url.as_deref().unwrap_or("")), app.url.clone()),
        Kind::Native => ("on the device", app.command.clone().unwrap_or_default(), None),
    };
    card(style::shelf_colour(&app.category), kind, &corner, &app.name, &app.description, href)
}

/// A URL's host, for a card's corner.
fn host(url: &str) -> String {
    url.trim_start_matches("https://").split('/').next().unwrap_or("").to_string()
}

fn title_case(s: &str) -> String {
    let mut c = s.chars();
    match c.next() {
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        None => String::new(),
    }
}

fn home(shell: &Shell) -> String {
    let mut body = vec![
        el("h1").text("Everything, on its shelf"),
        el("p").class("lede").text("Every app the repository declares for this screen, then the base it stands on. A card opens the module's own page."),
    ];
    for category in &shell.declared.categories {
        let apps: Vec<&App> = shell.apps.iter().map(|(_, a)| a).filter(|a| &a.category == category).collect();
        if apps.is_empty() {
            continue;
        }
        body.push(el("h2").attr("id", format!("shelf-{category}")).text(title_case(category)).child(count(apps.len(), "app", "apps")));
        body.push(el("ul").class("shelf").attr("aria-labelledby", format!("shelf-{category}")).children(apps.into_iter().map(app_card)));
    }
    body.push(el("h2").attr("id", "shelf-base").text("The base").child(count(shell.declared.sections.len(), "section", "sections")));
    body.push(el("ul").class("shelf").attr("aria-labelledby", "shelf-base").children(shell.declared.sections.iter().map(|s| {
        card(
            style::shelf_colour(&s.key),
            "settings",
            &format!("{} rows", s.rows.len()),
            &s.title,
            &s.rows.iter().take(3).map(|r| r.title.as_str()).collect::<Vec<_>>().join(" · "),
            Some(format!("settings/index.html#{}", s.key)),
        )
    })));
    frame(Here::Home, "Kagamizo", body)
}

fn rows<'a>(entries: impl IntoIterator<Item = (&'a str, &'a str)>) -> Node {
    el("ul").class("rows").children(entries.into_iter().map(|(title, detail)| {
        let li = el("li").child(el("div").class("title").text(title));
        if detail.is_empty() {
            li
        } else {
            li.child(el("div").class("detail").text(detail))
        }
    }))
}

fn settings(declared: &Declared) -> String {
    let mut body = vec![
        el("h1").text("Settings"),
        el("p").class("lede").text("The base: every target, device, account and team, read from the repository."),
    ];
    for s in &declared.sections {
        body.push(el("h2").attr("id", s.key.clone()).text(s.title.clone()).child(count(s.rows.len(), "row", "rows")));
        body.push(el("section").class("panel").attr("aria-labelledby", s.key.clone()).child(if s.rows.is_empty() {
            el("p").class("none").text("Nothing is declared here yet.")
        } else {
            rows(s.rows.iter().map(|r| (r.title.as_str(), r.detail.as_str())))
        }));
    }
    frame(Here::Settings, "Settings · Kagamizo", body)
}

fn chips(class: &str, items: &[String]) -> Node {
    el("ul").class(class).children(items.iter().map(|i| el("li").text(i.clone())))
}

fn module(name: &str, app: Option<&App>, page: &Page) -> String {
    let shown = app.map(|a| a.name.clone()).unwrap_or_else(|| title_case(name));
    let mut main = Vec::new();
    for (i, v) in page.view.iter().enumerate() {
        let id = format!("view-{i}");
        main.push(el("h2").attr("id", id.clone()).text(v.title.clone()).child(count(v.rows.len(), "row", "rows")));
        main.push(el("section").class("panel").attr("aria-labelledby", id).child(rows(v.rows.iter().map(|r| (r.title.as_str(), r.detail.as_str())))));
    }
    if page.view.is_empty() {
        main.push(el("h2").text("What it shows"));
        main.push(el("p").class("none").text("This module generates no rows for its page yet."));
    }
    let mut side = vec![el("h2").text("Paper")];
    if page.title.is_empty() {
        side.push(el("p").class("none").text("None yet: the module's paper is on the backlog."));
    } else {
        side.push(el("section").class("panel").child(rows([(page.title.as_str(), page.summary.as_str())])));
    }
    for (heading, class, items) in [
        ("What its Lean proves", "chips proved", &page.theorems),
        ("Checks", "chips", &page.checks),
        ("Packages", "chips", &page.packages),
        ("Teams", "chips", &page.teams),
    ] {
        if !items.is_empty() {
            side.push(el("h2").text(heading).child(count(items.len(), "", "").attr("aria-hidden", "true")));
            side.push(chips(class, items));
        }
    }
    let body = vec![
        el("p").class("brand").text(format!("modules/{name}")),
        el("h1").text(shown.clone()),
        el("p").class("lede").text(app.map(|a| a.description.clone()).unwrap_or_default()),
        el("div").class("split").child(el("div").children(main)).child(el("aside").attr("aria-label", "Paper and proofs").children(side)),
    ];
    frame(Here::Module, &format!("{shown} · Kagamizo"), body)
}

/// Every file of the site, by its path.
pub fn site(declared: Declared, target: &str) -> BTreeMap<String, String> {
    let shell = Shell::new(declared, target);
    let mut files = BTreeMap::new();
    files.insert("index.html".to_string(), home(&shell));
    files.insert("settings/index.html".to_string(), settings(&shell.declared));
    for (name, page) in &shell.declared.pages {
        let app = shell.apps.iter().map(|(_, a)| a).find(|a| &a.module == name && a.kind == Kind::Module);
        files.insert(format!("m/{name}/index.html"), module(name, app, page));
    }
    files.insert("shell.css".to_string(), style::render());
    files
}

#[cfg(test)]
mod tests {
    use super::*;

    fn declared() -> Declared {
        serde_json::from_str(
            r#"{
              "categories": ["system", "work", "money"],
              "sections": [{"key": "accounts", "title": "Accounts", "rows": [{"title": "proton", "detail": "unlimited"}]},
                           {"key": "devices", "title": "Devices", "rows": []}],
              "apps": {
                "settings": {"name": "Settings", "category": "system", "kind": "builtin", "command": null, "url": null, "targets": ["web"], "module": "shell", "description": "The base"},
                "logistics": {"name": "Logistics", "category": "work", "kind": "module", "command": null, "url": null, "targets": ["web"], "module": "logistics", "description": "From a <spec> to a thing & back"},
                "agents": {"name": "Agents", "category": "work", "kind": "web", "command": null, "url": "https://agents.example.org/", "targets": ["web"], "module": "hetzner", "description": "Chat"},
                "terminal": {"name": "Terminal", "category": "system", "kind": "native", "command": "foot", "url": null, "targets": ["yoga-c940"], "module": "shell", "description": "A shell"}
              },
              "pages": {
                "logistics": {"title": "Reliability before price", "abstract": "A typed path.", "theorems": ["choose_sound"], "checks": ["logistics"], "packages": ["logistics"], "teams": ["upkeep"],
                              "view": [{"title": "No step waits", "rows": [{"title": "fabric", "detail": "within 5 d"}]}]},
                "hetzner": {"title": "", "abstract": "", "checks": [], "packages": [], "teams": []}
              }
            }"#,
        )
        .unwrap()
    }

    /// Every `href` of a page that stays on the site, resolved from its path.
    fn internal_links(path: &str, html: &str) -> Vec<String> {
        let dir: Vec<&str> = path.split('/').rev().skip(1).collect::<Vec<_>>().into_iter().rev().collect();
        html.split("href=\"")
            .skip(1)
            .map(|rest| rest.split('"').next().unwrap())
            .filter(|h| !h.starts_with("https://") && !h.starts_with('#'))
            .map(|h| {
                let mut at = dir.clone();
                for part in h.split('#').next().unwrap().split('/') {
                    match part {
                        ".." => {
                            at.pop();
                        }
                        "" => {}
                        p => at.push(p),
                    }
                }
                at.join("/")
            })
            .collect()
    }

    #[test]
    fn every_screen_is_a_file() {
        let files = site(declared(), "web");
        let paths: Vec<&str> = files.keys().map(String::as_str).collect();
        assert_eq!(paths, ["index.html", "m/hetzner/index.html", "m/logistics/index.html", "settings/index.html", "shell.css"]);
    }

    #[test]
    fn every_internal_link_lands_on_a_generated_file() {
        let files = site(declared(), "web");
        for (path, html) in files.iter().filter(|(p, _)| p.ends_with(".html")) {
            for target in internal_links(path, html) {
                assert!(files.contains_key(&target), "{path} links to {target}, which is not generated");
            }
        }
    }

    #[test]
    fn every_page_has_one_heading_a_language_and_the_stylesheet() {
        let files = site(declared(), "web");
        for (path, html) in files.iter().filter(|(p, _)| p.ends_with(".html")) {
            assert_eq!(html.matches("<h1>").count(), 1, "{path}");
            assert!(html.starts_with("<!doctype html><html lang=\"en\">"), "{path}");
            assert!(html.contains("shell.css\">"), "{path}");
            assert!(html.contains("name=\"viewport\""), "{path}");
        }
    }

    #[test]
    fn the_catalog_shows_this_target_s_apps_only_each_on_its_shelf() {
        let home = &site(declared(), "web")["index.html"];
        assert!(home.contains(">Logistics<") && home.contains(">Agents<") && home.contains(">Settings<"));
        assert!(!home.contains(">Terminal<"), "a native app is not on the web target");
        assert!(home.find("id=\"shelf-system\"").unwrap() < home.find("id=\"shelf-work\"").unwrap());
        assert!(!home.contains("shelf-money"), "an empty shelf is not drawn");
        assert!(home.contains("href=\"https://agents.example.org/\" rel=\"noopener\""));
        assert!(home.contains("href=\"settings/index.html#accounts\""));
    }

    #[test]
    fn a_value_is_never_read_as_markup() {
        let home = &site(declared(), "web")["index.html"];
        assert!(home.contains("From a &lt;spec&gt; to a thing &amp; back"));
        assert!(!home.contains("<spec>"));
    }

    #[test]
    fn a_module_s_page_shows_its_rows_its_paper_and_what_is_proved() {
        let files = site(declared(), "web");
        let page = &files["m/logistics/index.html"];
        for wanted in ["No step waits", "within 5 d", "Reliability before price", "choose_sound", "chips proved", "modules/logistics"] {
            assert!(page.contains(wanted), "{wanted}");
        }
        let bare = &files["m/hetzner/index.html"];
        assert!(bare.contains("None yet: the module&#39;s paper is on the backlog."));
        assert!(bare.contains("generates no rows"));
    }

    #[test]
    fn the_same_declarations_give_the_same_bytes() {
        assert_eq!(site(declared(), "web"), site(declared(), "web"));
    }
}
