//! Ghost in a Discord call, through the routes a device and the Discord bot call (docs/DISCORD_CALLS.md): a code made
//! on a device and redeemed by `/ghost link`, once and only in time; the link shown and let go; `/ghost join` refused
//! for a Discord user not linked, and booked as a meeting for one who is, which the device lists and can send Ghost
//! out of and the Meet bot never sees; the call's take sealed on arrival as a Meet's, its end moved to when it ended;
//! the bot's routes answered on this machine only, with its own token, and for Discord calls alone; and the limits.

use crate::discord::TEST_DISCORD_TOKEN;
use crate::mail::seal;
use crate::mail_tests::with_key;
use crate::meet::{take_seal_context, take_wrap_context, unpack, TEST_BOT_TOKEN};
use crate::test_support::{routes, Harness};
use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Method, Request, StatusCode};
use serde_json::{json, Value};
use std::net::SocketAddr;
use tower::ServiceExt;

const SAM: &str = "111111111111111111";
const ALI: &str = "222222222222222222";
const GUILD: &str = "333333333333333333";
const CHANNEL: &str = "444444444444444444";

/// A request as the Discord bot makes one: over loopback, with `bearer` when given.
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
    let (status, _, bytes) = h.send(bot(method, path, Some(TEST_DISCORD_TOKEN), body)).await;
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// A code made on the account's device: as shown, `XXXX-XXXX`.
async fn code(h: &Harness, token: &str) -> String {
    let (status, body) = h.call(Method::POST, "/api/v1/discord/link-code", Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["code"].as_str().unwrap().to_string()
}

/// `/ghost link <code>` by Discord user `user`.
async fn redeem(h: &Harness, code: &str, user: &str, name: &str) -> (StatusCode, Value) {
    bot_call(h, Method::POST, "/api/internal/discord/link", Some(json!({ "code": code, "user": user, "name": name }))).await
}

/// `/ghost join` by `user` in the test's channel.
async fn join(h: &Harness, user: &str) -> (StatusCode, Value) {
    bot_call(h, Method::POST, "/api/internal/discord/session", Some(json!({ "user": user, "guild": GUILD, "channel": CHANNEL, "title": "Standup in Ghost HQ" }))).await
}

/// An account with a key, linked to Discord user `user`; its token.
async fn linked(h: &Harness, handle: &str, user: &str) -> String {
    let (token, _) = with_key(h, handle).await;
    let code = code(h, &token).await;
    let (status, body) = redeem(h, &code, user, handle).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    token
}

/// The bot's upload of a call's take, multipart.
fn take_upload(id: &str, audio: &[u8], captions: &[u8]) -> Request<Body> {
    let mut body = Vec::new();
    for (name, kind, bytes) in [("audio", "audio/webm;codecs=opus", audio), ("captions", "application/x-ndjson", captions)] {
        body.extend_from_slice(format!("--ghost-take\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{name}\"\r\nContent-Type: {kind}\r\n\r\n").as_bytes());
        body.extend_from_slice(bytes);
        body.extend_from_slice(b"\r\n");
    }
    body.extend_from_slice(b"--ghost-take--\r\n");
    Request::builder()
        .method(Method::PUT)
        .uri(format!("/api/internal/discord/{id}/take"))
        .header(header::AUTHORIZATION, format!("Bearer {TEST_DISCORD_TOKEN}"))
        .header(header::CONTENT_TYPE, "multipart/form-data; boundary=ghost-take")
        .body(Body::from(body))
        .unwrap()
}

#[tokio::test]
async fn a_code_from_the_device_links_the_discord_user_once_and_the_device_shows_and_lets_it_go() {
    let h = Harness::new("discord");
    let (token, _) = with_key(&h, "sam").await;
    let (status, body) = h.call(Method::GET, "/api/v1/discord/link", Some(&token), None).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "link": null })));
    let (status, made) = h.call(Method::POST, "/api/v1/discord/link-code", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let shown = made["code"].as_str().unwrap();
    assert!(regex_like_code(shown), "{shown}");
    let expires = made["expiresAt"].as_i64().unwrap();
    let now = crate::wire::now_secs() * 1000;
    assert!((now + 590_000..=now + 610_000).contains(&expires), "ten minutes on: {expires} vs {now}");
    // Typed in lower case without the dash, as a person might.
    let typed = shown.replace('-', "").to_lowercase();
    let (status, body) = redeem(&h, &typed, SAM, "sam_lee").await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "linked": true })));
    let (_, body) = h.call(Method::GET, "/api/v1/discord/link", Some(&token), None).await;
    assert_eq!((body["link"]["name"].as_str(), body["link"]["calls"].as_bool()), (Some("sam_lee"), Some(true)), "a new link joins calls");
    assert!(body["link"]["linkedAt"].as_i64().unwrap() > 1_700_000_000_000);
    // Good once.
    let (status, body) = redeem(&h, shown, ALI, "ali").await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    // Let go: the bot no longer finds an account for the user.
    let (status, body) = h.call(Method::DELETE, "/api/v1/discord/link", Some(&token), None).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "link": null })));
    let (status, body) = join(&h, SAM).await;
    assert_eq!((status, body["linked"].clone()), (StatusCode::NOT_FOUND, json!(false)));
}

