//! Organizations: a named team of accounts with roles, the invitations that bring people in, and every change to one
//! told to the people in it (src/orgs.rs, docs/TEAMS.md).
//!
//! Matt: "create an organization in order to add users as team members by handle, adding a team member should show
//! them an invite". A name, a hue, who is in and in what role are plaintext here, as handles already are: nothing in
//! an organization is a note, and the notes stay each member's own ciphertext. Every write that tells someone - an
//! invitation, a joining, a removal, a rename - writes their notification row in the same transaction as the change
//! (store/notifications.rs `notify`), so there is no half-state for a device to find. What a person does themself
//! is not news to them - the app keeps a person's own acts out of the feed, as it toasts a voice command rather than
//! recording it - so the one who renamed, removed or deleted is not told; their other devices learn from the
//! organization itself.
//!
//! One invariant, kept here and nowhere else: an organization has exactly one owner row, with state 'member', at all
//! times. Nobody removes the owner, the owner's role changes only by handing over, and a hand-over to someone who has
//! not joined is refused; so an organization can always be renamed, handed over or deleted by someone, and the
//! account-deletion rule (store/accounts.rs) always has an owner to hold to.

use super::notifications::Notice;
use super::Store;
use rusqlite::{params, Connection, OptionalExtension, Row, Transaction};
use serde_json::json;

/// A row's state: joined, asked, or asked and refused.
pub const MEMBER: &str = "member";
pub const INVITED: &str = "invited";
pub const DECLINED: &str = "declined";

/// What a row may do. The owner everything; an admin invites, renames and removes members and invitees; a member
/// leaves.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Owner,
    Admin,
    Member,
}

impl Role {
    pub fn parse(role: &str) -> Option<Role> {
        match role {
            "owner" => Some(Role::Owner),
            "admin" => Some(Role::Admin),
            "member" => Some(Role::Member),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Role::Owner => "owner",
            Role::Admin => "admin",
            Role::Member => "member",
        }
    }

    /// Whether the role invites, renames and removes: the owner's and an admin's.
    pub(super) fn manages(self) -> bool {
        matches!(self, Role::Owner | Role::Admin)
    }
}

/// Why an organization was not written.
#[derive(Debug, PartialEq, Eq)]
pub enum OrgWrite {
    /// No organization by that id that the caller has joined. One answer for "none" and "not yours", so a stranger
    /// learns nothing by asking.
    NoSuchOrg,
    /// The caller has joined, and this is the owner's or an admin's to do.
    AdminOnly,
    /// The caller is an admin or a member, and this is the owner's to do.
    OwnerOnly,
    /// The account owns as many organizations as it may.
    TooManyOrgs,
    /// No account has the handle.
    NoSuchHandle,
    /// Nobody by that handle is in the organization, joined or invited.
    NotInOrg,
    /// They have already joined.
    AlreadyMember,
    /// They declined within the day.
    Declined,
    /// They have as many invitations waiting as an account may.
    InviteeFull,
    /// The organization has as many people, joined and invited, as it may.
    Full,
    /// An admin may not remove an admin.
    RemoveAdmin,
    /// Nobody removes the owner, and the owner's role changes only by a hand-over.
    HandOver,
    /// A hand-over to someone who has not joined.
    NotJoined,
    /// Answering an invitation the account does not have.
    NotInvited,
    /// No invite link by that code or id that can still be used: it expired, was used up, or was turned off.
    NoSuchLink,
    /// The organization has as many invite links working as it may.
    TooManyLinks,
    /// Something below the rules failed.
    Failed,
}

/// A query that failed is the write failing, as it is for `WriteError`.
impl From<rusqlite::Error> for OrgWrite {
    fn from(_: rusqlite::Error) -> Self {
        OrgWrite::Failed
    }
}

/// An organization as the list answers it: the caller's own row in it, and how many have joined.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrgRow {
    pub id: String,
    pub name: String,
    pub hue: Option<String>,
    pub role: Role,
    pub state: String,
    pub members: i64,
    pub invited_by: Option<String>,
    pub created_at: i64,
}

/// Someone in an organization, joined or invited.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Member {
    pub handle: String,
    pub role: Role,
    pub state: String,
    pub since: i64,
    pub invited_by: Option<String>,
}

/// An organization as a member reads it: the caller's row and everyone in it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Org {
    pub id: String,
    pub name: String,
    pub hue: Option<String>,
    pub role: Role,
    pub state: String,
    pub invited_by: Option<String>,
    pub created_at: i64,
    pub members: Vec<Member>,
}

/// The limits an invitation is checked against, the route's numbers passed in (src/orgs.rs keeps them).
pub struct InviteCaps {
    /// Rows per organization, joined and invited together.
    pub rows_per_org: i64,
    /// Invitations one account may have waiting, across every organization.
    pub pending_per_invitee: i64,
    /// How long after declining the same organization may not ask again, in seconds.
    pub decline_cooldown: i64,
}

/// A row in an organization, inside a transaction: who, and what they may do.
pub(super) struct Seat {
    pub(super) account: i64,
    pub(super) handle: String,
    pub(super) role: Role,
    pub(super) state: String,
    pub(super) invited_by: Option<i64>,
}

