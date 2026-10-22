//! `mailbox login` and `mailbox link`: Proton Mail Bridge (pinned 3.24.2) run
//! headless under a private HOME, its keychain the `pass` stand-in
//! (mailbox-keychain), its encrypted vault and vault key kept in Proton Pass
//! between runs. The `mailbox` wrapper (../default.nix) asks governance first
//! and sets the environment read here.
//!
//!   mailbox login
//!       signs Bridge in to the Proton account with its login item's
//!       password; a 2FA code, or a human verification, is asked of the owner
//!   mailbox link --to A --from D... --host H... [--path P] [--since M] [--wait M]
//!       the newest link on a declared host, in mail to A from a declared
//!       sender domain received in the last M minutes, on stdout only;
//!       waits up to --wait minutes for it to arrive
//!
//! Bridge's own output is never echoed: its `info` carries the IMAP
//! password. Only its prompts for the owner and its errors are passed on.

use std::io::{BufRead, Read, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use mailbox::{get, marker, set, vault_key, XDG};
use zeroize::Zeroizing;

fn var(name: &str) -> Result<String> {
    std::env::var(name).with_context(|| format!("{name} is not set"))
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("login") => login(),
        Some("link") => link(&Query::parse(&args[1..])?),
        _ => bail!("usage: mailbox login | link --to A --from D... --host H... [--path P] [--since M] [--wait M]"),
    }
}

/// Bridge's directories, all under the private one.
struct Home {
    private: PathBuf,
    home: PathBuf,
    store: PathBuf,
}

impl Home {
    fn new() -> Result<Self> {
        let private = PathBuf::from(var("MAILBOX_PRIVATE")?);
        let home = private.join("home");
        let store = private.join("pass-store");
        std::fs::create_dir_all(&home)?;
        std::fs::create_dir_all(&store)?;
        Ok(Home { private, home, store })
    }

    fn vault_file(&self) -> PathBuf {
        self.home.join(".config/protonmail/bridge-v3/vault.enc")
    }

    /// The vault and its key as Proton Pass last kept them.
    fn restore(&self) -> Result<bool> {
        let key = get("BRIDGE_VAULT_KEY", "mailbox: open Bridge's vault")?;
        let vault = get("BRIDGE_VAULT", "mailbox: open Bridge's vault")?;
        if key.trim().is_empty() || vault.trim().is_empty() {
            return Ok(false);
        }
        marker(&self.store, &vault_key().1)?;
        let file = self.vault_file();
        std::fs::create_dir_all(file.parent().context("vault path")?)?;
        let bytes = Zeroizing::new(STANDARD.decode(vault.trim()).context("BRIDGE_VAULT is not base64")?);
        std::fs::write(&file, &*bytes)?;
        Ok(true)
    }

    /// The vault back into Proton Pass: Bridge rotates its session tokens.
    fn save(&self) -> Result<()> {
        let file = self.vault_file();
        if !file.exists() {
            return Ok(());
        }
        let bytes = Zeroizing::new(std::fs::read(&file)?);
        set("BRIDGE_VAULT", &STANDARD.encode(&*bytes), "mailbox: keep Bridge's vault")
    }
}

struct Bridge {
    child: Child,
    stdin: ChildStdin,
    out: Arc<Mutex<String>>,
    seen: usize,
}

impl Bridge {
    fn start(home: &Home) -> Result<Self> {
        let path = format!("{}:{}", var("MAILBOX_KEYCHAIN_DIR")?, var("PATH")?);
        let mut cmd = Command::new(var("MAILBOX_BRIDGE")?);
        for name in XDG {
            cmd.env(format!("MAILBOX_CALLER_{name}"), std::env::var(name).unwrap_or_default());
        }
        let mut child = cmd
            .arg("--cli")
            .env("HOME", &home.home)
            .env("XDG_CONFIG_HOME", home.home.join(".config"))
            .env("XDG_DATA_HOME", home.home.join(".local/share"))
            .env("XDG_CACHE_HOME", home.home.join(".cache"))
            .env("XDG_STATE_HOME", home.home.join(".local/state"))
            .env("PASSWORD_STORE_DIR", &home.store)
            .env("PATH", path)
            .env("MAILBOX_CALLER_HOME", var("HOME")?)
            .env("DBUS_SESSION_BUS_ADDRESS", "disabled:")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .context("starting Bridge")?;
        let stdin = child.stdin.take().context("Bridge's stdin")?;
        let mut stdout = child.stdout.take().context("Bridge's stdout")?;
        let out = Arc::new(Mutex::new(String::new()));
        let sink = out.clone();
        std::thread::spawn(move || {
            let mut buf = [0u8; 4096];
            while let Ok(n) = stdout.read(&mut buf) {
                if n == 0 {
                    break;
                }
                sink.lock().unwrap().push_str(&String::from_utf8_lossy(&buf[..n]));
            }
        });
        let mut bridge = Bridge { child, stdin, out, seen: 0 };
        bridge.wait(&["jgs"], 120).context("Bridge did not start")?;
        // Without its key from the keychain, Bridge keeps an unencrypted
        // vault in a folder of that name: never sign in to one.
        if home.home.join(".config/protonmail/bridge-v3/insecure").exists() {
            bridge.child.kill().ok();
            bail!("Bridge could not keep its vault key in Proton Pass and fell back to an unencrypted vault");
        }
        Ok(bridge)
    }