/// `XXXX-XXXX` of the code's letters.
fn regex_like_code(code: &str) -> bool {
    let (a, b) = code.split_once('-').unwrap_or(("", ""));
    a.len() == 4 && b.len() == 4 && crate::discord::typed_code(code).is_some()
}

#[tokio::test]
async fn a_code_needs_the_account_s_key_runs_out_and_a_wrong_one_links_nothing() {
    let h = Harness::new("discord");
    let token = h.signup("nokey", &crate::test_support::device()).await;
    let (status, _) = h.call(Method::POST, "/api/v1/discord/link-code", Some(&token), None).await;
    assert_eq!(status, StatusCode::CONFLICT, "a call is sealed to the key, so there must be one");
    let (status, _) = h.call(Method::POST, "/api/v1/discord/link-code", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let (token, _) = with_key(&h, "sam").await;
    let account = h.accounts.claims(&token).unwrap().sub;
    // A code that lapsed a moment ago, put straight into the store.
    let now = crate::wire::now_secs();
    let lapsed = "ABCDEFGH";
    let hash: String = <sha2::Sha256 as sha2::Digest>::digest(lapsed.as_bytes()).iter().map(|b| format!("{b:02x}")).collect();
    h.accounts.store.put_discord_code(account, &hash, now - 1, now - 601).unwrap();
    let (status, _) = redeem(&h, "ABCD-EFGH", SAM, "sam").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    for wrong in ["NOPE", "ABCD-EFG0", ""] {
        let (status, _) = redeem(&h, wrong, SAM, "sam").await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{wrong}");
    }
    let (status, _) = redeem(&h, "ABCD-EFGH", "not-a-snowflake", "sam").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (_, body) = h.call(Method::GET, "/api/v1/discord/link", Some(&token), None).await;
    assert_eq!(body["link"], Value::Null);
}

#[tokio::test]
async fn a_discord_user_trying_codes_is_stopped_after_ten_in_an_hour() {
    let h = Harness::new("discord");
    for i in 0..10 {
        let (status, _) = redeem(&h, "ABCD-EFGH", SAM, "sam").await;
        assert_eq!(status, StatusCode::NOT_FOUND, "try {i}");
    }
    let (status, _) = redeem(&h, "ABCD-EFGH", SAM, "sam").await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);
    // Another user has tries of their own, and a right code still links them.
    let (token, _) = with_key(&h, "ali").await;
    let code = code(&h, &token).await;
    assert_eq!(redeem(&h, &code, ALI, "ali").await.0, StatusCode::OK);
}

