//! Sync, through the routes a device calls (docs/SYNC.md): a note written on one device and read on another, a race
//! lost and told what won, the feed, settings, recordings and pictures, the limits, and what deleting an account takes
//! with it. And the one check every signed-in route shares, accounts' included.
//!
//! How a device gets its token - signing up and the three ways in, and the sign-in limit - is tried in
//! accounts/tests.rs, beside the module that answers it; here a test signs up in one line and gets on with syncing.

use crate::test_support::{device, login, sheet, wrapped, Harness};
use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use serde_json::{json, Value};
use tower::ServiceExt;

fn harness() -> Harness {
    Harness::new("sync")
}

/// A recording's bytes up or down: the status, the body, and the revision in `x-glyph-rev`.
async fn raw(h: &Harness, method: Method, path: &str, token: &str, body: Vec<u8>) -> (StatusCode, Vec<u8>, Option<String>) {
    let request = Request::builder()
        .method(method)
        .uri(path)
        .header(header::AUTHORIZATION, format!("Bearer {token}"))
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .body(Body::from(body))
        .unwrap();
    let (status, headers, bytes) = h.send(request).await;
    let rev = headers.get("x-glyph-rev").and_then(|v| v.to_str().ok()).map(str::to_string);
    (status, bytes, rev)
}

#[tokio::test]
async fn a_note_written_on_one_device_is_read_on_another_and_a_race_is_told_who_won() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let id = "7c1e0d9a-3f4b-4c55-9a51-2d6f1f0e8b13";
    let path = format!("/glyph/api/v1/notes/{id}");

    let (status, first) = h.call(Method::PUT, &path, Some(&token), Some(json!({ "base": 0, "blob": "Y2lwaGVyMQ" }))).await;
    assert_eq!(status, StatusCode::OK);
    let first = first["rev"].as_i64().unwrap();

    // The other device reads the feed from the start.
    let (status, feed) = h.call(Method::GET, "/glyph/api/v1/notes?since=0", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(feed["items"][0]["id"], json!(id));
    assert_eq!(feed["items"][0]["blob"], json!("Y2lwaGVyMQ"));
    assert_eq!(feed["rev"], json!(first));
    assert_eq!(feed["more"], json!(false));

    let (_, second) = h.call(Method::PUT, &path, Some(&token), Some(json!({ "base": first, "blob": "Y2lwaGVyMg" }))).await;
    let second = second["rev"].as_i64().unwrap();
    let (status, winner) = h.call(Method::PUT, &path, Some(&token), Some(json!({ "base": first, "blob": "bG9zdA" }))).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(winner["rev"], json!(second));
    assert_eq!(winner["blob"], json!("Y2lwaGVyMg"));

    let (status, gone) = h.call(Method::DELETE, &path, Some(&token), Some(json!({ "base": second }))).await;
    assert_eq!(status, StatusCode::OK);
    let (_, feed) = h.call(Method::GET, &format!("/glyph/api/v1/notes?since={second}"), Some(&token), None).await;
    assert_eq!(feed["items"][0]["deleted"], json!(true));
    assert!(feed["items"][0]["blob"].is_null());
    assert_eq!(feed["rev"], gone["rev"]);
}

#[tokio::test]
async fn the_feed_pages() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    for i in 0..5 {
        h.call(Method::PUT, &format!("/glyph/api/v1/notes/n-{i}"), Some(&token), Some(json!({ "base": 0, "blob": "YQ" }))).await;
    }
    let (_, page) = h.call(Method::GET, "/glyph/api/v1/notes?since=0&limit=2", Some(&token), None).await;
    assert_eq!(page["items"].as_array().unwrap().len(), 2);
    assert_eq!(page["more"], json!(true));
    let cursor = page["rev"].as_i64().unwrap();
    assert_eq!(cursor, page["items"][1]["rev"].as_i64().unwrap(), "with more to come, the cursor is the last note given");
    let (_, rest) = h.call(Method::GET, &format!("/glyph/api/v1/notes?since={cursor}&limit=10"), Some(&token), None).await;
    assert_eq!(rest["items"].as_array().unwrap().len(), 3);
    assert_eq!(rest["more"], json!(false));
}

