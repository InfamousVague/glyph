//! Glyph accounts: sign-up, sign-in, the devices and recovery codes that speak for an account, and the session
//! tokens every sync call carries (docs/SYNC.md).
//!
//! AttackFM's registry, copied in shape (`AttackFM/server/crates/registry/src/main.rs`): a handle, a password and/or
//! a device key, eight recovery codes, a signed token that lasts a week and is renewed with itself. Two things are
//! different, both because Glyph's notes are end-to-end encrypted:
//!
//! - **What arrives in place of a password is not the password.** A device derives two halves from it: a login
//!   secret, sent here and Argon2-hashed as AttackFM hashes a password, and a wrap key, which never leaves the device.
//!   The same split is made from each recovery code. So nothing this service stores or sees can unwrap the account
//!   key, and nothing it stores can read a note.
//! - **Sign-in is rate limited**, per address and per handle. AttackFM's registry has no limit on it.
//!
//!   GET  /glyph/api/v1/pubkey            the key tokens are signed with
//!   POST /glyph/api/v1/signup            a new account, with its wrapped key and its recovery sheet
//!   POST /glyph/api/v1/login             by password: the token, and the key wrapped under the password
//!   POST /glyph/api/v1/login/challenge   a nonce for a device to sign
//!   POST /glyph/api/v1/login/device      by device key: the token
//!   POST /glyph/api/v1/login/recovery    by recovery code, spent: the token, and the key wrapped under that code
//!   POST /glyph/api/v1/refresh           a fresh token for a live one
//!   POST /glyph/api/v1/device            another device for the signed-in account
//!   GET  /glyph/api/v1/keys              the key wrapped under the password
//!   PUT  /glyph/api/v1/password          a new password (a new login hash, the key wrapped anew)
//!   GET  /glyph/api/v1/recovery          how many codes are left
//!   POST /glyph/api/v1/recovery          a new sheet of codes
//!   DELETE /glyph/api/v1/account         the account and everything it keeps here, with the password
//!
//! This file owns the service itself - the signing key, issuing and checking tokens, the sign-in limits, and the
//! `Claims` extractor every signed-in route in the crate opens with - and the route table. The routes are beside it:
//! `accounts/ways_in.rs` the open ones that hand out a token, `accounts/account.rs` what a signed-in device may do to
//! its account, with `accounts/credentials.rs` for the rules and hashes of what a device sends and
//! `accounts/challenges.rs` for the nonces a device signs.

// A refusal here is the response itself, handed straight back from a handler; boxing it would only move it.
#![allow(clippy::result_large_err)]

mod account;
mod challenges;
mod credentials;
#[cfg(test)]
mod tests;
mod ways_in;

use crate::guard;
use crate::identity::{Claims, Issuer};
use crate::store::Store;
use crate::wire::{error, now_secs};
use axum::extract::{FromRequestParts, State};
use axum::http::request::Parts;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use axum::{Json, Router};
use challenges::Challenges;
use serde_json::json;
use std::net::IpAddr;
use std::sync::Arc;
use std::time::Instant;

/// A token lives a week; the app renews it long before, as AttackFM's does.
const TOKEN_TTL_SECS: i64 = 7 * 24 * 3600;
/// Sign-in attempts per address, and per handle, per minute.
const SIGN_IN_PER_ADDRESS: u32 = 20;
const SIGN_IN_PER_HANDLE: u32 = 10;
/// A recovery sheet is eight codes, as AttackFM's is.
pub const RECOVERY_CODES: usize = 8;
/// The signing key's name in the database's meta table.
const ISSUER_SECRET_KEY: &str = "issuer_secret_b64";

/// The accounts service: the database, the key tokens are signed with, the device-login challenges outstanding, and
/// the sign-in limits. Sync, shares and the relay hold the same one, for its `claims` and its `store`.
pub struct Accounts {
    pub store: Arc<Store>,
    issuer: Issuer,
    challenges: Challenges,
    by_address: guard::RateLimiter<IpAddr>,
    by_handle: guard::RateLimiter<String>,
}

impl Accounts {
    /// The accounts service over `store`, with the signing key it keeps, made on first use.
    pub fn new(store: Arc<Store>) -> Arc<Self> {
        let issuer = match store.meta(ISSUER_SECRET_KEY).and_then(|s| Issuer::from_secret_b64(&s)) {
            Some(issuer) => issuer,
            None => {
                let issuer = Issuer::generate();
                if let Err(e) = store.set_meta(ISSUER_SECRET_KEY, &issuer.secret_b64()) {
                    eprintln!("accounts: could not keep the signing key: {e}");
                }
                issuer
            }
        };
        let now = Instant::now();
        Arc::new(Self {
            store,
            issuer,
            challenges: Challenges::default(),
            by_address: guard::RateLimiter::new(SIGN_IN_PER_ADDRESS, now),
            by_handle: guard::RateLimiter::new(SIGN_IN_PER_HANDLE, now),
        })
    }

