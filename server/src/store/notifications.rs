//! Notifications: what an account is told, kept as rows on its own write counter so a device reads them as it reads
//! notes - everything after a revision, paged - and a change to a row is fed again (src/notifications.rs,
//! docs/TEAMS.md).
//!
//! Two shapes in one table. A row the service writes - an invitation, someone joining or leaving, a rename - carries
//! its kind, who caused it, the organization and a small plaintext body, because the service is the one that knows.
//! A row a device writes about its own account - Claude edited a note, a summary was written, a conflict was kept -
//! carries a blob sealed under the account key, which the service cannot read; its `kind` column is for the pruning
//! and the limits here, and the device trusts the kind sealed inside over it.
//!
//! The service writes a row inside the transaction of the change it tells of (`notify`, called by store/orgs.rs and
//! store/accounts.rs), so there is no half-state: a member removed is a member told. Every write here prunes the
//! account's rows: at most `KEPT`, the read-or-hidden ones going first and never a pending invitation, so a flood of
//! self-made rows cannot push an unanswered invitation out.

use super::Store;
use rusqlite::{params, OptionalExtension, Row, Transaction};
use serde_json::Value;

/// How many rows an account keeps. The oldest past this go, by when they were made - never by revision, which a read
/// mark changes - the read-or-hidden ones first.
pub const KEPT: i64 = 300;
/// A read-or-hidden row older than this goes whatever the count: sixty days.
pub const KEPT_READ_FOR: i64 = 60 * 24 * 3600;

/// The kinds the service writes; a device may post any other (src/notifications.rs refuses these).
pub const SERVER_KINDS: &[&str] = &[
    "invite",
    "invite-accepted",
    "invite-declined",
    "member-joined",
    "member-left",
    "member-removed",
    "role-changed",
    "org-renamed",
    "org-deleted",
];

/// Why a notification was not written.
#[derive(Debug, PartialEq, Eq)]
pub enum NotificationWrite {
    /// No row by that id in this account.
    NotFound,
    /// Something below the rules failed.
    Failed,
}

/// A query that failed is the write failing, as it is for `WriteError`.
impl From<rusqlite::Error> for NotificationWrite {
    fn from(_: rusqlite::Error) -> Self {
        NotificationWrite::Failed
    }
}

/// A row as the feed answers it. `from` is the handle of who caused it, `None` when that account is gone or the row
/// is the device's own; `org` is the organization's id and its name - live while the reader is still a member, else
/// the name the body kept, so someone removed does not go on reading the organization's renames.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotificationRow {
    pub id: String,
    pub rev: i64,
    pub kind: String,
    pub at: i64,
    pub read_at: Option<i64>,
    pub hidden: bool,
    pub from: Option<String>,
    pub org: Option<(String, String)>,
    pub body: Option<Value>,
    pub blob: Option<String>,
    pub state: Option<String>,
}

/// What the service tells an account, written by `Store::notify` inside the transaction of the change.
pub(super) struct Notice<'a> {
    pub kind: &'a str,
    /// Who caused it: cleared by the database if their account goes.
    pub from: Option<i64>,
    pub org: &'a str,
    /// Small and plaintext; always carries the organization's `name` at the time, which the feed falls back to once
    /// the reader is no longer a member.
    pub body: Value,
    /// An invitation's `pending`; nothing for every other kind.
    pub state: Option<&'a str>,
}

const ROW_SELECT: &str = "SELECT n.id, n.rev, n.kind, n.created_at, n.read_at, n.hidden, f.handle, n.org_id, \
    CASE WHEN m.account_id IS NOT NULL THEN o.name ELSE NULL END, n.body, n.blob, n.state \
    FROM notifications n \
    LEFT JOIN accounts f ON f.id = n.from_id \
    LEFT JOIN orgs o ON o.id = n.org_id \
    LEFT JOIN org_members m ON m.org_id = n.org_id AND m.account_id = n.account_id AND m.state = 'member'";

