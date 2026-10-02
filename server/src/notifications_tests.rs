//! Notifications, through the routes a device calls (docs/TEAMS.md): a device's own sealed row posted and read back,
//! a repeat of the post landing once, the feed's paging and its cursor, read marks and hiding fed again under new
//! revisions, what is kept and what is pruned, the limits, and one account never seeing another's.
//!
//! The rows the service writes - invitations and team changes - are tried where they are made, in orgs_tests.rs.

use crate::test_support::{device, Harness};
use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use serde_json::{json, Value};

/// A notification id as a device makes one: 128 random bits, base64url.
const ID: &str = "AbCdEfGhIjKlMnOpQrStUv";

fn harness() -> Harness {
    Harness::new("notifications")
}

async fn post(h: &Harness, token: &str, id: &str, kind: &str, blob: &str) -> (StatusCode, Value) {
    h.call(Method::POST, "/api/v1/notifications", Some(token), Some(json!({ "id": id, "kind": kind, "blob": blob }))).await
}

async fn feed_since(h: &Harness, token: &str, since: i64, limit: i64) -> Value {
    let (status, body) = h.call(Method::GET, &format!("/api/v1/notifications?since={since}&limit={limit}"), Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body
}

fn refusal(status: StatusCode, words: &str) -> (StatusCode, Value) {
    (status, json!({ "error": words }))
}

#[tokio::test]
async fn a_device_posts_its_own_sealed_row_reads_it_back_and_a_repeat_of_the_post_lands_once() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let (status, first) = post(&h, &matt, ID, "note-edited", "c2VhbGVk").await;
    assert_eq!(status, StatusCode::OK, "{first}");
    let rev = first["rev"].as_i64().unwrap();
    // Sent again, as a device does when the answer was lost: the same revision, nothing written.
    let (status, again) = post(&h, &matt, ID, "note-edited", "YW5vdGhlcg").await;
    assert_eq!((status, again["rev"].as_i64()), (StatusCode::OK, Some(rev)));
    let feed = feed_since(&h, &matt, 0, 100).await;
    assert_eq!((feed["rev"].clone(), feed["more"].clone()), (json!(rev), json!(false)));
    let items = feed["items"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0], json!({ "id": ID, "rev": rev, "kind": "note-edited", "at": items[0]["at"], "readAt": null, "hidden": false, "blob": "c2VhbGVk" }), "a device's own row: the blob and nothing else, no `from`, `org`, `body` or `state`");
    assert!(items[0]["at"].is_i64());
    // A note's own id is an id too, and a kind the app has not taught the service yet is taken as it is.
    let (status, _) = post(&h, &matt, "7c1e0d9a-3f4b-4c55-9a51-2d6f1f0e8b13", "something-new", "YQ").await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn only_the_account_s_own_kinds_can_be_posted_and_the_blob_and_the_body_have_their_limits() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let service_s = refusal(StatusCode::BAD_REQUEST, "That kind of notification is the service's to make.");
    for kind in ["invite", "invite-accepted", "invite-declined", "member-joined", "member-left", "member-removed", "role-changed", "org-renamed", "org-deleted"] {
        assert_eq!(post(&h, &matt, ID, kind, "YQ").await, service_s, "{kind}");
    }
    for kind in ["", "Note-Edited", "note edited", &"k".repeat(33)] {
        assert_eq!(post(&h, &matt, ID, kind, "YQ").await, refusal(StatusCode::BAD_REQUEST, "That kind of notification could not be read."), "{kind:?}");
    }
    assert_eq!(post(&h, &matt, "not an id", "note-edited", "YQ").await, refusal(StatusCode::BAD_REQUEST, "That notification's id could not be read."));
    assert_eq!(post(&h, &matt, &"a".repeat(65), "note-edited", "YQ").await, refusal(StatusCode::BAD_REQUEST, "That notification's id could not be read."));
    // The blob: 8 KB of base64url, and not a character more.
    let (status, _) = post(&h, &matt, ID, "note-edited", &"A".repeat(8 * 1024)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(post(&h, &matt, "two", "note-edited", &"A".repeat(8 * 1024 + 1)).await, refusal(StatusCode::BAD_REQUEST, "That notification is empty or too large."));
    assert_eq!(post(&h, &matt, "two", "note-edited", "").await, refusal(StatusCode::BAD_REQUEST, "That notification is empty or too large."));
    assert_eq!(post(&h, &matt, "two", "note-edited", "not base64!").await, refusal(StatusCode::BAD_REQUEST, "That notification is empty or too large."));
    // The body: 16 KB, before anything in it is read.
    let oversized = Request::post("/api/v1/notifications")
        .header(header::AUTHORIZATION, format!("Bearer {matt}"))
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(json!({ "id": "two", "kind": "note-edited", "blob": "A".repeat(17 * 1024) }).to_string()))
        .unwrap();
    let (status, _, _) = h.send(oversized).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(feed_since(&h, &matt, 0, 100).await["items"].as_array().unwrap().len(), 1, "only the one that passed");
}

