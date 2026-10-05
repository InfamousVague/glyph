//! Organizations, through the routes a device calls (docs/TEAMS.md): made, listed, read, renamed and deleted by their
//! owner; people invited by handle, told, and answering; the roles and the one invariant; what a stranger learns
//! (nothing); what an inviter's or an owner's account deletion does; and the limits, each in the words the app shows.
//!
//! The store's own tests (store/orgs.rs) try the rules at small numbers; here the numbers are the route's, and the
//! fifty rows and twenty invitations an organization meets are seeded through the store, since the sign-in limit
//! would not sign up fifty accounts in a minute.

use crate::store::InviteCaps;
use crate::test_support::{device, login, request, Harness};
use axum::http::{Method, StatusCode};
use serde_json::{json, Value};

fn harness() -> Harness {
    Harness::new("orgs")
}

/// `POST orgs` as the owner: the new organization's id.
async fn make(h: &Harness, token: &str, name: &str) -> String {
    let (status, body) = h.call(Method::POST, "/api/v1/orgs", Some(token), Some(json!({ "name": name }))).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    body["org"]["id"].as_str().unwrap().to_string()
}

async fn invite(h: &Harness, token: &str, org: &str, handle: &str) -> (StatusCode, Value) {
    h.call(Method::POST, &format!("/api/v1/orgs/{org}/members"), Some(token), Some(json!({ "handle": handle }))).await
}

async fn answer(h: &Harness, token: &str, org: &str, accept: bool) -> (StatusCode, Value) {
    h.call(Method::POST, &format!("/api/v1/orgs/{org}/invite"), Some(token), Some(json!({ "accept": accept }))).await
}

/// The account's whole feed, oldest first.
async fn feed(h: &Harness, token: &str) -> Vec<Value> {
    let (status, body) = h.call(Method::GET, "/api/v1/notifications?since=0&limit=200", Some(token), None).await;
    assert_eq!(status, StatusCode::OK);
    body["items"].as_array().unwrap().clone()
}

/// The feed's rows of one kind.
async fn of_kind(h: &Harness, token: &str, kind: &str) -> Vec<Value> {
    feed(h, token).await.into_iter().filter(|n| n["kind"] == kind).collect()
}

fn refusal(status: StatusCode, words: &str) -> (StatusCode, Value) {
    (status, json!({ "error": words }))
}

#[tokio::test]
async fn an_organization_is_made_listed_read_renamed_and_deleted_by_its_owner() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let (status, body) = h.call(Method::POST, "/api/v1/orgs", Some(&matt), Some(json!({ "name": "  Ghost  ", "hue": "moss" }))).await;
    assert_eq!(status, StatusCode::CREATED);
    let org = body["org"].clone();
    let id = org["id"].as_str().unwrap().to_string();
    assert_eq!(id.len(), 22, "an id the service made");
    assert_eq!((org["name"].clone(), org["hue"].clone(), org["role"].clone(), org["state"].clone()), (json!("Ghost"), json!("moss"), json!("owner"), json!("member")));
    assert_eq!(org["invitedBy"], Value::Null);
    assert!(org["createdAt"].is_i64());
    assert_eq!(org["members"], json!([{ "handle": "matt", "role": "owner", "state": "member", "since": org["createdAt"], "invitedBy": null, "colour": null, "pub": null }]));
    assert_eq!((org["colour"].clone(), org["keys"].clone()), (Value::Null, json!({ "generation": 0, "mine": false, "missing": 0 })));

    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    assert_eq!(list["orgs"], json!([{ "id": id, "name": "Ghost", "hue": "moss", "role": "owner", "state": "member", "members": 1, "invitedBy": null, "createdAt": org["createdAt"], "colour": null, "keys": { "generation": 0, "mine": false, "missing": 0 } }]));
    assert_eq!(list["colour"], Value::Null);
    let (status, read) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&matt), None).await;
    assert_eq!((status, read["org"].clone()), (StatusCode::OK, org));

    // A rename and a hue; `hue: null` clears it, a body without `hue` leaves it.
    let (status, renamed) = h.call(Method::PUT, &format!("/api/v1/orgs/{id}"), Some(&matt), Some(json!({ "name": "Ghost II" }))).await;
    assert_eq!((status, renamed["org"]["name"].clone(), renamed["org"]["hue"].clone()), (StatusCode::OK, json!("Ghost II"), json!("moss")));
    let (_, cleared) = h.call(Method::PUT, &format!("/api/v1/orgs/{id}"), Some(&matt), Some(json!({ "hue": null }))).await;
    assert_eq!((cleared["org"]["name"].clone(), cleared["org"]["hue"].clone()), (json!("Ghost II"), Value::Null));
    let (_, hued) = h.call(Method::PUT, &format!("/api/v1/orgs/{id}"), Some(&matt), Some(json!({ "hue": "rose" }))).await;
    assert_eq!(hued["org"]["hue"], json!("rose"));

    let (status, body) = h.call(Method::DELETE, &format!("/api/v1/orgs/{id}"), Some(&matt), None).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "deleted": true })));
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    assert_eq!(list["orgs"], json!([]));
    let (status, body) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&matt), None).await;
    assert_eq!((status, body), refusal(StatusCode::NOT_FOUND, "No such organization."));
}

