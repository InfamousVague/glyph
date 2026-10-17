//! Incoming hooks, through the routes a device and a poster call (docs/INTEGRATIONS.md, "In: a URL that adds to a
//! note"): a hook made, listed and deleted; a post in each of its three shapes kept ONLY sealed, and opened with the
//! account's private key alone; every refusal - an unknown token, too large a post, an `as` that is not one, too many
//! posts a minute, a full inbox, no key to seal to - and the thirty days a post waits.
//!
//! And the seal's one contract with the app: tauri/src/app/core/orgs/hookSeal.fixture.json holds a post this service
//! sealed, which wrap.ts's `unwrapWith` opens (hookSeal.test.ts), and a payload `wrapFor` wrapped, which this opens.
//! `GLYPH_WRITE_HOOK_FIXTURE=1 cargo test hook_seal_fixture` writes the service's half anew; the vitest, with the same
//! variable, writes wrap.ts's half.

use crate::hooks::{context, HOOKS_PER_ACCOUNT, KEPT_FOR, POST_LIMIT, WAITING};
use crate::mail::seal;
use crate::store::{HookItem, HookRow};
use crate::test_support::{device, Harness, TempDir};
use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use serde_json::{json, Value};

fn now() -> i64 {
    crate::wire::now_secs()
}

fn public_of(secret: &p256::SecretKey) -> String {
    URL_SAFE_NO_PAD.encode(secret.public_key().to_encoded_point(false).as_bytes())
}

