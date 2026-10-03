//! Invite links: a code anyone holding it may join an organization with (src/orgs.rs, docs/TEAMS.md). Matt: "add the
//! ability to invite people to a team by link".
//!
//! A link is made by the owner or an admin, lasts until it expires, is used up or is turned off, and is listed only to
//! the people who may manage it. Joining by one is the invitation and the answer in one: whoever holds a working code
//! joins as a member, told to every member as a joining is, with the link's maker as the one who asked. A person
//! already in is answered the organization and counts no use; one with an invitation waiting has it accepted; one who
//! declined within the day joins anyway, since following a link is asking to. The organization's cap on people holds.

use super::notifications::Notice;
use super::orgs::{INVITED, MEMBER};
use super::{Org, OrgWrite, Store};
use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::json;

/// An invite link, as the people who manage the organization see it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrgLink {
    pub id: String,
    pub code: String,
    pub created_at: i64,
    pub expires_at: Option<i64>,
    pub max_uses: Option<i64>,
    pub uses: i64,
    /// The handle of who made it, while their account is there.
    pub by: Option<String>,
}

/// What a working code says before it is followed: the organization's name, hue and how many have joined, and who
/// made the link. Enough to ask "Join it?", and nothing about who is in it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkPreview {
    pub org: String,
    pub name: String,
    pub hue: Option<String>,
    pub members: i64,
    pub by: Option<String>,
}

const LINK_SELECT: &str = "SELECT l.id, l.code, l.created_at, l.expires_at, l.max_uses, l.uses, \
    (SELECT handle FROM accounts WHERE id = l.made_by) FROM org_links l";

/// The rows still working at `now`: not expired, not used up.
const WORKING: &str = "(l.expires_at IS NULL OR l.expires_at > ?2) AND (l.max_uses IS NULL OR l.uses < l.max_uses)";

impl Store {
    fn link_row(r: &Row<'_>) -> rusqlite::Result<OrgLink> {
        Ok(OrgLink { id: r.get(0)?, code: r.get(1)?, created_at: r.get(2)?, expires_at: r.get(3)?, max_uses: r.get(4)?, uses: r.get(5)?, by: r.get(6)? })
    }

    /// The organization's working links, newest first.
    fn links_in(conn: &Connection, org: &str, now: i64) -> rusqlite::Result<Vec<OrgLink>> {
        let mut stmt = conn.prepare(&format!("{LINK_SELECT} WHERE l.org_id = ?1 AND {WORKING} ORDER BY l.created_at DESC, l.rowid DESC"))?;
        let links = stmt.query_map(params![org, now], Self::link_row)?.filter_map(Result::ok).collect();
        Ok(links)
    }