const ROW_SELECT: &str = "SELECT o.id, o.name, o.hue, m.role, m.state, o.created_at, \
    (SELECT COUNT(*) FROM org_members x WHERE x.org_id = o.id AND x.state = 'member'), \
    (SELECT handle FROM accounts WHERE id = m.invited_by) \
    FROM org_members m JOIN orgs o ON o.id = m.org_id";

const SEAT_SELECT: &str = "SELECT m.account_id, a.handle, m.role, m.state, m.invited_by \
    FROM org_members m JOIN accounts a ON a.id = m.account_id WHERE m.org_id = ?1";

fn role_at(r: &Row<'_>, index: usize) -> rusqlite::Result<Role> {
    // A role the database holds is one this file wrote; anything else reads as the least it could be.
    Ok(Role::parse(&r.get::<_, String>(index)?).unwrap_or(Role::Member))
}

impl Store {
    fn org_row(r: &Row<'_>) -> rusqlite::Result<OrgRow> {
        Ok(OrgRow { id: r.get(0)?, name: r.get(1)?, hue: r.get(2)?, role: role_at(r, 3)?, state: r.get(4)?, created_at: r.get(5)?, members: r.get(6)?, invited_by: r.get(7)? })
    }

    fn seat_row(r: &Row<'_>) -> rusqlite::Result<Seat> {
        Ok(Seat { account: r.get(0)?, handle: r.get(1)?, role: role_at(r, 2)?, state: r.get(3)?, invited_by: r.get(4)? })
    }

    fn member_row(r: &Row<'_>) -> rusqlite::Result<Member> {
        Ok(Member { handle: r.get(0)?, role: role_at(r, 1)?, state: r.get(2)?, since: r.get(3)?, invited_by: r.get(4)? })
    }

    // --- reads ------------------------------------------------------------------

    /// The organizations an account has joined or is invited to, oldest first (by the second, then by making).
    pub fn orgs_of(&self, account: i64) -> Vec<OrgRow> {
        self.all(
            &format!("{ROW_SELECT} WHERE m.account_id = ?1 AND m.state IN ('member', 'invited') ORDER BY o.created_at, o.rowid"),
            params![account],
            Self::org_row,
        )
    }

    /// An organization with its people, for an account that has joined it; nothing for an invitee or a stranger.
    pub fn org_of(&self, account: i64, org: &str) -> Option<Org> {
        Self::org_in(&self.lock(), account, org).ok().flatten()
    }

    pub(super) fn org_in(conn: &Connection, account: i64, org: &str) -> rusqlite::Result<Option<Org>> {
        let row = conn
            .query_row(&format!("{ROW_SELECT} WHERE m.org_id = ?1 AND m.account_id = ?2 AND m.state = 'member'"), params![org, account], Self::org_row)
            .optional()?;
        let Some(row) = row else { return Ok(None) };
        let mut stmt = conn.prepare(
            "SELECT a.handle, m.role, m.state, m.since, (SELECT handle FROM accounts WHERE id = m.invited_by) \
             FROM org_members m JOIN accounts a ON a.id = m.account_id \
             WHERE m.org_id = ?1 AND m.state IN ('member', 'invited') ORDER BY m.state = 'invited', m.since, m.rowid",
        )?;
        let members = stmt.query_map(params![org], Self::member_row)?.filter_map(Result::ok).collect();
        Ok(Some(Org { id: row.id, name: row.name, hue: row.hue, role: row.role, state: row.state, invited_by: row.invited_by, created_at: row.created_at, members }))
    }

    pub(super) fn seat_of(conn: &Connection, org: &str, account: i64) -> rusqlite::Result<Option<Seat>> {
        conn.query_row(&format!("{SEAT_SELECT} AND m.account_id = ?2"), params![org, account], Self::seat_row).optional()
    }

    /// The row by handle, matched without case as handles are, among those joined or invited.
    fn seat_by_handle(conn: &Connection, org: &str, handle: &str) -> rusqlite::Result<Option<Seat>> {
        conn.query_row(&format!("{SEAT_SELECT} AND a.handle = ?2 AND m.state IN ('member', 'invited')"), params![org, handle], Self::seat_row).optional()
    }

    /// The caller's row, for a write: they must have joined, or the organization is not theirs to know of.
    pub(super) fn acting(conn: &Connection, org: &str, account: i64) -> Result<Seat, OrgWrite> {
        match Self::seat_of(conn, org, account)? {
            Some(seat) if seat.state == MEMBER => Ok(seat),
            _ => Err(OrgWrite::NoSuchOrg),
        }
    }

    pub(super) fn org_name(conn: &Connection, org: &str) -> rusqlite::Result<String> {
        conn.query_row("SELECT name FROM orgs WHERE id = ?1", params![org], |r| r.get(0))
    }

    fn owner_of(conn: &Connection, org: &str) -> rusqlite::Result<i64> {
        conn.query_row("SELECT owner_id FROM orgs WHERE id = ?1", params![org], |r| r.get(0))
    }