#[tokio::test]
async fn a_name_a_hue_a_role_and_an_id_are_checked_before_anything_is_looked_up() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    for name in ["", "   ", &"x".repeat(61)] {
        let (status, body) = h.call(Method::POST, "/api/v1/orgs", Some(&matt), Some(json!({ "name": name }))).await;
        assert_eq!((status, body), refusal(StatusCode::BAD_REQUEST, "An organization's name is 1 to 60 characters."), "{name:?}");
    }
    let (status, _) = h.call(Method::POST, "/api/v1/orgs", Some(&matt), Some(json!({ "name": "é".repeat(60) }))).await;
    assert_eq!(status, StatusCode::CREATED, "sixty characters, not sixty bytes");
    let (status, body) = h.call(Method::POST, "/api/v1/orgs", Some(&matt), Some(json!({ "name": "Ghost", "hue": "teal" }))).await;
    assert_eq!((status, body), refusal(StatusCode::BAD_REQUEST, "That hue is not one of the workspace hues."));
    let id = make(&h, &matt, "Ghost").await;
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/orgs/{id}"), Some(&matt), Some(json!({ "hue": "teal" }))).await;
    assert_eq!((status, body), refusal(StatusCode::BAD_REQUEST, "That hue is not one of the workspace hues."));
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/orgs/{id}/members/matt"), Some(&matt), Some(json!({ "role": "boss" }))).await;
    assert_eq!((status, body), refusal(StatusCode::BAD_REQUEST, "A role is owner, admin or member."));
    let (status, body) = h.call(Method::GET, "/api/v1/orgs/not%20an%20id", Some(&matt), None).await;
    assert_eq!((status, body), refusal(StatusCode::BAD_REQUEST, "That organization's id could not be read."));
}

#[tokio::test]
async fn a_stranger_gets_one_404_from_every_route_of_an_organization() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    let not_yours = refusal(StatusCode::NOT_FOUND, "No such organization.");
    let routes = [
        (Method::GET, format!("/api/v1/orgs/{id}"), None),
        (Method::PUT, format!("/api/v1/orgs/{id}"), Some(json!({ "name": "Mine" }))),
        (Method::DELETE, format!("/api/v1/orgs/{id}"), None),
        (Method::POST, format!("/api/v1/orgs/{id}/members"), Some(json!({ "handle": "matt" }))),
        (Method::DELETE, format!("/api/v1/orgs/{id}/members/matt"), None),
        (Method::PUT, format!("/api/v1/orgs/{id}/members/matt"), Some(json!({ "role": "member" }))),
        (Method::POST, format!("/api/v1/orgs/{id}/links"), Some(json!({}))),
        (Method::GET, format!("/api/v1/orgs/{id}/links"), None),
        (Method::DELETE, format!("/api/v1/orgs/{id}/links/AAAAAAAAAAAAAAAAAAAAAA"), None),
        (Method::PUT, format!("/api/v1/orgs/{id}/colour"), Some(json!({ "hue": "sea" }))),
        (Method::GET, format!("/api/v1/orgs/{id}/keys"), None),
        (Method::POST, format!("/api/v1/orgs/{id}/keys"), Some(json!({ "generation": 1, "wraps": [] }))),
        // And one that was never made, in the same words.
        (Method::GET, "/api/v1/orgs/AAAAAAAAAAAAAAAAAAAAAA".to_string(), None),
    ];
    for (method, path, body) in routes {
        let answer = h.call(method.clone(), &path, Some(&sam), body).await;
        assert_eq!(answer, not_yours, "{method} {path}");
    }
    let (status, body) = answer(&h, &sam, &id, true).await;
    assert_eq!((status, body), refusal(StatusCode::NOT_FOUND, "You were not invited."));
    // An invitee reads the list, with the count and who asked, and not the members.
    invite(&h, &matt, &id, "sam").await;
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&sam), None).await;
    assert_eq!((list["orgs"][0]["state"].clone(), list["orgs"][0]["members"].clone(), list["orgs"][0]["invitedBy"].clone()), (json!("invited"), json!(1), json!("matt")));
    let answer = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&sam), None).await;
    assert_eq!(answer, not_yours);
    // Nothing changed under the owner.
    let (_, read) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&matt), None).await;
    assert_eq!(read["org"]["name"], "Ghost");
}

#[tokio::test]
async fn inviting_by_handle_tells_the_invitee_and_accepting_tells_the_asker_and_the_rest() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let ali = h.signup("ali", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    let (status, body) = invite(&h, &matt, &id, " SAM ").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!((body["member"]["handle"].clone(), body["member"]["role"].clone(), body["member"]["state"].clone(), body["member"]["invitedBy"].clone()), (json!("sam"), json!("member"), json!("invited"), json!("matt")));
    // The invitee's feed: one row, with everything the app draws from.
    let rows = feed(&h, &sam).await;
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert_eq!((row["kind"].clone(), row["from"].clone(), row["state"].clone(), row["readAt"].clone(), row["hidden"].clone()), (json!("invite"), json!("matt"), json!("pending"), Value::Null, json!(false)));
    assert_eq!(row["org"], json!({ "id": id, "name": "Ghost" }));
    assert_eq!(row["body"], json!({ "name": "Ghost" }));
    assert!(row["blob"].is_null() && row["id"].as_str().unwrap().len() == 22 && row["rev"].is_i64() && row["at"].is_i64());
    assert!(feed(&h, &matt).await.is_empty(), "asking is the asker's own act");
    // Asked again: the row is refreshed, not doubled.
    let (status, _) = invite(&h, &matt, &id, "sam").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(feed(&h, &sam).await.len(), 1);

    // Accepting answers the organization as the new member reads it.
    let (status, body) = answer(&h, &sam, &id, true).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!((body["org"]["id"].clone(), body["org"]["role"].clone(), body["org"]["state"].clone(), body["org"]["members"].as_array().unwrap().len()), (json!(id), json!("member"), json!("member"), 2));
    let settled = &feed(&h, &sam).await[0];
    assert_eq!((settled["state"].clone(), settled["hidden"].clone()), (json!("accepted"), json!(false)));
    assert!(settled["readAt"].is_i64(), "an invitation the person answered is read: the bell's dot goes with the tap");
    assert!(settled["rev"].as_i64() > row["rev"].as_i64(), "fed again under a new revision");
    let told = of_kind(&h, &matt, "invite-accepted").await;
    assert_eq!((told.len(), told[0]["from"].clone(), told[0]["org"]["name"].clone()), (1, json!("sam"), json!("Ghost")));
    assert!(of_kind(&h, &matt, "member-joined").await.is_empty(), "the asker is told once");
    // A third, asked by sam once an admin: the owner hears of the joining, sam of the acceptance.
    h.call(Method::PUT, &format!("/api/v1/orgs/{id}/members/sam"), Some(&matt), Some(json!({ "role": "admin" }))).await;
    assert_eq!(of_kind(&h, &sam, "role-changed").await[0]["body"], json!({ "name": "Ghost", "role": "admin" }));
    invite(&h, &sam, &id, "ali").await;
    answer(&h, &ali, &id, true).await;
    assert_eq!(of_kind(&h, &sam, "invite-accepted").await[0]["from"], "ali");
    assert_eq!(of_kind(&h, &matt, "member-joined").await[0]["from"], "ali");
    let (_, read) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&ali), None).await;
    let people: Vec<(String, String)> = read["org"]["members"].as_array().unwrap().iter().map(|m| (m["handle"].as_str().unwrap().into(), m["role"].as_str().unwrap().into())).collect();
    assert_eq!(people, vec![("matt".into(), "owner".into()), ("sam".into(), "admin".into()), ("ali".into(), "member".into())]);
}

