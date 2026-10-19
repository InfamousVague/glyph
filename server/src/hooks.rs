//! Incoming hooks (docs/INTEGRATIONS.md, "In: a URL that adds to a note"): a URL an account makes, which Zapier, Make,
//! IFTTT or a line of curl posts to, and what is posted becomes words in one of the account's notes.
//!
//!   POST   /api/v1/hooks              { name, note? }  a new hook: its id and, this once, its URL
//!   GET    /api/v1/hooks              the account's hooks, oldest first (no URL: the service no longer has it)
//!   DELETE /api/v1/hooks/{id}         a hook gone; its URL takes nothing from then on
//!   GET    /api/v1/hooks/inbox?after= what was posted, sealed, oldest first, a hundred at a time
//!   DELETE /api/v1/hooks/inbox/{id}   taken: a device has added it to its note
//!   POST   /api/hooks/{token}         the URL itself, with no sign-in: the token is the key
//!
//! A hook's URL is `<GLYPH_PUBLIC_URL>/api/hooks/<token>`, the token 32 random bytes as base64url. Only the token's
//! SHA-256 is kept, so the URL is answered once, when the hook is made, and a hook is found by the hash of what was
//! posted to. Every unknown token, of any shape, is looked up the same way and answered the same 404.
//!
//! A post is JSON `{ note?, text, as?, title? }`, a form with the same fields, or plain text (the whole body is the
//! `text`), at most 32 KB; `as` is `task`, `item`, `paragraph` or `note`, and absent leaves it to the device's own "add
//! to a note". A note not named goes to the hook's default note, or none. In the same request it is sealed to the
//! account's encryption PUBLIC key as `{ hook, note, text, as, title?, at }` (`at` in ms), ECIES exactly as wrap.ts's
//! `wrapFor` wraps an organization key (src/mail/seal.rs `wrap_for`, with the context `hook:<hook id>`), and only the
//! seal is kept: the clear post is never written, logged or kept past the answer, and the buffers holding it are wiped.
//! A device opens it with `unwrapWith(pair, sealed, 'hook:<hook id>')`, adds it, and deletes it.
//!
//! Each hook takes sixty posts a minute; an account keeps at most five hundred waiting, each for thirty days (the sweep,
//! `sweep_every_hour`, started by main.rs), and has at most fifty hooks.
//!
//! THE ENVIRONMENT: GLYPH_PUBLIC_URL (where the service is reached from outside, default `https://ghostmarkdown.com`).

// A refusal here is the response itself, handed straight back from a handler; boxing it would only move it.
#![allow(clippy::result_large_err)]

use crate::accounts::{Accounts, HasAccounts};
use crate::guard;
use crate::identity::Claims;
use crate::mail::seal;
use crate::store::{HookItem, HookRow, HookWrite};
use crate::wire::{base64url, error, fresh_id, millis, now_secs};
use axum::body::Bytes;
use axum::extract::rejection::BytesRejection;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use std::time::{Duration, Instant};
use zeroize::Zeroize;

/// The most a post may be, raw.
pub const POST_LIMIT: usize = 32 * 1024;
/// The most a post may be once it is the payload sealed: its text escaped as JSON can grow, and a seal is kept.
const PAYLOAD_LIMIT: usize = 64 * 1024;
/// Posts a hook takes in a minute.
const PER_HOOK_PER_MINUTE: u32 = 60;
/// The most posts an account keeps waiting, sealed, for its devices.
pub const WAITING: i64 = 500;
/// How long a post waits, in seconds: thirty days.
pub const KEPT_FOR: i64 = 30 * 24 * 3600;
/// The most hooks an account has.
pub const HOOKS_PER_ACCOUNT: i64 = 50;
/// The most posts one page of the inbox carries.
const PAGE: i64 = 100;
/// A hook's name, and a note's title or a post's title, in characters.
const NAME_LIMIT: usize = 100;
const TITLE_LIMIT: usize = 200;
/// What a post may be added as.
const KINDS: &[&str] = &["task", "item", "paragraph", "note"];
/// A token's bytes.
const TOKEN_BYTES: usize = 32;
const DEFAULT_PUBLIC_URL: &str = "https://ghostmarkdown.com";
/// The answer for no account key, worded as the contract words it.
const NO_KEY: &str = "This account has no encryption key yet.";

