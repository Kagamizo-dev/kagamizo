//! shell-e2e: every page of the site (../_site), used in a real browser the
//! way a person uses it, at a phone's, a tablet's and a desktop's width.
//! What ../_site/src/a11y.rs decides from a document's structure is decided
//! there; this is what only a browser can say.
//!
//!   shell-e2e SITE_DIR OUT_DIR [SERVER]
//!
//! With SERVER (chat-check-server, ../../agents/_chat) the site is served
//! over HTTP with the chat pages beside it, and those are checked too.
//!
//! On every page, at every width:
//!   * nothing scrolls sideways;
//!   * every link, box and button is a target at least 44 by 44 CSS pixels
//!     (the skip link is measured when it shows, on focus);
//!   * the browser's own accessibility tree has one main landmark, a name on
//!     every link, heading, box and button, and as many links as the
//!     document has.
//! With the keyboard alone, at the phone's and the desktop's width:
//!   * the first Tab shows the skip link, and Enter on it goes to the content;
//!   * Tab reaches every link, box and button, in the document's order,
//!     each one scrolled into view with a focus ring a person can see.
//! With the pointer, at the desktop's width:
//!   * every kind of link on the page is clicked (each navigation link, the
//!     first card, the first module of the index) and lands on a page of the
//!     site with one top heading.
//! In a room, with the keyboard, at the phone's and the desktop's width:
//!   * a message typed in the box and sent with Enter on the button is the
//!     latest thing said when the page comes back, and the page is at it.
//! A sample of pages is photographed at each width into OUT_DIR.
//!
//! The browser is the pinned Chromium (E2E_CHROMIUM); E2E_NO_SANDBOX is set
//! where it runs inside a build sandbox already.
use anyhow::{bail, Context, Result};
use chromiumoxide::browser::{Browser, BrowserConfig};
use chromiumoxide::cdp::browser_protocol::emulation::SetDeviceMetricsOverrideParams;
use chromiumoxide::cdp::browser_protocol::input::{DispatchKeyEventParams, DispatchKeyEventType};
use chromiumoxide::cdp::browser_protocol::page::CaptureScreenshotFormat;
use chromiumoxide::page::{Page, ScreenshotParams};
use futures::StreamExt;
use serde::Deserialize;
use std::path::{Path, PathBuf};

/// The smallest side of a target, in CSS pixels.
const TARGET: f64 = 44.0;
/// The thinnest focus ring that counts as seen.
const RING: f64 = 2.0;

const WIDTHS: [(&str, u32, u32); 3] = [("phone", 390, 844), ("tablet", 768, 1024), ("desktop", 1280, 800)];

/// The pages photographed at every width.
const PHOTOGRAPHED: [&str; 4] = ["index.html", "wallet/index.html", "settings/index.html", "m/logistics/index.html"];

/// What the page says of itself, measured in the browser.
const MEASURE: &str = r#"(() => {
  const links = [...document.querySelectorAll('a, button, textarea, input, select')].map(a => {
    const r = a.getBoundingClientRect();
    return { tag: a.tagName.toLowerCase(), text: (a.innerText || a.getAttribute('name') || '').trim().replace(/\s+/g, ' ').slice(0, 60), href: a.getAttribute('href') || '', skip: a.classList.contains('skip'), w: r.width, h: r.height };
  });
  const el = document.documentElement;
  return JSON.stringify({ sideways: el.scrollWidth > el.clientWidth, headings: document.querySelectorAll('h1').length, links });
})()"#;

/// The element the keyboard is on: which link it is, whether it is in view,
/// and the ring drawn around it.
const FOCUSED: &str = r#"(() => {
  const a = document.activeElement;
  const all = [...document.querySelectorAll('a, button, textarea, input, select')];
  const r = a.getBoundingClientRect();
  const s = getComputedStyle(a);
  return JSON.stringify({
    index: all.indexOf(a),
    inView: r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth && r.width > 0 && r.height > 0,
    ring: s.outlineStyle === 'none' ? 0 : parseFloat(s.outlineWidth) || 0,
    w: r.width, h: r.height, hash: location.hash, tag: a.tagName.toLowerCase()
  });
})()"#;

#[derive(Deserialize)]
struct Link {
    tag: String,
    text: String,
    href: String,
    skip: bool,
    w: f64,
    h: f64,
}