#[tokio::test]
async fn declining_settles_the_invitation_tells_the_asker_and_makes_the_organization_wait_a_day() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    invite(&h, &matt, &id, "sam").await;
    let (status, body) = answer(&h, &sam, &id, false).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "declined": true })));
    assert_eq!(feed(&h, &sam).await[0]["state"], "declined");
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&sam), None).await;
    assert_eq!(list["orgs"], json!([]), "declined is not listed");
    assert_eq!(of_kind(&h, &matt, "invite-declined").await[0]["from"], "sam");
    let (status, body) = answer(&h, &sam, &id, true).await;
    assert_eq!((status, body), refusal(StatusCode::NOT_FOUND, "You were not invited."), "answered already");
    let (status, body) = invite(&h, &matt, &id, "sam").await;
    assert_eq!((status, body), refusal(StatusCode::CONFLICT, "They declined; ask again tomorrow."));
    // (The day passing is the store's test, store/orgs.rs: the route cannot move the clock.)
}

#[tokio::test]
async fn every_invitation_refusal_in_its_words() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    for handle in ["nobody", "no!", "", "x"] {
        let answer = invite(&h, &matt, &id, handle).await;
        assert_eq!(answer, refusal(StatusCode::NOT_FOUND, "No one has that handle."), "{handle:?}: a handle that could not be anyone's is nobody's, in the same words");
    }
    assert_eq!(invite(&h, &matt, &id, "matt").await, refusal(StatusCode::CONFLICT, "They are already a member."));
    invite(&h, &matt, &id, "sam").await;
    answer(&h, &sam, &id, true).await;
    assert_eq!(invite(&h, &matt, &id, "sam").await, refusal(StatusCode::CONFLICT, "They are already a member."));
    assert_eq!(invite(&h, &sam, &id, "matt").await, refusal(StatusCode::FORBIDDEN, "Only the owner or an admin can do that."), "a member does not invite");

    // The caps, at the route's numbers, seeded through the store: twenty invitations waiting for one account ...
    let store = &h.accounts.store;
    let caps = || InviteCaps { rows_per_org: 1000, pending_per_invitee: 1000, decline_cooldown: 0 };
    store.create_account("ali", "", "", None, &[], 1).unwrap();
    for i in 0..crate::orgs::PENDING_PER_INVITEE {
        let owner = store.create_account(&format!("owner-{i}"), "", "", None, &[], 1).unwrap();
        store.create_org(owner.id, &format!("org-{i}"), "Theirs", None, 1, 1000).unwrap();
        store.invite(owner.id, &format!("org-{i}"), "ali", 2, caps()).unwrap();
    }
    assert_eq!(invite(&h, &matt, &id, "ali").await, refusal(StatusCode::CONFLICT, "They have as many invitations waiting as they can."));
    // ... and fifty rows in one organization, joined and invited together.
    let full = make(&h, &matt, "Full").await;
    let matt_id = store.account_by_handle("matt").unwrap().id;
    for i in 1..crate::orgs::ORG_ROWS {
        store.create_account(&format!("row-{i}"), "", "", None, &[], 1).unwrap();
        store.invite(matt_id, &full, &format!("row-{i}"), 3, caps()).unwrap();
    }
    assert_eq!(invite(&h, &matt, &full, "sam").await, refusal(StatusCode::CONFLICT, "The organization is full."));
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    let counted = list["orgs"].as_array().unwrap().iter().find(|o| o["id"] == full).unwrap();
    assert_eq!(counted["members"], json!(1), "the count is of those who have joined");
}

