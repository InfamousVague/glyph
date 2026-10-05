//! Team notes on the wire (docs/SHARED.md, S4, S5; store/org_notes.rs): an organization's notes, each note's CRDT
//! update log, and the organization's sealed files, for its members. The shapes are the account's (sync.rs), under
//! the organization, and as there every body is something a device sealed - under the organization key - that the
//! service checks for size and shape, never content.
//!
//!   GET    /api/v1/orgs/{id}/notes?since=&limit=              the feed: every note written after `since`
//!   PUT    /api/v1/orgs/{id}/notes/{nid}                      { base, blob, upTo?, generation? } a note; `upTo` cuts its log to there
//!   DELETE /api/v1/orgs/{id}/notes/{nid}                      { base } a deletion, which takes the log
//!   GET    /api/v1/orgs/{id}/heads                             each live note's log head, in one read
//!   GET    /api/v1/orgs/{id}/notes/{nid}/updates?since=&limit= the log after `since`
//!   POST   /api/v1/orgs/{id}/notes/{nid}/updates              { blobs, generation? } appended in order; answers the last seq; 409 "snapshot" past UPDATES_KEPT
//!   GET    /api/v1/orgs/{id}/files/{fid}                      a file's bytes, its revision in `x-glyph-rev` (HEAD too)
//!   PUT    /api/v1/orgs/{id}/files/{fid}?base=&generation=    a file's bytes
//!
//! `generation` names the key the body is sealed under (S11): one that is not the generation in force is refused
//! 409 with the one in force, so a device that slept through a turn re-seals rather than writing what nobody can open.
//!
//! A stranger to the organization, and an invitee who has not joined, get one 404 from every route, "No such
//! organization.", as from the organization's own routes (orgs.rs).
use crate::accounts::Accounts;
use crate::identity::Claims;
use crate::store::{OrgNoteRow, OrgNoteWrite, UpdateRow};
use crate::wire::{base64url, error, millis, now_secs};
use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;

/// A note's ciphertext, as base64: a megabyte of note and its encoding (sync.rs `NOTE_LIMIT`).
const NOTE_LIMIT: usize = 1_400_000;
/// One update of the log, as base64: a frame's worth (live.rs `MAX_FRAME`) and its encoding.
const UPDATE_LIMIT: usize = 90_000;
/// Updates in one post.
const UPDATES_PER_POST: usize = 100;
/// A file's ciphertext: a versions file or a picture; the account's recordings' limit (sync.rs).
const FILE_LIMIT: usize = 64 * 1024 * 1024;
/// The most rows one page of a feed or a log carries.
const PAGE_LIMIT: i64 = 500;
/// Team notes one organization may hold (SHARED.md, S11).
pub const NOTES_PER_ORG: i64 = 2000;
const ID_LENGTH: std::ops::RangeInclusive<usize> = 1..=64;

fn valid_id(id: &str) -> bool {
    base64url(id, ID_LENGTH)
}

fn valid_blob(blob: &str, limit: usize) -> bool {
    base64url(blob, 1..=limit)
}

fn note_json(note: &OrgNoteRow) -> serde_json::Value {
    json!({ "id": note.id, "rev": note.rev, "deleted": note.deleted, "blob": note.blob, "by": note.by, "updatedAt": millis(note.updated_at) })
}

fn update_json(update: &UpdateRow) -> serde_json::Value {
    json!({ "seq": update.seq, "blob": update.blob, "by": update.by, "at": millis(update.at) })
}

