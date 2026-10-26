//! Ghost in a Google Meet, through the routes the mail provider, a device and the bot call (docs/MEET.md): an invite
//! mailed to the account's address booked, moved and called off; "join now", the list and a skip; the bot's routes
//! answered on this machine only and with its token; a recording sealed on arrival, kept only sealed and opened with
//! the account's private key alone; and the sweep forgetting a meeting's title and link once it is over.

use crate::mail::seal;
use crate::mail_tests::{heard_pokes, post, token, turned_on, with_key};
use crate::meet::ics::tests::{google_invite, google_zoom_invite, utc, zoom_invite, ZOOM_LINK};
use crate::meet::{self, take_seal_context, take_wrap_context, unpack, TEST_BOT_TOKEN};
use crate::store::MeetBooking;
use crate::test_support::{behind_caddy, device, routes, Harness};
use axum::body::{to_bytes, Body};
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Method, Request, StatusCode};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use serde_json::{json, Value};
use std::net::SocketAddr;
use tower::ServiceExt;

/// A Google Calendar invitation as it reaches a guest: the plain and HTML alternatives with the `text/calendar` part
/// beside them, and the same calendar again as `invite.ics`.
pub(crate) fn invite_mail(to: &str, ics: &str) -> String {
    let attached = STANDARD.encode(ics.as_bytes()).as_bytes().chunks(76).map(|line| String::from_utf8_lossy(line).into_owned()).collect::<Vec<_>>().join("\r\n");
    format!(
        "From: Sam Lee <sam@example.com>\r\n\
To: {to}\r\n\
Subject: Invitation: Roadmap review, Q4 @ Tue Jan 15, 2030 11am - 12pm (EST)\r\n\
Date: Fri, 16 Oct 2026 14:05:00 +0000\r\n\
MIME-Version: 1.0\r\n\
Content-Type: multipart/mixed; boundary=\"mixed\"\r\n\
\r\n\
--mixed\r\n\
Content-Type: multipart/alternative; boundary=\"alt\"\r\n\
\r\n\
--alt\r\n\
Content-Type: text/plain; charset=\"UTF-8\"\r\n\
\r\n\
You have been invited to the following event.\r\n\
--alt\r\n\
Content-Type: text/html; charset=\"UTF-8\"\r\n\
\r\n\
<p>You have been invited to the following event.</p>\r\n\
--alt\r\n\
Content-Type: text/calendar; charset=\"UTF-8\"; method=REQUEST\r\n\
Content-Transfer-Encoding: 7bit\r\n\
\r\n\
{ics}\r\n\
--alt--\r\n\
--mixed\r\n\
Content-Type: application/ics; name=\"invite.ics\"\r\n\
Content-Disposition: attachment; filename=\"invite.ics\"\r\n\
Content-Transfer-Encoding: base64\r\n\
\r\n\
{attached}\r\n\
--mixed--\r\n"
    )
}