#[tokio::test]
async fn the_owner_invariant_through_the_routes() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let ali = h.signup("ali", &device()).await;
    let kim = h.signup("kim", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    for handle in ["sam", "ali", "kim"] {
        invite(&h, &matt, &id, handle).await;
    }
    answer(&h, &sam, &id, true).await;
    answer(&h, &ali, &id, true).await;
    let hr = &h;
    let role = |token: &str, handle: &str, role: &str| {
        let token = token.to_string();
        let path = format!("/api/v1/orgs/{id}/members/{handle}");
        let body = json!({ "role": role });
        async move { hr.call(Method::PUT, &path, Some(&token), Some(body)).await }
    };
    let remove = |token: &str, handle: &str| {
        let token = token.to_string();
        let path = format!("/api/v1/orgs/{id}/members/{handle}");
        async move { hr.call(Method::DELETE, &path, Some(&token), None).await }
    };
    let hand_over = refusal(StatusCode::FORBIDDEN, "Hand the organization over first.");
    role(&matt, "sam", "admin").await;
    assert_eq!(remove(&sam, "matt").await, hand_over, "nobody removes the owner");
    assert_eq!(remove(&matt, "matt").await, hand_over, "the owner does not leave");
    assert_eq!(role(&matt, "matt", "member").await, hand_over, "nor steps down");
    assert_eq!(role(&sam, "ali", "admin").await, refusal(StatusCode::FORBIDDEN, "Only the owner can do that."));
    assert_eq!(h.call(Method::DELETE, &format!("/api/v1/orgs/{id}"), Some(&sam), None).await, refusal(StatusCode::FORBIDDEN, "Only the owner can do that."));
    assert_eq!(remove(&ali, "sam").await, refusal(StatusCode::FORBIDDEN, "Only the owner or an admin can do that."));
    role(&matt, "ali", "admin").await;
    assert_eq!(remove(&sam, "ali").await, refusal(StatusCode::FORBIDDEN, "Only the owner can remove an admin."));
    assert_eq!(role(&matt, "kim", "owner").await, refusal(StatusCode::CONFLICT, "They have not joined yet."));
    assert_eq!(remove(&matt, "nobody").await, refusal(StatusCode::NOT_FOUND, "No one by that handle is in this organization."));
    assert_eq!(role(&matt, "nobody", "admin").await, refusal(StatusCode::NOT_FOUND, "No one by that handle is in this organization."));
    // Handed over: one owner, and the old one an admin, in one answer.
    let (status, handed) = role(&matt, "SAM", "owner").await;
    assert_eq!((status, handed["member"]["handle"].clone(), handed["member"]["role"].clone()), (StatusCode::OK, json!("sam"), json!("owner")));
    let (_, read) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&matt), None).await;
    let roles: Vec<(String, String)> = read["org"]["members"].as_array().unwrap().iter().map(|m| (m["handle"].as_str().unwrap().into(), m["role"].as_str().unwrap().into())).collect();
    assert_eq!(roles.iter().filter(|(_, r)| r == "owner").count(), 1);
    assert_eq!(roles[0], ("matt".to_string(), "admin".to_string()));
    assert_eq!(read["org"]["role"], "admin");
    assert_eq!(of_kind(&h, &sam, "role-changed").await.last().unwrap()["body"]["role"], "owner");
    // Now the old owner can leave, and the rest are told; and the new owner can remove an admin.
    assert_eq!(remove(&matt, "matt").await, (StatusCode::OK, json!({ "removed": true })));
    let left = of_kind(&h, &sam, "member-left").await;
    assert_eq!((left[0]["from"].clone(), left[0]["body"].clone()), (json!("matt"), json!({ "name": "Ghost", "handle": "matt" })));
    assert_eq!(remove(&sam, "ali").await, (StatusCode::OK, json!({ "removed": true })));
    let removed = of_kind(&h, &ali, "member-removed").await;
    assert_eq!((removed[0]["from"].clone(), removed[0]["body"].clone(), removed[0]["org"]["name"].clone()), (json!("sam"), json!({ "name": "Ghost" }), json!("Ghost")));
    assert!(of_kind(&h, &sam, "member-removed").await.is_empty(), "the remover's own act");
    // An invitee withdrawn: their invitation is settled and hidden, nobody else is told.
    assert_eq!(remove(&sam, "kim").await, (StatusCode::OK, json!({ "removed": true })));
    let withdrawn = &feed(&h, &kim).await[0];
    assert_eq!((withdrawn["state"].clone(), withdrawn["hidden"].clone()), (json!("declined"), json!(true)));
    assert_eq!(answer(&h, &kim, &id, true).await, refusal(StatusCode::NOT_FOUND, "You were not invited."));
}

#[tokio::test]
async fn a_rename_reaches_every_member_once_and_a_former_member_keeps_the_old_name() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let ali = h.signup("ali", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    invite(&h, &matt, &id, "sam").await;
    invite(&h, &matt, &id, "ali").await;
    answer(&h, &sam, &id, true).await;
    answer(&h, &ali, &id, true).await;
    h.call(Method::DELETE, &format!("/api/v1/orgs/{id}/members/ali"), Some(&matt), None).await;
    let before = of_kind(&h, &ali, "member-removed").await[0].clone();
    let hr = &h;
    let rename = |name: &str| {
        let body = json!({ "name": name });
        let path = format!("/api/v1/orgs/{id}");
        let token = matt.clone();
        async move { hr.call(Method::PUT, &path, Some(&token), Some(body)).await }
    };
    rename("Ghost II").await;
    let first = of_kind(&h, &sam, "org-renamed").await;
    rename("Ghost III").await;
    let second = of_kind(&h, &sam, "org-renamed").await;
    assert_eq!((first.len(), second.len()), (1, 1), "one unread rename, brought up to date");
    assert_eq!(second[0]["id"], first[0]["id"]);
    assert!(second[0]["rev"].as_i64() > first[0]["rev"].as_i64());
    assert_eq!(second[0]["body"], json!({ "name": "Ghost III", "was": "Ghost" }));
    assert_eq!(second[0]["org"]["name"], "Ghost III", "a member reads the live name");
    assert!(of_kind(&h, &matt, "org-renamed").await.is_empty(), "the renamer's own act");
    let after = of_kind(&h, &ali, "member-removed").await[0].clone();
    assert_eq!(after, before, "someone removed does not go on reading the organization's renames");
    assert_eq!(after["org"]["name"], "Ghost");
}