pub struct Hooks {
    accounts: Arc<Accounts>,
    /// Where the service is reached from outside, without a trailing slash: what a hook's URL starts with.
    public_url: String,
    per_hook: guard::RateLimiter<String>,
}

impl HasAccounts for Arc<Hooks> {
    fn accounts(&self) -> &Accounts {
        &self.accounts
    }
}

/// The context a post is sealed in: wrap.ts binds a wrap to its context as HKDF's info and as AES-GCM's associated
/// data, so a post's seal moved onto another hook opens nothing, nor does an organization's key wrap open as one.
pub fn context(hook: &str) -> String {
    format!("hook:{hook}")
}

/// What a token is kept and found as: its SHA-256, base64url.
fn hashed(token: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(token.as_bytes()))
}

fn new_token() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; TOKEN_BYTES];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let token = URL_SAFE_NO_PAD.encode(bytes);
    bytes.zeroize();
    token
}

/// `s` trimmed, or none when that leaves nothing; `Err` past `limit` characters.
fn trimmed(s: Option<&str>, limit: usize) -> Result<Option<String>, ()> {
    match s.map(str::trim).filter(|s| !s.is_empty()) {
        Some(s) if s.chars().count() > limit => Err(()),
        other => Ok(other.map(str::to_string)),
    }
}

fn hook_json(hook: &HookRow) -> Value {
    json!({ "id": hook.id, "name": hook.name, "note": hook.note, "createdAt": millis(hook.created_at), "lastUsedAt": hook.last_used_at.map(millis) })
}

#[derive(Deserialize)]
struct NewHook {
    name: String,
    #[serde(default)]
    note: Option<String>,
}

async fn make(State(hooks): State<Arc<Hooks>>, who: Claims, Json(body): Json<NewHook>) -> Response {
    let Ok(Some(name)) = trimmed(Some(&body.name), NAME_LIMIT) else {
        return error(StatusCode::BAD_REQUEST, "A hook needs a name of up to 100 characters.");
    };
    let Ok(note) = trimmed(body.note.as_deref(), TITLE_LIMIT) else {
        return error(StatusCode::BAD_REQUEST, "A note's title is at most 200 characters.");
    };
    // What is posted is sealed to the account's encryption key on arrival, so there must be one to seal it to.
    if hooks.accounts.store.account_key(who.sub).is_none() {
        return error(StatusCode::CONFLICT, NO_KEY);
    }
    let token = new_token();
    let hook = HookRow { id: fresh_id(), account: who.sub, name, note, created_at: now_secs(), last_used_at: None };
    match hooks.accounts.store.put_hook(&hook, &hashed(&token), HOOKS_PER_ACCOUNT) {
        Ok(()) => {
            let mut body = hook_json(&hook);
            body["url"] = json!(format!("{}/api/hooks/{token}", hooks.public_url));
            (StatusCode::CREATED, Json(body)).into_response()
        }
        Err(HookWrite::Full) => error(StatusCode::CONFLICT, "This account has as many hooks as it may: delete one first."),
        Err(HookWrite::Failed) => error(StatusCode::INTERNAL_SERVER_ERROR, "That hook could not be made. Try again."),
    }
}

async fn list(State(hooks): State<Arc<Hooks>>, who: Claims) -> Response {
    Json(hooks.accounts.store.hooks_of(who.sub).iter().map(hook_json).collect::<Vec<_>>()).into_response()
}

async fn remove(State(hooks): State<Arc<Hooks>>, Path(id): Path<String>, who: Claims) -> Response {
    if base64url(&id, 1..=64) {
        hooks.accounts.store.delete_hook(who.sub, &id);
    }
    StatusCode::NO_CONTENT.into_response()
}

#[derive(Deserialize)]
struct InboxQuery {
    #[serde(default)]
    after: Option<String>,
}

async fn inbox(State(hooks): State<Arc<Hooks>>, Query(query): Query<InboxQuery>, who: Claims) -> Response {
    let after = query.after.filter(|a| base64url(a, 1..=64));
    let items = hooks.accounts.store.hook_inbox(who.sub, after.as_deref(), PAGE, now_secs() - KEPT_FOR);
    Json(items.iter().map(|i| json!({ "id": i.id, "hook": i.hook, "at": millis(i.at), "sealed": i.sealed })).collect::<Vec<_>>()).into_response()
}