/// The account's meetings, as its device lists them.
async fn meetings(h: &Harness, token: &str) -> Vec<Value> {
    let (status, body) = h.call(Method::GET, "/api/v1/meet", Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["meetings"].as_array().unwrap().clone()
}

/// A request as the bot makes one, over loopback with its token unless told otherwise.
fn bot(method: Method, path: &str, bearer: Option<&str>, body: Option<Value>) -> Request<Body> {
    let mut request = Request::builder().method(method).uri(path);
    if let Some(bearer) = bearer {
        request = request.header(header::AUTHORIZATION, format!("Bearer {bearer}"));
    }
    match body {
        Some(body) => request.header(header::CONTENT_TYPE, "application/json").body(Body::from(body.to_string())),
        None => request.body(Body::empty()),
    }
    .unwrap()
}

async fn bot_call(h: &Harness, method: Method, path: &str, body: Option<Value>) -> (StatusCode, Value) {
    let (status, _, bytes) = h.send(bot(method, path, Some(TEST_BOT_TOKEN), body)).await;
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// The bot's upload of a take: multipart, each part its name, its type and its bytes.
fn take_upload(meeting: &str, parts: &[(&str, Option<&str>, &[u8])]) -> Request<Body> {
    let mut body = Vec::new();
    for (name, kind, bytes) in parts {
        body.extend_from_slice(format!("--ghost-take\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{name}\"\r\n").as_bytes());
        if let Some(kind) = kind {
            body.extend_from_slice(format!("Content-Type: {kind}\r\n").as_bytes());
        }
        body.extend_from_slice(b"\r\n");
        body.extend_from_slice(bytes);
        body.extend_from_slice(b"\r\n");
    }
    body.extend_from_slice(b"--ghost-take--\r\n");
    Request::builder()
        .method(Method::PUT)
        .uri(format!("/api/internal/meet/{meeting}/take"))
        .header(header::AUTHORIZATION, format!("Bearer {TEST_BOT_TOKEN}"))
        .header(header::CONTENT_TYPE, "multipart/form-data; boundary=ghost-take")
        .body(Body::from(body))
        .unwrap()
}

/// Ghost booked into a Meet now, by a device; the booking's id.
async fn join_now(h: &Harness, token: &str, title: &str) -> String {
    let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(token), Some(json!({ "url": "https://meet.google.com/abc-defg-hij", "title": title }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["meeting"]["id"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn a_google_invite_mailed_to_the_address_books_ghost_and_its_updates_move_and_call_it_off() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &account).await;
    let invite = google_invite("REQUEST", 0, "20300115T110000", "20300115T120000", "CONFIRMED");
    let (status, _, bytes) = h.send(post(&address, invite_mail(&address, &invite).as_bytes(), &token(1))).await;
    assert_eq!(status, StatusCode::OK, "{}", String::from_utf8_lossy(&bytes));
    // The mail is a note as any mail is.
    let (_, mail) = h.call(Method::GET, "/api/v1/mail", Some(&account), None).await;
    assert_eq!(mail["mail"].as_array().unwrap().len(), 1);
    // And Ghost is booked, once, though the invite came twice in the mail.
    let listed = meetings(&h, &account).await;
    assert_eq!(listed.len(), 1, "{listed:?}");
    let id = listed[0]["id"].as_str().unwrap().to_string();
    assert_eq!(
        listed[0],
        json!({ "id": id, "title": "Roadmap review, Q4", "url": "https://meet.google.com/abc-defg-hij", "kind": "meet", "startsAt": utc(2030, 1, 15, 16, 0), "endsAt": utc(2030, 1, 15, 17, 0), "state": "booked", "detail": null })
    );
    // A newer SEQUENCE moves it, the same booking.
    let moved = google_invite("REQUEST", 1, "20300116T090000", "20300116T100000", "CONFIRMED").replace("abc-defg-hij", "xyz-wxyz-xyz");
    h.send(post(&address, invite_mail(&address, &moved).as_bytes(), &token(2))).await;
    let listed = meetings(&h, &account).await;
    assert_eq!(listed.len(), 1);
    assert_eq!((listed[0]["id"].as_str(), listed[0]["startsAt"].as_i64(), listed[0]["url"].as_str()), (Some(id.as_str()), Some(utc(2030, 1, 16, 14, 0)), Some("https://meet.google.com/xyz-wxyz-xyz")));
    // An older one, arriving late, changes nothing.
    let stale = google_invite("REQUEST", 0, "20300120T090000", "20300120T100000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &stale).as_bytes(), &token(3))).await;
    assert_eq!(meetings(&h, &account).await[0]["startsAt"].as_i64(), Some(utc(2030, 1, 16, 14, 0)));
    // Called off.
    let cancel = google_invite("CANCEL", 2, "20300116T090000", "20300116T100000", "CANCELLED");
    h.send(post(&address, invite_mail(&address, &cancel).as_bytes(), &token(4))).await;
    let listed = meetings(&h, &account).await;
    assert_eq!((listed[0]["state"].as_str(), listed[0]["detail"].as_str()), (Some("cancelled"), Some("The organizer called it off.")));
    // And invited again: booked again.
    let again = google_invite("REQUEST", 3, "20300117T090000", "20300117T100000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &again).as_bytes(), &token(5))).await;
    assert_eq!(meetings(&h, &account).await[0]["state"], "booked");
}

#[tokio::test]
async fn an_invite_without_a_meet_or_zoom_link_or_already_over_books_nothing() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &account).await;
    let teams = google_invite("REQUEST", 0, "20300115T110000", "20300115T120000", "CONFIRMED").replace("https://meet.google.com/abc-defg-hij", "https://teams.microsoft.com/l/meetup-join/19%3ameeting");
    h.send(post(&address, invite_mail(&address, &teams).as_bytes(), &token(1))).await;
    let past = google_invite("REQUEST", 0, "20200115T110000", "20200115T120000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &past).as_bytes(), &token(2))).await;
    assert!(meetings(&h, &account).await.is_empty());
    let (_, mail) = h.call(Method::GET, "/api/v1/mail", Some(&account), None).await;
    assert_eq!(mail["mail"].as_array().unwrap().len(), 2, "both are notes all the same");
}

#[tokio::test]
async fn zoom_s_own_invite_and_a_google_event_on_zoom_book_ghost_into_the_zoom_and_tell_the_bot_so() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &account).await;
    // Zoom's own invite, as Zoom mails it or a person forwards it.
    let zoom = zoom_invite("20300115T100000", "20300115T110000");
    let (status, _, bytes) = h.send(post(&address, invite_mail(&address, &zoom).as_bytes(), &token(1))).await;
    assert_eq!(status, StatusCode::OK, "{}", String::from_utf8_lossy(&bytes));
    let listed = meetings(&h, &account).await;
    assert_eq!(listed.len(), 1, "{listed:?}");
    let id = listed[0]["id"].as_str().unwrap().to_string();
    assert_eq!(
        listed[0],
        json!({ "id": id, "title": "Design sync", "url": ZOOM_LINK, "kind": "zoom", "startsAt": utc(2030, 1, 15, 18, 0), "endsAt": utc(2030, 1, 15, 19, 0), "state": "booked", "detail": null })
    );

    // A Google Calendar event on Zoom: booked, and moved to Meet by its update, the same booking.
    let google = google_zoom_invite("REQUEST", 0, "20300116T110000", "20300116T120000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &google).as_bytes(), &token(2))).await;
    let on_zoom = meetings(&h, &account).await.into_iter().find(|m| m["title"] == "Roadmap review, Q4").unwrap();
    assert_eq!((on_zoom["url"].as_str(), on_zoom["kind"].as_str()), (Some(ZOOM_LINK), Some("zoom")));
    let to_meet = google_invite("REQUEST", 1, "20300116T110000", "20300116T120000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &to_meet).as_bytes(), &token(3))).await;
    let moved = meetings(&h, &account).await.into_iter().find(|m| m["title"] == "Roadmap review, Q4").unwrap();
    assert_eq!((moved["id"].as_str(), moved["url"].as_str(), moved["kind"].as_str()), (on_zoom["id"].as_str(), Some("https://meet.google.com/abc-defg-hij"), Some("meet")));
    // And back to Zoom; then the Zoom link taken away with nothing in its place calls it off.
    let back = google_zoom_invite("REQUEST", 2, "20300116T110000", "20300116T120000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &back).as_bytes(), &token(4))).await;
    let gone = google_zoom_invite("REQUEST", 3, "20300116T110000", "20300116T120000", "CONFIRMED").replace(ZOOM_LINK, "(link to come)");
    h.send(post(&address, invite_mail(&address, &gone).as_bytes(), &token(5))).await;
    let called_off = meetings(&h, &account).await.into_iter().find(|m| m["title"] == "Roadmap review, Q4").unwrap();
    assert_eq!((called_off["state"].as_str(), called_off["detail"].as_str()), (Some("cancelled"), Some("The invite no longer has a Google Meet or Zoom link.")));

    // The bot is told which service each is, so it opens Zoom's web client for the Zoom.
    let (_, due) = bot_call(&h, Method::GET, "/api/internal/meet/due", None).await;
    assert_eq!(due["meetings"], json!([]), "not due yet");
    let now = join_now_url(&h, &account, "zoom.us/my/Sam.Lee").await;
    let (_, due) = bot_call(&h, Method::GET, "/api/internal/meet/due", None).await;
    let one = due["meetings"].as_array().unwrap().iter().find(|m| m["id"] == now.as_str()).unwrap().clone();
    assert_eq!((one["url"].as_str(), one["kind"].as_str()), (Some("https://zoom.us/my/sam.lee"), Some("zoom")));
}

/// Ghost booked now into the meeting at `url`, by a device; the booking's id.
async fn join_now_url(h: &Harness, token: &str, url: &str) -> String {
    let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(token), Some(json!({ "url": url }))).await;
    assert_eq!(status, StatusCode::OK, "{url}: {body}");
    body["meeting"]["id"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn join_now_takes_a_zoom_link_in_its_three_shapes_and_nothing_else_of_zoom_s() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    for (typed, booked) in [
        (" https://us06web.zoom.us/j/83512345678?pwd=bWVvT3h5Vm1uVTNtTHpuNnJ3QT09.1&uname=Sam ", "https://us06web.zoom.us/j/83512345678?pwd=bWVvT3h5Vm1uVTNtTHpuNnJ3QT09.1"),
        ("zoom.us/wc/join/123456789", "https://zoom.us/j/123456789"),
        ("https://acme.zoom.us/my/sam.lee", "https://acme.zoom.us/my/sam.lee"),
    ] {
        let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(&account), Some(json!({ "url": typed }))).await;
        assert_eq!(status, StatusCode::OK, "{typed}: {body}");
        assert_eq!((body["meeting"]["url"].as_str(), body["meeting"]["kind"].as_str()), (Some(booked), Some("zoom")), "{typed}");
    }
    for bad in [
        "https://zoom.us/j/1",
        "https://zoom.us/w/123456789",
        "https://zoom.us/s/123456789",
        "https://evilzoom.us/j/123456789",
        "https://zoom.us.evil.example/j/123456789",
        "https://a.b.zoom.us/j/123456789",
        "https://example.com/?zoom.us/j/123456789",
        "https://zoom.us/j/123456789/start",
    ] {
        let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(&account), Some(json!({ "url": bad }))).await;
        assert_eq!(
            (status, body),
            (StatusCode::BAD_REQUEST, json!({ "error": "That is not a Google Meet or Zoom link. It looks like meet.google.com/abc-defg-hij or zoom.us/j/123456789." })),
            "{bad}"
        );
    }
}

#[tokio::test]
async fn join_now_books_lists_and_skips_and_needs_the_account_s_key() {
    let h = Harness::new("meet");
    let keyless = h.signup("nokey", &device()).await;
    let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(&keyless), Some(json!({ "url": "https://meet.google.com/abc-defg-hij" }))).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "Your account needs its encryption key first. Sync once, then try again." })));
    let (status, _) = h.call(Method::POST, "/api/v1/meet", None, Some(json!({ "url": "https://meet.google.com/abc-defg-hij" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let (account, _) = with_key(&h, "sam").await;
    for bad in ["https://zoom.us/j/1", "https://meet.google.com/abc-defg-hijk", "meet.google.com.evil.example/abc-defg-hij"] {
        let (status, _) = h.call(Method::POST, "/api/v1/meet", Some(&account), Some(json!({ "url": bad }))).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{bad}");
    }
    let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(&account), Some(json!({ "url": " meet.google.com/ABC-defg-hij?authuser=0 ", "title": "  Stand-up " }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let meeting = &body["meeting"];
    assert_eq!((meeting["url"].as_str(), meeting["title"].as_str(), meeting["state"].as_str()), (Some("https://meet.google.com/abc-defg-hij"), Some("Stand-up"), Some("booked")));
    assert_eq!(meeting["endsAt"].as_i64().unwrap() - meeting["startsAt"].as_i64().unwrap(), 2 * 3600 * 1000);
    let id = meeting["id"].as_str().unwrap().to_string();
    assert_eq!(meetings(&h, &account).await, vec![meeting.clone()]);

    // Another account neither sees nor skips it.
    let (other, _) = with_key(&h, "ali").await;
    assert!(meetings(&h, &other).await.is_empty());
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/meet/{id}"), Some(&other), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, body) = h.call(Method::DELETE, &format!("/api/v1/meet/{id}"), Some(&account), None).await;
    assert_eq!((status, body["meeting"]["state"].as_str()), (StatusCode::OK, Some("skipped")));
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{id}/state"), Some(json!({ "state": "joining" }))).await;
    assert_eq!(status, StatusCode::CONFLICT, "a skipped meeting is not joined");

    // Skipped while Ghost is in it: it leaves.
    let id = join_now(&h, &account, "Second").await;
    let (status, body) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{id}/state"), Some(json!({ "state": "in_call" }))).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "id": id, "state": "in_call" })));
    let (_, body) = h.call(Method::DELETE, &format!("/api/v1/meet/{id}"), Some(&account), None).await;
    assert_eq!(body["meeting"]["state"], "leave");
    let (_, due) = bot_call(&h, Method::GET, "/api/internal/meet/due", None).await;
    assert_eq!(due["meetings"][0]["state"], "leave", "the bot reads that it is to leave");
    let (status, body) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{id}/state"), Some(json!({ "state": "in_call" }))).await;
    assert_eq!((status, body["state"].as_str()), (StatusCode::CONFLICT, Some("leave")));
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{id}/state"), Some(json!({ "state": "done", "detail": "left when asked" }))).await;
    assert_eq!(status, StatusCode::OK);
    let listed = meetings(&h, &account).await;
    let second = listed.iter().find(|m| m["id"] == id.as_str()).unwrap();
    assert_eq!((second["state"].as_str(), second["detail"].as_str()), (Some("done"), Some("left when asked")));
}

#[tokio::test]
async fn the_bot_is_told_what_is_due_and_moves_it_on() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let id = join_now(&h, &account, "Planning").await;
    let (status, due) = bot_call(&h, Method::GET, "/api/internal/meet/due", None).await;
    assert_eq!(status, StatusCode::OK);
    let one = &due["meetings"][0];
    assert_eq!((one["id"].as_str(), one["url"].as_str(), one["title"].as_str(), one["state"].as_str()), (Some(id.as_str()), Some("https://meet.google.com/abc-defg-hij"), Some("Planning"), Some("booked")));
    assert_eq!(one["announce"], meet::ANNOUNCE);
    assert!(one["startsAt"].is_i64() && one["endsAt"].is_i64());
    for state in ["joining", "in_call", "failed"] {
        let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{id}/state"), Some(json!({ "state": state, "detail": "not admitted" }))).await;
        assert_eq!(status, StatusCode::OK, "{state}");
    }
    let (_, due) = bot_call(&h, Method::GET, "/api/internal/meet/due", None).await;
    assert_eq!(due["meetings"], json!([]), "failed is not due");
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{id}/state"), Some(json!({ "state": "booked" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "booked is not the bot's to set");
    let (status, _) = bot_call(&h, Method::POST, "/api/internal/meet/nope/state", Some(json!({ "state": "joining" }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn the_bot_s_routes_answer_only_this_machine_and_only_with_its_token() {
    let h = Harness::new("meet");
    let path = "/api/internal/meet/due";
    let (status, _, _) = h.send(bot(Method::GET, path, Some(TEST_BOT_TOKEN), None)).await;
    assert_eq!(status, StatusCode::OK);
    for wrong in [None, Some("meet-bot-test-token-0123456789abcdef012345678X"), Some("")] {
        let (status, _, _) = h.send(bot(Method::GET, path, wrong, None)).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{wrong:?}");
    }
    // Through Caddy: loopback still, but it says whom it is passing on.
    let mut proxied = bot(Method::GET, path, Some(TEST_BOT_TOKEN), None);
    proxied.headers_mut().insert("x-forwarded-for", "203.0.113.5".parse().unwrap());
    let (status, _, _) = h.send(proxied).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // From another machine, with the token.
    let outside = routes(Some(h.accounts.clone())).layer(MockConnectInfo(SocketAddr::from(([203, 0, 113, 5], 40000))));
    let response = outside.oneshot(bot(Method::GET, path, Some(TEST_BOT_TOKEN), None)).await.unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    let take = routes(Some(h.accounts.clone())).layer(MockConnectInfo(SocketAddr::from(([10, 0, 0, 2], 40000))));
    let response = take.oneshot(take_upload("x", &[("audio", Some("audio/webm"), b"sound")])).await.unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    // And with no token set up, the routes are not there at all.
    let unmounted = behind_caddy(meet::router(h.accounts.clone(), None));
    let response = unmounted.oneshot(bot(Method::GET, path, Some(TEST_BOT_TOKEN), None)).await.unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_take_is_sealed_on_arrival_kept_only_sealed_and_opened_by_the_account_alone() {
    let h = Harness::new("meet");
    let (account, secret) = with_key(&h, "sam").await;
    let id = join_now(&h, &account, "Budget").await;
    let audio = b"\x1aE\xdf\xa3 webm opus PRIVATE-AUDIO-MARKER and the rest of the meeting".to_vec();
    let captions = b"{\"at\":1,\"who\":\"Alice\",\"text\":\"PRIVATE-CAPTION-MARKER the pricing page\"}\n".to_vec();
    let upload = take_upload(&id, &[("audio", Some("audio/webm;codecs=opus"), &audio), ("captions", Some("application/x-ndjson"), &captions), ("startedAt", None, b"1792159500000")]);
    let (status, _, bytes) = h.send(upload).await;
    let answer: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(status, StatusCode::OK, "{answer}");
    let take = answer["take"].as_str().unwrap().to_string();
    assert_eq!(meetings(&h, &account).await[0]["state"], "done");

    // Nothing of it is in the clear anywhere the service keeps files.
    let mut files = vec![h.dir.path().to_path_buf()];
    let mut seen = Vec::new();
    while let Some(dir) = files.pop() {
        for entry in std::fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                files.push(path);
            } else {
                seen.extend(std::fs::read(&path).unwrap());
            }
        }
    }
    assert!(!seen.is_empty(), "the take is a file");
    let text = String::from_utf8_lossy(&seen);
    assert!(!text.contains("PRIVATE-AUDIO-MARKER") && !text.contains("PRIVATE-CAPTION-MARKER") && !text.contains("pricing"), "the take is in the clear on disk");

    // The device lists it, downloads it raw, and opens it with the account's key.
    let (status, body) = h.call(Method::GET, "/api/v1/meet/takes", Some(&account), None).await;
    assert_eq!(status, StatusCode::OK);
    let listed = &body["takes"][0];
    assert_eq!((listed["id"].as_str(), listed["meeting"].as_str(), listed["size"].as_i64()), (Some(take.as_str()), Some(id.as_str()), answer["size"].as_i64()));
    assert!(listed["at"].as_i64().unwrap() > 1_700_000_000_000);
    let (status, headers, sealed) = h.send(crate::test_support::request(Method::GET, &format!("/api/v1/meet/takes/{take}"), Some(&account), None)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers[header::CONTENT_TYPE], "application/octet-stream");
    assert_eq!(headers["x-glyph-meeting"], id.as_str());
    let wrapped = headers["x-glyph-wrapped"].to_str().unwrap().to_string();
    assert_eq!(listed["wrapped"].as_str(), Some(wrapped.as_str()));
    assert_eq!(sealed.len() as i64, answer["size"].as_i64().unwrap());
    let opened = seal::open_sealed_with(&secret, &wrapped, &take_wrap_context(&take), &sealed, &take_seal_context(&take)).unwrap();
    let (head, got_captions, got_audio) = unpack(&opened);
    assert_eq!((got_audio, got_captions), (audio.clone(), captions.clone()));
    assert_eq!(head["v"], 1);
    assert_eq!((head["meeting"].as_str(), head["title"].as_str(), head["mime"].as_str()), (Some(id.as_str()), Some("Budget"), Some("audio/webm;codecs=opus")));
    assert_eq!((head["startedAt"].as_i64(), head["captionsBytes"].as_u64(), head["audioBytes"].as_u64()), (Some(1_792_159_500_000), Some(captions.len() as u64), Some(audio.len() as u64)));
    assert!(head["endedAt"].as_i64().unwrap() > 1_700_000_000_000);
    assert_eq!(head["kind"], "meet", "which service it was, for the note's words");
    let other = p256::SecretKey::random(&mut rand::rngs::OsRng);
    assert!(seal::open_sealed_with(&other, &wrapped, &take_wrap_context(&take), &sealed, &take_seal_context(&take)).is_err());

    // Another account cannot read or take it; taken, it is gone.
    let (stranger, _) = with_key(&h, "ali").await;
    let (status, _) = h.call(Method::GET, &format!("/api/v1/meet/takes/{take}"), Some(&stranger), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    h.call(Method::DELETE, &format!("/api/v1/meet/takes/{take}"), Some(&stranger), None).await;
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/meet/takes/{take}"), Some(&account), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, body) = h.call(Method::GET, "/api/v1/meet/takes", Some(&account), None).await;
    assert_eq!(body["takes"], json!([]));
    let (status, _) = h.call(Method::GET, &format!("/api/v1/meet/takes/{take}"), Some(&account), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_take_needs_its_audio_and_a_meeting_that_was_not_called_off() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let id = join_now(&h, &account, "One").await;
    let (status, _, _) = h.send(take_upload(&id, &[("captions", Some("application/x-ndjson"), b"{}\n")])).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _, _) = h.send(take_upload("no-such-meeting", &[("audio", Some("audio/webm"), b"sound")])).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    h.call(Method::DELETE, &format!("/api/v1/meet/{id}"), Some(&account), None).await;
    let (status, _, _) = h.send(take_upload(&id, &[("audio", Some("audio/webm"), b"sound")])).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (_, body) = h.call(Method::GET, "/api/v1/meet/takes", Some(&account), None).await;
    assert_eq!(body["takes"], json!([]));
}

#[tokio::test]
async fn the_sweep_forgets_a_meeting_s_title_and_link_an_hour_after_it_is_over() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let id = join_now(&h, &account, "Secret project").await;
    let ends = meetings(&h, &account).await[0]["endsAt"].as_i64().unwrap();
    assert_eq!(meet::sweep(&h.accounts.store, ends + meet::CLEAR_FOR - 1), (0, 0), "not yet an hour");
    assert_eq!(meet::sweep(&h.accounts.store, ends + meet::CLEAR_FOR), (1, 0));
    let listed = meetings(&h, &account).await;
    assert_eq!((listed[0]["id"].as_str(), &listed[0]["title"], &listed[0]["url"]), (Some(id.as_str()), &Value::Null, &Value::Null));
    assert_eq!((listed[0]["state"].as_str(), listed[0]["detail"].as_str()), (Some("failed"), Some("missed")), "the bot never came");
    assert_eq!(meet::sweep(&h.accounts.store, ends + meet::KEPT_FOR), (0, 1));
    assert!(h.accounts.store.meet_booking(&id).is_none());
    // Nothing of it is answered whole any more, either.
    let response = h.service.clone().oneshot(crate::test_support::request(Method::GET, "/api/v1/meet", Some(&account), None)).await.unwrap();
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert!(!String::from_utf8_lossy(&body).contains("Secret project"));
}

// --- recurring meetings --------------------------------------------------------------------------
//
// These book at times of their own (`book_from_mail`, `advance` and `sweep` take `now`), so a series is followed across
// days with no new mail. The device's list and `due` move a series on at the real now, which is before every meeting
// here: that changes nothing a test does not mean it to.

/// The UID of `google_invite`.
const UID: &str = "7kukuqrfedlm2f9t0vd0b2gscq@google.com";

/// `google_invite` made a series by the lines `rule` (an RRULE, EXDATEs), each ending `\r\n`.
fn series(method: &str, sequence: i64, start: &str, end: &str, status: &str, rule: &str) -> String {
    google_invite(method, sequence, start, end, status).replace("TRANSP:OPAQUE\r\n", &format!("TRANSP:OPAQUE\r\n{rule}"))
}

/// The same calendar with one more VEVENT: an occurrence of the series changed on its own.
fn with_changed(calendar: &str, recurrence_id: &str, start: &str, end: &str, sequence: i64, status: &str) -> String {
    calendar.replace(
        "END:VCALENDAR\r\n",
        &format!(
            "BEGIN:VEVENT\r\nUID:{UID}\r\nRECURRENCE-ID;TZID=America/New_York:{recurrence_id}\r\nDTSTART;TZID=America/New_York:{start}\r\n\
DTEND;TZID=America/New_York:{end}\r\nSEQUENCE:{sequence}\r\nSTATUS:{status}\r\nSUMMARY:Stand-up, moved\r\nX-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        ),
    )
}

/// One VCALENDAR of only a changed occurrence, as Google mails "this event" alone.
fn only_changed(method: &str, recurrence_id: &str, start: &str, end: &str, sequence: i64, status: &str) -> String {
    let empty = format!("BEGIN:VCALENDAR\r\nPRODID:-//Google Inc//Google Calendar 70.9054//EN\r\nVERSION:2.0\r\nMETHOD:{method}\r\nEND:VCALENDAR\r\n");
    with_changed(&empty, recurrence_id, start, end, sequence, status)
}

/// An account with its key, and its id.
async fn sam(h: &Harness) -> (String, i64) {
    let (token, _) = with_key(h, "sam").await;
    let id = h.accounts.store.account_by_handle("sam").unwrap().id;
    (token, id)
}

/// The invite `calendar`, mailed to `account` at `now`.
fn mailed(h: &Harness, account: i64, calendar: &str, now: i64) -> usize {
    meet::book_from_mail(&h.accounts.store, account, invite_mail("k7m2q9xh4t3vbn8p@in.ghostmarkdown.com", calendar).as_bytes(), now)
}

/// The account's meetings, every one the device would list, soonest first.
fn listed(h: &Harness, account: i64) -> Vec<MeetBooking> {
    h.accounts.store.meet_bookings(account, i64::MIN)
}

/// What the bot is told is due at `now`, the series moved on first as `due` moves them.
fn due_at(h: &Harness, now: i64) -> Vec<MeetBooking> {
    meet::advance(&h.accounts.store, now);
    h.accounts.store.meet_due(now, 120_000, 900_000)
}

/// The series' own row.
fn series_row(h: &Harness, account: i64) -> MeetBooking {
    h.accounts.store.meet_booking_by_uid(account, UID).unwrap()
}

/// The bot's part in one meeting: joining, in it, and out.
async fn attended(h: &Harness, id: &str) {
    for state in ["joining", "in_call", "done"] {
        let (status, body) = bot_call(h, Method::POST, &format!("/api/internal/meet/{id}/state"), Some(json!({ "state": state }))).await;
        assert_eq!(status, StatusCode::OK, "{state}: {body}");
    }
}

#[tokio::test]
async fn a_daily_series_is_joined_every_day_with_no_new_mail_and_keeps_its_link_between() {
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    // A stand-up at 11:00 in New York (16:00 UTC in January), every day from 2030-01-15.
    let daily = series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n");
    assert_eq!(mailed(&h, account, &daily, utc(2030, 1, 10, 12, 0)), 1);
    // The device lists the one occurrence booked; the series' own row is no meeting of its list, nor its to skip.
    let listed_now = meetings(&h, &token).await;
    assert_eq!(listed_now.len(), 1, "{listed_now:?}");
    assert_eq!((listed_now[0]["startsAt"].as_i64(), listed_now[0]["url"].as_str()), (Some(utc(2030, 1, 15, 16, 0)), Some("https://meet.google.com/abc-defg-hij")));
    let own = series_row(&h, account);
    assert_eq!((own.state.as_str(), own.uid.as_str()), ("series", UID));
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/meet/{}", own.id), Some(&token), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{}/state", own.id), Some(json!({ "state": "joining" }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Day one: due, joined, and the take kept for it.
    let first = due_at(&h, utc(2030, 1, 15, 15, 59));
    assert_eq!(first.len(), 1);
    let one = first[0].id.clone();
    assert_eq!(first[0].uid, format!("{UID}#{}", utc(2030, 1, 15, 16, 0)));
    for state in ["joining", "in_call"] {
        bot_call(&h, Method::POST, &format!("/api/internal/meet/{one}/state"), Some(json!({ "state": state }))).await;
    }
    let (status, _, _) = h.send(take_upload(&one, &[("audio", Some("audio/webm"), b"day one")])).await;
    assert_eq!(status, StatusCode::OK);
    // Done, the next day is booked as a meeting of its own: a fresh id, booked, with the link.
    assert!(due_at(&h, utc(2030, 1, 15, 16, 16)).is_empty(), "nothing is due until tomorrow");
    let all = listed(&h, account);
    assert_eq!(all.iter().map(|b| (b.starts_at, b.state.as_str())).collect::<Vec<_>>(), vec![(utc(2030, 1, 15, 16, 0), "done"), (utc(2030, 1, 16, 16, 0), "booked")]);
    let two = all[1].id.clone();
    assert_ne!(one, two);
    // The take still names day one, which is still there to name.
    let (_, takes) = h.call(Method::GET, "/api/v1/meet/takes", Some(&token), None).await;
    assert_eq!(takes["takes"][0]["meeting"].as_str(), Some(one.as_str()));

    // The sweep between: day one's title and link are forgotten; the series and day two keep theirs.
    meet::sweep(&h.accounts.store, utc(2030, 1, 15, 18, 0));
    let day_one = h.accounts.store.meet_booking(&one).unwrap();
    assert_eq!((day_one.url.as_str(), day_one.title, day_one.state.as_str()), ("", None, "done"));
    assert_eq!(series_row(&h, account).url, "https://meet.google.com/abc-defg-hij");
    assert_eq!(h.accounts.store.meet_booking(&two).unwrap().url, "https://meet.google.com/abc-defg-hij");

    // Day two: joined.
    assert_eq!(due_at(&h, utc(2030, 1, 16, 15, 59)).iter().map(|b| b.id.clone()).collect::<Vec<_>>(), vec![two.clone()]);
    attended(&h, &two).await;
    // Day three is booked; the bot never comes, and the day after is booked all the same once it is over.
    let three = due_at(&h, utc(2030, 1, 17, 15, 59));
    assert_eq!((three.len(), three[0].starts_at), (1, utc(2030, 1, 17, 16, 0)));
    meet::sweep(&h.accounts.store, utc(2030, 1, 17, 18, 0));
    let missed = h.accounts.store.meet_booking(&three[0].id).unwrap();
    assert_eq!((missed.state.as_str(), missed.detail.as_deref()), ("failed", Some("missed")));
    let four = due_at(&h, utc(2030, 1, 18, 15, 59));
    assert_eq!((four.len(), four[0].starts_at, four[0].url.as_str()), (1, utc(2030, 1, 18, 16, 0), "https://meet.google.com/abc-defg-hij"));
    // And a month on, the occurrences that are thirty days over are gone while the series runs on.
    meet::sweep(&h.accounts.store, utc(2030, 2, 17, 12, 0));
    assert!(h.accounts.store.meet_booking(&one).is_none());
    let own = series_row(&h, account);
    assert_eq!((own.state.as_str(), own.url.as_str(), own.starts_at), ("series", "https://meet.google.com/abc-defg-hij", utc(2030, 2, 17, 16, 0)));
}

#[tokio::test]
async fn a_weekday_series_in_new_york_keeps_its_wall_clock_time_across_the_change_of_clocks() {
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    // 9:00 in New York, Monday to Friday, from Friday 2030-03-08; the clocks go forward on Sunday the 10th.
    let weekdays = series("REQUEST", 0, "20300308T090000", "20300308T091500", "CONFIRMED", "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR\r\n");
    mailed(&h, account, &weekdays, utc(2030, 3, 1, 12, 0));
    let mut joined = Vec::new();
    // Each morning, a minute before: what is due, joined.
    for (day, hour) in [(8, 14), (11, 13), (12, 13), (13, 13), (14, 13), (15, 13), (18, 13)] {
        let due = due_at(&h, utc(2030, 3, day, hour, 0) - 60_000);
        assert_eq!(due.len(), 1, "the {day}th: {due:?}");
        assert!(!joined.contains(&due[0].id), "a fresh booking each day");
        joined.push(due[0].id.clone());
        attended(&h, &due[0].id).await;
        assert_eq!(h.accounts.store.meet_booking(&due[0].id).unwrap().starts_at, utc(2030, 3, day, hour, 0), "the {day}th at 9:00 New York time");
    }
    // Nothing is booked on the weekend: Friday the 15th was followed by Monday the 18th.
    assert!(listed(&h, account).iter().all(|b| b.starts_at != utc(2030, 3, 16, 13, 0) && b.starts_at != utc(2030, 3, 17, 13, 0)));
}

#[tokio::test]
async fn an_exdate_and_occurrences_changed_or_called_off_on_their_own_are_passed_over_by_the_series() {
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    // Daily at 11:00 New York (16:00 UTC), not on the 16th; the 17th moved to 14:00 (19:00 UTC) in the same invite.
    let daily = series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\nEXDATE;TZID=America/New_York:20300116T110000\r\n");
    let daily = with_changed(&daily, "20300117T110000", "20300117T140000", "20300117T141500", 1, "CONFIRMED");
    mailed(&h, account, &daily, utc(2030, 1, 10, 12, 0));
    let starts = |h: &Harness| listed(h, account).iter().map(|b| (b.starts_at, b.state.clone())).collect::<Vec<_>>();
    assert_eq!(starts(&h), vec![(utc(2030, 1, 15, 16, 0), "booked".into()), (utc(2030, 1, 17, 19, 0), "booked".into())]);
    let moved = listed(&h, account)[1].clone();
    assert_eq!((moved.uid, moved.title.as_deref()), (format!("{UID}#{}", utc(2030, 1, 17, 16, 0)), Some("Stand-up, moved")));
    attended(&h, &listed(&h, account)[0].id).await;
    // Over: the 16th is excluded and the 17th is booked on its own, so the next the series books is the 18th.
    meet::advance(&h.accounts.store, utc(2030, 1, 15, 16, 20));
    assert_eq!(starts(&h)[1..], [(utc(2030, 1, 17, 19, 0), "booked".into()), (utc(2030, 1, 18, 16, 0), "booked".into())]);
    // The 19th called off on its own, in a mail of its own, before the series reaches it.
    mailed(&h, account, &only_changed("CANCEL", "20300119T110000", "20300119T110000", "20300119T111500", 1, "CANCELLED"), utc(2030, 1, 16, 12, 0));
    let cancelled = h.accounts.store.meet_booking_by_uid(account, &format!("{UID}#{}", utc(2030, 1, 19, 16, 0))).unwrap();
    assert_eq!((cancelled.state.as_str(), cancelled.url.as_str()), ("cancelled", ""), "kept as called off, with no link");
    // The moved 17th joined at its own time; after the 18th, not the 19th but the 20th.
    assert_eq!(due_at(&h, utc(2030, 1, 17, 18, 59)).iter().map(|b| b.id.clone()).collect::<Vec<_>>(), vec![moved.id.clone()]);
    attended(&h, &moved.id).await;
    let eighteenth = listed(&h, account).into_iter().find(|b| b.starts_at == utc(2030, 1, 18, 16, 0)).unwrap();
    attended(&h, &eighteenth.id).await;
    let due = due_at(&h, utc(2030, 1, 20, 15, 59));
    assert_eq!((due.len(), due[0].starts_at), (1, utc(2030, 1, 20, 16, 0)), "the 19th is passed over");
    assert!(due_at(&h, utc(2030, 1, 19, 15, 59)).is_empty());
}

#[tokio::test]
async fn a_series_called_off_calls_off_what_it_booked_and_books_no_more() {
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    let daily = series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n");
    mailed(&h, account, &daily, utc(2030, 1, 10, 12, 0));
    let one = listed(&h, account)[0].id.clone();
    for state in ["joining", "in_call"] {
        bot_call(&h, Method::POST, &format!("/api/internal/meet/{one}/state"), Some(json!({ "state": state }))).await;
    }
    // Called off while Ghost is in day one: it leaves; and the series is over.
    let cancel = series("CANCEL", 1, "20300115T110000", "20300115T111500", "CANCELLED", "RRULE:FREQ=DAILY\r\n");
    mailed(&h, account, &cancel, utc(2030, 1, 15, 16, 5));
    assert_eq!(h.accounts.store.meet_booking(&one).unwrap().state, "leave");
    assert_eq!(series_row(&h, account).state, "cancelled");
    bot_call(&h, Method::POST, &format!("/api/internal/meet/{one}/state"), Some(json!({ "state": "done" }))).await;
    for day in 16..=20 {
        assert!(due_at(&h, utc(2030, 1, day, 15, 59)).is_empty(), "the {day}th");
    }
    assert_eq!(listed(&h, account).len(), 1);
    // Its link goes an hour after it was called off, and the series' row a month after.
    meet::sweep(&h.accounts.store, utc(2030, 1, 15, 17, 5));
    assert_eq!((series_row(&h, account).url.as_str(), series_row(&h, account).title), ("", None));
    meet::sweep(&h.accounts.store, utc(2030, 2, 15, 17, 5));
    assert!(h.accounts.store.meet_booking_by_uid(account, UID).is_none());

    // A series called off before the occurrence it booked: that occurrence is called off.
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    mailed(&h, account, &daily, utc(2030, 1, 10, 12, 0));
    mailed(&h, account, &cancel, utc(2030, 1, 11, 12, 0));
    let only = &listed(&h, account)[0];
    assert_eq!((only.state.as_str(), only.detail.as_deref()), ("cancelled", Some("The organizer called it off.")));
}

#[tokio::test]
async fn a_series_updated_by_a_higher_sequence_moves_what_it_booked_and_what_it_books_next() {
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    mailed(&h, account, &series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 1, 10, 12, 0));
    let before = listed(&h, account)[0].clone();
    // Moved to 9:30 with a new link, before the first: the 11:00 booking is gone, the 9:30 one booked.
    let moved = series("REQUEST", 1, "20300115T093000", "20300115T094500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n").replace("abc-defg-hij", "xyz-wxyz-xyz");
    mailed(&h, account, &moved, utc(2030, 1, 11, 12, 0));
    assert!(h.accounts.store.meet_booking(&before.id).is_none());
    let after = listed(&h, account);
    assert_eq!(after.len(), 1);
    assert_eq!((after[0].starts_at, after[0].url.as_str()), (utc(2030, 1, 15, 14, 30), "https://meet.google.com/xyz-wxyz-xyz"));
    assert_eq!(series_row(&h, account).url, "https://meet.google.com/xyz-wxyz-xyz");
    // An older copy arriving late changes nothing.
    mailed(&h, account, &series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 1, 12, 12, 0));
    assert_eq!(listed(&h, account).iter().map(|b| b.starts_at).collect::<Vec<_>>(), vec![utc(2030, 1, 15, 14, 30)]);
    // A new title at the same time: the same booking follows it.
    mailed(&h, account, &moved.replace("SEQUENCE:1", "SEQUENCE:2").replace("Roadmap review\\, Q4", "Stand-up"), utc(2030, 1, 13, 12, 0));
    let renamed = listed(&h, account);
    assert_eq!((renamed.len(), renamed[0].id.as_str(), renamed[0].title.as_deref()), (1, after[0].id.as_str(), Some("Stand-up")));
    // And the next day is booked by the rule as it is now.
    attended(&h, &renamed[0].id).await;
    let next = due_at(&h, utc(2030, 1, 16, 14, 29));
    assert_eq!((next.len(), next[0].starts_at, next[0].url.as_str(), next[0].title.as_deref()), (1, utc(2030, 1, 16, 14, 30), "https://meet.google.com/xyz-wxyz-xyz", Some("Stand-up")));
}

#[tokio::test]
async fn count_and_until_end_a_series_and_the_sweep_then_forgets_it() {
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    mailed(&h, account, &series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY;COUNT=2\r\n"), utc(2030, 1, 10, 12, 0));
    attended(&h, &due_at(&h, utc(2030, 1, 15, 15, 59))[0].id).await;
    attended(&h, &due_at(&h, utc(2030, 1, 16, 15, 59))[0].id).await;
    // Two, and done: nothing on the third day, and the series is over.
    assert!(due_at(&h, utc(2030, 1, 17, 15, 59)).is_empty());
    assert_eq!(listed(&h, account).len(), 2);
    let own = series_row(&h, account);
    assert_eq!((own.state.as_str(), own.ends_at), ("done", utc(2030, 1, 16, 16, 15)));
    // So the sweep forgets it as any meeting: its link an hour after the last ended, the row a month after.
    meet::sweep(&h.accounts.store, utc(2030, 1, 16, 17, 15));
    assert_eq!((series_row(&h, account).url.as_str(), series_row(&h, account).title), ("", None));
    meet::sweep(&h.accounts.store, utc(2030, 2, 15, 16, 15));
    assert!(h.accounts.store.meet_booking_by_uid(account, UID).is_none());

    // UNTIL, moved earlier by an update before the occurrence booked: that booking goes, and the series is over.
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    mailed(&h, account, &series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 1, 16, 12, 0));
    assert_eq!(listed(&h, account)[0].starts_at, utc(2030, 1, 16, 16, 0), "the 15th is over: the 16th");
    let ended = series("REQUEST", 1, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY;UNTIL=20300115T235959Z\r\n");
    mailed(&h, account, &ended, utc(2030, 1, 16, 12, 30));
    assert!(listed(&h, account).is_empty());
    assert_eq!(series_row(&h, account).state, "done");
    assert!(due_at(&h, utc(2030, 1, 16, 15, 59)).is_empty());
}

#[tokio::test]
async fn skipping_one_occurrence_skips_that_one_and_not_the_series() {
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    mailed(&h, account, &series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 1, 10, 12, 0));
    let first = meetings(&h, &token).await[0]["id"].as_str().unwrap().to_string();
    let (status, body) = h.call(Method::DELETE, &format!("/api/v1/meet/{first}"), Some(&token), None).await;
    assert_eq!((status, body["meeting"]["state"].as_str()), (StatusCode::OK, Some("skipped")));
    // The device's list has the skip, and the next day booked already.
    let now = meetings(&h, &token).await;
    assert_eq!(
        now.iter().map(|m| (m["startsAt"].as_i64().unwrap(), m["state"].as_str().unwrap().to_string())).collect::<Vec<_>>(),
        vec![(utc(2030, 1, 15, 16, 0), "skipped".to_string()), (utc(2030, 1, 16, 16, 0), "booked".to_string())]
    );
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{first}/state"), Some(json!({ "state": "joining" }))).await;
    assert_eq!(status, StatusCode::CONFLICT, "the skipped day is not joined");
    assert!(due_at(&h, utc(2030, 1, 15, 15, 59)).is_empty());
    let next = due_at(&h, utc(2030, 1, 16, 15, 59));
    assert_eq!((next.len(), next[0].starts_at), (1, utc(2030, 1, 16, 16, 0)));
    assert_eq!(series_row(&h, account).state, "series");
}

#[tokio::test]
async fn a_series_counts_one_occurrence_at_a_time_and_waits_for_room_under_the_limit() {
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    mailed(&h, account, &series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 1, 10, 12, 0));
    let first = listed(&h, account)[0].id.clone();
    // A hundred more to come: the account's hundred, and the first besides.
    let store = &h.accounts.store;
    for n in 0..100 {
        let b = MeetBooking { id: format!("f{n}"), uid: format!("filler-{n}"), starts_at: utc(2031, 1, 1, 0, 0), ends_at: utc(2031, 1, 1, 1, 0), series: None, ..store.meet_booking(&first).unwrap() };
        assert!(store.insert_meet_booking(&b, 1).unwrap());
    }
    assert_eq!(store.meet_upcoming(account, utc(2030, 1, 10, 12, 0)), 101, "the series' own row is not counted");
    let another = series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n").replace(UID, "another@google.com");
    assert_eq!(mailed(&h, account, &another, utc(2030, 1, 10, 12, 0)), 0, "a new series is held to the limit too");
    assert!(store.meet_booking_by_uid(account, "another@google.com").is_none());
    attended(&h, &first).await;
    assert_eq!(meet::advance(store, utc(2030, 1, 15, 16, 20)), 0, "no room: the 16th waits");
    // Waiting, its last occurrence over for more than an hour: the sweep leaves the series its link all the same.
    meet::sweep(store, utc(2030, 1, 15, 18, 0));
    assert_eq!((series_row(&h, account).starts_at, series_row(&h, account).url.as_str()), (utc(2030, 1, 15, 16, 0), "https://meet.google.com/abc-defg-hij"));
    assert_eq!(store.meet_booking(&first).unwrap().url, "", "the occurrence's own is forgotten");
    store.set_meet_state("f0", "skipped", None, 2);
    assert_eq!(meet::advance(store, utc(2030, 1, 16, 12, 0)), 1);
    let sixteenth = listed(&h, account).into_iter().find(|b| b.starts_at == utc(2030, 1, 16, 16, 0)).unwrap();
    assert_eq!((sixteenth.state.as_str(), sixteenth.url.as_str()), ("booked", "https://meet.google.com/abc-defg-hij"));
}

#[tokio::test]
async fn a_v1_booking_of_one_occurrence_becomes_that_occurrence_s_when_the_series_is_booked_whole() {
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    // As v1 booked a series: its next occurrence, under the series' UID.
    let v1 = MeetBooking {
        id: "v1".into(),
        account,
        uid: UID.into(),
        url: "https://meet.google.com/abc-defg-hij".into(),
        title: Some("Roadmap review, Q4".into()),
        starts_at: utc(2030, 1, 15, 16, 0),
        ends_at: utc(2030, 1, 15, 16, 15),
        state: "booked".into(),
        detail: None,
        sequence: 0,
        series: None,
        kind: None,
    };
    h.accounts.store.insert_meet_booking(&v1, 1).unwrap();
    mailed(&h, account, &series("REQUEST", 1, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 1, 10, 12, 0));
    let all = listed(&h, account);
    assert_eq!(all.len(), 1);
    assert_eq!((all[0].id.as_str(), all[0].uid.clone()), ("v1", format!("{UID}#{}", utc(2030, 1, 15, 16, 0))));
    assert_eq!(series_row(&h, account).state, "series");
}

#[tokio::test]
async fn one_occurrence_of_a_series_mailed_alone_after_it_ended_books_nothing() {
    // Matt's stand-up: the organizer added Ghost to "this event" only, and Google mailed it once it was over.
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    let alone = only_changed("REQUEST", "20300115T110000", "20300115T110000", "20300115T111500", 0, "CONFIRMED");
    assert_eq!(mailed(&h, account, &alone, utc(2030, 1, 15, 17, 0)), 0);
    assert!(meetings(&h, &token).await.is_empty());
    // The same, still to come: booked as a meeting of its own.
    assert_eq!(mailed(&h, account, &alone, utc(2030, 1, 15, 15, 0)), 1);
    assert_eq!(listed(&h, account)[0].uid, format!("{UID}#{}", utc(2030, 1, 15, 16, 0)));
}

// --- recurring meetings on the device, and stopping one ------------------------------------------------------------
//
// Matt, 2026-10-24: "show recurring meetings in the meetings UI and paginate the meeting history".

/// DTSTART's wall-clock time as `Series` keeps it: seconds, as though UTC. 2030-01-15 is a Tuesday.
fn wall(y: i64, mo: i64, d: i64, h: i64, mi: i64) -> i64 {
    utc(y, mo, d, h, mi) / 1000
}

#[test]
fn a_rule_is_said_in_words_and_one_it_cannot_say_is_repeats() {
    let at = |rule: &str| meet::ics::rule_words(rule, wall(2030, 1, 15, 9, 30));
    let said = [
        ("FREQ=DAILY", "Daily at 9:30"),
        ("FREQ=DAILY;COUNT=5", "Daily at 9:30"),
        ("FREQ=DAILY;INTERVAL=3", "Every 3 days at 9:30"),
        ("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", "Every weekday at 9:30"),
        ("FREQ=DAILY;BYDAY=FR,MO,TU,WE,TH", "Every weekday at 9:30"),
        ("FREQ=WEEKLY;WKST=SU;BYDAY=MO,TU,WE,TH,FR;UNTIL=20300301T000000Z", "Every weekday at 9:30"),
        ("FREQ=WEEKLY;BYDAY=TH,TU", "Weekly on Tue and Thu at 9:30"),
        ("FREQ=WEEKLY;BYDAY=MO,WE,FR", "Weekly on Mon, Wed and Fri at 9:30"),
        ("FREQ=WEEKLY;BYDAY=SU,SA", "Weekly on Sat and Sun at 9:30"),
        ("FREQ=WEEKLY", "Weekly on Tue at 9:30"),
        ("FREQ=WEEKLY;BYDAY=SU,MO,TU,WE,TH,FR,SA", "Daily at 9:30"),
        ("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO", "Every 2 weeks on Mon at 9:30"),
        ("FREQ=WEEKLY;INTERVAL=2", "Every 2 weeks on Tue at 9:30"),
        ("FREQ=MONTHLY;BYDAY=2TU", "Monthly on the 2nd Tuesday at 9:30"),
        ("FREQ=MONTHLY;BYDAY=+1MO", "Monthly on the 1st Monday at 9:30"),
        ("FREQ=MONTHLY;BYDAY=-1FR", "Monthly on the last Friday at 9:30"),
        ("FREQ=MONTHLY;INTERVAL=3;BYDAY=3WE", "Every 3 months on the 3rd Wednesday at 9:30"),
        ("FREQ=MONTHLY", "Monthly on the 15th at 9:30"),
        ("FREQ=MONTHLY;BYMONTHDAY=15,1", "Monthly on the 1st and 15th at 9:30"),
        ("FREQ=MONTHLY;BYMONTHDAY=-1", "Monthly on the last day at 9:30"),
        ("FREQ=MONTHLY;BYMONTHDAY=11,21,22,23", "Monthly on the 11th, 21st, 22nd and 23rd at 9:30"),
        ("FREQ=YEARLY", "Yearly on 15 Jan at 9:30"),
        ("FREQ=YEARLY;BYMONTH=1", "Yearly on 15 Jan at 9:30"),
        ("FREQ=YEARLY;INTERVAL=2", "Every 2 years on 15 Jan at 9:30"),
    ];
    for (rule, words) in said {
        assert_eq!(at(rule), words, "{rule}");
    }
    // What it cannot say shortly, or a part that may move the time of day: "Repeats", with no time.
    for rule in [
        "FREQ=MONTHLY;BYSETPOS=-1;BYDAY=MO,TU",
        "FREQ=DAILY;BYHOUR=9,15",
        "FREQ=MONTHLY;BYDAY=TU",
        "FREQ=MONTHLY;BYDAY=-2FR",
        "FREQ=MONTHLY;BYDAY=1MO,3MO",
        "FREQ=MONTHLY;BYDAY=1MO;BYMONTHDAY=1",
        "FREQ=WEEKLY;BYDAY=1MO",
        "FREQ=DAILY;INTERVAL=2;BYDAY=MO,WE",
        "FREQ=YEARLY;BYMONTH=3",
        "FREQ=MONTHLY;BYMONTH=1,7",
        "FREQ=HOURLY",
        "FREQ=DAILY;INTERVAL=0",
        "FREQ=WEEKLY;BYDAY=XX",
        "",
    ] {
        assert_eq!(at(rule), "Repeats", "{rule}");
    }
    // Midnight and the evening, in the 24-hour clock.
    assert_eq!(meet::ics::rule_words("FREQ=DAILY", wall(2030, 1, 15, 0, 5)), "Daily at 0:05");
    assert_eq!(meet::ics::rule_words("FREQ=WEEKLY;BYDAY=TU,TH", wall(2030, 1, 15, 17, 45)), "Weekly on Tue and Thu at 17:45");
}

/// The account's series as its device lists them.
async fn listed_series(h: &Harness, token: &str) -> Vec<Value> {
    let (status, body) = h.call(Method::GET, "/api/v1/meet", Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["series"].as_array().unwrap().clone()
}

#[tokio::test]
async fn the_device_lists_each_running_series_with_its_rule_its_next_and_whether_ghost_joins_it() {
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    // 9:30 in New York on weekdays from Tuesday 2030-01-15; a weekly one that ends after six; a monthly one until July.
    mailed(&h, account, &series("REQUEST", 0, "20300115T093000", "20300115T100000", "CONFIRMED", "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR\r\n"), utc(2030, 1, 10, 12, 0));
    let weekly = series("REQUEST", 0, "20300117T110000", "20300117T120000", "CONFIRMED", "RRULE:FREQ=WEEKLY;BYDAY=TU,TH;COUNT=6\r\n").replace(UID, "weekly@google.com");
    mailed(&h, account, &weekly, utc(2030, 1, 10, 12, 0));
    let until = series("REQUEST", 0, "20300201T090000", "20300201T091500", "CONFIRMED", "RRULE:FREQ=MONTHLY;BYDAY=1FR;UNTIL=20300701T000000Z\r\n").replace(UID, "monthly@google.com");
    mailed(&h, account, &until, utc(2030, 1, 10, 12, 0));
    let own = series_row(&h, account);
    let first = h.accounts.store.meet_booking_by_uid(account, &format!("{UID}#{}", utc(2030, 1, 15, 14, 30))).unwrap();

    let listed = listed_series(&h, &token).await;
    assert_eq!(listed.len(), 3, "{listed:?}");
    assert_eq!(
        listed[0],
        json!({
            "id": own.id,
            "title": "Roadmap review, Q4",
            "kind": "meet",
            "rule": "Every weekday at 9:30",
            "time": "09:30",
            "zone": "America/New_York",
            "offset": -300,
            "next": { "id": first.id, "startsAt": utc(2030, 1, 15, 14, 30), "endsAt": utc(2030, 1, 15, 15, 0), "state": "booked", "joins": true },
            "until": null,
            "count": null,
        })
    );
    assert_eq!((listed[1]["rule"].as_str(), listed[1]["count"].as_i64(), listed[1]["next"]["startsAt"].as_i64()), (Some("Weekly on Tue and Thu at 11:00"), Some(6), Some(utc(2030, 1, 17, 16, 0))));
    assert_eq!((listed[2]["rule"].as_str(), listed[2]["until"].as_i64()), (Some("Monthly on the 1st Friday at 9:00"), Some(utc(2030, 7, 1, 0, 0))));
    // The occurrences in the list say which series they are of; a meeting of its own says nothing.
    join_now(&h, &token, "Ad hoc").await;
    let meetings = meetings(&h, &token).await;
    let of = |id: &str| meetings.iter().find(|m| m["id"] == id).unwrap().clone();
    assert_eq!(of(&first.id)["series"], json!(own.id));
    assert!(meetings.iter().any(|m| m["title"] == "Ad hoc" && m.get("series").is_none()));

    // The next skipped: still the next, and Ghost will not join it; the one after is booked already.
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/meet/{}", first.id), Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let next = &listed_series(&h, &token).await[0]["next"];
    assert_eq!((next["id"].as_str(), next["state"].as_str(), next["joins"].as_bool()), (Some(first.id.as_str()), Some("skipped"), Some(false)));

    // In summer New York is four hours behind: the offset is the next occurrence's.
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    mailed(&h, account, &series("REQUEST", 0, "20300716T093000", "20300716T100000", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 7, 10, 12, 0));
    let summer = &listed_series(&h, &token).await[0];
    assert_eq!((summer["rule"].as_str(), summer["offset"].as_i64()), (Some("Daily at 9:30"), Some(-240)));
    // A UTC series has no zone to name, and is said in UTC.
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    let utc_series = "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:utc@google.com\r\nDTSTART:20300115T150000Z\r\nDTEND:20300115T160000Z\r\nRRULE:FREQ=WEEKLY\r\nSUMMARY:Sync\r\nX-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
    mailed(&h, account, utc_series, utc(2030, 1, 10, 12, 0));
    let plain = &listed_series(&h, &token).await[0];
    assert_eq!((plain["rule"].as_str(), plain["zone"].clone(), plain["offset"].as_i64()), (Some("Weekly on Tue at 15:00"), Value::Null, Some(0)));
}

#[tokio::test]
async fn stopping_a_series_calls_off_what_is_to_come_has_ghost_leave_the_one_it_is_in_and_keeps_the_past() {
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    // Daily at 11:00 New York (16:00 UTC), the 18th moved to 14:00 in the same invite, booked on its own.
    let daily = with_changed(&series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), "20300118T110000", "20300118T140000", "20300118T141500", 1, "CONFIRMED");
    mailed(&h, account, &daily, utc(2030, 1, 10, 12, 0));
    // Day one: joined, recorded, done.
    let one = due_at(&h, utc(2030, 1, 15, 15, 59))[0].id.clone();
    for state in ["joining", "in_call"] {
        bot_call(&h, Method::POST, &format!("/api/internal/meet/{one}/state"), Some(json!({ "state": state }))).await;
    }
    let (status, _, _) = h.send(take_upload(&one, &[("audio", Some("audio/webm"), b"day one")])).await;
    assert_eq!(status, StatusCode::OK);
    // Day two: Ghost is in it.
    let two = due_at(&h, utc(2030, 1, 16, 15, 59))[0].id.clone();
    for state in ["joining", "in_call"] {
        bot_call(&h, Method::POST, &format!("/api/internal/meet/{two}/state"), Some(json!({ "state": state }))).await;
    }
    let moved = h.accounts.store.meet_booking_by_uid(account, &format!("{UID}#{}", utc(2030, 1, 18, 16, 0))).unwrap();
    let own = series_row(&h, account);

    // Another account's, an occurrence's id, or no id at all: no series by that id.
    let (other, _) = with_key(&h, "ali").await;
    for (who, id) in [(other.as_str(), own.id.as_str()), (token.as_str(), two.as_str()), (token.as_str(), "not%20an%20id")] {
        let (status, _) = h.call(Method::DELETE, &format!("/api/v1/meet/series/{id}"), Some(who), None).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{id}");
    }
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/meet/series/{}", own.id), None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert!(!h.accounts.store.meet_stopped(&own.id), "nothing was stopped by those");
    assert_eq!(h.accounts.store.meet_booking(&two).unwrap().state, "in_call");

    let (status, body) = h.call(Method::DELETE, &format!("/api/v1/meet/series/{}", own.id), Some(&token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["series"], json!({ "id": own.id, "stopped": true }));
    let changed: Vec<(String, String)> = body["meetings"].as_array().unwrap().iter().map(|m| (m["id"].as_str().unwrap().to_string(), m["state"].as_str().unwrap().to_string())).collect();
    assert_eq!(changed, vec![(two.clone(), "leave".to_string()), (moved.id.clone(), "cancelled".to_string())]);
    // The bot hears it is to leave, and may not join again; the moved 18th is called off; day one and its take stay.
    assert_eq!(due_at(&h, utc(2030, 1, 16, 16, 5)).iter().map(|b| (b.id.clone(), b.state.clone())).collect::<Vec<_>>(), vec![(two.clone(), "leave".to_string())]);
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/meet/{two}/state"), Some(json!({ "state": "in_call" }))).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let eighteenth = h.accounts.store.meet_booking(&moved.id).unwrap();
    assert_eq!((eighteenth.state.as_str(), eighteenth.detail.as_deref()), ("cancelled", Some("You asked Ghost to stop joining this meeting.")));
    assert_eq!(h.accounts.store.meet_booking(&one).unwrap().state, "done");
    let (_, takes) = h.call(Method::GET, "/api/v1/meet/takes", Some(&token), None).await;
    assert_eq!(takes["takes"][0]["meeting"].as_str(), Some(one.as_str()));
    // The series is no longer listed, and its row has no title or link; it is kept, stopped.
    assert!(listed_series(&h, &token).await.is_empty());
    let stopped = series_row(&h, account);
    assert_eq!((stopped.title, stopped.url.as_str(), stopped.state.as_str()), (None, "", "series"));
    assert!(h.accounts.store.meet_stopped(&own.id));
    // Asked again: the same answer, nothing more changed.
    let (status, again) = h.call(Method::DELETE, &format!("/api/v1/meet/series/{}", own.id), Some(&token), None).await;
    assert_eq!((status, again["meetings"].as_array().map(Vec::len)), (StatusCode::OK, Some(0)));

    // Day two's take, recorded until Ghost left, is kept as any.
    let (status, _, _) = h.send(take_upload(&two, &[("audio", Some("audio/webm"), b"day two")])).await;
    assert_eq!(status, StatusCode::OK);
    // And nothing is booked after: the days pass, the stopped row moves along its rule, and the sweep keeps it.
    let before = listed(&h, account).len();
    for day in 17..=22 {
        assert!(due_at(&h, utc(2030, 1, day, 15, 59)).is_empty(), "the {day}th");
    }
    assert_eq!(listed(&h, account).len(), before);
    assert_eq!(series_row(&h, account).starts_at, utc(2030, 1, 22, 16, 0), "moved along, booking nothing");
    meet::sweep(&h.accounts.store, utc(2030, 3, 1, 12, 0));
    assert!(h.accounts.store.meet_stopped(&own.id), "kept while the rule runs, a month on and more");
    assert!(h.accounts.store.meet_booking(&one).is_none(), "the occurrences are forgotten as any meeting");

    // Stopped at a given time: an occurrence already over is left as it was, though it never got its bot.
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    mailed(&h, account, &series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 1, 10, 12, 0));
    let missed = listed(&h, account)[0].clone();
    let changed = meet::stop(&h.accounts.store, &series_row(&h, account), utc(2030, 1, 15, 17, 0));
    assert!(changed.is_empty());
    assert_eq!(h.accounts.store.meet_booking(&missed.id).unwrap().state, "booked", "over: the sweep's to mark, not the stop's");
}

#[tokio::test]
async fn a_stopped_series_is_not_booked_again_by_an_update_but_a_new_invite_is() {
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    mailed(&h, account, &series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n"), utc(2030, 1, 10, 12, 0));
    let own = series_row(&h, account);
    let first = listed(&h, account)[0].clone();
    meet::stop(&h.accounts.store, &own, utc(2030, 1, 11, 12, 0));
    assert_eq!(h.accounts.store.meet_booking(&first.id).unwrap().state, "cancelled");

    // The organizer moves it, with a new link and a higher SEQUENCE: nothing is booked, linked or named.
    let moved = series("REQUEST", 1, "20300115T093000", "20300115T094500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n").replace("abc-defg-hij", "xyz-wxyz-xyz");
    assert_eq!(mailed(&h, account, &moved, utc(2030, 1, 12, 12, 0)), 0);
    let row = series_row(&h, account);
    assert_eq!((row.title, row.url.as_str(), row.sequence), (None, "", 1));
    assert!(h.accounts.store.meet_stopped(&own.id));
    assert_eq!(listed(&h, account).iter().map(|b| (b.id.clone(), b.state.clone())).collect::<Vec<_>>(), vec![(first.id.clone(), "cancelled".to_string())]);
    // Nor by one occurrence changed on its own, nor the called-off first invited again by itself.
    let changed = with_changed(&moved.replace("SEQUENCE:1", "SEQUENCE:2"), "20300117T093000", "20300117T120000", "20300117T121500", 2, "CONFIRMED");
    assert_eq!(mailed(&h, account, &changed, utc(2030, 1, 12, 13, 0)), 0);
    assert_eq!(mailed(&h, account, &only_changed("REQUEST", "20300115T110000", "20300115T110000", "20300115T111500", 3, "CONFIRMED"), utc(2030, 1, 12, 14, 0)), 0);
    assert_eq!(listed(&h, account).len(), 1);
    assert_eq!(h.accounts.store.meet_booking(&first.id).unwrap().state, "cancelled");
    for day in 15..=18 {
        assert!(due_at(&h, utc(2030, 1, day, 14, 29)).is_empty(), "the {day}th");
    }
    assert!(listed_series(&h, &token).await.is_empty());
    // The update's rule is the one the row is moved along and ended by: COUNT ends it.
    let ended = series("REQUEST", 4, "20300115T093000", "20300115T094500", "CONFIRMED", "RRULE:FREQ=DAILY;COUNT=2\r\n");
    mailed(&h, account, &ended, utc(2030, 1, 20, 12, 0));
    assert_eq!(series_row(&h, account).state, "done");

    // Called off and invited again as a new event, a new UID: a new series, booked.
    let again = series("REQUEST", 0, "20300201T110000", "20300201T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n").replace(UID, "again@google.com");
    assert_eq!(mailed(&h, account, &again, utc(2030, 1, 25, 12, 0)), 1);
    let listed_now = listed_series(&h, &token).await;
    assert_eq!((listed_now.len(), listed_now[0]["next"]["state"].as_str()), (1, Some("booked")));
}

// --- the history, in pages ------------------------------------------------------------------------------------------

/// The real now, in ms: the device's list reads at it.
fn real_now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as i64
}

/// A booking of `account`'s put straight into the store, ending at `ends_at`.
fn booking(h: &Harness, account: i64, id: &str, ends_at: i64, state: &str, title: Option<&str>) {
    let b = MeetBooking {
        id: id.into(),
        account,
        uid: format!("uid-{id}"),
        url: String::new(),
        title: title.map(str::to_string),
        starts_at: ends_at - 1_800_000,
        ends_at,
        state: state.into(),
        detail: None,
        sequence: 0,
        series: None,
        kind: None,
    };
    assert!(h.accounts.store.insert_meet_booking(&b, 1).unwrap());
}

/// One page as the device asks for it: its meetings' ids, its `next`, and the whole answer.
async fn page(h: &Harness, token: &str, query: &str) -> (Vec<String>, Option<String>, Value) {
    let (status, body) = h.call(Method::GET, &format!("/api/v1/meet{query}"), Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{query}: {body}");
    let ids = body["meetings"].as_array().unwrap().iter().map(|m| m["id"].as_str().unwrap().to_string()).collect();
    (ids, body["next"].as_str().map(str::to_string), body)
}

#[tokio::test]
async fn the_history_comes_in_pages_upcoming_first_then_the_latest_over_with_a_cursor_that_holds_under_ties() {
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    let now = real_now();
    let hour = 3_600_000;
    // Two to come; forty-five over, from eleven hours ago back over three weeks, five of them ending at the same
    // moment across where the first page ends, and one the sweep has blanked.
    booking(&h, account, "up2", now + 5 * hour, "booked", Some("Later"));
    booking(&h, account, "up1", now + hour, "booked", Some("Sooner"));
    let mut past: Vec<(i64, String)> = Vec::new();
    for n in 0..45 {
        let ends = if (18..23).contains(&n) { now - 19 * 11 * hour } else { now - (n + 1) * 11 * hour };
        let id = format!("p{n:02}");
        booking(&h, account, &id, ends, if n % 7 == 0 { "failed" } else { "done" }, if n == 3 { None } else { Some("Retro") });
        past.push((ends, id));
    }
    // The order a page keeps: the latest ended first, and by id, the larger first, where two ended together.
    past.sort_by(|a, b| b.cmp(a));
    let order: Vec<String> = past.iter().map(|(_, id)| id.clone()).collect();

    let (first, next, body) = page(&h, &token, "?limit=20").await;
    assert_eq!(first[..2], ["up1".to_string(), "up2".to_string()], "every one to come, soonest first");
    assert_eq!(first[2..], order[..20]);
    assert!(body["series"].is_array());
    let blanked = body["meetings"].as_array().unwrap().iter().find(|m| m["id"] == "p03").unwrap();
    assert_eq!((blanked["title"].clone(), blanked["url"].clone()), (Value::Null, Value::Null), "the device says 'A meeting'");
    let next = next.expect("more to come");
    assert_eq!(next, format!("{}:{}", past[19].0, past[19].1));
    assert!(past[19].0 == past[20].0, "the first page ends inside the tie");

    // A meeting ending meanwhile, newer than the first page's end, does not move the next page.
    booking(&h, account, "fresh", now - 60_000, "done", Some("Just now"));
    let (second, next2, body2) = page(&h, &token, &format!("?limit=20&before={next}")).await;
    assert_eq!(second, order[20..40]);
    assert!(body2.get("series").is_none(), "the series come with the first page");
    let (third, last, body3) = page(&h, &token, &format!("?before={}", next2.unwrap())).await;
    assert_eq!(third, order[40..], "a page is twenty unless asked otherwise");
    assert_eq!((last, body3["next"].clone()), (None, Value::Null), "the last page has no next");
    // No meeting twice, none dropped, across the tie at the page's end.
    let mut all: Vec<String> = [&first[2..], &second[..], &third[..]].concat();
    assert_eq!(all.len(), 45);
    all.sort();
    all.dedup();
    assert_eq!(all.len(), 45);

    // The same cursor read again answers the same page.
    assert_eq!(page(&h, &token, &format!("?limit=20&before={next}")).await.0, second);
    // A page of one, and a limit past the most is the most.
    let (one, after_one, _) = page(&h, &token, "?limit=1").await;
    assert_eq!((one.len(), one[2..].to_vec()), (3, vec!["fresh".to_string()]));
    assert!(after_one.is_some());
    let (big, none_after, _) = page(&h, &token, "?limit=1000").await;
    assert_eq!((big.len(), none_after), (2 + 46, None));
    for bad in ["?limit=lots", "?before=yesterday", "?before=12:not%20an%20id", "?before=:abc"] {
        let (status, _) = h.call(Method::GET, &format!("/api/v1/meet{bad}"), Some(&token), None).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{bad}");
    }
    // Another account's history is its own.
    let (other, _) = with_key(&h, "ali").await;
    assert!(page(&h, &other, "?limit=20").await.0.is_empty());
    assert!(page(&h, &other, &format!("?before={next}")).await.0.is_empty());
}

#[tokio::test]
async fn asked_with_no_page_the_list_is_what_it_always_was_with_next_for_the_older_ones() {
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    let now = real_now();
    let day = 24 * 3_600_000;
    booking(&h, account, "soon", now + day, "booked", Some("Soon"));
    booking(&h, account, "week", now - 2 * day, "done", Some("This week"));
    booking(&h, account, "old1", now - 9 * day, "done", Some("Older"));
    booking(&h, account, "old2", now - 20 * day, "done", Some("Older still"));
    let (ids, next, body) = page(&h, &token, "").await;
    // Still to come and the last seven days', soonest first, as an app from before pages reads it.
    assert_eq!(ids, vec!["week".to_string(), "soon".to_string()]);
    assert_eq!(body["meetings"][0], json!({ "id": "week", "title": "This week", "url": null, "kind": null, "startsAt": now - 2 * day - 1_800_000, "endsAt": now - 2 * day, "state": "done", "detail": null }));
    assert_eq!(body["series"], json!([]));
    // And where the older ones go on from: those past the seven days, the latest first.
    let next = next.expect("older ones are kept");
    assert!(next.ends_with(':'), "{next}");
    let (older, after, _) = page(&h, &token, &format!("?before={next}")).await;
    assert_eq!((older, after), (vec!["old1".to_string(), "old2".to_string()], None));
    // With nothing older than the seven days, no next.
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    booking(&h, account, "week", real_now() - 2 * day, "done", None);
    let (_, next, body) = page(&h, &token, "").await;
    assert_eq!((next, body["next"].clone()), (None, Value::Null));
}

// --- the devices told (live.rs, POKES) -----------------------------------------------------------

#[tokio::test]
async fn a_take_kept_pokes_its_account_s_devices_and_no_one_else_s() {
    let h = Harness::new("meet");
    let (token, account) = sam(&h).await;
    let (stranger, _) = with_key(&h, "ali").await;
    let ali = h.accounts.claims(&stranger).unwrap().sub;
    let mut phone = h.accounts.pokes.attach_for_test(account, 1);
    let mut mac = h.accounts.pokes.attach_for_test(account, 2);
    let mut other = h.accounts.pokes.attach_for_test(ali, 3);
    // Booked from a device: its devices' lists hear of it.
    let id = join_now(&h, &token, "Budget").await;
    assert_eq!(heard_pokes(&mut phone), vec!["meet"]);
    assert_eq!(heard_pokes(&mut mac), vec!["meet"]);
    // Kept: a take to fetch, a kind of its own and so not held back by the gap the booking began.
    let (status, _, _) = h.send(take_upload(&id, &[("audio", Some("audio/webm"), b"sound")])).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(heard_pokes(&mut phone), vec!["take"]);
    assert_eq!(heard_pokes(&mut mac), vec!["take"]);
    assert!(heard_pokes(&mut other).is_empty(), "another account hears nothing of it");
    // A take refused (the meeting skipped) is kept by nobody, and nobody is told of one.
    let skipped = join_now(&h, &stranger, "Not this").await;
    h.call(Method::DELETE, &format!("/api/v1/meet/{skipped}"), Some(&stranger), None).await;
    heard_pokes(&mut other);
    let (status, _, _) = h.send(take_upload(&skipped, &[("audio", Some("audio/webm"), b"sound")])).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert!(heard_pokes(&mut other).is_empty());
}

#[tokio::test]
async fn an_invite_the_bot_and_a_series_moving_on_each_poke_the_meetings_list() {
    let h = Harness::new("meet");
    let (token_sam, account) = sam(&h).await;
    let address = turned_on(&h, &token_sam).await;
    let mut phone = h.accounts.pokes.attach_for_test(account, 1);
    // The invite mailed: a booking, and a mail, each its own word.
    let invite = google_invite("REQUEST", 0, "20300115T110000", "20300115T120000", "CONFIRMED");
    let (status, _, _) = h.send(post(&address, invite_mail(&address, &invite).as_bytes(), &token(1))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(heard_pokes(&mut phone), vec!["meet", "mail"]);
    // The bot moving it on is said once the gap is over: the poke the invite began holds the next one back, and one
    // is said at the gap's end however many came in it.
    let id = meetings(&h, &token_sam).await[0]["id"].as_str().unwrap().to_string();
    attended(&h, &id).await;
    assert!(heard_pokes(&mut phone).is_empty(), "held for the gap");
    let gap = std::time::Duration::from_millis(crate::live::POKE_GAP_MS.load(std::sync::atomic::Ordering::Relaxed));
    let mut later = Vec::new();
    for _ in 0..(gap.as_millis() / 10 * 3) {
        later.extend(heard_pokes(&mut phone));
        if !later.is_empty() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    assert_eq!(later, vec!["meet"], "the bot's three states are one word at the end of the gap");

    // A series' next occurrence booked by `advance`, with no mail: its account is told, once however many it books.
    let other = Harness::new("meet");
    let (_, sam_there) = sam(&other).await;
    let mut there = other.accounts.pokes.attach_for_test(sam_there, 1);
    let daily = series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n");
    assert_eq!(mailed(&other, sam_there, &daily, utc(2030, 1, 10, 12, 0)), 1);
    let first = due_at(&other, utc(2030, 1, 15, 15, 59));
    other.accounts.store.set_meet_state(&first[0].id, "done", None, utc(2030, 1, 15, 16, 16) / 1000);
    assert_eq!(meet::advance_poking(&other.accounts, utc(2030, 1, 15, 16, 16)), 1);
    assert_eq!(heard_pokes(&mut there), vec!["meet"]);
    // Nothing more to book: nothing said.
    assert_eq!(meet::advance_poking(&other.accounts, utc(2030, 1, 15, 16, 17)), 0);
    assert!(heard_pokes(&mut there).is_empty());
}

// --- the two plugins: which kinds the account wants (meet.rs, "TWO PLUGINS, ONE ADDRESS") ----------------------------

/// The account's kinds, as a device reads them.
async fn kinds(h: &Harness, token: &str) -> Value {
    let (status, body) = h.call(Method::GET, "/api/v1/meet/kinds", Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body
}

/// The kinds set as a device sets them when a plugin's switch moves.
async fn set_kinds(h: &Harness, token: &str, body: Value) -> (StatusCode, Value) {
    h.call(Method::PUT, "/api/v1/meet/kinds", Some(token), Some(body)).await
}

/// A sealed mail of the account's, opened with its key: the note's head.
async fn opened_mail(h: &Harness, token: &str, secret: &p256::SecretKey, id: &str) -> Value {
    let (_, sealed) = h.call(Method::GET, &format!("/api/v1/mail/{id}"), Some(token), None).await;
    crate::mail::message::read(&seal::open_with(secret, id, sealed["wrapped"].as_str().unwrap(), sealed["blob"].as_str().unwrap()).unwrap()).0
}

#[tokio::test]
async fn the_kinds_start_on_are_kept_per_account_and_refuse_what_is_not_a_kind() {
    let h = Harness::new("meet");
    let (sam, _) = with_key(&h, "sam").await;
    assert_eq!(kinds(&h, &sam).await, json!({ "meet": true, "zoom": true }), "every kind on until a device says otherwise");
    assert_eq!(set_kinds(&h, &sam, json!({ "zoom": false })).await, (StatusCode::OK, json!({ "meet": true, "zoom": false })), "a kind not named stays");
    assert_eq!(kinds(&h, &sam).await, json!({ "meet": true, "zoom": false }));
    assert_eq!(set_kinds(&h, &sam, json!({ "meet": false, "zoom": true })).await.1, json!({ "meet": false, "zoom": true }));
    for bad in [json!({ "teams": true }), json!({ "zoom": "off" }), json!({ "meet": null })] {
        assert_eq!(set_kinds(&h, &sam, bad.clone()).await, (StatusCode::BAD_REQUEST, json!({ "error": "Each kind is meet or zoom, true or false." })), "{bad}");
    }
    assert_eq!(kinds(&h, &sam).await, json!({ "meet": false, "zoom": true }), "a refused body changes nothing");
    // Another account's are its own.
    let (ali, _) = with_key(&h, "ali").await;
    assert_eq!(kinds(&h, &ali).await, json!({ "meet": true, "zoom": true }));
    let (status, _) = h.call(Method::GET, "/api/v1/meet/kinds", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn join_now_with_a_link_of_a_kind_turned_off_is_refused_saying_which_plugin_to_turn_on() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    set_kinds(&h, &account, json!({ "zoom": false })).await;
    let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(&account), Some(json!({ "url": ZOOM_LINK }))).await;
    assert_eq!((status, body), (StatusCode::BAD_REQUEST, json!({ "error": "Turn on the Zoom plugin to send Ghost to Zoom calls." })));
    // Google Meet is on, and books as ever.
    join_now(&h, &account, "Stand-up").await;
    set_kinds(&h, &account, json!({ "meet": false, "zoom": true })).await;
    let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(&account), Some(json!({ "url": "https://meet.google.com/abc-defg-hij" }))).await;
    assert_eq!((status, body), (StatusCode::BAD_REQUEST, json!({ "error": "Turn on the Google Meet plugin to send Ghost to Google Meet calls." })));
    join_now_url(&h, &account, ZOOM_LINK).await;
}

#[tokio::test]
async fn an_invite_of_a_kind_turned_off_books_nothing_and_its_note_says_so() {
    let h = Harness::new("meet");
    let (account, secret) = with_key(&h, "sam").await;
    let address = turned_on(&h, &account).await;
    set_kinds(&h, &account, json!({ "zoom": false })).await;
    let zoom = zoom_invite("20300115T100000", "20300115T110000");
    let (status, _, bytes) = h.send(post(&address, invite_mail(&address, &zoom).as_bytes(), &token(1))).await;
    assert_eq!(status, StatusCode::OK, "{}", String::from_utf8_lossy(&bytes));
    assert!(meetings(&h, &account).await.is_empty(), "nothing booked of the Zoom");
    // The mail is a note all the same, and the note says why Ghost is not coming.
    let (_, mail) = h.call(Method::GET, "/api/v1/mail", Some(&account), None).await;
    let id = mail["mail"][0]["id"].as_str().unwrap().to_string();
    let head = opened_mail(&h, &account, &secret, &id).await;
    assert!(head["body"].as_str().unwrap().ends_with("\n\nGhost wasn't booked: the Zoom plugin is off. Turn it on in Ghost.md to have Ghost join."), "{}", head["body"]);
    // A Meet invite in the same account books as ever, and its note says nothing of plugins.
    let meet = google_invite("REQUEST", 0, "20300116T110000", "20300116T120000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &meet).as_bytes(), &token(2))).await;
    let listed = meetings(&h, &account).await;
    assert_eq!(listed.iter().map(|m| m["kind"].as_str()).collect::<Vec<_>>(), vec![Some("meet")]);
    let (_, mail) = h.call(Method::GET, "/api/v1/mail", Some(&account), None).await;
    let other = mail["mail"].as_array().unwrap().iter().map(|m| m["id"].as_str().unwrap().to_string()).find(|m| *m != id).unwrap();
    assert!(!opened_mail(&h, &account, &secret, &other).await["body"].as_str().unwrap().contains("plugin"));
    // An update moving that Meet onto Zoom, while Zoom is off, moves it and skips it: Ghost goes to neither link.
    let onto_zoom = google_zoom_invite("REQUEST", 1, "20300116T110000", "20300116T120000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &onto_zoom).as_bytes(), &token(3))).await;
    let moved = &meetings(&h, &account).await[0];
    assert_eq!((moved["state"].as_str(), moved["detail"].as_str(), moved["kind"].as_str()), (Some("skipped"), Some("The Zoom plugin is off."), Some("zoom")));
    // A cancellation is applied whatever the kind, and turning Zoom on after it books nothing again.
    let cancel = google_zoom_invite("CANCEL", 2, "20300116T110000", "20300116T120000", "CANCELLED");
    h.send(post(&address, invite_mail(&address, &cancel).as_bytes(), &token(4))).await;
    set_kinds(&h, &account, json!({ "zoom": true })).await;
    let gone = &meetings(&h, &account).await[0];
    assert_eq!((gone["state"].as_str(), gone["detail"].as_str()), (Some("cancelled"), Some("The organizer called it off.")));
}

#[tokio::test]
async fn turning_a_kind_off_skips_what_is_booked_of_it_and_turning_it_on_books_it_again() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &account).await;
    h.send(post(&address, invite_mail(&address, &zoom_invite("20300115T100000", "20300115T110000")).as_bytes(), &token(1))).await;
    h.send(post(&address, invite_mail(&address, &google_invite("REQUEST", 0, "20300116T110000", "20300116T120000", "CONFIRMED")).as_bytes(), &token(2))).await;
    let state = |list: &[Value], kind: &str| list.iter().find(|m| m["kind"] == kind).map(|m| (m["state"].as_str().unwrap().to_string(), m["detail"].as_str().map(str::to_string))).unwrap();
    // Ghost is in a Zoom right now, too.
    let now = join_now_url(&h, &account, "zoom.us/my/sam.lee").await;
    bot_call(&h, Method::POST, &format!("/api/internal/meet/{now}/state"), Some(json!({ "state": "in_call" }))).await;

    set_kinds(&h, &account, json!({ "zoom": false })).await;
    let listed = meetings(&h, &account).await;
    let invited = listed.iter().find(|m| m["title"] == "Design sync").unwrap();
    assert_eq!((invited["state"].as_str(), invited["detail"].as_str()), (Some("skipped"), Some("The Zoom plugin is off.")));
    let in_it = listed.iter().find(|m| m["id"] == now.as_str()).unwrap();
    assert_eq!((in_it["state"].as_str(), in_it["detail"].as_str()), (Some("leave"), Some("The Zoom plugin is off.")), "the bot reads leave and goes");
    assert_eq!(state(&listed, "meet"), ("booked".to_string(), None), "the Meet is untouched");
    let (_, due) = bot_call(&h, Method::GET, "/api/internal/meet/due", None).await;
    assert!(due["meetings"].as_array().unwrap().iter().all(|m| m["title"] != "Design sync"));

    // A skip of the person's own is not undone by the switch.
    let meet_id = listed.iter().find(|m| m["kind"] == "meet").unwrap()["id"].as_str().unwrap().to_string();
    h.call(Method::DELETE, &format!("/api/v1/meet/{meet_id}"), Some(&account), None).await;
    set_kinds(&h, &account, json!({ "meet": false })).await;
    set_kinds(&h, &account, json!({ "meet": true, "zoom": true })).await;
    let listed = meetings(&h, &account).await;
    let invited = listed.iter().find(|m| m["title"] == "Design sync").unwrap();
    assert_eq!((invited["state"].as_str(), invited["detail"].as_str()), (Some("booked"), None), "booked again, still to come");
    assert_eq!(listed.iter().find(|m| m["id"] == now.as_str()).unwrap()["state"], "leave", "Ghost left that one, and it stays left");
    assert_eq!(state(&listed, "meet"), ("skipped".to_string(), Some("You asked Ghost not to be in it.".to_string())));
}

#[tokio::test]
async fn a_series_of_a_kind_turned_off_books_no_next_occurrence_until_it_is_on_again() {
    let h = Harness::new("meet");
    let (_, account) = sam(&h).await;
    let daily = series("REQUEST", 0, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n");
    assert_eq!(mailed(&h, account, &daily, utc(2030, 1, 10, 12, 0)), 1);
    meet::set_kinds(&h.accounts.store, account, &[("meet", false)], utc(2030, 1, 10, 12, 5)).unwrap();
    assert_eq!(listed(&h, account).iter().map(|b| b.state.as_str()).collect::<Vec<_>>(), vec!["skipped"]);
    // Day one passes; no day two is booked while Google Meet is off.
    assert!(due_at(&h, utc(2030, 1, 15, 16, 0)).is_empty());
    assert_eq!(meet::advance(&h.accounts.store, utc(2030, 1, 15, 17, 0)), 0);
    assert_eq!(listed(&h, account).len(), 1);
    // Nor does an invite update book it.
    let again = series("REQUEST", 1, "20300115T110000", "20300115T111500", "CONFIRMED", "RRULE:FREQ=DAILY\r\n");
    assert_eq!(mailed(&h, account, &again, utc(2030, 1, 15, 17, 5)), 0);
    meet::set_kinds(&h.accounts.store, account, &[("meet", true)], utc(2030, 1, 15, 17, 10)).unwrap();
    assert_eq!(meet::advance(&h.accounts.store, utc(2030, 1, 15, 17, 15)), 1, "on again: the next one booked");
    let all = listed(&h, account);
    assert_eq!(all.iter().map(|b| (b.starts_at, b.state.as_str())).collect::<Vec<_>>(), vec![(utc(2030, 1, 15, 16, 0), "skipped"), (utc(2030, 1, 16, 16, 0), "booked")]);
}

#[tokio::test]
async fn a_meeting_keeps_its_kind_once_the_sweep_has_blanked_its_link() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &account).await;
    h.send(post(&address, invite_mail(&address, &zoom_invite("20300115T100000", "20300115T110000")).as_bytes(), &token(1))).await;
    meet::sweep(&h.accounts.store, utc(2030, 1, 15, 21, 0));
    let listed = h.accounts.store.meet_bookings(h.accounts.store.account_by_handle("sam").unwrap().id, i64::MIN);
    assert_eq!((listed[0].url.as_str(), listed[0].kind.as_deref()), ("", Some("zoom")));
    let (_, body) = h.call(Method::GET, "/api/v1/meet?limit=20", Some(&account), None).await;
    assert_eq!((body["meetings"][0]["url"].clone(), body["meetings"][0]["kind"].as_str()), (Value::Null, Some("zoom")));
}
