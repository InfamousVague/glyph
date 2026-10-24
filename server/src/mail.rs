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
//!   PUT    /api/v1/mail/address      {name}: a name of the person's own in place of the old one, the same way
//!   POST   /api/v1/mail/address/available  {name}: whether that name could be theirs, and if not why
//!   DELETE /api/v1/mail/address      the address off
//!   GET    /api/v1/mail              what waits, sealed: id, size and when each came (ms)
//!   GET    /api/v1/mail/{id}         one: its wrapped key and its sealed blob
//!   DELETE /api/v1/mail/{id}         taken: its note is filed
//!   POST   /api/v1/mail/inbound/mime what the mail provider posts (src/mail/mailgun.rs), signed
//!
//! An address is a readable name, `sneaky_siren33@in.ghostmarkdown.com` (`GLYPH_MAIL_DOMAIN`, src/mail/names.rs), on
//! a subdomain of its own, so the mail records it needs touch nothing else of the domain. Addresses made before the
//! names were sixteen random letters and digits; those still take mail. Mail to a dead address is refused at once (the sender is told). Each address takes thirty mails an hour,
//! a mail is at most 10 MB, and an account keeps at most two hundred waiting for its devices.
//!
//! Or a name of one's own, `matt@in.ghostmarkdown.com` (Matt, 2026-10-24: "i'd like you to add the ability to create
//! our own custom name for the email if the name is available"): 3 to 30 letters, digits and single dots, dashes or
//! underscores between them, lower-cased, nothing reserved and nothing shaped like a name the service makes
//! (names.rs `chosen`). A name is free only if no account has ever had it: an address given up is kept as its
//! account's for good (store/mail.rs), so mail for one person never reaches another. Asking whether a name is free
//! is an answer about everyone's addresses, so it is counted, with the choosing, per account and per client address
//! ([NAMES_PER_HOUR]): enough to try names as one types, too few to walk the namespace. The name rides in the body,
//! not the query, so it stays out of the proxy's access log. A chosen name is a guessable one, as `matt` is: anyone
//! may try mailing it. What reaches it is still sealed on arrival, and it still takes thirty an hour.
//!
//! THE ENVIRONMENT: GLYPH_MAILGUN_SIGNING_KEY (Mailgun's HTTP webhook signing key; unset, the service takes no mail and
//! says so, and no address can be turned on), GLYPH_MAIL_DOMAIN (default `in.ghostmarkdown.com`).

mod mailgun;
pub mod message;
mod names;
pub mod seal;

use crate::accounts::{Accounts, HasAccounts};
use crate::guard;
use crate::identity::Claims;
use crate::live::Poke;
use crate::store::{MailClaim, MailStanding, MailWrite, SealedMail};
use crate::wire::{base64url, error, fresh_id, millis, now_secs};
use axum::body::Bytes;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, State};
use axum::http::header::CONTENT_TYPE;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::json;
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
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
/// The local part addresses had before the readable names: sixteen of RFC 4648's base32 alphabet, lower-cased.
/// None is made any more, but those already given out still take mail.
const LOCAL_LENGTH: usize = 16;
/// How many names a new address tries before giving up: a name already taken is the only reason to try again.
const NAME_TRIES: usize = 8;
const ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";
/// Names an account may ask about, or choose, in an hour: the app asks once a pause in typing (400 ms), so sixty is
/// a good many names tried, and one a minute after that. Twice that from one client address, for a household or an
/// office behind one, so many accounts made to share the hour still meet one bucket.
pub const NAMES_PER_HOUR: u32 = 60;
const NAMES_PER_ADDRESS_PER_HOUR: u32 = 2 * NAMES_PER_HOUR;

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
    /// Names asked about or chosen, per account and per client address ([NAMES_PER_HOUR]).
    names_by_account: guard::RateLimiter<i64>,
    names_by_client: guard::RateLimiter<IpAddr>,
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
            let old = local.len() == LOCAL_LENGTH && local.bytes().all(|b| ALPHABET.contains(&b));
            // A made name, or one of a person's own (its shape: whether it is anyone's is the store's to say).
            if (old || names::is_readable(local) || names::shaped(local)) && !out.iter().any(|o| o == local) {
                out.push(local.to_string());
            }
        }
        out
    }
}


async fn get_address(State(mail): State<Arc<Mail>>, who: Claims) -> Response {
    let address = mail.accounts.store.mail_address_of(who.sub).map(|local| mail.full(&local));
    Json(json!({ "address": address, "available": mail.config.signing_key.is_some() })).into_response()
}

/// What an address needs before the account may have one: a service that takes mail, and the account's encryption
/// key, since mail is sealed to it on arrival.
fn ready_for_an_address(mail: &Mail, who: &Claims) -> Option<Response> {
    if mail.config.signing_key.is_none() {
        return Some(error(StatusCode::SERVICE_UNAVAILABLE, "Email to a note is not set up on this service yet."));
    }
    if mail.accounts.store.account_key(who.sub).is_none() {
        return Some(error(StatusCode::CONFLICT, "Your account needs its encryption key first. Sync once, then try again."));
    }
    None
}

async fn new_address(State(mail): State<Arc<Mail>>, who: Claims) -> Response {
    if let Some(refused) = ready_for_an_address(&mail, &who) {
        return refused;
    }
    // A name anyone has or had, this account's own included (a new one is asked for), is passed over; one taken in
    // the moment between is refused by the table's key and its transaction undone, so the account keeps its old
    // address, and another name is tried.
    for _ in 0..NAME_TRIES {
        let local = names::readable();
        if mail.accounts.store.mail_address_standing(who.sub, &local) != Some(MailStanding::Free) {
            continue;
        }
        if mail.accounts.store.set_mail_address(who.sub, &local, now_secs()).is_ok() {
            return Json(json!({ "address": mail.full(&local) })).into_response();
        }
    }
    error(StatusCode::INTERNAL_SERVER_ERROR, "That address could not be made. Try again.")
}

