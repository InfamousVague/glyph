//! Sync: an account's notes, settings, recordings and pictures, as ciphertext, kept the same on every device
//! (docs/SYNC.md).
//!
//! AttackFM's two shapes, copied: its library's change feed (a revision counter, deletions kept as markers, paged),
//! and its settings blob (written from a revision, refused with the winner when stale). The one difference is that
//! every device writes notes here, not only the server, so a note is written from the revision it was last seen at,
//! exactly as the settings blob is.
//!
//!   GET    /glyph/api/v1/notes?since=&limit=   the feed: every note written after `since`
//!   PUT    /glyph/api/v1/notes/{id}            { base, blob } a note, or 409 with the one that won
//!   DELETE /glyph/api/v1/notes/{id}            { base } a deletion, the same way
//!   GET    /glyph/api/v1/prefs                 the settings
//!   PUT    /glyph/api/v1/prefs                 { base, blob }
//!   GET    /glyph/api/v1/recordings/{id}       a recording's or a picture's bytes, its revision in `x-glyph-rev`
//!   PUT    /glyph/api/v1/recordings/{id}?base= a recording's or a picture's bytes
//!
//! The recordings routes carry pictures too (an `i-<ext>-<stem>` id, docs/SYNC.md): they were named for the audio
//! that came first. A device asks whether it has a picture's latest with a HEAD, which axum answers through the GET
//! handler with the body dropped, so the file is read to send its header.
//!
//! Every body here is something a device encrypted. The service checks sizes and shapes, never content.

use crate::accounts::Accounts;
use crate::identity::Claims;
use crate::store::{NoteRow, WriteError};
use crate::wire::{base64url, error, now_secs};
use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;

/// A note's ciphertext, as base64: a megabyte of note and its encoding.
const NOTE_LIMIT: usize = 1_400_000;
/// Settings, as base64.
const PREFS_LIMIT: usize = 350_000;
/// A recording's or a picture's ciphertext. A long voice note at 16 kHz mono is a few megabytes; this is well past
/// any of them.
const RECORDING_LIMIT: usize = 64 * 1024 * 1024;
/// The most notes one page of the feed carries.
const PAGE_LIMIT: i64 = 500;
/// How long a note's, a recording's or a picture's id may be.
const ID_LENGTH: std::ops::RangeInclusive<usize> = 1..=64;

/// Ids are the app's own: a note's UUID or its older `n-…` form, a recording's `r-<note id>`, a picture's
/// `i-<ext>-<stem>`. Anything else is refused before it reaches a path.
fn valid_id(id: &str) -> bool {
    base64url(id, ID_LENGTH)
}

/// A blob is base64url, as a device writes it.
fn valid_blob(blob: &str, limit: usize) -> bool {
    base64url(blob, 1..=limit)
}

fn note_json(note: &NoteRow) -> serde_json::Value {
    json!({ "id": note.id, "rev": note.rev, "deleted": note.deleted, "blob": note.blob })
}

#[derive(Deserialize)]
struct FeedQuery {
    #[serde(default)]
    since: i64,
    limit: Option<i64>,
}

async fn feed(State(accounts): State<Arc<Accounts>>, Query(query): Query<FeedQuery>, who: Claims) -> Response {
    let limit = query.limit.unwrap_or(PAGE_LIMIT).clamp(1, PAGE_LIMIT);
    match accounts.store.notes_since(who.sub, query.since.max(0), limit) {
        Ok((notes, more, head)) => {
            // The cursor is the last note given when there is more to come, and the account's head when there is not,
            // so a device that has everything also knows it has seen every write up to now.
            let rev = if more { notes.last().map(|n| n.rev).unwrap_or(head) } else { head };
            Json(json!({ "rev": rev, "items": notes.iter().map(note_json).collect::<Vec<_>>(), "more": more })).into_response()
        }
        Err(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "The notes could not be read."),
    }
}

#[derive(Deserialize)]
struct NoteBody {
    #[serde(default)]
    base: i64,
    #[serde(default)]
    blob: Option<String>,
}

