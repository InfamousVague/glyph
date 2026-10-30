//! Forms from a share link, through the routes a device and a visitor's browser call (docs/FORMS.md): a share made a
//! form, opened, answered and filed; an answer kept ONLY sealed, to every recipient, and opened with a recipient's
//! private key alone; every refusal - a body with a clear field, a blob or a wrap not shaped as a seal, a wrap to a
//! stranger, a form paused or closed, too large, too soon, too many from one address - and the hidden field; the claim
//! that lets one device alone file an answer, the ack that files it once, and the thirty days an answer waits.

use crate::forms::{seal_context, ticket_for, wrap_context, ANSWERS_PER_ADDRESS_PER_HOUR, ANSWER_LIMIT, CLAIM_FOR, KEPT_FOR, WAITING};
use crate::mail::seal;
use crate::store::{FormItem, FormState};
use crate::test_support::{device, Harness};
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
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

/// An account with a fresh encryption key registered: its token, its private key and its public one.
async fn with_key(h: &Harness, handle: &str) -> (String, p256::SecretKey, String) {
    let token = h.signup(handle, &device()).await;
    let secret = p256::SecretKey::random(&mut rand::rngs::OsRng);
    let (status, _) = h.call(Method::PUT, "/api/v1/account/key", Some(&token), Some(json!({ "pub": public_of(&secret), "sealed": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::CREATED);
    let public = public_of(&secret);
    (token, secret, public)
}

/// A share of the account's made a form through the routes; its id.
async fn a_form(h: &Harness, token: &str, id: &str, body: Value) -> Value {
    let (status, _) = h.call(Method::PUT, &format!("/api/v1/shares/{id}"), Some(token), Some(json!({ "blob": "c2VhbGVkLXNoYXJl" }))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, form) = h.call(Method::PUT, &format!("/api/v1/forms/{id}"), Some(token), Some(body)).await;
    assert_eq!(status, StatusCode::OK, "{form}");
    form
}

const FORM: &str = "Zm9ybS1vbmUtc2hhcmUtaWQ";

/// A ticket for `form`, as `GET /api/forms/{id}` would have handed one out `ago` seconds since.
fn ticket(h: &Harness, form: &str, ago: i64) -> String {
    let key = URL_SAFE_NO_PAD.decode(h.accounts.store.meta("form-ticket-key").unwrap()).unwrap();
    ticket_for(&key, form, now() - ago)
}

/// What a visitor's browser sends: `answers` sealed under a fresh key, that key wrapped to each of `to`.
fn sealed(form: &str, answer: &str, to: &[String], answers: &Value) -> (Vec<Value>, String) {
    let key: [u8; 32] = rand::random();
    let iv: [u8; 12] = rand::random();
    let context = seal_context(form, answer);
    let mut blob = vec![1u8];
    blob.extend_from_slice(&iv);
    blob.extend(Aes256Gcm::new((&key).into()).encrypt(Nonce::from_slice(&iv), Payload { msg: answers.to_string().as_bytes(), aad: context.as_bytes() }).unwrap());
    let wraps = to.iter().map(|public| json!({ "to": public, "wrap": seal::wrap_for(public, &key, &wrap_context(form, answer)).unwrap() })).collect();
    (wraps, URL_SAFE_NO_PAD.encode(blob))
}

/// An answer opened as a device opens it: its key out of the wrap made to `secret`'s public key, then the blob.
fn opened(secret: &p256::SecretKey, item: &Value) -> Value {
    let (form, answer) = (item["form"].as_str().unwrap(), item["id"].as_str().unwrap());
    let mine = public_of(secret);
    let wrap = item["wraps"].as_array().unwrap().iter().find(|w| w["to"] == mine.as_str()).expect("a wrap made to this key");
    let key = seal::unwrap_with(secret, wrap["wrap"].as_str().unwrap(), &wrap_context(form, answer)).unwrap();
    let blob = URL_SAFE_NO_PAD.decode(item["blob"].as_str().unwrap()).unwrap();
    let clear = Aes256Gcm::new(key.as_slice().into()).decrypt(Nonce::from_slice(&blob[1..13]), Payload { msg: &blob[13..], aad: seal_context(form, answer).as_bytes() }).unwrap();
    serde_json::from_slice(&clear).unwrap()
}

/// A visitor's request to the public route, from `address`.
fn visit(method: Method, form: &str, address: &str, body: Option<Value>) -> Request<Body> {
    let request = Request::builder().method(method).uri(format!("/api/forms/{form}")).header("x-forwarded-for", address);
    match body {
        Some(body) => request.header(header::CONTENT_TYPE, "application/json").body(Body::from(body.to_string())).unwrap(),
        None => request.body(Body::empty()).unwrap(),
    }
}

async fn sent(h: &Harness, request: Request<Body>) -> (StatusCode, Value) {
    let (status, _, bytes) = h.send(request).await;
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// An answer to `form` sealed to `to`, sent from `address` with a ticket three seconds and more old.
async fn answer(h: &Harness, form: &str, address: &str, id: &str, to: &[String], answers: Value) -> (StatusCode, Value) {
    let (wraps, blob) = sealed(form, id, to, &answers);
    sent(h, visit(Method::POST, form, address, Some(json!({ "id": id, "ticket": ticket(h, form, 10), "wraps": wraps, "blob": blob })))).await
}

async fn inbox(h: &Harness, token: &str) -> Vec<Value> {
    let (status, body) = h.call(Method::GET, "/api/v1/forms/inbox", Some(token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body.as_array().unwrap().clone()
}

fn answer_id(n: u32) -> String {
    format!("answer-{n:0>16}")
}

#[tokio::test]
async fn a_share_is_made_a_form_by_its_owner_alone_and_listed_with_its_counts() {
    let h = Harness::new("forms");
    let keyless = h.signup("lee", &device()).await;
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/shares/{FORM}"), Some(&keyless), Some(json!({ "blob": "c2hhcmU" }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/forms/{FORM}"), Some(&keyless), Some(json!({ "state": "open" }))).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "This account has no encryption key yet." })));

    let (sam, _, _) = with_key(&h, "sam").await;
    let (status, _) = h.call(Method::PUT, "/api/v1/forms/bm8tc3VjaC1zaGFyZS1oZXJl", Some(&sam), Some(json!({ "state": "open" }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "share it first");
    let (status, _) = h.call(Method::PUT, &format!("/api/v1/forms/{FORM}"), Some(&sam), Some(json!({ "state": "open" }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "another's share is not this account's to make a form");
    let (status, _) = h.call(Method::PUT, "/api/v1/forms/c2FtLXNoYXJlLWlkLTAwMDAx", Some(&sam), Some(json!({ "state": "ajar" }))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let form = a_form(&h, &sam, "c2FtLXNoYXJlLWlkLTAwMDAx", json!({ "state": "open" })).await;
    assert_eq!((form["state"].as_str(), form["files"].as_bool(), form["received"].as_i64(), form["mine"].as_bool()), (Some("open"), Some(false), Some(0), Some(true)));
    let (_, list) = h.call(Method::GET, "/api/v1/forms", Some(&sam), None).await;
    assert_eq!(list["forms"].as_array().unwrap().len(), 1);
    let (_, theirs) = h.call(Method::GET, "/api/v1/forms", Some(&keyless), None).await;
    assert_eq!(theirs["forms"], json!([]));
    let (status, _) = h.call(Method::GET, "/api/v1/forms", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn an_answer_is_kept_only_sealed_and_opens_with_the_owner_s_key_alone() {
    let h = Harness::new("forms");
    let (sam, secret, public) = with_key(&h, "sam").await;
    a_form(&h, &sam, FORM, json!({ "note": "6f1c-note-id", "files": false })).await;

    // The link: open, the one key to seal to, and a ticket.
    let (status, opened_form) = sent(&h, visit(Method::GET, FORM, "203.0.113.1", None)).await;
    assert_eq!(status, StatusCode::OK, "{opened_form}");
    assert_eq!((opened_form["state"].as_str(), opened_form["keys"].clone(), opened_form["wait"].as_i64()), (Some("open"), json!([public]), Some(3)));
    assert!(opened_form["ticket"].is_string());

    let answers = json!({ "Summary": "The app crashes on launch", "Email": "ana@example.com" });
    let (status, body) = answer(&h, FORM, "203.0.113.1", &answer_id(1), std::slice::from_ref(&public), answers.clone()).await;
    assert_eq!((status, body), (StatusCode::ACCEPTED, json!({ "id": answer_id(1) })));
    let items = inbox(&h, &sam).await;
    assert_eq!(items.len(), 1);
    assert_eq!((items[0]["form"].as_str(), items[0]["note"].as_str(), items[0]["claimed"].as_bool()), (Some(FORM), Some("6f1c-note-id"), Some(false)), "open with no state said, and its note named");
    assert_eq!(opened(&secret, &items[0]), answers);
    // Nothing of the answer is anywhere the service keeps it in the clear.
    let kept = format!("{:?}", h.accounts.store.form_inbox(1, None, 10, 0, 0)) + &format!("{:?}", h.accounts.store.forms_for(1, 0));
    for word in ["crashes", "ana@example.com", "Summary"] {
        assert!(!kept.contains(word), "{word} in {kept}");
    }
    // Nobody else reads or files it.
    let (ali, other, _) = with_key(&h, "ali").await;
    assert!(inbox(&h, &ali).await.is_empty());
    let mine = public_of(&other);
    let wrap = items[0]["wraps"][0]["wrap"].as_str().unwrap();
    assert!(seal::unwrap_with(&other, wrap, &wrap_context(FORM, &answer_id(1))).is_err(), "{mine}'s key opens nothing");
    assert!(seal::unwrap_with(&secret, wrap, &wrap_context("another-form", &answer_id(1))).is_err(), "nor in another form's context");
    let (_, list) = h.call(Method::GET, "/api/v1/forms", Some(&sam), None).await;
    assert_eq!((list["forms"][0]["received"].as_i64(), list["forms"][0]["waiting"].as_i64()), (Some(1), Some(1)));
}

#[tokio::test]
async fn only_a_seal_is_taken_never_a_clear_answer() {
    let h = Harness::new("forms");
    let (sam, _, public) = with_key(&h, "sam").await;
    a_form(&h, &sam, FORM, json!({ "state": "open" })).await;
    let (wraps, blob) = sealed(FORM, &answer_id(1), std::slice::from_ref(&public), &json!({ "Summary": "x" }));
    let good = json!({ "id": answer_id(1), "ticket": ticket(&h, FORM, 10), "wraps": wraps, "blob": blob });
    let with = |key: &str, value: Value| {
        let mut body = good.clone();
        body[key] = value;
        body
    };
    let (_, stranger, _) = with_key(&h, "ali").await;
    let clear = URL_SAFE_NO_PAD.encode(b"\x01 the summary in the clear, not sealed");
    for (bad, why) in [
        (with("answers", json!({ "Summary": "in the clear" })), "a field beside the seal"),
        (with("blob", json!("{\"Summary\":\"x\"}")), "a blob that is not base64url"),
        (with("blob", json!(URL_SAFE_NO_PAD.encode(b"\x02 not sealBytes"))), "a blob without the version byte"),
        (with("blob", json!("AQ")), "a blob too short to be sealed"),
        (with("wraps", json!([])), "no wraps"),
        (with("wraps", json!([{ "to": public, "wrap": "A".repeat(167) }])), "a wrap with no point on the curve"),
        (with("wraps", json!([{ "to": public, "wrap": clear }])), "a wrap of the wrong length"),
        (with("wraps", json!([{ "to": public, "wrap": good["wraps"][0]["wrap"], "note": "clear" }])), "a field beside a wrap"),
        (with("id", json!("short")), "an id too short"),
    ] {
        let (status, body) = sent(&h, visit(Method::POST, FORM, "203.0.113.2", Some(bad))).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{why}: {body}");
    }
    let to_stranger = with("wraps", json!([{ "to": public_of(&stranger), "wrap": good["wraps"][0]["wrap"] }]));
    let (status, _) = sent(&h, visit(Method::POST, FORM, "203.0.113.2", Some(to_stranger))).await;
    assert_eq!(status, StatusCode::CONFLICT, "a wrap to a key that is not the form's");
    assert!(inbox(&h, &sam).await.is_empty(), "nothing kept");
    let (status, _) = sent(&h, visit(Method::POST, FORM, "203.0.113.2", Some(good.clone()))).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    let (status, _) = sent(&h, visit(Method::POST, FORM, "203.0.113.2", Some(good))).await;
    assert_eq!(status, StatusCode::ACCEPTED, "the same send again");
    assert_eq!(inbox(&h, &sam).await.len(), 1, "kept once");
}

#[tokio::test]
async fn the_hidden_field_and_the_ticket_turn_bots_away() {
    let h = Harness::new("forms");
    let (sam, _, public) = with_key(&h, "sam").await;
    a_form(&h, &sam, FORM, json!({ "state": "open" })).await;
    let (wraps, blob) = sealed(FORM, &answer_id(1), std::slice::from_ref(&public), &json!({ "Summary": "x" }));
    let body = |ticket: String, hp: &str| json!({ "id": answer_id(1), "ticket": ticket, "wraps": wraps, "blob": blob, "hp": hp });
    let (status, said) = sent(&h, visit(Method::POST, FORM, "203.0.113.3", Some(body(ticket(&h, FORM, 10), "http://spam.example")))).await;
    assert_eq!((status, said), (StatusCode::ACCEPTED, json!({ "id": answer_id(1) })), "told what a person is told");
    assert!(inbox(&h, &sam).await.is_empty(), "and nothing kept");
    let (status, _) = sent(&h, visit(Method::POST, FORM, "203.0.113.3", Some(body(ticket(&h, FORM, 0), "")))).await;
    assert_eq!(status.as_u16(), 425, "sent the moment it was opened");
    let (status, _) = sent(&h, visit(Method::POST, FORM, "203.0.113.3", Some(body(ticket(&h, FORM, 25 * 3600), "")))).await;
    assert_eq!(status, StatusCode::CONFLICT, "a day old");
    let (status, _) = sent(&h, visit(Method::POST, FORM, "203.0.113.3", Some(body(ticket(&h, "c29tZS1vdGhlci1mb3JtLWlk", 10), "")))).await;
    assert_eq!(status, StatusCode::CONFLICT, "another form's ticket");
    let (status, _) = sent(&h, visit(Method::POST, FORM, "203.0.113.3", Some(body("Zm9yZ2Vk".into(), "")))).await;
    assert_eq!(status, StatusCode::CONFLICT, "one made up");
    assert!(inbox(&h, &sam).await.is_empty());
    let (status, _) = sent(&h, visit(Method::POST, FORM, "203.0.113.3", Some(body(ticket(&h, FORM, 10), "  ")))).await;
    assert_eq!(status, StatusCode::ACCEPTED, "a blank hidden field is a person's");
    assert_eq!(inbox(&h, &sam).await.len(), 1);
}

#[tokio::test]
async fn answers_are_limited_per_address_and_in_size_and_a_full_form_says_so() {
    let h = Harness::new("forms");
    let (sam, _, public) = with_key(&h, "sam").await;
    a_form(&h, &sam, FORM, json!({ "state": "open" })).await;
    let to = std::slice::from_ref(&public);
    for n in 0..ANSWERS_PER_ADDRESS_PER_HOUR {
        let (status, body) = answer(&h, FORM, "198.51.100.7", &answer_id(n), to, json!({ "n": n })).await;
        assert_eq!(status, StatusCode::ACCEPTED, "{n}: {body}");
    }
    let (status, _) = answer(&h, FORM, "198.51.100.7", &answer_id(99), to, json!({})).await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "that address's hour is spent");
    let (status, _) = answer(&h, FORM, "198.51.100.8", &answer_id(99), to, json!({})).await;
    assert_eq!(status, StatusCode::ACCEPTED, "another address is not");

    // Too large: past the limit for a form with no file.
    let big = json!({ "Details": "x".repeat(ANSWER_LIMIT) });
    let (status, _) = answer(&h, FORM, "198.51.100.9", &answer_id(100), to, big.clone()).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    // A form that takes a file takes it.
    a_form(&h, &sam, FORM, json!({ "state": "open", "files": true })).await;
    let (status, _) = answer(&h, FORM, "198.51.100.9", &answer_id(100), to, big).await;
    assert_eq!(status, StatusCode::ACCEPTED);

    // Full: as many waiting as a form keeps (seeded through the store).
    let other = "ZnVsbC1mb3JtLXNoYXJlLWlk";
    a_form(&h, &sam, other, json!({ "state": "open" })).await;
    for n in 0..WAITING {
        h.accounts.store.put_form_item(&FormItem { id: answer_id(1000 + n as u32), form: other.into(), note: None, wraps: "[]".into(), blob: "b".into(), at: now(), claimed: false }, WAITING, 0).unwrap();
    }
    let (status, _) = answer(&h, other, "198.51.100.10", &answer_id(9999), to, json!({})).await;
    assert_eq!(status, StatusCode::INSUFFICIENT_STORAGE);
}

#[tokio::test]
async fn a_paused_or_closed_form_says_so_and_takes_nothing() {
    let h = Harness::new("forms");
    let (sam, _, public) = with_key(&h, "sam").await;
    a_form(&h, &sam, FORM, json!({ "state": "open" })).await;
    let (ali, _, _) = with_key(&h, "ali").await;
    let (status, _) = h.call(Method::POST, &format!("/api/v1/forms/{FORM}/state"), Some(&ali), Some(json!({ "state": "closed" }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "not another's to close");

    let (status, form) = h.call(Method::POST, &format!("/api/v1/forms/{FORM}/state"), Some(&sam), Some(json!({ "state": "paused" }))).await;
    assert_eq!((status, form["state"].as_str()), (StatusCode::OK, Some("paused")));
    let again = a_form(&h, &sam, FORM, json!({ "org": null, "files": true })).await;
    assert_eq!(again["state"].as_str(), Some("paused"), "a device saying the form again does not reopen it");
    let (status, read) = sent(&h, visit(Method::GET, FORM, "192.0.2.1", None)).await;
    assert_eq!((status, read), (StatusCode::OK, json!({ "state": "paused" })), "no keys, no ticket");
    let (status, _) = answer(&h, FORM, "192.0.2.1", &answer_id(1), std::slice::from_ref(&public), json!({})).await;
    assert_eq!(status, StatusCode::LOCKED);

    h.call(Method::POST, &format!("/api/v1/forms/{FORM}/state"), Some(&sam), Some(json!({ "state": "closed" }))).await;
    assert_eq!(sent(&h, visit(Method::GET, FORM, "192.0.2.1", None)).await.1, json!({ "state": "closed" }));
    let (status, _) = answer(&h, FORM, "192.0.2.1", &answer_id(2), std::slice::from_ref(&public), json!({})).await;
    assert_eq!(status, StatusCode::GONE);
    assert!(inbox(&h, &sam).await.is_empty());

    // Taken down: the link reads nothing.
    h.call(Method::DELETE, &format!("/api/v1/shares/{FORM}"), Some(&sam), None).await;
    assert_eq!(sent(&h, visit(Method::GET, FORM, "192.0.2.1", None)).await.0, StatusCode::NOT_FOUND);
    assert_eq!(sent(&h, visit(Method::GET, "bm90LWEtZm9ybS1hdC1hbGwx", "192.0.2.1", None)).await.0, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn one_device_files_an_answer_and_it_is_filed_once() {
    let h = Harness::new("forms");
    let (sam, _, public) = with_key(&h, "sam").await;
    a_form(&h, &sam, FORM, json!({ "state": "open" })).await;
    answer(&h, FORM, "203.0.113.4", &answer_id(1), std::slice::from_ref(&public), json!({ "Summary": "x" })).await;
    let id = answer_id(1);
    let claim = |device: &str| json!({ "device": device });
    let (status, held) = h.call(Method::POST, &format!("/api/v1/forms/inbox/{id}/claim"), Some(&sam), Some(claim("phone"))).await;
    assert_eq!(status, StatusCode::OK, "{held}");
    let until = held["until"].as_i64().unwrap();
    assert!((until - (now() + CLAIM_FOR) * 1000).abs() < 5_000, "two minutes on, in ms");
    // The account's other device, at the same time: refused while the phone holds it.
    let (status, _) = h.call(Method::POST, &format!("/api/v1/forms/inbox/{id}/claim"), Some(&sam), Some(claim("mac"))).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(inbox(&h, &sam).await[0]["claimed"], json!(true));
    let (status, _) = h.call(Method::POST, &format!("/api/v1/forms/inbox/{id}/claim"), Some(&sam), Some(claim("phone"))).await;
    assert_eq!(status, StatusCode::OK, "the phone again holds it again");
    // Another account cannot claim or file it.
    let (ali, _, _) = with_key(&h, "ali").await;
    let (status, _) = h.call(Method::POST, &format!("/api/v1/forms/inbox/{id}/claim"), Some(&ali), Some(claim("theirs"))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    h.call(Method::DELETE, &format!("/api/v1/forms/inbox/{id}"), Some(&ali), None).await;
    assert_eq!(inbox(&h, &sam).await.len(), 1);
    // Filed: gone, and counted.
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/forms/inbox/{id}"), Some(&sam), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert!(inbox(&h, &sam).await.is_empty());
    let (status, _) = h.call(Method::POST, &format!("/api/v1/forms/inbox/{id}/claim"), Some(&sam), Some(claim("mac"))).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "nothing left for the Mac to file");
    let (_, list) = h.call(Method::GET, "/api/v1/forms", Some(&sam), None).await;
    assert_eq!((list["forms"][0]["received"].as_i64(), list["forms"][0]["waiting"].as_i64(), list["forms"][0]["filed"].as_i64()), (Some(1), Some(0), Some(1)));
    // A claim the phone made and then left: the Mac takes it once it lapses (through the store, two minutes on).
    answer(&h, FORM, "203.0.113.4", &answer_id(2), std::slice::from_ref(&public), json!({})).await;
    h.call(Method::POST, &format!("/api/v1/forms/inbox/{}/claim", answer_id(2)), Some(&sam), Some(claim("phone"))).await;
    let later = now() + CLAIM_FOR + 1;
    assert_eq!(h.accounts.store.claim_form_item(1, &answer_id(2), "mac", later, CLAIM_FOR), crate::store::FormClaim::Held(later + CLAIM_FOR));
}

#[tokio::test]
async fn a_team_s_form_is_sealed_to_every_member_and_any_of_them_files_it() {
    let h = Harness::new("forms");
    let (sam, sam_secret, sam_public) = with_key(&h, "sam").await;
    let (ali, ali_secret, ali_public) = with_key(&h, "ali").await;
    let (lee, _, _) = with_key(&h, "lee").await;
    let (_, org) = h.call(Method::POST, "/api/v1/orgs", Some(&sam), Some(json!({ "name": "Ghost" }))).await;
    let org = org["org"]["id"].as_str().unwrap().to_string();
    h.call(Method::POST, &format!("/api/v1/orgs/{org}/members"), Some(&sam), Some(json!({ "handle": "ali" }))).await;
    h.call(Method::POST, &format!("/api/v1/orgs/{org}/invite"), Some(&ali), Some(json!({ "accept": true }))).await;
    // Not a member: lee cannot make a form the team's.
    let (status, _) = h.call(Method::PUT, &format!("/api/v1/shares/{FORM}"), Some(&lee), Some(json!({ "blob": "c2hhcmU" }))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = h.call(Method::PUT, &format!("/api/v1/forms/{FORM}"), Some(&lee), Some(json!({ "state": "open", "org": org }))).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let team = "dGVhbS1mb3JtLXNoYXJlLWlk";
    let form = a_form(&h, &sam, team, json!({ "state": "open", "org": org })).await;
    assert_eq!(form["org"].as_str(), Some(org.as_str()));
    let (_, read) = sent(&h, visit(Method::GET, team, "203.0.113.5", None)).await;
    assert_eq!(read["keys"], json!([sam_public, ali_public]), "every member with a key, the owner first");
    let answers = json!({ "Request": "Dark mode for the reader" });
    let (status, _) = answer(&h, team, "203.0.113.5", &answer_id(1), &[sam_public.clone(), ali_public.clone()], answers.clone()).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    // Either member opens it with their own key, and either may file it.
    let for_ali = inbox(&h, &ali).await;
    assert_eq!(opened(&ali_secret, &for_ali[0]), answers);
    assert_eq!(opened(&sam_secret, &inbox(&h, &sam).await[0]), answers);
    assert!(inbox(&h, &lee).await.is_empty(), "nor anyone outside it");
    let (_, list) = h.call(Method::GET, "/api/v1/forms", Some(&ali), None).await;
    assert_eq!((list["forms"][0]["mine"].as_bool(), list["forms"].as_array().unwrap().len()), (Some(false), 1));
    let (status, _) = h.call(Method::POST, &format!("/api/v1/forms/inbox/{}/claim", answer_id(1)), Some(&ali), Some(json!({ "device": "alis-phone" }))).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = h.call(Method::POST, &format!("/api/v1/forms/inbox/{}/claim", answer_id(1)), Some(&sam), Some(json!({ "device": "sams-mac" }))).await;
    assert_eq!(status, StatusCode::CONFLICT, "one member at a time");
    h.call(Method::DELETE, &format!("/api/v1/forms/inbox/{}", answer_id(1)), Some(&ali), None).await;
    assert!(inbox(&h, &sam).await.is_empty(), "filed for the whole team");
    // A member may pause it; only its owner deletes it.
    let (status, _) = h.call(Method::POST, &format!("/api/v1/forms/{team}/state"), Some(&ali), Some(json!({ "state": "paused" }))).await;
    assert_eq!(status, StatusCode::OK);
    h.call(Method::DELETE, &format!("/api/v1/forms/{team}"), Some(&ali), None).await;
    assert!(h.accounts.store.form(team, 0).is_some());
    h.call(Method::DELETE, &format!("/api/v1/forms/{team}"), Some(&sam), None).await;
    assert!(h.accounts.store.form(team, 0).is_none());
}

#[tokio::test]
async fn an_answer_waits_thirty_days_and_the_owner_may_clear_what_waits() {
    let h = Harness::new("forms");
    let (sam, _, public) = with_key(&h, "sam").await;
    a_form(&h, &sam, FORM, json!({ "state": "open" })).await;
    let old = now() - KEPT_FOR - 60;
    h.accounts.store.put_form_item(&FormItem { id: answer_id(1), form: FORM.into(), note: None, wraps: "[]".into(), blob: "b".into(), at: old, claimed: false }, WAITING, 0).unwrap();
    assert!(inbox(&h, &sam).await.is_empty(), "past thirty days, not listed");
    assert_eq!(h.accounts.store.sweep_form_inbox(now() - KEPT_FOR), 1, "and swept");
    for n in 2..5 {
        answer(&h, FORM, "203.0.113.6", &answer_id(n), std::slice::from_ref(&public), json!({})).await;
    }
    assert_eq!(inbox(&h, &sam).await.len(), 3);
    let (ali, _, _) = with_key(&h, "ali").await;
    let (_, none) = h.call(Method::DELETE, &format!("/api/v1/forms/{FORM}/answers"), Some(&ali), None).await;
    assert_eq!(none, json!({ "deleted": 0 }));
    let (status, cleared) = h.call(Method::DELETE, &format!("/api/v1/forms/{FORM}/answers"), Some(&sam), None).await;
    assert_eq!((status, cleared), (StatusCode::OK, json!({ "deleted": 3 })));
    assert!(inbox(&h, &sam).await.is_empty());
    assert_eq!(h.accounts.store.form(FORM, 0).unwrap().state, FormState::Open, "the form stays");
}

/// The reader's seal (tauri/src/read/form.ts `sealAnswer`, written by its form.test.ts into formSeal.fixture.json):
/// taken by the route as any browser's answer is, and opened here with the fixture key's private half, as a device
/// opens one.
#[tokio::test]
async fn the_reader_s_seal_is_taken_and_opens_with_the_fixture_s_key() {
    let fixture: Value = serde_json::from_str(&std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../tauri/src/read/formSeal.fixture.json")).unwrap()).unwrap();
    let d = URL_SAFE_NO_PAD.decode(fixture["jwk"]["d"].as_str().unwrap()).unwrap();
    let secret = p256::SecretKey::from_slice(&d).unwrap();
    assert_eq!(public_of(&secret), fixture["public"].as_str().unwrap());
    let h = Harness::new("forms");
    let token = h.signup("sam", &device()).await;
    let (status, _) = h.call(Method::PUT, "/api/v1/account/key", Some(&token), Some(json!({ "pub": public_of(&secret), "sealed": "c2VhbGVk" }))).await;
    assert_eq!(status, StatusCode::CREATED);
    let form = fixture["form"].as_str().unwrap();
    a_form(&h, &token, form, json!({})).await;
    let sealed = &fixture["sealed"];
    let body = json!({ "id": fixture["answer"], "ticket": ticket(&h, form, 10), "wraps": sealed["wraps"], "blob": sealed["blob"], "hp": "" });
    let (status, said) = sent(&h, visit(Method::POST, form, "203.0.113.9", Some(body))).await;
    assert_eq!(status, StatusCode::ACCEPTED, "{said}");
    let items = inbox(&h, &token).await;
    assert_eq!(opened(&secret, &items[0]), fixture["payload"]);
}
