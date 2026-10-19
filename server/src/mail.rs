//! Email to a note (docs/MAIL.md): each account may turn on a private address, and mail sent to it becomes a note in
//! the person's Inbox.
//!
//! This is the one place the service sees words of a person's in the clear, and the setting says so in as many words.
//! A mail arrives from the mail provider as plain MIME, as all mail arrives at whoever receives it. In the same request
//! it is read (src/mail/message.rs), sealed to the account's encryption PUBLIC key (src/mail/seal.rs, ECIES as an
//! organization key is wrapped), and only the sealed copy is kept; the clear copy is never written, logged or kept past
//! the answer, and the buffers holding it are wiped. The next time a device of the account syncs it opens the mail
//! with the account's private key, which never leaves the account's devices, files the note through the normal path,
//! and deletes the sealed copy.
//!
//!   GET    /api/v1/mail/address      the account's address, if on, and whether the service takes mail at all
//!   POST   /api/v1/mail/address      a new address, in place of any old one (which takes no mail from then on)
//!   DELETE /api/v1/mail/address      the address off
//!   GET    /api/v1/mail              what waits, sealed: id, size and when each came (ms)
//!   GET    /api/v1/mail/{id}         one: its wrapped key and its sealed blob
//!   DELETE /api/v1/mail/{id}         taken: its note is filed
//!   POST   /api/v1/mail/inbound/mime what the mail provider posts (src/mail/mailgun.rs), signed
//!
//! An address is `<sixteen letters and digits>@in.ghostmarkdown.com` (`GLYPH_MAIL_DOMAIN`): eighty random bits, so
//! nobody finds one by guessing, on a subdomain of its own, so the mail records it needs touch nothing else of the
//! domain. Mail to a dead address is refused at once (the sender is told). Each address takes thirty mails an hour,
//! a mail is at most 10 MB, and an account keeps at most two hundred waiting for its devices.
//!
//! THE ENVIRONMENT: GLYPH_MAILGUN_SIGNING_KEY (Mailgun's HTTP webhook signing key; unset, the service takes no mail and
//! says so, and no address can be turned on), GLYPH_MAIL_DOMAIN (default `in.ghostmarkdown.com`).

mod mailgun;
pub mod message;
pub mod seal;

use crate::accounts::{Accounts, HasAccounts};
use crate::guard;
use crate::identity::Claims;
use crate::store::{MailWrite, SealedMail};
use crate::wire::{base64url, error, fresh_id, millis, now_secs};
use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::json;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use zeroize::Zeroize;

#[cfg(test)]
pub use mailgun::sign as mailgun_signature;

/// The most a mail may be, raw.
pub const MAIL_LIMIT: usize = 10_000_000;
/// The most the provider's post may be: the mail, form-encoded, which can nearly triple a byte.
const INBOUND_BODY: usize = 32_000_000;
/// The most mails an account keeps waiting, sealed, for its devices.
const WAITING: i64 = 200;
/// Mails an address takes in an hour.
const PER_ADDRESS_PER_HOUR: u32 = 30;
/// How far from now a signature's timestamp may be, in seconds. Mailgun tries again for eight hours.
const SIGNATURE_WINDOW: i64 = 9 * 3600;
/// The most tokens remembered, so a post seen once is not taken twice.
const TOKENS_KEPT: usize = 50_000;
/// An address's local part: sixteen of RFC 4648's base32 alphabet, lower-cased (eighty bits).
const LOCAL_LENGTH: usize = 16;
const ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";

/// What the service needs to take mail: the domain addresses are on, and the provider's signing key.
#[derive(Clone)]
pub struct MailConfig {
    pub domain: String,
    pub signing_key: Option<String>,
}

/// The signing key the tests sign with (`MailConfig::for_tests`).
#[cfg(test)]
pub const TEST_SIGNING_KEY: &str = "key-test-0123456789abcdef0123456789";

impl MailConfig {
    #[cfg_attr(test, allow(dead_code))]
    pub fn from_env() -> Self {
        let domain = std::env::var("GLYPH_MAIL_DOMAIN").ok().map(|d| d.trim().to_ascii_lowercase()).filter(|d| !d.is_empty()).unwrap_or_else(|| "in.ghostmarkdown.com".into());
        // A key too short to be Mailgun's is no key: better no mail than mail anyone could sign.
        let signing_key = std::env::var("GLYPH_MAILGUN_SIGNING_KEY").ok().map(|k| k.trim().to_string()).filter(|k| k.len() >= 16);
        MailConfig { domain, signing_key }
    }