    fn send(&mut self, line: &str) -> Result<()> {
        self.stdin.write_all(line.as_bytes())?;
        self.stdin.write_all(b"\n")?;
        self.stdin.flush()?;
        Ok(())
    }

    /// Waits for the first of the patterns after what was already read,
    /// and returns which one; what came before it is read past.
    fn wait(&mut self, patterns: &[&str], seconds: u64) -> Result<usize> {
        let start = Instant::now();
        loop {
            {
                let out = self.out.lock().unwrap();
                let rest = &out[self.seen..];
                let found = patterns
                    .iter()
                    .enumerate()
                    .filter_map(|(i, p)| rest.find(p).map(|at| (at, i, p.len())))
                    .min();
                if let Some((at, i, len)) = found {
                    self.seen += at + len;
                    return Ok(i);
                }
            }
            if start.elapsed() > Duration::from_secs(seconds) {
                bail!("Bridge never said any of {patterns:?}");
            }
            if let Ok(Some(status)) = self.child.try_wait() {
                bail!("Bridge exited ({status})");
            }
            std::thread::sleep(Duration::from_millis(200));
        }
    }

    /// The rest of the line after the last match.
    fn line(&mut self, seconds: u64) -> Result<String> {
        self.wait(&["\n"], seconds)?;
        let out = self.out.lock().unwrap();
        let before = &out[..self.seen - 1];
        Ok(before[before.rfind(['\n', '\r']).map_or(0, |i| i + 1)..].to_owned())
    }

    /// Bridge's settings that must hold before anything else: no
    /// downloaded updates (the pinned build is the one that runs), no
    /// usage diagnostics.
    fn settle(&mut self) -> Result<()> {
        for (command, done) in [
            ("updates autoupdates disable", "already set to NOT"),
            ("telemetry disable", "is disabled"),
        ] {
            self.send(command)?;
            if self.wait(&["yes/", done], 30)? == 0 {
                self.send("yes")?;
            }
        }
        Ok(())
    }

    fn stop(mut self) -> Result<()> {
        self.send("exit").ok();
        let start = Instant::now();
        while self.child.try_wait()?.is_none() {
            if start.elapsed() > Duration::from_secs(60) {
                self.child.kill().ok();
                break;
            }
            std::thread::sleep(Duration::from_millis(200));
        }
        Ok(())
    }
}

/// The owner's answer to a prompt, from our stdin; nothing else reads it.
fn ask(prompt: &str) -> Result<Zeroizing<String>> {
    eprintln!("mailbox: {prompt}");
    let mut line = Zeroizing::new(String::new());
    std::io::stdin().lock().read_line(&mut line)?;
    Ok(Zeroizing::new(line.trim().to_owned()))
}

fn password() -> Result<Zeroizing<String>> {
    let out = Command::new("pass-cli")
        .args([
            "item",
            "view",
            "--vault-name",
            &var("MAILBOX_LOGIN_VAULT")?,
            "--item-title",
            &var("MAILBOX_LOGIN_ITEM")?,
            "--field",
            "password",
        ])
        .stderr(Stdio::null())
        .output()
        .context("running pass-cli")?;
    let text = Zeroizing::new(String::from_utf8(out.stdout).context("pass-cli output is not UTF-8")?);
    if !out.status.success() || text.trim().is_empty() {
        bail!("pass-cli item view failed: no password on the Proton login item");
    }
    Ok(Zeroizing::new(text.trim_end_matches('\n').to_owned()))
}

