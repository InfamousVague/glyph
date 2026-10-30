//! A meeting's live captions (docs/MEET.md, "Live captions"; meet/live.rs): the bot's batches sealed on arrival and passed
//! to the meeting's account's devices alone, kept sealed for a device's catch-up, refused past the limits or once Ghost
//! is not in the meeting, and over when the take comes or the meeting ends.

use crate::mail::seal;
use crate::mail_tests::with_key;
use crate::meet::live::{key_context, seal_context, GETS_PER_MINUTE, LINES_MOST, POST_BURST};
use crate::meet::TEST_BOT_TOKEN;
use crate::test_support::Harness;
use axum::body::Body;
use axum::extract::ws::Message;
use axum::http::{header, Method, Request, StatusCode};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde_json::{json, Value};
use tokio::sync::mpsc::Receiver;

/// Ghost booked into a Meet now and in it, as the bot says; the booking's id.
async fn in_call(h: &Harness, token: &str) -> String {
    let (status, body) = h.call(Method::POST, "/api/v1/meet", Some(token), Some(json!({ "url": "https://meet.google.com/abc-defg-hij", "title": "Launch sync" }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let id = body["meeting"]["id"].as_str().unwrap().to_string();
    for state in ["joining", "in_call"] {
        let (status, _) = bot(h, Method::POST, &format!("/api/internal/meet/{id}/state"), Some(json!({ "state": state }))).await;
        assert_eq!(status, StatusCode::OK);
    }
    id
}

/// A request as the bot makes one: loopback, its token.
async fn bot(h: &Harness, method: Method, path: &str, body: Option<Value>) -> (StatusCode, Value) {
    let mut request = Request::builder().method(method).uri(path).header(header::AUTHORIZATION, format!("Bearer {TEST_BOT_TOKEN}"));
    let body = match body {
        Some(body) => {
            request = request.header(header::CONTENT_TYPE, "application/json");
            Body::from(body.to_string())
        }
        None => Body::empty(),
    };
    let (status, _, bytes) = h.send(request.body(body).unwrap()).await;
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

async fn send_live(h: &Harness, id: &str, body: Value) -> StatusCode {
    bot(h, Method::POST, &format!("/api/internal/meet/{id}/live"), Some(body)).await.0
}

/// The frames a socket has been sent, other than pokes.
fn frames(socket: &mut Receiver<Message>) -> Vec<Value> {
    let mut out = Vec::new();
    while let Ok(frame) = socket.try_recv() {
        let Message::Text(text) = frame else { continue };
        let value: Value = serde_json::from_str(&text).unwrap();
        if value["t"] != "poke" {
            out.push(value);
        }
    }
    out
}

/// A frame opened as the device opens one: `n` its `seq`, or `p<partial>`.
fn opened(secret: &p256::SecretKey, meeting: &str, n: &str, frame: &Value) -> Result<Value, String> {
    let sealed = URL_SAFE_NO_PAD.decode(frame["data"].as_str().unwrap()).unwrap();
    let clear = seal::open_sealed_with(secret, frame["wrapped"].as_str().unwrap(), &key_context(meeting, n), &sealed, &seal_context(meeting, n))?;
    Ok(serde_json::from_slice(&clear).unwrap())
}

fn files_under(dir: &std::path::Path) -> Vec<u8> {
    let mut dirs = vec![dir.to_path_buf()];
    let mut seen = Vec::new();
    while let Some(dir) = dirs.pop() {
        for entry in std::fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                dirs.push(path);
            } else {
                seen.extend(std::fs::read(&path).unwrap());
            }
        }
    }
    seen
}

#[tokio::test]
async fn live_captions_are_sealed_on_arrival_passed_to_the_account_s_devices_alone_and_kept_for_its_catch_up() {
    let h = Harness::new("meet-live");
    let (token, secret) = with_key(&h, "sam").await;
    let (stranger, _) = with_key(&h, "ali").await;
    let account = h.accounts.claims(&token).unwrap().sub;
    let ali = h.accounts.claims(&stranger).unwrap().sub;
    let id = in_call(&h, &token).await;
    let mut phone = h.accounts.pokes.attach_for_test(account, 1);
    let mut mac = h.accounts.pokes.attach_for_test(account, 2);
    let mut other = h.accounts.pokes.attach_for_test(ali, 3);

    let batch = json!({
        "startedAt": 1_792_159_500_000i64,
        "lines": [{ "at": 4000, "speaker": "Sam Lee", "text": "PRIVATE-LIVE-MARKER good morning everyone" }, { "at": 15000, "speaker": "Daniel", "text": "The pricing page is drafted." }],
        "partial": { "at": 21000, "speaker": "Sam Lee", "text": "and the launch" },
    });
    assert_eq!(send_live(&h, &id, batch).await, StatusCode::NO_CONTENT);
    let heard = frames(&mut phone);
    assert_eq!(heard.len(), 1, "{heard:?}");
    let frame = &heard[0];
    assert_eq!((frame["t"].as_str(), frame["meeting"].as_str(), frame["seq"].as_u64()), (Some("captions"), Some(id.as_str()), Some(1)));
    assert!(!frame.to_string().contains("PRIVATE-LIVE-MARKER") && !frame.to_string().contains("Daniel"), "sealed: {frame}");
    let words = opened(&secret, &id, "1", frame).unwrap();
    assert_eq!(words["v"], 1);
    assert_eq!(words["meeting"], id.as_str());
    assert_eq!(words["startedAt"], 1_792_159_500_000i64);
    assert_eq!(words["lines"], json!([{ "at": 4000, "speaker": "Sam Lee", "text": "PRIVATE-LIVE-MARKER good morning everyone" }, { "at": 15000, "speaker": "Daniel", "text": "The pricing page is drafted." }]));
    assert_eq!(words["partial"], json!({ "at": 21000, "speaker": "Sam Lee", "text": "and the launch" }));
    assert_eq!(frames(&mut mac).len(), 1, "every device of the account");
    assert!(frames(&mut other).is_empty(), "another account hears nothing of it");
    // Moved to another place in the meeting, or to another meeting, it opens nothing; nor with another key.
    assert!(opened(&secret, &id, "2", frame).is_err());
    assert!(opened(&secret, "another", "1", frame).is_err());
    let (stranger_secret, _) = seal::tests::account_pair();
    assert!(opened(&stranger_secret, &id, "1", frame).is_err());

    // The line being said alone: passed on, sealed in its own place, and not kept.
    assert_eq!(send_live(&h, &id, json!({ "lines": [], "partial": { "at": 21000, "speaker": "Sam Lee", "text": "and the launch is Tuesday" } })).await, StatusCode::NO_CONTENT);
    let partial = frames(&mut phone).remove(0);
    assert_eq!((partial["partial"].as_u64(), partial.get("seq")), (Some(1), None));
    assert_eq!(opened(&secret, &id, "p1", &partial).unwrap()["partial"]["text"], "and the launch is Tuesday");
    assert!(opened(&secret, &id, "1", &partial).is_err());
    // Nothing said is nothing sent.
    assert_eq!(send_live(&h, &id, json!({ "lines": [{ "at": 1, "speaker": "", "text": "  " }] })).await, StatusCode::NO_CONTENT);
    assert!(frames(&mut phone).is_empty());

    assert_eq!(send_live(&h, &id, json!({ "lines": [{ "at": 30000, "speaker": "Priya", "text": "Ship it." }] })).await, StatusCode::NO_CONTENT);
    frames(&mut phone);
    // The catch-up: the kept frames after the one given, sealed as they were sent.
    let (status, kept) = h.call(Method::GET, &format!("/api/v1/meet/{id}/live"), Some(&token), None).await;
    assert_eq!(status, StatusCode::OK, "{kept}");
    assert_eq!((kept["live"].as_bool(), kept["first"].as_u64()), (Some(true), Some(1)));
    let seqs: Vec<u64> = kept["frames"].as_array().unwrap().iter().map(|f| f["seq"].as_u64().unwrap()).collect();
    assert_eq!(seqs, vec![1, 2]);
    assert_eq!(opened(&secret, &id, "2", &kept["frames"][1]).unwrap()["lines"][0]["text"], "Ship it.");
    let (_, after) = h.call(Method::GET, &format!("/api/v1/meet/{id}/live?after=1"), Some(&token), None).await;
    assert_eq!(after["frames"].as_array().unwrap().len(), 1);
    let (_, none) = h.call(Method::GET, &format!("/api/v1/meet/{id}/live?after=2"), Some(&token), None).await;
    assert_eq!(none["frames"], json!([]));

    // Nothing of it is on disk in the clear.
    let seen = String::from_utf8_lossy(&files_under(h.dir.path())).into_owned();
    assert!(!seen.contains("PRIVATE-LIVE-MARKER") && !seen.contains("pricing page"), "the captions are in the clear on disk");
}

#[tokio::test]
async fn the_catch_up_is_the_meeting_s_own_account_s_alone_and_limited() {
    let h = Harness::new("meet-live");
    let (token, _) = with_key(&h, "sam").await;
    let (stranger, _) = with_key(&h, "ali").await;
    let id = in_call(&h, &token).await;
    assert_eq!(send_live(&h, &id, json!({ "lines": [{ "at": 1, "speaker": "Sam Lee", "text": "hello" }] })).await, StatusCode::NO_CONTENT);
    for (who, path) in [(Some(stranger.as_str()), format!("/api/v1/meet/{id}/live")), (Some(token.as_str()), "/api/v1/meet/nope/live".to_string())] {
        let (status, body) = h.call(Method::GET, &path, who, None).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    }
    let (status, _) = h.call(Method::GET, &format!("/api/v1/meet/{id}/live"), None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // A meeting Ghost has no feed for is not live, and has no frames.
    let (_, quiet) = h.call(Method::POST, "/api/v1/meet", Some(&token), Some(json!({ "url": "https://meet.google.com/xyz-defg-hij" }))).await;
    let quiet = quiet["meeting"]["id"].as_str().unwrap().to_string();
    let (status, body) = h.call(Method::GET, &format!("/api/v1/meet/{quiet}/live"), Some(&token), None).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "live": false, "first": null, "frames": [] })));
    // So many a minute, an account.
    let mut refused = None;
    for n in 0..GETS_PER_MINUTE + 2 {
        let (status, _) = h.call(Method::GET, &format!("/api/v1/meet/{id}/live"), Some(&token), None).await;
        if status == StatusCode::TOO_MANY_REQUESTS {
            refused = Some(n);
            break;
        }
    }
    assert!(refused.is_some_and(|n| n >= GETS_PER_MINUTE - 2), "{refused:?}");
}