#[tokio::test]
async fn read_marks_and_hiding_take_a_new_revision_and_are_fed_again() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    post(&h, &matt, "one", "summary-written", "YQ").await;
    let (_, two) = post(&h, &matt, "two", "summary-written", "YQ").await;
    let two = two["rev"].as_i64().unwrap();
    // Read on one device: the other, holding `two` as its cursor, is handed the row again.
    let (status, read) = h.call(Method::PUT, "/api/v1/notifications/one", Some(&matt), Some(json!({ "read": true }))).await;
    assert_eq!(status, StatusCode::OK, "{read}");
    let read = read["rev"].as_i64().unwrap();
    assert!(read > two);
    let feed = feed_since(&h, &matt, two, 100).await;
    assert_eq!(feed["items"].as_array().unwrap().len(), 1);
    assert_eq!((feed["items"][0]["id"].clone(), feed["items"][0]["rev"].clone(), feed["items"][0]["hidden"].clone()), (json!("one"), json!(read), json!(false)));
    assert!(feed["items"][0]["readAt"].is_i64());
    assert_eq!(feed["rev"], json!(read));
    // Hidden: fed again too, as deletions ride the notes feed, so a device that has it learns.
    let (_, hidden) = h.call(Method::PUT, "/api/v1/notifications/one", Some(&matt), Some(json!({ "hidden": true }))).await;
    let hidden = hidden["rev"].as_i64().unwrap();
    assert!(hidden > read);
    let feed = feed_since(&h, &matt, read, 100).await;
    assert_eq!((feed["items"][0]["id"].clone(), feed["items"][0]["hidden"].clone()), (json!("one"), json!(true)));
    assert!(feed["items"][0]["readAt"].is_i64(), "read stays read");
    // Unread and shown again, both at once.
    let (_, back) = h.call(Method::PUT, "/api/v1/notifications/one", Some(&matt), Some(json!({ "read": false, "hidden": false }))).await;
    let back = back["rev"].as_i64().unwrap();
    assert!(back > hidden);
    let feed = feed_since(&h, &matt, hidden, 100).await;
    assert_eq!((feed["items"][0]["readAt"].clone(), feed["items"][0]["hidden"].clone()), (Value::Null, json!(false)));
    // Marks by id, and "everything up to what I had seen".
    let (status, marked) = h.call(Method::POST, "/api/v1/notifications/read", Some(&matt), Some(json!({ "ids": ["one", "nope", "not an id"] }))).await;
    assert_eq!(status, StatusCode::OK, "{marked}");
    let marked = marked["rev"].as_i64().unwrap();
    assert!(marked > back);
    let (_, three) = post(&h, &matt, "three", "summary-written", "YQ").await;
    let (_, all) = h.call(Method::POST, "/api/v1/notifications/read", Some(&matt), Some(json!({ "all": true, "before": marked }))).await;
    let all = all["rev"].as_i64().unwrap();
    assert!(all > three["rev"].as_i64().unwrap());
    let items = feed_since(&h, &matt, 0, 100).await["items"].clone();
    let read_at = |id: &str| items.as_array().unwrap().iter().find(|n| n["id"] == id).map(|n| n["readAt"].is_i64());
    assert_eq!((read_at("one"), read_at("two"), read_at("three")), (Some(true), Some(true), Some(false)), "the row that arrived after `before` is not marked unseen");
    let (_, rest) = h.call(Method::POST, "/api/v1/notifications/read", Some(&matt), Some(json!({ "all": true }))).await;
    assert!(rest["rev"].as_i64().unwrap() > all);
    let items = feed_since(&h, &matt, 0, 100).await["items"].clone();
    assert!(items.as_array().unwrap().iter().all(|n| n["readAt"].is_i64()), "without `before`, everything");
    let (_, nothing) = h.call(Method::POST, "/api/v1/notifications/read", Some(&matt), Some(json!({}))).await;
    assert_eq!(nothing["rev"], rest["rev"], "nothing to mark answers the head");
    assert_eq!(h.call(Method::PUT, "/api/v1/notifications/nope", Some(&matt), Some(json!({ "read": true }))).await, refusal(StatusCode::NOT_FOUND, "No such notification."));
    assert_eq!(h.call(Method::PUT, "/api/v1/notifications/not%20an%20id", Some(&matt), Some(json!({ "read": true }))).await, refusal(StatusCode::BAD_REQUEST, "That notification's id could not be read."));
}