/// The login item's current 2FA code, from its TOTP key in Proton Pass:
/// the first 6 to 8 digits in pass-cli's answer.
fn totp() -> Result<Zeroizing<String>> {
    let out = Command::new("pass-cli")
        .args([
            "item",
            "totp",
            "--vault-name",
            &var("MAILBOX_LOGIN_VAULT")?,
            "--item-title",
            &var("MAILBOX_LOGIN_ITEM")?,
            "--output",
            "json",
        ])
        .stderr(Stdio::null())
        .output()
        .context("running pass-cli")?;
    let text = Zeroizing::new(String::from_utf8(out.stdout).context("pass-cli output is not UTF-8")?);
    if !out.status.success() {
        bail!("the login item has no 2FA key");
    }
    let code: String = text
        .split(|c: char| !c.is_ascii_digit())
        .find(|run| (6..=8).contains(&run.len()))
        .context("no code in pass-cli's answer")?
        .to_owned();
    Ok(Zeroizing::new(code))
}

fn login() -> Result<()> {
    let home = Home::new()?;
    home.restore()?;
    let mut bridge = Bridge::start(&home)?;
    let result = (|| -> Result<()> {
        bridge.settle()?;
        bridge.send("login")?;
        bridge.wait(&["Username:"], 60)?;
        bridge.send(&var("MAILBOX_LOGIN")?)?;
        bridge.wait(&["Password:"], 60)?;
        bridge.send(&password()?)?;
        loop {
            match bridge.wait(
                &[
                    "was added successfully",
                    "Two factor code:",
                    "Human Verification requested",
                    "Cannot login",
                    "Mailbox password:",
                    "Security key PIN",
                ],
                300,
            )? {
                0 => break,
                1 => {
                    let code = match totp() {
                        Ok(code) => code,
                        Err(_) => ask("Proton's 2FA code for the account:")?,
                    };
                    bridge.send(&code)?;
                }
                2 => {
                    // Bridge prints the challenge's address on its own line.
                    bridge.wait(&["https://"], 30)?;
                    let url = bridge.line(30)?.trim().to_owned();
                    eprintln!("mailbox: Proton asks for a human verification: {url}");
                    ask("press Enter here once it is done")?;
                    bridge.send("")?;
                }
                3 => {
                    let why = bridge.line(30).unwrap_or_default();
                    bail!("Proton refused the sign-in:{why}");
                }
                4 => bail!("the account has a second (mailbox) password; mailbox does not take one"),
                _ => bail!("the account asks for a security key; mailbox signs in with a 2FA code"),
            }
        }
        eprintln!("mailbox: Bridge is signed in");
        Ok(())
    })();
    bridge.stop()?;
    home.save()?;
    result
}

struct Query {
    to: String,
    from: Vec<String>,
    hosts: Vec<String>,
    path: Option<String>,
    since: u64,
    wait: u64,
}

impl Query {
    fn parse(args: &[String]) -> Result<Self> {
        let mut q = Query { to: String::new(), from: vec![], hosts: vec![], path: None, since: 30, wait: 10 };
        let mut it = args.iter();
        while let Some(flag) = it.next() {
            let value = it.next().with_context(|| format!("{flag} needs a value"))?.to_lowercase();
            match flag.as_str() {
                "--to" => q.to = value,
                "--from" => q.from.push(value),
                "--host" => q.hosts.push(value),
                "--path" => q.path = Some(value),
                "--since" => q.since = value.parse()?,
                "--wait" => q.wait = value.parse()?,
                _ => bail!("unknown option {flag}"),
            }
        }
        if q.to.is_empty() || q.from.is_empty() || q.hosts.is_empty() {
            bail!("--to, --from and --host are required");
        }
        Ok(q)
    }
}

/// IMAP's SEARCH date (e.g. 21-Oct-2026), a day before `secs` so a time
/// zone never hides a message; the exact window is held after.
fn imap_date(secs: u64) -> String {
    let days = (secs / 86_400) as i64 - 1;
    // Howard Hinnant's civil-from-days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    const MONTHS: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    format!("{d}-{}-{y}", MONTHS[(m - 1) as usize])
}

