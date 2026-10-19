//! Ghost in a Google Meet (GHST-106, docs/MEET.md): invite Ghost to a meeting and it joins by itself, records it, and
//! the recording reaches the person who invited it, sealed to their account. Matt: "invite Ghost to meetings for it to
//! automatically join".
//!
//! HOW A MEETING IS BOOKED. The person adds their mail-to-note address (`<16 letters>@in.ghostmarkdown.com`, mail.rs)
//! as a guest on a Google Calendar event. Google mails the invite there; the mail becomes a note as any mail does, and
//! in the same request `book_from_mail` reads the invite's calendar part (`text/calendar`, or an `.ics` attachment;
//! src/meet/ics.rs) and books Ghost for the meeting: one row per invite UID, moved by a newer SEQUENCE and called off by
//! METHOD:CANCEL or STATUS:CANCELLED. Only Google Meet links are booked. A device can also say "join this now".
//!
//! HOW GHOST JOINS. A separate bot service on the same box (Node, a signed-in Chrome; meet/spike/README.md) polls the
//! internal routes over loopback, joins what is due, says in the chat what it is, records, and uploads the recording
//! with the captions it read. This service seals that upload to the account's encryption PUBLIC key in the same
//! request, keeps only the sealed copy (a file beside the account's recordings), and drops the clear bytes. A device
//! of the account downloads it and opens it with the account's private key, which never leaves the account's devices.
//!
//! WHAT IS IN THE CLEAR, AND FOR HOW LONG. The bot has no key, so a booking's Meet link, its title and its times are
//! kept in the clear - what "automatically join" needs, and no more (the organizer and the guest list are read and
//! dropped). Only until the meeting is done: the hourly sweep (`sweep`, run with the hook inbox's in hooks.rs) blanks the
//! title and the link of every booking that ended more than an hour ago, and deletes bookings thirty days after they
//! ended. The recording and its captions are never kept in the clear, on disk or in a log.
//!
//!   GET    /api/v1/meet                 the account's meetings: still to come, and the last seven days'
//!   POST   /api/v1/meet                 { url, title? } Ghost joins this Meet now (for two hours at most)
//!   DELETE /api/v1/meet/{id}            not this one: skipped before it starts, left if Ghost is in it
//!   GET    /api/v1/meet/takes           the recordings waiting, sealed: id, meeting, size, when, the wrapped key
//!   GET    /api/v1/meet/takes/{id}      one recording's sealed bytes, raw; the wrapped key in `x-glyph-wrapped`
//!   DELETE /api/v1/meet/takes/{id}      taken: a device has it
//!
//!   GET    /api/internal/meet/due       what the bot should be in, or on its way to
//!   POST   /api/internal/meet/{id}/state  { state, detail? } where the bot is with a meeting
//!   PUT    /api/internal/meet/{id}/take   multipart: `audio` and `captions`, sealed on arrival
//!
//! The internal routes answer only a request made on this machine - the socket's peer is loopback and no proxy header
//! is present (every request through Caddy comes from loopback too, carrying `X-Forwarded-For`) - that carries the
//! bot's token, compared in constant time. Without the token in the environment they are not mounted at all.
//!
//! THE ENVIRONMENT: GLYPH_MEET_TOKEN (the bot's bearer token, 32 characters or more; unset, nothing joins a meeting,
//! though invites are still booked and listed).

// A refusal here is the response itself, handed straight back from a handler; boxing it would only move it.
#![allow(clippy::result_large_err)]

pub mod ics;

use crate::accounts::Accounts;
use crate::identity::Claims;
use crate::mail::seal;
use crate::store::{MeetBooking, Store};
use crate::wire::{base64url, error, fresh_id, millis, now_secs};
use axum::extract::multipart::Field;
use axum::extract::rejection::ExtensionRejection;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Multipart, Path, Request, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use axum::{Json, Router};
use ics::Invite;
use mail_parser::{MessageParser, MimeHeaders, PartType};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::net::SocketAddr;
use std::sync::Arc;
use zeroize::Zeroize;

