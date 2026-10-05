//! Team notes (docs/SHARED.md, S4, S5; src/org_notes.rs): an organization's notes as ciphertext under its key, the
//! feed of them, each note's CRDT update log, and the organization's sealed files.
//!
//! The shapes are the account's (store/notes.rs, store/recordings.rs), scoped to an organization: a note is written
//! from the revision it was last seen at and refused with the stored one when that moved on; the organization has a
//! write counter of its own, so a member's cursor is per organization; a note's updates are a log numbered from 1,
//! appended by any member and cut back to a device's snapshot when it puts the row with `up_to`; a file is bytes
//! beside the database under `recordings/org-<org id>/`. Every call checks that the caller has joined.
use super::orgs::OrgWrite;
use super::Store;
use rusqlite::{params, Connection, OptionalExtension, Row};
use std::path::{Path, PathBuf};

/// A team note as the service holds it: where it is in the organization's history, its ciphertext, and who wrote it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrgNoteRow {
    pub id: String,
    pub rev: i64,
    pub deleted: bool,
    pub blob: Option<String>,
    /// The handle of who wrote it; None once their account is gone.
    pub by: Option<String>,
    pub updated_at: i64,
}

/// One update of a note's log.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateRow {
    pub seq: i64,
    pub blob: String,
    pub by: Option<String>,
    pub at: i64,
}

/// Why a team note was not written.
#[derive(Debug, PartialEq, Eq)]
pub enum OrgNoteWrite {
    /// No organization by that id that the caller has joined.
    NoSuchOrg,
    /// The stored row has moved on since `base`: here it is.
    Stale(OrgNoteRow),
    /// A file's stored revision has moved on since `base`.
    StaleFile(i64),
    /// No row for that note, so no log to append to.
    NoSuchNote,
    /// The organization holds as many notes as it may.
    Full,
    Failed,
}

impl From<rusqlite::Error> for OrgNoteWrite {
    fn from(_: rusqlite::Error) -> Self {
        OrgNoteWrite::Failed
    }
}

impl From<std::io::Error> for OrgNoteWrite {
    fn from(_: std::io::Error) -> Self {
        OrgNoteWrite::Failed
    }
}

impl From<OrgWrite> for OrgNoteWrite {
    fn from(_: OrgWrite) -> Self {
        OrgNoteWrite::NoSuchOrg
    }
}

const NOTE_SELECT: &str = "SELECT n.id, n.rev, n.deleted, n.blob, (SELECT handle FROM accounts WHERE id = n.by_id), n.updated_at FROM org_notes n";

impl Store {
    fn org_note_row(r: &Row<'_>) -> rusqlite::Result<OrgNoteRow> {
        Ok(OrgNoteRow { id: r.get(0)?, rev: r.get(1)?, deleted: r.get::<_, i64>(2)? != 0, blob: r.get(3)?, by: r.get(4)?, updated_at: r.get(5)? })
    }

    fn update_row(r: &Row<'_>) -> rusqlite::Result<UpdateRow> {
        Ok(UpdateRow { seq: r.get(0)?, blob: r.get(1)?, by: r.get(2)?, at: r.get(3)? })
    }

    /// The organization's next revision, taken inside a write's transaction: one counter for its notes and files.
    fn org_next_rev(tx: &Connection, org: &str) -> rusqlite::Result<i64> {
        tx.execute("INSERT INTO org_revs (org_id, rev) VALUES (?1, 1) ON CONFLICT(org_id) DO UPDATE SET rev = rev + 1", params![org])?;
        tx.query_row("SELECT rev FROM org_revs WHERE org_id = ?1", params![org], |r| r.get(0))
    }

    fn org_head(conn: &Connection, org: &str) -> rusqlite::Result<i64> {
        Ok(conn.query_row("SELECT rev FROM org_revs WHERE org_id = ?1", params![org], |r| r.get(0)).optional()?.unwrap_or(0))
    }

    fn org_note_in(conn: &Connection, org: &str, note: &str) -> rusqlite::Result<Option<OrgNoteRow>> {
        conn.query_row(&format!("{NOTE_SELECT} WHERE n.org_id = ?1 AND n.id = ?2"), params![org, note], Self::org_note_row).optional()
    }

