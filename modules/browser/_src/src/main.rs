//! `browser [--check] FLOW.json`: runs one declared flow (or, with
//! --check, only type-checks it) in a fresh Chromium
//! profile over the DevTools Protocol. The `browser` wrapper (../default.nix)
//! asks governance-authorize first and hands it the flow; this program
//! checks the flow's types again, keeps the browser on the flow's hosts, and
//! types values from Proton Pass straight into the page.

mod flow;
mod pass;
mod passkey;
mod proton_passkey;

use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use chromiumoxide::browser::{Browser, BrowserConfig};
use chromiumoxide::cdp::browser_protocol::dom::{
    BackendNodeId, FocusParams, GetBoxModelParams, GetDocumentParams, ScrollIntoViewIfNeededParams,
};
use chromiumoxide::cdp::browser_protocol::input::InsertTextParams;
use chromiumoxide::layout::Point;
use chromiumoxide::Page;
use futures::StreamExt;
use serde::Serialize;
use tokio::io::AsyncBufReadExt;
use zeroize::Zeroizing;

use flow::{Flow, Step, Target, Until, Value};

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (check, path) = match args.as_slice() {
        [flag, path] if flag == "--check" => (true, path),
        [path] => (false, path),
        _ => bail!("usage: browser [--check] FLOW.json"),
    };
    let flow: Flow = serde_json::from_str(&std::fs::read_to_string(path)?)
        .context("the flow does not type-check")?;
    if check {
        return Ok(());
    }
    let chromium = std::env::var("BROWSER_CHROMIUM").context("BROWSER_CHROMIUM is not set")?;
    let profile = std::env::var("BROWSER_PROFILE").context("BROWSER_PROFILE is not set")?;

    let mut config = BrowserConfig::builder()
        .chrome_executable(chromium)
        .user_data_dir(profile)
        .window_size(1280, 900)
        .launch_timeout(Duration::from_secs(30))
        .arg("--headless=new")
        .arg("--disable-component-update");
    // Chromium's own sandbox refuses to run as root; the wrapper says so
    // only then, and the profile is a fresh directory either way.
    if std::env::var_os("BROWSER_NO_SANDBOX").is_some() {
        config = config.no_sandbox();
    }
    let config = config.build().map_err(anyhow::Error::msg)?;
    let (mut browser, mut handler) = Browser::launch(config).await?;
    let events = tokio::spawn(async move { while handler.next().await.is_some() {} });

    let page = browser.new_page("about:blank").await?;
    let result = run(&flow, &page).await;
    // Chromium is waited for, so the wrapper removes a profile nothing is
    // still writing.
    browser.close().await.ok();
    browser.wait().await.ok();
    events.abort();
    match &result {
        Ok(()) => eprintln!("browser: {} on {}: done", flow.action, flow.account),
        Err(e) => eprintln!(
            "browser: {} on {}: stopped: {e:#}",
            flow.action, flow.account
        ),
    }
    result
}

async fn run(flow: &Flow, page: &Page) -> Result<()> {
    let authenticator = match &flow.passkey {
        Some(store) => Some(
            passkey::start(page, store, &flow.login)
                .await
                .context("the passkey authenticator")?,
        ),
        None => None,
    };
    for (i, step) in flow.steps.iter().enumerate() {
        let n = i + 1;
        if let Step::Explore { minutes } = step {
            explore(flow, page, authenticator.as_ref(), n, *minutes).await?;
            continue;
        }
        bounded(flow, page, authenticator.as_ref(), n, step).await?;
    }
    Ok(())
}

/// One step under its deadline: a browser that dies mid-flow leaves its
/// socket open, so every step gets its own wait plus a minute.
async fn bounded(
    flow: &Flow,
    page: &Page,
    authenticator: Option<&passkey::Authenticator>,
    n: usize,
    step: &Step,
) -> Result<()> {
    let limit = Duration::from_secs(60)
        + match step {
            Step::WaitFor { seconds, .. } | Step::WaitUrl { seconds, .. } => {
                Duration::from_secs(*seconds)
            }
            Step::Approve { minutes, .. } => Duration::from_secs(minutes * 60),
            Step::Code { .. } => Duration::from_secs(600),
            _ => Duration::ZERO,
        };
    tokio::time::timeout(limit, one(flow, page, authenticator, n, step))
        .await
        .map_err(|_| {
            anyhow::anyhow!(
                "step {n}: no answer from the browser in {}s",
                limit.as_secs()
            )
        })?
}

