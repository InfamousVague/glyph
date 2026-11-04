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
//!   POST   /api/v1/orgs/{id}/links             { expiresIn?, maxUses? }  an invite link, by the owner or an admin
//!   GET    /api/v1/orgs/{id}/links                              its working links, for the owner or an admin
//!   DELETE /api/v1/orgs/{id}/links/{link}                       a link turned off
//!   POST   /api/v1/orgs/{id}/emails            { email }        an invitation by email, by the owner or an admin: mailed
//!   GET    /api/v1/orgs/{id}/emails                             its email invitations waiting, for the owner or an admin
//!   POST   /api/v1/orgs/{id}/emails/{invite}/resend             one mailed again, its fortnight started again
//!   DELETE /api/v1/orgs/{id}/emails/{invite}                    one turned off
//!   GET    /api/v1/joins/{code}                                 what a link joins, before it is followed
//!   POST   /api/v1/joins/{code}                                 the caller in, by the link
//!   POST   /api/v1/joins/preview               { code }         what a link joins, for the join page, signed out
//!   POST   /api/v1/orgs/{id}/ais               { name }         an AI seen through the caller's connector: its entry made, or seen again
//!   DELETE /api/v1/orgs/{id}/ais/{ai}                           an entry removed, by the owner, an admin, or the member it came through
//!
//! An AI's entry (store/org_ais.rs; Matt: "when an AI has accessed an ORG add it as a member labeled as (AI)") is a
//! record beside the members, answered as `ais` on the organization: a name, the member it came through, first and
//! last seen. It is not a member - no key wrap, no seat, nothing the key's `missing` or its turn counts - and removing
//! one removes the record, not the member's access, which is what their connector reads with.
//!
//! And, for notes shared in an organization (docs/SHARED.md): colours, the account's encryption key pair, and the
//! organization key wrapped per member (store/keys.rs). A colour is one of the app's hues, or null for none.
//!
//!   PUT    /api/v1/account/colour              { hue }         the account's own colour
//!   GET    /api/v1/account/key                                 the account's key pair: the public key, the private one sealed
//!   PUT    /api/v1/account/key                 { pub, sealed } registered once; 409 with the one that stands
//!   PUT    /api/v1/orgs/{id}/colour            { hue }         the caller's colour in this organization, or null for the account's
//!   GET    /api/v1/orgs/{id}/keys?generation=                  the generation in force, the caller's wrap (at an older generation, asked), who lacks one, whether a turn is owed
//!   POST   /api/v1/orgs/{id}/keys              { generation, make?, wraps: [{ handle, wrapped }] }  wraps by a member holding the key; `make` a new generation
//!
//! An invite link (store/org_links.rs) is a 128-bit code, so holding one is the permission: anyone signed in who has
//! it may see the organization's name and join it as a member, until it expires, is used up or is turned off. It
//! names nobody, so it is no handle oracle and is limited with every other change. A code that is not one, and one
//! that stopped working, get the same 404.
//!
//! An invitation by email (Matt, 2026-11-03: "email invites to join orgs on ghost markdown so people can click a link
//! download the app and be redirected on the app to join an org") is an invite link of one use that lasts a fortnight,
//! kept with the address it was mailed to (store/org_links.rs), and a mail through the outbox (outbox.rs) with the
//! link `https://ghostmarkdown.com/join#<code>`: the page there (landing/join.html) opens the app, which claims the
//! address on Android, or helps get it first. Joining by it is joining by a link, so the organization key reaches the
//! new member as it reaches anyone who joins: wrapped by a member holding it (`/keys`). Accounts have no addresses, so
//! the answer says nothing of who has one. It is mail from our domain with words a stranger chose (the organization's
//! name), so it is limited hardest: ten an hour per account, twenty per client address, fifty a day per organization
//! and three a day to any one address, a resend counting as a send; and without GLYPH_MAILGUN_API_KEY it answers 503.
//!
//! The join page shows the organization's name before anyone signs in: `POST joins/preview` with the code in the body,
//! never the path, so it reaches no log; sixty a minute per client address.
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
use crate::outbox::{html_escape, Letter};
use crate::store::{AccountKey, EmailInvite, EmailMailing, InviteCaps, KeyWrite, LinkPreview, Member, Org, OrgAi, OrgKeys, OrgLink, OrgRow, OrgWrite, Role, Wrap};
use crate::wire::{base64url, error, fresh_id, millis, now_secs};
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post, put};
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
/// Working invite links one organization may have at once.
const LINKS_PER_ORG: usize = 10;
/// How long a link may be made to last, in seconds: an hour to thirty days, or for good when none is given.
const LINK_LIFETIME: std::ops::RangeInclusive<i64> = 3600..=30 * 24 * 3600;
/// A code is a fresh id: 22 characters.
const CODE_LENGTH: std::ops::RangeInclusive<usize> = 16..=64;
/// A body here is a name, a hue, a handle or a role.
/// An AI's name, as its app gave it (store/org_ais.rs).
const AI_NAME_LENGTH: std::ops::RangeInclusive<usize> = 1..=40;
/// AI names one member holds at once in one organization; past it the one seen longest ago goes.
const AIS_PER_MEMBER: i64 = 8;
const BODY_LIMIT: usize = 16 * 1024;
/// How long an invitation by email lasts: a fortnight.
const EMAIL_LIFETIME: i64 = 14 * 24 * 3600;
/// Invitations mailed (and mailed again) an hour, per account, and per client address.
const EMAILS_PER_HOUR: u32 = 10;
const EMAILS_PER_ADDRESS_PER_HOUR: u32 = 20;
/// A day, per organization, and to any one address.
const EMAILS_PER_ORG_PER_DAY: u32 = 50;
const EMAILS_PER_RECIPIENT_PER_DAY: u32 = 3;
/// Email invitations one organization may have waiting: as many as it has seats.
const EMAILS_WAITING: usize = ORG_ROWS as usize;
/// The join page's look at a code, a minute, per client address.
const PREVIEWS_PER_MINUTE: u32 = 60;
/// Where the join page is, unless GLYPH_PUBLIC_URL says (as hooks.rs reads it).
const DEFAULT_PUBLIC_URL: &str = "https://ghostmarkdown.com";