#[derive(Deserialize)]
struct Measured {
    sideways: bool,
    headings: usize,
    links: Vec<Link>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Focused {
    index: i64,
    in_view: bool,
    ring: f64,
    w: f64,
    h: f64,
    hash: String,
    tag: String,
}

async fn eval<T: for<'de> Deserialize<'de>>(page: &Page, script: &str) -> Result<T> {
    let text: String = page.evaluate(script).await?.into_value()?;
    Ok(serde_json::from_str(&text)?)
}

async fn key(page: &Page, name: &str, code: i64) -> Result<()> {
    for kind in [DispatchKeyEventType::RawKeyDown, DispatchKeyEventType::KeyUp] {
        let event = DispatchKeyEventParams::builder().r#type(kind).key(name).code(name).windows_virtual_key_code(code).native_virtual_key_code(code).build().map_err(anyhow::Error::msg)?;
        page.execute(event).await?;
    }
    Ok(())
}

async fn open(page: &Page, url: &str, width: u32, height: u32) -> Result<()> {
    let metrics = SetDeviceMetricsOverrideParams::builder().width(width).height(height).device_scale_factor(1.0).mobile(width < 700).build().map_err(anyhow::Error::msg)?;
    page.execute(metrics).await?;
    page.goto(url).await?;
    Ok(())
}

/// `Accessibility.getFullAXTree`, read loosely: the pinned protocol types
/// refuse the reasons a newer browser gives for ignoring a node, and only
/// each node's role and name are wanted here.
#[derive(serde::Serialize)]
struct FullTree {}

impl chromiumoxide::Method for FullTree {
    fn identifier(&self) -> chromiumoxide::types::MethodId {
        "Accessibility.getFullAXTree".into()
    }
}

impl chromiumoxide::Command for FullTree {
    type Response = serde_json::Value;
}

/// The page as the browser's accessibility tree gives it.
async fn tree(page: &Page, links: usize, at: &str, found: &mut Vec<String>) -> Result<()> {
    let got = page.execute(FullTree {}).await?.result;
    let nodes = got["nodes"].as_array().context("no accessibility tree")?;
    let text = |n: &serde_json::Value, field: &str| n[field]["value"].as_str().unwrap_or_default().to_owned();
    let mut seen = (0usize, 0usize);
    for n in nodes.iter().filter(|n| n["ignored"] != true) {
        let (role, name) = (text(n, "role"), text(n, "name"));
        match role.as_str() {
            "main" => seen.0 += 1,
            "link" => {
                seen.1 += 1;
                if name.trim().is_empty() {
                    found.push(format!("{at}: the browser gives a link no name"));
                }
            }
            "heading" | "textbox" | "button" if name.trim().is_empty() => found.push(format!("{at}: the browser gives a {role} no name")),
            _ => {}
        }
    }
    if seen.0 != 1 {
        found.push(format!("{at}: {} main landmarks in the accessibility tree", seen.0));
    }
    if seen.1 != links {
        found.push(format!("{at}: {} links in the accessibility tree, {links} in the document", seen.1));
    }
    Ok(())
}

/// The page with the keyboard alone.
async fn keyboard(page: &Page, links: usize, at: &str, found: &mut Vec<String>) -> Result<()> {
    for i in 0..links {
        key(page, "Tab", 9).await?;
        let f: Focused = eval(page, FOCUSED).await?;
        if f.index != i as i64 {
            found.push(format!("{at}: Tab {} lands on link {}, out of the document's order", i + 1, f.index + 1));
            return Ok(());
        }
        if !f.in_view {
            found.push(format!("{at}: link {} takes the focus out of view", i + 1));
        }
        if f.ring < RING {
            found.push(format!("{at}: link {} shows no focus ring", i + 1));
        }
        if i == 0 && (f.w < TARGET || f.h < TARGET) {
            found.push(format!("{at}: the skip link shows as {:.0} by {:.0}, under {TARGET:.0}", f.w, f.h));
        }
    }
    Ok(())
}

/// The skip link, by the keyboard: shown on the first Tab, and Enter goes
/// to the content.
async fn skip(page: &Page, at: &str, found: &mut Vec<String>) -> Result<()> {
    key(page, "Tab", 9).await?;
    key(page, "Enter", 13).await?;
    tokio::time::sleep(std::time::Duration::from_millis(60)).await;
    let f: Focused = eval(page, FOCUSED).await?;
    if f.hash != "#main" {
        found.push(format!("{at}: Enter on the skip link goes to \"{}\", not to the content", f.hash));
    }
    Ok(())
}

/// The links a person would click on this page, one of each kind: every
/// navigation link, the first card and the first module of the index.
const CLICKABLE: &str = r#"(() => {
  const all = [...document.querySelectorAll('a')];
  const pick = [...document.querySelectorAll('header a, nav.top a'), document.querySelector('a.card'), document.querySelector('.index a')];
  return JSON.stringify(pick.filter(a => a && !(a.getAttribute('href') || '').startsWith('https://')).map(a => all.indexOf(a)));
})()"#;