fn link(q: &Query) -> Result<()> {
    let home = Home::new()?;
    if !home.restore()? {
        bail!("Bridge has no stored session: run `mailbox login` first");
    }
    let mut bridge = Bridge::start(&home)?;
    let result = (|| -> Result<String> {
        bridge.settle()?;
        // A fresh cache syncs the whole mailbox before IMAP serves it.
        let seen = bridge.seen;
        bridge.seen = 0;
        bridge
            .wait(&["A sync has finished"], q.wait * 60 + 600)
            .context("Bridge's sync did not finish")?;
        bridge.seen = bridge.seen.max(seen);

        bridge.send("info")?;
        bridge.wait(&["IMAP port:"], 60)?;
        let port: u16 = bridge.line(30)?.trim().parse().context("IMAP port")?;
        bridge.wait(&["Username:"], 30)?;
        let user = bridge.line(30)?.trim().to_owned();
        bridge.wait(&["Password:"], 30)?;
        let pass = Zeroizing::new(bridge.line(30)?.trim().to_owned());

        let certs = home.private.join("cert");
        std::fs::create_dir_all(&certs)?;
        bridge.send("cert export")?;
        bridge.wait(&["Enter a path"], 30)?;
        bridge.wait(&[":"], 30)?;
        bridge.send(certs.to_str().context("cert path")?)?;
        bridge.wait(&["exported to"], 30)?;
        let pem = std::fs::read(certs.join("cert.pem"));
        std::fs::remove_dir_all(&certs).ok();

        read(q, port, &user, &pass, &pem?)
    })();
    bridge.stop()?;
    home.save()?;
    let url = result?;
    println!("{url}");
    Ok(())
}

/// The newest declared link in declared mail, over Bridge's IMAP on the
/// loopback, trusting only Bridge's own certificate.
fn read(q: &Query, port: u16, user: &str, pass: &str, pem: &[u8]) -> Result<String> {
    let tls = native_tls::TlsConnector::builder()
        .add_root_certificate(native_tls::Certificate::from_pem(pem)?)
        .disable_built_in_roots(true)
        .danger_accept_invalid_hostnames(true)
        .build()?;
    let client = imap::connect_starttls(("127.0.0.1", port), "127.0.0.1", &tls)?;
    let mut session = client.login(user, pass).map_err(|e| e.0).context("Bridge's IMAP login")?;
    session.select("INBOX")?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let deadline = Instant::now() + Duration::from_secs(q.wait * 60);
    let found = loop {
        let mut uids: Vec<u32> = vec![];
        for domain in &q.from {
            let search = format!("SINCE {} FROM \"{domain}\" TO \"{}\"", imap_date(now), q.to);
            uids.extend(session.uid_search(search)?);
        }
        uids.sort_unstable();
        uids.dedup();
        let mut found = None;
        for uid in uids.iter().rev().take(10) {
            for fetch in session.uid_fetch(uid.to_string(), "RFC822")?.iter() {
                if let Some(body) = fetch.body() {
                    if let Some(url) = message_link(q, body, now)? {
                        found = Some(url);
                    }
                }
            }
            if found.is_some() {
                break;
            }
        }
        if let Some(url) = found {
            break Some(url);
        }
        if Instant::now() > deadline {
            break None;
        }
        std::thread::sleep(Duration::from_secs(10));
        session.noop()?;
    };
    session.logout().ok();
    found.with_context(|| format!("no mail to {} from {:?} with a link on {:?} in the last {} min", q.to, q.from, q.hosts, q.since))
}

fn message_link(q: &Query, raw: &[u8], now: u64) -> Result<Option<String>> {
    let mail = mailparse::parse_mail(raw)?;
    let header = |name: &str| mail.headers.iter().filter(|h| h.get_key().eq_ignore_ascii_case(name)).map(|h| h.get_value().to_lowercase()).collect::<Vec<_>>();
    // Received in the window.
    let when = header("date").first().and_then(|d| mailparse::dateparse(d).ok()).unwrap_or(0);
    if when < 0 || (when as u64) + q.since * 60 < now {
        return Ok(None);
    }
    // From one of the declared domains, exactly or a subdomain of one.
    let from = header("from");
    let sender = from
        .first()
        .and_then(|f| f.rsplit('@').next())
        .map(|d| d.trim_end_matches(['>', ' ', '"']).to_owned())
        .unwrap_or_default();
    if !q.from.iter().any(|d| sender == *d || sender.ends_with(&format!(".{d}"))) {
        return Ok(None);
    }
    // To the declared address.
    let to = [header("to"), header("delivered-to"), header("x-original-to")].concat();
    if !to.iter().any(|t| t.contains(&q.to)) {
        return Ok(None);
    }
    let mut bodies = vec![];
    collect(&mail, &mut bodies)?;
    for body in bodies {
        for url in links(&body) {
            let rest = &url["https://".len()..];
            let host = rest.split(['/', '?', '#', ':']).next().unwrap_or_default().to_lowercase();
            let path = rest[host.len()..].split(['?', '#']).next().unwrap_or_default();
            match &q.path {
                Some(p) if q.hosts.contains(&host) && path.starts_with(p.as_str()) => {
                    return Ok(Some(url));
                }
                Some(_) => {}
                // Not mapped yet: what the mail links to, without its query
                // or token, so the declared host and path can be written
                // from it; nothing is followed.
                None => {
                    let first = path.split('/').nth(1).unwrap_or_default();
                    eprintln!("mailbox: seen https://{host}/{first}/…");
                }
            }
        }
    }
    Ok(None)
}

