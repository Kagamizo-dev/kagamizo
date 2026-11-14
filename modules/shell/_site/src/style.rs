//! The site's one stylesheet, as values: the tokens are named here once, a
//! rule is a selector with its declarations, and the sheet is rendered from
//! them at build time. Nothing is styled outside this file.

/// A colour of the palette (the design canvas's, checked there for contrast
/// on the ground).
pub struct Palette;
impl Palette {
    pub const GROUND: &'static str = "#16142a";
    pub const PANEL: &'static str = "#221f40";
    pub const CARD: &'static str = "#2b2752";
    pub const LINE: &'static str = "#6a63a8";
    pub const INK: &'static str = "#f4ecd8";
    pub const MUTED: &'static str = "#c9c0e6";
    pub const ACCENT: &'static str = "#f0b44c";
    pub const GOOD: &'static str = "#9be3bd";
    pub const SHADOW: &'static str = "#000000";
}

/// A shelf's colour, by its category: the card kinds of the canvas.
pub fn shelf_colour(category: &str) -> &'static str {
    match category {
        "system" | "identity" | "governance" => "#3b2f6b",
        "work" | "build" => "#1f4d3c",
        "money" | "accounts" => "#5a3d10",
        "research" | "infrastructure" | "repository" => "#1e3d5c",
        "chat" | "media" | "play" => "#4d1f3c",
        _ => "#3a3a3a",
    }
}

pub struct Rule {
    pub selector: &'static str,
    pub declarations: Vec<(&'static str, String)>,
}

fn rule(selector: &'static str, declarations: &[(&'static str, &str)]) -> Rule {
    Rule { selector, declarations: declarations.iter().map(|(k, v)| (*k, v.to_string())).collect() }
}

/// The sans and the mono the system already has: no font is fetched.
const SANS: &str = "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif";
const MONO: &str = "ui-monospace, 'SF Mono', Menlo, Consolas, monospace";