    #[cfg(test)]
    pub fn for_tests() -> Self {
        MailConfig { domain: "in.ghostmarkdown.com".into(), signing_key: Some(TEST_SIGNING_KEY.into()) }
    }
}

pub struct Mail {
    accounts: Arc<Accounts>,
    config: MailConfig,
    per_address: guard::RateLimiter<String>,
    /// Tokens of posts already answered for good, with their timestamps.
    seen: Mutex<HashMap<String, i64>>,
}

impl HasAccounts for Arc<Mail> {
    fn accounts(&self) -> &Accounts {
        &self.accounts
    }
}

impl Mail {
    fn full(&self, local: &str) -> String {
        format!("{local}@{}", self.config.domain)
    }

    /// Whether a post with this token was already answered for good.
    fn seen(&self, token: &str) -> bool {
        self.seen.lock().map(|seen| seen.contains_key(token)).unwrap_or(true)
    }

    /// Remembers a token answered for good, forgetting those too old to be signed still.
    fn remember(&self, token: &str, now: i64) {
        let Ok(mut seen) = self.seen.lock() else { return };
        if seen.len() >= TOKENS_KEPT {
            seen.retain(|_, at| now - *at <= SIGNATURE_WINDOW);
        }
        if seen.len() < TOKENS_KEPT {
            seen.insert(token.to_string(), now);
        }
    }

    /// The local parts of `recipient` on this service's domain, lower-cased, a `+tag` dropped, each once.
    fn locals(&self, recipient: &str) -> Vec<String> {
        let suffix = format!("@{}", self.config.domain);
        let mut out: Vec<String> = Vec::new();
        for one in recipient.split(',') {
            let one = one.trim();
            let one = one.rsplit('<').next().unwrap_or(one).trim_end_matches('>').trim().to_ascii_lowercase();
            let Some(local) = one.strip_suffix(&suffix) else { continue };
            let local = local.split('+').next().unwrap_or(local);
            if local.len() == LOCAL_LENGTH && local.bytes().all(|b| ALPHABET.contains(&b)) && !out.iter().any(|o| o == local) {
                out.push(local.to_string());
            }
        }
        out
    }
}

fn new_local() -> String {
    rand::random::<[u8; LOCAL_LENGTH]>().iter().map(|b| ALPHABET[(*b & 31) as usize] as char).collect()
}

async fn get_address(State(mail): State<Arc<Mail>>, who: Claims) -> Response {
    let address = mail.accounts.store.mail_address_of(who.sub).map(|local| mail.full(&local));
    Json(json!({ "address": address, "available": mail.config.signing_key.is_some() })).into_response()
}

async fn new_address(State(mail): State<Arc<Mail>>, who: Claims) -> Response {
    if mail.config.signing_key.is_none() {
        return error(StatusCode::SERVICE_UNAVAILABLE, "Email to a note is not set up on this service yet.");
    }
    // Mail is sealed to the account's encryption key on arrival, so there must be one to seal it to.
    if mail.accounts.store.account_key(who.sub).is_none() {
        return error(StatusCode::CONFLICT, "Your account needs its encryption key first. Sync once, then try again.");
    }
    let local = new_local();
    match mail.accounts.store.set_mail_address(who.sub, &local, now_secs()) {
        Ok(()) => Json(json!({ "address": mail.full(&local) })).into_response(),
        Err(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "That address could not be made. Try again."),
    }
}

async fn delete_address(State(mail): State<Arc<Mail>>, who: Claims) -> Response {
    mail.accounts.store.clear_mail_address(who.sub);
    StatusCode::NO_CONTENT.into_response()
}

async fn list_mail(State(mail): State<Arc<Mail>>, who: Claims) -> Response {
    let list: Vec<_> = mail.accounts.store.mail_waiting(who.sub).into_iter().map(|(id, size, at)| json!({ "id": id, "size": size, "at": millis(at) })).collect();
    Json(json!({ "mail": list })).into_response()
}

async fn get_mail(State(mail): State<Arc<Mail>>, Path(id): Path<String>, who: Claims) -> Response {
    let found = if base64url(&id, 1..=64) { mail.accounts.store.mail(who.sub, &id) } else { None };
    match found {
        Some(sealed) => Json(json!({ "id": id, "wrapped": sealed.wrapped, "blob": sealed.blob, "at": millis(sealed.at) })).into_response(),
        None => error(StatusCode::NOT_FOUND, "That mail is not waiting. Another of your devices may have filed it."),
    }
}