/// The store's refusals, each in its words; a stale note carries the row that won, a stale file its revision.
fn refused(err: OrgNoteWrite) -> Response {
    match err {
        OrgNoteWrite::NoSuchOrg => error(StatusCode::NOT_FOUND, "No such organization."),
        OrgNoteWrite::NoSuchNote => error(StatusCode::NOT_FOUND, "No such note."),
        OrgNoteWrite::Stale(winner) => (StatusCode::CONFLICT, Json(note_json(&winner))).into_response(),
        OrgNoteWrite::StaleFile(rev) => (StatusCode::CONFLICT, Json(json!({ "rev": rev }))).into_response(),
        OrgNoteWrite::Full => error(StatusCode::CONFLICT, "The organization holds as many notes as it can."),
        OrgNoteWrite::Generation(in_force) => (StatusCode::CONFLICT, Json(json!({ "error": "That is not the generation in force.", "generation": in_force }))).into_response(),
        OrgNoteWrite::LogFull(seq) => (StatusCode::CONFLICT, Json(json!({ "error": "snapshot", "seq": seq }))).into_response(),
        OrgNoteWrite::Failed => error(StatusCode::INTERNAL_SERVER_ERROR, "That could not be stored."),
    }
}

/// An organization's id, and a note's or a file's, that will read: refused before anything is looked up.
fn ids(org: &str, id: Option<&str>) -> Result<(), Response> {
    if !valid_id(org) {
        return Err(error(StatusCode::BAD_REQUEST, "That organization's id could not be read."));
    }
    if id.is_some_and(|id| !valid_id(id)) {
        return Err(error(StatusCode::BAD_REQUEST, "That id could not be read."));
    }
    Ok(())
}

#[derive(Deserialize)]
struct SinceQuery {
    #[serde(default)]
    since: i64,
    limit: Option<i64>,
}