/// What the bot says in the meeting's chat when it is in, so nobody is recorded by something they cannot name.
pub const ANNOUNCE: &str = "Ghost.md is taking notes for this meeting. The recording goes to the person who invited it, sealed to their account.";
/// How long "join now" books Ghost for.
const NOW_LENGTH: i64 = 2 * 3600 * 1000;
/// The bot is told of a meeting this long before it starts, so it is in when the first person arrives...
const JOIN_EARLY: i64 = 120 * 1000;
/// ...and keeps being told of it this long after its booked end, as meetings run over.
const STAY_LATE: i64 = 15 * 60 * 1000;
/// A booking's title and link are blanked this long after its meeting ended.
pub const CLEAR_FOR: i64 = 3600 * 1000;
/// A booking is deleted this long after its meeting ended.
pub const KEPT_FOR: i64 = 30 * 24 * 3600 * 1000;
/// How far back the device's list reaches.
const LISTED_FOR: i64 = 7 * 24 * 3600 * 1000;
/// The most meetings an account has booked and still to come: an address anyone may mail cannot fill the bot's day.
const UPCOMING: i64 = 100;
/// The most a recording may be, and its captions. Opus at 32 kbit/s is 15 MB an hour; this is ten hours and more.
const AUDIO_LIMIT: usize = 300 * 1024 * 1024;
const CAPTIONS_LIMIT: usize = 20 * 1024 * 1024;
/// The upload's body: the two, and multipart's own bytes around them.
const TAKE_BODY: usize = AUDIO_LIMIT + CAPTIONS_LIMIT + 1024 * 1024;
/// A calendar part larger than this is not an invite.
const CALENDAR_LIMIT: usize = 1024 * 1024;
/// A title, and a state's detail, in characters.
const TITLE_LIMIT: usize = 200;
const DETAIL_LIMIT: usize = 200;
/// The states the bot may set. `leave` is set by a device or by a cancellation, for the bot to read; `booked` and
/// `cancelled` by an invite.
const BOT_STATES: &[&str] = &["joining", "in_call", "done", "failed", "skipped"];
/// States a booking does not leave, but for a new invite (`apply`).
const ENDED: &[&str] = &["done", "failed", "skipped", "cancelled"];
/// What a sealed take starts with: `GMT1`, as a mail's sealed note is `GML1` (src/mail/message.rs).
pub const MAGIC: &[u8; 4] = b"GMT1";
/// The minimum length of GLYPH_MEET_TOKEN, as GLYPH_API_TOKEN's.
#[cfg_attr(test, allow(dead_code))]
const TOKEN_FLOOR: usize = 32;

/// The context a take's key is wrapped in, and the one the take is sealed in: a take's seal opens as no mail's, nor
/// moved onto another take.
pub fn take_wrap_context(id: &str) -> String {
    format!("meet-take:{id}")
}

pub fn take_seal_context(id: &str) -> String {
    format!("meet:{id}")
}

fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// `s` trimmed to at most `limit` characters, or none when nothing is left.
fn clip(s: Option<&str>, limit: usize) -> Option<String> {
    s.map(str::trim).filter(|s| !s.is_empty()).map(|s| s.chars().take(limit).collect())
}

fn meeting_json(b: &MeetBooking) -> Value {
    json!({
        "id": b.id,
        "title": b.title,
        "url": if b.url.is_empty() { Value::Null } else { json!(b.url) },
        "startsAt": b.starts_at,
        "endsAt": b.ends_at,
        "state": b.state,
        "detail": b.detail,
    })
}

// --- invites -------------------------------------------------------------------------------------

/// Books, moves or calls off Ghost for every meeting the calendar parts of the raw mail `mime` name, for `account`, at
/// `now` (ms). Answers how many bookings it wrote. Called by mail.rs for each account a mail is for, once that account
/// has an encryption key (a recording could be sealed to nothing else); the mail still becomes a note as before.
pub fn book_from_mail(store: &Store, account: i64, mime: &[u8], now: i64) -> usize {
    let Some(message) = MessageParser::default().parse(mime) else { return 0 };
    // Google sends the invite twice in one mail, as the `text/calendar` alternative and as `invite.ics`: read once.
    let mut read: Vec<String> = Vec::new();
    let mut written = 0;
    for part in &message.parts {
        let kind = part.content_type().map(|t| format!("{}/{}", t.ctype(), t.subtype().unwrap_or("")).to_ascii_lowercase()).unwrap_or_default();
        let named = part.attachment_name().is_some_and(|n| n.to_ascii_lowercase().ends_with(".ics"));
        if kind != "text/calendar" && kind != "application/ics" && !named {
            continue;
        }
        let calendar = match &part.body {
            PartType::Text(t) => t.to_string(),
            PartType::Binary(b) | PartType::InlineBinary(b) => String::from_utf8_lossy(b).into_owned(),
            _ => continue,
        };
        if calendar.len() > CALENDAR_LIMIT || read.contains(&calendar) {
            continue;
        }
        for invite in ics::invites(&calendar, now) {
            if apply(store, account, &invite, now) {
                written += 1;
            }
        }
        read.push(calendar);
    }
    written
}