async fn take(State(hooks): State<Arc<Hooks>>, Path(id): Path<String>, who: Claims) -> Response {
    if base64url(&id, 1..=64) {
        hooks.accounts.store.delete_hook_item(who.sub, &id);
    }
    StatusCode::NO_CONTENT.into_response()
}

/// A post as it came, whichever shape it came in.
#[derive(Deserialize)]
struct Posted {
    #[serde(default)]
    note: Option<String>,
    #[serde(default)]
    text: Option<String>,
    #[serde(default, rename = "as")]
    kind: Option<String>,
    #[serde(default)]
    title: Option<String>,
}

impl Drop for Posted {
    fn drop(&mut self) {
        for field in [&mut self.note, &mut self.text, &mut self.kind, &mut self.title].into_iter().flatten() {
            field.zeroize();
        }
    }
}

/// The post out of `body`, read by its content type: JSON, a form, or plain text (the type a post without one is
/// read as). `Err` is the answer.
fn read_post(headers: &HeaderMap, body: &[u8]) -> Result<Posted, Response> {
    let unreadable = || error(StatusCode::BAD_REQUEST, "That post could not be read.");
    let kind = headers.get(header::CONTENT_TYPE).and_then(|v| v.to_str().ok()).unwrap_or("text/plain");
    let kind = kind.split(';').next().unwrap_or("").trim().to_ascii_lowercase();
    match kind.as_str() {
        "application/json" => serde_json::from_slice(body).map_err(|_| unreadable()),
        k if k.starts_with("application/") && k.ends_with("+json") => serde_json::from_slice(body).map_err(|_| unreadable()),
        "application/x-www-form-urlencoded" => serde_urlencoded::from_bytes(body).map_err(|_| unreadable()),
        "text/plain" | "" => match std::str::from_utf8(body) {
            Ok(text) => Ok(Posted { note: None, text: Some(text.to_string()), kind: None, title: None }),
            Err(_) => Err(unreadable()),
        },
        _ => Err(error(StatusCode::UNSUPPORTED_MEDIA_TYPE, "Send JSON, a form, or plain text.")),
    }
}

/// `POST /api/hooks/{token}`: a post to a hook. See the header for what happens to it, and in what order.
async fn posted(State(hooks): State<Arc<Hooks>>, Path(token): Path<String>, headers: HeaderMap, body: Result<Bytes, BytesRejection>) -> Response {
    // Found first, whatever the token's shape, so every unknown one costs the same lookup and gets the same answer.
    let Some(hook) = hooks.accounts.store.hook_by_token(&hashed(&token)) else {
        return error(StatusCode::NOT_FOUND, "There is no such hook.");
    };
    // Counted before the post is read: a flood is turned away without a word of it read.
    if !hooks.per_hook.take(hook.id.clone(), Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "That hook has taken as many posts as it may this minute. Try again shortly.");
    }
    let Ok(body) = body else {
        return error(StatusCode::PAYLOAD_TOO_LARGE, "That post is too large: a hook takes up to 32 KB.");
    };
    let mut body = body.to_vec();
    let post = read_post(&headers, &body);
    body.zeroize();
    let post = match post {
        Ok(post) => post,
        Err(answer) => return answer,
    };
    let Some(text) = post.text.as_deref().filter(|t| !t.trim().is_empty()) else {
        return error(StatusCode::BAD_REQUEST, "That post has no text.");
    };
    let kind = post.kind.as_deref().map(str::trim).filter(|k| !k.is_empty());
    if kind.is_some_and(|k| !KINDS.contains(&k)) {
        return error(StatusCode::BAD_REQUEST, "`as` is task, item, paragraph or note.");
    }
    let (Ok(note), Ok(title)) = (trimmed(post.note.as_deref(), TITLE_LIMIT), trimmed(post.title.as_deref(), TITLE_LIMIT)) else {
        return error(StatusCode::BAD_REQUEST, "A note's title is at most 200 characters.");
    };
    let Some(public) = hooks.accounts.store.account_key(hook.account).map(|k| k.pub_key) else {
        return error(StatusCode::CONFLICT, NO_KEY);
    };
    let now = now_secs();
    let mut payload = json!({ "hook": hook.id, "note": note.or(hook.note.clone()), "text": text, "as": kind, "at": millis(now) });
    if let Some(title) = title {
        payload["title"] = json!(title);
    }
    let mut bytes = serde_json::to_vec(&payload).unwrap_or_default();
    wipe(&mut payload);
    if bytes.len() > PAYLOAD_LIMIT {
        bytes.zeroize();
        return error(StatusCode::PAYLOAD_TOO_LARGE, "That post is too large: a hook takes up to 32 KB.");
    }
    let sealed = seal::wrap_for(&public, &bytes, &context(&hook.id));
    bytes.zeroize();
    let Ok(sealed) = sealed else {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "That post could not be sealed.");
    };
    let id = fresh_id();
    match hooks.accounts.store.put_hook_item(hook.account, &HookItem { id: id.clone(), hook: hook.id, sealed, at: now }, WAITING, now - KEPT_FOR) {
        Ok(()) => (StatusCode::ACCEPTED, Json(json!({ "id": id }))).into_response(),
        Err(HookWrite::Full) => error(StatusCode::INSUFFICIENT_STORAGE, "That inbox is full: its owner's devices have not synced for a while."),
        Err(HookWrite::Failed) => error(StatusCode::SERVICE_UNAVAILABLE, "That post could not be kept just now. Try again."),
    }
}

