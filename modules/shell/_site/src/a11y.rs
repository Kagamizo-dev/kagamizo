//! Accessibility, checked on every page before it is written: a page that
//! breaks a rule here fails the build, so none is served. The rules are the
//! ones a document's structure and the palette can decide by themselves
//! (WCAG 2.2: 1.3.1 info and relationships, 1.4.3 contrast, 1.4.4 resize,
//! 2.4.1 bypass blocks, 2.4.2 page titled, 2.4.4 link purpose, 2.4.6
//! headings, 3.1.1 language, 4.1.2 name and role). What needs a person or a
//! browser (reading order by eye, focus order under a real keyboard, a
//! screen reader's speech) is not claimed here.
use crate::html::Node;
use crate::style::{self, Pair};
use std::collections::BTreeSet;

fn name(n: &Node) -> &'static str {
    match n {
        Node::Element { name, .. } => name,
        Node::Text(_) => "",
    }
}

fn attr<'a>(n: &'a Node, key: &str) -> Option<&'a str> {
    match n {
        Node::Element { attrs, .. } => attrs.iter().find(|(k, _)| *k == key).map(|(_, v)| v.as_str()),
        Node::Text(_) => None,
    }
}

fn kids(n: &Node) -> &[Node] {
    match n {
        Node::Element { children, .. } => children,
        Node::Text(_) => &[],
    }
}

/// Every element of the document, in reading order.
pub fn elements(root: &Node) -> Vec<&Node> {
    let mut out = Vec::new();
    let mut stack = vec![root];
    while let Some(n) = stack.pop() {
        if matches!(n, Node::Element { .. }) {
            out.push(n);
        }
        for c in kids(n).iter().rev() {
            stack.push(c);
        }
    }
    out
}

/// What a screen reader would speak for an element: its text, without the
/// parts hidden from it.
pub fn spoken(n: &Node) -> String {
    match n {
        Node::Text(s) => s.clone(),
        Node::Element { .. } if attr(n, "aria-hidden") == Some("true") => String::new(),
        Node::Element { children, .. } => children.iter().map(spoken).collect::<Vec<_>>().join(" ").split_whitespace().collect::<Vec<_>>().join(" "),
    }
}

fn heading_level(n: &Node) -> Option<u8> {
    match name(n) {
        "h1" => Some(1),
        "h2" => Some(2),
        "h3" => Some(3),
        "h4" => Some(4),
        _ => None,
    }
}

/// Every rule a page breaks; empty when it breaks none.
pub fn problems(root: &Node) -> Vec<String> {
    let all = elements(root);
    let mut out = Vec::new();
    let count = |tag: &str| all.iter().filter(|n| name(n) == tag).count();

    if name(root) != "html" || attr(root, "lang").is_none_or(str::is_empty) {
        out.push("the document names no language".into());
    }
    match all.iter().find(|n| name(n) == "title") {
        Some(t) if !spoken(t).is_empty() => {}
        _ => out.push("the page has no title".into()),
    }
    match all.iter().find(|n| name(n) == "meta" && attr(n, "name") == Some("viewport")) {
        None => out.push("no viewport is declared".into()),
        Some(v) => {
            let c = attr(v, "content").unwrap_or("");
            if c.contains("user-scalable=no") || c.contains("maximum-scale") {
                out.push("the viewport forbids zooming".into());
            }
        }
    }
    if count("h1") != 1 {
        out.push(format!("{} top headings, where a page has one", count("h1")));
    }
    if count("main") != 1 {
        out.push(format!("{} main landmarks, where a page has one", count("main")));
    }

    // Headings: none empty, and no level skipped on the way down.
    let mut last = 0u8;
    for n in &all {
        if let Some(level) = heading_level(n) {
            if spoken(n).is_empty() {
                out.push(format!("an empty h{level}"));
            }
            if level > last + 1 {
                out.push(format!("h{level} \"{}\" follows h{last}, skipping a level", spoken(n)));
            }
            last = level;
        }
    }

    // Ids are unique, and everything that points at one finds it.
    let mut ids = BTreeSet::new();
    for n in &all {
        if let Some(id) = attr(n, "id") {
            if !ids.insert(id) {
                out.push(format!("the id \"{id}\" is used twice"));
            }
        }
    }
    for n in &all {
        if let Some(target) = attr(n, "aria-labelledby") {
            if !ids.contains(target) {
                out.push(format!("aria-labelledby names \"{target}\", which is not on the page"));
            }
        }
        if let Some(fragment) = attr(n, "href").and_then(|h| h.strip_prefix('#')) {
            if !ids.contains(fragment) {
                out.push(format!("a link goes to #{fragment}, which is not on the page"));
            }
        }
    }

    // The first link skips to the content.
    match all.iter().find(|n| name(n) == "a") {
        Some(a) if attr(a, "href") == Some("#main") => {}
        _ => out.push("the first link does not skip to the content".into()),
    }

    for n in &all {
        match name(n) {
            "a" => {
                if attr(n, "href").is_none_or(str::is_empty) {
                    out.push(format!("a link \"{}\" goes nowhere", spoken(n)));
                }
                if spoken(n).is_empty() && attr(n, "aria-label").is_none_or(str::is_empty) {
                    out.push(format!("a link to {} has no name", attr(n, "href").unwrap_or("?")));
                }
            }
            "nav" | "section" | "aside" => {
                if attr(n, "aria-label").is_none() && attr(n, "aria-labelledby").is_none() {
                    out.push(format!("a {} has no name", name(n)));
                }
            }
            "ul" | "ol" => {
                if kids(n).iter().any(|c| name(c) != "li") {
                    out.push("a list holds something that is not an item".into());
                }
            }
            "img" => {
                if attr(n, "alt").is_none() {
                    out.push("an image has no alternative text".into());
                }
            }
            _ => {}
        }
        if attr(n, "tabindex").is_some_and(|t| t.parse::<i32>().is_ok_and(|v| v > 0)) {
            out.push("a positive tabindex reorders the keyboard".into());
        }
        if matches!(attr(n, "role"), Some("button" | "link")) && !matches!(name(n), "a" | "button") {
            out.push(format!("a {} plays a control: use the element itself", name(n)));
        }
    }
    out
}

