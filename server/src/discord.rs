//! Ghost in a Discord call (docs/DISCORD_CALLS.md). Matt, 2026-10-26: "Add a new plugin to post notes to discord chats
//! as well as join discord calls to summarize meetings". This is the call half: someone in a Discord voice channel runs
//! `/ghost join`, Ghost joins the channel, records it, and the recording reaches their Ghost.md account sealed, filed
//! and written up on their device as a Google Meet is (meet.rs, docs/MEET.md).
//!
//! LINKING (Matt: "the user links their Discord account to Ghost once, with a code from the app's Settings"). A device
//! asks for a code (`POST /api/v1/discord/link-code`): eight letters and digits from an alphabet with no look-alikes,
//! shown as `K7QM-2XRP`, good once and for ten minutes, only its SHA-256 kept. The person runs `/ghost link K7QM-2XRP`
//! in Discord; the bot hands the code and the Discord user's id and name to `POST /api/internal/discord/link`, and the
//! Discord user is linked to the account (store/discord.rs: one each way; a link moves on a second linking). The
//! device shows the name (`GET /api/v1/discord/link`) and lets it go (`DELETE`).
//!
//! THE SWITCH (Matt, 2026-10-26, Discord calls belong to the Discord plugin: "Join Discord calls" on its page). The
//! link carries it (`calls`, store/discord.rs), on from the linking; the device sets it (`PUT /api/v1/discord/calls`),
//! and turns it off by itself on a pass where the plugin is off (lib/plugins/discord/calls.dart). While it is off,
//! `/ghost join` is refused with where to turn it on. Its own flag, not a "kind" of the meeting bookings: the
//! per-account kinds Google Meet and Zoom are getting were not on main when this was written.
//!
//! A CALL is a booking like any meeting's (`meet_bookings`), uid `discord:<id>`, its link the voice channel's
//! (`https://discord.com/channels/<guild>/<channel>`), its title the channel's and the server's names, from now for
//! three hours and a quarter (the bot leaves at three: meet/bot/lib/decide.mjs `maxMs`), `joining` from the start. So
//! the device lists it, "Leave now" (`DELETE /api/v1/meet/{id}`) sets `leave` as for a Meet, the hourly sweep blanks
//! and forgets it, and its take is sealed on arrival by meet.rs's own `put_take`: nothing of a Discord call is kept
//! in the clear that a Meet's is not, and for no longer. The Meet bot never sees one (store/meet.rs `meet_due`).
//!
//! WHO MAY BE RECORDED. The bot says in the voice channel's chat who asked and that the call is recorded, as the Meet
//! bot says it in Meet's (discord/bot/lib/words.mjs), and anyone in the channel can send it away with `/ghost leave`.
//!
//!   POST   /api/v1/discord/link-code       a code to link a Discord user with: { code, expiresAt }
//!   GET    /api/v1/discord/link            { link: { name, linkedAt, calls } | null }
//!   DELETE /api/v1/discord/link            the link let go: { link: null }
//!   PUT    /api/v1/discord/calls           { on } the plugin's "Join Discord calls": { link }; 404 not linked
//!
//!   POST   /api/internal/discord/link      { code, user, name } a code redeemed by `/ghost link`: { linked: true }
//!   POST   /api/internal/discord/session   { user, guild, channel, title? } `/ghost join`: { meeting, name }; 404 not
//!                                          linked, 403 its calls switched off, 409 no encryption key yet, 429 too many
//!   GET    /api/internal/discord/due       the Discord calls under way: { meetings: [{ id, state, startsAt, endsAt }] }
//!   POST   /api/internal/discord/{id}/state  as the Meet bot's (`meet::set_state`); the call's end set once it is over
//!   PUT    /api/internal/discord/{id}/take   as the Meet bot's (`meet::put_take`), sealed on arrival; the end set too
//!
//! The internal routes answer as the Meet bot's do: only a request made on this machine, not through Caddy, carrying
//! the Discord bot's own token, GLYPH_DISCORD_TOKEN (not Discord's bot token, which glyph-api never sees). They act on
//! Discord calls alone: a Meet's id is 404 here, as a Discord call's is to nothing but the Meet routes a device has.
//! Without the token NONE of these routes is mounted, the device's included, and the app draws no Discord section.
//!
//! THE ENVIRONMENT: GLYPH_DISCORD_TOKEN (32 to 200 letters, digits, - or _; `openssl rand -hex 32`).

