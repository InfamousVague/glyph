//! Shares: a note or a book, readable by anyone with its link, and nobody else - this service included (docs/SHARING.md).
//!
//! Matt: "share books and notes with people online and allow them to read only the notes and give them areas to fork
//! the note into their own Ghost.md app". A device seals what it shares under a key of its own, made for that share,
//! and puts the key in the link after the `#`, which a browser never sends: so the link reads the share, and the
//! service keeps only ciphertext it cannot open, the same promise sync makes. The owner writes it again as they edit
//! (the reader sees the edits), and takes it down to make the link go dead.
//!
//!   PUT    /api/v1/shares/{id}   { blob }  the owner's share, made or written again
//!   DELETE /api/v1/shares/{id}             the owner's share, taken down
//!   GET    /api/v1/shares                  the owner's shares: ids and when each was last written
//!   GET    /api/v1/shares/{id}             anyone: the ciphertext, and when it was written
//!
//! An id is the device's own - 128 random bits, base64url - so the link can be made before anything is sent, and one
//! share's id says nothing about another's. Reading is open, so it is rate-limited by address; writing is the owner's.
//!
//! A shared meeting can carry its recording (Matt, 2026-10-29: "Update the web version of the meeting transcripts to
//! include the casette tape and the per user transcript so we can listen along"): tens of megabytes, past what a
//! share holds, so it is an object of its own beside the share, sealed by the device a part at a time under the same
//! key, and as unreadable here as the words (store/share_audio.rs keeps it):
//!
//!   PUT    /api/v1/shares/{id}/audio/{upload}/{n}  part n of an upload, the bytes as they are     the owner
//!   POST   /api/v1/shares/{id}/audio               { upload, parts }: that upload whole, kept     the owner
//!   DELETE /api/v1/shares/{id}/audio               the recording taken down                       the owner
//!   GET    /api/v1/shares/{id}/audio               anyone: every part, each as its length (four bytes, big-endian)
//!                                                  and its bytes, in order, streamed as the file is read
//!
//! Parts let an hour's recording go up a megabyte at a time and a reader start on the first while the rest arrive.
//! A share's recording may be [`AUDIO_LIMIT`] and an account's together [`AUDIO_PER_ACCOUNT`]; reading one is
//! limited by address on its own, more tightly than the words, since each read is megabytes. Taking the share down
//! takes its recording with it.

use crate::accounts::{Accounts, HasAccounts};
use crate::guard;
use crate::identity::Claims;
use crate::store::{AudioWrite, ShareWrite};
use crate::wire::{base64url, error, now_secs};
use axum::body::{Body, Bytes};
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, put};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::json;
use std::io::Read;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

/// A share's ciphertext, as base64url: a book of its index and every chapter, generously.
const SHARE_LIMIT: usize = 6_000_000;
/// The most shares one account keeps up at once.
const SHARES_PER_ACCOUNT: i64 = 500;
/// Reads of shares, per address, per minute: a reader opening a book and its chapters, several times over.
const READS_PER_MINUTE: u32 = 240;
/// How long a share's id may be. The app's are 128 random bits, which is 22 base64url characters.
const ID_LENGTH: std::ops::RangeInclusive<usize> = 22..=64;

/// The most a share's recording may be, as kept: its parts and their lengths. A meeting's WAV, 16 kHz mono, is
/// 115 MB an hour, so this is an hour and three quarters of one (lib/share/share_audio.dart says so before sending).
pub const AUDIO_LIMIT: u64 = 200 * 1024 * 1024;
/// The most one account's shared recordings may be together, kept and still being sent.
pub const AUDIO_PER_ACCOUNT: u64 = 2 * 1024 * 1024 * 1024;
/// The most a part may be: a device sends a megabyte of sound at a time, sealed.
const AUDIO_PART_LIMIT: usize = 4 * 1024 * 1024;
/// How many parts a recording may have.
const AUDIO_PARTS: u32 = 1024;
/// Reads of a recording, per address, per minute: a reader opening a meeting, and opening it again.
const AUDIO_READS_PER_MINUTE: u32 = 20;
/// An upload's id, the device's own: 128 random bits at least.
const UPLOAD_LENGTH: std::ops::RangeInclusive<usize> = 16..=43;
/// How much of a recording's file is read at a time as it is streamed.
const AUDIO_READ: usize = 256 * 1024;

pub struct Shares {
    accounts: Arc<Accounts>,
    readers: guard::RateLimiter,
    listeners: guard::RateLimiter,
}

