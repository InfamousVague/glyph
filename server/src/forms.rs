//! Forms from a share link (docs/FORMS.md): a share that lets anyone with its link fill in a few fields, and a ticket
//! in a notebook for each answer (Matt, 2026-10-30, of a list of plain-Markdown features: "add all 12"; this is the
//! ninth, bug reports and requests from outside the team).
//!
//! A form is a note with a ```form fence, shared as any note is (shares.rs): the share holds its fields, sealed under
//! the key in the link, and the reader page (tauri/src/read/FormRead.tsx) draws the form instead of the note. The
//! device then says the share is a form here, so the service knows to take answers for it:
//!
//!   PUT    /api/v1/forms/{id}               { org?, note?, files?, state? }  the owner's share made a form, or set again
//!   GET    /api/v1/forms                    the forms the account files: its own and its organizations', with counts
//!   POST   /api/v1/forms/{id}/state         { state }  open, paused or closed, by anyone who files it
//!   DELETE /api/v1/forms/{id}               the form gone, with its answers waiting (the share is the device's to take down)
//!   DELETE /api/v1/forms/{id}/answers       every answer waiting deleted, by anyone who files it
//!   GET    /api/v1/forms/inbox?after=       the answers waiting, sealed, oldest first, a hundred at a time
//!   POST   /api/v1/forms/inbox/{id}/claim   { device }  this device files that one: held two minutes, or 409
//!   DELETE /api/v1/forms/inbox/{id}         filed: the answer gone, counted on its form
//!   GET    /api/forms/{id}                  anyone: whether it takes answers, the keys to seal to, and a ticket
//!   POST   /api/forms/{id}                  anyone: an answer, sealed { id, ticket, wraps, blob, hp? }
//!
//! THE SEAL is made in the visitor's browser, so no answer is ever here in the clear: a fresh 32-byte key, the answers
//! as JSON sealed under it as `sealBytes` seals everything synced (a version byte, a fresh IV, AES-256-GCM) with
//! `form:<form id>:<answer id>` as associated data - the `blob`; and that key wrapped to each recipient's encryption
//! PUBLIC key by ECIES exactly as wrap.ts's `wrapFor` wraps an organization key, in the context `form-key:<form
//! id>:<answer id>` - the `wraps`, each `{ to, wrap }`. The recipients are the owner's key, or for a form an
//! organization files every member's who has one; `GET /api/forms/{id}` hands them out. A device opens the wrap made to
//! its account's key with the pair it already has, then the blob (mail/seal.rs is the same two layers, made here).
//! The service checks only the shape: base64url, a version byte, a wrap the length one is with a point on the curve,
//! each made to a recipient - and refuses a body with any other field, so an answer cannot arrive in the clear.
//!
//! AGAINST ABUSE, with no accounts for whoever fills it in: answers are limited per address (twenty an hour) and per
//! form (thirty a minute); a form keeps at most five hundred waiting (fifty for one that takes a file); an answer is at
//! most 64 KB sealed, or 3 MB for a form that takes a file; a hidden field (`hp`) a person never sees is a bot's, and
//! is answered as if it were kept and kept nothing; and the ticket `GET` hands out says when the form was opened,
//! signed with a key of the service's own (`meta`), so an answer sent under three seconds after is turned away, as is
//! one a day old.
//!
//! FILED ONCE: a device lists the inbox, claims an answer (`claim`: held for two minutes by that device alone), files
//! it as a ticket under an id made from the answer's, and says so (`DELETE`): the answer goes, and the form counts it
//! filed. A claim lapsed, the device having stopped, is another's to take; the ticket's id is the same id, so it is
//! still one ticket. Whatever is not filed goes at thirty days (the sweep, `sweep_every_hour`, started by main.rs).

// A refusal here is the response itself, handed straight back from a handler; boxing it would only move it.
#![allow(clippy::result_large_err)]

