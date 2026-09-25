//! The ways in: a new account, and signing in to one by password, by device key or by recovery code.
//!
//! These are the open routes - no token, since getting one is what they are for - so each is counted against the
//! sign-in limits before it looks at anything (`Accounts::admit`), and each refuses a wrong handle and a wrong secret in
//! the same words, so asking says nothing about which handles exist.

use super::challenges::NO_ACCOUNT;
use super::credentials::{device_label, hash_code, hash_login, sheet, valid_handle, valid_login, valid_wrapped, verify_login, CodeBody};
use super::{signed_in, Accounts};
use crate::identity::verify_detached;
use crate::wire::{error, now_secs};
use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use std::net::SocketAddr;
use std::sync::Arc;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SignupBody {
    handle: String,
    #[serde(default)]
    login_secret: String,
    #[serde(default)]
    wrapped: String,
    #[serde(default)]
    device_public_key: String,
    #[serde(default)]
    device_label: String,
    #[serde(default)]
    recovery: Vec<CodeBody>,
}

/// `POST v1/signup`. Open, like AttackFM's: anyone may make an account.
pub async fn signup(
    State(accounts): State<Arc<Accounts>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<SignupBody>,
) -> Result<Response, Response> {
    let handle = body.handle.trim().to_string();
    accounts.admit(peer.ip(), &headers, &handle)?;
    if !valid_handle(&handle) {
        return Err(error(StatusCode::BAD_REQUEST, "A handle is 3 to 24 letters, digits, . _ or -, starting with a letter or digit."));
    }
    let has_password = !body.login_secret.is_empty();
    let device = body.device_public_key.trim();
    if !has_password && device.is_empty() {
        return Err(error(StatusCode::BAD_REQUEST, "Set a password, or sign up from a device."));
    }
    if has_password && (!valid_login(&body.login_secret) || !valid_wrapped(&body.wrapped)) {
        return Err(error(StatusCode::BAD_REQUEST, "That password could not be read."));
    }
    // End to end, the recovery sheet is the only way back into notes whose every device and password are gone, so an
    // account is not made without one.
    let codes = sheet(&body.recovery)?;
    if accounts.store.account_by_handle(&handle).is_some() {
        return Err(error(StatusCode::CONFLICT, "That handle is taken."));
    }
    let login_hash = if has_password { hash_login(&body.login_secret)? } else { String::new() };
    let device = (!device.is_empty()).then_some((device, device_label(&body.device_label)));
    let wrapped = if has_password { body.wrapped.as_str() } else { "" };
    match accounts.store.create_account(&handle, &login_hash, wrapped, device, &codes, now_secs()) {
        Ok(account) => Ok(signed_in(&accounts, account.id, &account.handle, None)),
        // The UNIQUE index is the real gate: a signup racing this one lands here.
        Err(_) => Err(error(StatusCode::CONFLICT, "That handle is taken.")),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginBody {
    handle: String,
    login_secret: String,
}

/// `POST v1/login`. The same answer for a wrong handle and a wrong password, as AttackFM gives.
pub async fn login(
    State(accounts): State<Arc<Accounts>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<LoginBody>,
) -> Result<Response, Response> {
    accounts.admit(peer.ip(), &headers, &body.handle)?;
    match accounts.store.account_by_handle(body.handle.trim()).filter(|a| verify_login(&body.login_secret, &a.login_hash)) {
        Some(account) => {
            accounts.store.touch_seen(account.id, now_secs());
            Ok(signed_in(&accounts, account.id, &account.handle, Some(&account.wrapped)))
        }
        None => Err(error(StatusCode::UNAUTHORIZED, "Wrong handle or password.")),
    }
}

#[derive(Deserialize)]
pub struct ChallengeBody {
    handle: String,
}

/// `POST v1/login/challenge`. A nonce whether or not the handle exists, so this says nothing about which do.
pub async fn challenge(
    State(accounts): State<Arc<Accounts>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<ChallengeBody>,
) -> Result<Response, Response> {
    accounts.admit(peer.ip(), &headers, &body.handle)?;
    let account = accounts.store.account_by_handle(body.handle.trim()).map(|a| a.id).unwrap_or(NO_ACCOUNT);
    let nonce = accounts.challenges.issue(account, now_secs());
    Ok(Json(json!({ "nonce": nonce })).into_response())
}

#[derive(Deserialize)]
pub struct DeviceLoginBody {
    handle: String,
    nonce: String,
    signature: String,
}

/// `POST v1/login/device`. The nonce is spent by the attempt, whether or not the signature holds.
pub async fn login_device(
    State(accounts): State<Arc<Accounts>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<DeviceLoginBody>,
) -> Result<Response, Response> {
    accounts.admit(peer.ip(), &headers, &body.handle)?;
    let now = now_secs();
    let Some(account_id) = accounts.challenges.take(&body.nonce, now) else {
        return Err(error(StatusCode::UNAUTHORIZED, "That sign-in took too long. Try again."));
    };
    let verified = accounts
        .store
        .account_by_handle(body.handle.trim())
        .filter(|a| a.id == account_id)
        .filter(|a| accounts.store.device_keys(a.id).iter().any(|key| verify_detached(key, body.nonce.as_bytes(), &body.signature)));
    match verified {
        Some(account) => {
            accounts.store.touch_seen(account.id, now);
            Ok(signed_in(&accounts, account.id, &account.handle, None))
        }
        None => Err(error(StatusCode::UNAUTHORIZED, "This device could not be verified.")),
    }
}

#[derive(Deserialize)]
pub struct RecoveryLoginBody {
    handle: String,
    login: String,
}

/// `POST v1/login/recovery`. The code is spent, and what comes back is the key wrapped under that code alone.
pub async fn login_recovery(
    State(accounts): State<Arc<Accounts>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<RecoveryLoginBody>,
) -> Result<Response, Response> {
    accounts.admit(peer.ip(), &headers, &body.handle)?;
    let now = now_secs();
    let found = accounts.store.account_by_handle(body.handle.trim()).and_then(|a| {
        let wrapped = valid_login(&body.login).then(|| accounts.store.use_recovery_code(a.id, &hash_code(&body.login), now)).flatten()?;
        Some((a, wrapped))
    });
    match found {
        Some((account, wrapped)) => {
            accounts.store.touch_seen(account.id, now);
            Ok(signed_in(&accounts, account.id, &account.handle, Some(&wrapped)))
        }
        None => Err(error(StatusCode::UNAUTHORIZED, "Wrong handle or code, or a code already used.")),
    }
}
