//! The recurring relationships in a mailbox, read off its receipts, renewal
//! notices and bills: who charges, how much, how often, on which card, and
//! where it is cancelled. Pure functions over raw messages, so every rule is
//! tested on fixtures; `mailbox recurring` (src/main.rs) feeds them from
//! Bridge and writes the tally to a private file, never to the terminal.

use std::collections::{BTreeMap, BTreeSet};

/// What one message says about a charge.
#[derive(Debug, Clone, PartialEq)]
pub struct Charge {
    pub domain: String,
    pub merchant: String,
    pub to: String,
    pub when: i64,
    pub amount: Option<f64>,
    pub card: Option<String>,
    pub kind: Kind,
    pub cancel: Vec<String>,
    /// Addresses a person reads at the merchant: Reply-To, and support or
    /// billing addresses on its own domain named in the mail.
    pub contacts: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    /// A utility, phone, internet, insurance, rent, loan or card bill.
    Bill,
    /// A subscription or membership that renews.
    Subscription,
    /// A receipt with no sign of renewing.
    Receipt,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Kind::Bill => "bill",
            Kind::Subscription => "subscription",
            Kind::Receipt => "receipt",
        }
    }
}

const BILL: &[&str] = &[
    "your bill", "bill is ready", "statement is ready", "statement is available", "payment due", "amount due",
    "autopay", "auto pay", "utility", "electric", "energy", "water bill", "gas bill", "internet", "wireless",
    "insurance", "premium", "policy", "rent", "mortgage", "loan payment", "minimum payment",
];
const SUBSCRIPTION: &[&str] = &[
    "subscription", "renewal", "renews", "renewed", "membership", "your plan", "monthly plan", "annual plan",
    "billing period", "recurring", "trial ends", "free trial", "auto-renew",
];
const CHARGE: &[&str] = &[
    "receipt", "invoice", "your order", "payment", "charged", "billing", "statement", "renew", "subscription",
    "membership", "bill", "autopay", "amount due",
];

/// Whether a subject is worth fetching the body for.
pub fn charge_subject(subject: &str) -> bool {
    let s = subject.to_lowercase();
    CHARGE.iter().any(|w| s.contains(w))
}

/// The registrable part of a host (the last two labels, or three under a
/// short second level in a country code: co.uk).
pub fn base_domain(host: &str) -> String {
    let labels: Vec<&str> = host.split('.').filter(|l| !l.is_empty()).collect();
    let n = labels.len();
    let keep = if n >= 3 && labels[n - 1].len() == 2 && labels[n - 2].len() <= 3 { 3 } else { 2 };
    labels[n.saturating_sub(keep)..].join(".")
}

/// Text with markup removed and whitespace collapsed, lowercased.
pub fn plain(body: &str) -> String {
    let mut out = String::with_capacity(body.len());
    let mut in_tag = false;
    for c in body.chars() {
        match c {
            '<' => in_tag = true,
            '>' => {
                in_tag = false;
                out.push(' ');
            }
            _ if !in_tag => out.push(c),
            _ => {}
        }
    }
    let out = out.replace("&nbsp;", " ").replace("&amp;", "&").replace("&#36;", "$");
    out.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase()
}

/// Every dollar amount in the text, in order: $1,234.56 or $9.99 or $10.
pub fn amounts(text: &str) -> Vec<(usize, f64)> {
    let bytes = text.as_bytes();
    let mut out = vec![];
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'$' {
            let mut j = i + 1;
            while j < bytes.len() && bytes[j] == b' ' {
                j += 1;
            }
            let start = j;
            while j < bytes.len() && (bytes[j].is_ascii_digit() || bytes[j] == b',' || bytes[j] == b'.') {
                j += 1;
            }
            let raw = text[start..j].trim_end_matches(['.', ',']).replace(',', "");
            if let Ok(v) = raw.parse::<f64>() {
                if v > 0.0 && v < 1_000_000.0 {
                    out.push((i, v));
                }
            }
            i = j.max(i + 1);
        } else {
            i += 1;
        }
    }
    out
}