impl Store {
    /// A row as `ROW_SELECT` reads it.
    fn notification_row(r: &Row<'_>) -> rusqlite::Result<NotificationRow> {
        let body: Option<Value> = r.get::<_, Option<String>>(9)?.and_then(|b| serde_json::from_str(&b).ok());
        let org_id: Option<String> = r.get(7)?;
        let live_name: Option<String> = r.get(8)?;
        let org = org_id.map(|id| {
            let kept = body.as_ref().and_then(|b| b["name"].as_str()).map(str::to_string);
            (id, live_name.or(kept).unwrap_or_default())
        });
        Ok(NotificationRow {
            id: r.get(0)?,
            rev: r.get(1)?,
            kind: r.get(2)?,
            at: r.get(3)?,
            read_at: r.get(4)?,
            hidden: r.get::<_, i64>(5)? != 0,
            from: r.get(6)?,
            org,
            body,
            blob: r.get(10)?,
            state: r.get(11)?,
        })
    }

    /// Everything written after `since`, oldest first, at most `limit`; whether there is more; and the account's head.
    /// Hidden rows ride too, as deletions ride the notes feed: a device that has the row learns it was hidden.
    pub fn notifications_since(&self, account: i64, since: i64, limit: i64) -> rusqlite::Result<(Vec<NotificationRow>, bool, i64)> {
        let conn = self.lock();
        let mut stmt = conn.prepare(&format!("{ROW_SELECT} WHERE n.account_id = ?1 AND n.rev > ?2 ORDER BY n.rev LIMIT ?3"))?;
        let mut rows: Vec<NotificationRow> = stmt.query_map(params![account, since, limit + 1], Self::notification_row)?.filter_map(Result::ok).collect();
        let more = rows.len() as i64 > limit;
        rows.truncate(limit as usize);
        let head: i64 = conn.query_row("SELECT rev FROM accounts WHERE id = ?1", params![account], |r| r.get(0))?;
        Ok((rows, more, head))
    }

