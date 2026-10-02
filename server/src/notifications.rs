//! Notifications: what an account is told, read as a feed on the account's own write counter (docs/TEAMS.md).
//!
//! Matt: "implement a full notification system and put the invites in there with an inline accept and deny also
//! wire up existing features to notifications where it makes sense so that we see things like claude creating a new
//! note or making edits". The service writes the rows it knows of - invitations and team changes, from src/orgs.rs -
//! and a device posts the rows only it knows of, sealed under the account key as its notes are: Claude's edits, a
//! summary written, a conflict kept. Read marks and hiding live here too, so they follow the person across devices;
//! each takes a new revision and the row is fed again, hidden ones included, as deletions ride the notes feed.
//!
//!   GET    /api/v1/notifications?since=&limit=   the feed: every row written after `since`
//!   POST   /api/v1/notifications                 { id, kind, blob }  a device's own row, sealed
//!   POST   /api/v1/notifications/read            { ids?, all?, before? }  read marks
//!   PUT    /api/v1/notifications/{id}            { read?, hidden? }
//!
//! A post is the device's to make, so it is limited to sixty a minute per account, a blob to 8 KB and a body to 16 KB;
//! a kind the service writes cannot be posted. A post with an id the account already has answers that row's revision
//! and writes nothing, so a device's retry of one whose answer was lost lands once (store/notifications.rs).

// A refusal here is the response itself, handed straight back from a handler; boxing it would only move it.
#![allow(clippy::result_large_err)]

use crate::accounts::{Accounts, HasAccounts};
use crate::guard;
use crate::identity::Claims;
use crate::store::{NotificationRow, NotificationWrite, SERVER_KINDS};
use crate::wire::{base64url, error, now_secs};
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post as post_to};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::{json, Value};
use std::sync::Arc;
use std::time::Instant;

/// A device's posts, a minute, per account: an MCP session editing note after note.
const POSTS_PER_MINUTE: u32 = 60;
/// A sealed blob, as base64url: a kind, a note's id and title, a few lines of diff.
const BLOB_LIMIT: usize = 8 * 1024;
/// A body: the blob and a little around it.
const BODY_LIMIT: usize = 16 * 1024;
/// The most rows one page of the feed carries, and the page when none is asked for.
const PAGE_LIMIT: i64 = 200;
const DEFAULT_PAGE: i64 = 100;
/// An id is the device's own, at the length notes are (sync.rs); the service's are 22 characters.
const ID_LENGTH: std::ops::RangeInclusive<usize> = 1..=64;
/// A kind: lowercase words joined by dashes, as the kinds table writes them.
const KIND_LENGTH: std::ops::RangeInclusive<usize> = 1..=32;

pub struct Notifications {
    accounts: Arc<Accounts>,
    posts: guard::RateLimiter<i64>,
}

impl Notifications {
    pub fn new(accounts: Arc<Accounts>) -> Arc<Self> {
        Arc::new(Self { accounts, posts: guard::RateLimiter::new(POSTS_PER_MINUTE, Instant::now()) })
    }
}

/// Where the `Claims` extractor (accounts.rs) finds the accounts behind this router's own state.
impl HasAccounts for Arc<Notifications> {
    fn accounts(&self) -> &Accounts {
        &self.accounts
    }
}

fn valid_id(id: &str) -> bool {
    base64url(id, ID_LENGTH)
}

fn valid_kind(kind: &str) -> bool {
    KIND_LENGTH.contains(&kind.len()) && kind.bytes().all(|b| b.is_ascii_lowercase() || b == b'-')
}

/// A row as the feed answers it. Every row has `id`, `rev`, `kind`, `at`, `readAt` and `hidden`. A row the service
/// wrote has `from` (a handle, or null once that account is gone), `org` ({ id, name }) and, when it has one, `body`
/// and `state`; a device's own row has `blob` and nothing else. A field that does not apply is absent, not null.
fn row_json(row: &NotificationRow) -> Value {
    let mut json = json!({ "id": row.id, "rev": row.rev, "kind": row.kind, "at": row.at, "readAt": row.read_at, "hidden": row.hidden });
    if let Some((id, name)) = &row.org {
        json["from"] = json!(row.from);
        json["org"] = json!({ "id": id, "name": name });
    }
    if let Some(body) = &row.body {
        json["body"] = body.clone();
    }
    if let Some(blob) = &row.blob {
        json["blob"] = json!(blob);
    }
    if let Some(state) = &row.state {
        json["state"] = json!(state);
    }
    json
}