use crate::accounts::{Accounts, HasAccounts};
use crate::guard;
use crate::identity::Claims;
use crate::store::{FormClaim, FormItem, FormRow, FormState, FormWrite};
use crate::wire::{base64url, error, millis, now_secs};
use axum::body::Bytes;
use axum::extract::rejection::BytesRejection;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use axum::{Json, Router};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hmac::{Hmac, Mac};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::Sha256;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

/// An answer's blob, as base64url: a form's fields, generously.
pub const ANSWER_LIMIT: usize = 64 * 1024;
/// An answer's blob for a form that takes a file: a picture or a log, sealed, of about two megabytes.
pub const FILE_LIMIT: usize = 3_000_000;
/// The body around the blob: the wraps, the ticket and the id.
const BODY_SLACK: usize = 32 * 1024;
/// The most answers a form keeps waiting, and for a form that takes a file.
pub const WAITING: i64 = 500;
pub const WAITING_WITH_FILES: i64 = 50;
/// How long an answer waits, in seconds: thirty days.
pub const KEPT_FOR: i64 = 30 * 24 * 3600;
/// The most forms an account has.
pub const FORMS_PER_ACCOUNT: i64 = 100;
/// Answers per address, an hour; per form, a minute; reads of a form, per address, a minute.
pub const ANSWERS_PER_ADDRESS_PER_HOUR: u32 = 20;
pub const ANSWERS_PER_FORM_PER_MINUTE: u32 = 30;
const OPENS_PER_MINUTE: u32 = 60;
/// How soon after it was opened a form may be sent, and how long after it may still be.
pub const MIN_FILL: i64 = 3;
pub const TICKET_LIFE: i64 = 24 * 3600;
/// How long a device's claim on an answer holds, in seconds.
pub const CLAIM_FOR: i64 = 120;
/// The most recipients an answer is sealed to: an organization's members, with room.
const RECIPIENTS: usize = 64;
/// A wrap of a 32-byte key: the ephemeral point (65), the IV (12), the key and its tag (48), as base64url.
const WRAP_LENGTH: usize = 167;
/// A form's id is its share's (shares.rs); an answer's the browser's, 128 random bits at least.
const ID_LENGTH: std::ops::RangeInclusive<usize> = 22..=64;
const ANSWER_ID_LENGTH: std::ops::RangeInclusive<usize> = 22..=43;
/// The most answers one page of the inbox carries.
const PAGE: i64 = 100;
/// `sealBytes`'s version byte, and the least a sealed blob is: the byte, an IV and a tag.
const VERSION: u8 = 1;
const SEALED_FLOOR: usize = 1 + 12 + 16;
/// Where the key the tickets are signed with is kept (store `meta`).
const TICKET_KEY: &str = "form-ticket-key";
const NO_KEY: &str = "This account has no encryption key yet.";

pub struct Forms {
    accounts: Arc<Accounts>,
    ticket_key: Vec<u8>,
    per_address: guard::RateLimiter,
    per_form: guard::RateLimiter<String>,
    openers: guard::RateLimiter,
}

impl HasAccounts for Arc<Forms> {
    fn accounts(&self) -> &Accounts {
        &self.accounts
    }
}