/// The amount charged: the first amount after the last "total" (or "amount
/// charged", "amount due", "you paid"), else the first amount.
pub fn charged(text: &str) -> Option<f64> {
    let found = amounts(text);
    let mark = ["amount charged", "total charged", "you paid", "amount due", "total due", "order total", "total"]
        .iter()
        .filter_map(|m| text.rfind(m))
        .max();
    match mark {
        Some(at) => found.iter().find(|(i, _)| *i > at).or(found.first()).map(|(_, v)| *v),
        None => found.first().map(|(_, v)| *v),
    }
}

/// The card a charge went to, when the mail names it: a brand if seen and
/// the last four digits ("ending in 1234", "•••• 1234", "x1234").
pub fn card(text: &str) -> Option<String> {
    let brands = [
        "visa", "mastercard", "american express", "amex", "discover", "chase", "capital one", "credit one",
        "paypal", "apple pay", "mercury",
    ];
    let digits = |s: &str| -> Option<String> {
        let d: String = s.chars().skip_while(|c| !c.is_ascii_digit()).take_while(|c| c.is_ascii_digit()).collect();
        (d.len() == 4).then_some(d)
    };
    let mut last4 = None;
    for key in ["ending in", "ending with", "ending", "•••• ", "**** ", "xxxx", " x"] {
        let mut rest = text;
        while let Some(at) = rest.find(key) {
            let after = &rest[at + key.len()..];
            if let Some(d) = digits(&after[..after.len().min(8)]) {
                last4 = Some(d);
                break;
            }
            rest = after;
        }
        if last4.is_some() {
            break;
        }
    }
    let brand = brands.iter().find(|b| text.contains(*b)).copied();
    match (brand, last4) {
        (Some(b), Some(d)) => Some(format!("{b} {d}")),
        (None, Some(d)) => Some(format!("card {d}")),
        (Some(b), None) if ["paypal", "apple pay"].contains(&b) => Some(b.to_string()),
        _ => None,
    }
}

/// Links that manage or cancel the relationship, without their query or
/// fragment (which carry tokens).
pub fn cancel_links(body: &str) -> Vec<String> {
    let mut out = BTreeSet::new();
    let mut rest = body;
    while let Some(at) = rest.find("https://") {
        let tail = &rest[at..];
        let end = tail.find(|c: char| c.is_whitespace() || "\"'<>()[]".contains(c)).unwrap_or(tail.len());
        let url = tail[..end].replace("&amp;", "&");
        let bare = url.split(['?', '#']).next().unwrap_or_default().trim_end_matches(['.', ',', ';']).to_lowercase();
        if ["cancel", "subscription", "membership", "manage", "billing", "account/plan", "autopay"]
            .iter()
            .any(|w| bare.contains(w))
            && !bare.contains("unsubscribe")
        {
            out.insert(bare);
        }
        rest = &tail[end..];
    }
    out.into_iter().take(3).collect()
}

/// Addresses on the merchant's own domain that a person reads: support,
/// help, billing, care, members, cancel; never no-reply.
pub fn contacts(text: &str, domain: &str) -> Vec<String> {
    let mut out = BTreeSet::new();
    for word in text.split(|c: char| c.is_whitespace() || "<>()[]\"',;:".contains(c)) {
        let w = word.trim_end_matches('.').to_lowercase();
        let Some((local, host)) = w.split_once('@') else { continue };
        if local.is_empty() || !host.contains('.') || base_domain(host) != domain {
            continue;
        }
        let human = ["support", "help", "billing", "care", "member", "cancel", "service", "account", "customer"]
            .iter()
            .any(|k| local.contains(k));
        let robot = ["noreply", "no-reply", "donotreply", "do-not-reply", "mailer", "bounce", "notification"]
            .iter()
            .any(|k| local.contains(k));
        if human && !robot {
            out.insert(w);
        }
    }
    out.into_iter().take(3).collect()
}

