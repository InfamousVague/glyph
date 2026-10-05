//! Team notes through the routes a device calls (docs/SHARED.md, S4, S5): the feed, a note written from the revision
//! it saw, its log, a file, and what a stranger and an invitee get.

use crate::test_support::{device, request, Harness};
use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use serde_json::{json, Value};

fn harness() -> Harness {
    Harness::new("org-notes")
}

async fn make(h: &Harness, token: &str, name: &str) -> String {
    let (status, body) = h.call(Method::POST, "/api/v1/orgs", Some(token), Some(json!({ "name": name }))).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    body["org"]["id"].as_str().unwrap().to_string()
}

async fn join(h: &Harness, owner: &str, org: &str, token: &str, handle: &str) {
    h.call(Method::POST, &format!("/api/v1/orgs/{org}/members"), Some(owner), Some(json!({ "handle": handle }))).await;
    let (status, _) = h.call(Method::POST, &format!("/api/v1/orgs/{org}/invite"), Some(token), Some(json!({ "accept": true }))).await;
    assert_eq!(status, StatusCode::OK);
}

fn refusal(status: StatusCode, words: &str) -> (StatusCode, Value) {
    (status, json!({ "error": words }))
}

#[tokio::test]
async fn a_team_note_is_written_fed_to_every_member_refused_when_stale_and_deleted_with_its_log() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let org = make(&h, &matt, "Ghost").await;
    join(&h, &matt, &org, &sam, "sam").await;
    // Nothing yet: an empty feed at head 0.
    let (status, body) = h.call(Method::GET, &format!("/api/v1/orgs/{org}/notes?since=0"), Some(&sam), None).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "rev": 0, "items": [], "more": false })));
    // matt writes; sam reads it with who wrote it, and writes it on from the revision seen.
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/orgs/{org}/notes/n1"), Some(&matt), Some(json!({ "base": 0, "blob": "c1" }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let r1 = body["rev"].as_i64().unwrap();
    let (_, feed) = h.call(Method::GET, &format!("/api/v1/orgs/{org}/notes?since=0"), Some(&sam), None).await;
    assert_eq!(feed["items"].as_array().unwrap().len(), 1);
    assert_eq!((feed["items"][0]["id"].clone(), feed["items"][0]["blob"].clone(), feed["items"][0]["by"].clone(), feed["items"][0]["deleted"].clone()), (json!("n1"), json!("c1"), json!("matt"), json!(false)));
    assert_eq!(feed["rev"], r1);
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/orgs/{org}/notes/n1"), Some(&sam), Some(json!({ "base": r1, "blob": "c2" }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let r2 = body["rev"].as_i64().unwrap();
    // matt, still at r1, is told what won.
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/orgs/{org}/notes/n1"), Some(&matt), Some(json!({ "base": r1, "blob": "c3" }))).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!((body["rev"].clone(), body["blob"].clone(), body["by"].clone()), (json!(r2), json!("c2"), json!("sam")));
    // The log: appended by either, numbered from 1, read after a seq, cut by a snapshot, gone with the note.
    let (status, body) = h.call(Method::POST, &format!("/api/v1/orgs/{org}/notes/n1/updates"), Some(&matt), Some(json!({ "blobs": ["u1", "u2"] }))).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "seq": 2 })));
    let (_, body) = h.call(Method::POST, &format!("/api/v1/orgs/{org}/notes/n1/updates"), Some(&sam), Some(json!({ "blobs": ["u3"] }))).await;
    assert_eq!(body["seq"], 3);
    let (_, log) = h.call(Method::GET, &format!("/api/v1/orgs/{org}/notes/n1/updates?since=1"), Some(&matt), None).await;
    assert_eq!(log["seq"], 3);
    assert_eq!(log["items"].as_array().unwrap().iter().map(|u| (u["seq"].as_i64().unwrap(), u["blob"].as_str().unwrap().to_string(), u["by"].as_str().unwrap().to_string())).collect::<Vec<_>>(), vec![(2, "u2".into(), "matt".into()), (3, "u3".into(), "sam".into())]);
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/orgs/{org}/notes/n1"), Some(&sam), Some(json!({ "base": r2, "blob": "snap", "upTo": 2 }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let r3 = body["rev"].as_i64().unwrap();
    let (_, log) = h.call(Method::GET, &format!("/api/v1/orgs/{org}/notes/n1/updates?since=0"), Some(&matt), None).await;
    assert_eq!(log["items"].as_array().unwrap().iter().map(|u| u["seq"].as_i64().unwrap()).collect::<Vec<_>>(), vec![3]);
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/orgs/{org}/notes/n1"), Some(&matt), Some(json!({ "base": r3 }))).await;
    assert_eq!(status, StatusCode::OK);
    let (_, feed) = h.call(Method::GET, &format!("/api/v1/orgs/{org}/notes?since={r3}"), Some(&sam), None).await;
    assert_eq!((feed["items"][0]["deleted"].clone(), feed["items"][0]["blob"].clone()), (json!(true), Value::Null));
    let gone = h.call(Method::GET, &format!("/api/v1/orgs/{org}/notes/n1/updates?since=0"), Some(&sam), None).await;
    assert_eq!(gone, refusal(StatusCode::NOT_FOUND, "No such note."));
    let gone = h.call(Method::POST, &format!("/api/v1/orgs/{org}/notes/n1/updates"), Some(&sam), Some(json!({ "blobs": ["u9"] }))).await;
    assert_eq!(gone, refusal(StatusCode::NOT_FOUND, "No such note."));
    // What will not read.
    let unreadable = h.call(Method::PUT, &format!("/api/v1/orgs/{org}/notes/n2"), Some(&matt), Some(json!({ "base": 0, "blob": "" }))).await;
    assert_eq!(unreadable, refusal(StatusCode::BAD_REQUEST, "That note is empty or too large to sync."));
    h.call(Method::PUT, &format!("/api/v1/orgs/{org}/notes/n2"), Some(&matt), Some(json!({ "base": 0, "blob": "c" }))).await;
    let unreadable = h.call(Method::POST, &format!("/api/v1/orgs/{org}/notes/n2/updates"), Some(&matt), Some(json!({ "blobs": [] }))).await;
    assert_eq!(unreadable, refusal(StatusCode::BAD_REQUEST, "Those updates could not be read."));
    let unreadable = h.call(Method::PUT, &format!("/api/v1/orgs/{org}/notes/not%20an%20id"), Some(&matt), Some(json!({ "base": 0, "blob": "c" }))).await;
    assert_eq!(unreadable, refusal(StatusCode::BAD_REQUEST, "That id could not be read."));
}