/// One meeting of an invite, applied to the account's bookings. A new one is booked if it has a Meet link and is not
/// over; one already booked follows the invite unless the invite is older (a lower SEQUENCE) than what was applied.
fn apply(store: &Store, account: i64, invite: &Invite, now: i64) -> bool {
    let secs = now.div_euclid(1000);
    // One occurrence moved or called off, where the series' booking is that very occurrence (a recurring meeting is
    // booked one occurrence at a time, ics.rs): the series' booking follows it.
    let existing = store.meet_booking_by_uid(account, &invite.uid).or_else(|| {
        let at = invite.recurrence_id?;
        let series = invite.uid.rsplit_once('#')?.0;
        store.meet_booking_by_uid(account, series).filter(|b| b.starts_at == at)
    });
    let Some(mut b) = existing else {
        let Some(url) = invite.url.clone().filter(|_| !invite.cancelled && invite.ends_at > now) else { return false };
        if store.meet_upcoming(account, now) >= UPCOMING {
            return false;
        }
        let booking = MeetBooking {
            id: fresh_id(),
            account,
            uid: invite.uid.clone(),
            url,
            title: clip(invite.title.as_deref(), TITLE_LIMIT),
            starts_at: invite.starts_at,
            ends_at: invite.ends_at,
            state: "booked".into(),
            detail: None,
            sequence: invite.sequence,
        };
        return store.insert_meet_booking(&booking, secs).unwrap_or(false);
    };
    if invite.sequence < b.sequence {
        return false;
    }
    b.sequence = invite.sequence;
    match (&invite.url, invite.cancelled) {
        (Some(url), false) => {
            let moved = b.starts_at != invite.starts_at;
            b.url = url.clone();
            b.title = clip(invite.title.as_deref(), TITLE_LIMIT);
            b.starts_at = invite.starts_at;
            b.ends_at = invite.ends_at;
            // Invited again after it was called off, or to a new time after it was over (the next occurrence of a
            // recurring meeting, or a meeting moved): booked again. A skip stands until the meeting moves.
            if invite.ends_at > now && (b.state == "cancelled" || (moved && ENDED.contains(&b.state.as_str()))) {
                b.state = "booked".into();
                b.detail = None;
            }
        }
        _ => {
            let why = if invite.cancelled { "The organizer called it off." } else { "The invite no longer has a Google Meet link." };
            let next = match b.state.as_str() {
                "booked" => "cancelled",
                // Ghost is in it, or on its way: the bot reads `leave` and goes.
                "joining" | "in_call" => "leave",
                other => other,
            };
            if next != b.state {
                b.state = next.into();
                b.detail = Some(why.into());
            }
        }
    }
    store.update_meet_booking(&b, secs).is_ok()
}

/// The hourly sweep's part, at `now` (ms): see the header. Answers how many bookings were blanked and how many deleted.
pub fn sweep(store: &Store, now: i64) -> (usize, usize) {
    store.sweep_meet(now, CLEAR_FOR, KEPT_FOR)
}

// --- the device's routes -------------------------------------------------------------------------

async fn list(State(accounts): State<Arc<Accounts>>, who: Claims) -> Response {
    let meetings: Vec<Value> = accounts.store.meet_bookings(who.sub, now_ms() - LISTED_FOR).iter().map(meeting_json).collect();
    Json(json!({ "meetings": meetings })).into_response()
}

#[derive(Deserialize)]
struct BookNow {
    url: String,
    #[serde(default)]
    title: Option<String>,
}

