//! Incoming hooks (src/hooks.rs, docs/INTEGRATIONS.md, "In: a URL that adds to a note"): each account's hooks, and
//! what was posted to them, sealed.
//!
//! A hook is kept with its name and its default note in the clear, as an organization's name is, and with the SHA-256
//! of its token, never the token: the service finds a hook by the hash of what was posted to, and nobody reading this
//! table can post to one. What was posted is kept ONLY sealed, to the account's encryption public key, until a device
//! of the account has opened it and added it to its note, and deletes it; or until it is thirty days old, when the
//! sweep (`sweep_hook_inbox`, run by main.rs every hour and by every post for its own account) takes it.

use super::Store;
use rusqlite::params;

/// Why a hook or a post to one was not kept.
#[derive(Debug, PartialEq, Eq)]
pub enum HookWrite {
    /// The account has as many hooks, or as many posts waiting, as it may.
    Full,
    Failed,
}

impl From<rusqlite::Error> for HookWrite {
    fn from(_: rusqlite::Error) -> Self {
        HookWrite::Failed
    }
}

/// A hook as its account's devices list it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HookRow {
    pub id: String,
    pub account: i64,
    pub name: String,
    pub note: Option<String>,
    pub created_at: i64,
    pub last_used_at: Option<i64>,
}

/// One post waiting, sealed: its id, its hook's id, the seal, and when it came.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HookItem {
    pub id: String,
    pub hook: String,
    pub sealed: String,
    pub at: i64,
}

fn hook_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<HookRow> {
    Ok(HookRow { id: r.get(0)?, account: r.get(1)?, name: r.get(2)?, note: r.get(3)?, created_at: r.get(4)?, last_used_at: r.get(5)? })
}

const HOOK_COLUMNS: &str = "id, account_id, name, note, created_at, last_used_at";

impl Store {
    // --- the hooks ---------------------------------------------------------------------

    /// Makes `hook` for its account, found by `token_hash`, unless the account already has `most`.
    pub fn put_hook(&self, hook: &HookRow, token_hash: &str, most: i64) -> Result<(), HookWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let made: i64 = tx.query_row("SELECT COUNT(*) FROM hooks WHERE account_id = ?1", params![hook.account], |r| r.get(0))?;
        if made >= most {
            return Err(HookWrite::Full);
        }
        tx.execute(
            "INSERT INTO hooks (id, account_id, token_hash, name, note, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![hook.id, hook.account, token_hash, hook.name, hook.note, hook.created_at],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// The account's hooks, oldest first.
    pub fn hooks_of(&self, account: i64) -> Vec<HookRow> {
        self.all(&format!("SELECT {HOOK_COLUMNS} FROM hooks WHERE account_id = ?1 ORDER BY created_at, id"), params![account], hook_row)
    }

    /// The hook whose token hashes to `token_hash`, whoever's it is.
    pub fn hook_by_token(&self, token_hash: &str) -> Option<HookRow> {
        self.one(&format!("SELECT {HOOK_COLUMNS} FROM hooks WHERE token_hash = ?1"), params![token_hash], hook_row)
    }

    /// A hook gone: its URL takes nothing from now on. What it was posted already stays until a device takes it.
    pub fn delete_hook(&self, account: i64, id: &str) -> bool {
        self.lock().execute("DELETE FROM hooks WHERE id = ?1 AND account_id = ?2", params![id, account]).map(|n| n > 0).unwrap_or(false)
    }

    // --- what was posted ---------------------------------------------------------------

    /// Keeps a sealed post for the account, unless it already has `most` waiting that are younger than `expired`
    /// (seconds); those older go first, in the same transaction, so a full inbox empties itself with time.
    pub fn put_hook_item(&self, account: i64, item: &HookItem, most: i64, expired: i64) -> Result<(), HookWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        tx.execute("DELETE FROM hook_inbox WHERE account_id = ?1 AND received_at <= ?2", params![account, expired])?;
        let waiting: i64 = tx.query_row("SELECT COUNT(*) FROM hook_inbox WHERE account_id = ?1", params![account], |r| r.get(0))?;
        if waiting >= most {
            return Err(HookWrite::Full);
        }
        tx.execute(
            "INSERT INTO hook_inbox (id, account_id, hook_id, sealed, received_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![item.id, account, item.hook, item.sealed, item.at],
        )?;
        tx.execute("UPDATE hooks SET last_used_at = ?1 WHERE id = ?2", params![item.at, item.hook])?;
        tx.commit()?;
        Ok(())
    }

    /// What waits for the account, oldest first, at most `limit`, younger than `expired` (seconds): after the post
    /// `after` names, or from the first when it names none, or one already taken - a device deletes each as it adds
    /// it, so a cursor that is gone starts over at what is left.
    pub fn hook_inbox(&self, account: i64, after: Option<&str>, limit: i64, expired: i64) -> Vec<HookItem> {
        self.all(
            "SELECT id, hook_id, sealed, received_at FROM hook_inbox WHERE account_id = ?1 AND received_at > ?2 \
             AND seq > COALESCE((SELECT seq FROM hook_inbox WHERE id = ?3 AND account_id = ?1), 0) ORDER BY seq LIMIT ?4",
            params![account, expired, after, limit],
            |r| Ok(HookItem { id: r.get(0)?, hook: r.get(1)?, sealed: r.get(2)?, at: r.get(3)? }),
        )
    }