#[tokio::test]
async fn the_feed_pages_with_the_notes_feed_s_cursor_rule_and_clamps_its_limit() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    for i in 0..5 {
        post(&h, &matt, &format!("n-{i}"), "note-edited", "YQ").await;
    }
    let page = feed_since(&h, &matt, 0, 2).await;
    assert_eq!((page["items"].as_array().unwrap().len(), page["more"].clone()), (2, json!(true)));
    assert_eq!(page["rev"], page["items"][1]["rev"], "with more to come, the cursor is the last row given");
    let rest = feed_since(&h, &matt, page["rev"].as_i64().unwrap(), 10).await;
    assert_eq!((rest["items"].as_array().unwrap().len(), rest["more"].clone()), (3, json!(false)));
    assert_eq!(rest["rev"], rest["items"][2]["rev"], "and the head when there is not");
    for limit in ["0", "-5"] {
        let page = feed_since(&h, &matt, 0, limit.parse().unwrap()).await;
        assert_eq!(page["items"].as_array().unwrap().len(), 1, "limit={limit}: at least one");
    }
    let (status, page) = h.call(Method::GET, "/api/v1/notifications", Some(&matt), None).await;
    assert_eq!((status, page["items"].as_array().unwrap().len()), (StatusCode::OK, 5), "no `since`, no `limit`: everything, a hundred a page");
    let page = feed_since(&h, &matt, 0, 5000).await;
    assert_eq!(page["items"].as_array().unwrap().len(), 5, "a limit past two hundred is two hundred, which five is under");
    let (status, _) = h.call(Method::GET, "/api/v1/notifications?since=soon", Some(&matt), None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn one_account_never_sees_or_marks_another_s_rows() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    post(&h, &matt, ID, "note-edited", "bWluZQ").await;
    assert_eq!(feed_since(&h, &sam, 0, 100).await["items"], json!([]));
    assert_eq!(h.call(Method::PUT, &format!("/api/v1/notifications/{ID}"), Some(&sam), Some(json!({ "hidden": true }))).await, refusal(StatusCode::NOT_FOUND, "No such notification."));
    let (status, theirs) = post(&h, &sam, ID, "note-edited", "dGhlaXJz").await;
    assert_eq!(status, StatusCode::OK, "the same id in another account is another row");
    let (_, marked) = h.call(Method::POST, "/api/v1/notifications/read", Some(&sam), Some(json!({ "ids": [ID] }))).await;
    assert!(marked["rev"].as_i64().unwrap() > theirs["rev"].as_i64().unwrap());
    let mine = feed_since(&h, &matt, 0, 100).await;
    assert_eq!((mine["items"][0]["blob"].clone(), mine["items"][0]["readAt"].clone(), mine["items"][0]["hidden"].clone()), (json!("bWluZQ"), Value::Null, json!(false)), "untouched");
}

