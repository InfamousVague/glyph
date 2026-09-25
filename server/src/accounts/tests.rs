//! The accounts routes a device calls once it is in, and the parts of the ways in that sync_tests.rs does not reach:
//! the published key, a device added after sign-up, renewing a token, the wrapped key, a token that has lapsed, a
//! challenge for a handle with no account, a device-only account deleted, and tokens outliving a restart.
//!
//! Inside the accounts module so a test can mint a token with the service's own key - one already expired - without a
//! clock to wind on.

use super::Accounts;
use crate::identity::{Claims, TokenVerifier};
use crate::store::Store;
use crate::test_support::{accounts_in, device, login, service, signup_body, wrapped, Harness, TempDir};
use crate::wire::now_secs;
use axum::http::{Method, StatusCode};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::Signer;
use serde_json::{json, Value};
use std::sync::Arc;

fn harness() -> Harness {
    Harness::new("accounts")
}

/// A device key as a device sends it: its public half, base64url.
fn public(key: &ed25519_dalek::SigningKey) -> String {
    URL_SAFE_NO_PAD.encode(key.verifying_key().to_bytes())
}

/// A challenge for `handle`, signed with `key`, sent: the status and the answer.
async fn sign_in_by_device(h: &Harness, handle: &str, key: &ed25519_dalek::SigningKey) -> (StatusCode, Value) {
    let (status, challenge) = h.call(Method::POST, "/glyph/api/v1/login/challenge", None, Some(json!({ "handle": handle }))).await;
    assert_eq!(status, StatusCode::OK, "a challenge is handed out for any handle");
    let nonce = challenge["nonce"].as_str().unwrap().to_string();
    let signature = URL_SAFE_NO_PAD.encode(key.sign(nonce.as_bytes()).to_bytes());
    h.call(Method::POST, "/glyph/api/v1/login/device", None, Some(json!({ "handle": handle, "nonce": nonce, "signature": signature }))).await
}

#[tokio::test]
async fn the_published_key_is_the_one_tokens_are_signed_with() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let (status, body) = h.call(Method::GET, "/glyph/api/v1/pubkey", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["alg"], "ed25519");
    let verifier = TokenVerifier::from_public_b64(body["publicKey"].as_str().unwrap()).expect("a public key");
    let claims = verifier.verify(&token, now_secs()).expect("the published key checks the service's own tokens");
    assert_eq!(claims.handle, "matt");
}

#[tokio::test]
async fn a_device_added_while_signed_in_can_then_sign_in_by_its_own_key() {
    let h = harness();
    // An account made on the web, with a password and no device of its own.
    let (status, body) = h.call(Method::POST, "/glyph/api/v1/signup", None, Some(signup_body("matt", None))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let token = body["token"].as_str().unwrap().to_string();
    let phone = device();
    let (status, _) = sign_in_by_device(&h, "matt", &phone).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "not yet one of the account's devices");

    let (status, body) = h.call(Method::POST, "/glyph/api/v1/device", Some(&token), Some(json!({ "devicePublicKey": public(&phone), "label": "phone" }))).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "ok": true })));
    let (status, body) = sign_in_by_device(&h, "matt", &phone).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["account"]["handle"], "matt");
    assert!(body.get("wrapped").is_none(), "a device keeps its own key; nothing wrapped is handed out");
}

#[tokio::test]
async fn a_device_key_that_cannot_be_one_is_refused() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    for key in [String::new(), "   ".to_string(), "k".repeat(65)] {
        let (status, body) = h.call(Method::POST, "/glyph/api/v1/device", Some(&token), Some(json!({ "devicePublicKey": key }))).await;
        assert_eq!((status, body), (StatusCode::BAD_REQUEST, json!({ "error": "That device key could not be read." })), "{key:?}");
    }
}

#[tokio::test]
async fn a_live_token_is_renewed_for_the_same_account_and_the_new_one_unlocks_the_wrapped_key() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let (status, renewed) = h.call(Method::POST, "/glyph/api/v1/refresh", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(renewed["account"], json!({ "id": 1, "handle": "matt" }));
    assert!(renewed.get("wrapped").is_none(), "renewing hands out a token, not the key");
    let fresh = renewed["token"].as_str().unwrap();
    let (status, keys) = h.call(Method::GET, "/glyph/api/v1/keys", Some(fresh), None).await;
    assert_eq!((status, keys), (StatusCode::OK, json!({ "wrapped": wrapped("password") })));
}