#[tokio::test]
async fn the_bot_s_batches_are_limited_and_refused_once_ghost_is_not_in_the_meeting() {
    let h = Harness::new("meet-live");
    let (token, _) = with_key(&h, "sam").await;
    let (status, booked) = h.call(Method::POST, "/api/v1/meet", Some(&token), Some(json!({ "url": "https://meet.google.com/abc-defg-hij" }))).await;
    assert_eq!(status, StatusCode::OK);
    let booked = booked["meeting"]["id"].as_str().unwrap().to_string();
    let line = json!({ "lines": [{ "at": 1, "speaker": "Sam Lee", "text": "hello" }] });
    // Booked, not yet joined: not Ghost's to send, and it says where the meeting stands.
    let (status, body) = bot(&h, Method::POST, &format!("/api/internal/meet/{booked}/live"), Some(line.clone())).await;
    assert_eq!((status, body["state"].as_str()), (StatusCode::CONFLICT, Some("booked")));
    assert_eq!(send_live(&h, "nope", line.clone()).await, StatusCode::NOT_FOUND);

    let id = in_call(&h, &token).await;
    let many: Vec<Value> = (0..=LINES_MOST).map(|n| json!({ "at": n, "speaker": "", "text": "a" })).collect();
    assert_eq!(send_live(&h, &id, json!({ "lines": many })).await, StatusCode::BAD_REQUEST);
    assert_eq!(send_live(&h, &id, json!({ "lines": [{ "at": 1, "speaker": "", "text": "a".repeat(2001) }] })).await, StatusCode::BAD_REQUEST);
    assert_eq!(send_live(&h, &id, json!({ "lines": [{ "at": 1, "speaker": "x".repeat(121), "text": "a" }] })).await, StatusCode::BAD_REQUEST);
    let huge = "word ".repeat(14_000);
    assert_eq!(send_live(&h, &id, json!({ "lines": [{ "at": 1, "speaker": "", "text": huge }] })).await, StatusCode::PAYLOAD_TOO_LARGE);
    // Without the bot's token, or from outside, there is no such door.
    let request = Request::builder().method(Method::POST).uri(format!("/api/internal/meet/{id}/live")).header(header::CONTENT_TYPE, "application/json").body(Body::from(line.to_string())).unwrap();
    assert_eq!(h.send(request).await.0, StatusCode::UNAUTHORIZED);
    let mut proxied = Request::builder().method(Method::POST).uri(format!("/api/internal/meet/{id}/live")).header(header::AUTHORIZATION, format!("Bearer {TEST_BOT_TOKEN}")).header(header::CONTENT_TYPE, "application/json").body(Body::from(line.to_string())).unwrap();
    proxied.headers_mut().insert("x-forwarded-for", "203.0.113.5".parse().unwrap());
    assert_eq!(h.send(proxied).await.0, StatusCode::NOT_FOUND);
    // A burst, then the pace: past it, 429.
    let mut busy = None;
    for n in 0..(POST_BURST as usize + 5) {
        if send_live(&h, &id, line.clone()).await == StatusCode::TOO_MANY_REQUESTS {
            busy = Some(n);
            break;
        }
    }
    assert!(busy.is_some_and(|n| n >= POST_BURST as usize - 1), "{busy:?}");
}

