//! Encryption keys and colours (docs/SHARED.md; src/orgs.rs): an account's encryption key pair, the organization key
//! wrapped for each member under it, and a person's colour - the account's own, and an organization's override.
//!
//! Nothing here opens anything. The public key is in the clear so a member can wrap to it; the private key and every
//! wrap are ciphertext made on a device. The service's part is the arbitration: one key pair an account, the first
//! registration standing; one generation of the organization key in force, the first device to make it winning; and
//! who still lacks a wrap at that generation, told to any member who holds the key.
use super::orgs::MEMBER;
use super::{OrgWrite, Store};
use rusqlite::{params, Connection, OptionalExtension};

/// An account's registered key pair: the public key in the clear, the private key sealed under the account key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountKey {
    pub pub_key: String,
    pub sealed: String,
}

/// Why a key was not written.
#[derive(Debug, PartialEq, Eq)]
pub enum KeyWrite {
    /// The account has a key pair already, and it stands: here it is.
    HasKey(AccountKey),
    /// No organization by that id that the caller has joined: one answer for "none" and "not yours".
    NoSuchOrg,
    /// The generation posted is not the one in force, nor the first from none: here is the one in force (0 for none).
    Generation(i64),
    Failed,
}

impl From<rusqlite::Error> for KeyWrite {
    fn from(_: rusqlite::Error) -> Self {
        KeyWrite::Failed
    }
}

/// The organization key wrapped for one member, as a device posts it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Wrap {
    pub handle: String,
    pub wrapped: String,
}

/// The organization key as a member reads it: the generation in force (0 while none has been made), the caller's own
/// wrap at it, and the members who lack one and have a public key to wrap to - handle and key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrgKeys {
    pub generation: i64,
    pub mine: Option<String>,
    pub missing: Vec<(String, String)>,
    /// A member has left or been removed since the generation in force was made (S11): the next member device to
    /// sync makes the one after it, wrapped for those who remain, and re-seals the team's notes under it.
    pub stale: bool,
}

impl Store {
    // --- the account's key pair ---------------------------------------------------

    pub fn account_key(&self, account: i64) -> Option<AccountKey> {
        self.one("SELECT pub, sealed FROM account_keys WHERE account_id = ?1", params![account], |r| Ok(AccountKey { pub_key: r.get(0)?, sealed: r.get(1)? }))
    }