/// A one-time code into its field: letters and digits only.
async fn type_code(flow: &Flow, page: &Page, target: &Target, line: &str) -> Result<()> {
    stay(flow, page).await?;
    let node = find(page, target, 20).await?;
    let code = line.trim();
    if code.is_empty() || !code.chars().all(|c| c.is_ascii_alphanumeric()) {
        bail!("not a code");
    }
    page.execute(FocusParams::builder().backend_node_id(node).build())
        .await?;
    page.execute(InsertTextParams::new(code)).await?;
    Ok(())
}

/// Steps read from stdin, one JSON object per line, after the declared ones.
/// Each is the same typed Step (an explore inside an explore is refused), so
/// it stays on the flow's hosts and types Proton Pass values unprinted.
async fn explore(
    flow: &Flow,
    page: &Page,
    authenticator: Option<&passkey::Authenticator>,
    n: usize,
    minutes: u64,
) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(minutes * 60);
    let mut lines = tokio::io::BufReader::new(tokio::io::stdin()).lines();
    let mut k = 0;
    eprintln!("browser: step {n}: exploring, one step per line on stdin");
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        let line = match tokio::time::timeout(left, lines.next_line()).await {
            Err(_) => bail!("step {n}: exploring ran past {minutes} min"),
            Ok(line) => match line? {
                Some(line) => line,
                None => return Ok(()),
            },
        };
        if line.trim().is_empty() {
            continue;
        }
        k += 1;
        let at = format!("{n}.{k}");
        let result = match serde_json::from_str::<Step>(&line) {
            Err(e) => Err(anyhow::anyhow!("step {at} does not type-check: {e}")),
            Ok(Step::Explore { .. }) => Err(anyhow::anyhow!("step {at}: already exploring")),
            // A code is the next line of the same stdin, read here so no
            // second reader can swallow it.
            Ok(Step::Code { prompt, target }) => {
                eprintln!("browser: {prompt}");
                match lines.next_line().await? {
                    Some(code) => type_code(flow, page, &target, &Zeroizing::new(code))
                        .await
                        .with_context(|| format!("step {at}")),
                    None => return Ok(()),
                }
            }
            Ok(step) => bounded(flow, page, authenticator, k, &step)
                .await
                .with_context(|| format!("step {at}")),
        };
        match result {
            Ok(()) => eprintln!("browser: step {at}: done"),
            Err(e) => eprintln!("browser: {e:#}"),
        }
    }
}