/// Where a click landed, once the page it opened answers.
async fn settled(page: &Page) -> Result<(String, Measured)> {
    let mut last = None;
    for _ in 0..50 {
        tokio::time::sleep(std::time::Duration::from_millis(40)).await;
        match eval::<Measured>(page, MEASURE).await {
            Ok(m) => {
                let landed: String = page.evaluate("location.href").await?.into_value()?;
                return Ok((landed, m));
            }
            Err(e) => last = Some(e),
        }
    }
    Err(last.unwrap_or_else(|| anyhow::anyhow!("the page never answered")))
}

async fn clicks(page: &Page, url: &str, site: &str, at: &str, found: &mut Vec<String>) -> Result<()> {
    let which: Vec<usize> = eval(page, CLICKABLE).await?;
    for index in which {
        page.goto(url).await?;
        let links = page.find_elements("a").await?;
        let Some(link) = links.get(index) else { continue };
        let href = link.attribute("href").await?.unwrap_or_default();
        link.scroll_into_view().await?;
        link.click().await?;
        let (landed, m) = settled(page).await?;
        if !landed.starts_with(site) {
            found.push(format!("{at}: clicking \"{href}\" leaves the site for {landed}"));
        } else if m.headings != 1 {
            found.push(format!("{at}: clicking \"{href}\" lands on a page with {} top headings", m.headings));
        }
    }
    Ok(())
}

/// A room, with the keyboard: type in the box, Tab to the button, Enter.
async fn talk(page: &Page, at: &str, found: &mut Vec<String>) -> Result<()> {
    let said = format!("Said by the check, {at}");
    let Ok(area) = page.find_element("form.say textarea").await else {
        return Ok(());
    };
    area.click().await?;
    area.type_str(&said).await?;
    key(page, "Tab", 9).await?;
    let f: Focused = eval(page, FOCUSED).await?;
    if f.tag != "button" {
        found.push(format!("{at}: Tab from the message box lands on a {}, not on Send", f.tag));
        return Ok(());
    }
    page.find_element("form.say button").await?.press_key("Enter").await?;
    let mut latest = String::new();
    let mut hash = String::new();
    for _ in 0..50 {
        tokio::time::sleep(std::time::Duration::from_millis(40)).await;
        if let Ok((l, h)) = eval::<(String, String)>(page, "JSON.stringify([document.querySelector('#latest p')?.innerText || '', location.hash])").await {
            (latest, hash) = (l, h);
            if latest == said {
                break;
            }
        }
    }
    if latest != said {
        found.push(format!("{at}: what was sent is not the latest thing said (it reads \"{latest}\")"));
    } else if hash != "#latest" {
        found.push(format!("{at}: after sending, the page is at \"{hash}\", not at the latest message"));
    }
    Ok(())
}

fn pages(dir: &Path, under: &Path, out: &mut Vec<String>) -> Result<()> {
    let mut entries: Vec<PathBuf> = std::fs::read_dir(dir)?.map(|e| e.map(|e| e.path())).collect::<std::io::Result<_>>()?;
    entries.sort();
    for path in entries {
        if path.is_dir() {
            pages(&path, under, out)?;
        } else if path.extension().is_some_and(|e| e == "html") {
            out.push(path.strip_prefix(under)?.to_string_lossy().into_owned());
        }
    }
    Ok(())
}

/// The port the check's own server listens on.
const PORT: u16 = 8791;