#[tokio::test]
async fn deleting_an_organization_settles_its_invitations_and_tells_its_members() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let ali = h.signup("ali", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    invite(&h, &matt, &id, "sam").await;
    invite(&h, &matt, &id, "ali").await;
    answer(&h, &sam, &id, true).await;
    let pending = feed(&h, &ali).await[0].clone();
    h.call(Method::DELETE, &format!("/api/v1/orgs/{id}"), Some(&matt), None).await;
    let settled = feed(&h, &ali).await[0].clone();
    assert_eq!((settled["state"].clone(), settled["hidden"].clone(), settled["org"]["name"].clone()), (json!("declined"), json!(true), json!("Ghost")));
    assert!(settled["rev"].as_i64() > pending["rev"].as_i64());
    assert_eq!(answer(&h, &ali, &id, true).await, refusal(StatusCode::NOT_FOUND, "You were not invited."));
    let gone = of_kind(&h, &sam, "org-deleted").await;
    assert_eq!((gone[0]["from"].clone(), gone[0]["body"].clone(), gone[0]["org"].clone()), (json!("matt"), json!({ "name": "Ghost" }), json!({ "id": id, "name": "Ghost" })));
    for token in [&matt, &sam, &ali] {
        let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(token), None).await;
        assert_eq!(list["orgs"], json!([]));
    }
}

/// The cascade and the SET NULL rules (store.rs): an asker's account going takes nobody with it, and an owner's
/// account does not go while anyone else is in the organization.
#[tokio::test]
async fn an_asker_who_deletes_their_account_leaves_the_invitee_a_member_and_an_owner_with_others_cannot() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let ali = h.signup("ali", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    invite(&h, &matt, &id, "sam").await;
    answer(&h, &sam, &id, true).await;
    h.call(Method::PUT, &format!("/api/v1/orgs/{id}/members/sam"), Some(&matt), Some(json!({ "role": "admin" }))).await;
    invite(&h, &sam, &id, "ali").await;
    let password = Some(json!({ "loginSecret": login(1) }));
    // The owner, with a member and an invitee in it: refused, with the session fine.
    let (status, body) = h.call(Method::DELETE, "/api/v1/account", Some(&matt), password.clone()).await;
    assert_eq!((status, body), refusal(StatusCode::FORBIDDEN, "Hand over or delete your organizations first."));
    let (status, _) = h.call(Method::GET, "/api/v1/keys", Some(&matt), None).await;
    assert_eq!(status, StatusCode::OK);
    // The asker, an admin: free to go. The invitee's row and the invitation stay, with nobody behind them.
    let (status, body) = h.call(Method::DELETE, "/api/v1/account", Some(&sam), password.clone()).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "deleted": true })));
    let left = of_kind(&h, &matt, "member-left").await;
    assert_eq!((left[0]["from"].clone(), left[0]["body"]["handle"].clone()), (Value::Null, json!("sam")), "told, and the account behind it gone");
    let theirs = feed(&h, &ali).await;
    assert_eq!((theirs.len(), theirs[0]["kind"].clone(), theirs[0]["from"].clone(), theirs[0]["state"].clone()), (1, json!("invite"), Value::Null, json!("pending")));
    let (status, body) = answer(&h, &ali, &id, true).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["org"]["members"], json!([
        { "handle": "matt", "role": "owner", "state": "member", "since": body["org"]["members"][0]["since"], "invitedBy": null, "colour": null, "pub": null },
        { "handle": "ali", "role": "member", "state": "member", "since": body["org"]["members"][1]["since"], "invitedBy": null, "colour": null, "pub": null },
    ]));
    assert_eq!(of_kind(&h, &matt, "invite-accepted").await.last().unwrap()["from"], "ali", "the asker gone, the owner is told");
    // Hand over, and the old owner may go; the organization is told they left.
    h.call(Method::PUT, &format!("/api/v1/orgs/{id}/members/ali"), Some(&matt), Some(json!({ "role": "owner" }))).await;
    let (status, _) = h.call(Method::DELETE, "/api/v1/account", Some(&matt), password.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(of_kind(&h, &ali, "member-left").await[0]["body"]["handle"], "matt");
    let (_, read) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&ali), None).await;
    assert_eq!(read["org"]["members"].as_array().unwrap().len(), 1);
    // An organization with nobody else in it goes with its owner.
    let (status, _) = h.call(Method::DELETE, "/api/v1/account", Some(&ali), password).await;
    assert_eq!(status, StatusCode::OK);
    let again = h.signup("ali", &device()).await;
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&again), None).await;
    assert_eq!(list["orgs"], json!([]));
    assert!(feed(&h, &again).await.is_empty(), "a new account under the handle starts empty");
}

/// The limits a device meets through the routes, at the route's numbers: twenty organizations owned, thirty
/// invitations an hour, sixty other changes a minute. The buckets refill, so a slow machine may earn one more before
/// the refusal; the refusal still comes.
#[tokio::test]
async fn the_limits_on_owning_inviting_and_changing() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    for i in 0..crate::orgs::ORGS_OWNED {
        let (status, _) = h.call(Method::POST, "/api/v1/orgs", Some(&matt), Some(json!({ "name": format!("Org {i}") }))).await;
        assert_eq!(status, StatusCode::CREATED, "organization {i} of the twenty");
    }
    assert_eq!(h.call(Method::POST, "/api/v1/orgs", Some(&matt), Some(json!({ "name": "One more" }))).await, refusal(StatusCode::CONFLICT, "You own as many organizations as you can."));
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    let id = list["orgs"][0]["id"].as_str().unwrap().to_string();
    // Invitations: thirty an hour, asking again counted like asking.
    for i in 0..30 {
        let (status, body) = invite(&h, &matt, &id, "sam").await;
        assert_eq!(status, StatusCode::OK, "invitation {i} of the hour's thirty: {body}");
    }
    let mut refused = None;
    for _ in 0..20 {
        let answer = invite(&h, &matt, &id, "sam").await;
        if answer.0 == StatusCode::TOO_MANY_REQUESTS {
            refused = Some(answer);
            break;
        }
    }
    assert_eq!(refused, Some(refusal(StatusCode::TOO_MANY_REQUESTS, "Too many invitations in an hour. Try again later.")));
    // Another account's hour, from another address, is its own.
    let other = make(&h, &sam, "Theirs").await;
    let mut from_elsewhere = request(Method::POST, &format!("/api/v1/orgs/{other}/members"), Some(&sam), Some(json!({ "handle": "matt" })));
    from_elsewhere.headers_mut().insert("x-forwarded-for", "203.0.113.9".parse().unwrap());
    let (status, _, _) = h.send(from_elsewhere).await;
    assert_eq!(status, StatusCode::OK);
    // Every other change: sixty a minute. Twenty-one were spent making the organizations above.
    for i in 21..60 {
        let (status, _) = h.call(Method::PUT, &format!("/api/v1/orgs/{id}"), Some(&matt), Some(json!({ "hue": "sea" }))).await;
        assert_eq!(status, StatusCode::OK, "change {i} of the minute's sixty");
    }
    let mut refused = None;
    for _ in 0..20 {
        let answer = h.call(Method::PUT, &format!("/api/v1/orgs/{id}"), Some(&matt), Some(json!({ "hue": "sea" }))).await;
        if answer.0 == StatusCode::TOO_MANY_REQUESTS {
            refused = Some(answer);
            break;
        }
    }
    assert_eq!(refused, Some(refusal(StatusCode::TOO_MANY_REQUESTS, "Too many changes in a minute. Try again shortly.")));
    let (status, _) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&matt), None).await;
    assert_eq!(status, StatusCode::OK, "reading is not a change");
}