async fn one(
    flow: &Flow,
    page: &Page,
    authenticator: Option<&passkey::Authenticator>,
    n: usize,
    step: &Step,
) -> Result<()> {
    {
        match step {
            Step::Goto { url } => {
                on_hosts(flow, url).with_context(|| format!("step {n}"))?;
                page.goto(url.as_str()).await?;
                page.wait_for_navigation().await?;
            }
            Step::Fill { target, value } => {
                stay(flow, page)
                    .await
                    .with_context(|| format!("step {n}"))?;
                let node = find(page, target, 20)
                    .await
                    .with_context(|| format!("step {n}"))?;
                let text = resolve(flow, value)
                    .await
                    .with_context(|| format!("step {n}"))?;
                page.execute(FocusParams::builder().backend_node_id(node).build())
                    .await?;
                page.execute(InsertTextParams::new(text.as_str())).await?;
            }
            Step::Click { target } => {
                stay(flow, page)
                    .await
                    .with_context(|| format!("step {n}"))?;
                let node = find(page, target, 20)
                    .await
                    .with_context(|| format!("step {n}"))?;
                click(page, node).await?;
            }
            Step::WaitFor { target, seconds } => {
                find(page, target, *seconds)
                    .await
                    .with_context(|| format!("step {n}"))?;
            }
            Step::WaitUrl { prefix, seconds } => {
                wait_url(page, prefix, Duration::from_secs(*seconds))
                    .await
                    .with_context(|| format!("step {n}"))?;
            }
            Step::Approve {
                prompt,
                until,
                minutes,
            } => {
                eprintln!("browser: {prompt} (waiting up to {minutes} min)");
                let limit = Duration::from_secs(minutes * 60);
                match until {
                    Until::UrlPrefix { prefix } => wait_url(page, prefix, limit).await,
                    Until::Shows { target } => {
                        find(page, target, limit.as_secs()).await.map(|_| ())
                    }
                }
                .with_context(|| format!("step {n}: not approved in time"))?;
            }
            Step::Code { prompt, target } => {
                eprintln!("browser: {prompt}");
                let mut line = Zeroizing::new(String::new());
                tokio::io::BufReader::new(tokio::io::stdin())
                    .read_line(&mut line)
                    .await?;
                type_code(flow, page, target, &line)
                    .await
                    .with_context(|| format!("step {n}"))?;
            }
            Step::Snapshot { text } => snapshot(page, *text).await?,
            Step::Explore { .. } => bail!("step {n}: explore runs only from the flow's steps"),
            Step::PasskeySave => match (authenticator, &flow.passkey) {
                (Some(auth), Some(store)) => passkey::save(page, auth, store)
                    .await
                    .with_context(|| format!("step {n}"))?,
                _ => bail!("step {n}: the flow declares no passkey store"),
            },
        }
    }
    Ok(())
}

/// The host of an HTTPS address; plain HTTP only on the loopback (127.0.0.1
/// or localhost, which WebAuthn needs as a domain), which the
/// module's types allow solely in its own check.
fn host_of(url: &str) -> Option<&str> {
    for loopback in ["127.0.0.1", "localhost"] {
        if let Some(rest) = url.strip_prefix(&format!("http://{loopback}")) {
            return rest.starts_with([':', '/']).then_some(loopback);
        }
    }
    let rest = url.strip_prefix("https://")?;
    Some(
        rest.split(['/', '?', '#'])
            .next()
            .unwrap_or(rest)
            .split(':')
            .next()
            .unwrap_or(rest),
    )
}

/// HTTPS on one of the flow's hosts, or nothing at all.
fn on_hosts(flow: &Flow, url: &str) -> Result<()> {
    match host_of(url) {
        Some(h) if flow.hosts.iter().any(|a| a == h) => Ok(()),
        _ => bail!(
            "{url} is not on the flow's hosts ({})",
            flow.hosts.join(", ")
        ),
    }
}

/// The page is still where the flow may type.
async fn stay(flow: &Flow, page: &Page) -> Result<()> {
    let url = page.url().await?.unwrap_or_default();
    on_hosts(flow, &url)
}

async fn resolve(flow: &Flow, value: &Value) -> Result<Zeroizing<String>> {
    Ok(match value {
        Value::Text { text } => Zeroizing::new(text.clone()),
        Value::Declared => Zeroizing::new(flow.login.email.clone()),
        Value::Pass { field } => pass::read(&flow.login, *field).await?,
    })
}

async fn wait_url(page: &Page, prefix: &str, limit: Duration) -> Result<()> {
    let start = Instant::now();
    loop {
        if page.url().await?.unwrap_or_default().starts_with(prefix) {
            return Ok(());
        }
        if start.elapsed() > limit {
            bail!("the page never reached {prefix}");
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
}

/// A protocol call read as plain JSON, for the domains where chromiumoxide's
/// generated types lag the pinned Chromium (its accessibility tree rejects
/// property values newer Chromium sends) or are not used (WebAuthn). Every
/// method named here is declared in the module's cdpCalls and checked
/// against the pinned protocol.
#[derive(Debug, Serialize)]
pub(crate) struct Raw {
    #[serde(skip)]
    method: &'static str,
    #[serde(flatten)]
    params: serde_json::Value,
}

impl Raw {
    pub(crate) fn new(method: &'static str, params: serde_json::Value) -> Self {
        Raw { method, params }
    }
}

impl chromiumoxide::Method for Raw {
    fn identifier(&self) -> chromiumoxide::types::MethodId {
        self.method.into()
    }
}

impl chromiumoxide::Command for Raw {
    type Response = serde_json::Value;
}

fn ax_str<'a>(node: &'a serde_json::Value, field: &str) -> &'a str {
    node.pointer(&format!("/{field}/value"))
        .and_then(|v| v.as_str())
        .unwrap_or_default()
}