async fn book_now(State(accounts): State<Arc<Accounts>>, who: Claims, Json(body): Json<BookNow>) -> Response {
    let Some(url) = ics::typed_meet_url(&body.url) else {
        return error(StatusCode::BAD_REQUEST, "That is not a Google Meet link. It looks like meet.google.com/abc-defg-hij.");
    };
    // The recording is sealed to the account's encryption key on arrival, so there must be one to seal it to.
    if accounts.store.account_key(who.sub).is_none() {
        return error(StatusCode::CONFLICT, "Your account needs its encryption key first. Sync once, then try again.");
    }
    let now = now_ms();
    if accounts.store.meet_upcoming(who.sub, now) >= UPCOMING {
        return error(StatusCode::TOO_MANY_REQUESTS, "Ghost is booked into as many meetings as it may be. Skip one first.");
    }
    let id = fresh_id();
    let booking = MeetBooking {
        id: id.clone(),
        account: who.sub,
        uid: format!("now:{id}"),
        url,
        title: clip(body.title.as_deref(), TITLE_LIMIT),
        starts_at: now,
        ends_at: now + NOW_LENGTH,
        state: "booked".into(),
        detail: None,
        sequence: 0,
    };
    match accounts.store.insert_meet_booking(&booking, now_secs()) {
        Ok(true) => Json(json!({ "meeting": meeting_json(&booking) })).into_response(),
        _ => error(StatusCode::INTERNAL_SERVER_ERROR, "Ghost could not be booked just now. Try again."),
    }
}

/// The account's booking `id`, or the 404 every other account's is answered with.
fn own(accounts: &Accounts, account: i64, id: &str) -> Result<MeetBooking, Response> {
    let found = if base64url(id, 1..=64) { accounts.store.meet_booking(id).filter(|b| b.account == account) } else { None };
    found.ok_or_else(|| error(StatusCode::NOT_FOUND, "No meeting by that id."))
}

async fn skip(State(accounts): State<Arc<Accounts>>, Path(id): Path<String>, who: Claims) -> Response {
    let mut b = match own(&accounts, who.sub, &id) {
        Ok(b) => b,
        Err(refused) => return refused,
    };
    let next = match b.state.as_str() {
        "booked" => "skipped",
        "joining" | "in_call" => "leave",
        other => other,
    };
    if next != b.state {
        b.state = next.into();
        b.detail = Some("You asked Ghost not to be in it.".into());
        if !accounts.store.set_meet_state(&b.id, &b.state, b.detail.as_deref(), now_secs()) {
            return error(StatusCode::INTERNAL_SERVER_ERROR, "That meeting could not be changed just now. Try again.");
        }
    }
    Json(json!({ "meeting": meeting_json(&b) })).into_response()
}

async fn takes(State(accounts): State<Arc<Accounts>>, who: Claims) -> Response {
    let list: Vec<Value> = accounts
        .store
        .meet_takes(who.sub)
        .into_iter()
        .map(|t| json!({ "id": t.id, "meeting": t.meeting, "size": t.size, "at": millis(t.at), "wrapped": t.wrapped }))
        .collect();
    Json(json!({ "takes": list })).into_response()
}

/// One take's sealed bytes, raw: a recording is tens of megabytes, which base64 in JSON would make a third larger
/// again and the phone would have to hold twice. The wrapped key rides in `x-glyph-wrapped`, as it is in the list.
async fn get_take(State(accounts): State<Arc<Accounts>>, Path(id): Path<String>, who: Claims) -> Response {
    if !base64url(&id, 1..=64) {
        return error(StatusCode::NOT_FOUND, "No recording by that id.");
    }
    let store = accounts.store.clone();
    let found = tokio::task::spawn_blocking(move || store.meet_take(who.sub, &id)).await.ok().flatten();
    let Some((take, bytes)) = found else {
        return error(StatusCode::NOT_FOUND, "No recording by that id. Another of your devices may have taken it.");
    };
    let mut response = (StatusCode::OK, bytes).into_response();
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/octet-stream"));
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    for (name, value) in [("x-glyph-wrapped", take.wrapped.as_str()), ("x-glyph-meeting", take.meeting.as_str())] {
        if let Ok(value) = HeaderValue::from_str(value) {
            headers.insert(name, value);
        }
    }
    response
}