async fn run(site: &Path, out: &Path, server: Option<&str>) -> Result<(usize, Vec<String>)> {
    let site = site.canonicalize().context("SITE_DIR")?;
    let mut serving = None;
    let root = match server {
        None => format!("file://{}", site.display()),
        Some(binary) => {
            serving = Some(tokio::process::Command::new(binary).arg(&site).arg(PORT.to_string()).kill_on_drop(true).spawn().with_context(|| binary.to_owned())?);
            format!("http://127.0.0.1:{PORT}/next")
        }
    };
    std::fs::create_dir_all(out)?;
    let mut all = Vec::new();
    pages(&site, &site, &mut all)?;
    if all.is_empty() {
        bail!("no page under {}", site.display());
    }
    if serving.is_some() {
        // The chat's pages: the teams, and the first team's room (found on
        // the teams page once the browser is up, below).
        all.push("chat/".into());
    }
    let chromium = std::env::var("E2E_CHROMIUM").context("E2E_CHROMIUM: the browser to drive")?;
    let mut config = BrowserConfig::builder().chrome_executable(chromium).arg("--headless=new").arg("--disable-component-update").arg("--hide-scrollbars");
    if std::env::var_os("E2E_NO_SANDBOX").is_some() {
        config = config.no_sandbox();
    }
    let (mut browser, mut handler) = Browser::launch(config.build().map_err(anyhow::Error::msg)?).await?;
    let events = tokio::spawn(async move { while handler.next().await.is_some() {} });
    let page = browser.new_page("about:blank").await?;
    let mut found = Vec::new();
    if serving.is_some() {
        for _ in 0..100 {
            if page.goto(format!("{root}/chat/")).await.is_ok() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }
        let first: String = page.evaluate("document.querySelector('.index a')?.getAttribute('href') || ''").await?.into_value()?;
        if first.is_empty() {
            bail!("the chat's teams page lists no room");
        }
        all.push(format!("chat/{first}"));
    }
    for path in &all {
        let url = format!("{root}/{path}");
        for (name, width, height) in WIDTHS {
            let at = format!("{path} at {name} width");
            open(&page, &url, width, height).await?;
            let m: Measured = eval(&page, MEASURE).await?;
            if m.sideways {
                found.push(format!("{at}: the page scrolls sideways"));
            }
            for l in m.links.iter().filter(|l| !l.skip) {
                if l.w < TARGET || l.h < TARGET {
                    found.push(format!("{at}: the {} \"{}\" ({}) is {:.0} by {:.0}, under {TARGET:.0}", l.tag, l.text, l.href, l.w, l.h));
                }
            }
            tree(&page, m.links.iter().filter(|l| l.tag == "a").count(), &at, &mut found).await.context("tree")?;
            if PHOTOGRAPHED.contains(&path.as_str()) || path.starts_with("chat/") {
                let shot = ScreenshotParams::builder().format(CaptureScreenshotFormat::Png).full_page(true).build();
                page.save_screenshot(shot, out.join(format!("{}-{name}.png", path.trim_end_matches("/index.html").trim_end_matches(".html").trim_end_matches('/').replace('/', "-")))).await?;
            }
            if name != "tablet" {
                keyboard(&page, m.links.len(), &at, &mut found).await.context("keyboard")?;
                open(&page, &url, width, height).await?;
                skip(&page, &at, &mut found).await.context("skip")?;
                open(&page, &url, width, height).await?;
                talk(&page, &at, &mut found).await.context("talk")?;
            }
            if name == "desktop" {
                clicks(&page, &url, &root, &at, &mut found).await.context("clicks")?;
            }
        }
    }
    browser.close().await.ok();
    events.abort();
    drop(serving);
    Ok((all.len(), found))
}

#[tokio::main]
async fn main() -> std::process::ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (site, out, server) = match args.as_slice() {
        [site, out] => (site, out, None),
        [site, out, server] => (site, out, Some(server.as_str())),
        _ => {
            eprintln!("usage: shell-e2e SITE_DIR OUT_DIR [SERVER]");
            return std::process::ExitCode::from(2);
        }
    };
    match run(Path::new(site), Path::new(out), server).await {
        Ok((pages, found)) if found.is_empty() => {
            println!("shell-e2e: {pages} pages at {} widths, by pointer and by keyboard: nothing found", WIDTHS.len());
            std::process::ExitCode::SUCCESS
        }
        Ok((pages, found)) => {
            eprintln!("shell-e2e: {} problem(s) on {pages} pages:", found.len());
            for f in &found {
                eprintln!("  {f}");
            }
            std::process::ExitCode::FAILURE
        }
        Err(e) => {
            eprintln!("shell-e2e: {e:#}");
            std::process::ExitCode::FAILURE
        }
    }
}
