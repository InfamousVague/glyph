//! Accounts and what speaks for them: the `accounts` row itself, the device keys that may sign in without a password,
//! and the recovery codes - and deleting an account, which takes everything else it keeps here with it.
//!
//! What arrives as a password is already a login secret a device derived, and what is kept of it is its Argon2 hash
//! (src/accounts/credentials.rs); the account key is kept only wrapped. So a row here says who an account is, never what is in it.

use super::Store;
use rusqlite::{params, Connection, OptionalExtension, Row};

/// What an account's reads select, in the order `Store::account_row` takes the columns.
const ACCOUNT_SELECT: &str = "SELECT id, handle, login_hash, wrapped FROM accounts";

pub struct Account {
    pub id: i64,
    pub handle: String,
    pub login_hash: String,
    pub wrapped: String,
}

impl Store {
    /// An account as `ACCOUNT_SELECT` reads it.
    fn account_row(r: &Row<'_>) -> rusqlite::Result<Account> {
        Ok(Account { id: r.get(0)?, handle: r.get(1)?, login_hash: r.get(2)?, wrapped: r.get(3)? })
    }

    pub fn account_by_handle(&self, handle: &str) -> Option<Account> {
        self.one(&format!("{ACCOUNT_SELECT} WHERE handle = ?1"), params![handle], Self::account_row)
    }

    pub fn account_by_id(&self, id: i64) -> Option<Account> {
        self.one(&format!("{ACCOUNT_SELECT} WHERE id = ?1"), params![id], Self::account_row)
    }