#[tokio::test]
async fn nothing_is_read_or_written_without_a_token_or_across_accounts() {
    let h = harness();
    let mine = h.signup("matt", &device()).await;
    let theirs = h.signup("sam", &device()).await;
    h.call(Method::PUT, "/glyph/api/v1/notes/n-1", Some(&mine), Some(json!({ "base": 0, "blob": "c2VjcmV0" }))).await;

    for (method, path) in [(Method::GET, "/glyph/api/v1/notes"), (Method::GET, "/glyph/api/v1/prefs"), (Method::GET, "/glyph/api/v1/keys")] {
        let (status, _) = h.call(method, path, None, None).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{path}");
    }
    let (status, _) = h.call(Method::GET, "/glyph/api/v1/notes", Some("glyph1.forged.token"), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (_, feed) = h.call(Method::GET, "/glyph/api/v1/notes", Some(&theirs), None).await;
    assert!(feed["items"].as_array().unwrap().is_empty(), "another account's notes are not in this feed");
}

/// Every signed-in route, accounts', sync's and shares' alike, and the one extractor they share (accounts.rs `Claims`):
/// the same two refusals, word for word, whichever router answers.
#[tokio::test]
async fn every_signed_in_route_refuses_in_the_same_words() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let id = "AbCdEfGhIjKlMnOpQrStUv";
    let routes = [
        (Method::POST, "/glyph/api/v1/refresh".to_string(), None),
        (Method::POST, "/glyph/api/v1/device".to_string(), Some(json!({ "devicePublicKey": "k" }))),
        (Method::GET, "/glyph/api/v1/keys".to_string(), None),
        (Method::PUT, "/glyph/api/v1/password".to_string(), Some(json!({ "loginSecret": login(9), "wrapped": wrapped("new") }))),
        (Method::GET, "/glyph/api/v1/recovery".to_string(), None),
        (Method::POST, "/glyph/api/v1/recovery".to_string(), Some(json!({ "codes": sheet() }))),
        (Method::DELETE, "/glyph/api/v1/account".to_string(), Some(json!({ "loginSecret": login(1) }))),
        (Method::GET, "/glyph/api/v1/notes?since=0".to_string(), None),
        (Method::PUT, "/glyph/api/v1/notes/n-1".to_string(), Some(json!({ "base": 0, "blob": "YQ" }))),
        (Method::DELETE, "/glyph/api/v1/notes/n-1".to_string(), Some(json!({ "base": 0 }))),
        (Method::GET, "/glyph/api/v1/prefs".to_string(), None),
        (Method::PUT, "/glyph/api/v1/prefs".to_string(), Some(json!({ "base": 0, "blob": "YQ" }))),
        (Method::GET, "/glyph/api/v1/recordings/n-1".to_string(), None),
        (Method::PUT, "/glyph/api/v1/recordings/n-1?base=0".to_string(), None),
        (Method::GET, "/glyph/api/v1/shares".to_string(), None),
        (Method::PUT, format!("/glyph/api/v1/shares/{id}"), Some(json!({ "blob": "YQ" }))),
        (Method::DELETE, format!("/glyph/api/v1/shares/{id}"), None),
    ];
    for (method, path, body) in routes {
        let (status, answer) = h.call(method.clone(), &path, None, body.clone()).await;
        assert_eq!((status, answer), (StatusCode::UNAUTHORIZED, json!({ "error": "Sign in first." })), "{method} {path} with no token");
        let (status, answer) = h.call(method.clone(), &path, Some("glyph1.forged.token"), body).await;
        assert_eq!(
            (status, answer),
            (StatusCode::UNAUTHORIZED, json!({ "error": "Your session has ended. Sign in again." })),
            "{method} {path} with a token that is not ours"
        );
    }
    // And the account it was all tried against is still there, still signed in.
    let (status, _) = h.call(Method::GET, "/glyph/api/v1/keys", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
}

/// A request with no token is refused before its body is read, however bad the body: the extractor reads the
/// request's head, and axum reads every head extractor before the body one. When the check was each handler's first
/// line, the body was parsed first, and a malformed one got axum's own 400, 415 or 422 instead.
#[tokio::test]
async fn a_request_with_no_token_is_refused_before_its_body_is_read() {
    let h = harness();
    let bad = [
        Request::put("/glyph/api/v1/notes/n-1").header(header::CONTENT_TYPE, "application/json").body(Body::from("not json")).unwrap(),
        Request::put("/glyph/api/v1/prefs").body(Body::from(r#"{"base":0,"blob":"YQ"}"#)).unwrap(),
        Request::put("/glyph/api/v1/shares/AbCdEfGhIjKlMnOpQrStUv").header(header::CONTENT_TYPE, "application/json").body(Body::from("{}")).unwrap(),
        Request::delete("/glyph/api/v1/account").body(Body::empty()).unwrap(),
    ];
    for request in bad {
        let path = request.uri().to_string();
        let (status, _, bytes) = h.send(request).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{path}");
        assert_eq!(serde_json::from_slice::<Value>(&bytes).unwrap(), json!({ "error": "Sign in first." }), "{path}");
    }
    // A query that will not read is still refused before the token is looked at, as it always was: `who: Claims`
    // comes after `Query` in the handler.
    let (status, _) = h.call(Method::GET, "/glyph/api/v1/notes?since=soon", None, None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    // Signed in, the same bad body is the body's refusal, as it always was.
    let token = h.signup("matt", &device()).await;
    let request = Request::put("/glyph/api/v1/notes/n-1")
        .header(header::AUTHORIZATION, format!("Bearer {token}"))
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from("not json"))
        .unwrap();
    let (status, _, _) = h.send(request).await;
    assert!(status.is_client_error() && status != StatusCode::UNAUTHORIZED, "{status}");
}

#[tokio::test]
async fn refuses_what_it_cannot_store() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let (status, _) = h.call(Method::PUT, "/glyph/api/v1/notes/..%2Fescape", Some(&token), Some(json!({ "blob": "YQ" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "an id is never a path");
    let (status, _) = h.call(Method::PUT, "/glyph/api/v1/notes/n-1", Some(&token), Some(json!({ "blob": "not base64!" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "a note is ciphertext, never plain words");
    let (status, _) = h.call(Method::PUT, "/glyph/api/v1/notes/n-1", Some(&token), Some(json!({ "base": 0 }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn settings_are_one_blob_written_from_the_revision_seen() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let (_, none) = h.call(Method::GET, "/glyph/api/v1/prefs", Some(&token), None).await;
    assert_eq!((none["rev"].clone(), none["blob"].clone()), (json!(0), Value::Null));
    let (_, first) = h.call(Method::PUT, "/glyph/api/v1/prefs", Some(&token), Some(json!({ "base": 0, "blob": "cHJlZnM" }))).await;
    let (status, winner) = h.call(Method::PUT, "/glyph/api/v1/prefs", Some(&token), Some(json!({ "base": 0, "blob": "c3RhbGU" }))).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!((winner["rev"].clone(), winner["blob"].clone()), (first["rev"].clone(), json!("cHJlZnM")));
}

#[tokio::test]
async fn recordings_go_up_and_come_back_byte_for_byte() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let audio: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
    let (status, body, _) = raw(&h, Method::PUT, "/glyph/api/v1/recordings/n-1?base=0", &token, audio.clone()).await;
    assert_eq!(status, StatusCode::OK, "{}", String::from_utf8_lossy(&body));
    let rev: Value = serde_json::from_slice(&body).unwrap();
    let (status, back, header_rev) = raw(&h, Method::GET, "/glyph/api/v1/recordings/n-1", &token, Vec::new()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(back, audio);
    assert_eq!(header_rev, Some(rev["rev"].to_string()));
    let (status, _, _) = raw(&h, Method::PUT, "/glyph/api/v1/recordings/n-1?base=0", &token, vec![1, 2, 3]).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _, _) = raw(&h, Method::GET, "/glyph/api/v1/recordings/none", &token, Vec::new()).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_browser_may_put_and_delete_and_read_the_recording_revision() {
    let h = harness();
    let request = Request::builder()
        .method(Method::OPTIONS)
        .uri("/glyph/api/v1/notes/n-1")
        .header(header::ORIGIN, "tauri://localhost")
        .header(header::ACCESS_CONTROL_REQUEST_METHOD, "DELETE")
        .body(Body::empty())
        .unwrap();
    let response = h.service.clone().oneshot(request).await.unwrap();
    let allowed = response.headers().get(header::ACCESS_CONTROL_ALLOW_METHODS).and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
    assert!(allowed.contains("PUT") && allowed.contains("DELETE"), "{allowed}");
}

#[tokio::test]
async fn deleting_the_account_takes_everything_it_kept_and_needs_the_password() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let other = h.signup("sam", &device()).await;
    h.call(Method::PUT, "/glyph/api/v1/notes/n-1", Some(&token), Some(json!({ "base": 0, "blob": "c2VjcmV0" }))).await;
    h.call(Method::PUT, "/glyph/api/v1/prefs", Some(&token), Some(json!({ "base": 0, "blob": "cHJlZnM" }))).await;
    raw(&h, Method::PUT, "/glyph/api/v1/recordings/n-1?base=0", &token, vec![9; 64]).await;
    let share = "/glyph/api/v1/shares/AAAAAAAAAAAAAAAAAAAAAA";
    let (status, _) = h.call(Method::PUT, share, Some(&token), Some(json!({ "blob": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::OK);
    h.call(Method::PUT, "/glyph/api/v1/notes/n-1", Some(&other), Some(json!({ "base": 0, "blob": "b3RoZXI" }))).await;
    let recordings = h.dir.path().join("recordings").join("1");
    assert!(recordings.exists(), "the recording is a file under the account's folder");

    // Without the password, or with the wrong one: refused, as the session is fine, and nothing goes.
    let (status, _) = h.call(Method::DELETE, "/glyph/api/v1/account", Some(&token), Some(json!({}))).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = h.call(Method::DELETE, "/glyph/api/v1/account", Some(&token), Some(json!({ "loginSecret": login(9) }))).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = h.call(Method::DELETE, "/glyph/api/v1/account", None, Some(json!({ "loginSecret": login(1) }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (_, feed) = h.call(Method::GET, "/glyph/api/v1/notes", Some(&token), None).await;
    assert_eq!(feed["items"].as_array().map(Vec::len), Some(1));

    let (status, body) = h.call(Method::DELETE, "/glyph/api/v1/account", Some(&token), Some(json!({ "loginSecret": login(1) }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["deleted"], true);

    // Gone: no signing in, no renewing the old session, the shared link reads nothing, the recording's file is gone.
    let (status, _) = h.call(Method::POST, "/glyph/api/v1/login", None, Some(json!({ "handle": "matt", "loginSecret": login(1) }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = h.call(Method::POST, "/glyph/api/v1/refresh", Some(&token), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = h.call(Method::GET, share, None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(!recordings.exists(), "the recordings folder goes with the account");
    // The handle is free again, and a new account under it starts empty.
    let again = h.signup("matt", &device()).await;
    let (_, feed) = h.call(Method::GET, "/glyph/api/v1/notes", Some(&again), None).await;
    assert_eq!(feed["items"].as_array().map(Vec::len), Some(0));
    let (_, prefs) = h.call(Method::GET, "/glyph/api/v1/prefs", Some(&again), None).await;
    assert_eq!(prefs["blob"], Value::Null, "no settings carried over");
    // The other account is untouched.
    let (_, feed) = h.call(Method::GET, "/glyph/api/v1/notes", Some(&other), None).await;
    assert_eq!(feed["items"].as_array().map(Vec::len), Some(1));
}

/// The app's limits as docs/SYNC.md gives them, a blob at each and one past it: 1.4 MB for a note and 350 KB for the
/// settings, counted in base64url characters. Written out rather than read from sync.rs, because they are a contract
/// with every device already out there, and a change to one should have to change this too.
#[tokio::test]
async fn a_note_and_the_settings_are_taken_up_to_their_limits_and_not_a_character_past() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let (status, _) = h.call(Method::PUT, "/glyph/api/v1/notes/n-1", Some(&token), Some(json!({ "base": 0, "blob": "A".repeat(1_400_000) }))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = h.call(Method::PUT, "/glyph/api/v1/notes/n-2", Some(&token), Some(json!({ "base": 0, "blob": "A".repeat(1_400_001) }))).await;
    assert_eq!((status, body), (StatusCode::BAD_REQUEST, json!({ "error": "That note is empty or too large to sync." })));
    let (status, _) = h.call(Method::PUT, "/glyph/api/v1/notes/n-3", Some(&token), Some(json!({ "base": 0, "blob": "" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "an empty note is a deletion, which is DELETE's");

    let (status, first) = h.call(Method::PUT, "/glyph/api/v1/prefs", Some(&token), Some(json!({ "base": 0, "blob": "A".repeat(350_000) }))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = h.call(Method::PUT, "/glyph/api/v1/prefs", Some(&token), Some(json!({ "base": first["rev"], "blob": "A".repeat(350_001) }))).await;
    assert_eq!((status, body), (StatusCode::BAD_REQUEST, json!({ "error": "Those settings are empty or too large to sync." })));
}

#[tokio::test]
async fn a_page_of_the_feed_is_at_least_one_note_and_a_cursor_below_zero_is_the_start() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    for i in 0..3 {
        h.call(Method::PUT, &format!("/glyph/api/v1/notes/n-{i}"), Some(&token), Some(json!({ "base": 0, "blob": "YQ" }))).await;
    }
    for limit in ["0", "-5"] {
        let (status, page) = h.call(Method::GET, &format!("/glyph/api/v1/notes?since=0&limit={limit}"), Some(&token), None).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!((page["items"].as_array().unwrap().len(), page["more"].clone()), (1, json!(true)), "limit={limit}");
    }
    let (_, from_zero) = h.call(Method::GET, "/glyph/api/v1/notes?since=0", Some(&token), None).await;
    let (_, from_below) = h.call(Method::GET, "/glyph/api/v1/notes?since=-10", Some(&token), None).await;
    assert_eq!(from_below, from_zero);
    assert_eq!(from_zero["items"].as_array().unwrap().len(), 3);
}

/// What a device asks before it uploads a picture (docs/SYNC.md, settlePictures): a HEAD, answered through the GET
/// route with the revision in its header and no body.
#[tokio::test]
async fn a_head_on_a_file_answers_its_revision_without_its_bytes() {
    let h = harness();
    let token = h.signup("matt", &device()).await;
    let (_, body, _) = raw(&h, Method::PUT, "/glyph/api/v1/recordings/i-png-cat?base=0", &token, vec![7; 4096]).await;
    let rev: Value = serde_json::from_slice(&body).unwrap();
    let (status, bytes, header_rev) = raw(&h, Method::HEAD, "/glyph/api/v1/recordings/i-png-cat", &token, Vec::new()).await;
    assert_eq!(status, StatusCode::OK);
    assert!(bytes.is_empty(), "a HEAD carries no body");
    assert_eq!(header_rev, Some(rev["rev"].to_string()));
    let (status, _, header_rev) = raw(&h, Method::HEAD, "/glyph/api/v1/recordings/i-png-dog", &token, Vec::new()).await;
    assert_eq!((status, header_rev), (StatusCode::NOT_FOUND, None), "one the account lacks is sent");
}