#[derive(Deserialize)]
struct FeedQuery {
    #[serde(default)]
    since: i64,
    limit: Option<i64>,
}

async fn feed(State(notifications): State<Arc<Notifications>>, Query(query): Query<FeedQuery>, who: Claims) -> Response {
    let limit = query.limit.unwrap_or(DEFAULT_PAGE).clamp(1, PAGE_LIMIT);
    match notifications.accounts.store.notifications_since(who.sub, query.since.max(0), limit) {
        Ok((rows, more, head)) => {
            // The cursor rule the notes feed keeps (sync.rs): the last row given when there is more, else the head.
            let rev = if more { rows.last().map(|n| n.rev).unwrap_or(head) } else { head };
            Json(json!({ "rev": rev, "items": rows.iter().map(row_json).collect::<Vec<_>>(), "more": more })).into_response()
        }
        Err(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "The notifications could not be read."),
    }
}

#[derive(Deserialize)]
struct PostBody {
    id: String,
    kind: String,
    blob: String,
}

async fn post(State(notifications): State<Arc<Notifications>>, who: Claims, Json(body): Json<PostBody>) -> Result<Response, Response> {
    if !notifications.posts.take(who.sub, Instant::now()) {
        return Err(error(StatusCode::TOO_MANY_REQUESTS, "Too many notifications in a minute. Try again shortly."));
    }
    if !valid_id(&body.id) {
        return Err(error(StatusCode::BAD_REQUEST, "That notification's id could not be read."));
    }
    if !valid_kind(&body.kind) {
        return Err(error(StatusCode::BAD_REQUEST, "That kind of notification could not be read."));
    }
    if SERVER_KINDS.contains(&body.kind.as_str()) {
        return Err(error(StatusCode::BAD_REQUEST, "That kind of notification is the service's to make."));
    }
    if !base64url(&body.blob, 1..=BLOB_LIMIT) {
        return Err(error(StatusCode::BAD_REQUEST, "That notification is empty or too large."));
    }
    match notifications.accounts.store.post_notification(who.sub, &body.id, &body.kind, &body.blob, now_secs()) {
        Ok(rev) => Ok(Json(json!({ "rev": rev })).into_response()),
        Err(_) => Err(error(StatusCode::INTERNAL_SERVER_ERROR, "That notification could not be kept.")),
    }
}

#[derive(Deserialize)]
struct ReadBody {
    #[serde(default)]
    ids: Vec<String>,
    #[serde(default)]
    all: bool,
    #[serde(default)]
    before: Option<i64>,
}

/// `POST v1/notifications/read`. The rows named, and with `all`, everything the device had seen: up to `before`,
/// the cursor it holds, so a row that arrived since is not marked unseen. Without `before`, everything.
async fn mark_read(State(notifications): State<Arc<Notifications>>, who: Claims, Json(body): Json<ReadBody>) -> Response {
    let ids: Vec<String> = body.ids.into_iter().filter(|id| valid_id(id)).collect();
    let all_before = body.all.then_some(body.before.unwrap_or(i64::MAX));
    match notifications.accounts.store.mark_notifications_read(who.sub, &ids, all_before, now_secs()) {
        Ok(rev) => Json(json!({ "rev": rev })).into_response(),
        Err(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "Those marks could not be kept."),
    }
}

#[derive(Deserialize)]
struct SetBody {
    #[serde(default)]
    read: Option<bool>,
    #[serde(default)]
    hidden: Option<bool>,
}

async fn set(State(notifications): State<Arc<Notifications>>, Path(id): Path<String>, who: Claims, Json(body): Json<SetBody>) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That notification's id could not be read.");
    }
    match notifications.accounts.store.set_notification(who.sub, &id, body.read, body.hidden, now_secs()) {
        Ok(rev) => Json(json!({ "rev": rev })).into_response(),
        Err(NotificationWrite::NotFound) => error(StatusCode::NOT_FOUND, "No such notification."),
        Err(NotificationWrite::Failed) => error(StatusCode::INTERNAL_SERVER_ERROR, "That mark could not be kept."),
    }
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    Router::new()
        .route("/api/v1/notifications", get(feed).post(post))
        .route("/api/v1/notifications/read", post_to(mark_read))
        .route("/api/v1/notifications/{id}", axum::routing::put(set))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
        .with_state(Notifications::new(accounts))
}