    /// Registers the account's key pair, or answers the one that stands: the first registration wins, so two devices
    /// making one at once end with one.
    pub fn register_key(&self, account: i64, pub_key: &str, sealed: &str, now: i64) -> Result<AccountKey, KeyWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let had = tx.query_row("SELECT pub, sealed FROM account_keys WHERE account_id = ?1", params![account], |r| Ok(AccountKey { pub_key: r.get(0)?, sealed: r.get(1)? })).optional()?;
        if let Some(had) = had {
            return Err(KeyWrite::HasKey(had));
        }
        tx.execute("INSERT INTO account_keys (account_id, pub, sealed, created_at) VALUES (?1, ?2, ?3, ?4)", params![account, pub_key, sealed, now])?;
        tx.commit()?;
        Ok(AccountKey { pub_key: pub_key.to_string(), sealed: sealed.to_string() })
    }

    // --- colours ----------------------------------------------------------------------

    /// The account's own colour, if one is chosen.
    pub fn account_hue(&self, account: i64) -> Option<String> {
        self.one("SELECT hue FROM account_hues WHERE account_id = ?1", params![account], |r| r.get(0))
    }

    /// The account's colour set, or cleared with `None`.
    pub fn set_account_hue(&self, account: i64, hue: Option<&str>) -> rusqlite::Result<()> {
        let conn = self.lock();
        match hue {
            Some(hue) => conn.execute("INSERT INTO account_hues (account_id, hue) VALUES (?1, ?2) ON CONFLICT(account_id) DO UPDATE SET hue = excluded.hue", params![account, hue])?,
            None => conn.execute("DELETE FROM account_hues WHERE account_id = ?1", params![account])?,
        };
        Ok(())
    }

    /// The caller's colour in one organization set, or cleared with `None` to the account's own; the organization
    /// as they now read it. For a member; a stranger or an invitee learns nothing.
    pub fn set_org_hue(&self, actor: i64, org: &str, hue: Option<&str>) -> Result<super::Org, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        Self::acting(&tx, org, actor)?;
        match hue {
            Some(hue) => tx.execute(
                "INSERT INTO org_member_hues (org_id, account_id, hue) VALUES (?1, ?2, ?3) ON CONFLICT(org_id, account_id) DO UPDATE SET hue = excluded.hue",
                params![org, actor, hue],
            )?,
            None => tx.execute("DELETE FROM org_member_hues WHERE org_id = ?1 AND account_id = ?2", params![org, actor])?,
        };
        let after = Self::org_in(&tx, actor, org)?.ok_or(OrgWrite::Failed)?;
        tx.commit()?;
        Ok(after)
    }

    // --- the organization key ------------------------------------------------------

    pub(super) fn generation_of(conn: &Connection, org: &str) -> rusqlite::Result<i64> {
        Ok(conn.query_row("SELECT generation FROM org_key_state WHERE org_id = ?1", params![org], |r| r.get(0)).optional()?.unwrap_or(0))
    }

    /// A turn owed (S11): a member has gone, so the generation in force must be replaced before it is trusted again.
    pub(super) fn turn_key(conn: &Connection, org: &str, now: i64) -> rusqlite::Result<()> {
        conn.execute("INSERT INTO org_key_turns (org_id, at) VALUES (?1, ?2)", params![org, now])?;
        Ok(())
    }

    fn stale_in(conn: &Connection, org: &str, generation: i64) -> rusqlite::Result<bool> {
        if generation == 0 {
            return Ok(false);
        }
        let owed: i64 = conn.query_row("SELECT COUNT(*) FROM org_key_turns WHERE org_id = ?1", params![org], |r| r.get(0))?;
        Ok(owed > 0)
    }

    /// The key as `account` reads it: `mine` at the generation in force, or at `at` when one is asked for - an older
    /// generation, for a row that was sealed before the key turned and not yet re-sealed.
    fn keys_in(conn: &Connection, account: i64, org: &str, at: Option<i64>) -> rusqlite::Result<OrgKeys> {
        let generation = Self::generation_of(conn, org)?;
        if generation == 0 {
            // Nothing made yet: everyone with a public key lacks a wrap, which is what the maker wraps for.
            let mut stmt = conn.prepare("SELECT a.handle, k.pub FROM org_members m JOIN accounts a ON a.id = m.account_id JOIN account_keys k ON k.account_id = m.account_id WHERE m.org_id = ?1 AND m.state = ?2 ORDER BY m.since, m.rowid")?;
            let missing = stmt.query_map(params![org, MEMBER], |r| Ok((r.get(0)?, r.get(1)?)))?.filter_map(Result::ok).collect();
            return Ok(OrgKeys { generation, mine: None, missing, stale: false });
        }
        let mine = conn
            .query_row("SELECT wrapped FROM org_keys WHERE org_id = ?1 AND account_id = ?2 AND generation = ?3", params![org, account, at.unwrap_or(generation)], |r| r.get(0))
            .optional()?;
        let mut stmt = conn.prepare(
            "SELECT a.handle, k.pub FROM org_members m JOIN accounts a ON a.id = m.account_id JOIN account_keys k ON k.account_id = m.account_id \
             WHERE m.org_id = ?1 AND m.state = ?2 AND NOT EXISTS (SELECT 1 FROM org_keys w WHERE w.org_id = m.org_id AND w.account_id = m.account_id AND w.generation = ?3) \
             ORDER BY m.since, m.rowid",
        )?;
        let missing = stmt.query_map(params![org, MEMBER, generation], |r| Ok((r.get(0)?, r.get(1)?)))?.filter_map(Result::ok).collect();
        Ok(OrgKeys { generation, mine, missing, stale: Self::stale_in(conn, org, generation)? })
    }

    /// The organization key as `account` reads it: for a member; a stranger or an invitee learns nothing. With `at`,
    /// the caller's wrap at that older generation instead of the one in force.
    pub fn org_keys(&self, account: i64, org: &str, at: Option<i64>) -> Result<OrgKeys, KeyWrite> {
        let conn = self.lock();
        match Self::acting(&conn, org, account) {
            Ok(_) => Ok(Self::keys_in(&conn, account, org, at)?),
            Err(_) => Err(KeyWrite::NoSuchOrg),
        }
    }

    /// Wraps posted by a member holding the key. With `make`, a new generation - the one after the generation in
    /// force, the first from none - which this call brings into force; without, wraps at the generation in force for
    /// members who lack one at it. Either way a generation that is not that one is refused with the one in force, so
    /// two devices making a key at once end with one, and a wrap at a stale generation is never kept. A wrap for a
    /// member who already has one at the generation is left as it was; one for a handle that is not a member of the
    /// organization is dropped. Answers the state after.
    pub fn post_org_keys(&self, actor: i64, org: &str, generation: i64, make: bool, wraps: &[Wrap], now: i64) -> Result<OrgKeys, KeyWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        if Self::acting(&tx, org, actor).is_err() {
            return Err(KeyWrite::NoSuchOrg);
        }
        let in_force = Self::generation_of(&tx, org)?;
        if make {
            if generation != in_force + 1 {
                return Err(KeyWrite::Generation(in_force));
            }
            tx.execute(
                "INSERT INTO org_key_state (org_id, generation, made_by, made_at) VALUES (?1, ?2, ?3, ?4) \
                 ON CONFLICT(org_id) DO UPDATE SET generation = excluded.generation, made_by = excluded.made_by, made_at = excluded.made_at",
                params![org, generation, actor, now],
            )?;
            // The turns owed are answered by this generation.
            tx.execute("DELETE FROM org_key_turns WHERE org_id = ?1", params![org])?;
        } else if generation != in_force {
            return Err(KeyWrite::Generation(in_force));
        }
        for wrap in wraps {
            // Only someone who has joined gets a wrap: an invitee could read the team's notes before accepting.
            let member: Option<i64> = tx
                .query_row("SELECT m.account_id FROM org_members m JOIN accounts a ON a.id = m.account_id WHERE m.org_id = ?1 AND a.handle = ?2 AND m.state = ?3", params![org, wrap.handle, MEMBER], |r| r.get(0))
                .optional()?;
            let Some(member) = member else { continue };
            tx.execute(
                "INSERT OR IGNORE INTO org_keys (org_id, account_id, generation, wrapped, wrapped_by, wrapped_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![org, member, generation, wrap.wrapped, actor, now],
            )?;
        }
        let after = Self::keys_in(&tx, actor, org, None)?;
        tx.commit()?;
        Ok(after)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::fixture;

    #[test]
    fn a_key_pair_is_registered_once_and_the_first_stands() {
        let (store, matt, _dir) = fixture();
        assert_eq!(store.account_key(matt.id), None);
        let first = store.register_key(matt.id, "pub-a", "sealed-a", 1).unwrap();
        assert_eq!(first, AccountKey { pub_key: "pub-a".into(), sealed: "sealed-a".into() });
        assert_eq!(store.register_key(matt.id, "pub-b", "sealed-b", 2), Err(KeyWrite::HasKey(first.clone())));
        assert_eq!(store.account_key(matt.id), Some(first));
    }

    #[test]
    fn a_colour_is_set_cleared_and_overridden_in_an_organization() {
        let (store, matt, _dir) = fixture();
        assert_eq!(store.account_hue(matt.id), None);
        store.set_account_hue(matt.id, Some("sea")).unwrap();
        assert_eq!(store.account_hue(matt.id), Some("sea".into()));
        let org = store.create_org(matt.id, "org-1", "Ghost", None, 1, 20).unwrap();
        assert_eq!(org.members[0].colour, Some("sea".into()), "the account's colour, with no override");
        let org = store.set_org_hue(matt.id, "org-1", Some("rose")).unwrap();
        assert_eq!(org.members[0].colour, Some("rose".into()));
        let org = store.set_org_hue(matt.id, "org-1", None).unwrap();
        assert_eq!(org.members[0].colour, Some("sea".into()));
        store.set_account_hue(matt.id, None).unwrap();
        assert_eq!(store.account_hue(matt.id), None);
        assert_eq!(store.set_org_hue(matt.id, "org-2", Some("rose")), Err(OrgWrite::NoSuchOrg));
    }

    #[test]
    fn the_organization_key_is_made_once_wrapped_for_the_missing_and_never_for_an_invitee() {
        let (store, matt, _dir) = fixture();
        let sam = store.create_account("sam", "login-hash", "wrapped-key", None, &[], 100).unwrap();
        let lee = store.create_account("lee", "login-hash", "wrapped-key", None, &[], 100).unwrap();
        store.create_org(matt.id, "org-1", "Ghost", None, 1, 20).unwrap();
        let caps = || crate::store::InviteCaps { rows_per_org: 50, pending_per_invitee: 20, decline_cooldown: 86_400 };
        store.invite(matt.id, "org-1", "sam", 2, caps()).unwrap();
        store.answer_invite(sam.id, "org-1", true, 3).unwrap();
        store.invite(matt.id, "org-1", "lee", 4, caps()).unwrap();
        // Nothing yet, and only those with a key pair can be wrapped for: sam has none.
        store.register_key(matt.id, "pub-matt", "sealed", 1).unwrap();
        let none = store.org_keys(matt.id, "org-1").unwrap();
        assert_eq!(none, OrgKeys { generation: 0, mine: None, missing: vec![("matt".into(), "pub-matt".into())] });
        // The first generation, made with matt's own wrap; a second maker is told the generation in force.
        let made = store.post_org_keys(matt.id, "org-1", 1, true, &[Wrap { handle: "matt".into(), wrapped: "w-matt-1".into() }], 5).unwrap();
        assert_eq!(made, OrgKeys { generation: 1, mine: Some("w-matt-1".into()), missing: vec![] });
        assert_eq!(store.post_org_keys(sam.id, "org-1", 1, true, &[], 6), Err(KeyWrite::Generation(1)), "a second maker is told the one in force");
        assert_eq!(store.post_org_keys(sam.id, "org-1", 1, false, &[], 6), Ok(OrgKeys { generation: 1, mine: None, missing: vec![] }), "at the generation in force, nothing to add is fine");
        assert_eq!(store.post_org_keys(sam.id, "org-1", 2, false, &[], 6), Err(KeyWrite::Generation(1)));
        assert_eq!(store.post_org_keys(sam.id, "org-1", 3, true, &[], 6), Err(KeyWrite::Generation(1)), "a new generation is the next one");
        // sam registers a key pair: now lacking, and listed to a member who reads; lee, invited, is not.
        store.register_key(sam.id, "pub-sam", "sealed", 7).unwrap();
        store.register_key(lee.id, "pub-lee", "sealed", 7).unwrap();
        let read = store.org_keys(matt.id, "org-1").unwrap();
        assert_eq!(read.missing, vec![("sam".into(), "pub-sam".into())]);
        assert_eq!(store.org_keys(sam.id, "org-1").unwrap().mine, None);
        let filled = store.post_org_keys(matt.id, "org-1", 1, false, &[Wrap { handle: "sam".into(), wrapped: "w-sam-1".into() }, Wrap { handle: "lee".into(), wrapped: "w-lee-1".into() }, Wrap { handle: "matt".into(), wrapped: "w-matt-again".into() }], 8).unwrap();
        assert_eq!(filled.missing, vec![]);
        assert_eq!(store.org_keys(sam.id, "org-1").unwrap().mine, Some("w-sam-1".into()));
        assert_eq!(store.org_keys(matt.id, "org-1").unwrap().mine, Some("w-matt-1".into()), "a wrap already there is kept");
        assert_eq!(store.org_keys(lee.id, "org-1"), Err(KeyWrite::NoSuchOrg), "an invitee reads nothing");
        assert_eq!(store.org_keys(sam.id, "org-9"), Err(KeyWrite::NoSuchOrg));
    }
}
