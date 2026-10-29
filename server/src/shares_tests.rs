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
    let path = format!("/api/v1/shares/{ID}");
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
    let (status, body) = service.call(Method::GET, "/api/v1/shares", Some(&owner), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["shares"].as_array().unwrap().len(), 1);
    assert_eq!(body["shares"][0]["id"], ID);
}

#[tokio::test]
async fn nobody_else_can_write_it_or_take_it_down_and_taken_down_it_is_gone() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let other = service.signup("ali", &device()).await;
    let path = format!("/api/v1/shares/{ID}");
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
    let (_, body) = service.call(Method::GET, "/api/v1/shares", Some(&owner), None).await;
    assert_eq!(body["shares"].as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn a_share_needs_an_account_to_write_and_a_proper_id_and_blob() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let path = format!("/api/v1/shares/{ID}");
    let (status, _) = service.call(Method::PUT, &path, None, Some(json!({ "blob": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = service.call(Method::PUT, "/api/v1/shares/short", Some(&owner), Some(json!({ "blob": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "not base64!" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = service.call(Method::GET, "/api/v1/shares/nothing-here-at-all-000", None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

/// docs/SHARING.md's limit, and src/app/share/share.ts's copy of it: 6 MB of base64url, and not a character more.
/// The store's own test of the per-account limit runs at a limit of two; this is the number a device meets, and the
/// words it is told.
#[tokio::test]
async fn an_account_keeps_five_hundred_shares_up_and_is_told_to_take_one_down_for_another() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let blob = Some(json!({ "blob": "c2VhbGVk" }));
    for i in 0..500 {
        let (status, _) = service.call(Method::PUT, &format!("/api/v1/shares/share-{i:016}"), Some(&owner), blob.clone()).await;
        assert_eq!(status, StatusCode::OK, "share {i}");
    }
    let (status, body) = service.call(Method::PUT, "/api/v1/shares/share-one-too-many-000", Some(&owner), blob.clone()).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "This account shares as much as it can: take a share down first." })));
    let (status, _) = service.call(Method::PUT, &format!("/api/v1/shares/share-{:016}", 0), Some(&owner), Some(json!({ "blob": "ZWRpdGVk" }))).await;
    assert_eq!(status, StatusCode::OK, "an edit of one it has is not one more");
}

#[tokio::test]
async fn a_share_is_taken_up_to_six_million_characters_and_not_one_past() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let path = format!("/api/v1/shares/{ID}");
    let (status, _) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "A".repeat(6_000_000) }))).await;
    assert_eq!(status, StatusCode::OK, "a whole book fits under the route's own body limit");
    let (status, body) = service.call(Method::PUT, &path, Some(&owner), Some(json!({ "blob": "A".repeat(6_000_001) }))).await;
    assert_eq!((status, body), (StatusCode::BAD_REQUEST, json!({ "error": "That share is empty or too large." })));
}

/// Reading is open, so it is limited by address: 240 a minute, the bucket full at the start, and another reader's
/// address counted apart.
#[tokio::test]
async fn reading_shares_is_limited_by_the_reader_s_address() {
    let service = service();
    let from = |address: &str| {
        let mut read = request(Method::GET, &format!("/api/v1/shares/{ID}"), None, None);
        read.headers_mut().insert("x-forwarded-for", address.parse().unwrap());
        read
    };
    for i in 0..240 {
        let (status, _, _) = service.send(from("203.0.113.9")).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "read {i} of the minute's 240 is answered");
    }
    // The bucket refills at four a second, so a slow machine may earn a few more; the refusal still comes.
    let mut refused = None;
    for _ in 0..60 {
        let (status, _, bytes) = service.send(from("203.0.113.9")).await;
        if status == StatusCode::TOO_MANY_REQUESTS {
            refused = Some(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap());
            break;
        }
    }
    assert_eq!(refused, Some(json!({ "error": "Too many reads in a minute. Try again shortly." })));
    let (status, _, _) = service.send(from("198.51.100.1")).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "another reader is not held to the first one's minute");
}

// ---- a meeting's recording ------------------------------------------------------------------------------------------

/// An upload's id as a device makes one.
const UPLOAD: &str = "UpLoAd0123456789abcdef";