async fn delete_take(State(accounts): State<Arc<Accounts>>, Path(id): Path<String>, who: Claims) -> Response {
    if base64url(&id, 1..=64) {
        accounts.store.delete_meet_take(who.sub, &id);
    }
    StatusCode::NO_CONTENT.into_response()
}

// --- the bot's routes ----------------------------------------------------------------------------

/// The bot's side: the accounts, and the SHA-256 of its token (compared as hashes, so in constant time and whatever
/// length a guess is).
pub struct Bot {
    accounts: Arc<Accounts>,
    token: [u8; 32],
}

/// The bot's token, from GLYPH_MEET_TOKEN: none when unset or too short to be one, and then the bot's routes are not
/// mounted.
#[cfg(not(test))]
pub fn bot_token() -> Option<String> {
    let token = std::env::var("GLYPH_MEET_TOKEN").ok().map(|t| t.trim().to_string()).filter(|t| !t.is_empty())?;
    if token.len() < TOKEN_FLOOR {
        eprintln!("GLYPH_MEET_TOKEN is shorter than {TOKEN_FLOOR} characters; the Meet bot's routes are off");
        return None;
    }
    Some(token)
}

/// In the tests, the bot's token is `TEST_BOT_TOKEN`.
#[cfg(test)]
pub fn bot_token() -> Option<String> {
    Some(TEST_BOT_TOKEN.into())
}

/// The token the tests' bot carries.
#[cfg(test)]
pub const TEST_BOT_TOKEN: &str = "meet-bot-test-token-0123456789abcdef0123456789";

/// Whether `given` is the bot's token, in time that does not depend on where they differ.
fn same_token(given: &str, token: &[u8; 32]) -> bool {
    let given = Sha256::digest(given.as_bytes());
    given.iter().zip(token.iter()).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
}

/// Lets a request through to the bot's routes only from this machine, not through Caddy, with the bot's token. A
/// request from anywhere else is answered as though the route were not there.
async fn bot_only(State(bot): State<Arc<Bot>>, peer: Result<ConnectInfo<SocketAddr>, ExtensionRejection>, request: Request, next: Next) -> Response {
    // No peer address at all (a server not started with connect info) is not taken for this machine.
    let local = peer.is_ok_and(|peer| peer.0.ip().to_canonical().is_loopback());
    // Caddy connects from loopback too, and always sets X-Forwarded-For (replacing any a client sent): a request that
    // carries one, or any other proxy's header, came from outside.
    let proxied = ["x-forwarded-for", "forwarded", "x-forwarded-host", "x-forwarded-proto", "x-real-ip"].iter().any(|h| request.headers().contains_key(*h));
    if !local || proxied {
        return error(StatusCode::NOT_FOUND, "no such route");
    }
    let given = request.headers().get(header::AUTHORIZATION).and_then(|v| v.to_str().ok()).and_then(|v| v.strip_prefix("Bearer ")).unwrap_or("");
    if !same_token(given.trim(), &bot.token) {
        return error(StatusCode::UNAUTHORIZED, "That is not the Meet bot's token.");
    }
    next.run(request).await
}

async fn due(State(bot): State<Arc<Bot>>) -> Response {
    let meetings: Vec<Value> = bot
        .accounts
        .store
        .meet_due(now_ms(), JOIN_EARLY, STAY_LATE)
        .iter()
        .map(|b| json!({ "id": b.id, "url": b.url, "title": b.title, "startsAt": b.starts_at, "endsAt": b.ends_at, "state": b.state, "announce": ANNOUNCE }))
        .collect();
    Json(json!({ "meetings": meetings })).into_response()
}

#[derive(Deserialize)]
struct StateBody {
    state: String,
    #[serde(default)]
    detail: Option<String>,
}

