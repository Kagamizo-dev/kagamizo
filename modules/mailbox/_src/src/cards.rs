//! Mailbox cards (../../cards.nix): a card hands one team the mail to one
//! address, from the senders it names, for what it says, until it expires.
//! Bridge serves the whole mailbox to this machine, so the scope is held
//! here: a message a card does not admit is never written out, and a holder
//! is given this program's output, never the mailbox.
use serde::Deserialize;
use std::collections::BTreeMap;

const DECLARED: &str = include_str!(env!("MAILBOX_CARDS"));

#[derive(Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum May {
    /// Who wrote, when, and the subject.
    Headers,
    /// The text of the message as well.
    Bodies,
    /// Prepare a reply as a draft; nothing is sent.
    Draft,
    /// Send. No card may yet (./_lean/Cards.lean).
    Send,
}

#[derive(Deserialize, Clone, Debug)]
pub struct Card {
    pub address: String,
    /// Sender domains the holder may see; empty is any.
    pub from: Vec<String>,
    pub may: Vec<May>,
    /// The team it is handed to.
    pub holder: String,
    /// The last day it is good for, YYYY-MM-DD.
    pub until: String,
}

pub fn declared() -> BTreeMap<String, Card> {
    serde_json::from_str(DECLARED).expect("the cards are rendered by cards.nix")
}

/// A day as YYYY-MM-DD, from seconds since 1970 (Howard Hinnant's
/// civil-from-days), so a card's last day compares as text.
pub fn day(secs: u64) -> String {
    let z = (secs / 86_400) as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

/// The addresses in a header's value, lower case.
fn addresses(value: &str) -> Vec<String> {
    value
        .split([',', ';'])
        .filter_map(|part| {
            let inner = part.rsplit('<').next()?.split('>').next()?.trim().trim_matches('"');
            inner.contains('@').then(|| inner.to_lowercase())
        })
        .collect()
}

fn host(address: &str) -> &str {
    address.rsplit('@').next().unwrap_or("")
}

/// Who may ask for a card's mail: the holder, as an agent, or a person (the
/// owner), whose mail it is.
pub fn may_ask(card: &Card, principal: Option<&str>) -> Result<(), String> {
    match principal.and_then(|p| p.strip_prefix("agent:")) {
        Some(agent) if agent != card.holder => Err(format!("the card is held by {}, not by {agent}", card.holder)),
        _ => Ok(()),
    }
}

/// Whether the card admits a message, by its headers, on a day.
pub fn admits(card: &Card, raw: &[u8], today: &str) -> Result<(), &'static str> {
    if today > card.until.as_str() {
        return Err("the card has expired");
    }
    let (headers, _) = mailparse::parse_headers(raw).map_err(|_| "the headers do not parse")?;
    let values = |key: &str| -> Vec<String> { headers.iter().filter(|h| h.get_key().eq_ignore_ascii_case(key)).map(|h| h.get_value()).collect() };
    let to: Vec<String> = ["to", "cc", "delivered-to", "x-original-to"].iter().flat_map(|k| values(k)).flat_map(|v| addresses(&v)).collect();
    if !to.contains(&card.address.to_lowercase()) {
        return Err("not addressed to the card's address");
    }
    if card.from.is_empty() {
        return Ok(());
    }
    let senders: Vec<String> = values("from").iter().flat_map(|v| addresses(v)).collect();
    let allowed = |sender: &String| card.from.iter().any(|d| host(sender) == d || host(sender).ends_with(&format!(".{d}")));
    if senders.is_empty() || !senders.iter().all(allowed) {
        return Err("not from a sender the card names");
    }
    Ok(())
}

fn text_of(part: &mailparse::ParsedMail) -> Option<String> {
    if part.subparts.is_empty() {
        return (part.ctype.mimetype == "text/plain").then(|| part.get_body().ok()).flatten();
    }
    part.subparts.iter().find_map(text_of)
}

/// The most of a message's text a card passes on.
const BODY_LIMIT: usize = 20_000;

/// What the holder is given of an admitted message: its headers, and its
/// text only where the card says so.
pub fn view(card: &Card, raw: &[u8]) -> Option<serde_json::Value> {
    let mail = mailparse::parse_mail(raw).ok()?;
    let get = |key: &str| mail.headers.iter().find(|h| h.get_key().eq_ignore_ascii_case(key)).map(|h| h.get_value()).unwrap_or_default();
    let mut out = serde_json::json!({ "from": get("from"), "date": get("date"), "subject": get("subject") });
    if card.may.contains(&May::Bodies) {
        let text = text_of(&mail).unwrap_or_default();
        out["body"] = text.chars().take(BODY_LIMIT).collect::<String>().into();
    }
    Some(out)
}

/// The most of a reply a card drafts.
const DRAFT_LIMIT: usize = 10_000;

