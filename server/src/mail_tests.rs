//! Email to a note, through the routes a device and the mail provider call (docs/MAIL.md): an address turned on, made
//! anew and turned off; a mail posted with Mailgun's signature kept ONLY sealed, and opened with the account's private
//! key alone; and every refusal - a forged or replayed post, a dead address, too much mail, too large a mail.

use crate::accounts::Accounts;
use crate::mail::{mailgun_signature, message, seal, TEST_SIGNING_KEY};
use crate::store::Store;
use crate::test_support::{device, service, Harness, TempDir};
use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use serde_json::{json, Value};
use std::sync::Arc;

fn now() -> i64 {
    crate::wire::now_secs()
}

/// A field, form-encoded as Mailgun encodes one.
fn enc(s: &[u8]) -> String {
    s.iter().map(|&b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect()
}

/// What Mailgun posts for a mail to `recipient`, signed with `key` at `timestamp` with `token`.
fn post_with(recipient: &str, mime: &[u8], token: &str, timestamp: i64, key: &str) -> Request<Body> {
    let ts = timestamp.to_string();
    let signature = mailgun_signature(key, &ts, token);
    let body = format!(
        "recipient={}&sender={}&subject={}&body-mime={}&timestamp={ts}&token={}&signature={signature}",
        enc(recipient.as_bytes()),
        enc(b"sam@example.com"),
        enc(b"ignored"),
        enc(mime),
        enc(token.as_bytes())
    );
    Request::builder().method(Method::POST).uri("/api/v1/mail/inbound/mime").header(header::CONTENT_TYPE, "application/x-www-form-urlencoded").body(Body::from(body)).unwrap()
}

pub(crate) fn post(recipient: &str, mime: &[u8], token: &str) -> Request<Body> {
    post_with(recipient, mime, token, now(), TEST_SIGNING_KEY)
}

pub(crate) fn token(n: u32) -> String {
    format!("mailgun-token-{n:012}")
}

/// An account with its encryption key registered, as a device registers one; its token and its private key.
pub(crate) async fn with_key(h: &Harness, handle: &str) -> (String, p256::SecretKey) {
    let token = h.signup(handle, &device()).await;
    let secret = p256::SecretKey::random(&mut rand::rngs::OsRng);
    let public = URL_SAFE_NO_PAD.encode(secret.public_key().to_encoded_point(false).as_bytes());
    let (status, _) = h.call(Method::PUT, "/api/v1/account/key", Some(&token), Some(json!({ "pub": public, "sealed": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::CREATED);
    (token, secret)
}

/// The account's address turned on: the whole address.
pub(crate) async fn turned_on(h: &Harness, token: &str) -> String {
    let (status, body) = h.call(Method::POST, "/api/v1/mail/address", Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["address"].as_str().unwrap().to_string()
}

const MAIL: &str = "From: Sam <sam@example.com>\r\nSubject: Pomegranate jam\r\nDate: Fri, 16 Oct 2026 14:05:00 +0000\r\n\r\nThree jars of pomegranate jam for Saturday.\r\n";

#[tokio::test]
async fn an_address_is_turned_on_shown_made_anew_and_turned_off() {
    let h = Harness::new("mail");
    let (token, _) = with_key(&h, "sam").await;
    let (status, body) = h.call(Method::GET, "/api/v1/mail/address", Some(&token), None).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "address": null, "available": true })));
    let first = turned_on(&h, &token).await;
    let (local, domain) = first.split_once('@').unwrap();
    assert_eq!(domain, "in.ghostmarkdown.com");
    // A readable name, `sneaky_siren33` (Matt, 2026-10-23): words, an underscore, two digits.
    let (adjective, rest) = local.split_once('_').expect(local);
    let (noun, number) = rest.split_at(rest.len() - 2);
    assert!(adjective.bytes().all(|b| b.is_ascii_lowercase()) && noun.bytes().all(|b| b.is_ascii_lowercase()) && !noun.is_empty(), "{local}");
    assert!(number.bytes().all(|b| b.is_ascii_digit()), "{local}");
    let (_, body) = h.call(Method::GET, "/api/v1/mail/address", Some(&token), None).await;
    assert_eq!(body["address"], first.as_str());
    let second = turned_on(&h, &token).await;
    assert_ne!(first, second, "a new address");
    // The old one takes nothing from then on, and the sender is told.
    let (status, _, bytes) = h.send(post(&first, MAIL.as_bytes(), &token_n(1))).await;
    assert_eq!((status, serde_json::from_slice::<Value>(&bytes).unwrap()["error"].as_str()), (StatusCode::NOT_ACCEPTABLE, Some("There is no such address.")));
    let (status, _, _) = h.send(post(&second, MAIL.as_bytes(), &token_n(2))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = h.call(Method::DELETE, "/api/v1/mail/address", Some(&token), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, body) = h.call(Method::GET, "/api/v1/mail/address", Some(&token), None).await;
    assert_eq!(body["address"], Value::Null);
    let (status, _, _) = h.send(post(&second, MAIL.as_bytes(), &token_n(3))).await;
    assert_eq!(status, StatusCode::NOT_ACCEPTABLE, "off is off");
    // What came while it was on still waits for a device.
    let (_, body) = h.call(Method::GET, "/api/v1/mail", Some(&token), None).await;
    assert_eq!(body["mail"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn an_address_made_before_the_readable_names_still_takes_mail() {
    let h = Harness::new("mail");
    let (token, _) = with_key(&h, "sam").await;
    let readable = turned_on(&h, &token).await;
    let account = h.accounts.store.mail_account(readable.split('@').next().unwrap()).unwrap();
    // As the store holds an address given out before 2026-10-23: sixteen base32 letters and digits.
    h.accounts.store.set_mail_address(account, "k7m2q3xh4t5vbn6p", 0).unwrap();
    let (status, _, _) = h.send(post("Ghost <K7M2Q3XH4T5VBN6P@in.ghostmarkdown.com>", MAIL.as_bytes(), &token_n(1))).await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = h.call(Method::GET, "/api/v1/mail", Some(&token), None).await;
    assert_eq!(body["mail"].as_array().unwrap().len(), 1);
}

fn token_n(n: u32) -> String {
    token(n)
}

#[tokio::test]
async fn an_address_needs_the_account_s_encryption_key_to_seal_to() {
    let h = Harness::new("mail");
    let token = h.signup("sam", &device()).await;
    let (status, body) = h.call(Method::POST, "/api/v1/mail/address", Some(&token), None).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "Your account needs its encryption key first. Sync once, then try again." })));
    let (status, _) = h.call(Method::POST, "/api/v1/mail/address", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn a_mail_is_kept_only_sealed_and_opens_with_the_account_s_private_key_alone() {
    let h = Harness::new("mail");
    let (token, secret) = with_key(&h, "sam").await;
    let address = turned_on(&h, &token).await;
    let (status, _, bytes) = h.send(post(&format!("Ghost <{}>", address.to_uppercase()), MAIL.as_bytes(), &token_n(1))).await;
    assert_eq!(status, StatusCode::OK, "{}", String::from_utf8_lossy(&bytes));
    let (status, body) = h.call(Method::GET, "/api/v1/mail", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let waiting = body["mail"].as_array().unwrap();
    assert_eq!(waiting.len(), 1);
    let id = waiting[0]["id"].as_str().unwrap().to_string();
    assert!(waiting[0]["at"].as_i64().unwrap() > 1_700_000_000_000);
    let (status, sealed) = h.call(Method::GET, &format!("/api/v1/mail/{id}"), Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let (wrapped, blob) = (sealed["wrapped"].as_str().unwrap(), sealed["blob"].as_str().unwrap());
    assert!(!blob.contains("omegranate") && !wrapped.contains("omegranate"));
    let (head, _) = message::read(&seal::open_with(&secret, &id, wrapped, blob).unwrap());
    assert_eq!((head["subject"].as_str(), head["from"].as_str()), (Some("Pomegranate jam"), Some("Sam <sam@example.com>")));
    assert!(head["body"].as_str().unwrap().contains("Three jars of pomegranate jam"));
    assert_eq!(head["to"].as_str(), Some(address.as_str()));
    let other = p256::SecretKey::random(&mut rand::rngs::OsRng);
    assert!(seal::open_with(&other, &id, wrapped, blob).is_err(), "no key but the account's opens it");
    // Another account can neither read nor take it.
    let (stranger, _) = with_key(&h, "ali").await;
    let (status, _) = h.call(Method::GET, &format!("/api/v1/mail/{id}"), Some(&stranger), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    h.call(Method::DELETE, &format!("/api/v1/mail/{id}"), Some(&stranger), None).await;
    let (_, body) = h.call(Method::GET, "/api/v1/mail", Some(&token), None).await;
    assert_eq!(body["mail"].as_array().unwrap().len(), 1);
    // Filed: taken.
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/mail/{id}"), Some(&token), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, body) = h.call(Method::GET, "/api/v1/mail", Some(&token), None).await;
    assert_eq!(body["mail"], json!([]));
}

/// The promise in the setting's words, held to the database's own files: not a word of a mail is in them, on disk,
/// while it waits sealed.
#[tokio::test]
async fn not_a_word_of_a_mail_reaches_the_service_s_files() {
    let dir = TempDir::new("mail-disk");
    let data = dir.path().join("glyph-api");
    let h = Harness { service: service(Some(Accounts::new(Arc::new(Store::open(&data).unwrap())))), accounts: Accounts::new(Arc::new(Store::open(&data).unwrap())), dir: TempDir::new("mail-disk-unused") };
    let (token, secret) = with_key(&h, "sam").await;
    let address = turned_on(&h, &token).await;
    let (status, _, _) = h.send(post(&address, MAIL.as_bytes(), &token_n(1))).await;
    assert_eq!(status, StatusCode::OK);
    let mut seen = Vec::new();
    for entry in std::fs::read_dir(&data).unwrap() {
        let path = entry.unwrap().path();
        if path.is_file() {
            seen.extend(std::fs::read(&path).unwrap());
        }
    }
    assert!(!seen.is_empty());
    let text = String::from_utf8_lossy(&seen).to_lowercase();
    for word in ["pomegranate", "three jars", "saturday", "sam@example.com"] {
        assert!(!text.contains(word), "{word:?} is in the service's files");
    }
    // And yet it is all there, for the account's key.
    let (_, body) = h.call(Method::GET, "/api/v1/mail", Some(&token), None).await;
    let id = body["mail"][0]["id"].as_str().unwrap().to_string();
    let (_, sealed) = h.call(Method::GET, &format!("/api/v1/mail/{id}"), Some(&token), None).await;
    let (head, _) = message::read(&seal::open_with(&secret, &id, sealed["wrapped"].as_str().unwrap(), sealed["blob"].as_str().unwrap()).unwrap());
    assert_eq!(head["subject"], "Pomegranate jam");
}

#[tokio::test]
async fn a_post_not_signed_with_the_provider_s_key_or_too_old_or_seen_before_is_refused() {
    let h = Harness::new("mail");
    let (token, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &token).await;
    let (status, _, _) = h.send(post_with(&address, MAIL.as_bytes(), &token_n(1), now(), "key-someone-else-entirely-000")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _, _) = h.send(post_with(&address, MAIL.as_bytes(), &token_n(2), now() - 10 * 3600, TEST_SIGNING_KEY)).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "a signature from ten hours ago");
    let (status, _, _) = h.send(post(&address, MAIL.as_bytes(), &token_n(3))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _, bytes) = h.send(post(&address, MAIL.as_bytes(), &token_n(3))).await;
    assert_eq!((status, serde_json::from_slice::<Value>(&bytes).unwrap()["error"].as_str()), (StatusCode::NOT_ACCEPTABLE, Some("That mail was taken already.")));
    let garbage = Request::builder().method(Method::POST).uri("/api/v1/mail/inbound/mime").body(Body::from("hello")).unwrap();
    let (status, _, _) = h.send(garbage).await;
    assert_eq!(status, StatusCode::NOT_ACCEPTABLE);
    let (_, body) = h.call(Method::GET, "/api/v1/mail", Some(&token), None).await;
    assert_eq!(body["mail"].as_array().unwrap().len(), 1, "only the one signed, fresh, first-time post was kept");
}

#[tokio::test]
async fn an_address_takes_thirty_mails_an_hour_and_the_provider_is_told_to_try_again() {
    let h = Harness::new("mail");
    let (token, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &token).await;
    let small = "Subject: hi\r\n\r\nhi\r\n";
    for i in 0..30 {
        let (status, _, _) = h.send(post(&address, small.as_bytes(), &token_n(100 + i))).await;
        assert_eq!(status, StatusCode::OK, "mail {i}");
    }
    let (status, _, _) = h.send(post(&address, small.as_bytes(), &token_n(200))).await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "tried again later, not dropped");
    // The refused post's token was not spent: the same post, later, is still taken (a second address shows the
    // bucket is the address's, not the service's).
    let (other, _) = with_key(&h, "ali").await;
    let theirs = turned_on(&h, &other).await;
    let (status, _, _) = h.send(post(&theirs, small.as_bytes(), &token_n(200))).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn a_mail_past_ten_megabytes_is_refused_and_one_under_is_taken() {
    let h = Harness::new("mail");
    let (token, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &token).await;
    let big = format!("Subject: big\r\n\r\n{}", "a".repeat(crate::mail::MAIL_LIMIT));
    let (status, _, bytes) = h.send(post(&address, big.as_bytes(), &token_n(1))).await;
    assert_eq!((status, serde_json::from_slice::<Value>(&bytes).unwrap()["error"].as_str()), (StatusCode::NOT_ACCEPTABLE, Some("That mail is too large: Ghost.md takes mail up to 10 MB.")));
    let under = format!("Subject: under\r\n\r\n{}", "a".repeat(2_000_000));
    let (status, _, _) = h.send(post(&address, under.as_bytes(), &token_n(2))).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn an_account_keeps_two_hundred_mails_waiting_and_the_two_hundred_and_first_bounces() {
    let h = Harness::new("mail");
    let (token, _) = with_key(&h, "sam").await;
    let address = turned_on(&h, &token).await;
    let account = h.accounts.store.mail_account(address.split('@').next().unwrap()).unwrap();
    for i in 0..200 {
        let sealed = crate::store::SealedMail { wrapped: "dw".into(), blob: "Yg".into(), at: i };
        h.accounts.store.put_mail(account, &format!("seeded-{i}"), &sealed, 200).unwrap();
    }
    let (status, _, bytes) = h.send(post(&address, MAIL.as_bytes(), &token_n(1))).await;
    assert_eq!(
        (status, serde_json::from_slice::<Value>(&bytes).unwrap()["error"].as_str()),
        (StatusCode::NOT_ACCEPTABLE, Some("That mailbox is full: its owner's devices have not synced for a while."))
    );
}

/// The sealed mail the app's own code opens (test/mail/sealed_mail_test.dart, over the Rust core's `unwrap_with`,
/// `seal_key_import` and `open`): written by this service's own sealing when `GLYPH_MAIL_FIXTURE` names where, and
/// otherwise checked to open still, so the two sides cannot drift apart unseen.
#[test]
fn the_sealed_mail_the_app_opens() {
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../test/mail/fixtures/sealed_mail.json");
    if let Ok(out) = std::env::var("GLYPH_MAIL_FIXTURE") {
        let secret = p256::SecretKey::random(&mut rand::rngs::OsRng);
        let point = secret.public_key().to_encoded_point(false);
        let public = URL_SAFE_NO_PAD.encode(point.as_bytes());
        let jwk = json!({
            "kty": "EC", "crv": "P-256", "ext": true, "key_ops": ["deriveBits"],
            "x": URL_SAFE_NO_PAD.encode(point.x().unwrap()), "y": URL_SAFE_NO_PAD.encode(point.y().unwrap()),
            "d": URL_SAFE_NO_PAD.encode(secret.to_bytes()),
        });
        let id = crate::wire::fresh_id();
        let payload = message::payload(message::tests::MAIL.as_bytes(), "k7m2q9xh4t3vbn8p@in.ghostmarkdown.com", 0).unwrap();
        let (wrapped, blob) = seal::seal_for(&public, &id, &payload).unwrap();
        let written = json!({ "about": "A mail sealed by server/src/mail/seal.rs for a made-up account (mail_tests.rs). The private key is that account's and nobody's else.", "jwk": jwk, "pub": public, "id": id, "wrapped": wrapped, "blob": blob });
        std::fs::write(out, serde_json::to_string_pretty(&written).unwrap() + "\n").unwrap();
        return;
    }
    let Ok(text) = std::fs::read_to_string(&fixture) else {
        // A copy of server/ alone (tool/local-server.sh builds one) has no app beside it.
        eprintln!("no fixture at {}", fixture.display());
        return;
    };
    let kept: Value = serde_json::from_str(&text).unwrap();
    let d = URL_SAFE_NO_PAD.decode(kept["jwk"]["d"].as_str().unwrap()).unwrap();
    let secret = p256::SecretKey::from_slice(&d).unwrap();
    let id = kept["id"].as_str().unwrap();
    let (head, files) = message::read(&seal::open_with(&secret, id, kept["wrapped"].as_str().unwrap(), kept["blob"].as_str().unwrap()).unwrap());
    assert_eq!(head["subject"], "Café plans");
    assert_eq!(files.len(), 2);
}