#[tokio::test]
async fn a_token_that_has_lapsed_is_told_its_session_has_ended() {
    let dir = TempDir::new("accounts-lapsed");
    let accounts = accounts_in(dir.path());
    let h = Harness { service: service(Some(accounts.clone())), dir };
    h.signup("matt", &device()).await;
    // Signed with the service's own key, so only its age is wrong.
    let now = now_secs();
    let lapsed = accounts.issuer.issue(&Claims { sub: 1, handle: "matt".into(), iat: now - 3_600, exp: now - 1 });
    for (method, path) in [(Method::GET, "/glyph/api/v1/keys"), (Method::POST, "/glyph/api/v1/refresh"), (Method::GET, "/glyph/api/v1/notes")] {
        let (status, body) = h.call(method, path, Some(&lapsed), None).await;
        assert_eq!((status, body), (StatusCode::UNAUTHORIZED, json!({ "error": "Your session has ended. Sign in again." })), "{path}");
    }
    assert!(accounts.claims(&lapsed).is_none(), "the socket's first frame is checked the same way");
}

#[tokio::test]
async fn a_challenge_for_a_handle_with_no_account_is_handed_out_and_nothing_signs_it() {
    let h = harness();
    let stranger = device();
    let (status, body) = sign_in_by_device(&h, "nobody", &stranger).await;
    assert_eq!((status, body), (StatusCode::UNAUTHORIZED, json!({ "error": "This device could not be verified." })));
    // And one handed out for a real account is not good for another handle.
    let phone = device();
    h.signup("matt", &phone).await;
    let (_, challenge) = h.call(Method::POST, "/glyph/api/v1/login/challenge", None, Some(json!({ "handle": "matt" }))).await;
    let nonce = challenge["nonce"].as_str().unwrap().to_string();
    h.signup("sam", &phone).await;
    let signature = URL_SAFE_NO_PAD.encode(phone.sign(nonce.as_bytes()).to_bytes());
    let (status, _) = h.call(Method::POST, "/glyph/api/v1/login/device", None, Some(json!({ "handle": "sam", "nonce": nonce, "signature": signature }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "matt's nonce, sam's handle");
}

#[tokio::test]
async fn an_account_with_only_a_device_key_is_deleted_without_a_password() {
    let h = harness();
    let phone = device();
    let mut body = signup_body("matt", Some(&phone));
    body.as_object_mut().unwrap().retain(|key, _| key != "loginSecret" && key != "wrapped");
    let (status, answer) = h.call(Method::POST, "/glyph/api/v1/signup", None, Some(body)).await;
    assert_eq!(status, StatusCode::OK, "{answer}");
    let token = answer["token"].as_str().unwrap().to_string();
    let (status, _) = h.call(Method::POST, "/glyph/api/v1/login", None, Some(json!({ "handle": "matt", "loginSecret": login(1) }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "there is no password to sign in with");

    let (status, body) = h.call(Method::DELETE, "/glyph/api/v1/account", Some(&token), Some(json!({}))).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "deleted": true })), "nothing to ask for");
    let (status, _) = sign_in_by_device(&h, "matt", &phone).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn a_token_issued_before_a_restart_is_still_good_after_it() {
    // The signing key is kept in the database: glyph-api.service's note that backing up /var/lib/glyph-api backs up
    // the key rests on this.
    let dir = TempDir::new("accounts-restart");
    let data = dir.path().join("data");
    let token = {
        let accounts = Accounts::new(Arc::new(Store::open(&data).unwrap()));
        accounts.issue(1, "matt")
    };
    let restarted = Accounts::new(Arc::new(Store::open(&data).unwrap()));
    assert_eq!(restarted.claims(&token).map(|c| (c.sub, c.handle)), Some((1, "matt".to_string())));
    let elsewhere = TempDir::new("accounts-elsewhere");
    let other = Accounts::new(Arc::new(Store::open(elsewhere.path()).unwrap()));
    assert!(other.claims(&token).is_none(), "another database made another key");
}
