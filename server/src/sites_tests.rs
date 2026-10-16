//! Published sites, through the routes a device and a visitor call (docs/SITES.md): the owner publishes, anyone reads
//! it with no account and is told not to index it, publishing again keeps the address and moves "last published",
//! the owner's devices list it with what they sealed about it, nobody else can write or unpublish it, and an
//! unpublished site is gone.

use crate::test_support::{device, request, Harness};
use axum::http::{header, Method, StatusCode};
use serde_json::json;

const ID: &str = "SiteSiteSiteSiteSite01";

fn service() -> Harness {
    Harness::new("sites")
}

#[tokio::test]
async fn the_owner_publishes_anyone_reads_it_unindexed_and_publishing_again_keeps_the_address() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let path = format!("/api/v1/sites/{ID}");
    let (status, body) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "c2VhbGVk", "meta": "bWV0YQ" }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["id"], ID);
    let first = body["updated"].as_i64().unwrap();
    assert!(first > 1_700_000_000_000, "in ms, as the app keeps every moment: {first}");
    // No account, no token: the link is enough; nothing between keeps a copy, and no search engine lists it.
    let (status, headers, bytes) = service.send(request(Method::GET, &path, None, None)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap()["blob"], "c2VhbGVk");
    assert_eq!(headers.get(header::CACHE_CONTROL).and_then(|v| v.to_str().ok()), Some("no-store"));
    assert_eq!(headers.get("x-robots-tag").and_then(|v| v.to_str().ok()), Some("noindex, nofollow"));
    // Published again: the same id, the new words.
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "YWdhaW4", "meta": "bWV0YTI" }))).await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = service.call(Method::GET, &path, None, None).await;
    assert_eq!(body["blob"], "YWdhaW4");
    let (status, body) = service.call(Method::GET, "/api/v1/sites", Some(&owner), None).await;
    assert_eq!(status, StatusCode::OK);
    let sites = body["sites"].as_array().unwrap();
    assert_eq!(sites.len(), 1);
    assert_eq!((sites[0]["id"].as_str(), sites[0]["meta"].as_str()), (Some(ID), Some("bWV0YTI")));
    assert_eq!(sites[0]["created"].as_i64(), Some(first), "first published stays");
    assert!(sites[0]["updated"].as_i64().unwrap() >= first);
}

#[tokio::test]
async fn nobody_else_can_publish_over_it_or_unpublish_it_and_unpublished_it_is_gone() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let other = service.signup("ali", &device()).await;
    let path = format!("/api/v1/sites/{ID}");
    service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "c2VhbGVk", "meta": "bWV0YQ" }))).await;
    let (status, body) = service.call(Method::PUT, &path, Some(&other), Some(json!({ "blob": "b3RoZXI", "meta": "bWV0YQ" }))).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "That site belongs to someone else." })));
    let (status, _) = service.call(Method::DELETE, &path, Some(&other), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "answered as if it worked");
    let (_, body) = service.call(Method::GET, &path, None, None).await;
    assert_eq!(body["blob"], "c2VhbGVk", "and it did nothing");
    let (_, body) = service.call(Method::GET, "/api/v1/sites", Some(&other), None).await;
    assert_eq!(body["sites"], json!([]));
    let (status, _) = service.call(Method::DELETE, &path, Some(&owner), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, headers, bytes) = service.send(request(Method::GET, &path, None, None)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap()["error"], "Nothing is published at that link. It may have been unpublished.");
    assert_eq!(headers.get("x-robots-tag").and_then(|v| v.to_str().ok()), Some("noindex, nofollow"), "a dead link is not indexed either");
}

#[tokio::test]
async fn a_site_needs_an_account_a_proper_id_a_blob_and_meta_and_fits_six_million_characters() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let path = format!("/api/v1/sites/{ID}");
    let (status, _) = service.call(Method::PUT, &path, None, Some(json!({ "blob": "c2VhbGVk", "meta": "bWV0YQ" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = service.call(Method::PUT, "/api/v1/sites/short", Some(&owner), Some(json!({ "blob": "c2VhbGVk", "meta": "bWV0YQ" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, body) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "not base64!", "meta": "bWV0YQ" }))).await;
    assert_eq!((status, body["error"].as_str()), (StatusCode::BAD_REQUEST, Some("That site is empty or too large.")));
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "c2VhbGVk", "meta": "" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "A".repeat(6_000_000), "meta": "bWV0YQ" }))).await;
    assert_eq!(status, StatusCode::OK, "a whole notebook with its pictures fits under the route's own body limit");
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "A".repeat(6_000_001), "meta": "bWV0YQ" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = service.call(Method::GET, "/api/v1/sites/nothing-here-at-all-000", None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn an_account_publishes_a_hundred_sites_and_is_told_to_unpublish_one_for_another() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let blob = Some(json!({ "blob": "c2VhbGVk", "meta": "bWV0YQ" }));
    for i in 0..100 {
        let (status, _) = service.call(Method::PUT, &format!("/api/v1/sites/site-{i:017}"), Some(&owner), blob.clone()).await;
        assert_eq!(status, StatusCode::OK, "site {i}");
    }
    let (status, body) = service.call(Method::PUT, "/api/v1/sites/site-one-too-many-0000", Some(&owner), blob.clone()).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "This account has published as many sites as it can: unpublish one first." })));
    let (status, _) = service.call(Method::PUT, &format!("/api/v1/sites/site-{:017}", 0), Some(&owner), blob).await;
    assert_eq!(status, StatusCode::OK, "publishing one it has again is not one more");
}

#[tokio::test]
async fn a_site_goes_when_its_account_is_deleted() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let path = format!("/api/v1/sites/{ID}");
    service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "c2VhbGVk", "meta": "bWV0YQ" }))).await;
    let (status, body) = service.call(Method::DELETE, "/api/v1/account", Some(&owner), Some(json!({ "loginSecret": crate::test_support::login(1) }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, _) = service.call(Method::GET, &path, None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