impl Shares {
    pub fn new(accounts: Arc<Accounts>) -> Arc<Self> {
        let now = Instant::now();
        Arc::new(Self { accounts, readers: guard::RateLimiter::new(READS_PER_MINUTE, now), listeners: guard::RateLimiter::new(AUDIO_READS_PER_MINUTE, now) })
    }
}

/// Where the `Claims` extractor (accounts.rs) finds the accounts behind this router's own state.
impl HasAccounts for Arc<Shares> {
    fn accounts(&self) -> &Accounts {
        &self.accounts
    }
}

/// A share's id, as a device makes one: 22 to 64 base64url characters.
fn valid_id(id: &str) -> bool {
    base64url(id, ID_LENGTH)
}

#[derive(Deserialize)]
struct ShareBody {
    blob: String,
}

async fn put_share(State(shares): State<Arc<Shares>>, Path(id): Path<String>, who: Claims, Json(body): Json<ShareBody>) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That share's id could not be read.");
    }
    // What a device sends: base64url ciphertext, not empty, under the limit.
    if !base64url(&body.blob, 1..=SHARE_LIMIT) {
        return error(StatusCode::BAD_REQUEST, "That share is empty or too large.");
    }
    match shares.accounts.store.put_share(who.sub, &id, &body.blob, now_secs(), SHARES_PER_ACCOUNT) {
        Ok(updated) => Json(json!({ "id": id, "updated": updated })).into_response(),
        Err(ShareWrite::Taken) => error(StatusCode::CONFLICT, "That share belongs to someone else."),
        Err(ShareWrite::Full) => error(StatusCode::CONFLICT, "This account shares as much as it can: take a share down first."),
        Err(ShareWrite::Failed) => error(StatusCode::INTERNAL_SERVER_ERROR, "That share could not be kept."),
    }
}

async fn delete_share(State(shares): State<Arc<Shares>>, Path(id): Path<String>, who: Claims) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That share's id could not be read.");
    }
    // Taking down what is not there, or not yours, answers the same as taking down your own: nothing to learn by asking.
    shares.accounts.store.delete_share(who.sub, &id);
    StatusCode::NO_CONTENT.into_response()
}

async fn list_shares(State(shares): State<Arc<Shares>>, who: Claims) -> Response {
    let list: Vec<_> = shares.accounts.store.shares_of(who.sub).into_iter().map(|(id, updated)| json!({ "id": id, "updated": updated })).collect();
    Json(json!({ "shares": list })).into_response()
}

async fn read_share(State(shares): State<Arc<Shares>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Path(id): Path<String>) -> Response {
    if !shares.readers.take(guard::client_ip_of(peer.ip(), &headers), Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "Too many reads in a minute. Try again shortly.");
    }
    if !valid_id(&id) {
        return error(StatusCode::NOT_FOUND, "Nothing is shared at that link.");
    }
    let Some((blob, updated)) = shares.accounts.store.share(&id) else {
        return error(StatusCode::NOT_FOUND, "Nothing is shared at that link. It may have been taken down.");
    };
    let mut response = Json(json!({ "blob": blob, "updated": updated })).into_response();
    // Always asked again: a reader should see the owner's latest edit, and a share taken down should go at once.
    response.headers_mut().insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

// ---- a meeting's recording ------------------------------------------------------------------------------------------

/// What a refused part or commit is told.
fn audio_refused(why: AudioWrite) -> Response {
    match why {
        AudioWrite::NoShare => error(StatusCode::NOT_FOUND, "There is no share of yours at that link. Share the meeting first."),
        AudioWrite::TooLarge => error(StatusCode::PAYLOAD_TOO_LARGE, "That recording is longer than a share can carry."),
        AudioWrite::AccountFull => error(StatusCode::CONFLICT, "This account shares as much recording as it can: take a meeting's share down first."),
        AudioWrite::Missing => error(StatusCode::CONFLICT, "Not every part of that recording has arrived. Send it again."),
        AudioWrite::Failed => error(StatusCode::INTERNAL_SERVER_ERROR, "That recording could not be kept."),
    }
}