fn collect(part: &mailparse::ParsedMail, out: &mut Vec<String>) -> Result<()> {
    if part.subparts.is_empty() {
        let ctype = part.ctype.mimetype.to_lowercase();
        if ctype == "text/html" || ctype == "text/plain" {
            out.push(part.get_body()?);
        }
    }
    for sub in &part.subparts {
        collect(sub, out)?;
    }
    Ok(())
}

fn links(text: &str) -> Vec<String> {
    let mut found = vec![];
    let mut rest = text;
    while let Some(at) = rest.find("https://") {
        let tail = &rest[at..];
        let end = tail.find(|c: char| c.is_whitespace() || "\"'<>()[]".contains(c)).unwrap_or(tail.len());
        found.push(tail[..end].replace("&amp;", "&").trim_end_matches(['.', ',', ';']).to_owned());
        rest = &tail[end..];
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    fn query() -> Query {
        Query {
            to: "finance@jingzo.org".into(),
            from: vec!["mercury.com".into()],
            hosts: vec!["app.mercury.com".into()],
            path: Some("/verify".into()),
            since: 30,
            wait: 0,
        }
    }

    fn mail(from: &str, to: &str, date: &str) -> Vec<u8> {
        format!(
            "From: Mercury <{from}>\r\nTo: {to}\r\nDate: {date}\r\nContent-Type: text/html\r\n\r\n\
             <a href=\"https://mercury.com/help\">Help</a> \
             <a href=\"https://app.mercury.com/verify?token=abc&amp;d=1\">Verify</a>\r\n"
        )
        .into_bytes()
    }

    const NOW: u64 = 1_792_700_000; // 2026-10-22 20:13 UTC
    const DATE: &str = "Thu, 22 Oct 2026 20:00:00 +0000"; // 13 min before NOW

    #[test]
    fn dates_are_a_day_early() {
        assert_eq!(imap_date(NOW), "21-Oct-2026");
        assert_eq!(imap_date(951_868_800), "29-Feb-2000"); // 2000-03-01
    }

    #[test]
    fn links_end_at_markup_and_unescape() {
        assert_eq!(
            links("see <https://a.b/c?x=1&amp;y=2>, or (https://d.e/f)."),
            vec!["https://a.b/c?x=1&y=2", "https://d.e/f"]
        );
    }

    #[test]
    fn only_declared_mail_gives_its_link() {
        let q = query();
        let ok = message_link(&q, &mail("no-reply@mercury.com", "finance@jingzo.org", DATE), NOW).unwrap();
        assert_eq!(ok.as_deref(), Some("https://app.mercury.com/verify?token=abc&d=1"));
        // A subdomain of a declared sender is the sender.
        assert!(message_link(&q, &mail("x@mail.mercury.com", "finance@jingzo.org", DATE), NOW).unwrap().is_some());
        // Another sender, a look-alike domain, another recipient, an old mail.
        for raw in [
            mail("x@evil.com", "finance@jingzo.org", DATE),
            mail("x@notmercury.com", "finance@jingzo.org", DATE),
            mail("no-reply@mercury.com", "zach@mirazo.org", DATE),
            mail("no-reply@mercury.com", "finance@jingzo.org", "Thu, 22 Oct 2026 01:00:00 +0000"),
        ] {
            assert_eq!(message_link(&q, &raw, NOW).unwrap(), None);
        }
    }
}