#[derive(Deserialize)]
struct NameBody {
    name: String,
}

/// A name refused, with the word the app says it by: `{ error, reason }`.
fn unfit(status: StatusCode, reason: &str, words: &str) -> Response {
    (status, Json(json!({ "error": words, "reason": reason }))).into_response()
}

const TAKEN: &str = "That name is taken.";
const YOURS: &str = "That is your address already.";

impl Mail {
    /// One name asked about or chosen by `who` from `peer`, counted against both; refused with a 429 when either
    /// hour is spent.
    fn count_name(&self, who: &Claims, peer: IpAddr, headers: &HeaderMap) -> Option<Response> {
        let now = Instant::now();
        let by_account = self.names_by_account.take(who.sub, now);
        let by_client = self.names_by_client.take(guard::client_ip_of(peer, headers), now);
        if by_account && by_client {
            None
        } else {
            Some(error(StatusCode::TOO_MANY_REQUESTS, "Too many names tried in an hour. Try again later."))
        }
    }
}

/// `POST v1/mail/address/available {name}`: whether the name could be the account's, as
/// `{ name, available, reason, message }` - `name` as it would be kept, `reason` one of names.rs's codes or `taken`
/// or `yours`, `message` its words; both null when it is free.
async fn name_available(State(mail): State<Arc<Mail>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, who: Claims, Json(body): Json<NameBody>) -> Response {
    if let Some(refused) = mail.count_name(&who, peer.ip(), &headers) {
        return refused;
    }
    let name = names::normal(&body.name);
    let (reason, message) = match names::chosen(&name) {
        Some(unfit) => (Some(unfit.code()), Some(unfit.words())),
        None => match mail.accounts.store.mail_address_standing(who.sub, &name) {
            Some(MailStanding::Free) => (None, None),
            Some(MailStanding::Yours) => (Some("yours"), Some(YOURS)),
            Some(MailStanding::Taken) => (Some("taken"), Some(TAKEN)),
            None => return error(StatusCode::INTERNAL_SERVER_ERROR, "That name could not be looked up just now."),
        },
    };
    Json(json!({ "name": name, "available": reason.is_none(), "reason": reason, "message": message })).into_response()
}

/// `PUT v1/mail/address {name}`: the name in place of the account's address, exactly as a new one is made (the old
/// one dead at once, and kept as the account's), or refused: 400 with the reason it may not be anyone's, 409 `taken`
/// when it is another account's, and the refusals a new address has.
async fn choose_address(State(mail): State<Arc<Mail>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, who: Claims, Json(body): Json<NameBody>) -> Response {
    if let Some(refused) = ready_for_an_address(&mail, &who) {
        return refused;
    }
    if let Some(refused) = mail.count_name(&who, peer.ip(), &headers) {
        return refused;
    }
    let name = names::normal(&body.name);
    if let Some(why) = names::chosen(&name) {
        return unfit(StatusCode::BAD_REQUEST, why.code(), why.words());
    }
    match mail.accounts.store.set_mail_address(who.sub, &name, now_secs()) {
        Ok(()) => Json(json!({ "address": mail.full(&name) })).into_response(),
        Err(MailClaim::Taken) => unfit(StatusCode::CONFLICT, "taken", TAKEN),
        Err(MailClaim::Failed) => error(StatusCode::INTERNAL_SERVER_ERROR, "That address could not be made. Try again."),
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
async fn inbound(State(mail): State<Arc<Mail>>, headers: HeaderMap, body: Bytes) -> Response {
    let Some(key) = mail.config.signing_key.as_deref() else {
        return error(StatusCode::SERVICE_UNAVAILABLE, "This service takes no mail.");
    };
    let content_type = headers.get(CONTENT_TYPE).and_then(|v| v.to_str().ok());
    let Some(mut post) = mailgun::Inbound::parse_any(&body, content_type) else {
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
        if crate::meet::book_from_mail(&mail.accounts.store, *account, &post.mime, now * 1000) > 0 {
            // Its devices' meetings lists show the booking now (live.rs, POKES).
            mail.accounts.pokes.poke(*account, Poke::Meet);
        }
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
            Ok(()) => {
                kept += 1;
                // Its devices fetch it now rather than at their next pass (live.rs, POKES).
                mail.accounts.pokes.poke(*account, Poke::Mail);
            }
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
    let now = Instant::now();
    let mail = Arc::new(Mail {
        accounts,
        config,
        per_address: guard::RateLimiter::per_hour(PER_ADDRESS_PER_HOUR, now),
        names_by_account: guard::RateLimiter::per_hour(NAMES_PER_HOUR, now),
        names_by_client: guard::RateLimiter::per_hour(NAMES_PER_ADDRESS_PER_HOUR, now),
        seen: Mutex::new(HashMap::new()),
    });
    Router::new()
        .route("/api/v1/mail/address", get(get_address).post(new_address).put(choose_address).delete(delete_address))
        .route("/api/v1/mail/address/available", post(name_available))
        .route("/api/v1/mail", get(list_mail))
        .route("/api/v1/mail/{id}", get(get_mail).delete(delete_mail))
        .route("/api/v1/mail/inbound/mime", post(inbound).layer(DefaultBodyLimit::max(INBOUND_BODY)))
        .with_state(mail)
}
