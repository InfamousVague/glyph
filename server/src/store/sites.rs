//! Published sites: a note or a notebook sealed under a key only the site's link carries, as a share is, kept under the
//! device's own id with its owner (src/sites.rs, docs/SITES.md).
//!
//! A site differs from a share in two ways the store sees. It is written when its owner says so (Publish, Publish
//! again), not after every save, so `updated_at` is when it was last published. And it keeps a second blob, `meta`,
//! sealed under the ACCOUNT key: what the site is of (the note's id), its title and its link's key, so every device of
//! the account can list the account's sites with their links without the settings carrying them. The service can open
//! neither blob.

use super::Store;
use rusqlite::{params, OptionalExtension};

/// Why a site was not written.
#[derive(Debug, PartialEq, Eq)]
pub enum SiteWrite {
    /// The id is another account's site.
    Taken,
    /// The account already keeps as many sites as it may.
    Full,
    /// Something below the rules failed.
    Failed,
}

impl From<rusqlite::Error> for SiteWrite {
    fn from(_: rusqlite::Error) -> Self {
        SiteWrite::Failed
    }
}

/// A site as its owner lists it: its id, what its devices sealed about it, and when it was first and last published.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SiteRow {
    pub id: String,
    pub meta: String,
    pub created: i64,
    pub updated: i64,
}

impl Store {
    /// Publishes an account's site: made if new, written over if it is theirs; refused if it is another's, or if a new
    /// one would take the account past `most`. Answers when it was published.
    pub fn put_site(&self, account: i64, id: &str, blob: &str, meta: &str, now: i64, most: i64) -> Result<i64, SiteWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let owner: Option<i64> = tx.query_row("SELECT account_id FROM sites WHERE id = ?1", params![id], |r| r.get(0)).optional()?;
        match owner {
            Some(owner) if owner != account => return Err(SiteWrite::Taken),
            Some(_) => {
                tx.execute("UPDATE sites SET blob = ?1, meta = ?2, updated_at = ?3 WHERE id = ?4", params![blob, meta, now, id])?;
            }
            None => {
                let kept: i64 = tx.query_row("SELECT COUNT(*) FROM sites WHERE account_id = ?1", params![account], |r| r.get(0))?;
                if kept >= most {
                    return Err(SiteWrite::Full);
                }
                tx.execute(
                    "INSERT INTO sites (id, account_id, blob, meta, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
                    params![id, account, blob, meta, now],
                )?;
            }
        }
        tx.commit()?;
        Ok(now)
    }

    /// A site's ciphertext and when it was last published, for anyone who has its id.
    pub fn site(&self, id: &str) -> Option<(String, i64)> {
        self.one("SELECT blob, updated_at FROM sites WHERE id = ?1", params![id], |r| Ok((r.get(0)?, r.get(1)?)))
    }

    /// Unpublishes an account's site; another's, or none, is left as it is. Answers whether one went.
    pub fn delete_site(&self, account: i64, id: &str) -> bool {
        self.lock().execute("DELETE FROM sites WHERE id = ?1 AND account_id = ?2", params![id, account]).map(|n| n > 0).unwrap_or(false)
    }

    /// An account's sites, last published first.
    pub fn sites_of(&self, account: i64) -> Vec<SiteRow> {
        self.all(
            "SELECT id, meta, created_at, updated_at FROM sites WHERE account_id = ?1 ORDER BY updated_at DESC, id",
            params![account],
            |r| Ok(SiteRow { id: r.get(0)?, meta: r.get(1)?, created: r.get(2)?, updated: r.get(3)? }),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    #[test]
    fn an_account_keeps_at_most_its_limit_and_may_publish_the_ones_it_has_again() {
        let (s, a, _dir) = fixture();
        assert_eq!(s.put_site(a.id, "one", "b1", "m1", 10, 2), Ok(10));
        assert_eq!(s.put_site(a.id, "two", "b2", "m2", 11, 2), Ok(11));
        assert_eq!(s.put_site(a.id, "three", "b3", "m3", 12, 2), Err(SiteWrite::Full));
        assert_eq!(s.site("three"), None, "a refused site is not kept");
        assert_eq!(s.put_site(a.id, "one", "b1-again", "m1-again", 13, 2), Ok(13), "publishing again is not a new site");
        assert_eq!(s.site("one"), Some(("b1-again".to_string(), 13)));
        let one = s.sites_of(a.id).into_iter().find(|row| row.id == "one").unwrap();
        assert_eq!((one.meta.as_str(), one.created, one.updated), ("m1-again", 10, 13), "first published stays, last published moves");
        assert!(s.delete_site(a.id, "two"));
        assert_eq!(s.put_site(a.id, "three", "b3", "m3", 14, 2), Ok(14), "an unpublished site makes room");
    }

    #[test]
    fn another_account_cannot_publish_over_or_unpublish_a_site_it_does_not_own() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        s.put_site(a.id, "mine", "sealed", "meta", 10, 100).unwrap();
        assert_eq!(s.put_site(b.id, "mine", "theirs", "meta", 11, 100), Err(SiteWrite::Taken));
        assert!(!s.delete_site(b.id, "mine"));
        assert_eq!(s.site("mine"), Some(("sealed".to_string(), 10)));
        assert!(s.sites_of(b.id).is_empty());
    }

    #[test]
    fn a_site_goes_with_its_owner_s_account() {
        let (s, a, _dir) = fixture();
        s.put_site(a.id, "mine", "sealed", "meta", 10, 100).unwrap();
        s.lock().execute("DELETE FROM accounts WHERE id = ?1", params![a.id]).unwrap();
        assert_eq!(s.site("mine"), None);
    }
}