    /// A device's own row: its sealed blob under the id the device chose. An id the account already has answers that
    /// row's revision and writes nothing, so a post whose answer was lost can be sent again and land once.
    pub fn post_notification(&self, account: i64, id: &str, kind: &str, blob: &str, now: i64) -> Result<i64, NotificationWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let existing: Option<i64> = tx.query_row("SELECT rev FROM notifications WHERE account_id = ?1 AND id = ?2", params![account, id], |r| r.get(0)).optional()?;
        if let Some(rev) = existing {
            return Ok(rev);
        }
        let rev = Self::next_rev(&tx, account)?;
        tx.execute(
            "INSERT INTO notifications (account_id, id, rev, kind, from_id, org_id, body, blob, state, created_at, read_at, hidden) \
             VALUES (?1, ?2, ?3, ?4, NULL, NULL, NULL, ?5, NULL, ?6, NULL, 0)",
            params![account, id, rev, kind, blob, now],
        )?;
        Self::prune_notifications(&tx, account, now)?;
        tx.commit()?;
        Ok(rev)
    }

    /// Read marks: the rows named, and with `all_before`, every unread row at or under that revision - what the
    /// device had seen when it asked, so a page that arrived later is not marked unseen. Each row marked takes a new
    /// revision; answers the account's head.
    pub fn mark_notifications_read(&self, account: i64, ids: &[String], all_before: Option<i64>, now: i64) -> rusqlite::Result<i64> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let mut unread: Vec<String> = Vec::new();
        if let Some(before) = all_before {
            let mut stmt = tx.prepare("SELECT id FROM notifications WHERE account_id = ?1 AND rev <= ?2 AND read_at IS NULL")?;
            unread.extend(stmt.query_map(params![account, before], |r| r.get::<_, String>(0))?.filter_map(Result::ok));
        }
        for id in ids {
            let is_unread: Option<i64> = tx
                .query_row("SELECT 1 FROM notifications WHERE account_id = ?1 AND id = ?2 AND read_at IS NULL", params![account, id], |r| r.get(0))
                .optional()?;
            if is_unread.is_some() && !unread.contains(id) {
                unread.push(id.clone());
            }
        }
        for id in &unread {
            let rev = Self::next_rev(&tx, account)?;
            tx.execute("UPDATE notifications SET read_at = ?3, rev = ?4 WHERE account_id = ?1 AND id = ?2", params![account, id, now, rev])?;
        }
        let head: i64 = tx.query_row("SELECT rev FROM accounts WHERE id = ?1", params![account], |r| r.get(0))?;
        tx.commit()?;
        Ok(head)
    }

    /// One row's read and hidden state, either or both; a field not given is left as it is. Takes a new revision
    /// whatever changed, so a repeat of a mark whose answer was lost still converges. Answers the row's revision.
    pub fn set_notification(&self, account: i64, id: &str, read: Option<bool>, hidden: Option<bool>, now: i64) -> Result<i64, NotificationWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let current: Option<(Option<i64>, i64)> = tx
            .query_row("SELECT read_at, hidden FROM notifications WHERE account_id = ?1 AND id = ?2", params![account, id], |r| Ok((r.get(0)?, r.get(1)?)))
            .optional()?;
        let Some((read_at, was_hidden)) = current else {
            return Err(NotificationWrite::NotFound);
        };
        let read_at = match read {
            Some(true) => Some(read_at.unwrap_or(now)),
            Some(false) => None,
            None => read_at,
        };
        let hidden = hidden.map_or(was_hidden, i64::from);
        let rev = Self::next_rev(&tx, account)?;
        tx.execute("UPDATE notifications SET read_at = ?3, hidden = ?4, rev = ?5 WHERE account_id = ?1 AND id = ?2", params![account, id, read_at, hidden, rev])?;
        tx.commit()?;
        Ok(rev)
    }

    // --- what the service writes, inside another write's transaction -------------

    /// A row for `to`, told by the service.
    pub(super) fn notify(tx: &Transaction<'_>, to: i64, notice: &Notice<'_>, now: i64) -> rusqlite::Result<()> {
        let rev = Self::next_rev(tx, to)?;
        tx.execute(
            "INSERT INTO notifications (account_id, id, rev, kind, from_id, org_id, body, blob, state, created_at, read_at, hidden) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL, ?8, ?9, NULL, 0)",
            params![to, crate::wire::fresh_id(), rev, notice.kind, notice.from, notice.org, notice.body.to_string(), notice.state, now],
        )?;
        Self::prune_notifications(tx, to, now)
    }

    /// An invitation, told: the one `invite` row an account has for an organization, made pending again if it is
    /// there (asked before, answered, and asked again), made if not. So an account's feed carries one invitation per
    /// organization, whatever its history.
    pub(super) fn notify_invited(tx: &Transaction<'_>, to: i64, org: &str, from: i64, body: Value, now: i64) -> rusqlite::Result<()> {
        let existing: Option<String> = tx
            .query_row("SELECT id FROM notifications WHERE account_id = ?1 AND org_id = ?2 AND kind = 'invite'", params![to, org], |r| r.get(0))
            .optional()?;
        match existing {
            Some(id) => {
                let rev = Self::next_rev(tx, to)?;
                tx.execute(
                    "UPDATE notifications SET rev = ?3, from_id = ?4, body = ?5, state = 'pending', created_at = ?6, read_at = NULL, hidden = 0 \
                     WHERE account_id = ?1 AND id = ?2",
                    params![to, id, rev, from, body.to_string(), now],
                )?;
                Ok(())
            }
            None => Self::notify(tx, to, &Notice { kind: "invite", from: Some(from), org, body, state: Some("pending") }, now),
        }
    }

    /// A rename, told: an unread rename of the same organization is brought up to date rather than joined by
    /// another, keeping the name it first said `was`, so three renames in a row read as one.
    pub(super) fn notify_renamed(tx: &Transaction<'_>, to: i64, org: &str, from: i64, name: &str, was: &str, now: i64) -> rusqlite::Result<()> {
        let unread: Option<(String, String)> = tx
            .query_row(
                "SELECT id, body FROM notifications WHERE account_id = ?1 AND org_id = ?2 AND kind = 'org-renamed' AND read_at IS NULL AND hidden = 0",
                params![to, org],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        match unread {
            Some((id, body)) => {
                let first = serde_json::from_str::<Value>(&body).ok().and_then(|b| b["was"].as_str().map(str::to_string)).unwrap_or_else(|| was.to_string());
                let rev = Self::next_rev(tx, to)?;
                let body = serde_json::json!({ "name": name, "was": first }).to_string();
                tx.execute(
                    "UPDATE notifications SET rev = ?3, from_id = ?4, body = ?5, created_at = ?6 WHERE account_id = ?1 AND id = ?2",
                    params![to, id, rev, from, body, now],
                )?;
                Ok(())
            }
            None => {
                let body = serde_json::json!({ "name": name, "was": was });
                Self::notify(tx, to, &Notice { kind: "org-renamed", from: Some(from), org, body, state: None }, now)
            }
        }
    }

    /// An account's pending invitation to `org`, answered or withdrawn: its state, hidden when it is nothing to look
    /// at any more (the organization gone, the invitation withdrawn), fed again under a new revision.
    /// An answered invitation is read as well as settled: the person tapped it, and a dot that stayed on the bell after
    /// Accept (seen on the first two-account run) said otherwise until the next feed page undid the device's own mark.
    pub(super) fn settle_invite(tx: &Transaction<'_>, account: i64, org: &str, state: &str, hidden: bool, now: i64) -> rusqlite::Result<()> {
        let pending: Option<String> = tx
            .query_row(
                "SELECT id FROM notifications WHERE account_id = ?1 AND org_id = ?2 AND kind = 'invite' AND state = 'pending'",
                params![account, org],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(id) = pending {
            let rev = Self::next_rev(tx, account)?;
            tx.execute(
                "UPDATE notifications SET state = ?3, hidden = ?4, rev = ?5, read_at = COALESCE(read_at, ?6) WHERE account_id = ?1 AND id = ?2",
                params![account, id, state, i64::from(hidden), rev, now],
            )?;
        }
        Ok(())
    }

    /// Every pending invitation to `org`, settled as declined and hidden: the organization is going.
    pub(super) fn settle_invites(tx: &Transaction<'_>, org: &str, now: i64) -> rusqlite::Result<()> {
        let mut stmt = tx.prepare("SELECT account_id FROM notifications WHERE org_id = ?1 AND kind = 'invite' AND state = 'pending'")?;
        let invited: Vec<i64> = stmt.query_map(params![org], |r| r.get(0))?.filter_map(Result::ok).collect();
        drop(stmt);
        for account in invited {
            Self::settle_invite(tx, account, org, "declined", true, now)?;
        }
        Ok(())
    }

    /// The account's rows kept to `KEPT`, inside the write that may have taken it past: read-or-hidden rows older
    /// than `KEPT_READ_FOR` go first whatever the count, then the oldest read-or-hidden, then the oldest of the rest -
    /// by when each was made, never by revision - and a pending invitation never goes.
    fn prune_notifications(tx: &Transaction<'_>, account: i64, now: i64) -> rusqlite::Result<()> {
        const NOT_PENDING: &str = "NOT (kind = 'invite' AND state = 'pending')";
        tx.execute(
            &format!("DELETE FROM notifications WHERE account_id = ?1 AND (read_at IS NOT NULL OR hidden = 1) AND created_at < ?2 AND {NOT_PENDING}"),
            params![account, now - KEPT_READ_FOR],
        )?;
        let count = |tx: &Transaction<'_>| tx.query_row("SELECT COUNT(*) FROM notifications WHERE account_id = ?1", params![account], |r| r.get::<_, i64>(0));
        let mut over = count(tx)? - KEPT;
        if over > 0 {
            tx.execute(
                &format!(
                    "DELETE FROM notifications WHERE rowid IN (SELECT rowid FROM notifications WHERE account_id = ?1 \
                     AND (read_at IS NOT NULL OR hidden = 1) AND {NOT_PENDING} ORDER BY created_at, rev LIMIT ?2)"
                ),
                params![account, over],
            )?;
            over = count(tx)? - KEPT;
        }
        if over > 0 {
            tx.execute(
                &format!("DELETE FROM notifications WHERE rowid IN (SELECT rowid FROM notifications WHERE account_id = ?1 AND {NOT_PENDING} ORDER BY created_at, rev LIMIT ?2)"),
                params![account, over],
            )?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::super::{fixture, InviteCaps};
    use super::*;
    use serde_json::json;

    /// The invitation caps, wide open: these tests are about the feed; the caps have tests of their own in
    /// store/orgs.rs.
    fn open_caps() -> InviteCaps {
        InviteCaps { rows_per_org: 1000, pending_per_invitee: 1000, decline_cooldown: 0 }
    }

    /// The ids of an account's feed from the start, in order.
    fn feed(s: &Store, account: i64) -> Vec<NotificationRow> {
        s.notifications_since(account, 0, 1000).unwrap().0
    }

    #[test]
    fn a_post_with_an_id_the_account_has_answers_its_revision_and_writes_nothing() {
        let (s, a, _dir) = fixture();
        let first = s.post_notification(a.id, "n-one", "note-edited", "c2VhbGVk", 10).unwrap();
        assert_eq!(s.post_notification(a.id, "n-one", "note-edited", "YW5vdGhlcg", 11), Ok(first), "the same id again is the same row");
        let rows = feed(&s, a.id);
        assert_eq!(rows.len(), 1);
        assert_eq!((rows[0].blob.as_deref(), rows[0].at, rows[0].kind.as_str()), (Some("c2VhbGVk"), 10, "note-edited"));
        assert!(rows[0].from.is_none() && rows[0].org.is_none() && rows[0].body.is_none() && rows[0].state.is_none());
        // The same id in another account is another row.
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        assert!(s.post_notification(b.id, "n-one", "note-edited", "dGhlaXJz", 12).unwrap() > 0);
        assert_eq!(feed(&s, b.id)[0].blob.as_deref(), Some("dGhlaXJz"));
        assert_eq!(feed(&s, a.id)[0].blob.as_deref(), Some("c2VhbGVk"));
    }

    #[test]
    fn read_and_hidden_changes_take_a_new_revision_and_ride_the_feed_again() {
        let (s, a, _dir) = fixture();
        let first = s.post_notification(a.id, "n-one", "summary-written", "YQ", 10).unwrap();
        s.post_notification(a.id, "n-two", "summary-written", "YQ", 11).unwrap();
        let read = s.set_notification(a.id, "n-one", Some(true), None, 20).unwrap();
        assert!(read > first);
        let (after, _, head) = s.notifications_since(a.id, first, 10).unwrap();
        assert_eq!(after.iter().map(|n| n.id.as_str()).collect::<Vec<_>>(), vec!["n-two", "n-one"], "the read row comes round again, after the one written since");
        assert_eq!((after[1].read_at, after[1].hidden, head), (Some(20), false, read));
        let hidden = s.set_notification(a.id, "n-one", None, Some(true), 21).unwrap();
        assert!(hidden > read);
        let (again, _, _) = s.notifications_since(a.id, read, 10).unwrap();
        assert_eq!((again.len(), again[0].read_at, again[0].hidden), (1, Some(20), true), "hidden rows are fed, as deletions are");
        let unread = s.set_notification(a.id, "n-one", Some(false), Some(false), 22).unwrap();
        assert!(unread > hidden);
        assert_eq!(feed(&s, a.id).iter().find(|n| n.id == "n-one").map(|n| (n.read_at, n.hidden)), Some((None, false)));
        assert_eq!(s.set_notification(a.id, "nope", Some(true), None, 23), Err(NotificationWrite::NotFound));
        // Marks by id and by "everything up to here": each row marked takes a revision, and the head is answered.
        let before = s.notifications_since(a.id, 0, 10).unwrap().2;
        s.post_notification(a.id, "n-three", "summary-written", "YQ", 30).unwrap();
        let head = s.mark_notifications_read(a.id, &[], Some(before), 31).unwrap();
        let rows = feed(&s, a.id);
        let read_at = |id: &str| rows.iter().find(|n| n.id == id).and_then(|n| n.read_at);
        assert_eq!((read_at("n-one"), read_at("n-two"), read_at("n-three")), (Some(31), Some(31), None), "the row that arrived after `before` is not marked");
        assert_eq!(head, rows.iter().map(|n| n.rev).max().unwrap());
        let again = s.mark_notifications_read(a.id, &["n-three".into(), "nope".into()], None, 32).unwrap();
        assert!(again > head);
        assert_eq!(feed(&s, a.id).iter().find(|n| n.id == "n-three").and_then(|n| n.read_at), Some(32));
        assert_eq!(s.mark_notifications_read(a.id, &["n-three".into()], None, 33).unwrap(), again, "a row already read is left alone");
    }

    #[test]
    fn the_feed_pages_by_revision_and_one_account_never_sees_another() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        for i in 0..3 {
            s.post_notification(a.id, &format!("n-{i}"), "note-edited", "YQ", 10 + i).unwrap();
        }
        s.post_notification(b.id, "theirs", "note-edited", "YQ", 20).unwrap();
        let (page, more, _) = s.notifications_since(a.id, 0, 2).unwrap();
        assert_eq!((page.len(), more), (2, true));
        let (rest, more, head) = s.notifications_since(a.id, page[1].rev, 2).unwrap();
        assert_eq!((rest.len(), more, rest[0].id.as_str()), (1, false, "n-2"));
        assert_eq!(head, rest[0].rev);
        assert!(feed(&s, a.id).iter().all(|n| n.id != "theirs"));
    }

    #[test]
    fn pruning_drops_read_or_hidden_rows_first_by_age_and_never_a_pending_invitation() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        // An invitation waits in the feed, older than everything that follows; it is one of the three hundred.
        let org = s.create_org(sam.id, "org-ghost", "Ghost", None, 5, 20).unwrap();
        s.invite(sam.id, &org.id, "matt", 6, open_caps()).unwrap();
        let newest = KEPT - 2;
        for i in 0..KEPT - 1 {
            s.post_notification(a.id, &format!("n-{i:04}"), "note-edited", "YQ", 100 + i).unwrap();
        }
        assert_eq!(feed(&s, a.id).len() as i64, KEPT, "the invitation and the rest");
        // One more: the oldest read row goes - the newest, read, not the oldest unread, whatever their revisions.
        s.set_notification(a.id, &format!("n-{newest:04}"), Some(true), None, 500).unwrap();
        s.post_notification(a.id, "n-more", "note-edited", "YQ", 501).unwrap();
        let rows = feed(&s, a.id);
        let ids: Vec<&str> = rows.iter().map(|n| n.id.as_str()).collect();
        assert_eq!(rows.len() as i64, KEPT);
        assert!(ids.contains(&"n-0000") && ids.contains(&"n-more"), "{ids:?}");
        assert!(!ids.contains(&format!("n-{newest:04}").as_str()), "the read row went first");
        assert!(rows.iter().any(|n| n.kind == "invite" && n.state.as_deref() == Some("pending")));
        // Nothing read or hidden left: now the oldest unread goes, and still not the invitation, which is older.
        s.post_notification(a.id, "n-more-2", "note-edited", "YQ", 502).unwrap();
        let rows = feed(&s, a.id);
        assert_eq!(rows.len() as i64, KEPT);
        assert!(rows.iter().all(|n| n.id != "n-0000") && rows.iter().any(|n| n.id == "n-more-2"));
        assert!(rows.iter().any(|n| n.kind == "invite"));
    }

    #[test]
    fn read_or_hidden_rows_older_than_sixty_days_go_with_the_next_write() {
        let (s, a, _dir) = fixture();
        s.post_notification(a.id, "old-read", "note-edited", "YQ", 1000).unwrap();
        s.post_notification(a.id, "old-unread", "note-edited", "YQ", 1001).unwrap();
        s.set_notification(a.id, "old-read", Some(true), None, 1002).unwrap();
        s.post_notification(a.id, "later", "note-edited", "YQ", 1002 + KEPT_READ_FOR).unwrap();
        let ids: Vec<String> = feed(&s, a.id).iter().map(|n| n.id.clone()).collect();
        assert_eq!(ids, vec!["old-unread".to_string(), "later".to_string()], "read and sixty days old goes; unread stays however old");
    }

    #[test]
    fn a_rename_brings_an_unread_one_up_to_date_rather_than_adding_another() {
        let (s, a, _dir) = fixture();
        let sam = s.create_account("sam", "", "", None, &[], 1).unwrap();
        let org = s.create_org(sam.id, "org-ghost", "Ghost", None, 5, 20).unwrap();
        s.invite(sam.id, &org.id, "matt", 6, open_caps()).unwrap();
        s.answer_invite(a.id, &org.id, true, 7).unwrap();
        s.update_org(sam.id, &org.id, Some("Ghost II"), None, 8).unwrap();
        s.update_org(sam.id, &org.id, Some("Ghost III"), None, 9).unwrap();
        let rows = feed(&s, a.id);
        let renames: Vec<&NotificationRow> = rows.iter().filter(|n| n.kind == "org-renamed").collect();
        assert_eq!(renames.len(), 1);
        assert_eq!(renames[0].body, Some(json!({ "name": "Ghost III", "was": "Ghost" })));
        assert_eq!(renames[0].org, Some((org.id.clone(), "Ghost III".to_string())));
        // Read, the next rename is news again.
        s.set_notification(a.id, &renames[0].id, Some(true), None, 10).unwrap();
        s.update_org(sam.id, &org.id, Some("Ghost IV"), None, 11).unwrap();
        let rows = feed(&s, a.id);
        assert_eq!(rows.iter().filter(|n| n.kind == "org-renamed").count(), 2);
    }
}