/// Every string in `value` wiped, before it is dropped: the clear post's copies in the payload.
fn wipe(value: &mut Value) {
    match value {
        Value::String(s) => s.zeroize(),
        Value::Object(map) => map.values_mut().for_each(wipe),
        Value::Array(list) => list.iter_mut().for_each(wipe),
        _ => {}
    }
}

/// Posts thirty days old, of every account, swept every hour from now on (the first at once). A post past its time is
/// never listed in any case (`inbox`); the sweep is so it is not kept either. The same hour sweeps Ghost's Meet bookings
/// (src/meet.rs): a meeting's title and link are blanked an hour after it ended, and the booking goes after thirty days.
#[cfg_attr(test, allow(dead_code))]
pub fn sweep_every_hour(accounts: Arc<Accounts>) {
    tokio::spawn(async move {
        let mut every = tokio::time::interval(Duration::from_secs(3600));
        loop {
            every.tick().await;
            let swept = accounts.store.sweep_hook_inbox(now_secs() - KEPT_FOR);
            if swept > 0 {
                eprintln!("glyph-api swept {swept} hook posts past thirty days");
            }
            let (blanked, gone) = crate::meet::sweep(&accounts.store, now_secs() * 1000);
            if blanked + gone > 0 {
                eprintln!("glyph-api blanked {blanked} Meet bookings over for an hour and deleted {gone} past thirty days");
            }
        }
    });
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    let public_url = std::env::var("GLYPH_PUBLIC_URL").ok().map(|u| u.trim().trim_end_matches('/').to_string()).filter(|u| !u.is_empty()).unwrap_or_else(|| DEFAULT_PUBLIC_URL.into());
    let hooks = Arc::new(Hooks { accounts, public_url, per_hook: guard::RateLimiter::new(PER_HOOK_PER_MINUTE, Instant::now()) });
    Router::new()
        .route("/api/v1/hooks", get(list).post(make))
        .route("/api/v1/hooks/inbox", get(inbox))
        .route("/api/v1/hooks/inbox/{id}", delete(take))
        .route("/api/v1/hooks/{id}", delete(remove))
        .route("/api/hooks/{token}", post(posted).layer(DefaultBodyLimit::max(POST_LIMIT)))
        .with_state(hooks)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_token_is_thirty_two_random_bytes_and_is_kept_as_its_hash() {
        let (a, b) = (new_token(), new_token());
        assert_ne!(a, b);
        assert!(base64url(&a, 43..=43), "{a}");
        assert_eq!(URL_SAFE_NO_PAD.decode(&a).unwrap().len(), 32);
        assert_eq!(hashed(&a), URL_SAFE_NO_PAD.encode(Sha256::digest(a.as_bytes())));
        assert_ne!(hashed(&a), a);
    }

    #[test]
    fn a_title_is_trimmed_empty_is_none_and_too_long_is_refused() {
        assert_eq!(trimmed(Some("  Groceries "), 10), Ok(Some("Groceries".into())));
        assert_eq!(trimmed(Some("   "), 10), Ok(None));
        assert_eq!(trimmed(None, 10), Ok(None));
        assert_eq!(trimmed(Some(&"é".repeat(10)), 10), Ok(Some("é".repeat(10))), "counted in characters, not bytes");
        assert_eq!(trimmed(Some(&"a".repeat(11)), 10), Err(()));
    }
}
