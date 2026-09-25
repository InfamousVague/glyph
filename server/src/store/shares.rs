//! Shares: a note or a book sealed under a key only its link carries, kept under the device's own id with its owner,
//! and readable by anyone who has the id (src/shares.rs, docs/SHARING.md).
//!
//! A share has no revision. It is written whole each time its owner edits, and `updated_at` - wall-clock seconds, not
//! the account's write counter - is its version, which is what the app's ten-minute rule reads.

use super::Store;
use rusqlite::{params, OptionalExtension};

/// Why a share was not written.
#[derive(Debug, PartialEq, Eq)]
pub enum ShareWrite {
    /// The id is another account's share.
    Taken,
    /// The account already keeps as many shares as it may.
    Full,
    /// Something below the rules failed.
    Failed,
}

impl Store {
    /// Writes an account's share: made if new, written again if it is theirs; refused if it is another's, or if a new
    /// one would take the account past `most`. Answers when it was written.
    pub fn put_share(&self, account: i64, id: &str, blob: &str, now: i64, most: i64) -> Result<i64, ShareWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(|_| ShareWrite::Failed)?;
        let owner: Option<i64> = tx
            .query_row("SELECT account_id FROM shares WHERE id = ?1", params![id], |r| r.get(0))
            .optional()
            .map_err(|_| ShareWrite::Failed)?;
        match owner {
            Some(owner) if owner != account => return Err(ShareWrite::Taken),
            Some(_) => {
                tx.execute("UPDATE shares SET blob = ?1, updated_at = ?2 WHERE id = ?3", params![blob, now, id]).map_err(|_| ShareWrite::Failed)?;
            }
            None => {
                let kept: i64 = tx
                    .query_row("SELECT COUNT(*) FROM shares WHERE account_id = ?1", params![account], |r| r.get(0))
                    .map_err(|_| ShareWrite::Failed)?;
                if kept >= most {
                    return Err(ShareWrite::Full);
                }
                tx.execute(
                    "INSERT INTO shares (id, account_id, blob, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)",
                    params![id, account, blob, now],
                )
                .map_err(|_| ShareWrite::Failed)?;
            }
        }
        tx.commit().map_err(|_| ShareWrite::Failed)?;
        Ok(now)
    }

    /// A share's ciphertext and when it was last written, for anyone who has its id.
    pub fn share(&self, id: &str) -> Option<(String, i64)> {
        self.one("SELECT blob, updated_at FROM shares WHERE id = ?1", params![id], |r| Ok((r.get(0)?, r.get(1)?)))
    }

    /// Takes down an account's share; another's, or none, is left as it is. Answers whether one went.
    pub fn delete_share(&self, account: i64, id: &str) -> bool {
        self.lock().execute("DELETE FROM shares WHERE id = ?1 AND account_id = ?2", params![id, account]).map(|n| n > 0).unwrap_or(false)
    }

    /// An account's shares, newest written first: their ids and when each was written.
    pub fn shares_of(&self, account: i64) -> Vec<(String, i64)> {
        self.all("SELECT id, updated_at FROM shares WHERE account_id = ?1 ORDER BY updated_at DESC", params![account], |r| Ok((r.get(0)?, r.get(1)?)))
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    #[test]
    fn an_account_keeps_at_most_its_limit_and_may_still_write_the_ones_it_has() {
        let (s, a, _dir) = fixture();
        assert_eq!(s.put_share(a.id, "one", "b1", 10, 2), Ok(10));
        assert_eq!(s.put_share(a.id, "two", "b2", 11, 2), Ok(11));
        assert_eq!(s.put_share(a.id, "three", "b3", 12, 2), Err(ShareWrite::Full));
        assert_eq!(s.share("three"), None, "a refused share is not kept");
        assert_eq!(s.put_share(a.id, "one", "b1-edited", 13, 2), Ok(13), "an edit is not a new share");
        assert_eq!(s.share("one"), Some(("b1-edited".to_string(), 13)));
        assert!(s.delete_share(a.id, "two"));
        assert_eq!(s.put_share(a.id, "three", "b3", 14, 2), Ok(14), "a share taken down makes room");
    }

    #[test]
    fn another_account_cannot_write_or_take_down_a_share_it_does_not_own() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        s.put_share(a.id, "mine", "sealed", 10, 500).unwrap();
        assert_eq!(s.put_share(b.id, "mine", "theirs", 11, 500), Err(ShareWrite::Taken));
        assert!(!s.delete_share(b.id, "mine"));
        assert_eq!(s.share("mine"), Some(("sealed".to_string(), 10)));
        assert!(s.shares_of(b.id).is_empty());
    }

    #[test]
    fn an_owner_s_shares_are_listed_newest_written_first() {
        let (s, a, _dir) = fixture();
        s.put_share(a.id, "old", "b", 10, 500).unwrap();
        s.put_share(a.id, "new", "b", 20, 500).unwrap();
        s.put_share(a.id, "old", "b", 30, 500).unwrap();
        assert_eq!(s.shares_of(a.id), vec![("old".to_string(), 30), ("new".to_string(), 20)]);
    }
}