    /// A new link, by the owner or an admin: `expires_at` and `max_uses` are none for never and no limit. Refused when
    /// the organization has `most` working already.
    #[allow(clippy::too_many_arguments)]
    pub fn make_link(&self, actor: i64, org: &str, id: &str, code: &str, expires_at: Option<i64>, max_uses: Option<i64>, now: i64, most: usize) -> Result<OrgLink, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let seat = Self::acting(&tx, org, actor)?;
        if !seat.role.manages() {
            return Err(OrgWrite::AdminOnly);
        }
        if Self::links_in(&tx, org, now)?.len() >= most {
            return Err(OrgWrite::TooManyLinks);
        }
        // The ones that stopped working are cleared as a new one is made, so the table holds what is live.
        tx.execute(
            "DELETE FROM org_links WHERE org_id = ?1 AND NOT ((expires_at IS NULL OR expires_at > ?2) AND (max_uses IS NULL OR uses < max_uses))",
            params![org, now],
        )?;
        tx.execute(
            "INSERT INTO org_links (id, code, org_id, made_by, created_at, expires_at, max_uses, uses) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0)",
            params![id, code, org, actor, now, expires_at, max_uses],
        )?;
        let link = tx.query_row(&format!("{LINK_SELECT} WHERE l.id = ?1"), params![id], Self::link_row)?;
        tx.commit()?;
        Ok(link)
    }

    /// The organization's working links, for the owner or an admin.
    pub fn links_of(&self, actor: i64, org: &str, now: i64) -> Result<Vec<OrgLink>, OrgWrite> {
        let conn = self.lock();
        let seat = Self::acting(&conn, org, actor)?;
        if !seat.role.manages() {
            return Err(OrgWrite::AdminOnly);
        }
        Ok(Self::links_in(&conn, org, now)?)
    }

    /// A link turned off, by the owner or an admin: its row gone, so its code joins nobody from now on.
    pub fn drop_link(&self, actor: i64, org: &str, link: &str) -> Result<(), OrgWrite> {
        let conn = self.lock();
        let seat = Self::acting(&conn, org, actor)?;
        if !seat.role.manages() {
            return Err(OrgWrite::AdminOnly);
        }
        let gone = conn.execute("DELETE FROM org_links WHERE id = ?1 AND org_id = ?2", params![link, org])?;
        if gone == 0 {
            return Err(OrgWrite::NoSuchLink);
        }
        Ok(())
    }

    /// The organization a working code joins, and who made it: `(org, made_by)`.
    fn link_target(conn: &Connection, code: &str, now: i64) -> rusqlite::Result<Option<(String, Option<i64>)>> {
        conn.query_row(&format!("SELECT l.org_id, l.made_by FROM org_links l WHERE l.code = ?1 AND {WORKING}"), params![code, now], |r| Ok((r.get(0)?, r.get(1)?)))
            .optional()
    }

    /// What a working code says before it is followed; none for a code that is not one, or no longer works.
    pub fn link_preview(&self, code: &str, now: i64) -> Option<LinkPreview> {
        let conn = self.lock();
        conn.query_row(
            &format!(
                "SELECT o.id, o.name, o.hue, (SELECT COUNT(*) FROM org_members x WHERE x.org_id = o.id AND x.state = 'member'), \
                 (SELECT handle FROM accounts WHERE id = l.made_by) \
                 FROM org_links l JOIN orgs o ON o.id = l.org_id WHERE l.code = ?1 AND {WORKING}"
            ),
            params![code, now],
            |r| Ok(LinkPreview { org: r.get(0)?, name: r.get(1)?, hue: r.get(2)?, members: r.get(3)?, by: r.get(4)? }),
        )
        .optional()
        .ok()
        .flatten()
    }

    /// The account in by a working code, answered the organization as it now reads it. Someone already in counts no
    /// use; an invitation waiting is accepted; otherwise a member's row is made, inside `rows_per_org`, with the
    /// link's maker as the one who asked. Every other member hears of the joining, and the maker is told as the asker
    /// of an accepted invitation is.
    pub fn join_by_link(&self, account: i64, code: &str, now: i64, rows_per_org: i64) -> Result<Org, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let Some((org, made_by)) = Self::link_target(&tx, code, now)? else {
            return Err(OrgWrite::NoSuchLink);
        };
        let current = Self::seat_of(&tx, &org, account)?;
        if current.as_ref().is_some_and(|seat| seat.state == MEMBER) {
            let joined = Self::org_in(&tx, account, &org)?.ok_or(OrgWrite::Failed)?;
            tx.commit()?;
            return Ok(joined);
        }
        let invited = current.as_ref().is_some_and(|seat| seat.state == INVITED);
        if !invited {
            let rows: i64 = tx.query_row("SELECT COUNT(*) FROM org_members WHERE org_id = ?1 AND state IN ('member', 'invited')", params![org], |r| r.get(0))?;
            if rows >= rows_per_org {
                return Err(OrgWrite::Full);
            }
        }
        // The one who asked: the link's maker while they are still in, else (as for an invitation) the owner.
        let asker = Self::asker_or_owner(&tx, &org, made_by)?;
        tx.execute(
            "INSERT INTO org_members (org_id, account_id, role, state, invited_by, since) VALUES (?1, ?2, 'member', 'member', ?3, ?4) \
             ON CONFLICT(org_id, account_id) DO UPDATE SET role = 'member', state = 'member', \
             invited_by = COALESCE(org_members.invited_by, excluded.invited_by), since = excluded.since",
            params![org, account, asker, now],
        )?;
        tx.execute("UPDATE org_links SET uses = uses + 1 WHERE code = ?1", params![code])?;
        // An invitation that was waiting is answered by the joining, as accepting it would have answered it.
        Self::settle_invite(&tx, account, &org, "accepted", false, now)?;
        let name = Self::org_name(&tx, &org)?;
        let body = json!({ "name": name });
        if asker != account {
            Self::notify(&tx, asker, &Notice { kind: "invite-accepted", from: Some(account), org: &org, body: body.clone(), state: None }, now)?;
        }
        let others = Self::members_but(&tx, &org, &[account, asker])?;
        Self::tell(&tx, &others, &Notice { kind: "member-joined", from: Some(account), org: &org, body, state: None }, now)?;
        let joined = Self::org_in(&tx, account, &org)?.ok_or(OrgWrite::Failed)?;
        tx.commit()?;
        Ok(joined)
    }
}