/// What a raw message says about a charge, if it reads as one.
pub fn charge(raw: &[u8]) -> Option<Charge> {
    let mail = mailparse::parse_mail(raw).ok()?;
    let header = |k: &str| mail.headers.iter().find(|h| h.get_key().eq_ignore_ascii_case(k)).map(|h| h.get_value());
    let from = header("from")?;
    let subject = header("subject").unwrap_or_default();
    if !charge_subject(&subject) {
        return None;
    }
    let addr = from.rsplit('<').next().unwrap_or(&from).trim_end_matches(['>', ' ', '"']).to_lowercase();
    let host = addr.rsplit('@').next()?.to_string();
    if !host.contains('.') {
        return None;
    }
    let display = from.split('<').next().unwrap_or_default().trim().trim_matches('"').to_string();
    let domain = base_domain(&host);
    let mut bodies = vec![];
    collect(&mail, &mut bodies);
    let raw_body = bodies.join(" ");
    let text = format!("{} {}", subject.to_lowercase(), plain(&raw_body));
    let kind = if BILL.iter().any(|w| text.contains(w)) {
        Kind::Bill
    } else if SUBSCRIPTION.iter().any(|w| text.contains(w)) {
        Kind::Subscription
    } else {
        Kind::Receipt
    };
    let contact_list = {
        let reply = header("reply-to").unwrap_or_default();
        let mut c = contacts(&format!("{reply} {}", plain(&raw_body)), &domain);
        let reply = reply.rsplit('<').next().unwrap_or("").trim_end_matches(['>', ' ', '"']).to_lowercase();
        let robot = ["noreply", "no-reply", "donotreply", "do-not-reply"].iter().any(|k| reply.contains(k));
        if reply.contains('@') && !robot && !c.contains(&reply) {
            c.insert(0, reply);
        }
        c.truncate(3);
        c
    };
    Some(Charge {
        merchant: if display.is_empty() { domain.clone() } else { display },
        domain,
        to: header("to").unwrap_or_default().to_lowercase(),
        when: header("date").and_then(|d| mailparse::dateparse(&d).ok()).unwrap_or(0),
        amount: charged(&text),
        card: card(&text),
        kind,
        cancel: cancel_links(&raw_body),
        contacts: contact_list,
    })
}

fn collect(part: &mailparse::ParsedMail, out: &mut Vec<String>) {
    if part.subparts.is_empty() {
        let t = part.ctype.mimetype.to_lowercase();
        if t == "text/html" || t == "text/plain" {
            if let Ok(b) = part.get_body() {
                out.push(b);
            }
        }
    }
    for sub in &part.subparts {
        collect(sub, out);
    }
}

/// How often a relationship charges, from its dated charges.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cadence {
    Weekly,
    Monthly,
    Quarterly,
    Yearly,
    Irregular,
    Once,
}

impl Cadence {
    pub fn name(self) -> &'static str {
        match self {
            Cadence::Weekly => "weekly",
            Cadence::Monthly => "monthly",
            Cadence::Quarterly => "quarterly",
            Cadence::Yearly => "yearly",
            Cadence::Irregular => "irregular",
            Cadence::Once => "once",
        }
    }

    /// Charges a year, for a monthly-equivalent total.
    pub fn per_year(self) -> f64 {
        match self {
            Cadence::Weekly => 52.0,
            Cadence::Monthly => 12.0,
            Cadence::Quarterly => 4.0,
            Cadence::Yearly => 1.0,
            Cadence::Irregular | Cadence::Once => 0.0,
        }
    }
}

/// The cadence of distinct charge days: the median gap between them.
pub fn cadence(days: &[i64]) -> Cadence {
    let mut d: Vec<i64> = days.iter().map(|t| t / 86_400).collect();
    d.sort_unstable();
    d.dedup();
    if d.len() < 2 {
        return Cadence::Once;
    }
    let mut gaps: Vec<i64> = d.windows(2).map(|w| w[1] - w[0]).collect();
    gaps.sort_unstable();
    match gaps[gaps.len() / 2] {
        5..=9 => Cadence::Weekly,
        25..=35 => Cadence::Monthly,
        80..=100 => Cadence::Quarterly,
        330..=400 => Cadence::Yearly,
        _ => Cadence::Irregular,
    }
}