    /// Everyone who has joined, but `except`.
    pub(super) fn members_but(conn: &Connection, org: &str, except: &[i64]) -> rusqlite::Result<Vec<i64>> {
        let mut stmt = conn.prepare("SELECT account_id FROM org_members WHERE org_id = ?1 AND state = 'member'")?;
        let ids = stmt.query_map(params![org], |r| r.get::<_, i64>(0))?.filter_map(Result::ok).filter(|id| !except.contains(id)).collect();
        Ok(ids)
    }

    fn member_by_account(conn: &Connection, org: &str, account: i64) -> rusqlite::Result<Member> {
        conn.query_row(
            "SELECT a.handle, m.role, m.state, m.since, (SELECT handle FROM accounts WHERE id = m.invited_by) \
             FROM org_members m JOIN accounts a ON a.id = m.account_id WHERE m.org_id = ?1 AND m.account_id = ?2",
            params![org, account],
            Self::member_row,
        )
    }

    /// Who is told that an invitation was answered: the one who asked, if they are still in; else the owner.
    pub(super) fn asker_or_owner(conn: &Connection, org: &str, invited_by: Option<i64>) -> rusqlite::Result<i64> {
        if let Some(asker) = invited_by {
            if Self::seat_of(conn, org, asker)?.is_some_and(|s| s.state == MEMBER) {
                return Ok(asker);
            }
        }
        Self::owner_of(conn, org)
    }

    /// The same notice to each of `to`.
    pub(super) fn tell(tx: &Transaction<'_>, to: &[i64], notice: &Notice<'_>, now: i64) -> rusqlite::Result<()> {
        for account in to {
            Self::notify(tx, *account, notice, now)?;
        }
        Ok(())
    }

    // --- writes -----------------------------------------------------------------

