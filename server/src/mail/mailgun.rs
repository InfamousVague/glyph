//! The one provider-specific part of email to a note (docs/MAIL.md, "Mailgun"): what Mailgun posts, and its signature.
//!
//! A Mailgun route whose action is `forward("https://ghostmarkdown.com/api/v1/mail/inbound/mime")` posts every mail it
//! takes for `*@in.ghostmarkdown.com` here. A forward URL ending in `mime` posts the mail RAW, as
//! `application/x-www-form-urlencoded`, with these fields among others:
//!
//! | field | what it is |
//! |---|---|
//! | `recipient` | the address the mail was sent to, from the SMTP envelope |
//! | `body-mime` | the whole mail, MIME |
//! | `timestamp`, `token`, `signature` | `signature` is the hex HMAC-SHA256 of `timestamp` then `token`, keyed with the account's HTTP webhook signing key |
//!
//! Mailgun's own advice, followed: the timestamp near now, and a token honoured once. Mailgun takes a 200 as kept, a
//! 406 as refused for good, and anything else as "try again later" (for up to eight hours).
//!
//! Another provider that can post raw MIME with an HMAC over it (Cloudflare Email Workers, Postmark's raw field) would
//! be another file beside this one: everything after `Inbound` is the provider's own business no further.

use hmac::{Hmac, Mac};
use sha2::Sha256;
use zeroize::Zeroizing;

/// What Mailgun posts, the parts of it the service reads.
pub struct Inbound {
    pub recipient: String,
    pub mime: Zeroizing<Vec<u8>>,
    pub timestamp: String,
    pub token: String,
    pub signature: String,
}

/// One `x-www-form-urlencoded` value, decoded to bytes: `+` is a space, `%XX` a byte. A raw mail's bytes need not be
/// UTF-8 (an 8-bit Latin-1 part is still a mail), so nothing here is read as text before the MIME parser does.
fn decoded(value: &[u8]) -> Vec<u8> {
    let hex = |b: u8| (b as char).to_digit(16).map(|d| d as u8);
    let mut out = Vec::with_capacity(value.len());
    let mut i = 0;
    while i < value.len() {
        match value[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < value.len() => match (hex(value[i + 1]), hex(value[i + 2])) {
                (Some(h), Some(l)) => {
                    out.push(h << 4 | l);
                    i += 2;
                }
                _ => out.push(b'%'),
            },
            b => out.push(b),
        }
        i += 1;
    }
    out
}

impl Inbound {
    /// The fields out of a posted form; none when one the service needs is not there.
    pub fn parse(body: &[u8]) -> Option<Inbound> {
        let (mut recipient, mut mime, mut timestamp, mut token, mut signature) = (None, None, None, None, None);
        for pair in body.split(|b| *b == b'&') {
            let (name, value) = match pair.iter().position(|b| *b == b'=') {
                Some(at) => (&pair[..at], &pair[at + 1..]),
                None => (pair, &[][..]),
            };
            let text = || String::from_utf8(decoded(value)).ok();
            match decoded(name).as_slice() {
                b"recipient" => recipient = text(),
                b"body-mime" => mime = Some(Zeroizing::new(decoded(value))),
                b"timestamp" => timestamp = text(),
                b"token" => token = text(),
                b"signature" => signature = text(),
                _ => {}
            }
        }
        Some(Inbound { recipient: recipient?, mime: mime?, timestamp: timestamp?, token: token?, signature: signature? })
    }

    /// Whether Mailgun signed this with `key`, within `window` seconds of `now`.
    pub fn signed(&self, key: &str, now: i64, window: i64) -> bool {
        let Ok(at) = self.timestamp.parse::<i64>() else { return false };
        if (now - at).abs() > window || self.token.len() < 16 || self.token.len() > 128 {
            return false;
        }
        let Some(expected) = (0..self.signature.len()).step_by(2).map(|i| self.signature.get(i..i + 2).and_then(|h| u8::from_str_radix(h, 16).ok())).collect::<Option<Vec<u8>>>() else {
            return false;
        };
        let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(key.as_bytes()) else { return false };
        mac.update(self.timestamp.as_bytes());
        mac.update(self.token.as_bytes());
        // `verify_slice` compares in constant time.
        mac.verify_slice(&expected).is_ok()
    }
}

/// The signature Mailgun would send, for the tests.
#[cfg(test)]
pub fn sign(key: &str, timestamp: &str, token: &str) -> String {
    let mut mac = Hmac::<Sha256>::new_from_slice(key.as_bytes()).expect("any length is a key");
    mac.update(timestamp.as_bytes());
    mac.update(token.as_bytes());
    mac.finalize().into_bytes().iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn form(fields: &[(&str, &str)]) -> Vec<u8> {
        let enc = |s: &str| s.bytes().map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect::<String>();
        fields.iter().map(|(k, v)| format!("{}={}", enc(k), enc(v))).collect::<Vec<_>>().join("&").into_bytes()
    }

    #[test]
    fn a_post_is_read_to_bytes_and_its_signature_is_mailgun_s_hmac_of_timestamp_and_token() {
        let key = "key-0123456789abcdef";
        let signature = sign(key, "1791533100", "a-token-from-mailgun-0001");
        let body = form(&[("recipient", "x@in.ghostmarkdown.com"), ("body-mime", "Subject: hi\r\n\r\nCaf\u{e9} + more"), ("timestamp", "1791533100"), ("token", "a-token-from-mailgun-0001"), ("signature", &signature), ("subject", "ignored")]);
        let inbound = Inbound::parse(&body).unwrap();
        assert_eq!(inbound.recipient, "x@in.ghostmarkdown.com");
        assert_eq!(inbound.mime.as_slice(), "Subject: hi\r\n\r\nCaf\u{e9} + more".as_bytes());
        assert!(inbound.signed(key, 1_791_533_100 + 60, 600));
        assert!(!inbound.signed("another key", 1_791_533_100, 600), "another key");
        assert!(!inbound.signed(key, 1_791_533_100 + 601, 600), "too old");
        let mut tampered = Inbound::parse(&body).unwrap();
        tampered.token = "a-token-from-mailgun-0002".into();
        assert!(!tampered.signed(key, 1_791_533_100, 600), "the token is part of what is signed");
        assert!(Inbound::parse(&form(&[("recipient", "x"), ("timestamp", "1")])).is_none(), "a post without the mail is no post");
    }

    #[test]
    fn a_form_value_decodes_plus_and_percent_and_leaves_a_broken_escape_as_it_was() {
        assert_eq!(decoded(b"a+b%2Bc%e9%"), b"a b+c\xe9%");
        assert_eq!(decoded(b"%zz%4"), b"%zz%4");
    }
}