/// The context an answer's key is wrapped in, and the one its blob is sealed in.
/// (The browser makes both, tauri/src/read/form.ts; here they are what the tests seal and open with.)
#[cfg_attr(not(test), allow(dead_code))]
pub fn wrap_context(form: &str, answer: &str) -> String {
    format!("form-key:{form}:{answer}")
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn seal_context(form: &str, answer: &str) -> String {
    format!("form:{form}:{answer}")
}

/// The key tickets are signed with: kept in the database, so a restart does not turn away a form opened before it;
/// made on first use.
fn ticket_key(accounts: &Accounts) -> Vec<u8> {
    if let Some(kept) = accounts.store.meta(TICKET_KEY).and_then(|k| URL_SAFE_NO_PAD.decode(k).ok()).filter(|k| k.len() == 32) {
        return kept;
    }
    let key: [u8; 32] = rand::random();
    let _ = accounts.store.set_meta(TICKET_KEY, &URL_SAFE_NO_PAD.encode(key));
    key.to_vec()
}

fn mac(key: &[u8], form: &str, issued: i64) -> [u8; 16] {
    let mut mac = Hmac::<Sha256>::new_from_slice(key).expect("HMAC takes a key of any length");
    mac.update(format!("form-ticket:{form}:{issued}").as_bytes());
    let full = mac.finalize().into_bytes();
    let mut out = [0u8; 16];
    out.copy_from_slice(&full[..16]);
    out
}

/// A ticket for `form`, opened at `issued` (seconds): the moment and its MAC, base64url.
pub fn ticket_for(key: &[u8], form: &str, issued: i64) -> String {
    let mut bytes = issued.to_be_bytes().to_vec();
    bytes.extend_from_slice(&mac(key, form, issued));
    URL_SAFE_NO_PAD.encode(bytes)
}

/// What a ticket says, checked: when the form was opened, or `None` for one this service did not sign for this form.
fn ticket_opened(key: &[u8], form: &str, ticket: &str) -> Option<i64> {
    let bytes = URL_SAFE_NO_PAD.decode(ticket).ok().filter(|b| b.len() == 24)?;
    let issued = i64::from_be_bytes(bytes[..8].try_into().ok()?);
    let expected = mac(key, form, issued);
    // In constant time: a guesser learns nothing from how long a wrong ticket took.
    let same = expected.iter().zip(&bytes[8..]).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0;
    same.then_some(issued)
}

fn form_json(form: &FormRow, who: i64) -> Value {
    json!({
        "id": form.id, "org": form.org, "note": form.note, "state": form.state.as_str(), "files": form.files,
        "received": form.received, "waiting": form.waiting, "filed": form.filed,
        "createdAt": millis(form.created_at), "updatedAt": millis(form.updated_at), "mine": form.account == who,
    })
}

fn no_store(mut response: Response) -> Response {
    response.headers_mut().insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

// ---- the owner's ----------------------------------------------------------------------------------------------------

#[derive(Deserialize)]
struct FormBody {
    #[serde(default)]
    org: Option<String>,
    /// The note that defines it: a device's own id for it, as sync names it.
    #[serde(default)]
    note: Option<String>,
    /// Left out, a new form is open and one already made keeps its state: a device saying again which org files it
    /// does not reopen a form someone closed.
    #[serde(default)]
    state: Option<String>,
    #[serde(default)]
    files: bool,
}

async fn put_form(State(forms): State<Arc<Forms>>, Path(id): Path<String>, who: Claims, Json(body): Json<FormBody>) -> Response {
    if !base64url(&id, ID_LENGTH) {
        return error(StatusCode::BAD_REQUEST, "That form's id could not be read.");
    }
    let state = match body.state.as_deref().map(FormState::parse) {
        None => None,
        Some(Some(state)) => Some(state),
        Some(None) => return error(StatusCode::BAD_REQUEST, "A form is open, paused or closed."),
    };
    let note = body.note.filter(|n| !n.is_empty());
    if note.as_deref().is_some_and(|n| !base64url(n, 1..=64)) {
        return error(StatusCode::BAD_REQUEST, "That note's id could not be read.");
    }
    let org = body.org.filter(|o| !o.is_empty());
    if org.as_deref().is_some_and(|o| !base64url(o, 1..=64)) {
        return error(StatusCode::BAD_REQUEST, "That organization's id could not be read.");
    }
    // An answer is sealed to the owner's key, so there must be one; an organization's form, to its members'.
    if org.is_none() && forms.accounts.store.account_key(who.sub).is_none() {
        return error(StatusCode::CONFLICT, NO_KEY);
    }
    match forms.accounts.store.put_form(who.sub, &id, org.as_deref(), note.as_deref(), state, body.files, now_secs(), FORMS_PER_ACCOUNT) {
        Ok(form) => Json(form_json(&form, who.sub)).into_response(),
        Err(FormWrite::NoShare) => error(StatusCode::NOT_FOUND, "There is no share of yours at that link. Share the form first."),
        Err(FormWrite::Taken) => error(StatusCode::CONFLICT, "That form belongs to someone else."),
        Err(FormWrite::NotMember) => error(StatusCode::FORBIDDEN, "You are not in that organization."),
        Err(FormWrite::Full) => error(StatusCode::CONFLICT, "This account has as many forms as it may: delete one first."),
        Err(FormWrite::Failed) => error(StatusCode::INTERNAL_SERVER_ERROR, "That form could not be kept."),
    }
}

async fn list_forms(State(forms): State<Arc<Forms>>, who: Claims) -> Response {
    let list: Vec<_> = forms.accounts.store.forms_for(who.sub, now_secs() - KEPT_FOR).iter().map(|f| form_json(f, who.sub)).collect();
    Json(json!({ "forms": list })).into_response()
}

#[derive(Deserialize)]
struct StateBody {
    state: String,
}

async fn set_state(State(forms): State<Arc<Forms>>, Path(id): Path<String>, who: Claims, Json(body): Json<StateBody>) -> Response {
    let Some(state) = FormState::parse(&body.state) else {
        return error(StatusCode::BAD_REQUEST, "A form is open, paused or closed.");
    };
    if !base64url(&id, ID_LENGTH) {
        return error(StatusCode::NOT_FOUND, "There is no form of yours at that link.");
    }
    match forms.accounts.store.set_form_state(who.sub, &id, state, now_secs()) {
        Some(form) => Json(form_json(&form, who.sub)).into_response(),
        None => error(StatusCode::NOT_FOUND, "There is no form of yours at that link."),
    }
}

async fn delete_form(State(forms): State<Arc<Forms>>, Path(id): Path<String>, who: Claims) -> Response {
    // Another's, or none, answers the same as one's own: nothing to learn by asking.
    if base64url(&id, ID_LENGTH) {
        forms.accounts.store.delete_form(who.sub, &id);
    }
    StatusCode::NO_CONTENT.into_response()
}

async fn clear_answers(State(forms): State<Arc<Forms>>, Path(id): Path<String>, who: Claims) -> Response {
    let deleted = if base64url(&id, ID_LENGTH) { forms.accounts.store.clear_form_items(who.sub, &id) } else { 0 };
    Json(json!({ "deleted": deleted })).into_response()
}

#[derive(Deserialize)]
struct InboxQuery {
    #[serde(default)]
    after: Option<String>,
}

async fn inbox(State(forms): State<Arc<Forms>>, Query(query): Query<InboxQuery>, who: Claims) -> Response {
    let after = query.after.filter(|a| base64url(a, 1..=64));
    let now = now_secs();
    let items = forms.accounts.store.form_inbox(who.sub, after.as_deref(), PAGE, now - KEPT_FOR, now);
    let list: Vec<_> = items
        .iter()
        .map(|i| json!({ "id": i.id, "form": i.form, "note": i.note, "at": millis(i.at), "wraps": serde_json::from_str::<Value>(&i.wraps).unwrap_or(Value::Array(vec![])), "blob": i.blob, "claimed": i.claimed }))
        .collect();
    no_store(Json(list).into_response())
}

#[derive(Deserialize)]
struct ClaimBody {
    device: String,
}

async fn claim(State(forms): State<Arc<Forms>>, Path(id): Path<String>, who: Claims, Json(body): Json<ClaimBody>) -> Response {
    if !base64url(&body.device, 1..=64) {
        return error(StatusCode::BAD_REQUEST, "A claim names the device making it.");
    }
    if !base64url(&id, ANSWER_ID_LENGTH) {
        return error(StatusCode::NOT_FOUND, "That answer is not waiting: it was filed, or it is gone.");
    }
    match forms.accounts.store.claim_form_item(who.sub, &id, &body.device, now_secs(), CLAIM_FOR) {
        FormClaim::Held(until) => Json(json!({ "id": id, "until": millis(until) })).into_response(),
        FormClaim::Elsewhere => error(StatusCode::CONFLICT, "Another device is filing that answer."),
        FormClaim::Gone => error(StatusCode::NOT_FOUND, "That answer is not waiting: it was filed, or it is gone."),
    }
}

async fn filed(State(forms): State<Arc<Forms>>, Path(id): Path<String>, who: Claims) -> Response {
    if base64url(&id, ANSWER_ID_LENGTH) {
        forms.accounts.store.ack_form_item(who.sub, &id);
    }
    StatusCode::NO_CONTENT.into_response()
}

// ---- anyone's -------------------------------------------------------------------------------------------------------

/// What a form's link reads as for a form not open: the state, and nothing to seal to.
fn shut(form: &FormRow) -> Response {
    no_store(Json(json!({ "state": form.state.as_str() })).into_response())
}

async fn open_form(State(forms): State<Arc<Forms>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Path(id): Path<String>) -> Response {
    if !forms.openers.take(guard::client_ip_of(peer.ip(), &headers), Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "Too many forms opened in a minute. Try again shortly.");
    }
    let gone = || error(StatusCode::NOT_FOUND, "There is no form at that link. It may have been taken down.");
    if !base64url(&id, ID_LENGTH) {
        return gone();
    }
    let now = now_secs();
    let Some(form) = forms.accounts.store.form(&id, now - KEPT_FOR) else { return gone() };
    if form.state != FormState::Open {
        return shut(&form);
    }
    let keys = forms.accounts.store.form_recipients(&form);
    let limit = if form.files { FILE_LIMIT } else { ANSWER_LIMIT };
    no_store(Json(json!({ "state": "open", "files": form.files, "keys": keys, "ticket": ticket_for(&forms.ticket_key, &id, now), "wait": MIN_FILL, "limit": limit })).into_response())
}

/// One wrap of an answer's key, as the browser made it.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Wrap {
    to: String,
    wrap: String,
}