#[cfg(test)]
mod tests {
    use super::super::orgs::InviteCaps;
    use super::super::{fixture, Role};
    use super::*;

    fn caps() -> InviteCaps {
        InviteCaps { rows_per_org: 50, pending_per_invitee: 20, decline_cooldown: 24 * 3600 }
    }

    fn kinds(s: &Store, account: i64) -> Vec<String> {
        s.notifications_since(account, 0, 1000).unwrap().0.into_iter().map(|n| n.kind).collect()
    }

    fn uses(s: &Store, code: &str) -> i64 {
        s.all("SELECT uses FROM org_links WHERE code = ?1", params![code], |r| r.get(0))[0]
    }

    #[test]
    fn a_link_joins_whoever_holds_it_as_a_member_and_tells_everyone() {
        let (s, matt, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        s.create_org(matt.id, "org", "Ghost", Some("moss"), 10, 20).unwrap();
        s.invite(matt.id, "org", "sam", 11, caps()).unwrap();
        s.answer_invite(sam.id, "org", true, 12).unwrap();
        let link = s.make_link(matt.id, "org", "l1", "code-one", None, None, 13, 10).unwrap();
        assert_eq!((link.uses, link.by.as_deref(), link.expires_at, link.max_uses), (0, Some("matt"), None, None));

        let preview = s.link_preview("code-one", 14).unwrap();
        assert_eq!(preview, LinkPreview { org: "org".into(), name: "Ghost".into(), hue: Some("moss".into()), members: 2, by: Some("matt".into()) });
        assert_eq!(s.link_preview("not-a-code", 14), None);

        let joined = s.join_by_link(ali.id, "code-one", 15, 50).unwrap();
        assert_eq!((joined.role, joined.state.as_str(), joined.invited_by.as_deref(), joined.members.len()), (Role::Member, "member", Some("matt"), 3));
        assert_eq!(uses(&s, "code-one"), 1);
        assert!(kinds(&s, matt.id).contains(&"invite-accepted".to_string()), "the maker hears as an inviter does");
        assert_eq!(kinds(&s, sam.id).last().map(String::as_str), Some("member-joined"), "every other member hears of it");
        assert!(kinds(&s, ali.id).is_empty(), "the one joining is not told of their own joining");

        // Following it again is no second joining and no use.
        s.join_by_link(ali.id, "code-one", 16, 50).unwrap();
        assert_eq!(uses(&s, "code-one"), 1);
    }

    #[test]
    fn a_waiting_invitation_is_accepted_and_a_decline_is_no_bar() {
        let (s, matt, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        s.create_org(matt.id, "org", "Ghost", None, 10, 20).unwrap();
        s.invite(matt.id, "org", "sam", 11, caps()).unwrap();
        s.invite(matt.id, "org", "ali", 11, caps()).unwrap();
        s.answer_invite(ali.id, "org", false, 12).unwrap();
        s.make_link(matt.id, "org", "l1", "code", None, None, 13, 10).unwrap();
        s.join_by_link(sam.id, "code", 14, 50).unwrap();
        let invite = s.notifications_since(sam.id, 0, 100).unwrap().0.into_iter().find(|n| n.kind == "invite").unwrap();
        assert_eq!(invite.state.as_deref(), Some("accepted"), "the invitation in their feed is answered");
        assert_eq!(s.join_by_link(ali.id, "code", 15, 50).unwrap().state, "member", "declined an hour ago, and following a link is asking to");
    }

    #[test]
    fn only_the_owner_or_an_admin_makes_lists_or_turns_off_a_link() {
        let (s, matt, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        s.create_org(matt.id, "org", "Ghost", None, 10, 20).unwrap();
        s.invite(matt.id, "org", "sam", 11, caps()).unwrap();
        s.answer_invite(sam.id, "org", true, 12).unwrap();
        assert_eq!(s.make_link(sam.id, "org", "l1", "c1", None, None, 13, 10), Err(OrgWrite::AdminOnly));
        assert_eq!(s.links_of(sam.id, "org", 13), Err(OrgWrite::AdminOnly));
        assert_eq!(s.make_link(ali.id, "org", "l1", "c1", None, None, 13, 10), Err(OrgWrite::NoSuchOrg), "a stranger learns nothing");
        s.set_role(matt.id, "org", "sam", Role::Admin, 14).unwrap();
        let made = s.make_link(sam.id, "org", "l1", "c1", Some(1000), Some(5), 15, 10).unwrap();
        assert_eq!(s.links_of(matt.id, "org", 16).unwrap(), vec![made]);
        assert_eq!(s.drop_link(matt.id, "org", "nope"), Err(OrgWrite::NoSuchLink));
        s.drop_link(matt.id, "org", "l1").unwrap();
        assert_eq!(s.links_of(matt.id, "org", 17).unwrap(), vec![]);
        assert_eq!(s.join_by_link(ali.id, "c1", 18, 50).map(|o| o.id), Err(OrgWrite::NoSuchLink), "a link turned off joins nobody");
    }

    #[test]
    fn a_link_stops_at_its_hour_its_uses_and_the_organizations_size() {
        let (s, matt, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let ali = s.create_account("ali", "", "", None, &[], 1).unwrap();
        let kim = s.create_account("kim", "", "", None, &[], 1).unwrap();
        s.create_org(matt.id, "org", "Ghost", None, 10, 20).unwrap();
        s.make_link(matt.id, "org", "timed", "timed", Some(100), None, 10, 10).unwrap();
        s.make_link(matt.id, "org", "once", "once", None, Some(1), 10, 10).unwrap();
        s.make_link(matt.id, "org", "open", "open", None, None, 10, 10).unwrap();
        assert_eq!(s.join_by_link(sam.id, "timed", 100, 50).map(|o| o.id), Err(OrgWrite::NoSuchLink), "expired at its second");
        assert_eq!(s.link_preview("timed", 100), None);
        s.join_by_link(sam.id, "once", 20, 50).unwrap();
        assert_eq!(s.join_by_link(ali.id, "once", 21, 50).map(|o| o.id), Err(OrgWrite::NoSuchLink), "used up");
        assert_eq!(s.links_of(matt.id, "org", 100).unwrap().iter().map(|l| l.id.as_str()).collect::<Vec<_>>(), vec!["open"]);
        // matt and sam are two rows; a cap of two is full.
        assert_eq!(s.join_by_link(kim.id, "open", 22, 2).map(|o| o.id), Err(OrgWrite::Full));
        // At most this many working; a new one clears the ones that stopped.
        assert_eq!(s.make_link(matt.id, "org", "more", "more", None, None, 200, 1), Err(OrgWrite::TooManyLinks));
        s.make_link(matt.id, "org", "more", "more", None, None, 200, 2).unwrap();
        assert_eq!(s.all("SELECT id FROM org_links ORDER BY id", params![], |r| r.get::<_, String>(0)), vec!["more".to_string(), "open".to_string()]);
    }

    #[test]
    fn a_link_goes_with_its_organization() {
        let (s, matt, _dir) = fixture();
        s.create_org(matt.id, "org", "Ghost", None, 10, 20).unwrap();
        s.make_link(matt.id, "org", "l1", "c1", None, None, 11, 10).unwrap();
        s.delete_org(matt.id, "org", 12).unwrap();
        assert_eq!(s.all("SELECT COUNT(*) FROM org_links", params![], |r| r.get::<_, i64>(0)), vec![0]);
    }
}