    /// A new organization under `id`, its maker the owner; refused when they own `most_owned` already.
    pub fn create_org(&self, owner: i64, id: &str, name: &str, hue: Option<&str>, now: i64, most_owned: i64) -> Result<Org, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let owned: i64 = tx.query_row("SELECT COUNT(*) FROM orgs WHERE owner_id = ?1", params![owner], |r| r.get(0))?;
        if owned >= most_owned {
            return Err(OrgWrite::TooManyOrgs);
        }
        tx.execute("INSERT INTO orgs (id, name, hue, owner_id, created_at) VALUES (?1, ?2, ?3, ?4, ?5)", params![id, name, hue, owner, now])?;
        tx.execute(
            "INSERT INTO org_members (org_id, account_id, role, state, invited_by, since) VALUES (?1, ?2, 'owner', 'member', NULL, ?3)",
            params![id, owner, now],
        )?;
        let org = Self::org_in(&tx, owner, id)?.ok_or(OrgWrite::Failed)?;
        tx.commit()?;
        Ok(org)
    }

    /// A new name and/or hue, by the owner or an admin. `hue` is `None` to leave it, `Some(None)` to clear it. A new
    /// name is told to every other member; a hue is not news.
    pub fn update_org(&self, actor: i64, org: &str, name: Option<&str>, hue: Option<Option<&str>>, now: i64) -> Result<Org, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let seat = Self::acting(&tx, org, actor)?;
        if !seat.role.manages() {
            return Err(OrgWrite::AdminOnly);
        }
        if let Some(hue) = hue {
            tx.execute("UPDATE orgs SET hue = ?2 WHERE id = ?1", params![org, hue])?;
        }
        if let Some(name) = name {
            let was = Self::org_name(&tx, org)?;
            if name != was {
                tx.execute("UPDATE orgs SET name = ?2 WHERE id = ?1", params![org, name])?;
                for to in Self::members_but(&tx, org, &[actor])? {
                    Self::notify_renamed(&tx, to, org, actor, name, &was, now)?;
                }
            }
        }
        let after = Self::org_in(&tx, actor, org)?.ok_or(OrgWrite::Failed)?;
        tx.commit()?;
        Ok(after)
    }

    /// The organization gone, by its owner: every pending invitation to it settled, every other member told, and
    /// then the row, which takes its people with it.
    pub fn delete_org(&self, actor: i64, org: &str, now: i64) -> Result<(), OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let seat = Self::acting(&tx, org, actor)?;
        if seat.role != Role::Owner {
            return Err(OrgWrite::OwnerOnly);
        }
        let name = Self::org_name(&tx, org)?;
        Self::settle_invites(&tx, org, now)?;
        let others = Self::members_but(&tx, org, &[actor])?;
        Self::tell(&tx, &others, &Notice { kind: "org-deleted", from: Some(actor), org, body: json!({ "name": name }), state: None }, now)?;
        tx.execute("DELETE FROM orgs WHERE id = ?1", params![org])?;
        tx.commit()?;
        Ok(())
    }

    /// An invitation by handle, from the owner or an admin. Someone already asked is asked again - their `since`
    /// moves, nothing else - someone who declined is not asked again inside the cooldown, and the caps hold. The
    /// invitee is told; nobody else is, until they answer.
    pub fn invite(&self, actor: i64, org: &str, handle: &str, now: i64, caps: InviteCaps) -> Result<Member, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let seat = Self::acting(&tx, org, actor)?;
        if !seat.role.manages() {
            return Err(OrgWrite::AdminOnly);
        }
        let invitee = Self::account_in(&tx, handle)?.ok_or(OrgWrite::NoSuchHandle)?;
        let current = Self::seat_of(&tx, org, invitee)?;
        let declined_at: Option<i64> = match current.as_ref().map(|s| s.state.as_str()) {
            Some(MEMBER) => return Err(OrgWrite::AlreadyMember),
            Some(INVITED) => {
                tx.execute("UPDATE org_members SET since = ?3, invited_by = ?4 WHERE org_id = ?1 AND account_id = ?2", params![org, invitee, now, actor])?;
                let member = Self::member_by_account(&tx, org, invitee)?;
                tx.commit()?;
                return Ok(member);
            }
            Some(_) => Some(tx.query_row("SELECT since FROM org_members WHERE org_id = ?1 AND account_id = ?2", params![org, invitee], |r| r.get(0))?),
            None => None,
        };
        if declined_at.is_some_and(|at| at + caps.decline_cooldown > now) {
            return Err(OrgWrite::Declined);
        }
        let pending: i64 = tx.query_row("SELECT COUNT(*) FROM org_members WHERE account_id = ?1 AND state = 'invited'", params![invitee], |r| r.get(0))?;
        if pending >= caps.pending_per_invitee {
            return Err(OrgWrite::InviteeFull);
        }
        let rows: i64 = tx.query_row("SELECT COUNT(*) FROM org_members WHERE org_id = ?1 AND state IN ('member', 'invited')", params![org], |r| r.get(0))?;
        if rows >= caps.rows_per_org {
            return Err(OrgWrite::Full);
        }
        tx.execute(
            "INSERT INTO org_members (org_id, account_id, role, state, invited_by, since) VALUES (?1, ?2, 'member', 'invited', ?3, ?4) \
             ON CONFLICT(org_id, account_id) DO UPDATE SET role = 'member', state = 'invited', invited_by = excluded.invited_by, since = excluded.since",
            params![org, invitee, actor, now],
        )?;
        let name = Self::org_name(&tx, org)?;
        Self::notify_invited(&tx, invitee, org, actor, json!({ "name": name }), now)?;
        let member = Self::member_by_account(&tx, org, invitee)?;
        tx.commit()?;
        Ok(member)
    }

    /// Someone out, by handle: an invitee withdrawn, a member removed by the owner or an admin (an admin, not another
    /// admin), or the caller leaving. The owner goes nowhere except by handing over first.
    pub fn remove_member(&self, actor: i64, org: &str, handle: &str, now: i64) -> Result<(), OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let seat = Self::acting(&tx, org, actor)?;
        let target = Self::seat_by_handle(&tx, org, handle)?.ok_or(OrgWrite::NotInOrg)?;
        let name = Self::org_name(&tx, org)?;
        if target.account == actor {
            if seat.role == Role::Owner {
                return Err(OrgWrite::HandOver);
            }
            tx.execute("DELETE FROM org_members WHERE org_id = ?1 AND account_id = ?2", params![org, actor])?;
            let rest = Self::members_but(&tx, org, &[])?;
            let body = json!({ "name": name, "handle": seat.handle });
            Self::tell(&tx, &rest, &Notice { kind: "member-left", from: Some(actor), org, body, state: None }, now)?;
            tx.commit()?;
            return Ok(());
        }
        if !seat.role.manages() {
            return Err(OrgWrite::AdminOnly);
        }
        if target.role == Role::Owner {
            return Err(OrgWrite::HandOver);
        }
        if target.state == INVITED {
            tx.execute("DELETE FROM org_members WHERE org_id = ?1 AND account_id = ?2", params![org, target.account])?;
            Self::settle_invite(&tx, target.account, org, DECLINED, true, now)?;
            tx.commit()?;
            return Ok(());
        }
        if target.role == Role::Admin && seat.role != Role::Owner {
            return Err(OrgWrite::RemoveAdmin);
        }
        tx.execute("DELETE FROM org_members WHERE org_id = ?1 AND account_id = ?2", params![org, target.account])?;
        Self::notify(&tx, target.account, &Notice { kind: "member-removed", from: Some(actor), org, body: json!({ "name": name }), state: None }, now)?;
        let rest = Self::members_but(&tx, org, &[actor])?;
        let body = json!({ "name": name, "handle": target.handle });
        Self::tell(&tx, &rest, &Notice { kind: "member-removed", from: Some(actor), org, body, state: None }, now)?;
        tx.commit()?;
        Ok(())
    }

    /// A member's role, by the owner. `Role::Owner` is the hand-over: the target becomes the owner and the caller an
    /// admin, in this one transaction, so there is never no owner and never two. The person is told.
    pub fn set_role(&self, actor: i64, org: &str, handle: &str, role: Role, now: i64) -> Result<Member, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let seat = Self::acting(&tx, org, actor)?;
        if seat.role != Role::Owner {
            return Err(OrgWrite::OwnerOnly);
        }
        let target = Self::seat_by_handle(&tx, org, handle)?.ok_or(OrgWrite::NotInOrg)?;
        if target.account == actor {
            return Err(OrgWrite::HandOver);
        }
        if target.state != MEMBER {
            return Err(OrgWrite::NotJoined);
        }
        if target.role != role {
            tx.execute("UPDATE org_members SET role = ?3 WHERE org_id = ?1 AND account_id = ?2", params![org, target.account, role.as_str()])?;
            if role == Role::Owner {
                tx.execute("UPDATE org_members SET role = 'admin' WHERE org_id = ?1 AND account_id = ?2", params![org, actor])?;
                tx.execute("UPDATE orgs SET owner_id = ?2 WHERE id = ?1", params![org, target.account])?;
            }
            let name = Self::org_name(&tx, org)?;
            let body = json!({ "name": name, "role": role.as_str() });
            Self::notify(&tx, target.account, &Notice { kind: "role-changed", from: Some(actor), org, body, state: None }, now)?;
        }
        let member = Self::member_by_account(&tx, org, target.account)?;
        tx.commit()?;
        Ok(member)
    }

    /// The invited person's answer. Accepted, they are a member: the one who asked (or the owner, if the asker has
    /// gone) is told, and every other member hears of the joining; the organization is answered as they now read it.
    /// Declined, the row stays as declined for the cooldown, the asker is told, and nothing is answered.
    pub fn answer_invite(&self, account: i64, org: &str, accept: bool, now: i64) -> Result<Option<Org>, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let seat = match Self::seat_of(&tx, org, account)? {
            Some(seat) if seat.state == INVITED => seat,
            _ => return Err(OrgWrite::NotInvited),
        };
        let name = Self::org_name(&tx, org)?;
        let asker = Self::asker_or_owner(&tx, org, seat.invited_by)?;
        let body = json!({ "name": name });
        if accept {
            tx.execute("UPDATE org_members SET state = 'member', role = 'member', since = ?3 WHERE org_id = ?1 AND account_id = ?2", params![org, account, now])?;
            Self::settle_invite(&tx, account, org, "accepted", false, now)?;
            Self::notify(&tx, asker, &Notice { kind: "invite-accepted", from: Some(account), org, body: body.clone(), state: None }, now)?;
            let others = Self::members_but(&tx, org, &[account, asker])?;
            Self::tell(&tx, &others, &Notice { kind: "member-joined", from: Some(account), org, body, state: None }, now)?;
            let joined = Self::org_in(&tx, account, org)?;
            tx.commit()?;
            Ok(joined)
        } else {
            tx.execute("UPDATE org_members SET state = 'declined', since = ?3 WHERE org_id = ?1 AND account_id = ?2", params![org, account, now])?;
            Self::settle_invite(&tx, account, org, DECLINED, false, now)?;
            Self::notify(&tx, asker, &Notice { kind: "invite-declined", from: Some(account), org, body, state: None }, now)?;
            tx.commit()?;
            Ok(None)
        }
    }

    // --- inside an account's deletion (store/accounts.rs) --------------------------

    /// Whether the account owns an organization anyone else is in, joined or invited: a deletion is refused over it.
    /// Someone who declined is not in it.
    pub(super) fn owns_org_with_others(conn: &Connection, account: i64) -> rusqlite::Result<bool> {
        conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM orgs o JOIN org_members m ON m.org_id = o.id \
             WHERE o.owner_id = ?1 AND m.account_id != ?1 AND m.state IN ('member', 'invited'))",
            params![account],
            |r| r.get(0),
        )
    }

    /// Every organization the account had joined told that they left, before its rows go with the account. Their
    /// handle rides in the body, since `from` is cleared once the account is gone. An account already gone has
    /// nothing to leave.
    pub(super) fn leave_every_org(tx: &Transaction<'_>, account: i64, now: i64) -> rusqlite::Result<()> {
        let handle: Option<String> = tx.query_row("SELECT handle FROM accounts WHERE id = ?1", params![account], |r| r.get(0)).optional()?;
        let Some(handle) = handle else {
            return Ok(());
        };
        let mut stmt = tx.prepare("SELECT org_id FROM org_members WHERE account_id = ?1 AND state = 'member' AND role != 'owner'")?;
        let joined: Vec<String> = stmt.query_map(params![account], |r| r.get(0))?.filter_map(Result::ok).collect();
        drop(stmt);
        for org in joined {
            let name = Self::org_name(tx, &org)?;
            let rest = Self::members_but(tx, &org, &[account])?;
            let body = json!({ "name": name, "handle": handle });
            Self::tell(tx, &rest, &Notice { kind: "member-left", from: Some(account), org: &org, body, state: None }, now)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    fn caps() -> InviteCaps {
        InviteCaps { rows_per_org: 50, pending_per_invitee: 20, decline_cooldown: 24 * 3600 }
    }

    /// The invariant, read straight from the table: one owner row, and it has joined.
    fn owners(s: &Store, org: &str) -> Vec<(i64, String)> {
        s.all("SELECT account_id, state FROM org_members WHERE org_id = ?1 AND role = 'owner'", params![org], |r| Ok((r.get(0)?, r.get(1)?)))
    }

    fn kinds(s: &Store, account: i64) -> Vec<(String, Option<String>)> {
        s.notifications_since(account, 0, 1000).unwrap().0.into_iter().map(|n| (n.kind, n.from)).collect()
    }

    #[test]
    fn an_organization_starts_with_its_owner_and_is_listed_for_members_and_invitees_only() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let org = s.create_org(a.id, "org-ghost", "Ghost", Some("moss"), 10, 20).unwrap();
        assert_eq!((org.role, org.state.as_str(), org.hue.as_deref(), org.members.len()), (Role::Owner, "member", Some("moss"), 1));
        assert_eq!(owners(&s, "org-ghost"), vec![(a.id, "member".to_string())]);
        s.invite(a.id, "org-ghost", "SAM", 11, caps()).unwrap();
        let theirs = s.orgs_of(sam.id);
        assert_eq!((theirs.len(), theirs[0].state.as_str(), theirs[0].members, theirs[0].invited_by.as_deref()), (1, "invited", 1, Some("matt")));
        assert_eq!(s.org_of(sam.id, "org-ghost"), None, "an invitee does not read the members");
        assert_eq!(s.update_org(sam.id, "org-ghost", Some("Mine"), None, 12), Err(OrgWrite::NoSuchOrg), "nor write");
        s.answer_invite(sam.id, "org-ghost", true, 13).unwrap();
        let read = s.org_of(sam.id, "org-ghost").unwrap();
        assert_eq!(read.members.iter().map(|m| (m.handle.as_str(), m.role, m.state.as_str())).collect::<Vec<_>>(), vec![("matt", Role::Owner, "member"), ("sam", Role::Member, "member")]);
        assert_eq!(read.members[1].invited_by.as_deref(), Some("matt"));
        assert_eq!(s.orgs_of(a.id)[0].members, 2);
        // The limit on what one account owns.
        s.create_org(a.id, "org-two", "Two", None, 14, 2).unwrap();
        assert_eq!(s.create_org(a.id, "org-three", "Three", None, 15, 2), Err(OrgWrite::TooManyOrgs));
    }

    #[test]
    fn the_owner_invariant_holds_through_every_path() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        let kim = s.create_account("kim", "", "", None, &[], 1).unwrap();
        s.create_org(a.id, "org", "Ghost", None, 10, 20).unwrap();
        for who in [sam.id, ali.id, kim.id] {
            s.invite(a.id, "org", &s.account_by_id(who).unwrap().handle, 11, caps()).unwrap();
        }
        s.answer_invite(sam.id, "org", true, 12).unwrap();
        s.answer_invite(ali.id, "org", true, 12).unwrap();
        s.set_role(a.id, "org", "sam", Role::Admin, 13).unwrap();
        // Nobody removes the owner; the owner cannot leave or step down.
        assert_eq!(s.remove_member(sam.id, "org", "matt", 14), Err(OrgWrite::HandOver));
        assert_eq!(s.remove_member(a.id, "org", "matt", 14), Err(OrgWrite::HandOver));
        assert_eq!(s.set_role(a.id, "org", "matt", Role::Member, 14), Err(OrgWrite::HandOver));
        // Only the owner changes roles; an admin may not remove an admin; a member removes nobody.
        assert_eq!(s.set_role(sam.id, "org", "ali", Role::Admin, 14), Err(OrgWrite::OwnerOnly));
        s.set_role(a.id, "org", "ali", Role::Admin, 15).unwrap();
        assert_eq!(s.remove_member(sam.id, "org", "ali", 16), Err(OrgWrite::RemoveAdmin));
        assert_eq!(s.remove_member(ali.id, "org", "sam", 16), Err(OrgWrite::RemoveAdmin));
        s.set_role(a.id, "org", "ali", Role::Member, 17).unwrap();
        assert_eq!(s.remove_member(ali.id, "org", "sam", 18), Err(OrgWrite::AdminOnly));
        assert_eq!(s.invite(ali.id, "org", "kim", 18, caps()), Err(OrgWrite::AdminOnly));
        // A hand-over goes only to someone who has joined, and makes the old owner an admin in the same breath.
        assert_eq!(s.set_role(a.id, "org", "kim", Role::Owner, 19), Err(OrgWrite::NotJoined));
        let handed = s.set_role(a.id, "org", "sam", Role::Owner, 20).unwrap();
        assert_eq!((handed.handle.as_str(), handed.role), ("sam", Role::Owner));
        assert_eq!(owners(&s, "org"), vec![(sam.id, "member".to_string())]);
        assert_eq!(s.org_of(a.id, "org").unwrap().role, Role::Admin);
        assert_eq!(s.delete_org(a.id, "org", 21), Err(OrgWrite::OwnerOnly));
        // Now the old owner may leave, and the new one is told.
        s.remove_member(a.id, "org", "matt", 22).unwrap();
        assert_eq!(s.org_of(a.id, "org"), None);
        assert!(kinds(&s, sam.id).contains(&("member-left".to_string(), Some("matt".to_string()))));
        assert_eq!(owners(&s, "org"), vec![(sam.id, "member".to_string())]);
        assert_eq!(s.remove_member(sam.id, "org", "nobody", 23), Err(OrgWrite::NotInOrg));
        assert_eq!(s.remove_member(sam.id, "org", "matt", 23), Err(OrgWrite::NotInOrg), "gone is the same as never there");
    }

    #[test]
    fn invitations_refresh_wait_out_a_decline_and_stop_at_the_caps() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        s.create_org(a.id, "org", "Ghost", None, 10, 20).unwrap();
        assert_eq!(s.invite(a.id, "org", "nobody", 11, caps()), Err(OrgWrite::NoSuchHandle));
        assert_eq!(s.invite(a.id, "org", "matt", 11, caps()), Err(OrgWrite::AlreadyMember));
        let first = s.invite(a.id, "org", "sam", 11, caps()).unwrap();
        assert_eq!((first.state.as_str(), first.since, first.invited_by.as_deref()), ("invited", 11, Some("matt")));
        let again = s.invite(a.id, "org", "sam", 12, caps()).unwrap();
        assert_eq!(again.since, 12, "asked again: the same row, moved on");
        assert_eq!(kinds(&s, sam.id).len(), 1, "and no second notification");
        // Declined: the organization waits a day before asking again.
        assert_eq!(s.answer_invite(sam.id, "org", false, 13).unwrap(), None);
        assert_eq!(s.answer_invite(sam.id, "org", false, 13), Err(OrgWrite::NotInvited), "answered already");
        assert!(s.orgs_of(sam.id).is_empty(), "declined is not listed");
        assert_eq!(s.invite(a.id, "org", "sam", 14, caps()), Err(OrgWrite::Declined));
        assert_eq!(s.invite(a.id, "org", "sam", 13 + 24 * 3600 - 1, caps()), Err(OrgWrite::Declined));
        let asked = s.invite(a.id, "org", "sam", 13 + 24 * 3600, caps()).unwrap();
        assert_eq!(asked.state, "invited");
        let rows = s.notifications_since(sam.id, 0, 100).unwrap().0;
        assert_eq!(rows.iter().filter(|n| n.kind == "invite").count(), 1, "one invite row per organization, pending again");
        assert_eq!(rows[0].state.as_deref(), Some("pending"));
        assert!(kinds(&s, a.id).contains(&("invite-declined".to_string(), Some("sam".to_string()))));
        // The caps: an invitee may have so many waiting, an organization so many rows.
        let tight = || InviteCaps { rows_per_org: 3, pending_per_invitee: 1, decline_cooldown: 0 };
        s.create_org(ali.id, "theirs", "Theirs", None, 20, 20).unwrap();
        assert_eq!(s.invite(ali.id, "theirs", "sam", 21, tight()), Err(OrgWrite::InviteeFull), "sam already has one waiting");
        s.invite(a.id, "org", "ali", 22, tight()).unwrap();
        let kim = s.create_account("kim", "", "", None, &[], 1).unwrap();
        assert_eq!(s.invite(a.id, "org", "kim", 23, tight()), Err(OrgWrite::Full), "matt, sam and ali are three rows");
        let _ = kim;
    }

    #[test]
    fn accepting_tells_the_asker_or_the_owner_and_the_rest_hear_of_the_joining() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        let kim = s.create_account("kim", "", "", None, &[], 1).unwrap();
        s.create_org(a.id, "org", "Ghost", None, 10, 20).unwrap();
        s.invite(a.id, "org", "sam", 11, caps()).unwrap();
        s.answer_invite(sam.id, "org", true, 12).unwrap();
        s.set_role(a.id, "org", "sam", Role::Admin, 13).unwrap();
        s.invite(sam.id, "org", "ali", 14, caps()).unwrap();
        s.invite(sam.id, "org", "kim", 14, caps()).unwrap();
        let joined = s.answer_invite(ali.id, "org", true, 15).unwrap().unwrap();
        assert_eq!((joined.role, joined.members.len()), (Role::Member, 4), "answered as they now read it: three joined, one invited");
        assert!(kinds(&s, sam.id).contains(&("invite-accepted".to_string(), Some("ali".to_string()))), "the asker is told");
        assert!(!kinds(&s, sam.id).contains(&("member-joined".to_string(), Some("ali".to_string()))), "and not twice");
        assert!(kinds(&s, a.id).contains(&("member-joined".to_string(), Some("ali".to_string()))), "the owner hears of the joining");
        // The asker has left: the owner is told instead.
        s.remove_member(sam.id, "org", "sam", 16).unwrap();
        s.answer_invite(kim.id, "org", true, 17).unwrap();
        assert!(kinds(&s, a.id).contains(&("invite-accepted".to_string(), Some("kim".to_string()))));
        assert!(!kinds(&s, sam.id).iter().any(|(k, f)| k == "invite-accepted" && f.as_deref() == Some("kim")));
    }

    #[test]
    fn an_asker_who_deletes_their_account_leaves_the_invitee_in_place_with_the_asker_blank() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        s.create_org(a.id, "org", "Ghost", None, 10, 20).unwrap();
        s.invite(a.id, "org", "sam", 11, caps()).unwrap();
        s.answer_invite(sam.id, "org", true, 12).unwrap();
        s.set_role(a.id, "org", "sam", Role::Admin, 13).unwrap();
        s.invite(sam.id, "org", "ali", 14, caps()).unwrap();
        assert_eq!(s.delete_account(sam.id, 15), Ok(true), "an admin, not an owner: free to go");
        let left = s.org_of(a.id, "org").unwrap();
        assert_eq!(left.members.iter().map(|m| (m.handle.as_str(), m.state.as_str(), m.invited_by.as_deref())).collect::<Vec<_>>(), vec![("matt", "member", None), ("ali", "invited", None)]);
        let theirs = s.notifications_since(ali.id, 0, 100).unwrap().0;
        assert_eq!((theirs.len(), theirs[0].kind.as_str(), theirs[0].from.as_deref(), theirs[0].state.as_deref()), (1, "invite", None, Some("pending")), "the row stays, its asker blank");
        assert_eq!(theirs[0].org, Some(("org".to_string(), "Ghost".to_string())));
        assert!(s.answer_invite(ali.id, "org", true, 16).unwrap().is_some(), "and can still be answered: the owner is told");
        assert!(kinds(&s, a.id).contains(&("invite-accepted".to_string(), Some("ali".to_string()))));
        assert!(kinds(&s, a.id).contains(&("member-left".to_string(), None)), "the deleted account's leaving reads with nobody behind it");
    }

    #[test]
    fn deleting_an_organization_settles_its_invitations_and_tells_its_members() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        s.create_org(a.id, "org", "Ghost", None, 10, 20).unwrap();
        s.invite(a.id, "org", "sam", 11, caps()).unwrap();
        s.invite(a.id, "org", "ali", 11, caps()).unwrap();
        s.answer_invite(sam.id, "org", true, 12).unwrap();
        let before = s.notifications_since(ali.id, 0, 100).unwrap().2;
        s.delete_org(a.id, "org", 13).unwrap();
        assert!(s.orgs_of(a.id).is_empty() && s.orgs_of(sam.id).is_empty() && s.orgs_of(ali.id).is_empty());
        let (settled, _, _) = s.notifications_since(ali.id, before, 100).unwrap();
        assert_eq!((settled.len(), settled[0].kind.as_str(), settled[0].state.as_deref(), settled[0].hidden), (1, "invite", Some("declined"), true), "fed again, settled");
        assert_eq!(settled[0].org, Some(("org".to_string(), "Ghost".to_string())), "the name the body kept, the organization being gone");
        let told = s.notifications_since(sam.id, 0, 100).unwrap().0;
        let gone = told.iter().find(|n| n.kind == "org-deleted").unwrap();
        assert_eq!((gone.from.as_deref(), gone.org.as_ref().map(|o| o.1.as_str())), (Some("matt"), Some("Ghost")));
        assert_eq!(s.delete_org(a.id, "org", 14), Err(OrgWrite::NoSuchOrg));
    }

    #[test]
    fn an_account_owning_an_organization_anyone_else_is_in_is_not_deleted_and_one_alone_goes_with_it() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        s.create_org(a.id, "org", "Ghost", None, 10, 20).unwrap();
        s.invite(a.id, "org", "sam", 11, caps()).unwrap();
        assert_eq!(s.delete_account(a.id, 12), Err(super::super::DeleteAccount::OwnsOrganizations), "an invitee is someone else in it");
        assert!(s.account_by_id(a.id).is_some(), "nothing went");
        s.answer_invite(sam.id, "org", false, 13).unwrap();
        assert_eq!(s.delete_account(a.id, 14), Ok(true), "declined, they are not in it: the organization goes with the account");
        assert!(s.orgs_of(sam.id).is_empty());
        assert_eq!(s.all("SELECT id FROM orgs", [], |r| r.get::<_, String>(0)), Vec::<String>::new());
        // A member of someone else's organization: free to go, and the rest are told.
        let b = s.create_account("matt", "", "", None, &[], 15).unwrap();
        s.create_org(sam.id, "theirs", "Theirs", None, 16, 20).unwrap();
        s.invite(sam.id, "theirs", "matt", 17, caps()).unwrap();
        s.answer_invite(b.id, "theirs", true, 18).unwrap();
        assert_eq!(s.delete_account(b.id, 19), Ok(true));
        let told = s.notifications_since(sam.id, 0, 100).unwrap().0;
        let left = told.iter().find(|n| n.kind == "member-left").unwrap();
        assert_eq!((left.from.as_deref(), left.body.as_ref().and_then(|b| b["handle"].as_str())), (None, Some("matt")));
        assert_eq!(s.org_of(sam.id, "theirs").unwrap().members.len(), 1);
    }
}