// A refusal here is the response itself, handed straight back from a handler.
#![allow(clippy::result_large_err)]

use crate::accounts::{Accounts, HasAccounts};
use crate::guard::RateLimiter;
use crate::identity::Claims;
use crate::live::Poke;
use crate::meet::{self, Bot, StateBody};
use crate::store::{MeetBooking, DISCORD_UID};
use crate::wire::{base64url, error, fresh_id, millis, now_secs};
use axum::extract::rejection::ExtensionRejection;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Multipart, Path, Request, State};
use axum::http::{header, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post, put};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

/// How long a link code is good for, in seconds.
pub const CODE_FOR: i64 = 10 * 60;
/// The letters a code is made of: no 0 or O, 1, I or L, nor U. Thirty, so eight of them are 6.5 × 10^11 codes.
const CODE_LETTERS: &[u8] = b"23456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH: usize = 8;
/// How long a call is booked for: the bot's three hours, and a quarter more, so a call is "to come" while it is on.
const CALL_LENGTH: i64 = (3 * 60 + 15) * 60 * 1000;
/// A Discord user's name, in characters (Discord's own are 32 at most).
const NAME_LIMIT: usize = 100;
/// The limits: codes an account makes in an hour; codes a Discord user tries in an hour, and every user together in a
/// minute (a guesser with many Discord accounts still meets one bucket); calls a Discord user opens in an hour.
const CODES_PER_HOUR: u32 = 10;
const REDEEMS_PER_USER_HOUR: u32 = 10;
const REDEEMS_PER_MINUTE: u32 = 60;
const CALLS_PER_USER_HOUR: u32 = 20;

fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// A fresh code, `CODE_LENGTH` of `CODE_LETTERS`, each drawn without bias (a byte past the last whole multiple of
/// thirty is drawn again).
fn fresh_code() -> String {
    let limit = (256 / CODE_LETTERS.len() * CODE_LETTERS.len()) as u8;
    let mut code = String::with_capacity(CODE_LENGTH);
    while code.len() < CODE_LENGTH {
        let byte = rand::random::<u8>();
        if byte < limit {
            code.push(CODE_LETTERS[byte as usize % CODE_LETTERS.len()] as char);
        }
    }
    code
}

/// A code as it is shown: `K7QM-2XRP`.
pub fn shown_code(code: &str) -> String {
    let (a, b) = code.split_at(CODE_LENGTH / 2);
    format!("{a}-{b}")
}

/// A code as a person typed it, read: any case, with or without the dash or spaces. None for one that cannot be a code.
pub fn typed_code(typed: &str) -> Option<String> {
    let code: String = typed.chars().filter(|c| !matches!(c, '-' | ' ' | '\u{2010}'..='\u{2015}')).map(|c| c.to_ascii_uppercase()).collect();
    (code.len() == CODE_LENGTH && code.bytes().all(|b| CODE_LETTERS.contains(&b))).then_some(code)
}