#[tokio::test]
async fn joining_books_a_call_the_device_lists_and_can_send_ghost_out_of_and_the_meet_bot_never_sees() {
    let h = Harness::new("discord");
    let token = linked(&h, "sam", SAM).await;
    let (status, body) = join(&h, SAM).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["name"], "sam");
    let id = body["meeting"]["id"].as_str().unwrap().to_string();
    assert_eq!(body["meeting"]["state"], "joining");
    let (starts, ends) = (body["meeting"]["startsAt"].as_i64().unwrap(), body["meeting"]["endsAt"].as_i64().unwrap());
    assert_eq!(ends - starts, (3 * 60 + 15) * 60 * 1000);

    // The device lists it as any meeting, the channel's link its url.
    let (_, listed) = h.call(Method::GET, "/api/v1/meet?limit=20", Some(&token), None).await;
    let meeting = &listed["meetings"][0];
    assert_eq!((meeting["id"].as_str(), meeting["title"].as_str()), (Some(id.as_str()), Some("Standup in Ghost HQ")));
    assert_eq!(meeting["url"], format!("https://discord.com/channels/{GUILD}/{CHANNEL}"));
    assert_eq!(meeting["kind"], "discord");

    // The Meet bot's due passes it over (it would refuse a link that is not Meet's); the Discord bot's lists it.
    let (status, _, bytes) = h.send(bot(Method::GET, "/api/internal/meet/due", Some(TEST_BOT_TOKEN), None)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(serde_json::from_slice::<Value>(&bytes).unwrap()["meetings"], json!([]));
    let (_, due) = bot_call(&h, Method::GET, "/api/internal/discord/due", None).await;
    assert_eq!(due["meetings"].as_array().unwrap().iter().map(|m| m["id"].as_str().unwrap()).collect::<Vec<_>>(), vec![id.as_str()]);

    // In the call; then the device's Leave now: the bot reads `leave`, and is not let back in.
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/discord/{id}/state"), Some(json!({ "state": "in_call" }))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = h.call(Method::DELETE, &format!("/api/v1/meet/{id}"), Some(&token), None).await;
    assert_eq!((status, body["meeting"]["state"].as_str()), (StatusCode::OK, Some("leave")));
    let (_, due) = bot_call(&h, Method::GET, "/api/internal/discord/due", None).await;
    assert_eq!(due["meetings"][0]["state"], "leave");
    let (status, body) = bot_call(&h, Method::POST, &format!("/api/internal/discord/{id}/state"), Some(json!({ "state": "in_call" }))).await;
    assert_eq!((status, body["state"].as_str()), (StatusCode::CONFLICT, Some("leave")));

    // A call that ends with nothing recorded: failed, and its end is now, not three hours on.
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/discord/{id}/state"), Some(json!({ "state": "failed", "detail": "nothing_heard" }))).await;
    assert_eq!(status, StatusCode::OK);
    let b = h.accounts.store.meet_booking(&id).unwrap();
    assert!(b.ends_at - b.starts_at < 60_000, "{} after its start", b.ends_at - b.starts_at);
    let (_, due) = bot_call(&h, Method::GET, "/api/internal/discord/due", None).await;
    assert_eq!(due["meetings"], json!([]));
}

#[tokio::test]
async fn a_call_s_take_is_sealed_on_arrival_and_opened_by_the_account_alone() {
    let h = Harness::new("discord");
    let (token, secret) = with_key(&h, "sam").await;
    let code = code(&h, &token).await;
    redeem(&h, &code, SAM, "sam").await;
    let (_, body) = join(&h, SAM).await;
    let id = body["meeting"]["id"].as_str().unwrap().to_string();
    let audio = b"\x1aE\xdf\xa3 PRIVATE-DISCORD-AUDIO".to_vec();
    let captions = b"{\"at\":1000,\"speaker\":\"Sam Lee\",\"text\":\"\"}\n".to_vec();
    let (status, _, bytes) = h.send(take_upload(&id, &audio, &captions)).await;
    let answer: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(status, StatusCode::OK, "{answer}");
    let take = answer["take"].as_str().unwrap().to_string();
    let b = h.accounts.store.meet_booking(&id).unwrap();
    assert_eq!(b.state, "done");
    assert!(b.ends_at - b.starts_at < 60_000, "the call's end is when its take came");

    let (_, listed) = h.call(Method::GET, "/api/v1/meet/takes", Some(&token), None).await;
    assert_eq!(listed["takes"][0]["meeting"], id.as_str());
    let (status, headers, sealed) = h.send(crate::test_support::request(Method::GET, &format!("/api/v1/meet/takes/{take}"), Some(&token), None)).await;
    assert_eq!(status, StatusCode::OK);
    let wrapped = headers["x-glyph-wrapped"].to_str().unwrap().to_string();
    assert!(!String::from_utf8_lossy(&sealed).contains("PRIVATE-DISCORD-AUDIO"));
    let opened = seal::open_sealed_with(&secret, &wrapped, &take_wrap_context(&take), &sealed, &take_seal_context(&take)).unwrap();
    let (head, got_captions, got_audio) = unpack(&opened);
    assert_eq!((got_audio, got_captions), (audio, captions));
    assert_eq!(head["title"], "Standup in Ghost HQ");
    assert_eq!(head["kind"], "discord", "the take says which service it is, for the device to file it under");
}

