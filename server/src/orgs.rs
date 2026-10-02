//! Organizations: teams of accounts invited by handle, with an owner, admins and members, and what each may do
//! (docs/TEAMS.md).
//!
//! Matt: "create an organization in order to add users as team members by handle, adding a team member should show
//! them an invite". The store (store/orgs.rs) keeps the rows and the one invariant - exactly one owner, who has
//! joined - and writes what each change tells people (store/notifications.rs); this file is the wire: the routes, the
//! limits, and the words each refusal is given, which the app shows as they are.
//!
//!   POST   /api/v1/orgs                        { name, hue? }   a new organization, the caller its owner
//!   GET    /api/v1/orgs                                         the caller's: every one joined or invited to
//!   GET    /api/v1/orgs/{id}                                    one, with its people: for those who have joined
//!   PUT    /api/v1/orgs/{id}                   { name?, hue? }  owner or admin
//!   DELETE /api/v1/orgs/{id}                                    owner: gone, its invitations settled, its people told
//!   POST   /api/v1/orgs/{id}/members           { handle }       an invitation, by the owner or an admin
//!   DELETE /api/v1/orgs/{id}/members/{handle}                   someone out, or the caller leaving
//!   PUT    /api/v1/orgs/{id}/members/{handle}  { role }         owner: a role, or 'owner' to hand over
//!   POST   /api/v1/orgs/{id}/invite            { accept }       the invited person's answer
//!
//! Inviting by handle is the one place a signed-in account learns whether a handle exists (404 "No one has that
//! handle."): the ways in never say (accounts/ways_in.rs). So it is limited to thirty an hour, per account and per
//! address, and docs/TEAMS.md says so. Everything else is limited to sixty a minute per account, since a rename or a
//! removal writes a row to every member, and the box is shared. A stranger to an organization gets one 404 from every
//! route of it, "No such organization.", whether it exists or not.

// A refusal here is the response itself, handed straight back from a handler; boxing it would only move it.
#![allow(clippy::result_large_err)]

use crate::accounts::{Accounts, HasAccounts};
use crate::guard;
use crate::identity::Claims;
use crate::store::{InviteCaps, Member, Org, OrgRow, OrgWrite, Role};
use crate::wire::{base64url, error, fresh_id, millis, now_secs};
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Deserializer};
use serde_json::{json, Value};
use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::Instant;

/// Invitations an hour, per inviting account and per address: the handle oracle's budget.
const INVITES_PER_HOUR: u32 = 30;
/// Every other change to an organization, a minute, per account.
const CHANGES_PER_MINUTE: u32 = 60;
/// Organizations one account may own.
pub const ORGS_OWNED: i64 = 20;
/// People in one organization, joined and invited together.
pub const ORG_ROWS: i64 = 50;
/// Invitations one account may have waiting, across every organization.
pub const PENDING_PER_INVITEE: i64 = 20;
/// How long after declining the same organization may not ask again.
const DECLINE_COOLDOWN: i64 = 24 * 3600;
/// An organization's name, in characters after trimming.
const NAME_LENGTH: std::ops::RangeInclusive<usize> = 1..=60;
/// The app's workspace hues (src/app/core/workspaces.ts `WORKSPACE_HUES`), which an organization's workspace takes
/// from the organization. Edit both together.
const HUES: &[&str] = &["ink", "ember", "amber", "moss", "sea", "violet", "rose"];
/// An id the service made is 22 characters; a device's own is taken at the length notes are (sync.rs).
const ID_LENGTH: std::ops::RangeInclusive<usize> = 1..=64;
/// A body here is a name, a hue, a handle or a role.
const BODY_LIMIT: usize = 16 * 1024;

pub struct Orgs {
    accounts: Arc<Accounts>,
    invites_by_account: guard::RateLimiter<i64>,
    invites_by_address: guard::RateLimiter<IpAddr>,
    changes: guard::RateLimiter<i64>,
}

impl Orgs {
    pub fn new(accounts: Arc<Accounts>) -> Arc<Self> {
        let now = Instant::now();
        Arc::new(Self {
            accounts,
            invites_by_account: guard::RateLimiter::per_hour(INVITES_PER_HOUR, now),
            invites_by_address: guard::RateLimiter::per_hour(INVITES_PER_HOUR, now),
            changes: guard::RateLimiter::new(CHANGES_PER_MINUTE, now),
        })
    }

    /// One change by `who`, counted; refused with a 429 when the minute's are spent.
    fn change(&self, who: &Claims) -> Result<(), Response> {
        if self.changes.take(who.sub, Instant::now()) {
            Ok(())
        } else {
            Err(error(StatusCode::TOO_MANY_REQUESTS, "Too many changes in a minute. Try again shortly."))
        }
    }