/// What a code is kept as.
fn code_hash(code: &str) -> String {
    Sha256::digest(code.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}

/// A Discord id (a snowflake): digits, 15 to 21 of them.
fn snowflake(id: &str) -> bool {
    (15..=21).contains(&id.len()) && id.bytes().all(|b| b.is_ascii_digit())
}

/// Text as it is kept: no control characters, one space between words, at most `limit` characters; none when empty.
fn clean(text: Option<&str>, limit: usize) -> Option<String> {
    let text: String = text?.chars().map(|c| if c.is_control() { ' ' } else { c }).collect();
    let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    (!text.is_empty()).then(|| text.chars().take(limit).collect())
}

/// The routes' state: the accounts, the bot's side as meet.rs knows it (its token, for `set_state` and `put_take`),
/// and the limits.
pub struct Discord {
    accounts: Arc<Accounts>,
    bot: Arc<Bot>,
    codes: RateLimiter<i64>,
    redeems_by_user: RateLimiter<String>,
    redeems: RateLimiter<u8>,
    calls_by_user: RateLimiter<String>,
}

impl HasAccounts for Arc<Discord> {
    fn accounts(&self) -> &Accounts {
        &self.accounts
    }
}

/// The Discord bot's token, from GLYPH_DISCORD_TOKEN: none when unset or too short, and then nothing here is mounted.
#[cfg(not(test))]
pub fn bot_token() -> Option<String> {
    let token = std::env::var("GLYPH_DISCORD_TOKEN").ok().map(|t| t.trim().to_string()).filter(|t| !t.is_empty())?;
    if token.len() < meet::TOKEN_FLOOR {
        eprintln!("GLYPH_DISCORD_TOKEN is shorter than {} characters; the Discord routes are off", meet::TOKEN_FLOOR);
        return None;
    }
    Some(token)
}

/// In the tests, the Discord bot's token is `TEST_DISCORD_TOKEN`.
#[cfg(test)]
pub fn bot_token() -> Option<String> {
    Some(TEST_DISCORD_TOKEN.into())
}

#[cfg(test)]
pub const TEST_DISCORD_TOKEN: &str = "discord-bot-test-token-0123456789abcdef01234567";

// --- the device's routes -------------------------------------------------------------------------

async fn link_code(State(d): State<Arc<Discord>>, who: Claims) -> Response {
    // A call is sealed to the account's encryption key on arrival, so there must be one before anything is linked.
    if d.accounts.store.account_key(who.sub).is_none() {
        return error(StatusCode::CONFLICT, "Your account needs its encryption key first. Sync once, then try again.");
    }
    if !d.codes.take(who.sub, Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "That is a lot of codes in an hour. Wait a while, then make one more.");
    }
    let code = fresh_code();
    let now = now_secs();
    if d.accounts.store.put_discord_code(who.sub, &code_hash(&code), now + CODE_FOR, now).is_err() {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "A code could not be made just now. Try again.");
    }
    Json(json!({ "code": shown_code(&code), "expiresAt": millis(now + CODE_FOR) })).into_response()
}

fn link_json(d: &Discord, account: i64) -> Value {
    match d.accounts.store.discord_link_of_account(account) {
        Some(link) => json!({ "name": link.name, "linkedAt": millis(link.linked_at), "calls": link.calls }),
        None => Value::Null,
    }
}

async fn get_link(State(d): State<Arc<Discord>>, who: Claims) -> Response {
    Json(json!({ "link": link_json(&d, who.sub) })).into_response()
}

#[derive(Deserialize)]
struct Calls {
    on: bool,
}

async fn set_calls(State(d): State<Arc<Discord>>, who: Claims, Json(body): Json<Calls>) -> Response {
    if !d.accounts.store.set_discord_calls(who.sub, body.on) {
        return error(StatusCode::NOT_FOUND, "Link your Discord first.");
    }
    Json(json!({ "link": link_json(&d, who.sub) })).into_response()
}

async fn unlink(State(d): State<Arc<Discord>>, who: Claims) -> Response {
    d.accounts.store.unlink_discord(who.sub);
    Json(json!({ "link": Value::Null })).into_response()
}

// --- the bot's routes ----------------------------------------------------------------------------

/// As meet.rs's `bot_only`, with the Discord bot's token: this machine, not through Caddy, the token. Anywhere else the
/// route is not there.
async fn bot_only(State(d): State<Arc<Discord>>, peer: Result<ConnectInfo<SocketAddr>, ExtensionRejection>, request: Request, next: Next) -> Response {
    let local = peer.is_ok_and(|peer| peer.0.ip().to_canonical().is_loopback());
    let proxied = ["x-forwarded-for", "forwarded", "x-forwarded-host", "x-forwarded-proto", "x-real-ip"].iter().any(|h| request.headers().contains_key(*h));
    if !local || proxied {
        return error(StatusCode::NOT_FOUND, "no such route");
    }
    let given = request.headers().get(header::AUTHORIZATION).and_then(|v| v.to_str().ok()).and_then(|v| v.strip_prefix("Bearer ")).unwrap_or("");
    if !d.bot.admits(given.trim()) {
        return error(StatusCode::UNAUTHORIZED, "That is not the Discord bot's token.");
    }
    next.run(request).await
}

#[derive(Deserialize)]
struct Redeem {
    code: String,
    user: String,
    #[serde(default)]
    name: Option<String>,
}