/// What the service keeps per account, at the store's number (store/notifications.rs `KEPT`): three hundred, the
/// read-or-hidden going first by age, and never a pending invitation. Seeded through the store, since the route
/// takes sixty a minute.
#[tokio::test]
async fn three_hundred_are_kept_the_read_ones_go_first_and_a_pending_invitation_never_goes() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let (_, body) = h.call(Method::POST, "/api/v1/orgs", Some(&sam), Some(json!({ "name": "Ghost" }))).await;
    let org = body["org"]["id"].as_str().unwrap().to_string();
    h.call(Method::POST, &format!("/api/v1/orgs/{org}/members"), Some(&sam), Some(json!({ "handle": "matt" }))).await;
    let store = &h.accounts.store;
    let matt_id = store.account_by_handle("matt").unwrap().id;
    let kept = crate::store::KEPT;
    for i in 0..kept - 1 {
        store.post_notification(matt_id, &format!("n-{i:04}"), "note-edited", "YQ", 1000 + i).unwrap();
    }
    let newest = format!("n-{:04}", kept - 2);
    h.call(Method::PUT, &format!("/api/v1/notifications/{newest}"), Some(&matt), Some(json!({ "read": true }))).await;
    let (status, _) = post(&h, &matt, "n-more", "note-edited", "YQ").await;
    assert_eq!(status, StatusCode::OK);
    let items = feed_since(&h, &matt, 0, 200).await;
    let more = feed_since(&h, &matt, items["rev"].as_i64().unwrap(), 200).await;
    let rows: Vec<&Value> = items["items"].as_array().unwrap().iter().chain(more["items"].as_array().unwrap()).collect();
    let ids: Vec<&str> = rows.iter().map(|n| n["id"].as_str().unwrap()).collect();
    assert_eq!(ids.len() as i64, kept, "the invitation among the three hundred");
    assert!(ids.contains(&"n-0000") && ids.contains(&"n-more") && !ids.contains(&newest.as_str()), "the read one went, whatever its revision");
    let invite = rows.iter().find(|n| n["kind"] == "invite").unwrap();
    assert_eq!(invite["state"], "pending");
}

/// Sixty posts a minute, the bucket full at the start; the refusal in its words. The bucket refills, so a slow
/// machine may earn one more before it; the refusal still comes.
#[tokio::test]
async fn sixty_posts_a_minute_then_a_refusal() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    for i in 0..60 {
        let (status, body) = post(&h, &matt, &format!("n-{i}"), "note-edited", "YQ").await;
        assert_eq!(status, StatusCode::OK, "post {i} of the minute's sixty: {body}");
    }
    let mut refused = None;
    for i in 60..80 {
        let answer = post(&h, &matt, &format!("n-{i}"), "note-edited", "YQ").await;
        if answer.0 == StatusCode::TOO_MANY_REQUESTS {
            refused = Some(answer);
            break;
        }
    }
    assert_eq!(refused, Some(refusal(StatusCode::TOO_MANY_REQUESTS, "Too many notifications in a minute. Try again shortly.")));
    // Reading and marking are not posts.
    let (status, _) = h.call(Method::GET, "/api/v1/notifications", Some(&matt), None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = h.call(Method::POST, "/api/v1/notifications/read", Some(&matt), Some(json!({ "all": true }))).await;
    assert_eq!(status, StatusCode::OK);
    // Nor is another account held to this one's minute.
    let sam = h.signup("sam", &device()).await;
    let (status, _) = post(&h, &sam, ID, "note-edited", "YQ").await;
    assert_eq!(status, StatusCode::OK);
}
