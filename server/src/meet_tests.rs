//! Ghost in a Google Meet, through the routes the mail provider, a device and the bot call (docs/MEET.md): an invite
//! mailed to the account's address booked, moved and called off; "join now", the list and a skip; the bot's routes
//! answered on this machine only and with its token; a recording sealed on arrival, kept only sealed and opened with
//! the account's private key alone; and the sweep forgetting a meeting's title and link once it is over.

use crate::mail::seal;
use crate::mail_tests::{post, token, turned_on, with_key};
use crate::meet::ics::tests::{google_invite, utc};
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
fn invite_mail(to: &str, ics: &str) -> String {
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
        json!({ "id": id, "title": "Roadmap review, Q4", "url": "https://meet.google.com/abc-defg-hij", "startsAt": utc(2030, 1, 15, 16, 0), "endsAt": utc(2030, 1, 15, 17, 0), "state": "booked", "detail": null })
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
async fn an_invite_without_a_meet_link_or_already_over_books_nothing() {
    let h = Harness::new("meet");
    let (account, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &account).await;
    let zoom = google_invite("REQUEST", 0, "20300115T110000", "20300115T120000", "CONFIRMED").replace("https://meet.google.com/abc-defg-hij", "https://zoom.us/j/123456789");
    h.send(post(&address, invite_mail(&address, &zoom).as_bytes(), &token(1))).await;
    let past = google_invite("REQUEST", 0, "20200115T110000", "20200115T120000", "CONFIRMED");
    h.send(post(&address, invite_mail(&address, &past).as_bytes(), &token(2))).await;
    assert!(meetings(&h, &account).await.is_empty());
    let (_, mail) = h.call(Method::GET, "/api/v1/mail", Some(&account), None).await;
    assert_eq!(mail["mail"].as_array().unwrap().len(), 2, "both are notes all the same");
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