/// `/ghost link <code>`: the Discord user linked to the account whose code it is. The code goes whether or not it was
/// right for long; a wrong one costs the user, and everyone, a try.
async fn redeem(State(d): State<Arc<Discord>>, Json(body): Json<Redeem>) -> Response {
    if !snowflake(&body.user) {
        return error(StatusCode::BAD_REQUEST, "A Discord user is their id, in digits.");
    }
    let now = Instant::now();
    if !d.redeems.take(0, now) || !d.redeems_by_user.take(body.user.clone(), now) {
        return error(StatusCode::TOO_MANY_REQUESTS, "Too many codes tried. Wait a while, then try again.");
    }
    let lapsed = || error(StatusCode::NOT_FOUND, "That is not a code Ghost.md gave, or it has run out. Make a new one in the app.");
    let Some(code) = typed_code(&body.code) else { return lapsed() };
    let Some(account) = d.accounts.store.take_discord_code(&code_hash(&code), now_secs()) else { return lapsed() };
    let name = clean(body.name.as_deref(), NAME_LIMIT).unwrap_or_else(|| "Discord user".into());
    if d.accounts.store.link_discord(&body.user, account, &name, now_secs()).is_err() {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "That could not be linked just now. Make a new code and try again.");
    }
    Json(json!({ "linked": true })).into_response()
}

#[derive(Deserialize)]
struct Open {
    user: String,
    guild: String,
    channel: String,
    #[serde(default)]
    title: Option<String>,
}

fn call_json(b: &MeetBooking) -> Value {
    json!({ "id": b.id, "state": b.state, "startsAt": b.starts_at, "endsAt": b.ends_at })
}

/// `/ghost join`: a call booked for the account the Discord user is linked to, `joining` now, for the bot to record
/// and hand back. Not linked is 404 (`linked: false`), which the bot answers with how to link; linked with the
/// plugin's "Join Discord calls" off is 403 (`calls: false`), answered with where to turn it on.
async fn open_call(State(d): State<Arc<Discord>>, Json(body): Json<Open>) -> Response {
    if ![&body.user, &body.guild, &body.channel].iter().all(|id| snowflake(id)) {
        return error(StatusCode::BAD_REQUEST, "A user, a server and a channel are each their id, in digits.");
    }
    if !d.calls_by_user.take(body.user.clone(), Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "That is a lot of calls in an hour. Wait a while, then try again.");
    }
    let store = &d.accounts.store;
    let Some(link) = store.discord_link_of_user(&body.user) else {
        return (StatusCode::NOT_FOUND, Json(json!({ "error": "That Discord user is not linked to Ghost.md.", "linked": false }))).into_response();
    };
    if !link.calls {
        return (StatusCode::FORBIDDEN, Json(json!({ "error": "Ghost joining Discord calls is off for that account.", "linked": true, "calls": false }))).into_response();
    }
    if store.account_key(link.account).is_none() {
        return error(StatusCode::CONFLICT, "That account needs its encryption key first: open Ghost.md and sync once.");
    }
    let now = now_ms();
    if store.meet_upcoming(link.account, now) >= meet::UPCOMING {
        return error(StatusCode::TOO_MANY_REQUESTS, "Ghost is booked into as many meetings as it may be. Skip one first.");
    }
    let id = fresh_id();
    let booking = MeetBooking {
        id: id.clone(),
        account: link.account,
        uid: format!("{DISCORD_UID}{id}"),
        url: format!("https://discord.com/channels/{}/{}", body.guild, body.channel),
        title: Some(clean(body.title.as_deref(), meet::TITLE_LIMIT).unwrap_or_else(|| "Discord call".into())),
        starts_at: now,
        ends_at: now + CALL_LENGTH,
        state: "joining".into(),
        detail: None,
        sequence: 0,
        series: None,
        kind: Some("discord".into()),
    };
    match store.insert_meet_booking(&booking, now_secs()) {
        Ok(true) => {
            // The account's devices list it now: "In the meeting" is what Leave now is pressed on.
            d.accounts.pokes.poke(link.account, Poke::Meet);
            Json(json!({ "meeting": call_json(&booking), "name": link.name })).into_response()
        }
        _ => error(StatusCode::INTERNAL_SERVER_ERROR, "Ghost could not be booked just now. Try again."),
    }
}

async fn due(State(d): State<Arc<Discord>>) -> Response {
    let calls: Vec<Value> = d.accounts.store.discord_due(now_ms()).iter().map(call_json).collect();
    Json(json!({ "meetings": calls })).into_response()
}

/// Whether `id` is a Discord call's booking: the only ones these routes act on.
fn is_call(d: &Discord, id: &str) -> bool {
    base64url(id, 1..=64) && d.accounts.store.meet_booking(id).is_some_and(|b| b.uid.starts_with(DISCORD_UID))
}