/// A part of a recording as a device sends one: its sealed bytes as they are.
fn part(n: u32, token: Option<&str>, bytes: &[u8]) -> axum::http::Request<axum::body::Body> {
    let mut put = axum::http::Request::builder().method(Method::PUT).uri(format!("/api/v1/shares/{ID}/audio/{UPLOAD}/{n}")).header(header::CONTENT_TYPE, "application/octet-stream");
    if let Some(token) = token {
        put = put.header(header::AUTHORIZATION, format!("Bearer {token}"));
    }
    put.body(axum::body::Body::from(bytes.to_vec())).unwrap()
}

/// A read of the recording from `address`.
fn listen(address: &str) -> axum::http::Request<axum::body::Body> {
    let mut read = request(Method::GET, &format!("/api/v1/shares/{ID}/audio"), None, None);
    read.headers_mut().insert("x-forwarded-for", address.parse().unwrap());
    read
}

#[tokio::test]
async fn the_owner_sends_a_recording_in_parts_and_anyone_with_the_link_reads_it_framed() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    service.call(Method::PUT, &format!("/api/v1/shares/{ID}"), Some(&owner), Some(json!({ "blob": "c2VhbGVk" }))).await;
    let audio = format!("/api/v1/shares/{ID}/audio");
    let (status, _, _) = service.send(part(0, Some(&owner), b"first part")).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, body) = service.call(Method::POST, &audio, Some(&owner), Some(json!({ "upload": UPLOAD, "parts": 2 }))).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "Not every part of that recording has arrived. Send it again." })));
    let (status, _, _) = service.send(listen("203.0.113.1")).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "nothing to hear until the upload is whole");
    service.send(part(0, Some(&owner), b"first part")).await;
    service.send(part(1, Some(&owner), b"second")).await;
    let (status, body) = service.call(Method::POST, &audio, Some(&owner), Some(json!({ "upload": UPLOAD, "parts": 2 }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body, json!({ "upload": UPLOAD, "parts": 2, "size": 24 }));
    // No account: the link is enough. Each part as its length and its bytes, in order, and nothing kept between.
    let (status, headers, bytes) = service.send(listen("203.0.113.1")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(bytes, [&[0, 0, 0, 10][..], b"first part", &[0, 0, 0, 6], b"second"].concat());
    assert_eq!(headers.get(header::CACHE_CONTROL).and_then(|v| v.to_str().ok()), Some("no-store"));
    assert_eq!(headers.get(header::CONTENT_LENGTH).and_then(|v| v.to_str().ok()), Some("24"));
    // The share's words written again do not touch it.
    service.call(Method::PUT, &format!("/api/v1/shares/{ID}"), Some(&owner), Some(json!({ "blob": "ZWRpdGVk" }))).await;
    let (status, _, again) = service.send(listen("203.0.113.1")).await;
    assert_eq!((status, again), (StatusCode::OK, bytes));
}

#[tokio::test]
async fn only_the_share_s_owner_may_send_commit_or_take_down_its_recording() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let other = service.signup("ali", &device()).await;
    let audio = format!("/api/v1/shares/{ID}/audio");
    let (status, _, _) = service.send(part(0, Some(&owner), b"too soon")).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "a recording needs its share first");
    service.call(Method::PUT, &format!("/api/v1/shares/{ID}"), Some(&owner), Some(json!({ "blob": "c2VhbGVk" }))).await;
    let (status, _, _) = service.send(part(0, None, b"anyone")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _, bytes) = service.send(part(0, Some(&other), b"not theirs")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap()["error"], "There is no share of yours at that link. Share the meeting first.");
    service.send(part(0, Some(&owner), b"mine")).await;
    let (status, _) = service.call(Method::POST, &audio, Some(&other), Some(json!({ "upload": UPLOAD, "parts": 1 }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = service.call(Method::POST, &audio, Some(&owner), Some(json!({ "upload": UPLOAD, "parts": 1 }))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = service.call(Method::DELETE, &audio, Some(&other), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "another's take-down answers as if it worked");
    let (status, _, _) = service.send(listen("203.0.113.2")).await;
    assert_eq!(status, StatusCode::OK, "and does nothing");
    let (status, _) = service.call(Method::DELETE, &audio, None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = service.call(Method::DELETE, &audio, Some(&owner), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _, _) = service.send(listen("203.0.113.2")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, body) = service.call(Method::GET, &format!("/api/v1/shares/{ID}"), None, None).await;
    assert_eq!(body["blob"], "c2VhbGVk", "the words stay shared without it");
}

#[tokio::test]
async fn taking_the_share_down_takes_its_recording_with_it() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    let share = format!("/api/v1/shares/{ID}");
    service.call(Method::PUT, &share, Some(&owner), Some(json!({ "blob": "c2VhbGVk" }))).await;
    service.send(part(0, Some(&owner), b"the meeting")).await;
    service.call(Method::POST, &format!("{share}/audio"), Some(&owner), Some(json!({ "upload": UPLOAD, "parts": 1 }))).await;
    let (_, _, heard) = service.send(listen("203.0.113.3")).await;
    assert_eq!(heard.len(), 15);
    let (status, _) = service.call(Method::DELETE, &share, Some(&owner), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _, _) = service.send(listen("203.0.113.3")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let folders = std::fs::read_dir(service.dir.path().join("recordings")).unwrap().flatten().map(|account| account.path().join("share-audio"));
    let left: usize = folders.map(|folder| std::fs::read_dir(folder).map(|e| e.count()).unwrap_or(0)).sum();
    assert_eq!(left, 0, "no file left on the disk, and no upload's folder");
    // The same id shared again starts with no recording.
    service.call(Method::PUT, &share, Some(&owner), Some(json!({ "blob": "YWdhaW4" }))).await;
    let (status, _, _) = service.send(listen("203.0.113.3")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

/// The route's own limits: a part past four megabytes, an upload's id or a part's number it cannot read, a commit of
/// no parts. (What a whole recording and an account's recordings may be is the store's test, at small limits:
/// store/share_audio.rs.)
#[tokio::test]
async fn a_part_is_held_to_its_size_and_an_upload_to_its_shape() {
    let service = service();
    let owner = service.signup("sam", &device()).await;
    service.call(Method::PUT, &format!("/api/v1/shares/{ID}"), Some(&owner), Some(json!({ "blob": "c2VhbGVk" }))).await;
    let (status, _, _) = service.send(part(0, Some(&owner), &vec![7; 4 * 1024 * 1024])).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "four megabytes is a part");
    let (status, _, _) = service.send(part(1, Some(&owner), &vec![7; 4 * 1024 * 1024 + 1])).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE, "a byte more is not");
    let (status, _, _) = service.send(part(1024, Some(&owner), b"x")).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "a recording has at most 1024 parts");
    let (status, _, _) = service.send(part(1, Some(&owner), b"")).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "an empty part is nothing");
    let bad_upload = axum::http::Request::builder()
        .method(Method::PUT)
        .uri(format!("/api/v1/shares/{ID}/audio/short/0"))
        .header(header::AUTHORIZATION, format!("Bearer {owner}"))
        .body(axum::body::Body::from("x"))
        .unwrap();
    let (status, _, _) = service.send(bad_upload).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = service.call(Method::POST, &format!("/api/v1/shares/{ID}/audio"), Some(&owner), Some(json!({ "upload": UPLOAD, "parts": 0 }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = service.call(Method::POST, &format!("/api/v1/shares/{ID}/audio"), Some(&owner), Some(json!({ "upload": UPLOAD, "parts": 1 }))).await;
    assert_eq!(status, StatusCode::OK, "the four megabytes that were taken make a recording");
}

/// Hearing a recording is open, so it is limited by address, and more tightly than reading a share's words: twenty a
/// minute, each a read of megabytes. Another listener is counted apart, and the words' own bucket is not spent.
#[tokio::test]
async fn hearing_a_recording_is_limited_by_the_listener_s_address() {
    let service = service();
    for i in 0..20 {
        let (status, _, _) = service.send(listen("203.0.113.9")).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "play {i} of the minute's 20 is answered");
    }
    // The bucket refills at one every three seconds, so a slow machine may earn one more; the refusal still comes.
    let mut refused = None;
    for _ in 0..10 {
        let (status, _, bytes) = service.send(listen("203.0.113.9")).await;
        if status == StatusCode::TOO_MANY_REQUESTS {
            refused = Some(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap());
            break;
        }
    }
    assert_eq!(refused, Some(json!({ "error": "Too many plays in a minute. Try again shortly." })));
    let (status, _, _) = service.send(listen("198.51.100.1")).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "another listener is not held to the first one's minute");
    let mut words = request(Method::GET, &format!("/api/v1/shares/{ID}"), None, None);
    words.headers_mut().insert("x-forwarded-for", "203.0.113.9".parse().unwrap());
    let (status, _, _) = service.send(words).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "the share's words are read on their own count");
}
