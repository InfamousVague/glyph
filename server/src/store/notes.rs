//! Notes: each one's ciphertext and the revision it was written at, the feed of everything written after a revision,
//! and deletions kept as marker rows so a device that was away learns what went.
//!
//! A note is written from the revision it was last seen at, and refused with the stored one when that has moved on
//! (sync.rs answers the refusal with a 409 and the winner). The revision is the account's one write counter, which
//! settings and recordings take from too, so a note's revisions are ordered but not contiguous.

use super::{Store, WriteError};
use rusqlite::{params, Connection, OptionalExtension, Row};

/// A note as the service holds it: an id, where it is in the account's history, and its ciphertext.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteRow {
    pub id: String,
    pub rev: i64,
    pub deleted: bool,
    pub blob: Option<String>,
}

impl Store {
    /// A note as `SELECT id, rev, deleted, blob` reads it, the feed's and a write's alike.
    fn note_row(r: &Row<'_>) -> rusqlite::Result<NoteRow> {
        Ok(NoteRow { id: r.get(0)?, rev: r.get(1)?, deleted: r.get::<_, i64>(2)? != 0, blob: r.get(3)? })
    }

    /// Everything written after `since`, oldest first, at most `limit`; and whether there is more.
    pub fn notes_since(&self, id: i64, since: i64, limit: i64) -> rusqlite::Result<(Vec<NoteRow>, bool, i64)> {
        let conn = self.lock();
        let mut stmt = conn.prepare("SELECT id, rev, deleted, blob FROM notes WHERE account_id = ?1 AND rev > ?2 ORDER BY rev LIMIT ?3")?;
        let mut rows: Vec<NoteRow> = stmt.query_map(params![id, since, limit + 1], Self::note_row)?.filter_map(Result::ok).collect();
        let more = rows.len() as i64 > limit;
        rows.truncate(limit as usize);
        let head: i64 = conn.query_row("SELECT rev FROM accounts WHERE id = ?1", params![id], |r| r.get(0))?;
        Ok((rows, more, head))
    }

    fn note_in(conn: &Connection, account: i64, note: &str) -> rusqlite::Result<Option<NoteRow>> {
        conn.query_row("SELECT id, rev, deleted, blob FROM notes WHERE account_id = ?1 AND id = ?2", params![account, note], Self::note_row).optional()
    }

    /// Stores a note written from revision `base`, or refuses it when the stored note has moved on since. `None` for
    /// the blob is a deletion.
    ///
    /// A note the service has never seen is taken whatever its base: there is nothing it could overwrite.
    pub fn put_note(&self, account: i64, note: &str, base: i64, blob: Option<&str>, now: i64) -> Result<i64, WriteError<NoteRow>> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        if let Some(current) = Self::note_in(&tx, account, note)? {
            if current.rev != base {
                return Err(WriteError::Stale(current));
            }
        }
        let rev = Self::next_rev(&tx, account)?;
        tx.execute(
            "INSERT INTO notes (account_id, id, rev, deleted, blob, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(account_id, id) DO UPDATE SET rev = excluded.rev, deleted = excluded.deleted, blob = excluded.blob, updated_at = excluded.updated_at",
            params![account, note, rev, i64::from(blob.is_none()), blob, now],
        )?;
        tx.commit()?;
        Ok(rev)
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    #[test]
    fn notes_are_written_from_the_revision_they_saw() {
        let (s, a, _dir) = fixture();
        let first = s.put_note(a.id, "n1", 0, Some("v1"), 1).unwrap();
        let second = s.put_note(a.id, "n1", first, Some("v2"), 2).unwrap();
        assert!(second > first);
        // A device that only saw the first version lost the race: it is told what won.
        match s.put_note(a.id, "n1", first, Some("v2-elsewhere"), 3) {
            Err(WriteError::Stale(winner)) => assert_eq!((winner.rev, winner.blob.as_deref()), (second, Some("v2"))),
            other => panic!("expected a stale write, got {other:?}"),
        }
    }

    #[test]
    fn a_note_never_seen_is_taken_whatever_it_claims() {
        let (s, a, _dir) = fixture();
        assert!(s.put_note(a.id, "new", 42, Some("v"), 1).is_ok());
        // A deletion of a note the service never had is kept too, as a marker the other devices read.
        let rev = s.put_note(a.id, "never-synced", 7, None, 2).unwrap();
        let (feed, _, _) = s.notes_since(a.id, 0, 10).unwrap();
        assert_eq!(feed.last(), Some(&NoteRow { id: "never-synced".into(), rev, deleted: true, blob: None }));
    }

    #[test]
    fn the_feed_carries_writes_and_deletions_in_order_with_paging() {
        let (s, a, _dir) = fixture();
        let r1 = s.put_note(a.id, "a", 0, Some("a1"), 1).unwrap();
        s.put_note(a.id, "b", 0, Some("b1"), 2).unwrap();
        s.put_note(a.id, "a", r1, None, 3).unwrap();
        let (page, more, head) = s.notes_since(a.id, 0, 2).unwrap();
        assert_eq!(page.iter().map(|n| n.id.as_str()).collect::<Vec<_>>(), vec!["b", "a"]);
        assert!(!more);
        assert!(page[1].deleted && page[1].blob.is_none());
        assert_eq!(head, page[1].rev);
        let (rest, _, _) = s.notes_since(a.id, page[0].rev, 10).unwrap();
        assert_eq!(rest.len(), 1);
        let (one, more, _) = s.notes_since(a.id, 0, 1).unwrap();
        assert_eq!(one.len(), 1);
        assert!(more);
    }

    #[test]
    fn one_account_never_sees_another() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", Some(("k2", "d")), &[], 1).unwrap();
        s.put_note(a.id, "mine", 0, Some("secret"), 1).unwrap();
        assert!(s.notes_since(b.id, 0, 10).unwrap().0.is_empty());
        assert!(s.put_note(b.id, "mine", 0, Some("theirs"), 2).is_ok(), "the same id in another account is another note");
        assert_eq!(s.notes_since(a.id, 0, 10).unwrap().0[0].blob.as_deref(), Some("secret"));
    }
}