/// An answer as it is sent: nothing but its seal, the ticket and the hidden field. Any other field - an answer in the
/// clear - is refused whole.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Answer {
    id: String,
    ticket: String,
    wraps: Vec<Wrap>,
    blob: String,
    #[serde(default)]
    hp: Option<String>,
}

/// Whether `wrap` is one `wrapFor` made of a 32-byte key: its length, and a point on the curve where it starts.
fn wrap_shaped(wrap: &str) -> bool {
    if !base64url(wrap, WRAP_LENGTH..=WRAP_LENGTH) {
        return false;
    }
    URL_SAFE_NO_PAD.decode(wrap).ok().is_some_and(|bytes| bytes.len() == 125 && p256::PublicKey::from_sec1_bytes(&bytes[..65]).is_ok())
}

/// Whether `blob` is one `sealBytes` made: base64url, its version byte, and room for an IV and a tag.
fn blob_shaped(blob: &str) -> bool {
    URL_SAFE_NO_PAD.decode(blob).ok().is_some_and(|bytes| bytes.len() >= SEALED_FLOOR && bytes[0] == VERSION)
}

/// `POST /api/forms/{id}`: an answer. See the header for what is checked, and in what order.
async fn answered(State(forms): State<Arc<Forms>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Path(id): Path<String>, body: Result<Bytes, BytesRejection>) -> Response {
    // Counted before anything is read: a flood is turned away without a byte of it looked at.
    if !forms.per_address.take(guard::client_ip_of(peer.ip(), &headers), Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "Too many answers from here in an hour. Try again later.");
    }
    let gone = || error(StatusCode::NOT_FOUND, "There is no form at that link. It may have been taken down.");
    if !base64url(&id, ID_LENGTH) {
        return gone();
    }
    let now = now_secs();
    let Some(form) = forms.accounts.store.form(&id, now - KEPT_FOR) else { return gone() };
    if !forms.per_form.take(id.clone(), Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "This form has taken as many answers as it may this minute. Try again shortly.");
    }
    match form.state {
        FormState::Open => {}
        FormState::Paused => return error(StatusCode::LOCKED, "This form is paused: it is not taking answers just now."),
        FormState::Closed => return error(StatusCode::GONE, "This form is closed."),
    }
    let too_large = || error(StatusCode::PAYLOAD_TOO_LARGE, if form.files { "That answer is too large: a form takes a file of up to about 2 MB." } else { "That answer is too large." });
    let Ok(body) = body else { return too_large() };
    let Ok(answer) = serde_json::from_slice::<Answer>(&body) else {
        return error(StatusCode::BAD_REQUEST, "That answer could not be read: only a sealed answer is taken.");
    };
    // The field a person never sees: filled, it was a bot, which is told what a person is told and keeps nothing.
    if answer.hp.as_deref().is_some_and(|hp| !hp.trim().is_empty()) {
        return (StatusCode::ACCEPTED, Json(json!({ "id": answer.id }))).into_response();
    }
    match ticket_opened(&forms.ticket_key, &id, &answer.ticket) {
        None => return error(StatusCode::CONFLICT, "This form was open too long, or opened elsewhere. Open it again and send it."),
        Some(opened) if now - opened < MIN_FILL => return error(StatusCode::from_u16(425).unwrap_or(StatusCode::BAD_REQUEST), "That was sent too quickly. Wait a moment and send it again."),
        Some(opened) if now - opened > TICKET_LIFE => return error(StatusCode::CONFLICT, "This form was open too long, or opened elsewhere. Open it again and send it."),
        Some(_) => {}
    }
    if !base64url(&answer.id, ANSWER_ID_LENGTH) {
        return error(StatusCode::BAD_REQUEST, "That answer could not be read: only a sealed answer is taken.");
    }
    let limit = if form.files { FILE_LIMIT } else { ANSWER_LIMIT };
    if answer.blob.len() > limit {
        return too_large();
    }
    if !base64url(&answer.blob, 1..=limit) || !blob_shaped(&answer.blob) {
        return error(StatusCode::BAD_REQUEST, "That answer could not be read: only a sealed answer is taken.");
    }
    // Every wrap made to one of the form's recipients, once each, and shaped as a wrap of a key is.
    let recipients = forms.accounts.store.form_recipients(&form);
    if recipients.is_empty() {
        return error(StatusCode::CONFLICT, "This form cannot take answers yet: its owner's app has not finished setting it up.");
    }
    let mut seen = std::collections::HashSet::new();
    if answer.wraps.is_empty() || answer.wraps.len() > RECIPIENTS || !answer.wraps.iter().all(|w| wrap_shaped(&w.wrap) && seen.insert(w.to.as_str())) {
        return error(StatusCode::BAD_REQUEST, "That answer could not be read: only a sealed answer is taken.");
    }
    if !answer.wraps.iter().all(|w| recipients.contains(&w.to)) {
        return error(StatusCode::CONFLICT, "This form changed while it was open. Send it again.");
    }
    let wraps = serde_json::to_string(&answer.wraps.iter().map(|w| json!({ "to": w.to, "wrap": w.wrap })).collect::<Vec<_>>()).unwrap_or_else(|_| "[]".into());
    let most = if form.files { WAITING_WITH_FILES } else { WAITING };
    match forms.accounts.store.put_form_item(&FormItem { id: answer.id.clone(), form: id, note: None, wraps, blob: answer.blob, at: now, claimed: false }, most, now - KEPT_FOR) {
        Ok(_) => (StatusCode::ACCEPTED, Json(json!({ "id": answer.id }))).into_response(),
        Err(FormWrite::Full) => error(StatusCode::INSUFFICIENT_STORAGE, "This form has more answers waiting than it keeps. Try again later."),
        Err(FormWrite::Taken) => error(StatusCode::CONFLICT, "That answer could not be kept. Open the form again and send it."),
        Err(_) => error(StatusCode::SERVICE_UNAVAILABLE, "That answer could not be kept just now. Try again."),
    }
}