pub struct Orgs {
    accounts: Arc<Accounts>,
    invites_by_account: guard::RateLimiter<i64>,
    invites_by_address: guard::RateLimiter<IpAddr>,
    changes: guard::RateLimiter<i64>,
    emails_by_account: guard::RateLimiter<i64>,
    emails_by_address: guard::RateLimiter<IpAddr>,
    emails_by_org: guard::RateLimiter<String>,
    emails_to: guard::RateLimiter<String>,
    previews: guard::RateLimiter<IpAddr>,
    /// What a mailed link starts with: `https://ghostmarkdown.com`.
    public_url: String,
}

impl Orgs {
    pub fn new(accounts: Arc<Accounts>) -> Arc<Self> {
        let now = Instant::now();
        Arc::new(Self {
            accounts,
            invites_by_account: guard::RateLimiter::per_hour(INVITES_PER_HOUR, now),
            invites_by_address: guard::RateLimiter::per_hour(INVITES_PER_HOUR, now),
            changes: guard::RateLimiter::new(CHANGES_PER_MINUTE, now),
            emails_by_account: guard::RateLimiter::per_hour(EMAILS_PER_HOUR, now),
            emails_by_address: guard::RateLimiter::per_hour(EMAILS_PER_ADDRESS_PER_HOUR, now),
            emails_by_org: guard::RateLimiter::per_day(EMAILS_PER_ORG_PER_DAY, now),
            emails_to: guard::RateLimiter::per_day(EMAILS_PER_RECIPIENT_PER_DAY, now),
            previews: guard::RateLimiter::new(PREVIEWS_PER_MINUTE, now),
            public_url: std::env::var("GLYPH_PUBLIC_URL").ok().map(|u| u.trim().trim_end_matches('/').to_string()).filter(|u| !u.is_empty()).unwrap_or_else(|| DEFAULT_PUBLIC_URL.into()),
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

impl Orgs {
    /// One mailing by `who` from `peer`, of `org`'s, to `to`: counted against all four; refused when any is spent.
    fn mailing(&self, who: &Claims, peer: IpAddr, headers: &HeaderMap, org: &str, to: &str) -> Result<(), Response> {
        let now = Instant::now();
        let by_account = self.emails_by_account.take(who.sub, now);
        let by_address = self.emails_by_address.take(guard::client_ip_of(peer, headers), now);
        if !(by_account && by_address) {
            return Err(error(StatusCode::TOO_MANY_REQUESTS, "Too many email invitations in an hour. Try again later."));
        }
        if !self.emails_by_org.take(org.to_string(), now) {
            return Err(error(StatusCode::TOO_MANY_REQUESTS, "This organization has sent as many email invitations as it can today. Try again tomorrow."));
        }
        if !self.emails_to.take(to.to_string(), now) {
            return Err(error(StatusCode::TOO_MANY_REQUESTS, "That address has been sent enough invitations today. Try again tomorrow."));
        }
        Ok(())
    }

    /// The link a mailed invitation carries: the join page, the code after the `#`, where only the browser reads it.
    fn join_url(&self, code: &str) -> String {
        format!("{}/join#{code}", self.public_url)
    }

    /// The mail for an invitation: who asked, to what, the one link, and how to get the app.
    fn letter(&self, mailing: &EmailMailing, inviter: &str) -> Letter {
        // The organization's name is a stranger's words in our mail: one line, no controls.
        let org: String = mailing.org_name.chars().map(|c| if c.is_control() { ' ' } else { c }).collect();
        let link = self.join_url(&mailing.code);
        let subject = format!("@{inviter} invited you to {org} on Ghost Markdown");
        let text = format!(
            "@{inviter} invited you to join {org} on Ghost Markdown, the notes app you write in by typing or by voice.\n\n\
             Join {org}:\n{link}\n\n\
             The link opens Ghost Markdown if you have it. If you don't, the page helps you download it: then come back to \
             this mail and tap the link again, or paste it into the app when you sign up.\n\n\
             The invitation lasts 14 days and works once. If you weren't expecting it, you can ignore this mail.\n"
        );
        let (org_h, inviter_h, link_h) = (html_escape(&org), html_escape(inviter), html_escape(&link));
        let html = format!(
            "<!doctype html><html><body style=\"margin:0;padding:24px;background:#f6f5f2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#1d1c1a\">\
             <div style=\"max-width:480px;margin:0 auto;background:#fff;border-radius:16px;padding:32px\">\
             <p style=\"margin:0 0 8px;font-size:13px;color:#6b6862\">Ghost Markdown</p>\
             <h1 style=\"margin:0 0 16px;font-size:22px;line-height:1.3\">@{inviter_h} invited you to join {org_h}</h1>\
             <p style=\"margin:0 0 24px;font-size:15px;line-height:1.5\">Ghost Markdown is a notes app you write in by typing or by voice. Join the team to share notes with them.</p>\
             <p style=\"margin:0 0 24px\"><a href=\"{link_h}\" style=\"display:inline-block;background:#1d1c1a;color:#fff;text-decoration:none;font-size:16px;font-weight:600;padding:14px 24px;border-radius:999px\">Join {org_h}</a></p>\
             <p style=\"margin:0 0 12px;font-size:14px;line-height:1.5;color:#45433f\">The link opens Ghost Markdown if you have it. If you don't, the page helps you download it: then come back here and tap <strong>Join</strong> again, or paste the link into the app when you sign up.</p>\
             <p style=\"margin:0;font-size:13px;line-height:1.5;color:#6b6862\">The invitation lasts 14 days and works once. Not expecting it? You can ignore this mail.<br><span style=\"word-break:break-all\">{link_h}</span></p>\
             </div></body></html>"
        );
        Letter { to: mailing.invite.email.clone(), subject, text, html }
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
        OrgWrite::NoSuchLink => error(StatusCode::NOT_FOUND, "That invite link has expired or was turned off."),
        OrgWrite::TooManyLinks => error(StatusCode::CONFLICT, "This organization has as many invite links as it can. Turn one off first."),
        OrgWrite::TooManyEmails => error(StatusCode::CONFLICT, "This organization has as many email invitations waiting as it can. Turn one off first."),
        OrgWrite::NoSuchAi => error(StatusCode::NOT_FOUND, "No such AI in this organization."),
        OrgWrite::Failed => error(StatusCode::INTERNAL_SERVER_ERROR, "That could not be stored."),
    }
}

// --- the shapes on the wire ------------------------------------------------------

fn row_json(row: &OrgRow) -> Value {
    json!({
        "id": row.id, "name": row.name, "hue": row.hue, "role": row.role.as_str(), "state": row.state,
        "members": row.members, "invitedBy": row.invited_by, "createdAt": millis(row.created_at),
        "colour": row.colour, "keys": { "generation": row.key_generation, "mine": row.key_mine, "missing": row.key_missing, "stale": row.key_stale },
    })
}

fn member_json(member: &Member) -> Value {
    json!({
        "handle": member.handle, "role": member.role.as_str(), "state": member.state, "since": millis(member.since), "invitedBy": member.invited_by,
        "colour": member.colour, "pub": member.pub_key,
    })
}

fn org_json(org: &Org) -> Value {
    json!({
        "id": org.id, "name": org.name, "hue": org.hue, "role": org.role.as_str(), "state": org.state,
        "invitedBy": org.invited_by, "createdAt": millis(org.created_at),
        "colour": org.colour, "keys": { "generation": org.key_generation, "mine": org.key_mine, "missing": org.key_missing, "stale": org.key_stale },
        "members": org.members.iter().map(member_json).collect::<Vec<_>>(),
        "ais": org.ais.iter().map(ai_json).collect::<Vec<_>>(),
    })
}

fn ai_json(ai: &OrgAi) -> Value {
    json!({ "id": ai.id, "name": ai.name, "via": ai.via, "firstSeen": millis(ai.first_seen), "lastSeen": millis(ai.last_seen) })
}

fn key_json(key: &AccountKey) -> Value {
    json!({ "pub": key.pub_key, "sealed": key.sealed })
}

fn keys_json(keys: &OrgKeys) -> Value {
    json!({
        "generation": keys.generation, "mine": keys.mine, "stale": keys.stale,
        "missing": keys.missing.iter().map(|(handle, pub_key)| json!({ "handle": handle, "pub": pub_key })).collect::<Vec<_>>(),
    })
}

fn link_json(link: &OrgLink) -> Value {
    json!({
        "id": link.id, "code": link.code, "createdAt": millis(link.created_at), "expiresAt": link.expires_at.map(millis),
        "maxUses": link.max_uses, "uses": link.uses, "by": link.by,
    })
}

fn email_json(invite: &EmailInvite) -> Value {
    json!({
        "id": invite.id, "email": invite.email, "createdAt": millis(invite.created_at), "expiresAt": invite.expires_at.map(millis),
        "sentAt": invite.sent_at.map(millis), "by": invite.by,
    })
}

fn preview_json(preview: &LinkPreview, member: bool) -> Value {
    json!({
        "org": { "id": preview.org, "name": preview.name, "hue": preview.hue, "members": preview.members },
        "by": preview.by, "member": member,
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LinkBody {
    /// Seconds from now; none for a link that lasts until it is turned off.
    #[serde(default)]
    expires_in: Option<i64>,
    /// How many may join by it; none for no limit.
    #[serde(default)]
    max_uses: Option<i64>,
}

#[derive(Deserialize)]
struct EmailBody {
    email: String,
}

#[derive(Deserialize)]
struct CodeBody {
    code: String,
}

/// Longest an address may be (RFC 5321's path less its brackets).
const EMAIL_LENGTH: usize = 254;

/// An address as it is kept and mailed: trimmed and lowercased, one `@`, a local part of 1 to 64 characters with
/// nothing a header could be broken with, and a domain of dotted labels ending in letters. Not every address RFC 5322
/// allows; every address people type.
fn email_of(text: &str) -> Result<String, Response> {
    let refuse = || error(StatusCode::BAD_REQUEST, "That doesn't look like an email address.");
    let email = text.trim().to_lowercase();
    if email.len() > EMAIL_LENGTH {
        return Err(refuse());
    }
    let Some((local, domain)) = email.split_once('@') else { return Err(refuse()) };
    let local_ok = (1..=64).contains(&local.len())
        && !local.starts_with('.')
        && !local.ends_with('.')
        && !local.contains("..")
        && local.chars().all(|c| c.is_ascii_alphanumeric() || "!#$%&'*+/=?^_`{|}~.-".contains(c));
    let labels: Vec<&str> = domain.split('.').collect();
    let domain_ok = labels.len() >= 2
        && labels.iter().all(|l| (1..=63).contains(&l.len()) && !l.starts_with('-') && !l.ends_with('-') && l.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'))
        && labels.last().is_some_and(|tld| tld.len() >= 2 && tld.chars().all(|c| c.is_ascii_alphabetic()));
    if local_ok && domain_ok {
        Ok(email)
    } else {
        Err(refuse())
    }
}

/// A code that will not read is no code: the same answer as one that does not work, and no shape to learn.
fn code_of(code: &str) -> Result<&str, Response> {
    let code = code.trim();
    if base64url(code, CODE_LENGTH) {
        Ok(code)
    } else {
        Err(refused(OrgWrite::NoSuchLink))
    }
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
    // And the account's own colour, which Settings › Account shows whether or not it is in any organization.
    Json(json!({ "orgs": list, "colour": orgs.accounts.store.account_hue(who.sub) })).into_response()
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

async fn make_link(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims, Json(body): Json<LinkBody>) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    if body.expires_in.is_some_and(|secs| !LINK_LIFETIME.contains(&secs)) {
        return Err(error(StatusCode::BAD_REQUEST, "A link lasts an hour to thirty days, or until it is turned off."));
    }
    if body.max_uses.is_some_and(|uses| !(1..=ORG_ROWS).contains(&uses)) {
        return Err(error(StatusCode::BAD_REQUEST, "A link may be used 1 to 50 times, or without a limit."));
    }
    let now = now_secs();
    let expires_at = body.expires_in.map(|secs| now + secs);
    match orgs.accounts.store.make_link(who.sub, &id, &fresh_id(), &fresh_id(), expires_at, body.max_uses, now, LINKS_PER_ORG) {
        Ok(link) => Ok((StatusCode::CREATED, Json(json!({ "link": link_json(&link) }))).into_response()),
        Err(err) => Err(refused(err)),
    }
}

async fn list_links(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    match orgs.accounts.store.links_of(who.sub, &id, now_secs()) {
        Ok(links) => Ok(Json(json!({ "links": links.iter().map(link_json).collect::<Vec<_>>() })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

async fn drop_link(State(orgs): State<Arc<Orgs>>, Path((id, link)): Path<(String, String)>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    if !valid_id(&link) {
        return Err(refused(OrgWrite::NoSuchLink));
    }
    match orgs.accounts.store.drop_link(who.sub, &id, &link) {
        Ok(()) => Ok(Json(json!({ "dropped": true })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

/// Nothing can be mailed from this service: said before anything is made.
fn no_mail() -> Response {
    error(StatusCode::SERVICE_UNAVAILABLE, "Email invitations aren't set up on this service yet. Send an invite link instead.")
}

/// The mail for `mailing` sent; a failure said in plain words (the outbox's own go to the log).
async fn send_invite(orgs: &Orgs, mailing: &EmailMailing, inviter: &str) -> Result<(), Response> {
    let letter = orgs.letter(mailing, inviter);
    orgs.accounts.outbox.send(&letter).await.map_err(|why| {
        eprintln!("glyph-api: an email invitation could not be sent: {why}");
        error(StatusCode::BAD_GATEWAY, "The email couldn't be sent. Try again in a moment.")
    })
}

/// `POST orgs/{id}/emails`: an invitation by email made (or the one waiting for that address renewed) and mailed.
async fn invite_email(
    State(orgs): State<Arc<Orgs>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    who: Claims,
    Json(body): Json<EmailBody>,
) -> Result<Response, Response> {
    org_id(&id)?;
    let email = email_of(&body.email)?;
    if !orgs.accounts.outbox.ready() {
        return Err(no_mail());
    }
    // A stranger, or a member who may not invite, is refused before anything is counted against the organization.
    orgs.accounts.store.email_invites_of(who.sub, &id, now_secs()).map_err(refused)?;
    orgs.mailing(&who, peer.ip(), &headers, &id, &email)?;
    let now = now_secs();
    let made = fresh_id();
    let mailing = orgs.accounts.store.make_email_invite(who.sub, &id, &made, &fresh_id(), &email, now + EMAIL_LIFETIME, now, EMAILS_WAITING, ORG_ROWS).map_err(refused)?;
    let inviter = mailing.invite.by.clone().unwrap_or_else(|| who.handle.clone());
    if let Err(failed) = send_invite(&orgs, &mailing, &inviter).await {
        // Never listed as waiting when it never went: a new one is dropped, a renewed one stays as it was sent before.
        if mailing.invite.id == made {
            let _ = orgs.accounts.store.drop_link(who.sub, &id, &mailing.invite.id);
        }
        return Err(failed);
    }
    Ok((StatusCode::CREATED, Json(json!({ "invite": email_json(&mailing.invite) }))).into_response())
}

/// `GET orgs/{id}/emails`: the email invitations waiting.
async fn list_emails(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    match orgs.accounts.store.email_invites_of(who.sub, &id, now_secs()) {
        Ok(invites) => Ok(Json(json!({ "invites": invites.iter().map(email_json).collect::<Vec<_>>(), "mail": orgs.accounts.outbox.ready() })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

/// `POST orgs/{id}/emails/{invite}/resend`: one waiting, mailed again.
async fn resend_email(
    State(orgs): State<Arc<Orgs>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path((id, invite)): Path<(String, String)>,
    who: Claims,
) -> Result<Response, Response> {
    org_id(&id)?;
    if !valid_id(&invite) {
        return Err(refused(OrgWrite::NoSuchLink));
    }
    if !orgs.accounts.outbox.ready() {
        return Err(no_mail());
    }
    let now = now_secs();
    let waiting = orgs.accounts.store.email_invites_of(who.sub, &id, now).map_err(refused)?;
    let Some(found) = waiting.iter().find(|each| each.id == invite) else {
        return Err(refused(OrgWrite::NoSuchLink));
    };
    orgs.mailing(&who, peer.ip(), &headers, &id, &found.email)?;
    let mailing = orgs.accounts.store.resend_email_invite(who.sub, &id, &invite, now + EMAIL_LIFETIME, now).map_err(refused)?;
    // The one asking now is who the mail says invited them.
    send_invite(&orgs, &mailing, &who.handle).await?;
    Ok(Json(json!({ "invite": email_json(&mailing.invite) })).into_response())
}

/// `DELETE orgs/{id}/emails/{invite}`: one turned off, its address gone with it.
async fn drop_email(State(orgs): State<Arc<Orgs>>, Path((id, invite)): Path<(String, String)>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    if !valid_id(&invite) {
        return Err(refused(OrgWrite::NoSuchLink));
    }
    let waiting = orgs.accounts.store.email_invites_of(who.sub, &id, now_secs()).map_err(refused)?;
    if !waiting.iter().any(|each| each.id == invite) {
        return Err(refused(OrgWrite::NoSuchLink));
    }
    match orgs.accounts.store.drop_link(who.sub, &id, &invite) {
        Ok(()) => Ok(Json(json!({ "dropped": true })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

#[derive(Deserialize)]
struct AiBody {
    name: String,
}

/// An AI's name as it is kept: trimmed, 1 to 40 characters, none of them a control character.
fn ai_name(name: &str) -> Result<&str, Response> {
    let name = name.trim();
    if AI_NAME_LENGTH.contains(&name.chars().count()) && !name.chars().any(char::is_control) {
        Ok(name)
    } else {
        Err(error(StatusCode::BAD_REQUEST, "An AI's name is 1 to 40 characters."))
    }
}

async fn see_ai(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims, Json(body): Json<AiBody>) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    let name = ai_name(&body.name)?;
    match orgs.accounts.store.ai_seen(who.sub, &id, &fresh_id(), name, now_secs(), AIS_PER_MEMBER) {
        Ok(ai) => Ok(Json(json!({ "ai": ai_json(&ai) })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

async fn drop_ai(State(orgs): State<Arc<Orgs>>, Path((id, ai)): Path<(String, String)>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    if !valid_id(&ai) {
        return Err(refused(OrgWrite::NoSuchAi));
    }
    match orgs.accounts.store.drop_ai(who.sub, &id, &ai) {
        Ok(()) => Ok(Json(json!({ "removed": true })).into_response()),
        Err(err) => Err(refused(err)),
    }
}

async fn preview_join(State(orgs): State<Arc<Orgs>>, Path(code): Path<String>, who: Claims) -> Result<Response, Response> {
    let code = code_of(&code)?;
    orgs.change(&who)?;
    let Some(preview) = orgs.accounts.store.link_preview(code, now_secs()) else {
        return Err(refused(OrgWrite::NoSuchLink));
    };
    let member = orgs.accounts.store.org_of(who.sub, &preview.org).is_some();
    Ok(Json(preview_json(&preview, member)).into_response())
}

/// `POST joins/preview`: what a link joins, for the join page, which nobody need be signed in to see. The code is in
/// the body so it reaches no log; the answer is the organization's name, hue and size and who made the link, as the
/// signed-in look gives, without the organization's id.
async fn preview_signed_out(State(orgs): State<Arc<Orgs>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Json(body): Json<CodeBody>) -> Result<Response, Response> {
    if !orgs.previews.take(guard::client_ip_of(peer.ip(), &headers), Instant::now()) {
        return Err(error(StatusCode::TOO_MANY_REQUESTS, "Too many looks in a minute. Try again shortly."));
    }
    let code = code_of(&body.code)?;
    let Some(preview) = orgs.accounts.store.link_preview(code, now_secs()) else {
        return Err(refused(OrgWrite::NoSuchLink));
    };
    Ok(Json(json!({ "org": { "name": preview.name, "hue": preview.hue, "members": preview.members }, "by": preview.by })).into_response())
}

async fn join(State(orgs): State<Arc<Orgs>>, Path(code): Path<String>, who: Claims) -> Result<Response, Response> {
    let code = code_of(&code)?;
    orgs.change(&who)?;
    Ok(with_org(orgs.accounts.store.join_by_link(who.sub, code, now_secs(), ORG_ROWS), StatusCode::OK))
}

// --- colours and keys (docs/SHARED.md, S2, S3, S7) -------------------------------------------

/// A sealed private key, or the organization key wrapped for one member: base64url, up to this long.
const WRAP_LIMIT: usize = 4096;
/// An encryption public key: a P-256 point, base64url.
const PUB_LIMIT: usize = 256;
/// Wraps in one post: at most the organization's rows.
const WRAPS_PER_POST: usize = 50;

#[derive(Deserialize)]
struct ColourBody {
    /// One of the hues, or null (or nothing) for none: the app's own ink, or in an organization the account's colour.
    hue: Option<String>,
}

#[derive(Deserialize)]
struct KeyBody {
    #[serde(rename = "pub")]
    pub_key: String,
    sealed: String,
}

#[derive(Deserialize)]
struct WrapBody {
    handle: String,
    wrapped: String,
}

#[derive(Deserialize)]
struct KeysBody {
    generation: i64,
    /// A new generation, the one after the generation in force (the first, from none), rather than wraps at it.
    #[serde(default)]
    make: bool,
    #[serde(default)]
    wraps: Vec<WrapBody>,
}

/// A colour as it is kept: one of the hues, with ink - the app's own, no colour - kept as none.
fn colour_of(hue: Option<&str>) -> Result<Option<&str>, Response> {
    Ok(hue_of(hue)?.filter(|hue| *hue != "ink"))
}

fn refused_key(err: KeyWrite) -> Response {
    match err {
        KeyWrite::NoSuchOrg => refused(OrgWrite::NoSuchOrg),
        KeyWrite::Generation(generation) => (StatusCode::CONFLICT, Json(json!({ "error": "That is not the generation in force.", "generation": generation }))).into_response(),
        KeyWrite::HasKey(_) | KeyWrite::Failed => error(StatusCode::INTERNAL_SERVER_ERROR, "That could not be stored."),
    }
}

/// `PUT account/colour`: the account's own colour, set or cleared.
async fn account_colour(State(orgs): State<Arc<Orgs>>, who: Claims, Json(body): Json<ColourBody>) -> Result<Response, Response> {
    orgs.change(&who)?;
    let hue = colour_of(body.hue.as_deref())?;
    match orgs.accounts.store.set_account_hue(who.sub, hue) {
        Ok(()) => Ok(Json(json!({ "colour": hue })).into_response()),
        Err(_) => Err(error(StatusCode::INTERNAL_SERVER_ERROR, "That colour could not be stored.")),
    }
}

/// `PUT orgs/{id}/colour`: the caller's colour in this organization, set, or cleared to the account's own.
async fn org_colour(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims, Json(body): Json<ColourBody>) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    let hue = colour_of(body.hue.as_deref())?;
    Ok(with_org(orgs.accounts.store.set_org_hue(who.sub, &id, hue), StatusCode::OK))
}

/// `GET account/key`: the account's encryption key pair, for a device of its that has none yet.
async fn read_key(State(orgs): State<Arc<Orgs>>, who: Claims) -> Result<Response, Response> {
    match orgs.accounts.store.account_key(who.sub) {
        Some(key) => Ok(Json(key_json(&key)).into_response()),
        None => Err(error(StatusCode::NOT_FOUND, "No key pair yet.")),
    }
}

/// `PUT account/key`: the pair this device made, registered; or 409 with the one that stands, which the device adopts.
async fn register_key(State(orgs): State<Arc<Orgs>>, who: Claims, Json(body): Json<KeyBody>) -> Result<Response, Response> {
    orgs.change(&who)?;
    if !base64url(&body.pub_key, 1..=PUB_LIMIT) || !base64url(&body.sealed, 1..=WRAP_LIMIT) {
        return Err(error(StatusCode::BAD_REQUEST, "That key pair could not be read."));
    }
    match orgs.accounts.store.register_key(who.sub, &body.pub_key, &body.sealed, now_secs()) {
        Ok(key) => Ok((StatusCode::CREATED, Json(key_json(&key))).into_response()),
        Err(KeyWrite::HasKey(key)) => {
            let mut answer = key_json(&key);
            answer["error"] = json!("The account has a key pair already; this is it.");
            Ok((StatusCode::CONFLICT, Json(answer)).into_response())
        }
        Err(_) => Err(error(StatusCode::INTERNAL_SERVER_ERROR, "That key pair could not be stored.")),
    }
}

#[derive(Deserialize)]
struct KeysQuery {
    /// An older generation to read the caller's wrap at (S11): for a row sealed before the key turned.
    #[serde(default)]
    generation: Option<i64>,
}

/// `GET orgs/{id}/keys`: the generation in force, the caller's wrap at it (or at `?generation=`), who lacks one, and
/// whether the key owes a turn.
async fn read_org_keys(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, Query(query): Query<KeysQuery>, who: Claims) -> Result<Response, Response> {
    org_id(&id)?;
    if query.generation.is_some_and(|generation| generation < 1) {
        return Err(error(StatusCode::BAD_REQUEST, "That generation could not be read."));
    }
    match orgs.accounts.store.org_keys(who.sub, &id, query.generation) {
        Ok(keys) => Ok(Json(keys_json(&keys)).into_response()),
        Err(err) => Err(refused_key(err)),
    }
}

/// `POST orgs/{id}/keys`: wraps at the generation in force (or the first, from none), by a member holding the key.
async fn post_org_keys(State(orgs): State<Arc<Orgs>>, Path(id): Path<String>, who: Claims, Json(body): Json<KeysBody>) -> Result<Response, Response> {
    org_id(&id)?;
    orgs.change(&who)?;
    let readable = body.generation >= 1
        && body.wraps.len() <= WRAPS_PER_POST
        && body.wraps.iter().all(|wrap| crate::accounts::valid_handle(wrap.handle.trim()) && base64url(&wrap.wrapped, 1..=WRAP_LIMIT));
    if !readable {
        return Err(error(StatusCode::BAD_REQUEST, "Those wraps could not be read."));
    }
    let wraps: Vec<Wrap> = body.wraps.iter().map(|wrap| Wrap { handle: wrap.handle.trim().to_string(), wrapped: wrap.wrapped.clone() }).collect();
    match orgs.accounts.store.post_org_keys(who.sub, &id, body.generation, body.make, &wraps, now_secs()) {
        Ok(keys) => Ok(Json(keys_json(&keys)).into_response()),
        Err(err) => Err(refused_key(err)),
    }
}

/// Every email invitation that has expired deleted, with its address, every hour (docs/TEAMS.md, landing/privacy.html).
pub fn sweep_every_hour(accounts: Arc<Accounts>) {
    tokio::spawn(async move {
        let mut every = tokio::time::interval(std::time::Duration::from_secs(3600));
        loop {
            every.tick().await;
            let swept = accounts.store.sweep_email_invites(now_secs());
            if swept > 0 {
                eprintln!("glyph-api swept {swept} expired email invitations");
            }
        }
    });
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    Router::new()
        .route("/api/v1/account/colour", put(account_colour))
        .route("/api/v1/account/key", get(read_key).put(register_key))
        .route("/api/v1/orgs/{id}/colour", put(org_colour))
        .route("/api/v1/orgs/{id}/keys", get(read_org_keys).post(post_org_keys))
        .route("/api/v1/orgs", get(list_orgs).post(create_org))
        .route("/api/v1/orgs/{id}", get(read_org).put(update_org).delete(delete_org))
        .route("/api/v1/orgs/{id}/members", post(invite))
        .route("/api/v1/orgs/{id}/members/{handle}", axum::routing::delete(remove_member).put(set_role))
        .route("/api/v1/orgs/{id}/invite", post(answer_invite))
        .route("/api/v1/orgs/{id}/links", get(list_links).post(make_link))
        .route("/api/v1/orgs/{id}/links/{link}", axum::routing::delete(drop_link))
        .route("/api/v1/orgs/{id}/ais", post(see_ai))
        .route("/api/v1/orgs/{id}/ais/{ai}", axum::routing::delete(drop_ai))
        .route("/api/v1/orgs/{id}/emails", get(list_emails).post(invite_email))
        .route("/api/v1/orgs/{id}/emails/{invite}", axum::routing::delete(drop_email))
        .route("/api/v1/orgs/{id}/emails/{invite}/resend", post(resend_email))
        .route("/api/v1/joins/preview", post(preview_signed_out))
        .route("/api/v1/joins/{code}", get(preview_join).post(join))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
        .with_state(Orgs::new(accounts))
}