    /// One invitation by `who` from `peer`, counted against both; refused when either hour is spent.
    fn invitation(&self, who: &Claims, peer: IpAddr, headers: &HeaderMap) -> Result<(), Response> {
        let now = Instant::now();
        let by_account = self.invites_by_account.take(who.sub, now);
        let by_address = self.invites_by_address.take(guard::client_ip_of(peer, headers), now);
        if by_account && by_address {
            Ok(())
        } else {
            Err(error(StatusCode::TOO_MANY_REQUESTS, "Too many invitations in an hour. Try again later."))
        }
    }
}

/// Where the `Claims` extractor (accounts.rs) finds the accounts behind this router's own state.
impl HasAccounts for Arc<Orgs> {
    fn accounts(&self) -> &Accounts {
        &self.accounts
    }
}

fn valid_id(id: &str) -> bool {
    base64url(id, ID_LENGTH)
}

/// An id that will not read is refused before anything is looked up.
fn org_id(id: &str) -> Result<(), Response> {
    if valid_id(id) {
        Ok(())
    } else {
        Err(error(StatusCode::BAD_REQUEST, "That organization's id could not be read."))
    }
}

/// A name as it is kept: trimmed, 1 to 60 characters.
fn name_of(name: &str) -> Result<&str, Response> {
    let name = name.trim();
    if NAME_LENGTH.contains(&name.chars().count()) {
        Ok(name)
    } else {
        Err(error(StatusCode::BAD_REQUEST, "An organization's name is 1 to 60 characters."))
    }
}

/// A hue as it is kept: one of the app's, or none.
fn hue_of(hue: Option<&str>) -> Result<Option<&str>, Response> {
    match hue {
        None => Ok(None),
        Some(hue) if HUES.contains(&hue) => Ok(Some(hue)),
        Some(_) => Err(error(StatusCode::BAD_REQUEST, "That hue is not one of the workspace hues.")),
    }
}

/// The store's refusals, each in its words.
fn refused(err: OrgWrite) -> Response {
    match err {
        OrgWrite::NoSuchOrg => error(StatusCode::NOT_FOUND, "No such organization."),
        OrgWrite::AdminOnly => error(StatusCode::FORBIDDEN, "Only the owner or an admin can do that."),
        OrgWrite::OwnerOnly => error(StatusCode::FORBIDDEN, "Only the owner can do that."),
        OrgWrite::TooManyOrgs => error(StatusCode::CONFLICT, "You own as many organizations as you can."),
        OrgWrite::NoSuchHandle => error(StatusCode::NOT_FOUND, "No one has that handle."),
        OrgWrite::NotInOrg => error(StatusCode::NOT_FOUND, "No one by that handle is in this organization."),
        OrgWrite::AlreadyMember => error(StatusCode::CONFLICT, "They are already a member."),
        OrgWrite::Declined => error(StatusCode::CONFLICT, "They declined; ask again tomorrow."),
        OrgWrite::InviteeFull => error(StatusCode::CONFLICT, "They have as many invitations waiting as they can."),
        OrgWrite::Full => error(StatusCode::CONFLICT, "The organization is full."),
        OrgWrite::RemoveAdmin => error(StatusCode::FORBIDDEN, "Only the owner can remove an admin."),
        OrgWrite::HandOver => error(StatusCode::FORBIDDEN, "Hand the organization over first."),
        OrgWrite::NotJoined => error(StatusCode::CONFLICT, "They have not joined yet."),
        OrgWrite::NotInvited => error(StatusCode::NOT_FOUND, "You were not invited."),
        OrgWrite::Failed => error(StatusCode::INTERNAL_SERVER_ERROR, "That could not be stored."),
    }
}

// --- the shapes on the wire ------------------------------------------------------

fn row_json(row: &OrgRow) -> Value {
    json!({
        "id": row.id, "name": row.name, "hue": row.hue, "role": row.role.as_str(), "state": row.state,
        "members": row.members, "invitedBy": row.invited_by, "createdAt": millis(row.created_at),
    })
}

fn member_json(member: &Member) -> Value {
    json!({ "handle": member.handle, "role": member.role.as_str(), "state": member.state, "since": millis(member.since), "invitedBy": member.invited_by })
}

fn org_json(org: &Org) -> Value {
    json!({
        "id": org.id, "name": org.name, "hue": org.hue, "role": org.role.as_str(), "state": org.state,
        "invitedBy": org.invited_by, "createdAt": millis(org.created_at),
        "members": org.members.iter().map(member_json).collect::<Vec<_>>(),
    })
}

fn with_org(result: Result<Org, OrgWrite>, status: StatusCode) -> Response {
    match result {
        Ok(org) => (status, Json(json!({ "org": org_json(&org) }))).into_response(),
        Err(err) => refused(err),
    }
}

fn with_member(result: Result<Member, OrgWrite>) -> Response {
    match result {
        Ok(member) => Json(json!({ "member": member_json(&member) })).into_response(),
        Err(err) => refused(err),
    }
}