    /// The account a bearer token speaks for, or why not: what the `Claims` extractor below answers with.
    fn caller(&self, headers: &HeaderMap) -> Result<Claims, Response> {
        let raw = headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(|| error(StatusCode::UNAUTHORIZED, "Sign in first."))?;
        self.claims(raw).ok_or_else(|| error(StatusCode::UNAUTHORIZED, "Your session has ended. Sign in again."))
    }

    /// The account a token speaks for, if it is one of ours and still current. The one check every way in uses: a
    /// header on the HTTP routes, the first frame on live sync's socket (src/live.rs), which cannot carry a header.
    pub fn claims(&self, raw: &str) -> Option<Claims> {
        self.issuer.verifier().verify(raw.trim(), now_secs()).ok()
    }

    fn issue(&self, id: i64, handle: &str) -> String {
        let now = now_secs();
        self.issuer.issue(&Claims { sub: id, handle: handle.to_string(), iat: now, exp: now + TOKEN_TTL_SECS })
    }

    /// A token signed with the service's own key that lapses at `exp`, for the tests of what happens when one does:
    /// the routes' refusal, and the relay closing a socket.
    #[cfg(test)]
    pub fn issue_until(&self, id: i64, handle: &str, exp: i64) -> String {
        self.issuer.issue(&Claims { sub: id, handle: handle.to_string(), iat: now_secs(), exp })
    }

    /// One sign-in attempt, counted against the address and the handle. Refused with a 429 when either is spent.
    fn admit(&self, peer: IpAddr, headers: &HeaderMap, handle: &str) -> Result<(), Response> {
        let now = Instant::now();
        let by_address = self.by_address.take(guard::client_ip_of(peer, headers), now);
        let by_handle = self.by_handle.take(handle.trim().to_lowercase(), now);
        if by_address && by_handle {
            Ok(())
        } else {
            Err(error(StatusCode::TOO_MANY_REQUESTS, "Too many tries. Wait a minute and try again."))
        }
    }
}

/// The signed-in caller, as a handler's argument: `who: Claims`, in place of the four lines that read the bearer header
/// and handed the refusal back by hand, which seventeen handlers across accounts.rs, sync.rs and shares.rs opened with.
///
/// Generic over the router's state so the shares router, whose state is its own (`Arc<Shares>`, which carries a
/// limiter as well), gets the same extractor by saying where its accounts are (`HasAccounts`, below). The rejection is
/// `caller`'s own 401 - "Sign in first." with no token, "Your session has ended. Sign in again." with one that is not
/// current - word for word what the handlers answered before.
///
/// ORDER: axum runs the extractors that read a request's parts before the one that reads its body, so a request with
/// no token is refused with this 401 before its body is looked at, however malformed or large the body is. Each
/// handler lists `who: Claims` after its `Path` and `Query`, so those are still read first, as they were when the check
/// was the handler's first line.
impl<S: HasAccounts + Send + Sync> FromRequestParts<S> for Claims {
    type Rejection = Response;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        state.accounts().caller(&parts.headers)
    }
}

/// A router state the `Claims` extractor can find the accounts in.
///
/// A trait of this crate's own rather than axum's `FromRef`, because `FromRef<Arc<Shares>> for Arc<Accounts>` names
/// no type this crate owns at the top level (`Arc` is std's), and Rust's orphan rule refuses it.
pub trait HasAccounts {
    fn accounts(&self) -> &Accounts;
}

impl HasAccounts for Arc<Accounts> {
    fn accounts(&self) -> &Accounts {
        self
    }
}

/// What every way in answers: a fresh token and the account it is for, and the account key wrapped under the secret
/// that got in, when that way hands one out (a password or a recovery code; a device keeps its own key).
fn signed_in(accounts: &Accounts, id: i64, handle: &str, wrapped: Option<&str>) -> Response {
    let mut body = json!({ "token": accounts.issue(id, handle), "account": { "id": id, "handle": handle } });
    if let Some(wrapped) = wrapped {
        body["wrapped"] = json!(wrapped);
    }
    Json(body).into_response()
}

/// `GET v1/pubkey`. The key tokens are checked against, published as AttackFM publishes its own.
async fn pubkey(State(accounts): State<Arc<Accounts>>) -> Response {
    Json(json!({ "alg": "ed25519", "publicKey": accounts.issuer.public_b64() })).into_response()
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    Router::new()
        .route("/glyph/api/v1/pubkey", get(pubkey))
        .route("/glyph/api/v1/signup", post(ways_in::signup))
        .route("/glyph/api/v1/login", post(ways_in::login))
        .route("/glyph/api/v1/login/challenge", post(ways_in::challenge))
        .route("/glyph/api/v1/login/device", post(ways_in::login_device))
        .route("/glyph/api/v1/login/recovery", post(ways_in::login_recovery))
        .route("/glyph/api/v1/refresh", post(account::refresh))
        .route("/glyph/api/v1/device", post(account::add_device))
        .route("/glyph/api/v1/keys", get(account::keys))
        .route("/glyph/api/v1/password", put(account::password))
        .route("/glyph/api/v1/recovery", get(account::recovery_left).post(account::recovery_replace))
        .route("/glyph/api/v1/account", delete(account::delete_account))
        .with_state(accounts)
}