async fn put_audio_part(State(shares): State<Arc<Shares>>, Path((id, upload, n)): Path<(String, String, u32)>, who: Claims, body: Bytes) -> Response {
    if !valid_id(&id) || !base64url(&upload, UPLOAD_LENGTH) || n >= AUDIO_PARTS {
        return error(StatusCode::BAD_REQUEST, "That part of a recording could not be read.");
    }
    if body.is_empty() {
        return error(StatusCode::BAD_REQUEST, "That part of a recording is empty.");
    }
    let store = shares.accounts.store.clone();
    let kept = tokio::task::spawn_blocking(move || store.put_share_audio_part(who.sub, &id, &upload, n, &body, AUDIO_LIMIT, AUDIO_PER_ACCOUNT)).await;
    match kept {
        Ok(Ok(())) => StatusCode::NO_CONTENT.into_response(),
        Ok(Err(why)) => audio_refused(why),
        Err(_) => audio_refused(AudioWrite::Failed),
    }
}

#[derive(Deserialize)]
struct AudioCommit {
    upload: String,
    parts: u32,
}

async fn commit_audio(State(shares): State<Arc<Shares>>, Path(id): Path<String>, who: Claims, Json(body): Json<AudioCommit>) -> Response {
    if !valid_id(&id) || !base64url(&body.upload, UPLOAD_LENGTH) || body.parts == 0 || body.parts > AUDIO_PARTS {
        return error(StatusCode::BAD_REQUEST, "That recording could not be read.");
    }
    let store = shares.accounts.store.clone();
    let upload = body.upload.clone();
    let kept = tokio::task::spawn_blocking(move || store.commit_share_audio(who.sub, &id, &upload, body.parts, now_secs(), AUDIO_LIMIT)).await;
    match kept {
        Ok(Ok(size)) => Json(json!({ "upload": body.upload, "parts": body.parts, "size": size })).into_response(),
        Ok(Err(why)) => audio_refused(why),
        Err(_) => audio_refused(AudioWrite::Failed),
    }
}

async fn delete_audio(State(shares): State<Arc<Shares>>, Path(id): Path<String>, who: Claims) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That share's id could not be read.");
    }
    // As a share's own take-down: another's, or none, answers the same.
    let store = shares.accounts.store.clone();
    let _ = tokio::task::spawn_blocking(move || store.delete_share_audio(who.sub, &id)).await;
    StatusCode::NO_CONTENT.into_response()
}

/// The recording's file, a piece at a time, as it is read: an hour's is never held whole in memory here.
fn streamed(file: std::fs::File) -> Body {
    let pieces = futures_util::stream::unfold(Some(file), |file| async move {
        let mut file = file?;
        let read = tokio::task::spawn_blocking(move || {
            let mut piece = vec![0u8; AUDIO_READ];
            let n = file.read(&mut piece)?;
            piece.truncate(n);
            Ok::<_, std::io::Error>((file, piece))
        })
        .await
        .unwrap_or_else(|_| Err(std::io::Error::other("the read stopped")));
        match read {
            Ok((_, piece)) if piece.is_empty() => None,
            Ok((file, piece)) => Some((Ok(Bytes::from(piece)), Some(file))),
            Err(failed) => Some((Err(failed), None)),
        }
    });
    Body::from_stream(pieces)
}

async fn read_audio(State(shares): State<Arc<Shares>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Path(id): Path<String>) -> Response {
    if !shares.listeners.take(guard::client_ip_of(peer.ip(), &headers), Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "Too many plays in a minute. Try again shortly.");
    }
    let gone = || error(StatusCode::NOT_FOUND, "This share carries no recording. It may have been taken down.");
    if !valid_id(&id) {
        return gone();
    }
    let store = shares.accounts.store.clone();
    let opened = tokio::task::spawn_blocking(move || {
        let audio = store.share_audio(&id)?;
        let file = std::fs::File::open(&audio.path).ok()?;
        let size = file.metadata().ok()?.len();
        Some((file, size))
    })
    .await
    .ok()
    .flatten();
    let Some((file, size)) = opened else { return gone() };
    let mut response = Response::new(streamed(file));
    let kept = response.headers_mut();
    kept.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/octet-stream"));
    kept.insert(header::CONTENT_LENGTH, HeaderValue::from(size));
    // As the words: asked again each time, so a recording taken down goes at once.
    kept.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    Router::new()
        .route("/api/v1/shares", get(list_shares))
        .route(
            "/api/v1/shares/{id}",
            get(read_share).put(put_share).delete(delete_share).layer(DefaultBodyLimit::max(SHARE_LIMIT + 1024)),
        )
        .route("/api/v1/shares/{id}/audio", get(read_audio).post(commit_audio).delete(delete_audio))
        .route("/api/v1/shares/{id}/audio/{upload}/{n}", put(put_audio_part).layer(DefaultBodyLimit::max(AUDIO_PART_LIMIT)))
        .with_state(Shares::new(accounts))
}