/// A field that may be absent (leave it), null (clear it) or a value: serde reads a missing field and a null one
/// alike unless told apart, and a hue has both meanings.
fn absent_null_or<'de, D: Deserializer<'de>>(d: D) -> Result<Option<Option<String>>, D::Error> {
    Option::<String>::deserialize(d).map(Some)
}

#[derive(Deserialize)]
struct CreateBody {
    name: String,
    #[serde(default)]
    hue: Option<String>,
}

#[derive(Deserialize)]
struct UpdateBody {
    #[serde(default)]
    name: Option<String>,
    #[serde(default, deserialize_with = "absent_null_or")]
    hue: Option<Option<String>>,
}

#[derive(Deserialize)]
struct InviteBody {
    handle: String,
}

#[derive(Deserialize)]
struct RoleBody {
    role: String,
}

#[derive(Deserialize)]
struct AnswerBody {
    accept: bool,
}

// --- the routes -------------------------------------------------------------------

async fn create_org(State(orgs): State<Arc<Orgs>>, who: Claims, Json(body): Json<CreateBody>) -> Result<Response, Response> {
    orgs.change(&who)?;
    let name = name_of(&body.name)?;
    let hue = hue_of(body.hue.as_deref())?;
    Ok(with_org(orgs.accounts.store.create_org(who.sub, &fresh_id(), name, hue, now_secs(), ORGS_OWNED), StatusCode::CREATED))
}

async fn list_orgs(State(orgs): State<Arc<Orgs>>, who: Claims) -> Response {
    let list: Vec<Value> = orgs.accounts.store.orgs_of(who.sub).iter().map(row_json).collect();
    Json(json!({ "orgs": list })).into_response()
}

async fn read_org(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    match orgs.accounts.store.org_of(who.sub, &id) {
        Some(org) => Ok(Json(json!({ "org": org_json(&org) })).into_response()),
        None => Err(refused(OrgWrite::NoSuchOrg)),
    }
}

async fn update_org(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims, Json(body): Json<UpdateBody>) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    let name = body.name.as_deref().map(name_of).transpose()?;
    let hue = match &body.hue {
        None => None,
        Some(hue) => Some(hue_of(hue.as_deref())?),
    };
    Ok(with_org(orgs.accounts.store.update_org(who.sub, &id, name, hue, now_secs()), StatusCode::OK))
}

async fn delete_org(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    match orgs.accounts.store.delete_org(who.sub, &id, now_secs()) {
        Ok(()) => Ok(Json(json!({ "deleted": true })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

async fn invite(
    State(orgs): State<Arc<Orgs>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    who: Claims,
    Json(body): Json<InviteBody>,
) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.invitation(&who, peer.ip(), &headers)?;
    // A handle that could not be anyone's is nobody's: the same answer as one that is not, and no shape to learn.
    let handle = body.handle.trim();
    if !crate::accounts::valid_handle(handle) {
        return Err(refused(OrgWrite::NoSuchHandle));
    }
    let caps = InviteCaps { rows_per_org: ORG_ROWS, pending_per_invitee: PENDING_PER_INVITEE, decline_cooldown: DECLINE_COOLDOWN };
    Ok(with_member(orgs.accounts.store.invite(who.sub, &id, handle, now_secs(), caps)))
}

async fn remove_member(State(orgs): State<Arc<Orgs>>, Path((id, handle)): Path<(String, String)>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    match orgs.accounts.store.remove_member(who.sub, &id, handle.trim(), now_secs()) {
        Ok(()) => Ok(Json(json!({ "removed": true })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

async fn set_role(State(orgs): State<Arc<Orgs>>, Path((id, handle)): Path<(String, String)>, who: Claims, Json(body): Json<RoleBody>) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    let Some(role) = Role::parse(body.role.trim()) else {
        return Err(error(StatusCode::BAD_REQUEST, "A role is owner, admin or member."));
    };
    Ok(with_member(orgs.accounts.store.set_role(who.sub, &id, handle.trim(), role, now_secs())))
}

async fn answer_invite(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims, Json(body): Json<AnswerBody>) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    match orgs.accounts.store.answer_invite(who.sub, &id, body.accept, now_secs()) {
        Ok(Some(org)) => Ok(Json(json!({ "org": org_json(&org) })).into_response()),
        Ok(None) => Ok(Json(json!({ "declined": true })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    Router::new()
        .route("/api/v1/orgs", get(list_orgs).post(create_org))
        .route("/api/v1/orgs/{id}", get(read_org).put(update_org).delete(delete_org))
        .route("/api/v1/orgs/{id}/members", post(invite))
        .route("/api/v1/orgs/{id}/members/{handle}", axum::routing::delete(remove_member).put(set_role))
        .route("/api/v1/orgs/{id}/invite", post(answer_invite))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
        .with_state(Orgs::new(accounts))
}