async fn feed(State(accounts): State<Arc<Accounts>>, Path(org): Path<String>, Query(query): Query<SinceQuery>, who: Claims) -> Result<Response, Response> {
    ids(&org, None)?;
    let limit = query.limit.unwrap_or(PAGE_LIMIT).clamp(1, PAGE_LIMIT);
    match accounts.store.org_notes_since(who.sub, &org, query.since.max(0), limit) {
        Ok((notes, more, head)) => {
            let rev = if more { notes.last().map(|n| n.rev).unwrap_or(head) } else { head };
            Ok(Json(json!({ "rev": rev, "items": notes.iter().map(note_json).collect::<Vec<_>>(), "more": more })).into_response())
        }
        Err(err) => Err(refused(err)),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NoteBody {
    #[serde(default)]
    base: i64,
    #[serde(default)]
    blob: Option<String>,
    /// The log's seq this write's snapshot covers: the updates up to it are cut.
    #[serde(default)]
    up_to: Option<i64>,
    /// The key's generation the blob is sealed under (S11): refused with the one in force when it is not that.
    #[serde(default)]
    generation: Option<i64>,
}

fn written(result: Result<i64, OrgNoteWrite>) -> Response {
    match result {
        Ok(rev) => Json(json!({ "rev": rev })).into_response(),
        Err(err) => refused(err),
    }
}

async fn put_note(State(accounts): State<Arc<Accounts>>, Path((org, note)): Path<(String, String)>, who: Claims, Json(body): Json<NoteBody>) -> Result<Response, Response> {
    ids(&org, Some(&note))?;
    let Some(blob) = body.blob.as_deref().filter(|b| valid_blob(b, NOTE_LIMIT)) else {
        return Err(error(StatusCode::BAD_REQUEST, "That note is empty or too large to sync."));
    };
    Ok(written(accounts.store.put_org_note(who.sub, &org, &note, body.base, Some(blob), body.up_to, body.generation, NOTES_PER_ORG, now_secs())))
}

async fn delete_note(State(accounts): State<Arc<Accounts>>, Path((org, note)): Path<(String, String)>, who: Claims, Json(body): Json<NoteBody>) -> Result<Response, Response> {
    ids(&org, Some(&note))?;
    Ok(written(accounts.store.put_org_note(who.sub, &org, &note, body.base, None, None, None, NOTES_PER_ORG, now_secs())))
}

async fn updates(State(accounts): State<Arc<Accounts>>, Path((org, note)): Path<(String, String)>, Query(query): Query<SinceQuery>, who: Claims) -> Result<Response, Response> {
    ids(&org, Some(&note))?;
    let limit = query.limit.unwrap_or(PAGE_LIMIT).clamp(1, PAGE_LIMIT);
    match accounts.store.org_updates_since(who.sub, &org, &note, query.since.max(0), limit) {
        Ok((rows, more, head)) => {
            let seq = if more { rows.last().map(|u| u.seq).unwrap_or(head) } else { head };
            Ok(Json(json!({ "seq": seq, "items": rows.iter().map(update_json).collect::<Vec<_>>(), "more": more })).into_response())
        }
        Err(err) => Err(refused(err)),
    }
}

/// `GET orgs/{id}/heads`: each live note's log head, so a device reads only the logs that moved.
async fn heads(State(accounts): State<Arc<Accounts>>, Path(org): Path<String>, who: Claims) -> Result<Response, Response> {
    ids(&org, None)?;
    match accounts.store.org_note_heads(who.sub, &org) {
        Ok(heads) => Ok(Json(json!({ "heads": heads.into_iter().map(|(id, seq)| (id, json!(seq))).collect::<serde_json::Map<_, _>>() })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

#[derive(Deserialize)]
struct UpdatesBody {
    #[serde(default)]
    blobs: Vec<String>,
    #[serde(default)]
    generation: Option<i64>,
}

async fn post_updates(State(accounts): State<Arc<Accounts>>, Path((org, note)): Path<(String, String)>, who: Claims, Json(body): Json<UpdatesBody>) -> Result<Response, Response> {
    ids(&org, Some(&note))?;
    if body.blobs.is_empty() || body.blobs.len() > UPDATES_PER_POST || !body.blobs.iter().all(|b| valid_blob(b, UPDATE_LIMIT)) {
        return Err(error(StatusCode::BAD_REQUEST, "Those updates could not be read."));
    }
    match accounts.store.post_org_updates(who.sub, &org, &note, &body.blobs, body.generation, now_secs()) {
        Ok(seq) => Ok(Json(json!({ "seq": seq })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

async fn get_file(State(accounts): State<Arc<Accounts>>, Path((org, file)): Path<(String, String)>, who: Claims) -> Result<Response, Response> {
    ids(&org, Some(&file))?;
    match accounts.store.org_file(who.sub, &org, &file) {
        Ok(Some((rev, bytes))) => {
            let mut response = (StatusCode::OK, bytes).into_response();
            let headers = response.headers_mut();
            headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/octet-stream"));
            headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
            if let Ok(value) = HeaderValue::from_str(&rev.to_string()) {
                headers.insert("x-glyph-rev", value);
            }
            Ok(response)
        }
        Ok(None) => Err(error(StatusCode::NOT_FOUND, "No file by that id.")),
        Err(err) => Err(refused(err)),
    }
}

#[derive(Deserialize)]
struct FileQuery {
    #[serde(default)]
    base: i64,
    #[serde(default)]
    generation: Option<i64>,
}

async fn put_file(State(accounts): State<Arc<Accounts>>, Path((org, file)): Path<(String, String)>, Query(query): Query<FileQuery>, who: Claims, body: Bytes) -> Result<Response, Response> {
    ids(&org, Some(&file))?;
    if body.is_empty() {
        return Err(error(StatusCode::BAD_REQUEST, "That file is empty."));
    }
    Ok(written(accounts.store.put_org_file(who.sub, &org, &file, query.base, query.generation, &body, now_secs())))
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    Router::new()
        .route("/api/v1/orgs/{id}/notes", get(feed))
        .route("/api/v1/orgs/{id}/heads", get(heads))
        .route("/api/v1/orgs/{id}/notes/{nid}", axum::routing::put(put_note).delete(delete_note))
        .route("/api/v1/orgs/{id}/notes/{nid}/updates", get(updates).post(post_updates).layer(DefaultBodyLimit::max(UPDATES_PER_POST * UPDATE_LIMIT + 4096)))
        .route("/api/v1/orgs/{id}/files/{fid}", get(get_file).put(put_file).layer(DefaultBodyLimit::max(FILE_LIMIT)))
        .with_state(accounts)
}