/// One merchant's relationship, over all its charges.
#[derive(Debug, Clone, PartialEq)]
pub struct Relationship {
    pub domain: String,
    pub merchant: String,
    pub kind: Kind,
    pub cadence: Cadence,
    pub charges: usize,
    pub first: i64,
    pub last: i64,
    pub last_amount: Option<f64>,
    pub cards: Vec<String>,
    pub to: Vec<String>,
    pub cancel: Vec<String>,
    pub contacts: Vec<String>,
}

impl Relationship {
    /// Whether it recurs: a cadence, or a bill or subscription by its words.
    pub fn recurring(&self) -> bool {
        self.cadence.per_year() > 0.0 || matches!(self.kind, Kind::Bill | Kind::Subscription)
    }

    pub fn per_month(&self) -> f64 {
        self.last_amount.unwrap_or(0.0) * self.cadence.per_year() / 12.0
    }

    pub fn json(&self) -> String {
        let s = |v: &str| v.replace(['"', '\\'], "");
        let list = |v: &[String]| v.iter().map(|x| format!("\"{}\"", s(x))).collect::<Vec<_>>().join(",");
        format!(
            "{{\"domain\":\"{}\",\"merchant\":\"{}\",\"kind\":\"{}\",\"cadence\":\"{}\",\"recurring\":{},\"charges\":{},\"first\":{},\"last\":{},\"last_amount\":{},\"per_month\":{:.2},\"cards\":[{}],\"to\":[{}],\"cancel\":[{}],\"contacts\":[{}],\"decision\":null}}",
            s(&self.domain),
            s(&self.merchant),
            self.kind.name(),
            self.cadence.name(),
            self.recurring(),
            self.charges,
            self.first,
            self.last,
            self.last_amount.map_or("null".into(), |a| format!("{a:.2}")),
            self.per_month(),
            list(&self.cards),
            list(&self.to),
            list(&self.cancel),
            list(&self.contacts),
        )
    }
}

