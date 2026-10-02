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
    assert_eq!(org["members"], json!([{ "handle": "matt", "role": "owner", "state": "member", "since": org["createdAt"], "invitedBy": null }]));

    let (_, list) = h.call(Method::GET, "/api/v1/orgs", Some(&matt), None).await;
    assert_eq!(list["orgs"], json!([{ "id": id, "name": "Ghost", "hue": "moss", "role": "owner", "state": "member", "members": 1, "invitedBy": null, "createdAt": org["createdAt"] }]));
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
        { "handle": "matt", "role": "owner", "state": "member", "since": body["org"]["members"][0]["since"], "invitedBy": null },
        { "handle": "ali", "role": "member", "state": "member", "since": body["org"]["members"][1]["since"], "invitedBy": null },
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