/// A reply a card's holder prepares: from the card's address, to someone
/// who wrote to it (by the mail the card's read gave, one JSON object a
/// line), as one entry of a batch. Nothing is sent: a batch leaves only
/// when the owner has approved it by its digest.
pub fn draft(card: &Card, mail: &str, to: &str, subject: &str, body: &str) -> Result<serde_json::Value, String> {
    if !card.may.contains(&May::Draft) {
        return Err("the card does not let its holder draft".into());
    }
    let to = to.trim().to_lowercase();
    let wrote = mail
        .lines()
        .filter_map(|l| serde_json::from_str::<serde_json::Value>(l).ok())
        .filter_map(|v| v["from"].as_str().map(addresses))
        .flatten()
        .any(|a| a == to);
    if !wrote {
        return Err(format!("{to} has not written to {}: a card replies, it does not write first", card.address));
    }
    if subject.trim().is_empty() || subject.contains(['\r', '\n']) {
        return Err("the subject is empty or runs over a line".into());
    }
    if body.trim().is_empty() || body.chars().count() > DRAFT_LIMIT {
        return Err(format!("the body is empty or over {DRAFT_LIMIT} characters"));
    }
    Ok(serde_json::json!({ "from": card.address, "to": to, "subject": subject.trim(), "body": body }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn card(from: &[&str], may: &[May]) -> Card {
        Card { address: "receipts@jingzo.org".into(), from: from.iter().map(|s| s.to_string()).collect(), may: may.to_vec(), holder: "accounting-jingzo".into(), until: "2027-01-31".into() }
    }

    fn mail(from: &str, to: &str) -> Vec<u8> {
        format!("From: {from}\r\nTo: {to}\r\nDate: Mon, 02 Nov 2026 10:00:00 +0000\r\nSubject: Your receipt\r\nContent-Type: text/plain\r\n\r\nYou paid 20 dollars.\r\n").into_bytes()
    }

    #[test]
    fn every_declared_card_is_one_this_reader_can_hold_to() {
        for (name, c) in declared() {
            assert!(c.address.contains('@'), "{name}");
            assert_eq!(c.until.len(), 10, "{name}");
            assert!(!c.may.is_empty(), "{name}");
            assert!(!c.may.contains(&May::Send), "{name}: no card may send yet");
        }
    }

    #[test]
    fn a_day_is_the_calendar_s() {
        assert_eq!(day(0), "1970-01-01");
        assert_eq!(day(1_794_614_400), "2026-11-14");
        assert_eq!(day(951_782_400), "2000-02-29");
    }

    #[test]
    fn a_card_admits_only_mail_to_its_own_address() {
        let c = card(&[], &[May::Headers]);
        assert_eq!(admits(&c, &mail("Shop <billing@shop.com>", "Receipts <Receipts@Jingzo.org>"), "2026-11-14"), Ok(()));
        assert_eq!(admits(&c, &mail("billing@shop.com", "finance@jingzo.org, receipts@jingzo.org"), "2026-11-14"), Ok(()));
        assert_eq!(admits(&c, &mail("billing@shop.com", "finance@jingzo.org"), "2026-11-14"), Err("not addressed to the card's address"));
        assert_eq!(admits(&c, &mail("billing@shop.com", "xreceipts@jingzo.org"), "2026-11-14"), Err("not addressed to the card's address"));
    }

    #[test]
    fn a_card_that_names_senders_admits_only_them() {
        let c = card(&["mercury.com"], &[May::Headers]);
        assert_eq!(admits(&c, &mail("hello@mercury.com", "receipts@jingzo.org"), "2026-11-14"), Ok(()));
        assert_eq!(admits(&c, &mail("no-reply@mail.mercury.com", "receipts@jingzo.org"), "2026-11-14"), Ok(()));
        assert_eq!(admits(&c, &mail("hello@notmercury.com", "receipts@jingzo.org"), "2026-11-14"), Err("not from a sender the card names"));
        assert_eq!(admits(&c, &mail("hello@mercury.com.evil.org", "receipts@jingzo.org"), "2026-11-14"), Err("not from a sender the card names"));
    }

    #[test]
    fn an_expired_card_admits_nothing() {
        let c = card(&[], &[May::Headers]);
        let m = mail("billing@shop.com", "receipts@jingzo.org");
        assert_eq!(admits(&c, &m, "2027-01-31"), Ok(()));
        assert_eq!(admits(&c, &m, "2027-02-01"), Err("the card has expired"));
    }

    #[test]
    fn the_text_is_passed_on_only_where_the_card_says() {
        let m = mail("billing@shop.com", "receipts@jingzo.org");
        let headers = view(&card(&[], &[May::Headers]), &m).unwrap();
        assert_eq!(headers["subject"], "Your receipt");
        assert!(headers.get("body").is_none());
        let bodies = view(&card(&[], &[May::Headers, May::Bodies]), &m).unwrap();
        assert!(bodies["body"].as_str().unwrap().contains("You paid 20 dollars."));
    }

    #[test]
    fn a_card_drafts_only_a_reply_and_only_if_it_may() {
        let mail = "{\"from\":\"Shop <billing@shop.com>\",\"date\":\"\",\"subject\":\"Your receipt\"}\n";
        let may = card(&[], &[May::Headers, May::Draft]);
        let d = draft(&may, mail, "Billing@Shop.com", "Re: Your receipt", "Please send the invoice as a PDF.").unwrap();
        assert_eq!(d["from"], "receipts@jingzo.org");
        assert_eq!(d["to"], "billing@shop.com");
        assert!(draft(&may, mail, "stranger@else.org", "Hello", "x").unwrap_err().contains("has not written"));
        assert!(draft(&may, mail, "billing@shop.com", "Two\nlines", "x").is_err());
        assert!(draft(&may, mail, "billing@shop.com", "Re", " ").is_err());
        assert!(draft(&card(&[], &[May::Headers]), mail, "billing@shop.com", "Re", "x").unwrap_err().contains("does not let"));
    }

    #[test]
    fn only_the_holder_or_a_person_may_ask() {
        let c = card(&[], &[May::Headers]);
        assert!(may_ask(&c, Some("agent:accounting-jingzo")).is_ok());
        assert!(may_ask(&c, Some("agent:research-jingzo")).is_err());
        assert!(may_ask(&c, Some("person:zachariah")).is_ok());
        assert!(may_ask(&c, None).is_ok());
    }
}