/// Where the bot is with a meeting. A meeting that is over (done, failed, skipped, called off) stays over, and one a
/// device asked Ghost to leave is not joined again: both are answered 409 with the state that stands, for the bot to
/// act on.
async fn set_state(State(bot): State<Arc<Bot>>, Path(id): Path<String>, Json(body): Json<StateBody>) -> Response {
    if !BOT_STATES.contains(&body.state.as_str()) {
        return error(StatusCode::BAD_REQUEST, "A state is joining, in_call, done, failed or skipped.");
    }
    let Some(b) = bot.accounts.store.meet_booking(&id).filter(|_| base64url(&id, 1..=64)) else {
        return error(StatusCode::NOT_FOUND, "No meeting by that id.");
    };
    let refused = (ENDED.contains(&b.state.as_str()) && b.state != body.state) || (b.state == "leave" && matches!(body.state.as_str(), "joining" | "in_call"));
    if refused {
        return (StatusCode::CONFLICT, Json(json!({ "error": "That meeting is not Ghost's to be in any more.", "id": b.id, "state": b.state }))).into_response();
    }
    let detail = clip(body.detail.as_deref(), DETAIL_LIMIT);
    if !bot.accounts.store.set_meet_state(&b.id, &body.state, detail.as_deref(), now_secs()) {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "That state could not be kept.");
    }
    Json(json!({ "id": b.id, "state": body.state })).into_response()
}

/// A field's bytes appended to `into`, refused past `limit` in all.
async fn read_into(field: &mut Field<'_>, into: &mut Vec<u8>, limit: usize) -> Result<(), ()> {
    while let Some(chunk) = field.chunk().await.map_err(|_| ())? {
        if into.len() + chunk.len() > limit {
            return Err(());
        }
        into.extend_from_slice(&chunk);
    }
    Ok(())
}

/// A take as it is sealed, `GMT1`: the four magic bytes, the head's length as four bytes big-endian, the head as JSON,
/// the captions' bytes, then the audio's.
fn pack(head: &Value, captions: &[u8], audio: &[u8]) -> Option<Vec<u8>> {
    let head = serde_json::to_vec(head).ok()?;
    let length = u32::try_from(head.len()).ok()?;
    let mut out = Vec::with_capacity(8 + head.len() + captions.len() + audio.len());
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&length.to_be_bytes());
    out.extend_from_slice(&head);
    out.extend_from_slice(captions);
    out.extend_from_slice(audio);
    Some(out)
}

/// An audio type as the bot names it, if it looks like one; `audio/webm` otherwise.
fn audio_type(given: Option<&str>) -> String {
    given
        .map(|t| t.trim().to_ascii_lowercase())
        .filter(|t| t.starts_with("audio/") && t.len() <= 100 && t.bytes().all(|b| b.is_ascii_alphanumeric() || b"/;=.+-_ ".contains(&b)))
        .unwrap_or_else(|| "audio/webm".into())
}