    /// A new account with everything it starts with, in one transaction: a signup is all there or not there at all.
    pub fn create_account(
        &self,
        handle: &str,
        login_hash: &str,
        wrapped: &str,
        device: Option<(&str, &str)>,
        codes: &[(String, String)],
        now: i64,
    ) -> rusqlite::Result<Account> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO accounts (handle, login_hash, wrapped, created_at, seen_at) VALUES (?1, ?2, ?3, ?4, ?4)",
            params![handle, login_hash, wrapped, now],
        )?;
        let id = tx.last_insert_rowid();
        if let Some((key, label)) = device {
            tx.execute("INSERT INTO device_keys (account_id, public_key, label, created_at) VALUES (?1, ?2, ?3, ?4)", params![id, key, label, now])?;
        }
        Self::insert_codes(&tx, id, codes)?;
        tx.commit()?;
        Ok(Account { id, handle: handle.to_string(), login_hash: login_hash.to_string(), wrapped: wrapped.to_string() })
    }

    pub fn touch_seen(&self, id: i64, now: i64) {
        let _ = self.lock().execute("UPDATE accounts SET seen_at = ?2 WHERE id = ?1", params![id, now]);
    }

    /// A new password: a new login hash, and the account key wrapped under the new wrap key, together.
    pub fn set_password(&self, id: i64, login_hash: &str, wrapped: &str) -> rusqlite::Result<()> {
        self.lock().execute("UPDATE accounts SET login_hash = ?2, wrapped = ?3 WHERE id = ?1", params![id, login_hash, wrapped])?;
        Ok(())
    }

    /// An account and everything it keeps here, gone (Settings > Account > Delete account). The one row goes, and the
    /// tables that hang from it cascade: its devices, its recovery codes, its notes, its settings, its shares (so every
    /// link it made reads nothing from then on) and its recordings' rows. Then its recordings' files. Whether there was
    /// an account to delete.
    pub fn delete_account(&self, id: i64) -> rusqlite::Result<bool> {
        let gone = self.lock().execute("DELETE FROM accounts WHERE id = ?1", params![id])? > 0;
        let folder = self.recordings.join(id.to_string());
        if folder.exists() {
            std::fs::remove_dir_all(&folder).map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
        }
        Ok(gone)
    }

    // --- devices ----------------------------------------------------------------

    /// Another device for the account; a key it already has keeps its place and takes the new label.
    pub fn add_device_key(&self, id: i64, key: &str, label: &str, now: i64) -> rusqlite::Result<()> {
        self.lock().execute(
            "INSERT INTO device_keys (account_id, public_key, label, created_at) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(account_id, public_key) DO UPDATE SET label = excluded.label",
            params![id, key, label, now],
        )?;
        Ok(())
    }

    pub fn device_keys(&self, id: i64) -> Vec<String> {
        self.all("SELECT public_key FROM device_keys WHERE account_id = ?1", params![id], |r| r.get(0))
    }

    // --- recovery codes ---------------------------------------------------------

    /// A sheet's codes, each in the slot of its place on the sheet, inside a sign-up's transaction or a new sheet's.
    fn insert_codes(conn: &Connection, id: i64, codes: &[(String, String)]) -> rusqlite::Result<()> {
        for (slot, (hash, wrapped)) in codes.iter().enumerate() {
            conn.execute("INSERT INTO recovery_codes (account_id, slot, login_hash, wrapped) VALUES (?1, ?2, ?3, ?4)", params![id, slot as i64, hash, wrapped])?;
        }
        Ok(())
    }

    /// Spends the code whose login half hashes to `hash`, and answers the account key wrapped under it.
    pub fn use_recovery_code(&self, id: i64, hash: &str, now: i64) -> Option<String> {
        let conn = self.lock();
        let found: Option<(i64, String)> = conn
            .query_row(
                "SELECT slot, wrapped FROM recovery_codes WHERE account_id = ?1 AND login_hash = ?2 AND used_at IS NULL",
                params![id, hash],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .ok()
            .flatten();
        let (slot, wrapped) = found?;
        conn.execute("UPDATE recovery_codes SET used_at = ?3 WHERE account_id = ?1 AND slot = ?2", params![id, slot, now]).ok()?;
        Some(wrapped)
    }

    /// A fresh sheet of codes in place of the old one.
    pub fn replace_recovery_codes(&self, id: i64, codes: &[(String, String)]) -> rusqlite::Result<()> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        tx.execute("DELETE FROM recovery_codes WHERE account_id = ?1", params![id])?;
        Self::insert_codes(&tx, id, codes)?;
        tx.commit()
    }

    pub fn recovery_codes_left(&self, id: i64) -> i64 {
        self.lock()
            .query_row("SELECT COUNT(*) FROM recovery_codes WHERE account_id = ?1 AND used_at IS NULL", params![id], |r| r.get(0))
            .unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;

    #[test]
    fn a_signup_keeps_everything_it_came_with() {
        let (s, a, _dir) = fixture();
        let found = s.account_by_handle("MATT").expect("handles match without case");
        assert_eq!(found.id, a.id);
        assert_eq!(found.wrapped, "wrapped-key");
        assert_eq!(s.device_keys(a.id), vec!["device-key".to_string()]);
        assert_eq!(s.recovery_codes_left(a.id), 2);
        assert!(s.create_account("Matt", "", "", None, &[], 101).is_err(), "a handle is taken whatever its case");
    }

    #[test]
    fn a_recovery_code_answers_its_own_wrapped_key_once() {
        let (s, a, _dir) = fixture();
        assert_eq!(s.use_recovery_code(a.id, "hash-b", 200).as_deref(), Some("wrap-b"));
        assert_eq!(s.use_recovery_code(a.id, "hash-b", 201), None, "spent");
        assert_eq!(s.use_recovery_code(a.id, "nope", 202), None);
        assert_eq!(s.recovery_codes_left(a.id), 1);
    }

    #[test]
    fn a_new_sheet_replaces_every_code_spent_or_not() {
        let (s, a, _dir) = fixture();
        s.use_recovery_code(a.id, "hash-a", 200);
        let sheet = vec![("hash-c".to_string(), "wrap-c".to_string())];
        s.replace_recovery_codes(a.id, &sheet).unwrap();
        assert_eq!(s.recovery_codes_left(a.id), 1);
        assert_eq!(s.use_recovery_code(a.id, "hash-b", 201), None, "the old sheet's unspent code is gone with it");
        assert_eq!(s.use_recovery_code(a.id, "hash-c", 202).as_deref(), Some("wrap-c"));
    }

    #[test]
    fn a_new_password_replaces_the_hash_and_the_wrapped_key_together() {
        let (s, a, _dir) = fixture();
        s.set_password(a.id, "new-hash", "new-wrap").unwrap();
        let after = s.account_by_id(a.id).unwrap();
        assert_eq!((after.login_hash.as_str(), after.wrapped.as_str()), ("new-hash", "new-wrap"));
    }

    #[test]
    fn a_device_added_twice_is_one_device_with_its_first_date_and_its_new_label() {
        let (s, a, _dir) = fixture();
        s.add_device_key(a.id, "laptop-key", "laptop", 200).unwrap();
        s.add_device_key(a.id, "laptop-key", "the laptop, renamed", 201).unwrap();
        let mut keys = s.device_keys(a.id);
        keys.sort();
        assert_eq!(keys, vec!["device-key".to_string(), "laptop-key".to_string()]);
        // Nothing the service answers reads a label back yet, so the row itself is what shows it.
        let kept: (String, i64) = s
            .lock()
            .query_row("SELECT label, created_at FROM device_keys WHERE public_key = 'laptop-key'", [], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap();
        assert_eq!(kept, ("the laptop, renamed".to_string(), 200));
    }

    #[test]
    fn deleting_an_account_answers_whether_there_was_one_with_or_without_a_recordings_folder() {
        let (s, a, _dir) = fixture();
        assert_eq!(s.delete_account(a.id).ok(), Some(true), "no recording was ever kept, so there is no folder to remove");
        assert!(s.account_by_id(a.id).is_none());
        assert!(s.device_keys(a.id).is_empty() && s.recovery_codes_left(a.id) == 0, "its devices and codes cascade");
        assert_eq!(s.delete_account(a.id).ok(), Some(false), "a second delete finds nothing");
    }
}