/// A write's answer, for notes, settings and recordings alike: its new revision; or 409 with what won, as `winner`
/// renders it, so the device can merge and try again rather than guess what it collided with; or a 500 in the words
/// `could_not`. A stale write with nothing to show - settings written from a base when none were ever stored - is
/// answered as the failure, as it always has been: the app always writes settings from the revision it just read.
fn written<W>(result: Result<i64, WriteError<W>>, winner: impl FnOnce(W) -> Option<serde_json::Value>, could_not: &str) -> Response {
    match result {
        Ok(rev) => Json(json!({ "rev": rev })).into_response(),
        Err(WriteError::Stale(won)) => match winner(won) {
            Some(body) => (StatusCode::CONFLICT, Json(body)).into_response(),
            None => error(StatusCode::INTERNAL_SERVER_ERROR, could_not),
        },
        Err(WriteError::Failed) => error(StatusCode::INTERNAL_SERVER_ERROR, could_not),
    }
}

/// A note's write, answered: the winner is the stored note.
fn note_written(result: Result<i64, WriteError<NoteRow>>) -> Response {
    written(result, |winner| Some(note_json(&winner)), "That note could not be stored.")
}

async fn put_note(State(accounts): State<Arc<Accounts>>, Path(id): Path<String>, who: Claims, Json(body): Json<NoteBody>) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That note id could not be read.");
    }
    let Some(blob) = body.blob.as_deref().filter(|b| valid_blob(b, NOTE_LIMIT)) else {
        return error(StatusCode::BAD_REQUEST, "That note is empty or too large to sync.");
    };
    note_written(accounts.store.put_note(who.sub, &id, body.base, Some(blob), now_secs()))
}

async fn delete_note(State(accounts): State<Arc<Accounts>>, Path(id): Path<String>, who: Claims, Json(body): Json<NoteBody>) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That note id could not be read.");
    }
    note_written(accounts.store.put_note(who.sub, &id, body.base, None, now_secs()))
}

async fn get_prefs(State(accounts): State<Arc<Accounts>>, who: Claims) -> Response {
    // Rev 0 and no blob says "nothing has ever been stored": a device keeps what it has and pushes it.
    let (rev, blob) = accounts.store.prefs(who.sub).map_or((0, None), |(rev, blob)| (rev, Some(blob)));
    Json(json!({ "rev": rev, "blob": blob })).into_response()
}

#[derive(Deserialize)]
struct PrefsBody {
    #[serde(default)]
    base: i64,
    blob: String,
}

async fn put_prefs(State(accounts): State<Arc<Accounts>>, who: Claims, Json(body): Json<PrefsBody>) -> Response {
    if !valid_blob(&body.blob, PREFS_LIMIT) {
        return error(StatusCode::BAD_REQUEST, "Those settings are empty or too large to sync.");
    }
    written(
        accounts.store.put_prefs(who.sub, body.base, &body.blob, now_secs()),
        |stored| stored.map(|(rev, blob)| json!({ "rev": rev, "blob": blob })),
        "Those settings could not be stored.",
    )
}

async fn get_recording(State(accounts): State<Arc<Accounts>>, Path(id): Path<String>, who: Claims) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That recording id could not be read.");
    }
    match accounts.store.recording(who.sub, &id) {
        Some((rev, bytes)) => {
            let mut response = (StatusCode::OK, bytes).into_response();
            let headers = response.headers_mut();
            headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/octet-stream"));
            headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
            if let Ok(value) = HeaderValue::from_str(&rev.to_string()) {
                headers.insert("x-glyph-rev", value);
            }
            response
        }
        None => error(StatusCode::NOT_FOUND, "No recording by that id."),
    }
}

#[derive(Deserialize)]
struct RecordingQuery {
    #[serde(default)]
    base: i64,
}

async fn put_recording(
    State(accounts): State<Arc<Accounts>>,
    Path(id): Path<String>,
    Query(query): Query<RecordingQuery>,
    who: Claims,
    body: Bytes,
) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That recording id could not be read.");
    }
    if body.is_empty() {
        return error(StatusCode::BAD_REQUEST, "That recording is empty.");
    }
    written(
        accounts.store.put_recording(who.sub, &id, query.base, &body, now_secs()),
        |rev| Some(json!({ "rev": rev })),
        "That recording could not be stored.",
    )
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    Router::new()
        .route("/glyph/api/v1/notes", get(feed))
        .route("/glyph/api/v1/notes/{id}", axum::routing::put(put_note).delete(delete_note))
        .route("/glyph/api/v1/prefs", get(get_prefs).put(put_prefs))
        .route(
            "/glyph/api/v1/recordings/{id}",
            get(get_recording).put(put_recording).layer(DefaultBodyLimit::max(RECORDING_LIMIT)),
        )
        .with_state(accounts)
}
