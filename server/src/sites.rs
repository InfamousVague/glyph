//! Published sites: a note or a notebook as a small website, readable by anyone with its link, and nobody else - this
//! service included (docs/SITES.md).
//!
//! Matt asked for "Publish as a site": the same end-to-end sealed content as a shared link, read on the reader page as a
//! site, with a clean address per page (`/s/<id>/<page>`) and the key still after the `#`, which a browser never sends.
//! So a site is a share in all that matters here: a device seals it under a key of its own and the service keeps
//! ciphertext it cannot open. What is the site's own:
//!
//! - **It is published by hand.** Publish, and Publish again, write it; an edit in between does not, so `updated` is
//!   when it was last published, which Settings shows.
//! - **It carries `meta`, sealed under the account key**: what it is of, its title and its link's key, so every device
//!   of the account lists the account's sites with their links (Settings › Account › Published sites), with nothing
//!   added to the synced settings.
//! - **It is never indexed.** The page and this route both say `noindex`; and a search engine could not read it if it
//!   tried, since the key is in the part of the link it never sees.
//!
//!   PUT    /api/v1/sites/{id}   { blob, meta }  the owner's site, published or published again
//!   DELETE /api/v1/sites/{id}                  the owner's site, unpublished
//!   GET    /api/v1/sites                       the owner's sites: id, meta, first and last published
//!   GET    /api/v1/sites/{id}                  anyone: the ciphertext, and when it was last published
//!
//! The page addresses (`/s/<id>/<page>`) are the reader page's (scripts/deploy-landing.mjs serves read.html there);
//! nothing on this route reads a page's name, and the reader asks only for the id.

use crate::accounts::{Accounts, HasAccounts};
use crate::guard;
use crate::identity::Claims;
use crate::store::SiteWrite;
use crate::wire::{base64url, error, millis, now_secs};
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::json;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

/// A site's ciphertext, as base64url: as much as a share holds (shares.rs `SHARE_LIMIT`), a notebook and its pictures.
pub const SITE_LIMIT: usize = 6_000_000;
/// What the account's devices seal about a site: an id, a title and a key, generously.
const META_LIMIT: usize = 4_096;
/// The most sites one account keeps published at once.
const SITES_PER_ACCOUNT: i64 = 100;
/// Reads of sites, per address, per minute. A visit is one read: the reader page goes from page to page itself.
const READS_PER_MINUTE: u32 = 240;
/// How long a site's id may be. The app's are 128 random bits, which is 22 base64url characters.
const ID_LENGTH: std::ops::RangeInclusive<usize> = 22..=64;

pub struct Sites {
    accounts: Arc<Accounts>,
    readers: guard::RateLimiter,
}

impl HasAccounts for Arc<Sites> {
    fn accounts(&self) -> &Accounts {
        &self.accounts
    }
}

fn valid_id(id: &str) -> bool {
    base64url(id, ID_LENGTH)
}

#[derive(Deserialize)]
struct SiteBody {
    blob: String,
    meta: String,
}

async fn put_site(State(sites): State<Arc<Sites>>, Path(id): Path<String>, who: Claims, Json(body): Json<SiteBody>) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That site's id could not be read.");
    }
    if !base64url(&body.blob, 1..=SITE_LIMIT) {
        return error(StatusCode::BAD_REQUEST, "That site is empty or too large.");
    }
    if !base64url(&body.meta, 1..=META_LIMIT) {
        return error(StatusCode::BAD_REQUEST, "What that site says about itself could not be read.");
    }
    match sites.accounts.store.put_site(who.sub, &id, &body.blob, &body.meta, now_secs(), SITES_PER_ACCOUNT) {
        Ok(updated) => Json(json!({ "id": id, "updated": millis(updated) })).into_response(),
        Err(SiteWrite::Taken) => error(StatusCode::CONFLICT, "That site belongs to someone else."),
        Err(SiteWrite::Full) => error(StatusCode::CONFLICT, "This account has published as many sites as it can: unpublish one first."),
        Err(SiteWrite::Failed) => error(StatusCode::INTERNAL_SERVER_ERROR, "That site could not be kept."),
    }
}

async fn delete_site(State(sites): State<Arc<Sites>>, Path(id): Path<String>, who: Claims) -> Response {
    if !valid_id(&id) {
        return error(StatusCode::BAD_REQUEST, "That site's id could not be read.");
    }
    // Unpublishing what is not there, or not yours, answers the same as unpublishing your own.
    sites.accounts.store.delete_site(who.sub, &id);
    StatusCode::NO_CONTENT.into_response()
}

async fn list_sites(State(sites): State<Arc<Sites>>, who: Claims) -> Response {
    let list: Vec<_> = sites
        .accounts
        .store
        .sites_of(who.sub)
        .into_iter()
        .map(|row| json!({ "id": row.id, "meta": row.meta, "created": millis(row.created), "updated": millis(row.updated) }))
        .collect();
    Json(json!({ "sites": list })).into_response()
}

async fn read_site(State(sites): State<Arc<Sites>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Path(id): Path<String>) -> Response {
    if !sites.readers.take(guard::client_ip_of(peer.ip(), &headers), Instant::now()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "Too many reads in a minute. Try again shortly.");
    }
    let found = if valid_id(&id) { sites.accounts.store.site(&id) } else { None };
    let mut response = match found {
        Some((blob, updated)) => Json(json!({ "blob": blob, "updated": millis(updated) })).into_response(),
        None => error(StatusCode::NOT_FOUND, "Nothing is published at that link. It may have been unpublished."),
    };
    let headers = response.headers_mut();
    // Always asked again: a reader sees the site as last published, and an unpublished one goes at once.
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    headers.insert(header::HeaderName::from_static("x-robots-tag"), HeaderValue::from_static("noindex, nofollow"));
    response
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    Router::new()
        .route("/api/v1/sites", get(list_sites))
        .route("/api/v1/sites/{id}", get(read_site).put(put_site).delete(delete_site).layer(DefaultBodyLimit::max(SITE_LIMIT + META_LIMIT + 1024)))
        .with_state(Arc::new(Sites { accounts, readers: guard::RateLimiter::new(READS_PER_MINUTE, Instant::now()) }))
}