#[tokio::test]
async fn joining_needs_a_link_a_key_and_ids_and_a_user_may_open_twenty_calls_an_hour() {
    let h = Harness::new("discord");
    let (status, body) = join(&h, SAM).await;
    assert_eq!((status, body["linked"].clone()), (StatusCode::NOT_FOUND, json!(false)));
    let (status, _) = bot_call(&h, Method::POST, "/api/internal/discord/session", Some(json!({ "user": SAM, "guild": "x", "channel": CHANNEL }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    linked(&h, "sam", SAM).await;
    // The title is optional, and a plain one is made.
    let (status, body) = bot_call(&h, Method::POST, "/api/internal/discord/session", Some(json!({ "user": SAM, "guild": GUILD, "channel": CHANNEL }))).await;
    assert_eq!(status, StatusCode::OK);
    let id = body["meeting"]["id"].as_str().unwrap();
    assert_eq!(h.accounts.store.meet_booking(id).unwrap().title.as_deref(), Some("Discord call"));
    // The refused join above counted (a user is limited before they are looked up), and so did that one: eighteen more.
    for i in 2..20 {
        assert_eq!(join(&h, SAM).await.0, StatusCode::OK, "call {i}");
    }
    assert_eq!(join(&h, SAM).await.0, StatusCode::TOO_MANY_REQUESTS);
}

#[tokio::test]
async fn the_bot_s_routes_answer_only_here_with_its_own_token_and_for_discord_calls_alone() {
    let h = Harness::new("discord");
    let token = linked(&h, "sam", SAM).await;
    // Through Caddy: not there at all.
    let mut through = bot(Method::GET, "/api/internal/discord/due", Some(TEST_DISCORD_TOKEN), None);
    through.headers_mut().insert("x-forwarded-for", "203.0.113.9".parse().unwrap());
    let (status, _, bytes) = h.send(through).await;
    assert_eq!((status, serde_json::from_slice::<Value>(&bytes).unwrap()), (StatusCode::NOT_FOUND, json!({ "error": "no such route" })));
    // From another machine: the same.
    let elsewhere = routes(Some(h.accounts.clone())).layer(MockConnectInfo(SocketAddr::from(([198, 51, 100, 7], 40000))));
    let response = elsewhere.oneshot(bot(Method::GET, "/api/internal/discord/due", Some(TEST_DISCORD_TOKEN), None)).await.unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    // Here, with no token, a wrong one, or the Meet bot's: 401.
    for bearer in [None, Some("wrong"), Some(TEST_BOT_TOKEN)] {
        let (status, _, _) = h.send(bot(Method::GET, "/api/internal/discord/due", bearer, None)).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{bearer:?}");
    }
    // And the Discord bot's token opens none of the Meet bot's routes.
    let (status, _, _) = h.send(bot(Method::GET, "/api/internal/meet/due", Some(TEST_DISCORD_TOKEN), None)).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // A Meet booked from the device is not the Discord bot's to move or upload to.
    let (_, body) = h.call(Method::POST, "/api/v1/meet", Some(&token), Some(json!({ "url": "https://meet.google.com/abc-defg-hij" }))).await;
    let meet = body["meeting"]["id"].as_str().unwrap().to_string();
    let (status, _) = bot_call(&h, Method::POST, &format!("/api/internal/discord/{meet}/state"), Some(json!({ "state": "in_call" }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = h.send(take_upload(&meet, b"audio", b"")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(h.accounts.store.meet_booking(&meet).unwrap().state, "booked");
    // The device's routes need a session, as every device route does.
    let (status, _) = h.call(Method::GET, "/api/v1/discord/link", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn the_plugin_s_switch_turns_joining_off_and_on_and_needs_a_link() {
    let h = Harness::new("discord");
    let (unlinked, _) = with_key(&h, "ali").await;
    let (status, _) = h.call(Method::PUT, "/api/v1/discord/calls", Some(&unlinked), Some(json!({ "on": false }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let token = linked(&h, "sam", SAM).await;
    let (status, body) = h.call(Method::PUT, "/api/v1/discord/calls", Some(&token), Some(json!({ "on": false }))).await;
    assert_eq!((status, body["link"]["calls"].as_bool()), (StatusCode::OK, Some(false)));
    let (status, body) = join(&h, SAM).await;
    assert_eq!((status, body["calls"].clone(), body["linked"].clone()), (StatusCode::FORBIDDEN, json!(false), json!(true)));
    let (_, listed) = h.call(Method::GET, "/api/v1/meet?limit=20", Some(&token), None).await;
    assert_eq!(listed["meetings"], json!([]), "nothing booked");
    h.call(Method::PUT, "/api/v1/discord/calls", Some(&token), Some(json!({ "on": true }))).await;
    assert_eq!(join(&h, SAM).await.0, StatusCode::OK);
}
