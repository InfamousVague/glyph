//! Ghost in a Google Meet, through the routes the mail provider, a device and the bot call (docs/MEET.md): an invite
//! mailed to the account's address booked, moved and called off; "join now", the list and a skip; the bot's routes
//! answered on this machine only and with its token; a recording sealed on arrival, kept only sealed and opened with
//! the account's private key alone; and the sweep forgetting a meeting's title and link once it is over.

use crate::mail::seal;
use crate::mail_tests::{post, token, turned_on, with_key};
use crate::meet::ics::tests::{google_invite, utc};
use crate::meet::{self, take_seal_context, take_wrap_context, unpack, TEST_BOT_TOKEN};
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