/// `POST links` as `token`: the new link.
async fn make_link(h: &Harness, token: &str, org: &str, body: Value) -> (StatusCode, Value) {
    h.call(Method::POST, &format!("/api/v1/orgs/{org}/links"), Some(token), Some(body)).await
}

#[tokio::test]
async fn an_invite_link_is_made_previewed_followed_and_turned_off() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let ali = h.signup("ali", &device()).await;
    let org = make(&h, &matt, "Ghost").await;

    let (status, body) = make_link(&h, &matt, &org, json!({ "expiresIn": 7 * 24 * 3600, "maxUses": 5 })).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let link = body["link"].clone();
    let code = link["code"].as_str().unwrap().to_string();
    assert_eq!(code.len(), 22, "128 random bits");
    assert_eq!((link["uses"].clone(), link["maxUses"].clone(), link["by"].clone()), (json!(0), json!(5), json!("matt")));
    assert_eq!(link["expiresAt"].as_i64().unwrap() - link["createdAt"].as_i64().unwrap(), 7 * 24 * 3600 * 1000);
    let (_, listed) = h.call(Method::GET, &format!("/api/v1/orgs/{org}/links"), Some(&matt), None).await;
    assert_eq!(listed["links"], json!([link]));

    // The preview: the name and the count, nothing about who.
    let (status, preview) = h.call(Method::GET, &format!("/api/v1/joins/{code}"), Some(&sam), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(preview, json!({ "org": { "id": org, "name": "Ghost", "hue": null, "members": 1 }, "by": "matt", "member": false }));

    let (status, joined) = h.call(Method::POST, &format!("/api/v1/joins/{code}"), Some(&sam), None).await;
    assert_eq!(status, StatusCode::OK, "{joined}");
    assert_eq!((joined["org"]["role"].clone(), joined["org"]["state"].clone(), joined["org"]["invitedBy"].clone()), (json!("member"), json!("member"), json!("matt")));
    let (_, preview) = h.call(Method::GET, &format!("/api/v1/joins/{code}"), Some(&sam), None).await;
    assert_eq!((preview["member"].clone(), preview["org"]["members"].clone()), (json!(true), json!(2)));
    assert_eq!(of_kind(&h, &matt, "invite-accepted").await.len(), 1, "the maker is told");

    // A member who does not manage cannot see, make or turn off links.
    let admin_only = refusal(StatusCode::FORBIDDEN, "Only the owner or an admin can do that.");
    assert_eq!(make_link(&h, &sam, &org, json!({})).await, admin_only);
    assert_eq!(h.call(Method::GET, &format!("/api/v1/orgs/{org}/links"), Some(&sam), None).await, admin_only);

    let link_id = link["id"].as_str().unwrap();
    let (status, body) = h.call(Method::DELETE, &format!("/api/v1/orgs/{org}/links/{link_id}"), Some(&matt), None).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "dropped": true })));
    let gone = refusal(StatusCode::NOT_FOUND, "That invite link has expired or was turned off.");
    assert_eq!(h.call(Method::GET, &format!("/api/v1/joins/{code}"), Some(&ali), None).await, gone);
    assert_eq!(h.call(Method::POST, &format!("/api/v1/joins/{code}"), Some(&ali), None).await, gone);
    // A code that could not be one gets the same words.
    assert_eq!(h.call(Method::POST, "/api/v1/joins/x", Some(&ali), None).await, gone);
    let (status, _) = h.call(Method::POST, &format!("/api/v1/joins/{code}"), None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "joining needs an account");
}

#[tokio::test]
async fn an_invite_links_terms_and_count_are_checked() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let org = make(&h, &matt, "Ghost").await;
    for secs in [60, 31 * 24 * 3600] {
        let (status, body) = make_link(&h, &matt, &org, json!({ "expiresIn": secs })).await;
        assert_eq!((status, body), refusal(StatusCode::BAD_REQUEST, "A link lasts an hour to thirty days, or until it is turned off."), "{secs}");
    }
    for uses in [0, 51] {
        let (status, body) = make_link(&h, &matt, &org, json!({ "maxUses": uses })).await;
        assert_eq!((status, body), refusal(StatusCode::BAD_REQUEST, "A link may be used 1 to 50 times, or without a limit."), "{uses}");
    }
    let (status, body) = make_link(&h, &matt, &org, json!({})).await;
    assert_eq!((status, body["link"]["expiresAt"].clone(), body["link"]["maxUses"].clone()), (StatusCode::CREATED, Value::Null, Value::Null), "none given is for good");
    for _ in 1..10 {
        assert_eq!(make_link(&h, &matt, &org, json!({})).await.0, StatusCode::CREATED);
    }
    let (status, body) = make_link(&h, &matt, &org, json!({})).await;
    assert_eq!((status, body), refusal(StatusCode::CONFLICT, "This organization has as many invite links as it can. Turn one off first."));
}