/// Rules for every width, then the ones a wide screen adds.
pub fn sheet() -> (Vec<Rule>, Vec<Rule>) {
    let base = vec![
        rule("*", &[("box-sizing", "border-box")]),
        rule(
            "html",
            &[("background", Palette::GROUND), ("color", Palette::INK), ("font-family", SANS), ("font-size", "16px"), ("line-height", "1.45"), ("-webkit-text-size-adjust", "100%")],
        ),
        rule("body", &[("margin", "0"), ("padding", "20px 16px 64px")]),
        rule("main, header.top", &[("max-width", "1280px"), ("margin", "0 auto")]),
        rule("a", &[("color", "inherit"), ("text-decoration", "none")]),
        rule("a:focus-visible, summary:focus-visible", &[("outline", &format!("3px solid {}", Palette::ACCENT)), ("outline-offset", "3px")]),
        rule(".skip", &[("position", "absolute"), ("left", "-999px")]),
        rule(".skip:focus", &[("left", "16px"), ("top", "12px"), ("background", Palette::ACCENT), ("color", Palette::GROUND), ("padding", "8px 12px")]),
        rule("header.top", &[("display", "flex"), ("flex-wrap", "wrap"), ("align-items", "baseline"), ("gap", "8px 20px"), ("padding-bottom", "20px")]),
        rule(".brand", &[("font-family", MONO), ("font-size", "13px"), ("letter-spacing", "2px"), ("color", Palette::ACCENT), ("text-transform", "uppercase")]),
        rule("nav.top", &[("display", "flex"), ("flex-wrap", "wrap"), ("gap", "4px 16px"), ("font-family", MONO), ("font-size", "13px")]),
        rule("nav.top a", &[("color", Palette::MUTED), ("padding", "10px 0"), ("min-height", "44px"), ("display", "inline-flex"), ("align-items", "center")]),
        rule("nav.top a[aria-current]", &[("color", Palette::INK), ("border-bottom", &format!("2px solid {}", Palette::ACCENT))]),
        rule("h1", &[("font-size", "30px"), ("line-height", "1.15"), ("margin", "0 0 8px")]),
        rule("h2", &[("font-family", MONO), ("font-size", "13px"), ("letter-spacing", "1.5px"), ("text-transform", "uppercase"), ("color", Palette::ACCENT), ("margin", "32px 0 12px")]),
        rule(".lede", &[("color", Palette::MUTED), ("max-width", "70ch"), ("margin", "0")]),
        rule(".count", &[("font-family", MONO), ("font-size", "12px"), ("color", Palette::MUTED), ("margin-left", "8px")]),
        // A shelf scrolls sideways on a phone and wraps into a grid when wide.
        rule(".shelf", &[("display", "grid"), ("grid-auto-flow", "column"), ("grid-auto-columns", "minmax(240px, 78%)"), ("gap", "16px"), ("overflow-x", "auto"), ("padding", "4px 4px 14px"), ("margin", "0 -4px"), ("scroll-snap-type", "x proximity"), ("list-style", "none")]),
        rule(".shelf > li", &[("scroll-snap-align", "start"), ("display", "flex")]),
        rule(
            ".card",
            &[("display", "flex"), ("flex-direction", "column"), ("justify-content", "space-between"), ("gap", "14px"), ("width", "100%"), ("aspect-ratio", "1.586"), ("padding", "14px 16px"), ("border", &format!("3px solid {}", Palette::SHADOW)), ("box-shadow", &format!("5px 5px 0 {}", Palette::SHADOW)), ("background", "var(--shelf, #3a3a3a)")],
        ),
        rule("a.card:hover", &[("transform", "translate(-1px, -1px)"), ("box-shadow", &format!("7px 7px 0 {}", Palette::SHADOW))]),
        rule(".card .kind", &[("display", "flex"), ("justify-content", "space-between"), ("gap", "8px"), ("font-family", MONO), ("font-size", "11px"), ("text-transform", "uppercase"), ("letter-spacing", "1px"), ("color", Palette::INK), ("opacity", "0.85")]),
        rule(".card .name", &[("font-size", "20px"), ("font-weight", "700"), ("line-height", "1.15")]),
        rule(".card .what", &[("font-size", "13px"), ("color", Palette::INK), ("opacity", "0.9"), ("display", "-webkit-box"), ("-webkit-line-clamp", "3"), ("-webkit-box-orient", "vertical"), ("overflow", "hidden")]),
        rule(".panel", &[("background", Palette::PANEL), ("border", &format!("3px solid {}", Palette::SHADOW)), ("box-shadow", &format!("6px 6px 0 {}", Palette::SHADOW)), ("padding", "4px 16px"), ("margin", "0")]),
        rule(".rows", &[("margin", "0"), ("padding", "0"), ("list-style", "none")]),
        rule(".rows > li", &[("padding", "12px 0"), ("border-top", &format!("1px solid {}", Palette::CARD))]),
        rule(".rows > li:first-child", &[("border-top", "0")]),
        rule(".rows .title", &[("font-weight", "600"), ("overflow-wrap", "anywhere")]),
        rule(".rows .detail", &[("color", Palette::MUTED), ("font-size", "14px"), ("overflow-wrap", "anywhere")]),
        rule(".chips", &[("display", "flex"), ("flex-wrap", "wrap"), ("gap", "8px"), ("margin", "0"), ("padding", "0"), ("list-style", "none")]),
        rule(".chips > li", &[("font-family", MONO), ("font-size", "12.5px"), ("padding", "6px 10px"), ("background", Palette::CARD), ("border", &format!("1px solid {}", Palette::LINE)), ("overflow-wrap", "anywhere")]),
        rule(".chips.proved > li", &[("border-color", Palette::GOOD), ("color", Palette::GOOD)]),
        rule(".none", &[("color", Palette::MUTED), ("font-style", "italic")]),
        rule("footer", &[("max-width", "1280px"), ("margin", "48px auto 0"), ("font-family", MONO), ("font-size", "12px"), ("color", Palette::MUTED)]),
    ];
    let wide = vec![
        rule("body", &[("padding", "32px 32px 80px")]),
        rule("h1", &[("font-size", "40px")]),
        rule(".shelf", &[("grid-auto-flow", "row"), ("grid-template-columns", "repeat(auto-fill, minmax(240px, 1fr))"), ("overflow-x", "visible")]),
        rule(".split", &[("display", "grid"), ("grid-template-columns", "minmax(0, 2fr) minmax(0, 1fr)"), ("gap", "32px"), ("align-items", "start")]),
    ];
    (base, wide)
}

fn block(rules: &[Rule], out: &mut String) {
    for r in rules {
        out.push_str(r.selector);
        out.push('{');
        for (i, (k, v)) in r.declarations.iter().enumerate() {
            if i > 0 {
                out.push(';');
            }
            out.push_str(k);
            out.push(':');
            out.push_str(v);
        }
        out.push('}');
    }
}

/// The width from which the wide rules apply.
pub const WIDE_FROM_PX: u32 = 760;

pub fn render() -> String {
    let (base, wide) = sheet();
    let mut out = String::new();
    block(&base, &mut out);
    out.push_str(&format!("@media (min-width:{WIDE_FROM_PX}px){{"));
    block(&wide, &mut out);
    out.push('}');
    out.push_str("@media (prefers-reduced-motion:reduce){a.card:hover{transform:none}}");
    out.push('\n');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_rule_declares_something_and_no_value_can_close_the_sheet() {
        let (base, wide) = sheet();
        for r in base.iter().chain(&wide) {
            assert!(!r.declarations.is_empty(), "{}", r.selector);
            for (k, v) in &r.declarations {
                assert!(!v.contains('}') && !v.contains(';') && !v.contains('<'), "{}: {k}", r.selector);
            }
        }
    }

    #[test]
    fn touch_targets_in_the_navigation_are_tall_enough() {
        let (base, _) = sheet();
        let nav = base.iter().find(|r| r.selector == "nav.top a").unwrap();
        assert!(nav.declarations.iter().any(|(k, v)| *k == "min-height" && v == "44px"));
    }
}
