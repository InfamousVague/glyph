//! Mail the service SENDS (Matt, 2026-11-03: "email invites to join orgs on ghost markdown so people can click a link
//! download the app and be redirected on the app to join an org"). The one sender so far is the email invitation
//! (orgs.rs `invite_email`); everything that comes IN is mail.rs's.
//!
//! Through Mailgun's messages API: `POST {base}/v3/{domain}/messages`, basic auth `api:{key}`, a form of `from`, `to`,
//! `subject`, `text` and `html`. The sending domain has to be one Mailgun has verified for sending (its SPF and DKIM
//! records at Gandi); the inbound one, `in.ghostmarkdown.com`, is, since adding a domain in Mailgun asks for both, so
//! it is the default.
//!
//! THE ENVIRONMENT: GLYPH_MAILGUN_API_KEY (a Mailgun sending key, or the account's private API key; unset, nothing is
//! sent and the routes that would send say so with a 503); GLYPH_MAIL_SEND_DOMAIN (the Mailgun domain mail is sent
//! through; default GLYPH_MAIL_DOMAIN's value, else `in.ghostmarkdown.com`); GLYPH_MAIL_FROM (default
//! `Ghost Markdown <invites@{send domain}>`); GLYPH_MAILGUN_API_BASE (default `https://api.mailgun.net`; an EU-region
//! domain is `https://api.eu.mailgun.net`).
//!
//! In the tests the outbox keeps what it was given instead ([Outbox::kept]), and can be told to fail.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;

/// One mail: to one address, its subject, and the same words as plain text and as simple HTML.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Letter {
    pub to: String,
    pub subject: String,
    pub text: String,
    pub html: String,
}

pub enum Outbox {
    /// No key: nothing is sent.
    Off,
    Mailgun { client: reqwest::Client, base: String, domain: String, key: String, from: String },
    /// The tests' outbox: what would have gone, and whether the next sends fail.
    #[cfg_attr(not(test), allow(dead_code))]
    Kept { sent: Mutex<Vec<Letter>>, failing: AtomicBool },
}

impl Outbox {
    #[cfg_attr(test, allow(dead_code))]
    pub fn from_env() -> Self {
        let var = |name: &str| std::env::var(name).ok().map(|v| v.trim().to_string()).filter(|v| !v.is_empty());
        // A key too short to be Mailgun's is no key.
        let Some(key) = var("GLYPH_MAILGUN_API_KEY").filter(|k| k.len() >= 16) else {
            return Outbox::Off;
        };
        let domain = var("GLYPH_MAIL_SEND_DOMAIN").or_else(|| var("GLYPH_MAIL_DOMAIN")).unwrap_or_else(|| "in.ghostmarkdown.com".into()).to_ascii_lowercase();
        let from = var("GLYPH_MAIL_FROM").unwrap_or_else(|| format!("Ghost Markdown <invites@{domain}>"));
        let base = var("GLYPH_MAILGUN_API_BASE").unwrap_or_else(|| "https://api.mailgun.net".into()).trim_end_matches('/').to_string();
        let client = reqwest::Client::builder().connect_timeout(Duration::from_secs(5)).timeout(Duration::from_secs(20)).build().expect("a client");
        Outbox::Mailgun { client, base, domain, key, from }
    }

    /// An outbox that keeps what it is given, for the tests.
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn kept() -> Self {
        Outbox::Kept { sent: Mutex::new(Vec::new()), failing: AtomicBool::new(false) }
    }

    /// Whether anything can be sent at all.
    pub fn ready(&self) -> bool {
        !matches!(self, Outbox::Off)
    }

    /// What the tests' outbox was given, oldest first.
    #[cfg(test)]
    pub fn sent(&self) -> Vec<Letter> {
        match self {
            Outbox::Kept { sent, .. } => sent.lock().map(|s| s.clone()).unwrap_or_default(),
            _ => Vec::new(),
        }
    }

    /// The tests' outbox told to fail its sends, or not.
    #[cfg(test)]
    pub fn fail(&self, failing: bool) {
        if let Outbox::Kept { failing: f, .. } = self {
            f.store(failing, Ordering::SeqCst);
        }
    }

    /// One letter sent. An error is for the log, never for the person asking: it can carry Mailgun's own words.
    pub async fn send(&self, letter: &Letter) -> Result<(), String> {
        match self {
            Outbox::Off => Err("no GLYPH_MAILGUN_API_KEY".into()),
            Outbox::Kept { sent, failing } => {
                if failing.load(Ordering::SeqCst) {
                    return Err("told to fail".into());
                }
                sent.lock().map_err(|_| "poisoned".to_string())?.push(letter.clone());
                Ok(())
            }
            Outbox::Mailgun { client, base, domain, key, from } => {
                let form = [("from", from.as_str()), ("to", letter.to.as_str()), ("subject", letter.subject.as_str()), ("text", letter.text.as_str()), ("html", letter.html.as_str())];
                let answer = client.post(format!("{base}/v3/{domain}/messages")).basic_auth("api", Some(key)).form(&form).send().await.map_err(|e| e.to_string())?;
                if answer.status().is_success() {
                    Ok(())
                } else {
                    let status = answer.status();
                    let words = answer.text().await.unwrap_or_default();
                    Err(format!("Mailgun answered {status}: {}", words.chars().take(200).collect::<String>()))
                }
            }
        }
    }
}

/// Text made safe to put in HTML.
pub fn html_escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn the_tests_outbox_keeps_what_it_is_given_and_fails_when_told() {
        let outbox = Outbox::kept();
        let letter = Letter { to: "a@example.com".into(), subject: "s".into(), text: "t".into(), html: "h".into() };
        outbox.send(&letter).await.unwrap();
        outbox.fail(true);
        assert!(outbox.send(&letter).await.is_err());
        assert_eq!(outbox.sent(), vec![letter]);
        assert!(!Outbox::Off.ready());
    }

    #[test]
    fn html_is_escaped() {
        assert_eq!(html_escape(r#"<a href="x">Tom & 'Jo'</a>"#), "&lt;a href=&quot;x&quot;&gt;Tom &amp; &#39;Jo&#39;&lt;/a&gt;");
    }
}
