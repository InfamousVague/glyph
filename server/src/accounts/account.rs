//! What a signed-in device may do to its own account: renew its token, add another device, fetch the wrapped key,
//! set a new password, replace the recovery sheet, and delete the account.
//!
//! Every route here takes `who: Claims`, so a request without a current token is refused before it is read
//! (accounts.rs says in which words). Deleting is the one that also asks for the password, and is counted against the
//! sign-in limits for it, since it is one more way to try a password.

use super::credentials::{device_label, hash_login, sheet, valid_login, valid_wrapped, verify_login, CodeBody};
use super::{signed_in, Accounts, RECOVERY_CODES};
use crate::identity::Claims;
use crate::wire::{error, now_secs};
use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use std::net::SocketAddr;
use std::sync::Arc;

/// The longest device key taken: an Ed25519 public key is 43 base64url characters, and this leaves room for a mistake.
const DEVICE_KEY_LIMIT: usize = 64;

/// `POST v1/refresh`. A fresh token for a live one.
pub async fn refresh(State(accounts): State<Arc<Accounts>>, who: Claims) -> Response {
    match accounts.store.account_by_id(who.sub) {
        Some(account) => signed_in(&accounts, account.id, &account.handle, None),
        None => error(StatusCode::UNAUTHORIZED, "That account is gone."),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddDeviceBody {
    device_public_key: String,
    #[serde(default)]
    label: String,
}

/// `POST v1/device`. Another device for the signed-in account, so it can sign in without the password.
pub async fn add_device(State(accounts): State<Arc<Accounts>>, who: Claims, Json(body): Json<AddDeviceBody>) -> Response {
    let key = body.device_public_key.trim();
    if key.is_empty() || key.len() > DEVICE_KEY_LIMIT {
        return error(StatusCode::BAD_REQUEST, "That device key could not be read.");
    }
    match accounts.store.add_device_key(who.sub, key, device_label(&body.label), now_secs()) {
        Ok(()) => Json(json!({ "ok": true })).into_response(),
        Err(_) => error(StatusCode::BAD_REQUEST, "That device key could not be stored."),
    }
}

/// `GET v1/keys`. The account key wrapped under the password, for a signed-in device that needs to unlock it.
pub async fn keys(State(accounts): State<Arc<Accounts>>, who: Claims) -> Response {
    match accounts.store.account_by_id(who.sub) {
        Some(account) => Json(json!({ "wrapped": account.wrapped })).into_response(),
        None => error(StatusCode::UNAUTHORIZED, "That account is gone."),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PasswordBody {
    login_secret: String,
    wrapped: String,
}

/// `PUT v1/password`. A new password: set after a recovery code, or changed on a signed-in device.
pub async fn password(State(accounts): State<Arc<Accounts>>, who: Claims, Json(body): Json<PasswordBody>) -> Result<Response, Response> {
    if !valid_login(&body.login_secret) || !valid_wrapped(&body.wrapped) {
        return Err(error(StatusCode::BAD_REQUEST, "That password could not be read."));
    }
    let hash = hash_login(&body.login_secret)?;
    match accounts.store.set_password(who.sub, &hash, &body.wrapped) {
        Ok(()) => Ok(Json(json!({ "ok": true })).into_response()),
        Err(_) => Err(error(StatusCode::INTERNAL_SERVER_ERROR, "That password could not be stored.")),
    }
}

/// `GET v1/recovery`. How many unused codes are left, for Settings.
pub async fn recovery_left(State(accounts): State<Arc<Accounts>>, who: Claims) -> Response {
    Json(json!({ "left": accounts.store.recovery_codes_left(who.sub) })).into_response()
}

#[derive(Deserialize)]
pub struct RecoverySheetBody {
    codes: Vec<CodeBody>,
}

/// `POST v1/recovery`. A new sheet in place of the old: the device made the codes, and sends only their login halves
/// and the key wrapped under each.
pub async fn recovery_replace(State(accounts): State<Arc<Accounts>>, who: Claims, Json(body): Json<RecoverySheetBody>) -> Result<Response, Response> {
    let codes = sheet(&body.codes)?;
    match accounts.store.replace_recovery_codes(who.sub, &codes) {
        Ok(()) => Ok(Json(json!({ "left": RECOVERY_CODES })).into_response()),
        Err(_) => Err(error(StatusCode::INTERNAL_SERVER_ERROR, "Those codes could not be stored.")),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteAccountBody {
    /// The login half of the password, as sign-in sends it. Asked for so a phone left unlocked can't lose its owner's
    /// account; an account with no password (a device key only) has nothing to ask for.
    #[serde(default)]
    login_secret: String,
}

/// `DELETE v1/account`. The account and everything it keeps here: its notes, settings, recordings and pictures,
/// shared links, devices and recovery codes (store.rs `delete_account`). What is on a device stays on the device. The
/// password check is counted against sign-in's limits, as it is one more way to try a password.
pub async fn delete_account(
    State(accounts): State<Arc<Accounts>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    who: Claims,
    Json(body): Json<DeleteAccountBody>,
) -> Result<Response, Response> {
    let Some(account) = accounts.store.account_by_id(who.sub) else {
        return Err(error(StatusCode::UNAUTHORIZED, "That account is gone."));
    };
    accounts.admit(peer.ip(), &headers, &account.handle)?;
    // 403 rather than 401: the session is fine, only the password is wrong, and a 401 reads as signed out.
    if !account.login_hash.is_empty() && !verify_login(&body.login_secret, &account.login_hash) {
        return Err(error(StatusCode::FORBIDDEN, "That is not the password."));
    }
    match accounts.store.delete_account(account.id) {
        Ok(_) => Ok(Json(json!({ "deleted": true })).into_response()),
        Err(_) => Err(error(StatusCode::INTERNAL_SERVER_ERROR, "The account could not be deleted. Nothing was lost; try again.")),
    }
}