#[tokio::test]
async fn a_file_is_kept_whole_under_the_organization_and_read_by_any_member() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let org = make(&h, &matt, "Ghost").await;
    join(&h, &matt, &org, &sam, "sam").await;
    let put = |token: &str, base: i64, bytes: &'static [u8]| {
        Request::builder().method(Method::PUT).uri(format!("/api/v1/orgs/{org}/files/v-n1?base={base}")).header("Authorization", format!("Bearer {token}")).header("Content-Type", "application/octet-stream").body(Body::from(bytes)).unwrap()
    };
    let (status, _, bytes) = h.send(put(&matt, 0, b"versions-1")).await;
    assert_eq!(status, StatusCode::OK);
    let rev: Value = serde_json::from_slice(&bytes).unwrap();
    let rev = rev["rev"].as_i64().unwrap();
    let (status, headers, bytes) = h.send(request(Method::GET, &format!("/api/v1/orgs/{org}/files/v-n1"), Some(&sam), None)).await;
    assert_eq!((status, bytes), (StatusCode::OK, b"versions-1".to_vec()));
    assert_eq!(headers.get("x-glyph-rev").unwrap().to_str().unwrap(), rev.to_string());
    let (status, _, bytes) = h.send(put(&sam, 0, b"stale")).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(serde_json::from_slice::<Value>(&bytes).unwrap(), json!({ "rev": rev }));
    let (status, _, _) = h.send(put(&sam, rev, b"versions-2")).await;
    assert_eq!(status, StatusCode::OK);
    let missing = h.call(Method::GET, &format!("/api/v1/orgs/{org}/files/nothing"), Some(&sam), None).await;
    assert_eq!(missing, refusal(StatusCode::NOT_FOUND, "No file by that id."));
}

#[tokio::test]
async fn a_stranger_and_an_invitee_get_one_404_from_every_route() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let lee = h.signup("lee", &device()).await;
    let org = make(&h, &matt, "Ghost").await;
    h.call(Method::PUT, &format!("/api/v1/orgs/{org}/notes/n1"), Some(&matt), Some(json!({ "base": 0, "blob": "c1" }))).await;
    let not_yours = refusal(StatusCode::NOT_FOUND, "No such organization.");
    let routes = [
        (Method::GET, format!("/api/v1/orgs/{org}/notes?since=0"), None),
        (Method::PUT, format!("/api/v1/orgs/{org}/notes/n1"), Some(json!({ "base": 0, "blob": "x" }))),
        (Method::DELETE, format!("/api/v1/orgs/{org}/notes/n1"), Some(json!({ "base": 0 }))),
        (Method::GET, format!("/api/v1/orgs/{org}/notes/n1/updates?since=0"), None),
        (Method::POST, format!("/api/v1/orgs/{org}/notes/n1/updates"), Some(json!({ "blobs": ["u"] }))),
        (Method::GET, format!("/api/v1/orgs/{org}/files/v-n1"), None),
    ];
    for (method, path, body) in &routes {
        let answer = h.call(method.clone(), path, Some(&lee), body.clone()).await;
        assert_eq!(answer, not_yours, "{method} {path}");
    }
    h.call(Method::POST, &format!("/api/v1/orgs/{org}/members"), Some(&matt), Some(json!({ "handle": "lee" }))).await;
    for (method, path, body) in &routes {
        let answer = h.call(method.clone(), path, Some(&lee), body.clone()).await;
        assert_eq!(answer, not_yours, "invited, not joined: {method} {path}");
    }
}