/// Answers thirty days old, of every form, swept every hour from now on (the first at once). An answer past its time
/// is never listed in any case (`inbox`); the sweep is so it is not kept either.
#[cfg_attr(test, allow(dead_code))]
pub fn sweep_every_hour(accounts: Arc<Accounts>) {
    tokio::spawn(async move {
        let mut every = tokio::time::interval(Duration::from_secs(3600));
        loop {
            every.tick().await;
            let swept = accounts.store.sweep_form_inbox(now_secs() - KEPT_FOR);
            if swept > 0 {
                eprintln!("glyph-api swept {swept} form answers past thirty days");
            }
        }
    });
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    let now = Instant::now();
    let forms = Arc::new(Forms {
        ticket_key: ticket_key(&accounts),
        accounts,
        per_address: guard::RateLimiter::per_hour(ANSWERS_PER_ADDRESS_PER_HOUR, now),
        per_form: guard::RateLimiter::new(ANSWERS_PER_FORM_PER_MINUTE, now),
        openers: guard::RateLimiter::new(OPENS_PER_MINUTE, now),
    });
    Router::new()
        .route("/api/v1/forms", get(list_forms))
        .route("/api/v1/forms/inbox", get(inbox))
        .route("/api/v1/forms/inbox/{id}", delete(filed))
        .route("/api/v1/forms/inbox/{id}/claim", post(claim))
        .route("/api/v1/forms/{id}", put(put_form).delete(delete_form))
        .route("/api/v1/forms/{id}/state", post(set_state))
        .route("/api/v1/forms/{id}/answers", delete(clear_answers))
        .route("/api/forms/{id}", get(open_form).post(answered).layer(DefaultBodyLimit::max(FILE_LIMIT + BODY_SLACK)))
        .with_state(forms)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_ticket_says_when_it_was_made_for_its_form_alone() {
        let key = [7u8; 32];
        let ticket = ticket_for(&key, "form-a", 1_000);
        assert_eq!(ticket_opened(&key, "form-a", &ticket), Some(1_000));
        assert_eq!(ticket_opened(&key, "form-b", &ticket), None, "another form's");
        assert_eq!(ticket_opened(&[8u8; 32], "form-a", &ticket), None, "another key's");
        let mut forged = URL_SAFE_NO_PAD.decode(&ticket).unwrap();
        forged[..8].copy_from_slice(&900i64.to_be_bytes());
        assert_eq!(ticket_opened(&key, "form-a", &URL_SAFE_NO_PAD.encode(forged)), None, "an earlier moment, not signed");
        assert_eq!(ticket_opened(&key, "form-a", "short"), None);
    }

    #[test]
    fn a_wrap_and_a_blob_are_told_by_their_shape() {
        let (_, public) = crate::mail::seal::tests::account_pair();
        let wrap = crate::mail::seal::wrap_for(&public, &[1u8; 32], "form-key:f:a").unwrap();
        assert!(wrap_shaped(&wrap), "{wrap}");
        assert!(!wrap_shaped(&"A".repeat(WRAP_LENGTH)), "the length of one, but no point on the curve");
        assert!(!wrap_shaped("abc"));
        assert!(blob_shaped(&URL_SAFE_NO_PAD.encode([1u8; 40])));
        assert!(!blob_shaped(&URL_SAFE_NO_PAD.encode([2u8; 40])), "not sealBytes's version");
        assert!(!blob_shaped(&URL_SAFE_NO_PAD.encode([1u8; 10])), "too short to be sealed");
        assert!(!blob_shaped("{\"summary\":\"clear\"}"));
    }
}
