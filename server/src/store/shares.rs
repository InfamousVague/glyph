//! Shares: a note or a book sealed under a key only its link carries, kept under the device's own id with its owner,
//! and readable by anyone who has the id (src/shares.rs, docs/SHARING.md).
//!
//! A share has no revision. It is written whole each time its owner edits, and `updated_at` - wall-clock seconds, not
//! the account's write counter - is its version, which is what the app's ten-minute rule reads.
//!
//! Beside the blob a share may carry `meta`, as a site does (store/sites.rs): what the owner's devices sealed about it
//! under the ACCOUNT key - the note it is of, its link's key, its switches - so a device signing in afresh lists the
//! account's shares with their links, where before the link's key lived only in the synced settings and went with
//! them (docs/MARKDOWN_FIRST.md §11 decision 8). Written on its own (`put_share_meta`), after the share, and never
//! moving `updated_at`, which is the words' version. NULL on a share from an older app. The service can open neither.

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

/// A query that failed is the write failing, as it is for `WriteError`: which query, the device cannot act on.
impl From<rusqlite::Error> for ShareWrite {
    fn from(_: rusqlite::Error) -> Self {
        ShareWrite::Failed
    }
}

/// Why a share's meta was not written.
#[derive(Debug, PartialEq, Eq)]
pub enum ShareMetaWrite {
    /// There is no share of this account's by that id: the share goes first.
    NoShare,
    /// Something below the rules failed.
    Failed,
}

impl From<rusqlite::Error> for ShareMetaWrite {
    fn from(_: rusqlite::Error) -> Self {
        ShareMetaWrite::Failed
    }
}

/// A share as its owner lists it: its id, when it was first and last written, and what its devices sealed about it,
/// where one has.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShareRow {
    pub id: String,
    pub created: i64,
    pub updated: i64,
    pub meta: Option<String>,
}

impl Store {
    /// Writes an account's share: made if new, written again if it is theirs; refused if it is another's, or if a new
    /// one would take the account past `most`. Answers when it was written.
    pub fn put_share(&self, account: i64, id: &str, blob: &str, now: i64, most: i64) -> Result<i64, ShareWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let owner: Option<i64> = tx.query_row("SELECT account_id FROM shares WHERE id = ?1", params![id], |r| r.get(0)).optional()?;
        match owner {
            Some(owner) if owner != account => return Err(ShareWrite::Taken),
            Some(_) => {
                tx.execute("UPDATE shares SET blob = ?1, updated_at = ?2 WHERE id = ?3", params![blob, now, id])?;
            }
            None => {
                let kept: i64 = tx.query_row("SELECT COUNT(*) FROM shares WHERE account_id = ?1", params![account], |r| r.get(0))?;
                if kept >= most {
                    return Err(ShareWrite::Full);
                }
                tx.execute(
                    "INSERT INTO shares (id, account_id, blob, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)",
                    params![id, account, blob, now],
                )?;
            }
        }
        tx.commit()?;
        Ok(now)
    }

    /// A share's ciphertext and when it was last written, for anyone who has its id.
    pub fn share(&self, id: &str) -> Option<(String, i64)> {
        self.one("SELECT blob, updated_at FROM shares WHERE id = ?1", params![id], |r| Ok((r.get(0)?, r.get(1)?)))
    }

    /// Takes down an account's share, with its recording; another's, or none, is left as it is. Answers whether one
    /// went.
    pub fn delete_share(&self, account: i64, id: &str) -> bool {
        let gone = self.lock().execute("DELETE FROM shares WHERE id = ?1 AND account_id = ?2", params![id, account]).map(|n| n > 0).unwrap_or(false);
        // A meeting's recording goes with its share (store/share_audio.rs): its row by the cascade, its file here.
        if gone {
            self.delete_share_audio(account, id);
        }
        gone
    }

    /// Writes what an account's devices sealed about its share; refused where the account has no share by that id.
    /// The share's own time is left as it is: the meta is not an edit a reader sees.
    pub fn put_share_meta(&self, account: i64, id: &str, meta: &str) -> Result<(), ShareMetaWrite> {
        let changed = self.lock().execute("UPDATE shares SET meta = ?1 WHERE id = ?2 AND account_id = ?3", params![meta, id, account])?;
        if changed == 0 {
            return Err(ShareMetaWrite::NoShare);
        }
        Ok(())
    }

    /// An account's shares, newest written first: their ids, when each was first and last written, and each one's
    /// meta where a device has sealed one.
    pub fn shares_of(&self, account: i64) -> Vec<ShareRow> {
        self.all("SELECT id, created_at, updated_at, meta FROM shares WHERE account_id = ?1 ORDER BY updated_at DESC, id", params![account], |r| {
            Ok(ShareRow { id: r.get(0)?, created: r.get(1)?, updated: r.get(2)?, meta: r.get(3)? })
        })
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
        assert_eq!(for_each(&s.shares_of(a.id)), vec![("old".to_string(), 10, 30), ("new".to_string(), 20, 20)]);
    }

    /// Each listed share as (id, first written, last written).
    fn for_each(rows: &[ShareRow]) -> Vec<(String, i64, i64)> {
        rows.iter().map(|row| (row.id.clone(), row.created, row.updated)).collect()
    }

    #[test]
    fn a_share_s_meta_is_written_after_the_share_moves_no_time_and_goes_with_it() {
        let (s, a, _dir) = fixture();
        assert_eq!(s.put_share_meta(a.id, "mine", "m1"), Err(ShareMetaWrite::NoShare), "the share goes first");
        s.put_share(a.id, "mine", "sealed", 10, 500).unwrap();
        assert_eq!(s.shares_of(a.id)[0].meta, None, "an older app's share says nothing about itself");
        assert_eq!(s.put_share_meta(a.id, "mine", "m1"), Ok(()));
        assert_eq!(s.put_share_meta(a.id, "mine", "m2"), Ok(()), "written over, as the devices' latest word");
        let listed = s.shares_of(a.id);
        assert_eq!((listed[0].meta.as_deref(), listed[0].updated), (Some("m2"), 10), "the words' time stands");
        assert_eq!(s.share("mine"), Some(("sealed".to_string(), 10)), "a reader sees nothing of it");
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        assert_eq!(s.put_share_meta(b.id, "mine", "theirs"), Err(ShareMetaWrite::NoShare), "another account has no share by that id");
        assert_eq!(s.shares_of(a.id)[0].meta.as_deref(), Some("m2"));
        assert!(s.delete_share(a.id, "mine"));
        assert!(s.shares_of(a.id).is_empty(), "taken down, the meta is gone with the share");
    }
}