/// The charges grouped by merchant domain, newest facts winning.
pub fn relationships(charges: &[Charge]) -> Vec<Relationship> {
    let mut by: BTreeMap<&str, Vec<&Charge>> = BTreeMap::new();
    for c in charges {
        by.entry(c.domain.as_str()).or_default().push(c);
    }
    let mut out = vec![];
    for (domain, mut cs) in by {
        cs.sort_by_key(|c| c.when);
        let latest = cs.last().expect("a group has a charge");
        let dated: Vec<i64> = cs.iter().filter(|c| c.amount.is_some()).map(|c| c.when).collect();
        out.push(Relationship {
            domain: domain.to_string(),
            merchant: latest.merchant.clone(),
            kind: cs.iter().map(|c| c.kind).min().expect("a group has a charge"),
            cadence: cadence(&dated),
            charges: cs.len(),
            first: cs.first().map_or(0, |c| c.when),
            last: latest.when,
            last_amount: cs.iter().rev().find_map(|c| c.amount),
            cards: cs.iter().filter_map(|c| c.card.clone()).collect::<BTreeSet<_>>().into_iter().collect(),
            to: cs.iter().map(|c| c.to.clone()).filter(|t| !t.is_empty()).collect::<BTreeSet<_>>().into_iter().collect(),
            cancel: cs.iter().flat_map(|c| c.cancel.clone()).collect::<BTreeSet<_>>().into_iter().take(3).collect(),
            contacts: cs.iter().flat_map(|c| c.contacts.clone()).collect::<BTreeSet<_>>().into_iter().take(3).collect(),
        });
    }
    out.sort_by(|a, b| b.per_month().partial_cmp(&a.per_month()).unwrap_or(std::cmp::Ordering::Equal));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mail(from: &str, subject: &str, date: &str, body: &str) -> Vec<u8> {
        format!("From: {from}\r\nTo: zach@example.org\r\nSubject: {subject}\r\nDate: {date}\r\nContent-Type: text/html\r\n\r\n{body}\r\n").into_bytes()
    }

    #[test]
    fn amounts_and_the_charged_total() {
        let t = plain("<td>Subtotal</td><td>$9.99</td><td>Tax</td><td>$0.82</td><td>Total</td><td>$10.81</td>");
        assert_eq!(amounts(&t).iter().map(|a| a.1).collect::<Vec<_>>(), vec![9.99, 0.82, 10.81]);
        assert_eq!(charged(&t), Some(10.81));
        assert_eq!(charged("you paid $1,204.50 today"), Some(1204.5));
        assert_eq!(charged("no money here"), None);
    }

    #[test]
    fn cards_by_brand_and_last_four() {
        assert_eq!(card("charged to your visa ending in 4242"), Some("visa 4242".into()));
        assert_eq!(card("chase sapphire •••• 1234 was charged"), Some("chase 1234".into()));
        assert_eq!(card("paid with paypal"), Some("paypal".into()));
        assert_eq!(card("thanks for your order"), None);
    }

    #[test]
    fn cancel_links_drop_tokens_and_marketing() {
        let l = cancel_links(r#"<a href="https://x.com/account/subscription?t=SECRET">Manage</a> <a href="https://x.com/unsubscribe?u=1">x</a>"#);
        assert_eq!(l, vec!["https://x.com/account/subscription".to_string()]);
    }

    #[test]
    fn messages_classify_and_group_into_monthly_relationships() {
        let a = charge(&mail("Streamer <billing@mail.streamer.com>", "Your receipt", "Tue, 1 Sep 2026 10:00:00 +0000",
            "Your subscription renews monthly. Total $15.49 charged to Visa ending in 4242. <a href='https://streamer.com/account/cancel?x=1'>Cancel</a>")).unwrap();
        let b = charge(&mail("Streamer <billing@mail.streamer.com>", "Your receipt", "Thu, 1 Oct 2026 10:00:00 +0000",
            "Your subscription renews monthly. Total $15.49 charged to Visa ending in 4242.")).unwrap();
        let bill = charge(&mail("City Power <noreply@citypower.com>", "Your bill is ready", "Thu, 1 Oct 2026 10:00:00 +0000",
            "Amount due $82.10. Autopay from Chase checking ending in 9876.")).unwrap();
        assert_eq!(a.kind, Kind::Subscription);
        assert_eq!(bill.kind, Kind::Bill);
        assert_eq!(bill.card.as_deref(), Some("chase 9876"));
        assert!(charge(&mail("Friend <a@b.com>", "lunch?", "Thu, 1 Oct 2026 10:00:00 +0000", "$5")).is_none());
        let r = relationships(&[a, b, bill]);
        let s = r.iter().find(|r| r.domain == "streamer.com").unwrap();
        assert_eq!((s.cadence, s.charges, s.last_amount), (Cadence::Monthly, 2, Some(15.49)));
        assert_eq!(s.cards, vec!["visa 4242".to_string()]);
        assert_eq!(s.cancel, vec!["https://streamer.com/account/cancel".to_string()]);
        assert!((s.per_month() - 15.49).abs() < 1e-9);
        assert!(r.iter().all(|r| r.recurring()));
    }

    #[test]
    fn contacts_are_the_merchants_own_human_addresses() {
        let t = "questions? write support@streamer.com or billing@mail.streamer.com, not noreply@streamer.com or help@other.com";
        assert_eq!(contacts(t, "streamer.com"), vec!["billing@mail.streamer.com".to_string(), "support@streamer.com".to_string()]);
    }

    #[test]
    fn cadences_from_gaps() {
        let day = 86_400;
        assert_eq!(cadence(&[0]), Cadence::Once);
        assert_eq!(cadence(&[0, 7 * day, 14 * day]), Cadence::Weekly);
        assert_eq!(cadence(&[0, 365 * day]), Cadence::Yearly);
        assert_eq!(cadence(&[0, 50 * day, 300 * day]), Cadence::Irregular);
    }
}

/// One relationship as the tally file holds it, with the owner's decision.
#[derive(Debug, Clone, serde::Deserialize)]
pub struct Decided {
    pub domain: String,
    pub merchant: String,
    pub kind: String,
    #[serde(default)]
    pub cards: Vec<String>,
    #[serde(default)]
    pub to: Vec<String>,
    #[serde(default)]
    pub contacts: Vec<String>,
    /// "keep", "cancel", or null while undecided.
    pub decision: Option<String>,
}

/// A notice to send: the batch `mailbox send` takes.
#[derive(Debug, Clone, serde::Serialize, PartialEq)]
pub struct Notice {
    pub from: String,
    pub to: String,
    pub subject: String,
    pub body: String,
}

/// The cancellation notice for a relationship the owner marked "cancel",
/// to its first human contact: cancel, stop renewing, revoke every
/// payment authorization, delete stored payment details, confirm in
/// writing. None when it is not marked cancel or no contact is known.
pub fn notice(d: &Decided, from: &str, name: &str, date: &str) -> Option<Notice> {
    if d.decision.as_deref() != Some("cancel") {
        return None;
    }
    let to = d.contacts.first()?.clone();
    let what = match d.kind.as_str() {
        "bill" => "service",
        "subscription" => "subscription or membership",
        _ => "recurring service",
    };
    let accounts = if d.to.is_empty() { String::new() } else { format!(" (the account registered to {})", d.to.join(", ")) };
    let cards = if d.cards.is_empty() {
        "any payment method you hold on file for me".to_string()
    } else {
        format!("every payment method you hold on file for me, including {}", d.cards.join(", "))
    };
    let body = format!(
        "To {merchant},\n\n\
         I am the holder of my account with you{accounts}.\n\n\
         Effective immediately, please cancel my {what} and any automatic renewal, and stop every recurring \
         charge. I revoke my authorization for you to charge {cards}, for any amount, from today. Please also \
         delete my stored payment details.\n\n\
         Please confirm in writing, by reply to this address, that the {what} is cancelled, the date it took \
         effect, and that no further charges will be made.\n\n\
         {name}\n{from}\n{date}\n",
        merchant = d.merchant,
    );
    Some(Notice {
        from: from.to_string(),
        to,
        subject: format!("Cancellation and revocation of recurring payment authorization: {}", d.merchant),
        body,
    })
}

#[cfg(test)]
mod notice_tests {
    use super::*;

    fn decided(decision: Option<&str>, contacts: &[&str]) -> Decided {
        Decided {
            domain: "streamer.com".into(),
            merchant: "Streamer".into(),
            kind: "subscription".into(),
            cards: vec!["chase 1234".into()],
            to: vec!["owner@example.org".into()],
            contacts: contacts.iter().map(|c| c.to_string()).collect(),
            decision: decision.map(str::to_string),
        }
    }

    #[test]
    fn only_cancelled_relationships_with_a_contact_get_a_notice() {
        assert!(notice(&decided(Some("keep"), &["support@streamer.com"]), "a@b.c", "A B", "2026-11-08").is_none());
        assert!(notice(&decided(None, &["support@streamer.com"]), "a@b.c", "A B", "2026-11-08").is_none());
        assert!(notice(&decided(Some("cancel"), &[]), "a@b.c", "A B", "2026-11-08").is_none());
        let n = notice(&decided(Some("cancel"), &["support@streamer.com"]), "a@b.c", "A B", "2026-11-08").unwrap();
        assert_eq!(n.to, "support@streamer.com");
        assert!(n.body.contains("revoke my authorization"));
        assert!(n.body.contains("chase 1234"));
        assert!(n.body.contains("owner@example.org"));
        assert!(n.body.contains("confirm in writing"));
    }
}
