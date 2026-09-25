//! Shares, through the routes a device and a reader call (docs/SHARING.md): the owner writes one, anyone reads it with
//! no account, the owner's edits reach the reader, nobody else can write or take it down, and a share taken down is
//! gone.

use crate::test_support::{device, request, Harness};
use axum::http::{header, Method, StatusCode};
use serde_json::json;

/// A share id as a device makes one: 128 random bits, base64url.
const ID: &str = "AbCdEfGhIjKlMnOpQrStUv";

fn service() -> Harness {
    Harness::new("shares")
}

#[tokio::test]
async fn the_owner_shares_anyone_reads_and_the_owner_s_edits_reach_the_reader() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let path = format!("/glyph/api/v1/shares/{ID}");
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::OK);
    // No account, no token: the link is enough, and nothing between keeps a copy.
    let (status, headers, bytes) = service.send(request(Method::GET, &path, None, None)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap()["blob"], "c2VhbGVk");
    assert_eq!(headers.get(header::CACHE_CONTROL).and_then(|v| v.to_str().ok()), Some("no-store"));
    // Written again as the owner edits: the reader sees the new one.
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "ZWRpdGVk" }))).await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = service.call(Method::GET, &path, None, None).await;
    assert_eq!(body["blob"], "ZWRpdGVk");
    let (status, body) = service.call(Method::GET, "/glyph/api/v1/shares", Some(&owner), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["shares"].as_array().unwrap().len(), 1);
    assert_eq!(body["shares"][0]["id"], ID);
}

#[tokio::test]
async fn nobody_else_can_write_it_or_take_it_down_and_taken_down_it_is_gone() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let other = service.signup("ali", &device()).await;
    let path = format!("/glyph/api/v1/shares/{ID}");
    service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "c2VhbGVk" }))).await;
    let (status, _) = service.call(Method::PUT, &path, Some(&other), Some(json!({ "blob": "b3RoZXI" }))).await;
    assert_eq!(status, StatusCode::CONFLICT);
    // Another's delete answers as if it worked, and does nothing.
    let (status, _) = service.call(Method::DELETE, &path, Some(&other), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, body) = service.call(Method::GET, &path, None, None).await;
    assert_eq!(body["blob"], "c2VhbGVk");
    let (status, _) = service.call(Method::DELETE, &path, Some(&owner), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = service.call(Method::GET, &path, None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, body) = service.call(Method::GET, "/glyph/api/v1/shares", Some(&owner), None).await;
    assert_eq!(body["shares"].as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn a_share_needs_an_account_to_write_and_a_proper_id_and_blob() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let path = format!("/glyph/api/v1/shares/{ID}");
    let (status, _) = service.call(Method::PUT, &path, None, Some(json!({ "blob": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = service.call(Method::PUT, "/glyph/api/v1/shares/short", Some(&owner), Some(json!({ "blob": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "not base64!" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = service.call(Method::GET, "/glyph/api/v1/shares/nothing-here-at-all-000", None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