/// The recording of meeting `id`, with its captions: sealed to the meeting's account in this request, kept only sealed,
/// and the meeting then `done`. Multipart: `audio` (the recording; its type is kept), `captions` (NDJSON, optional),
/// and optionally `startedAt` and `endedAt` (ms) when the recording's own span differs from the booking's.
async fn put_take(State(bot): State<Arc<Bot>>, Path(id): Path<String>, mut multipart: Multipart) -> Response {
    let Some(b) = bot.accounts.store.meet_booking(&id).filter(|_| base64url(&id, 1..=64)) else {
        return error(StatusCode::NOT_FOUND, "No meeting by that id.");
    };
    if b.state == "skipped" || b.state == "cancelled" {
        return error(StatusCode::CONFLICT, "That meeting was called off or skipped: nothing of it is kept.");
    }
    let Some(public) = bot.accounts.store.account_key(b.account).map(|k| k.pub_key) else {
        return error(StatusCode::CONFLICT, "That meeting's account has no encryption key to seal it to.");
    };
    let (mut audio, mut captions) = (Vec::new(), Vec::new());
    let (mut mime, mut started, mut ended) = (String::from("audio/webm"), None, None);
    let read: Result<(), &str> = async {
        while let Some(mut field) = multipart.next_field().await.map_err(|_| "That upload could not be read.")? {
            let name = field.name().unwrap_or("").to_string();
            match name.as_str() {
                "audio" => {
                    mime = audio_type(field.content_type());
                    read_into(&mut field, &mut audio, AUDIO_LIMIT).await.map_err(|_| "That recording is too large or could not be read.")?;
                }
                "captions" => read_into(&mut field, &mut captions, CAPTIONS_LIMIT).await.map_err(|_| "Those captions are too large or could not be read.")?,
                "startedAt" | "endedAt" => {
                    let mut text = Vec::new();
                    read_into(&mut field, &mut text, 20).await.map_err(|_| "A time is milliseconds since the epoch.")?;
                    let at = std::str::from_utf8(&text).ok().and_then(|t| t.trim().parse::<i64>().ok()).ok_or("A time is milliseconds since the epoch.")?;
                    if name == "startedAt" {
                        started = Some(at);
                    } else {
                        ended = Some(at);
                    }
                }
                // Anything else is not read: it is no part of a take.
                _ => while let Ok(Some(_)) = field.chunk().await {},
            }
        }
        if audio.is_empty() {
            return Err("A take needs its audio.");
        }
        Ok(())
    }
    .await;
    if let Err(why) = read {
        audio.zeroize();
        captions.zeroize();
        return error(StatusCode::BAD_REQUEST, why);
    }
    let take = fresh_id();
    let head = json!({
        "v": 1,
        "meeting": b.id,
        "title": b.title,
        "startedAt": started.unwrap_or(b.starts_at),
        "endedAt": ended.unwrap_or_else(now_ms),
        "mime": mime,
        "captionsBytes": captions.len(),
        "audioBytes": audio.len(),
    });
    let packed = pack(&head, &captions, &audio);
    audio.zeroize();
    captions.zeroize();
    let Some(mut payload) = packed else {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "That take could not be kept.");
    };
    // Sealing and writing tens of megabytes is work for a blocking thread, not for the one answering requests.
    let store = bot.accounts.store.clone();
    let (account, meeting, take_id) = (b.account, b.id.clone(), take.clone());
    let kept = tokio::task::spawn_blocking(move || {
        let sealed = seal::seal_in_place(&public, &take_wrap_context(&take_id), &take_seal_context(&take_id), &mut payload);
        let kept = sealed.ok().and_then(|(wrapped, head)| store.put_meet_take(account, &take_id, &meeting, &wrapped, &[&head[..], &payload[..]], now_secs()).ok());
        // Ciphertext by now, or wiped by `seal_in_place`; dropped either way.
        payload.zeroize();
        kept
    })
    .await
    .ok()
    .flatten();
    let Some(size) = kept else {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "That take could not be kept.");
    };
    bot.accounts.store.set_meet_state(&b.id, "done", b.detail.as_deref(), now_secs());
    Json(json!({ "take": take, "size": size })).into_response()
}

/// The device's routes; and the bot's when it has a token (`bot_token`), behind `bot_only`.
pub fn router(accounts: Arc<Accounts>, bot_token: Option<String>) -> Router {
    let mut routes = Router::new()
        .route("/api/v1/meet", get(list).post(book_now))
        .route("/api/v1/meet/takes", get(takes))
        .route("/api/v1/meet/takes/{id}", get(get_take).delete(delete_take))
        .route("/api/v1/meet/{id}", delete(skip))
        .with_state(accounts.clone());
    if let Some(token) = bot_token {
        let bot = Arc::new(Bot { accounts, token: Sha256::digest(token.as_bytes()).into() });
        let internal = Router::new()
            .route("/api/internal/meet/due", get(due))
            .route("/api/internal/meet/{id}/state", post(set_state))
            .route("/api/internal/meet/{id}/take", put(put_take).layer(DefaultBodyLimit::max(TAKE_BODY)))
            .route_layer(middleware::from_fn_with_state(bot.clone(), bot_only))
            .with_state(bot);
        routes = routes.merge(internal);
    }
    routes
}

/// The GMT1 head and the two parts back out of a take, for the tests (the device's reading is the app's).
#[cfg(test)]
pub fn unpack(payload: &[u8]) -> (Value, Vec<u8>, Vec<u8>) {
    assert_eq!(&payload[..4], MAGIC);
    let length = u32::from_be_bytes(payload[4..8].try_into().unwrap()) as usize;
    let head: Value = serde_json::from_slice(&payload[8..8 + length]).unwrap();
    let captions = head["captionsBytes"].as_u64().unwrap() as usize;
    let rest = &payload[8 + length..];
    (head, rest[..captions].to_vec(), rest[captions..].to_vec())
}
