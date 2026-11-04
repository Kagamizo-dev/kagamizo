//! The relay's rule and the shaping of what it relays, pure: what
//! ../_lean/Relay.lean states and proves, implemented here and unit-tested.

use serde::Deserialize;

/// A Discord snowflake: digits only, checked once at configuration.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Id(String);

impl Id {
    pub fn parse(name: &str, s: &str) -> Result<Id, String> {
        if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
            return Err(format!("{name}: a Discord id is digits only"));
        }
        Ok(Id(s.to_owned()))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Deserialize)]
pub struct Author {
    pub id: String,
    #[serde(default)]
    pub bot: bool,
}

#[derive(Debug, Deserialize)]
pub struct Attachment {
    pub filename: String,
    pub url: String,
}

/// A Discord MESSAGE_CREATE, the fields the relay reads.
#[derive(Debug, Deserialize)]
pub struct Message {
    pub channel_id: String,
    pub author: Author,
    #[serde(default)]
    pub content: String,
    #[serde(default)]
    pub attachments: Vec<Attachment>,
}

/// The rule (Relay.lean `relayed`): only the owner's messages, only in the
/// declared channel, and never a bot's.
pub fn relayed(m: &Message, owner: &Id, channel: &Id) -> bool {
    m.author.id == owner.0 && m.channel_id == channel.0 && !m.author.bot
}

/// What reaches Matrix: the text, then one line per attachment (its name
/// and URL). None when there is nothing to say (a sticker, an embed only).
pub fn matrix_body(m: &Message) -> Option<String> {
    let mut lines: Vec<String> = Vec::new();
    let text = m.content.trim();
    if !text.is_empty() {
        lines.push(text.to_owned());
    }
    for a in &m.attachments {
        lines.push(format!("{} {}", a.filename, a.url));
    }
    if lines.is_empty() {
        None
    } else {
        Some(lines.join("\n"))
    }
}

/// Discord takes 2000 characters a message: longer replies go in pieces,
/// split at a line break where one is near.
pub fn discord_chunks(body: &str) -> Vec<String> {
    const MAX: usize = 2000;
    let mut out = Vec::new();
    let mut rest = body.trim_end();
    while rest.chars().count() > MAX {
        let hard: usize = rest.char_indices().nth(MAX).map(|(i, _)| i).unwrap_or(rest.len());
        let cut = rest[..hard].rfind('\n').filter(|&i| i > hard / 2).unwrap_or(hard);
        out.push(rest[..cut].trim_end().to_owned());
        rest = rest[cut..].trim_start();
    }
    if !rest.is_empty() {
        out.push(rest.to_owned());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(author: &str, channel: &str, bot: bool, content: &str, files: &[(&str, &str)]) -> Message {
        Message {
            channel_id: channel.into(),
            author: Author { id: author.into(), bot },
            content: content.into(),
            attachments: files.iter().map(|(f, u)| Attachment { filename: (*f).into(), url: (*u).into() }).collect(),
        }
    }

    #[test]
    fn ids_are_digits() {
        assert!(Id::parse("x", "123").is_ok());
        assert!(Id::parse("x", "").is_err());
        assert!(Id::parse("x", "12a").is_err());
        assert!(Id::parse("x", "-1").is_err());
    }

    #[test]
    fn only_the_owner_in_the_channel() {
        let owner = Id("1".into());
        let chan = Id("9".into());
        assert!(relayed(&msg("1", "9", false, "hi", &[]), &owner, &chan));
        assert!(!relayed(&msg("2", "9", false, "hi", &[]), &owner, &chan));
        assert!(!relayed(&msg("1", "8", false, "hi", &[]), &owner, &chan));
        assert!(!relayed(&msg("1", "9", true, "hi", &[]), &owner, &chan));
    }

    #[test]
    fn body_has_text_then_attachments() {
        let m = msg("1", "9", false, "  look  ", &[("note.ogg", "https://cdn/x.ogg")]);
        assert_eq!(matrix_body(&m).as_deref(), Some("look\nnote.ogg https://cdn/x.ogg"));
        assert_eq!(matrix_body(&msg("1", "9", false, " ", &[])), None);
        let m = msg("1", "9", false, "", &[("a.mp4", "https://cdn/a"), ("b.jpg", "https://cdn/b")]);
        assert_eq!(matrix_body(&m).as_deref(), Some("a.mp4 https://cdn/a\nb.jpg https://cdn/b"));
    }

    #[test]
    fn chunks_fit_discord() {
        assert_eq!(discord_chunks("short"), vec!["short"]);
        assert!(discord_chunks("   ").is_empty());
        let long = format!("{}\n{}", "a".repeat(1500), "é".repeat(1500));
        let parts = discord_chunks(&long);
        assert_eq!(parts, vec!["a".repeat(1500), "é".repeat(1500)]);
        let solid = "x".repeat(4500);
        let parts = discord_chunks(&solid);
        assert_eq!(parts.iter().map(|p| p.chars().count()).collect::<Vec<_>>(), vec![2000, 2000, 500]);
        assert!(parts.iter().all(|p| p.chars().count() <= 2000));
    }
}