fn ax_nodes(result: &serde_json::Value) -> impl Iterator<Item = &serde_json::Value> {
    result["nodes"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|n| n["ignored"] != serde_json::Value::Bool(true))
}

/// The element a target names, retried while the page renders.
async fn find(page: &Page, target: &Target, seconds: u64) -> Result<BackendNodeId> {
    let start = Instant::now();
    loop {
        if let Some(node) = locate(page, target).await? {
            return Ok(node);
        }
        if start.elapsed() > Duration::from_secs(seconds) {
            bail!("nothing on the page matches {target:?}");
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
}

async fn locate(page: &Page, target: &Target) -> Result<Option<BackendNodeId>> {
    match target {
        Target::Css { css } => Ok(page
            .find_element(css.as_str())
            .await
            .ok()
            .map(|e| e.backend_node_id)),
        Target::Role { role, name } => {
            let doc = page
                .execute(GetDocumentParams::builder().depth(0).build())
                .await?;
            let query = Raw {
                method: "Accessibility.queryAXTree",
                params: serde_json::json!({
                    "backendNodeId": doc.result.root.backend_node_id,
                    "accessibleName": name,
                    "role": role.as_str(),
                }),
            };
            let found = page.execute(query).await?;
            let node = ax_nodes(&found.result).find_map(|n| n["backendDOMNodeId"].as_i64());
            Ok(node.map(BackendNodeId::new))
        }
    }
}

async fn click(page: &Page, node: BackendNodeId) -> Result<()> {
    page.execute(
        ScrollIntoViewIfNeededParams::builder()
            .backend_node_id(node)
            .build(),
    )
    .await?;
    let model = page
        .execute(GetBoxModelParams::builder().backend_node_id(node).build())
        .await?;
    let q = model.result.model.content.inner();
    let (x, y) = (
        (q[0] + q[2] + q[4] + q[6]) / 4.0,
        (q[1] + q[3] + q[5] + q[7]) / 4.0,
    );
    page.click(Point { x, y }).await?;
    Ok(())
}

/// Controls and headings by role and name; text fields' values are left out.
/// With `text`, the page's words too, for a message no control carries; off
/// by default, since a signed-in page's text is the account's data.
async fn snapshot(page: &Page, text: bool) -> Result<()> {
    const ROLES: [&str; 16] = [
        "button",
        "link",
        "textbox",
        "combobox",
        "checkbox",
        "radio",
        "option",
        "menuitem",
        "tab",
        "heading",
        "searchbox",
        "switch",
        // What the page says back: errors, prompts for a second factor.
        "alert",
        "alertdialog",
        "status",
        "dialog",
    ];
    let url = page.url().await?.unwrap_or_default();
    println!("== {}", url.split('?').next().unwrap_or(&url));
    let tree = page
        .execute(Raw {
            method: "Accessibility.getFullAXTree",
            params: serde_json::json!({}),
        })
        .await?;
    // A text field's value shows as text inside it: never printed.
    let parents: std::collections::HashMap<&str, (&str, &str)> = tree.result["nodes"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|n| {
            (
                n["nodeId"].as_str().unwrap_or_default(),
                (
                    ax_str(n, "role"),
                    n["parentId"].as_str().unwrap_or_default(),
                ),
            )
        })
        .collect();
    let in_field = |node: &serde_json::Value| {
        let mut at = node["parentId"].as_str().unwrap_or_default();
        while let Some((role, up)) = parents.get(at) {
            if matches!(*role, "textbox" | "searchbox" | "combobox") {
                return true;
            }
            at = up;
        }
        false
    };
    for node in ax_nodes(&tree.result) {
        let role = ax_str(node, "role");
        if ROLES.contains(&role) || (text && role == "StaticText" && !in_field(node)) {
            println!("{role:<10} {:?}", ax_str(node, "name"));
        }
    }
    Ok(())
}