fn channel(hex: &str, at: usize) -> f64 {
    u8::from_str_radix(&hex[at..at + 2], 16).expect("a colour is #rrggbb") as f64 / 255.0
}

fn rgb(hex: &str) -> [f64; 3] {
    [channel(hex, 1), channel(hex, 3), channel(hex, 5)]
}

fn luminance(c: [f64; 3]) -> f64 {
    let lin = |v: f64| if v <= 0.04045 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) };
    0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])
}

/// WCAG's contrast ratio of a text colour, at its opacity, on its ground.
pub fn contrast(pair: &Pair) -> f64 {
    let (fg, bg) = (rgb(pair.text), rgb(pair.on));
    let seen = [0, 1, 2].map(|i| fg[i] * pair.opacity + bg[i] * (1.0 - pair.opacity));
    let (a, b) = (luminance(seen), luminance(bg));
    (a.max(b) + 0.05) / (a.min(b) + 0.05)
}

/// The palette's pairs that fall short of AA: 4.5 to 1 for text.
pub fn low_contrast() -> Vec<String> {
    style::pairs().iter().filter(|p| contrast(p) < 4.5).map(|p| format!("{}: {:.2} to 1, under 4.5", p.what, contrast(p))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::html::el;

    fn page(body: Vec<Node>) -> Node {
        el("html").attr("lang", "en").child(el("head").child(el("title").text("T")).child(el("meta").attr("name", "viewport").attr("content", "width=device-width, initial-scale=1"))).child(
            el("body").child(el("a").attr("href", "#main").text("Skip")).child(el("main").attr("id", "main").child(el("h1").text("One")).children(body)),
        )
    }

    #[test]
    fn a_sound_page_breaks_no_rule() {
        assert_eq!(problems(&page(vec![el("h2").text("Two")])), Vec::<String>::new());
    }

    #[test]
    fn each_rule_catches_its_fault() {
        let caught = |body: Vec<Node>, part: &str| {
            let found = problems(&page(body));
            assert!(found.iter().any(|p| p.contains(part)), "{part}: {found:?}");
        };
        caught(vec![el("h3").text("Deep")], "skipping a level");
        caught(vec![el("h1").text("Again")], "2 top headings");
        caught(vec![el("a").attr("href", "x")], "has no name");
        caught(vec![el("a").text("Nowhere")], "goes nowhere");
        caught(vec![el("a").attr("href", "#gone").text("x")], "#gone");
        caught(vec![el("p").attr("id", "main")], "used twice");
        caught(vec![el("section")], "a section has no name");
        caught(vec![el("section").attr("aria-labelledby", "missing")], "not on the page");
        caught(vec![el("ul").child(el("p"))], "not an item");
        caught(vec![el("img")], "no alternative text");
        caught(vec![el("div").attr("role", "button")], "plays a control");
        caught(vec![el("p").attr("tabindex", "3")], "tabindex");
        caught(vec![el("h2")], "an empty h2");
    }

    #[test]
    fn a_page_without_language_title_or_skip_link_is_caught() {
        let bare = el("html").child(el("body").child(el("main").child(el("h1").text("x"))));
        let found = problems(&bare).join("; ");
        for part in ["names no language", "no title", "no viewport", "does not skip"] {
            assert!(found.contains(part), "{part}: {found}");
        }
    }

    #[test]
    fn hidden_text_is_not_spoken() {
        let n = el("p").text("Shown").child(el("span").attr("aria-hidden", "true").text("Hidden"));
        assert_eq!(spoken(&n), "Shown");
    }

    #[test]
    fn contrast_is_wcag_s() {
        let p = |text, on, opacity| Pair { what: "", text, on, opacity };
        assert!((contrast(&p("#000000", "#ffffff", 1.0)) - 21.0).abs() < 0.01);
        assert!((contrast(&p("#ffffff", "#ffffff", 1.0)) - 1.0).abs() < 0.01);
        assert!((contrast(&p("#767676", "#ffffff", 1.0)) - 4.54).abs() < 0.01);
        // Half-transparent black on white is mid grey.
        assert!(contrast(&p("#000000", "#ffffff", 0.5)) < 5.4);
    }

    #[test]
    fn every_text_colour_of_the_palette_meets_aa_on_its_ground() {
        assert_eq!(low_contrast(), Vec::<String>::new());
    }
}