/// Where the bot is with a call, as the Meet bot's state (`meet::set_state`, its 409s and all); and once it is over
/// (done, failed, skipped), its end is now, not the three hours it was booked for.
async fn call_state(State(d): State<Arc<Discord>>, Path(id): Path<String>, Json(body): Json<StateBody>) -> Response {
    if !is_call(&d, &id) {
        return error(StatusCode::NOT_FOUND, "No Discord call by that id.");
    }
    let over = matches!(body.state.as_str(), "done" | "failed" | "skipped");
    let answered = meet::set_state(State(d.bot.clone()), Path(id.clone()), Json(body)).await;
    if over && answered.status().is_success() {
        d.accounts.store.end_discord_call(&id, now_ms(), now_secs());
    }
    answered
}

/// A call's recording and its speaker turns, sealed on arrival by meet.rs's own `put_take`; the call's end is now.
async fn call_take(State(d): State<Arc<Discord>>, Path(id): Path<String>, multipart: Multipart) -> Response {
    if !is_call(&d, &id) {
        return error(StatusCode::NOT_FOUND, "No Discord call by that id.");
    }
    let answered = meet::put_take(State(d.bot.clone()), Path(id.clone()), multipart).await;
    if answered.status().is_success() {
        d.accounts.store.end_discord_call(&id, now_ms(), now_secs());
    }
    answered
}

/// Every route here, when the Discord bot has a token (`bot_token`); none without one.
pub fn router(accounts: Arc<Accounts>, bot_token: Option<String>) -> Router {
    let Some(token) = bot_token else { return Router::new() };
    let now = Instant::now();
    let d = Arc::new(Discord {
        bot: Arc::new(Bot::new(accounts.clone(), &token)),
        accounts,
        codes: RateLimiter::per_hour(CODES_PER_HOUR, now),
        redeems_by_user: RateLimiter::per_hour(REDEEMS_PER_USER_HOUR, now),
        redeems: RateLimiter::new(REDEEMS_PER_MINUTE, now),
        calls_by_user: RateLimiter::per_hour(CALLS_PER_USER_HOUR, now),
    });
    let device = Router::new()
        .route("/api/v1/discord/link-code", post(link_code))
        .route("/api/v1/discord/link", get(get_link).delete(unlink))
        .route("/api/v1/discord/calls", put(set_calls))
        .with_state(d.clone());
    let internal = Router::new()
        .route("/api/internal/discord/link", post(redeem))
        .route("/api/internal/discord/session", post(open_call))
        .route("/api/internal/discord/due", get(due))
        .route("/api/internal/discord/{id}/state", post(call_state))
        .route("/api/internal/discord/{id}/take", put(call_take).layer(DefaultBodyLimit::max(meet::TAKE_BODY)))
        .route_layer(middleware::from_fn_with_state(d.clone(), bot_only))
        .with_state(d);
    device.merge(internal)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_code_is_eight_of_thirty_unmistakable_letters_shown_with_a_dash_and_read_however_it_is_typed() {
        for _ in 0..200 {
            let code = fresh_code();
            assert_eq!(code.len(), 8);
            assert!(code.bytes().all(|b| CODE_LETTERS.contains(&b)), "{code}");
            assert_eq!(typed_code(&shown_code(&code)).as_deref(), Some(code.as_str()));
        }
        assert_eq!(CODE_LETTERS.len(), 30);
        assert_eq!(typed_code(" k7qm-2xrp ").as_deref(), Some("K7QM2XRP"));
        assert_eq!(typed_code("K7QM 2XRP").as_deref(), Some("K7QM2XRP"));
        for no in ["K7QM-2XR", "K7QM-2XRPP", "K7QM-2XR0", "OOOO-IIII", "K7QM_2XRP", ""] {
            assert_eq!(typed_code(no), None, "{no}");
        }
    }

    #[test]
    fn ids_are_digits_and_names_are_kept_plain() {
        assert!(snowflake("123456789012345678"));
        assert!(!snowflake("12345678901234567a") && !snowflake("123") && !snowflake("1234567890123456789012"));
        assert_eq!(clean(Some("  Sam\n\tLee\u{7} "), 100).as_deref(), Some("Sam Lee"));
        assert_eq!(clean(Some(" \n "), 100), None);
        assert_eq!(clean(Some("abcdef"), 3).as_deref(), Some("abc"));
    }
}