async fn delete_mail(State(mail): State<Arc<Mail>>, Path(id): Path<String>, who: Claims) -> Response {
    if base64url(&id, 1..=64) {
        mail.accounts.store.delete_mail(who.sub, &id);
    }
    StatusCode::NO_CONTENT.into_response()
}

/// Refused for good: Mailgun's 406 is "rejected, and not tried again", and the sender is told it bounced.
fn refused(message: &str) -> Response {
    error(StatusCode::NOT_ACCEPTABLE, message)
}

/// `POST v1/mail/inbound/mime`: a mail from the provider. See the header for what happens to it, and in what order.
async fn inbound(State(mail): State<Arc<Mail>>, body: Bytes) -> Response {
    let Some(key) = mail.config.signing_key.as_deref() else {
        return error(StatusCode::SERVICE_UNAVAILABLE, "This service takes no mail.");
    };
    let Some(mut post) = mailgun::Inbound::parse(&body) else {
        return refused("That post is not a mail.");
    };
    let now = now_secs();
    if !post.signed(key, now, SIGNATURE_WINDOW) {
        return error(StatusCode::UNAUTHORIZED, "That post is not signed by the mail provider.");
    }
    if mail.seen(&post.token) {
        return refused("That mail was taken already.");
    }
    let mut to: Vec<(String, i64)> = Vec::new();
    for local in mail.locals(&post.recipient) {
        if let Some(account) = mail.accounts.store.mail_account(&local) {
            if !to.iter().any(|(_, a)| *a == account) {
                to.push((local, account));
            }
        }
    }
    if to.is_empty() {
        mail.remember(&post.token, now);
        return refused("There is no such address.");
    }
    // Counted before the mail is read: a flood is turned away without the service reading a word of it. Answered so
    // the provider tries again later, not refused: a person forwarding forty mails at once loses none of them.
    if !to.iter().all(|(local, _)| mail.per_address.take(local.clone(), Instant::now())) {
        return error(StatusCode::TOO_MANY_REQUESTS, "That address has taken as much mail as it may this hour.");
    }
    if post.mime.len() > MAIL_LIMIT {
        mail.remember(&post.token, now);
        return refused("That mail is too large: Ghost.md takes mail up to 10 MB.");
    }
    let mut kept = 0;
    let mut full = 0;
    for (local, account) in &to {
        let Some(public) = mail.accounts.store.account_key(*account).map(|k| k.pub_key) else { continue };
        // A calendar invite in the mail books Ghost into its Google Meet (src/meet.rs, docs/MEET.md); the mail is a
        // note all the same. Only for an account with a key, as Ghost's recording is sealed to it.
        crate::meet::book_from_mail(&mail.accounts.store, *account, &post.mime, now * 1000);
        let Ok(mut payload) = message::payload(&post.mime, &mail.full(local), now * 1000) else {
            post.mime.zeroize();
            mail.remember(&post.token, now);
            return refused("That mail could not be read.");
        };
        let id = fresh_id();
        let sealed = seal::seal_for(&public, &id, &payload);
        payload.zeroize();
        let Ok((wrapped, blob)) = sealed else { continue };
        match mail.accounts.store.put_mail(*account, &id, &SealedMail { wrapped, blob, at: now }, WAITING) {
            Ok(()) => kept += 1,
            Err(MailWrite::Full) => full += 1,
            Err(MailWrite::Failed) => {}
        }
    }
    post.mime.zeroize();
    if kept == 0 && full > 0 {
        mail.remember(&post.token, now);
        return refused("That mailbox is full: its owner's devices have not synced for a while.");
    }
    if kept == 0 {
        // Nothing could be kept, for a reason of the service's own: the provider tries again.
        return error(StatusCode::SERVICE_UNAVAILABLE, "That mail could not be kept just now.");
    }
    mail.remember(&post.token, now);
    Json(json!({ "kept": kept })).into_response()
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    #[cfg(test)]
    let config = MailConfig::for_tests();
    #[cfg(not(test))]
    let config = MailConfig::from_env();
    let mail = Arc::new(Mail { accounts, config, per_address: guard::RateLimiter::per_hour(PER_ADDRESS_PER_HOUR, Instant::now()), seen: Mutex::new(HashMap::new()) });
    Router::new()
        .route("/api/v1/mail/address", get(get_address).post(new_address).delete(delete_address))
        .route("/api/v1/mail", get(list_mail))
        .route("/api/v1/mail/{id}", get(get_mail).delete(delete_mail))
        .route("/api/v1/mail/inbound/mime", post(inbound).layer(DefaultBodyLimit::max(INBOUND_BODY)))
        .with_state(mail)
}