// --- colours and keys (docs/SHARED.md) -------------------------------------------------------

#[tokio::test]
async fn a_colour_is_the_accounts_until_an_organization_overrides_it_and_the_list_carries_both() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    invite(&h, &matt, &id, "sam").await;
    answer(&h, &sam, &id, true).await;
    // Nothing chosen: no colour anywhere.
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    assert_eq!((list["colour"].clone(), list["orgs"][0]["colour"].clone()), (Value::Null, Value::Null));
    // The account's colour, seen by the account and by the others in every organization.
    let (status, body) = h.call(Method::PUT, "/api/v1/account/colour", Some(&matt), Some(json!({ "hue": "sea" }))).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "colour": "sea" })));
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    assert_eq!((list["colour"].clone(), list["orgs"][0]["colour"].clone()), (json!("sea"), json!("sea")));
    let (_, read) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&sam), None).await;
    assert_eq!(read["org"]["members"][0]["colour"], "sea");
    assert_eq!(read["org"]["members"][1]["colour"], Value::Null, "sam chose nothing");
    // An override in this organization, for matt alone; cleared, the account's shows again.
    let (status, body) = h.call(Method::PUT, &format!("/api/v1/orgs/{id}/colour"), Some(&matt), Some(json!({ "hue": "rose" }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!((body["org"]["colour"].clone(), body["org"]["members"][0]["colour"].clone()), (json!("rose"), json!("rose")));
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    assert_eq!((list["colour"].clone(), list["orgs"][0]["colour"].clone()), (json!("sea"), json!("rose")));
    let (_, body) = h.call(Method::PUT, &format!("/api/v1/orgs/{id}/colour"), Some(&matt), Some(json!({ "hue": null }))).await;
    assert_eq!(body["org"]["colour"], "sea");
    // Ink is no colour; a hue the app does not have is refused; a stranger is refused in the usual words.
    let (_, body) = h.call(Method::PUT, "/api/v1/account/colour", Some(&matt), Some(json!({ "hue": "ink" }))).await;
    assert_eq!(body, json!({ "colour": null }));
    let unknown = h.call(Method::PUT, "/api/v1/account/colour", Some(&matt), Some(json!({ "hue": "teal" }))).await;
    assert_eq!(unknown, refusal(StatusCode::BAD_REQUEST, "That hue is not one of the workspace hues."));
    let lee = h.signup("lee", &device()).await;
    let stranger = h.call(Method::PUT, &format!("/api/v1/orgs/{id}/colour"), Some(&lee), Some(json!({ "hue": "sea" }))).await;
    assert_eq!(stranger, refusal(StatusCode::NOT_FOUND, "No such organization."));
}

#[tokio::test]
async fn a_key_pair_is_registered_once_and_the_organization_key_is_made_once_and_filled_for_the_missing() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let lee = h.signup("lee", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    invite(&h, &matt, &id, "sam").await;
    answer(&h, &sam, &id, true).await;
    invite(&h, &matt, &id, "lee").await;
    // No pair yet: 404; registered: 201; a second registration: 409 with the first, which stands.
    let none_yet = h.call(Method::GET, "/api/v1/account/key", Some(&matt), None).await;
    assert_eq!(none_yet, refusal(StatusCode::NOT_FOUND, "No key pair yet."));
    let (status, body) = h.call(Method::PUT, "/api/v1/account/key", Some(&matt), Some(json!({ "pub": "pub-matt", "sealed": "sealed-matt" }))).await;
    assert_eq!((status, body), (StatusCode::CREATED, json!({ "pub": "pub-matt", "sealed": "sealed-matt" })));
    let (status, body) = h.call(Method::PUT, "/api/v1/account/key", Some(&matt), Some(json!({ "pub": "pub-other", "sealed": "sealed-other" }))).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!((body["pub"].clone(), body["sealed"].clone()), (json!("pub-matt"), json!("sealed-matt")));
    let (_, body) = h.call(Method::GET, "/api/v1/account/key", Some(&matt), None).await;
    assert_eq!(body, json!({ "pub": "pub-matt", "sealed": "sealed-matt" }));
    let unreadable = h.call(Method::PUT, "/api/v1/account/key", Some(&sam), Some(json!({ "pub": "not base64!", "sealed": "x" }))).await;
    assert_eq!(unreadable, refusal(StatusCode::BAD_REQUEST, "That key pair could not be read."));
    // The members carry each other's public keys, and the list says what the organization key needs.
    let (_, read) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&sam), None).await;
    assert_eq!((read["org"]["members"][0]["pub"].clone(), read["org"]["members"][1]["pub"].clone()), (json!("pub-matt"), Value::Null));
    assert_eq!(read["org"]["keys"], json!({ "generation": 0, "mine": false, "missing": 1 }), "matt has a key and no wrap");
    // Nothing made: who lacks is everyone with a key; matt makes the first generation and wraps for himself.
    let (_, keys) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), None).await;
    assert_eq!(keys, json!({ "generation": 0, "mine": null, "missing": [{ "handle": "matt", "pub": "pub-matt" }] }));
    let (status, keys) = h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), Some(json!({ "generation": 1, "make": true, "wraps": [{ "handle": "matt", "wrapped": "w-matt" }] }))).await;
    assert_eq!((status, keys), (StatusCode::OK, json!({ "generation": 1, "mine": "w-matt", "missing": [] })));
    // A second maker, racing: told the generation in force, and its key goes nowhere; a wrap at that generation is kept.
    let (status, body) = h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&sam), Some(json!({ "generation": 1, "make": true, "wraps": [{ "handle": "sam", "wrapped": "w-sam-race" }] }))).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "That is not the generation in force.", "generation": 1 })));
    let (status, body) = h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&sam), Some(json!({ "generation": 1, "wraps": [{ "handle": "sam", "wrapped": "w-sam-race" }] }))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["mine"], "w-sam-race");
    let (status, body) = h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&sam), Some(json!({ "generation": 2, "wraps": [] }))).await;
    assert_eq!((status, body), (StatusCode::CONFLICT, json!({ "error": "That is not the generation in force.", "generation": 1 })));
    // lee registers a key while still invited: not wrapped for, not listed; accepted, listed as missing and filled.
    h.call(Method::PUT, "/api/v1/account/key", Some(&lee), Some(json!({ "pub": "pub-lee", "sealed": "sealed-lee" }))).await;
    let (_, keys) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), None).await;
    assert_eq!(keys["missing"], json!([]));
    let refused_lee = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&lee), None).await;
    assert_eq!(refused_lee, refusal(StatusCode::NOT_FOUND, "No such organization."));
    answer(&h, &lee, &id, true).await;
    let (_, keys) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), None).await;
    assert_eq!(keys["missing"], json!([{ "handle": "lee", "pub": "pub-lee" }]));
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    assert_eq!(list["orgs"][0]["keys"], json!({ "generation": 1, "mine": true, "missing": 1 }));
    let (_, keys) = h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), Some(json!({ "generation": 1, "wraps": [{ "handle": "lee", "wrapped": "w-lee" }, { "handle": "nobody", "wrapped": "w-nobody" }] }))).await;
    assert_eq!(keys["missing"], json!([]));
    let (_, keys) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&lee), None).await;
    assert_eq!(keys["mine"], "w-lee");
    let unreadable = h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), Some(json!({ "generation": 0, "wraps": [] }))).await;
    assert_eq!(unreadable, refusal(StatusCode::BAD_REQUEST, "Those wraps could not be read."));
}