/// An account with `secret` registered as its encryption key, as a device registers one; its token.
async fn with_this_key(h: &Harness, handle: &str, secret: &p256::SecretKey) -> String {
    let token = h.signup(handle, &device()).await;
    let (status, _) = h.call(Method::PUT, "/api/v1/account/key", Some(&token), Some(json!({ "pub": public_of(secret), "sealed": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::CREATED);
    token
}

/// An account with a fresh encryption key registered; its token and its private key.
async fn with_key(h: &Harness, handle: &str) -> (String, p256::SecretKey) {
    let secret = p256::SecretKey::random(&mut rand::rngs::OsRng);
    (with_this_key(h, handle, &secret).await, secret)
}

/// A hook made through the route: its id and the token in its URL.
async fn made(h: &Harness, token: &str, body: Value) -> (String, String) {
    let (status, hook) = h.call(Method::POST, "/api/v1/hooks", Some(token), Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{hook}");
    let url = hook["url"].as_str().unwrap();
    (hook["id"].as_str().unwrap().to_string(), url.rsplit('/').next().unwrap().to_string())
}

/// A post to the hook whose token is `token`, of `kind` (a content type, or none).
fn post(token: &str, kind: Option<&str>, body: impl Into<Body>) -> Request<Body> {
    let mut request = Request::builder().method(Method::POST).uri(format!("/api/hooks/{token}"));
    if let Some(kind) = kind {
        request = request.header(header::CONTENT_TYPE, kind);
    }
    request.body(body.into()).unwrap()
}

async fn status_of(h: &Harness, request: Request<Body>) -> (StatusCode, Value) {
    let (status, _, bytes) = h.send(request).await;
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// What waits for the account, through the route.
async fn inbox(h: &Harness, token: &str, after: Option<&str>) -> Vec<Value> {
    let path = match after {
        Some(after) => format!("/api/v1/hooks/inbox?after={after}"),
        None => "/api/v1/hooks/inbox".into(),
    };
    let (status, body) = h.call(Method::GET, &path, Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body.as_array().unwrap().clone()
}

/// A waiting post opened as a device opens it, with the account's private key, in its hook's context.
fn opened(secret: &p256::SecretKey, item: &Value) -> Value {
    let hook = item["hook"].as_str().unwrap();
    serde_json::from_slice(&seal::unwrap_with(secret, item["sealed"].as_str().unwrap(), &context(hook)).unwrap()).unwrap()
}

#[tokio::test]
async fn a_hook_is_made_with_its_url_once_listed_without_it_and_deleted_by_its_account_alone() {
    let h = Harness::new("hooks");
    let (token, _) = with_key(&h, "sam").await;
    let (status, _) = h.call(Method::POST, "/api/v1/hooks", None, Some(json!({ "name": "Zapier" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = h.call(Method::GET, "/api/v1/hooks", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, hook) = h.call(Method::POST, "/api/v1/hooks", Some(&token), Some(json!({ "name": "  Zapier ", "note": "Groceries" }))).await;
    assert_eq!(status, StatusCode::CREATED, "{hook}");
    let id = hook["id"].as_str().unwrap();
    assert_eq!((hook["name"].as_str(), hook["note"].as_str()), (Some("Zapier"), Some("Groceries")));
    assert!(hook["createdAt"].as_i64().unwrap() > 1_700_000_000_000, "in ms");
    let url = hook["url"].as_str().unwrap();
    let secret_part = url.strip_prefix("https://ghostmarkdown.com/api/hooks/").unwrap();
    assert_eq!(URL_SAFE_NO_PAD.decode(secret_part).unwrap().len(), 32, "{url}");
    // The token is nowhere in what the service keeps.
    let kept: Vec<String> = h.accounts.store.hooks_of(1).into_iter().map(|h| format!("{h:?}")).collect();
    assert!(!kept.concat().contains(secret_part));
    let (status, list) = h.call(Method::GET, "/api/v1/hooks", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list, json!([{ "id": id, "name": "Zapier", "note": "Groceries", "createdAt": hook["createdAt"], "lastUsedAt": null }]));
    // Another account sees none of it and deletes none of it.
    let (stranger, _) = with_key(&h, "ali").await;
    let (_, theirs) = h.call(Method::GET, "/api/v1/hooks", Some(&stranger), None).await;
    assert_eq!(theirs, json!([]));
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/hooks/{id}"), Some(&stranger), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(status_of(&h, post(secret_part, Some("text/plain"), "milk")).await.0, StatusCode::ACCEPTED, "still live");
    let (_, list) = h.call(Method::GET, "/api/v1/hooks", Some(&token), None).await;
    assert!(list[0]["lastUsedAt"].as_i64().unwrap() > 1_700_000_000_000, "used just now");
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/hooks/{id}"), Some(&token), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(status_of(&h, post(secret_part, Some("text/plain"), "eggs")).await, (StatusCode::NOT_FOUND, json!({ "error": "There is no such hook." })));
    // What it took before it went still waits for a device.
    assert_eq!(inbox(&h, &token, None).await.len(), 1);
}

#[tokio::test]
async fn a_hook_needs_a_name_an_encryption_key_and_room() {
    let h = Harness::new("hooks");
    let keyless = h.signup("lee", &device()).await;
    let (status, body) = h.call(Method::POST, "/api/v1/hooks", Some(&keyless), Some(json!({ "name": "Zapier" }))).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "This account has no encryption key yet." })));
    let (token, _) = with_key(&h, "sam").await;
    for bad in [json!({ "name": "   " }), json!({ "name": "a".repeat(101) }), json!({ "name": "ok", "note": "n".repeat(201) })] {
        let (status, _) = h.call(Method::POST, "/api/v1/hooks", Some(&token), Some(bad.clone())).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{bad}");
    }
    let (_, hook) = h.call(Method::POST, "/api/v1/hooks", Some(&token), Some(json!({ "name": "No note", "note": "  " }))).await;
    assert_eq!(hook["note"], Value::Null, "a blank note is none");
    for i in 1..HOOKS_PER_ACCOUNT {
        made(&h, &token, json!({ "name": format!("hook {i}") })).await;
    }
    let (status, _) = h.call(Method::POST, "/api/v1/hooks", Some(&token), Some(json!({ "name": "one too many" }))).await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn a_post_is_kept_only_sealed_and_opens_with_the_account_s_private_key_alone() {
    let h = Harness::new("hooks");
    let (token, secret) = with_key(&h, "sam").await;
    let (id, hook) = made(&h, &token, json!({ "name": "Zapier", "note": "Groceries" })).await;
    let (status, body) = status_of(&h, post(&hook, Some("application/json"), json!({ "text": "Pomegranate jam", "as": "item" }).to_string())).await;
    assert_eq!(status, StatusCode::ACCEPTED, "{body}");
    let items = inbox(&h, &token, None).await;
    assert_eq!(items.len(), 1);
    assert_eq!((items[0]["id"].as_str(), items[0]["hook"].as_str()), (body["id"].as_str(), Some(id.as_str())));
    assert!(items[0]["at"].as_i64().unwrap() > 1_700_000_000_000);
    let sealed = items[0]["sealed"].as_str().unwrap();
    assert!(!String::from_utf8_lossy(&URL_SAFE_NO_PAD.decode(sealed).unwrap()).contains("omegranate"));
    let payload = opened(&secret, &items[0]);
    assert_eq!(payload, json!({ "hook": id, "note": "Groceries", "text": "Pomegranate jam", "as": "item", "at": items[0]["at"] }));
    // wrapFor's layout: the ephemeral point, the IV, the payload and its tag.
    assert_eq!(URL_SAFE_NO_PAD.decode(sealed).unwrap().len(), 65 + 12 + serde_json::to_vec(&payload).unwrap().len() + 16);
    let other = p256::SecretKey::random(&mut rand::rngs::OsRng);
    assert!(seal::unwrap_with(&other, sealed, &context(&id)).is_err(), "no key but the account's opens it");
    assert!(seal::unwrap_with(&secret, sealed, &context("another-hook")).is_err(), "nor in another hook's context");
    assert!(seal::unwrap_with(&secret, sealed, &format!("org-key:{id}:1")).is_err(), "nor as an organization key");
    // Another account can neither read nor take it.
    let (stranger, _) = with_key(&h, "ali").await;
    assert!(inbox(&h, &stranger, None).await.is_empty());
    let item = items[0]["id"].as_str().unwrap();
    h.call(Method::DELETE, &format!("/api/v1/hooks/inbox/{item}"), Some(&stranger), None).await;
    assert_eq!(inbox(&h, &token, None).await.len(), 1);
    let (status, _) = h.call(Method::GET, "/api/v1/hooks/inbox", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // Added to its note: taken.
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/hooks/inbox/{item}"), Some(&token), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert!(inbox(&h, &token, None).await.is_empty());
}

#[tokio::test]
async fn a_post_is_json_a_form_or_plain_text_and_the_hook_s_note_is_its_default() {
    let h = Harness::new("hooks");
    let (token, secret) = with_key(&h, "sam").await;
    let (_, hook) = made(&h, &token, json!({ "name": "curl", "note": "Groceries" })).await;
    let (_, bare) = made(&h, &token, json!({ "name": "no note" })).await;
    let posts = [
        post(&hook, Some("application/json; charset=utf-8"), json!({ "note": "Trip", "text": "Passports", "as": "task", "title": "Packing", "extra": 1 }).to_string()),
        post(&hook, Some("application/x-www-form-urlencoded"), "text=Two+lemons%21&as=item"),
        post(&hook, Some("text/plain; charset=utf-8"), "Ring the plumber\nabout the boiler"),
        post(&hook, None, "No content type is plain text"),
        post(&bare, Some("application/json"), json!({ "text": "Somewhere", "as": "note" }).to_string()),
    ];
    for request in posts {
        let (status, body) = status_of(&h, request).await;
        assert_eq!(status, StatusCode::ACCEPTED, "{body}");
    }
    let opened: Vec<Value> = inbox(&h, &token, None).await.iter().map(|i| opened(&secret, i)).map(|mut p| {
        p.as_object_mut().unwrap().retain(|k, _| k != "hook" && k != "at");
        p
    }).collect();
    assert_eq!(
        opened,
        vec![
            json!({ "note": "Trip", "text": "Passports", "as": "task", "title": "Packing" }),
            json!({ "note": "Groceries", "text": "Two lemons!", "as": "item" }),
            json!({ "note": "Groceries", "text": "Ring the plumber\nabout the boiler", "as": null }),
            json!({ "note": "Groceries", "text": "No content type is plain text", "as": null }),
            json!({ "note": null, "text": "Somewhere", "as": "note" }),
        ]
    );
}

#[tokio::test]
async fn a_post_that_cannot_be_read_or_has_no_text_or_a_wrong_as_is_refused_and_nothing_is_kept() {
    let h = Harness::new("hooks");
    let (token, _) = with_key(&h, "sam").await;
    let (_, hook) = made(&h, &token, json!({ "name": "curl" })).await;
    let refused = [
        (post(&hook, Some("application/json"), "{ not json"), StatusCode::BAD_REQUEST),
        (post(&hook, Some("application/json"), json!({ "note": "Trip" }).to_string()), StatusCode::BAD_REQUEST),
        (post(&hook, Some("application/json"), json!({ "text": "   " }).to_string()), StatusCode::BAD_REQUEST),
        (post(&hook, Some("application/json"), json!({ "text": 3 }).to_string()), StatusCode::BAD_REQUEST),
        (post(&hook, Some("application/json"), json!({ "text": "x", "as": "heading" }).to_string()), StatusCode::BAD_REQUEST),
        (post(&hook, Some("application/json"), json!({ "text": "x", "note": "n".repeat(201) }).to_string()), StatusCode::BAD_REQUEST),
        (post(&hook, Some("application/x-www-form-urlencoded"), "as=task"), StatusCode::BAD_REQUEST),
        (post(&hook, Some("text/plain"), vec![0xff, 0xfe]), StatusCode::BAD_REQUEST),
        (post(&hook, Some("text/plain"), ""), StatusCode::BAD_REQUEST),
        (post(&hook, Some("image/png"), "x"), StatusCode::UNSUPPORTED_MEDIA_TYPE),
    ];
    for (request, expected) in refused {
        let (status, body) = status_of(&h, request).await;
        assert_eq!(status, expected, "{body}");
        assert!(body["error"].is_string());
    }
    let (_, body) = status_of(&h, post(&hook, Some("application/json"), json!({ "text": "x", "as": "heading" }).to_string())).await;
    assert_eq!(body, json!({ "error": "`as` is task, item, paragraph or note." }));
    assert!(inbox(&h, &token, None).await.is_empty());
}

#[tokio::test]
async fn a_post_is_at_most_32_kb() {
    let h = Harness::new("hooks");
    let (token, _) = with_key(&h, "sam").await;
    let (_, hook) = made(&h, &token, json!({ "name": "curl" })).await;
    assert_eq!(status_of(&h, post(&hook, Some("text/plain"), "a".repeat(POST_LIMIT))).await.0, StatusCode::ACCEPTED, "32 KB exactly");
    let (status, body) = status_of(&h, post(&hook, Some("text/plain"), "a".repeat(POST_LIMIT + 1))).await;
    assert_eq!((status, body), (StatusCode::PAYLOAD_TOO_LARGE, json!({ "error": "That post is too large: a hook takes up to 32 KB." })));
    // Text that escapes to more than twice its size as JSON is held to what is sealed, too.
    let (status, _) = status_of(&h, post(&hook, Some("text/plain"), "\u{1}".repeat(16 * 1024))).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(inbox(&h, &token, None).await.len(), 1);
}

#[tokio::test]
async fn an_unknown_token_of_any_shape_is_the_same_404() {
    let h = Harness::new("hooks");
    let (token, _) = with_key(&h, "sam").await;
    let (_, hook) = made(&h, &token, json!({ "name": "curl" })).await;
    let mut wrong = hook.clone().into_bytes();
    wrong[0] = if wrong[0] == b'A' { b'B' } else { b'A' };
    let wrong = String::from_utf8(wrong).unwrap();
    for unknown in [wrong.as_str(), "short", "not%20a%20token", &"A".repeat(43), &"x".repeat(500)] {
        let answer = status_of(&h, post(unknown, Some("text/plain"), "milk")).await;
        assert_eq!(answer, (StatusCode::NOT_FOUND, json!({ "error": "There is no such hook." })), "{unknown}");
    }
    // A hook's id is not its token.
    let (status, _) = h.call(Method::GET, "/api/v1/hooks", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let id = h.accounts.store.hooks_of(1)[0].id.clone();
    assert_eq!(status_of(&h, post(&id, Some("text/plain"), "milk")).await.0, StatusCode::NOT_FOUND);
    assert!(inbox(&h, &token, None).await.is_empty());
}

#[tokio::test]
async fn a_hook_takes_sixty_posts_a_minute_and_another_hook_its_own_sixty() {
    let h = Harness::new("hooks");
    let (token, _) = with_key(&h, "sam").await;
    let (_, busy) = made(&h, &token, json!({ "name": "busy" })).await;
    let (_, quiet) = made(&h, &token, json!({ "name": "quiet" })).await;
    // Posted until refused, the time it took measured: the bucket earns one back a second, so a slow machine is let
    // one more post for each second it spent, and never fewer than sixty.
    let start = std::time::Instant::now();
    let mut taken = 0;
    loop {
        let (status, body) = status_of(&h, post(&busy, Some("text/plain"), format!("post {taken}"))).await;
        if status == StatusCode::TOO_MANY_REQUESTS {
            assert_eq!(body, json!({ "error": "That hook has taken as many posts as it may this minute. Try again shortly." }));
            break;
        }
        assert_eq!(status, StatusCode::ACCEPTED, "post {taken}: {body}");
        taken += 1;
        assert!(taken <= 200, "never refused");
    }
    let earned = start.elapsed().as_secs() as usize + 1;
    assert!((60..=60 + earned).contains(&taken), "{taken} taken in {earned} s");
    assert_eq!(status_of(&h, post(&quiet, Some("text/plain"), "mine")).await.0, StatusCode::ACCEPTED);
}

/// A hook seeded through the store, as the route would make it, with `hash` for its token's hash.
fn seeded_hook(h: &Harness, account: i64, id: &str, hash: &str) {
    let hook = HookRow { id: id.into(), account, name: "seeded".into(), note: None, created_at: now(), last_used_at: None };
    h.accounts.store.put_hook(&hook, hash, HOOKS_PER_ACCOUNT).unwrap();
}

fn hash_of(token: &str) -> String {
    use sha2::Digest;
    URL_SAFE_NO_PAD.encode(sha2::Sha256::digest(token.as_bytes()))
}

#[tokio::test]
async fn an_account_keeps_five_hundred_waiting_and_a_full_inbox_is_said() {
    let h = Harness::new("hooks");
    let (token, _) = with_key(&h, "sam").await;
    let (id, hook) = made(&h, &token, json!({ "name": "curl" })).await;
    for i in 0..WAITING {
        h.accounts.store.put_hook_item(1, &HookItem { id: format!("seeded{i}"), hook: id.clone(), sealed: "s".into(), at: now() }, WAITING, 0).unwrap();
    }
    let (status, body) = status_of(&h, post(&hook, Some("text/plain"), "milk")).await;
    assert_eq!((status, body), (StatusCode::INSUFFICIENT_STORAGE, json!({ "error": "That inbox is full: its owner's devices have not synced for a while." })));
    // A device takes one, and there is room again.
    h.call(Method::DELETE, "/api/v1/hooks/inbox/seeded0", Some(&token), None).await;
    assert_eq!(status_of(&h, post(&hook, Some("text/plain"), "milk")).await.0, StatusCode::ACCEPTED);
}

#[tokio::test]
async fn a_post_to_an_account_without_an_encryption_key_is_refused_unread() {
    let h = Harness::new("hooks");
    let keyless = h.signup("lee", &device()).await;
    seeded_hook(&h, 1, "keyless-hook", &hash_of("the-token"));
    let (status, body) = status_of(&h, post("the-token", Some("text/plain"), "milk")).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "This account has no encryption key yet." })));
    assert!(inbox(&h, &keyless, None).await.is_empty());
}

#[tokio::test]
async fn the_inbox_is_read_a_hundred_at_a_time_oldest_first() {
    let h = Harness::new("hooks");
    let (token, _) = with_key(&h, "sam").await;
    for i in 0..150 {
        h.accounts.store.put_hook_item(1, &HookItem { id: format!("p{i:03}"), hook: "h".into(), sealed: "s".into(), at: now() }, WAITING, 0).unwrap();
    }
    let first = inbox(&h, &token, None).await;
    assert_eq!((first.len(), first[0]["id"].as_str(), first[99]["id"].as_str()), (100, Some("p000"), Some("p099")));
    let rest = inbox(&h, &token, Some("p099")).await;
    assert_eq!((rest.len(), rest[0]["id"].as_str(), rest[49]["id"].as_str()), (50, Some("p100"), Some("p149")));
    assert!(inbox(&h, &token, Some("p149")).await.is_empty());
    assert_eq!(inbox(&h, &token, Some("not/an/id")).await.len(), 100, "a cursor that cannot be read starts at the first");
}

#[tokio::test]
async fn a_post_waits_thirty_days_and_no_longer() {
    let h = Harness::new("hooks");
    let (token, _) = with_key(&h, "sam").await;
    let store = &h.accounts.store;
    store.put_hook_item(1, &HookItem { id: "old".into(), hook: "h".into(), sealed: "s".into(), at: now() - KEPT_FOR - 5 }, WAITING, 0).unwrap();
    store.put_hook_item(1, &HookItem { id: "young".into(), hook: "h".into(), sealed: "s".into(), at: now() - KEPT_FOR + 3600 }, WAITING, 0).unwrap();
    let ids: Vec<Value> = inbox(&h, &token, None).await.iter().map(|i| i["id"].clone()).collect();
    assert_eq!(ids, vec![json!("young")], "past thirty days, not listed");
    assert_eq!(store.sweep_hook_inbox(now() - KEPT_FOR), 1, "and swept");
    assert_eq!(store.sweep_hook_inbox(now() - KEPT_FOR), 0);
}

/// The promise of the contract, held to the database's own file: not a word of a post is in it, on disk.
#[tokio::test]
async fn not_a_word_of_a_post_reaches_the_service_s_files() {
    use crate::accounts::Accounts;
    use crate::store::Store;
    use std::sync::Arc;
    let dir = TempDir::new("hooks-disk");
    let data = dir.path().join("glyph-api");
    let accounts = Accounts::new(Arc::new(Store::open(&data).unwrap()));
    let h = Harness { service: crate::test_support::service(Some(accounts.clone())), accounts, dir: TempDir::new("hooks-disk-unused") };
    let (token, secret) = with_key(&h, "sam").await;
    let (_, hook) = made(&h, &token, json!({ "name": "curl" })).await;
    assert_eq!(status_of(&h, post(&hook, Some("text/plain"), "Pomegranate jam for Saturday")).await.0, StatusCode::ACCEPTED);
    let mut seen = Vec::new();
    for entry in std::fs::read_dir(&data).unwrap() {
        let path = entry.unwrap().path();
        if path.is_file() {
            seen.extend(std::fs::read(&path).unwrap());
        }
    }
    let text = String::from_utf8_lossy(&seen).to_lowercase();
    assert!(!text.is_empty());
    for word in ["pomegranate", "saturday", &hook.to_lowercase()] {
        assert!(!text.contains(word), "{word:?} is in the service's files");
    }
    assert_eq!(opened(&secret, &inbox(&h, &token, None).await[0])["text"], "Pomegranate jam for Saturday");
}

// --- the seal, across languages --------------------------------------------------

/// Where the fixture both sides read is kept: beside wrap.ts, whose `unwrapWith` opens it.
const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../tauri/src/app/core/orgs/hookSeal.fixture.json");

/// The fixture's account key: fixed, so the fixture's JWK and the key below are the same key on every run.
fn fixture_secret() -> p256::SecretKey {
    p256::SecretKey::from_slice(&[7u8; 32]).unwrap()
}

/// The private key as wrap.ts's `importEncryptionKey` takes it: a JWK, every coordinate base64url.
fn jwk_of(secret: &p256::SecretKey) -> Value {
    let point = secret.public_key().to_encoded_point(false);
    let b64 = |b: &[u8]| URL_SAFE_NO_PAD.encode(b);
    json!({ "kty": "EC", "crv": "P-256", "d": b64(&secret.to_bytes()), "x": b64(point.x().unwrap()), "y": b64(point.y().unwrap()), "ext": true })
}

#[tokio::test]
async fn hook_seal_fixture() {
    let secret = fixture_secret();
    let write = std::env::var("GLYPH_WRITE_HOOK_FIXTURE").is_ok_and(|v| v == "1");
    let mut fixture: Value = std::fs::read(FIXTURE).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_else(|| json!({}));
    if write {
        // A post sealed by the route itself, to the fixed key, as a poster's would be.
        let h = Harness::new("hooks-fixture");
        let token = with_this_key(&h, "fixture", &secret).await;
        let (_, hook) = made(&h, &token, json!({ "name": "fixture", "note": "Groceries" })).await;
        let body = json!({ "text": "Pomegranate jam ✓, “quoted”, and a line\nbreak", "as": "item", "title": "From Rust" });
        assert_eq!(status_of(&h, post(&hook, Some("application/json"), body.to_string())).await.0, StatusCode::ACCEPTED);
        let item = inbox(&h, &token, None).await.remove(0);
        let hook_id = item["hook"].as_str().unwrap().to_string();
        fixture["about"] = json!("An incoming hook's seal across languages (server/src/hooks_tests.rs, hookSeal.test.ts): `rust` was sealed by glyph-api and opens with wrap.ts's unwrapWith; `typescript` was wrapped by wrapFor and opens in glyph-api. Both to `jwk`, in the context `hook:<hook>`.");
        fixture["jwk"] = jwk_of(&secret);
        fixture["public"] = json!(public_of(&secret));
        fixture["rust"] = json!({ "hook": hook_id, "context": context(&hook_id), "sealed": item["sealed"], "payload": opened(&secret, &item) });
        std::fs::write(FIXTURE, serde_json::to_string_pretty(&fixture).unwrap() + "\n").unwrap();
    }
    // The fixture's key is the fixed key, and the service's half opens with it here as wrap.ts opens it there.
    assert_eq!(fixture["jwk"], jwk_of(&secret), "run with GLYPH_WRITE_HOOK_FIXTURE=1 to write {FIXTURE}");
    assert_eq!(fixture["public"], json!(public_of(&secret)));
    let rust = &fixture["rust"];
    let opened_here: Value = serde_json::from_slice(&seal::unwrap_with(&secret, rust["sealed"].as_str().unwrap(), rust["context"].as_str().unwrap()).unwrap()).unwrap();
    assert_eq!(&opened_here, &rust["payload"]);
    assert_eq!(rust["context"], json!(context(rust["hook"].as_str().unwrap())));
    // wrap.ts's half: what `wrapFor` made, opened by the service's own ECIES.
    let typescript = &fixture["typescript"];
    if write && typescript.is_null() {
        return;
    }
    let sealed = typescript["sealed"].as_str().expect("the fixture has wrapFor's half: run hookSeal.test.ts with GLYPH_WRITE_HOOK_FIXTURE=1");
    let from_ts: Value = serde_json::from_slice(&seal::unwrap_with(&secret, sealed, typescript["context"].as_str().unwrap()).unwrap()).unwrap();
    assert_eq!(&from_ts, &typescript["payload"]);
    assert!(seal::unwrap_with(&secret, sealed, &context("another-hook")).is_err());
}
