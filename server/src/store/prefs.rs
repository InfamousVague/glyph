//! Settings: one ciphertext blob per account and the revision it was written at, written from the revision a device
//! saw and refused with the stored one when that has moved on - AttackFM's settings blob, copied in shape.

use super::Store;
use rusqlite::{params, Connection, OptionalExtension};

impl Store {
    /// The stored settings and their revision, read by `prefs` and inside `put_prefs`'s transaction alike.
    fn prefs_in(conn: &Connection, account: i64) -> rusqlite::Result<Option<(i64, String)>> {
        conn.query_row("SELECT rev, blob FROM prefs WHERE account_id = ?1", params![account], |r| Ok((r.get(0)?, r.get(1)?))).optional()
    }

    pub fn prefs(&self, account: i64) -> Option<(i64, String)> {
        Self::prefs_in(&self.lock(), account).ok().flatten()
    }

    /// Stores settings written from `base`: 0 for "never seen any". Refused, with the stored ones, when stale.
    pub fn put_prefs(&self, account: i64, base: i64, blob: &str, now: i64) -> Result<i64, Option<(i64, String)>> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(|_| None)?;
        let current = Self::prefs_in(&tx, account).map_err(|_| None)?;
        let stored_rev = current.as_ref().map(|(rev, _)| *rev).unwrap_or(0);
        if stored_rev != base {
            return Err(current);
        }
        let rev = Self::next_rev(&tx, account).map_err(|_| None)?;
        tx.execute(
            "INSERT INTO prefs (account_id, rev, blob, updated_at) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(account_id) DO UPDATE SET rev = excluded.rev, blob = excluded.blob, updated_at = excluded.updated_at",
            params![account, rev, blob, now],
        )
        .map_err(|_| None)?;
        tx.commit().map_err(|_| None)?;
        Ok(rev)
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;

    #[test]
    fn settings_are_written_from_the_revision_they_saw() {
        let (s, a, _dir) = fixture();
        let first = s.put_prefs(a.id, 0, "p1", 1).unwrap();
        assert_eq!(s.put_prefs(a.id, 0, "stale", 2), Err(Some((first, "p1".to_string()))));
        let second = s.put_prefs(a.id, first, "p2", 3).unwrap();
        assert_eq!(s.prefs(a.id), Some((second, "p2".to_string())));
    }
}