#[tokio::test]
async fn the_key_owes_a_turn_when_a_member_goes_and_the_next_generation_answers_it() {
    let h = harness();
    let matt = h.signup("matt", &device()).await;
    let sam = h.signup("sam", &device()).await;
    let lee = h.signup("lee", &device()).await;
    let id = make(&h, &matt, "Ghost").await;
    for (token, name) in [(&matt, "matt"), (&sam, "sam"), (&lee, "lee")] {
        h.call(Method::PUT, "/api/v1/account/key", Some(token), Some(json!({ "pub": format!("pub-{name}"), "sealed": format!("sealed-{name}") }))).await;
    }
    invite(&h, &matt, &id, "sam").await;
    answer(&h, &sam, &id, true).await;
    // A member gone before any key: nothing to turn.
    let (_, keys) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), None).await;
    assert_eq!(keys["stale"], false);
    let (status, keys) = h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), Some(json!({ "generation": 1, "make": true, "wraps": [{ "handle": "matt", "wrapped": "w-matt-1" }, { "handle": "sam", "wrapped": "w-sam-1" }] }))).await;
    assert_eq!(status, StatusCode::OK, "{keys}");
    assert_eq!(keys["stale"], false);
    // sam leaves: the key owes a turn, which the list and the key say, until matt's device makes the next generation.
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/orgs/{id}/members/sam"), Some(&sam), None).await;
    assert_eq!(status, StatusCode::OK);
    let (_, keys) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), None).await;
    assert_eq!((keys["generation"].clone(), keys["stale"].clone()), (json!(1), json!(true)));
    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    assert_eq!(list["orgs"][0]["keys"], json!({ "generation": 1, "mine": true, "missing": 0, "stale": true }));
    let (_, read) = h.call(Method::GET, &format!("/api/v1/orgs/{id}"), Some(&matt), None).await;
    assert_eq!(read["org"]["keys"]["stale"], true);
    let (status, keys) = h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), Some(json!({ "generation": 2, "make": true, "wraps": [{ "handle": "matt", "wrapped": "w-matt-2" }] }))).await;
    assert_eq!(status, StatusCode::OK, "{keys}");
    assert_eq!((keys["generation"].clone(), keys["mine"].clone(), keys["stale"].clone()), (json!(2), json!("w-matt-2"), json!(false)));
    // The older wrap is still there to read, for a row sealed before the turn; a generation that is not a number is refused.
    let (_, old) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys?generation=1"), Some(&matt), None).await;
    assert_eq!((old["generation"].clone(), old["mine"].clone()), (json!(2), json!("w-matt-1")));
    let (_, none) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys?generation=7"), Some(&matt), None).await;
    assert_eq!(none["mine"], Value::Null);
    let bad = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys?generation=0"), Some(&matt), None).await;
    assert_eq!(bad, refusal(StatusCode::BAD_REQUEST, "That generation could not be read."));
    // A member removed owes a turn as one who left does; an invitee withdrawn does not, having had no wrap.
    invite(&h, &matt, &id, "lee").await;
    answer(&h, &lee, &id, true).await;
    h.call(Method::POST, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), Some(json!({ "generation": 2, "wraps": [{ "handle": "lee", "wrapped": "w-lee-2" }] }))).await;
    invite(&h, &matt, &id, "sam").await;
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/orgs/{id}/members/sam"), Some(&matt), None).await;
    assert_eq!(status, StatusCode::OK);
    let (_, keys) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), None).await;
    assert_eq!(keys["stale"], false, "an invitee withdrawn had no key");
    let (status, _) = h.call(Method::DELETE, &format!("/api/v1/orgs/{id}/members/lee"), Some(&matt), None).await;
    assert_eq!(status, StatusCode::OK);
    let (_, keys) = h.call(Method::GET, &format!("/api/v1/orgs/{id}/keys"), Some(&matt), None).await;
    assert_eq!(keys["stale"], true);
}