    /// A post taken: a device has added it to its note. Answers whether one went.
    pub fn delete_hook_item(&self, account: i64, id: &str) -> bool {
        self.lock().execute("DELETE FROM hook_inbox WHERE id = ?1 AND account_id = ?2", params![id, account]).map(|n| n > 0).unwrap_or(false)
    }

    /// Every post, of every account, at `expired` (seconds) or older, gone. Answers how many.
    pub fn sweep_hook_inbox(&self, expired: i64) -> usize {
        self.lock().execute("DELETE FROM hook_inbox WHERE received_at <= ?1", params![expired]).unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    fn hook(account: i64, id: &str, name: &str, note: Option<&str>, at: i64) -> HookRow {
        HookRow { id: id.into(), account, name: name.into(), note: note.map(str::to_string), created_at: at, last_used_at: None }
    }

    fn item(id: &str, at: i64) -> HookItem {
        HookItem { id: id.into(), hook: "h1".into(), sealed: "s".into(), at }
    }

    #[test]
    fn a_hook_is_found_by_its_token_s_hash_listed_by_its_account_and_deleted_by_it_alone() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        s.put_hook(&hook(a.id, "h1", "Zapier", Some("Groceries"), 10), "hash-1", 2).unwrap();
        s.put_hook(&hook(a.id, "h2", "IFTTT", None, 20), "hash-2", 2).unwrap();
        assert_eq!(s.put_hook(&hook(a.id, "h3", "Make", None, 30), "hash-3", 2), Err(HookWrite::Full));
        let found = s.hook_by_token("hash-1").unwrap();
        assert_eq!((found.id.as_str(), found.account, found.note.as_deref()), ("h1", a.id, Some("Groceries")));
        assert_eq!(s.hook_by_token("h1"), None, "an id is not a token");
        assert_eq!(s.hooks_of(a.id).iter().map(|h| h.id.as_str()).collect::<Vec<_>>(), vec!["h1", "h2"]);
        assert!(s.hooks_of(b.id).is_empty());
        assert!(!s.delete_hook(b.id, "h1"), "another account deletes none of them");
        assert!(s.delete_hook(a.id, "h1"));
        assert_eq!(s.hook_by_token("hash-1"), None);
    }

    #[test]
    fn posts_wait_oldest_first_in_pages_up_to_their_limit_and_only_their_account_reads_or_takes_them() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        s.put_hook(&hook(a.id, "h1", "Zapier", None, 1), "hash-1", 10).unwrap();
        for (i, id) in ["p1", "p2", "p3"].iter().enumerate() {
            s.put_hook_item(a.id, &item(id, 100 + i as i64), 3, 0).unwrap();
        }
        assert_eq!(s.put_hook_item(a.id, &item("p4", 200), 3, 0), Err(HookWrite::Full));
        assert_eq!(s.hooks_of(a.id)[0].last_used_at, Some(102));
        let ids = |items: Vec<HookItem>| items.into_iter().map(|i| i.id).collect::<Vec<_>>();
        assert_eq!(ids(s.hook_inbox(a.id, None, 2, 0)), vec!["p1", "p2"]);
        assert_eq!(ids(s.hook_inbox(a.id, Some("p2"), 2, 0)), vec!["p3"]);
        assert!(s.hook_inbox(b.id, None, 10, 0).is_empty());
        assert!(!s.delete_hook_item(b.id, "p1"));
        assert!(s.delete_hook_item(a.id, "p1") && s.delete_hook_item(a.id, "p2"));
        assert_eq!(ids(s.hook_inbox(a.id, Some("p2"), 2, 0)), vec!["p3"], "a cursor taken already starts over at what is left");
    }

    #[test]
    fn an_old_post_is_not_listed_is_swept_and_makes_room_for_a_new_one() {
        let (s, a, _dir) = fixture();
        s.put_hook_item(a.id, &item("old", 100), 1, 0).unwrap();
        assert!(s.hook_inbox(a.id, None, 10, 100).is_empty(), "at the expiry, not listed");
        s.put_hook_item(a.id, &item("new", 300), 1, 100).unwrap();
        assert_eq!(s.hook_inbox(a.id, None, 10, 0).iter().map(|i| i.id.as_str()).collect::<Vec<_>>(), vec!["new"], "the old one went to make room");
        assert_eq!(s.sweep_hook_inbox(299), 0);
        assert_eq!(s.sweep_hook_inbox(300), 1);
        assert!(s.hook_inbox(a.id, None, 10, 0).is_empty());
    }

    #[test]
    fn hooks_and_their_posts_go_with_the_account() {
        let (s, a, _dir) = fixture();
        s.put_hook(&hook(a.id, "h1", "Zapier", None, 1), "hash-1", 10).unwrap();
        s.put_hook_item(a.id, &item("p1", 1), 10, 0).unwrap();
        s.lock().execute("DELETE FROM accounts WHERE id = ?1", params![a.id]).unwrap();
        assert_eq!(s.hook_by_token("hash-1"), None);
        assert!(s.hook_inbox(a.id, None, 10, 0).is_empty());
    }
}