    /// Everything written after `since`, oldest first, at most `limit`, whether there is more, and the organization's
    /// head: for a member.
    pub fn org_notes_since(&self, account: i64, org: &str, since: i64, limit: i64) -> Result<(Vec<OrgNoteRow>, bool, i64), OrgNoteWrite> {
        let conn = self.lock();
        Self::acting(&conn, org, account)?;
        let mut stmt = conn.prepare(&format!("{NOTE_SELECT} WHERE n.org_id = ?1 AND n.rev > ?2 ORDER BY n.rev LIMIT ?3"))?;
        let mut rows: Vec<OrgNoteRow> = stmt.query_map(params![org, since, limit + 1], Self::org_note_row)?.filter_map(Result::ok).collect();
        let more = rows.len() as i64 > limit;
        rows.truncate(limit as usize);
        let head = Self::org_head(&conn, org)?;
        Ok((rows, more, head))
    }

    /// Stores a team note written from `base`, or refuses it with the stored row when that has moved on; `None` for
    /// the blob is a deletion, which takes the note's log with it. A note the organization has never seen is taken
    /// whatever its base, up to `most` live notes. With `up_to`, the updates up to that seq are cut: the row holds a
    /// snapshot that covers them.
    pub fn put_org_note(&self, account: i64, org: &str, note: &str, base: i64, blob: Option<&str>, up_to: Option<i64>, most: i64, now: i64) -> Result<i64, OrgNoteWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        Self::acting(&tx, org, account)?;
        match Self::org_note_in(&tx, org, note)? {
            Some(current) if current.rev != base => return Err(OrgNoteWrite::Stale(current)),
            Some(_) => {}
            None if blob.is_some() => {
                let live: i64 = tx.query_row("SELECT COUNT(*) FROM org_notes WHERE org_id = ?1 AND deleted = 0", params![org], |r| r.get(0))?;
                if live >= most {
                    return Err(OrgNoteWrite::Full);
                }
            }
            None => {}
        }
        let rev = Self::org_next_rev(&tx, org)?;
        tx.execute(
            "INSERT INTO org_notes (org_id, id, rev, deleted, blob, by_id, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(org_id, id) DO UPDATE SET rev = excluded.rev, deleted = excluded.deleted, blob = excluded.blob, by_id = excluded.by_id, updated_at = excluded.updated_at",
            params![org, note, rev, i64::from(blob.is_none()), blob, account, now],
        )?;
        if blob.is_none() {
            tx.execute("DELETE FROM org_note_updates WHERE org_id = ?1 AND note_id = ?2", params![org, note])?;
        } else if let Some(up_to) = up_to {
            tx.execute("DELETE FROM org_note_updates WHERE org_id = ?1 AND note_id = ?2 AND seq <= ?3", params![org, note, up_to])?;
        }
        tx.commit()?;
        Ok(rev)
    }

    /// A note's updates after `since`, oldest first, at most `limit`, whether there is more, and the log's head: for
    /// a member, of a note the organization has.
    pub fn org_updates_since(&self, account: i64, org: &str, note: &str, since: i64, limit: i64) -> Result<(Vec<UpdateRow>, bool, i64), OrgNoteWrite> {
        let conn = self.lock();
        Self::acting(&conn, org, account)?;
        if Self::org_note_in(&conn, org, note)?.is_none_or(|row| row.deleted) {
            return Err(OrgNoteWrite::NoSuchNote);
        }
        let mut stmt = conn.prepare("SELECT u.seq, u.blob, (SELECT handle FROM accounts WHERE id = u.by_id), u.at FROM org_note_updates u WHERE u.org_id = ?1 AND u.note_id = ?2 AND u.seq > ?3 ORDER BY u.seq LIMIT ?4")?;
        let mut rows: Vec<UpdateRow> = stmt.query_map(params![org, note, since, limit + 1], Self::update_row)?.filter_map(Result::ok).collect();
        let more = rows.len() as i64 > limit;
        rows.truncate(limit as usize);
        let head: i64 = conn.query_row("SELECT COALESCE(MAX(seq), 0) FROM org_note_updates WHERE org_id = ?1 AND note_id = ?2", params![org, note], |r| r.get(0))?;
        Ok((rows, more, head))
    }

    /// `blobs` appended to a note's log in order, by a member; answers the seq of the last. A note that was cut back
    /// keeps counting from where it was, so a device's seq never goes backwards.
    pub fn post_org_updates(&self, account: i64, org: &str, note: &str, blobs: &[String], now: i64) -> Result<i64, OrgNoteWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        Self::acting(&tx, org, account)?;
        if Self::org_note_in(&tx, org, note)?.is_none_or(|row| row.deleted) {
            return Err(OrgNoteWrite::NoSuchNote);
        }
        // The log's next number: past everything ever appended, which `org_note_seqs` remembers across a cut.
        let mut seq: i64 = tx.query_row("SELECT COALESCE(MAX(seq), 0) FROM org_note_updates WHERE org_id = ?1 AND note_id = ?2", params![org, note], |r| r.get(0))?;
        let kept: i64 = tx.query_row("SELECT COALESCE((SELECT value FROM meta WHERE key = ?1), '0')", params![format!("org-seq:{org}:{note}")], |r| r.get::<_, String>(0))?.parse().unwrap_or(0);
        seq = seq.max(kept);
        for blob in blobs {
            seq += 1;
            tx.execute("INSERT INTO org_note_updates (org_id, note_id, seq, blob, by_id, at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)", params![org, note, seq, blob, account, now])?;
        }
        tx.execute("INSERT INTO meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value", params![format!("org-seq:{org}:{note}"), seq.to_string()])?;
        tx.commit()?;
        Ok(seq)
    }

    /// Each live note's log head - the seq of its last update, 0 for none - in one read, so a device fetches the logs
    /// that moved and not every note's every pass.
    pub fn org_note_heads(&self, account: i64, org: &str) -> Result<Vec<(String, i64)>, OrgNoteWrite> {
        let conn = self.lock();
        Self::acting(&conn, org, account)?;
        let mut stmt = conn.prepare(
            "SELECT n.id, COALESCE((SELECT value FROM meta WHERE key = 'org-seq:' || n.org_id || ':' || n.id), '0') \
             FROM org_notes n WHERE n.org_id = ?1 AND n.deleted = 0",
        )?;
        let heads = stmt.query_map(params![org], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?.parse().unwrap_or(0))))?.filter_map(Result::ok).collect();
        Ok(heads)
    }

    // --- files ----------------------------------------------------------------------

    fn org_file_path(&self, org: &str, id: &str) -> PathBuf {
        self.recordings.join(format!("org-{org}")).join(format!("{id}.bin"))
    }

    fn org_file_rev_in(conn: &Connection, org: &str, id: &str) -> rusqlite::Result<Option<i64>> {
        conn.query_row("SELECT rev FROM org_files WHERE org_id = ?1 AND id = ?2", params![org, id], |r| r.get(0)).optional()
    }

    /// An organization's file written from `base`, as an account's recording is (store/recordings.rs): the bytes in
    /// a side file first, renamed into place under the lock once the row is ready.
    pub fn put_org_file(&self, account: i64, org: &str, id: &str, base: i64, bytes: &[u8], now: i64) -> Result<i64, OrgNoteWrite> {
        let dir = self.recordings.join(format!("org-{org}"));
        std::fs::create_dir_all(&dir)?;
        let part = dir.join(format!("{id}.{:016x}.part", rand::random::<u64>()));
        std::fs::write(&part, bytes)?;
        let placed = self.place_org_file(account, org, id, base, bytes.len(), now, &part);
        if placed.is_err() {
            let _ = std::fs::remove_file(&part);
        }
        placed
    }

    fn place_org_file(&self, account: i64, org: &str, id: &str, base: i64, size: usize, now: i64, part: &Path) -> Result<i64, OrgNoteWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        Self::acting(&tx, org, account)?;
        if let Some(stored) = Self::org_file_rev_in(&tx, org, id)? {
            if stored != base {
                return Err(OrgNoteWrite::StaleFile(stored));
            }
        }
        let rev = Self::org_next_rev(&tx, org)?;
        tx.execute(
            "INSERT INTO org_files (org_id, id, rev, size, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(org_id, id) DO UPDATE SET rev = excluded.rev, size = excluded.size, updated_at = excluded.updated_at",
            params![org, id, rev, size as i64, now],
        )?;
        std::fs::rename(part, self.org_file_path(org, id))?;
        tx.commit()?;
        Ok(rev)
    }

    /// A file's revision and bytes, for a member; None where the organization has none by that id.
    pub fn org_file(&self, account: i64, org: &str, id: &str) -> Result<Option<(i64, Vec<u8>)>, OrgNoteWrite> {
        let conn = self.lock();
        Self::acting(&conn, org, account)?;
        let Some(rev) = Self::org_file_rev_in(&conn, org, id)? else { return Ok(None) };
        Ok(std::fs::read(self.org_file_path(org, id)).ok().map(|bytes| (rev, bytes)))
    }

    /// The organization's files folder, gone with it (store/orgs.rs `delete_org`). Best effort: the rows are gone already.
    pub(super) fn drop_org_files(&self, org: &str) {
        let _ = std::fs::remove_dir_all(self.recordings.join(format!("org-{org}")));
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    fn with_org(s: &Store, owner: i64) -> String {
        s.create_org(owner, "org-1", "Ghost", None, 1, 20).unwrap();
        "org-1".to_string()
    }

    #[test]
    fn team_notes_are_written_from_the_revision_seen_fed_in_order_and_gone_with_their_log() {
        let (s, a, _dir) = fixture();
        let org = with_org(&s, a.id);
        let r1 = s.put_org_note(a.id, &org, "n1", 0, Some("v1"), None, 2000, 1).unwrap();
        let r2 = s.put_org_note(a.id, &org, "n1", r1, Some("v2"), None, 2000, 2).unwrap();
        assert!(r2 > r1);
        match s.put_org_note(a.id, &org, "n1", r1, Some("elsewhere"), None, 2000, 3) {
            Err(OrgNoteWrite::Stale(winner)) => assert_eq!((winner.rev, winner.blob.as_deref(), winner.by.as_deref()), (r2, Some("v2"), Some("matt"))),
            other => panic!("expected a stale write, got {other:?}"),
        }
        s.put_org_note(a.id, &org, "n2", 0, Some("b1"), None, 2000, 4).unwrap();
        let (feed, more, head) = s.org_notes_since(a.id, &org, 0, 10).unwrap();
        assert_eq!(feed.iter().map(|n| n.id.as_str()).collect::<Vec<_>>(), vec!["n1", "n2"]);
        assert!(!more);
        assert_eq!(head, feed[1].rev);
        // The log, numbered from 1, cut back by a snapshot, and gone with the note.
        assert_eq!(s.org_note_heads(a.id, &org).unwrap(), vec![("n1".to_string(), 0), ("n2".to_string(), 0)], "no updates yet");
        assert_eq!(s.post_org_updates(a.id, &org, "n1", &["u1".into(), "u2".into(), "u3".into()], 5).unwrap(), 3);
        assert_eq!(s.org_note_heads(a.id, &org).unwrap(), vec![("n1".to_string(), 3), ("n2".to_string(), 0)]);
        let (updates, _, head) = s.org_updates_since(a.id, &org, "n1", 1, 10).unwrap();
        assert_eq!((updates.iter().map(|u| u.seq).collect::<Vec<_>>(), head), (vec![2, 3], 3));
        assert_eq!(updates[0].by.as_deref(), Some("matt"));
        s.put_org_note(a.id, &org, "n1", r2, Some("snapshot"), Some(2), 2000, 6).unwrap();
        let (updates, _, _) = s.org_updates_since(a.id, &org, "n1", 0, 10).unwrap();
        assert_eq!(updates.iter().map(|u| u.seq).collect::<Vec<_>>(), vec![3]);
        // Cut to nothing, the numbering still goes on from where it was.
        s.put_org_note(a.id, &org, "n1", s.org_note_in_test(&org, "n1"), Some("snapshot2"), Some(3), 2000, 7).unwrap();
        assert_eq!(s.post_org_updates(a.id, &org, "n1", &["u4".into()], 8).unwrap(), 4);
        let rev = s.org_note_in_test(&org, "n1");
        s.put_org_note(a.id, &org, "n1", rev, None, None, 2000, 9).unwrap();
        assert_eq!(s.org_updates_since(a.id, &org, "n1", 0, 10), Err(OrgNoteWrite::NoSuchNote));
        assert_eq!(s.post_org_updates(a.id, &org, "n3", &["x".into()], 10), Err(OrgNoteWrite::NoSuchNote));
    }

    #[test]
    fn a_stranger_an_invitee_and_a_full_organization_are_refused() {
        let (s, a, _dir) = fixture();
        let org = with_org(&s, a.id);
        let sam = s.create_account("sam", "login-hash", "wrapped-key", None, &[], 100).unwrap();
        assert_eq!(s.org_notes_since(sam.id, &org, 0, 10), Err(OrgNoteWrite::NoSuchOrg));
        assert_eq!(s.put_org_note(sam.id, &org, "n1", 0, Some("v"), None, 2000, 1), Err(OrgNoteWrite::NoSuchOrg));
        assert_eq!(s.put_org_file(sam.id, &org, "v-n1", 0, b"bytes", 1), Err(OrgNoteWrite::NoSuchOrg));
        let caps = crate::store::InviteCaps { rows_per_org: 50, pending_per_invitee: 20, decline_cooldown: 86_400 };
        s.invite(a.id, &org, "sam", 2, caps).unwrap();
        assert_eq!(s.org_notes_since(sam.id, &org, 0, 10), Err(OrgNoteWrite::NoSuchOrg), "invited is not joined");
        s.answer_invite(sam.id, &org, true, 3).unwrap();
        assert!(s.org_notes_since(sam.id, &org, 0, 10).is_ok());
        s.put_org_note(a.id, &org, "n1", 0, Some("v"), None, 2, 4).unwrap();
        s.put_org_note(sam.id, &org, "n2", 0, Some("v"), None, 2, 5).unwrap();
        assert_eq!(s.put_org_note(a.id, &org, "n3", 0, Some("v"), None, 2, 6), Err(OrgNoteWrite::Full));
        // A deletion is never refused for fullness, and frees a place.
        let rev = s.org_note_in_test(&org, "n2");
        s.put_org_note(sam.id, &org, "n2", rev, None, None, 2, 7).unwrap();
        assert!(s.put_org_note(a.id, &org, "n3", 0, Some("v"), None, 2, 8).is_ok());
    }

    #[test]
    fn files_are_whole_with_the_organizations_revision_and_go_with_it() {
        let (s, a, dir) = fixture();
        let org = with_org(&s, a.id);
        let rev = s.put_org_file(a.id, &org, "v-n1", 0, b"versions-1", 1).unwrap();
        assert_eq!(s.org_file(a.id, &org, "v-n1").unwrap(), Some((rev, b"versions-1".to_vec())));
        assert_eq!(s.put_org_file(a.id, &org, "v-n1", 0, b"stale", 2), Err(OrgNoteWrite::StaleFile(rev)));
        let next = s.put_org_file(a.id, &org, "v-n1", rev, b"versions-2", 3).unwrap();
        assert!(next > rev);
        assert_eq!(s.org_file(a.id, &org, "nothing").unwrap(), None);
        let (_, _, head) = s.org_notes_since(a.id, &org, 0, 10).unwrap();
        assert_eq!(head, next, "files take the organization's counter too");
        s.delete_org(a.id, &org, 9).unwrap();
        assert!(!dir.path().join("recordings").join("org-org-1").exists());
    }

    impl Store {
        /// A note's revision, for the tests.
        fn org_note_in_test(&self, org: &str, note: &str) -> i64 {
            Self::org_note_in(&self.lock(), org, note).unwrap().map(|row| row.rev).unwrap_or(0)
        }
    }
}