#[tokio::test]
async fn the_take_or_the_meeting_s_end_ends_its_live_captions_and_its_devices_are_told() {
    let h = Harness::new("meet-live");
    let (token, _) = with_key(&h, "sam").await;
    let account = h.accounts.claims(&token).unwrap().sub;
    let mut phone = h.accounts.pokes.attach_for_test(account, 1);
    let id = in_call(&h, &token).await;
    assert_eq!(send_live(&h, &id, json!({ "lines": [{ "at": 1, "speaker": "Sam Lee", "text": "hello" }] })).await, StatusCode::NO_CONTENT);
    frames(&mut phone);
    // The take: the feed is over, said once, and the catch-up has nothing more.
    let body = "--ghost-take\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"audio\"\r\nContent-Type: audio/webm\r\n\r\nsound\r\n--ghost-take--\r\n";
    let upload = Request::builder()
        .method(Method::PUT)
        .uri(format!("/api/internal/meet/{id}/take"))
        .header(header::AUTHORIZATION, format!("Bearer {TEST_BOT_TOKEN}"))
        .header(header::CONTENT_TYPE, "multipart/form-data; boundary=ghost-take")
        .body(Body::from(body))
        .unwrap();
    assert_eq!(h.send(upload).await.0, StatusCode::OK);
    assert_eq!(frames(&mut phone), vec![json!({ "t": "captions", "meeting": id, "ended": true })]);
    let (_, kept) = h.call(Method::GET, &format!("/api/v1/meet/{id}/live"), Some(&token), None).await;
    assert_eq!(kept["live"], false);
    assert_eq!(h.accounts.captions.feeds(), 0);
    // Done: the bot sends no more, told so.
    assert_eq!(send_live(&h, &id, json!({ "lines": [{ "at": 2, "speaker": "Sam Lee", "text": "after" }] })).await, StatusCode::CONFLICT);

    // A meeting that fails mid-call ends its feed the same way.
    let failed = in_call(&h, &token).await;
    assert_eq!(send_live(&h, &failed, json!({ "lines": [{ "at": 1, "speaker": "Sam Lee", "text": "hello" }] })).await, StatusCode::NO_CONTENT);
    frames(&mut phone);
    let (status, _) = bot(&h, Method::POST, &format!("/api/internal/meet/{failed}/state"), Some(json!({ "state": "failed", "detail": "error" }))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(frames(&mut phone), vec![json!({ "t": "captions", "meeting": failed, "ended": true })]);
}
