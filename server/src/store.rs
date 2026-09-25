//! The accounts database: who has an account, the keys that speak for them, and the encrypted copies of what they
//! keep in sync (docs/SYNC.md).
//!
//! One SQLite file, as AttackFM's registry keeps one (`AttackFM/server/crates/registry/src/db.rs`), with the signing
//! key in it, so the accounts and the key that vouches for them are one file and one backup. Recordings and pictures
//! are the one thing not in it: they are files beside it, because they are megabytes each.
//!
//! Nothing in here can be read by this service. A note, a settings blob, a recording and the account key are all
//! ciphertext made on a device; the service stores them, counts them, and hands them back.
//!
//! This file owns the schema, the one connection, and what every query goes through. Each table's queries are in the
//! file named for what they keep - `store/accounts.rs` (accounts, their devices and recovery codes), `store/notes.rs`,
//! `store/prefs.rs`, `store/shares.rs` and `store/recordings.rs` - each an `impl Store` of its own, so a caller still
//! holds one `Store`.
//!
//! THE SCHEMA ONLY GROWS BY TABLES. It is `CREATE TABLE IF NOT EXISTS` and nothing else: a new table reaches the box on
//! the next start (shares did), and a new column on a table that is already there does not. The first column added
//! needs an ALTER path, as src-tauri/src/store.rs's `add_missing_columns` has. Nor is there a `busy_timeout`, which is
//! safe only while the one `Mutex<Connection>` is the file's only writer.

mod accounts;
mod notes;
mod prefs;
mod recordings;
mod shares;

pub use notes::{NoteRow, WriteError};
pub use shares::ShareWrite;

use rusqlite::{params, Connection, OptionalExtension, Params, Row};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS accounts (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    handle     TEXT NOT NULL UNIQUE COLLATE NOCASE,
    -- Argon2 of the login secret a device derives from the password; empty for a device-key-only account.
    login_hash TEXT NOT NULL DEFAULT '',
    -- The account key, wrapped under the password's wrap key. Ciphertext; empty with no password.
    wrapped    TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    seen_at    INTEGER NOT NULL DEFAULT 0,
    -- The account's write counter: every note, settings or recording write takes the next value.
    rev        INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS device_keys (
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    public_key TEXT NOT NULL,
    label      TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (account_id, public_key)
);
CREATE TABLE IF NOT EXISTS recovery_codes (
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    slot       INTEGER NOT NULL,
    -- SHA-256 of the code's login half. The code itself, and its wrap half, never reach the service.
    login_hash TEXT NOT NULL,
    -- The account key wrapped under this code's wrap key.
    wrapped    TEXT NOT NULL,
    used_at    INTEGER,
    PRIMARY KEY (account_id, slot)
);
CREATE TABLE IF NOT EXISTS notes (
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    id         TEXT NOT NULL,
    rev        INTEGER NOT NULL,
    deleted    INTEGER NOT NULL DEFAULT 0,
    blob       TEXT,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (account_id, id)
);
CREATE INDEX IF NOT EXISTS notes_by_rev ON notes(account_id, rev);
CREATE TABLE IF NOT EXISTS prefs (
    account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    rev        INTEGER NOT NULL,
    blob       TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
-- A note or a book shared by its link (server/src/shares.rs): the owner, and ciphertext sealed under a key only the
-- link carries. Taken down with its owner's account.
CREATE TABLE IF NOT EXISTS shares (
    id         TEXT PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    blob       TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS shares_by_owner ON shares(account_id);
CREATE TABLE IF NOT EXISTS recordings (
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    id         TEXT NOT NULL,
    rev        INTEGER NOT NULL,
    size       INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (account_id, id)
);
"#;

/// The accounts database: one connection, and the folder recordings are kept in beside it.
pub struct Store {
    conn: Mutex<Connection>,
    recordings: PathBuf,
}

/// What every connection is opened with, the file and the tests' in-memory one alike: the cascades on, and the tables.
fn schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.execute_batch(SCHEMA)
}

impl Store {
    /// Opens the database in `dir`, making it on first use, with the recordings folder beside it.
    pub fn open(dir: &Path) -> rusqlite::Result<Self> {
        std::fs::create_dir_all(dir).map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
        let conn = Connection::open(dir.join("glyph-accounts.sqlite3"))?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        schema(&conn)?;
        Ok(Self { conn: Mutex::new(conn), recordings: dir.join("recordings") })
    }

    /// A database in memory, with recordings in a fresh folder: for the tests.
    #[cfg(test)]
    pub fn in_memory(recordings: PathBuf) -> Self {
        let conn = Connection::open_in_memory().unwrap();
        schema(&conn).unwrap();
        Self { conn: Mutex::new(conn), recordings }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        // A panic while the lock was held leaves the connection as it was; SQLite's own transactions kept it whole.
        self.conn.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// The one row `sql` finds, or `None` for no row and for a query that failed alike: the reads that answer `Option`
    /// have never told the two apart, and this keeps it so.
    fn one<T>(&self, sql: &str, params: impl Params, map: impl FnOnce(&Row<'_>) -> rusqlite::Result<T>) -> Option<T> {
        self.lock().query_row(sql, params, map).optional().ok().flatten()
    }

    /// Every row `sql` finds, skipping any that will not read; empty when the query fails.
    fn all<T>(&self, sql: &str, params: impl Params, map: impl FnMut(&Row<'_>) -> rusqlite::Result<T>) -> Vec<T> {
        let conn = self.lock();
        let Ok(mut statement) = conn.prepare(sql) else {
            return Vec::new();
        };
        statement.query_map(params, map).map(|rows| rows.filter_map(Result::ok).collect()).unwrap_or_default()
    }

    // --- meta -------------------------------------------------------------------

    pub fn meta(&self, key: &str) -> Option<String> {
        self.one("SELECT value FROM meta WHERE key = ?1", params![key], |r| r.get(0))
    }

    pub fn set_meta(&self, key: &str, value: &str) -> rusqlite::Result<()> {
        self.lock().execute("INSERT INTO meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value", params![key, value])?;
        Ok(())
    }

    // --- the write counter ------------------------------------------------------

    /// The account's next revision, taken inside a write's transaction. One counter serves notes, settings and
    /// recordings alike, which is why the feed is `rev > since` rather than a count of notes.
    fn next_rev(tx: &rusqlite::Transaction<'_>, account: i64) -> rusqlite::Result<i64> {
        tx.execute("UPDATE accounts SET rev = rev + 1 WHERE id = ?1", params![account])?;
        tx.query_row("SELECT rev FROM accounts WHERE id = ?1", params![account], |r| r.get(0))
    }
}

/// What each table's tests start from: a store in memory over a fresh folder, and one account in it with a device
/// and two recovery codes.
#[cfg(test)]
fn fixture() -> (Store, accounts::Account, crate::test_support::TempDir) {
    let dir = crate::test_support::TempDir::new("store");
    let store = Store::in_memory(dir.path().join("recordings"));
    let codes = vec![("hash-a".to_string(), "wrap-a".to_string()), ("hash-b".to_string(), "wrap-b".to_string())];
    let account = store.create_account("matt", "login-hash", "wrapped-key", Some(("device-key", "phone")), &codes, 100).unwrap();
    (store, account, dir)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn a_database_on_disk_keeps_what_it_was_given_across_a_reopen() {
        // What the box's restarts depend on: the signing key is a meta row, and the accounts are rows beside it.
        let dir = TempDir::new("store-open");
        let data = dir.path().join("glyph-api");
        {
            let store = Store::open(&data).unwrap();
            store.set_meta("issuer_secret_b64", "the key").unwrap();
            store.create_account("matt", "", "", Some(("device-key", "phone")), &[], 1).unwrap();
        }
        assert!(data.join("glyph-accounts.sqlite3").exists(), "made, with the folder it is in, on first use");
        let reopened = Store::open(&data).unwrap();
        assert_eq!(reopened.meta("issuer_secret_b64").as_deref(), Some("the key"));
        assert_eq!(reopened.account_by_handle("matt").map(|a| a.id), Some(1));
        let mode: String = reopened.lock().query_row("PRAGMA journal_mode", [], |r| r.get(0)).unwrap();
        assert_eq!(mode, "wal");
        let cascades: i64 = reopened.lock().query_row("PRAGMA foreign_keys", [], |r| r.get(0)).unwrap();
        assert_eq!(cascades, 1, "a connection without foreign keys would leave a deleted account's shares readable");
    }

    #[test]
    fn a_meta_key_is_written_over_not_added_to() {
        let (s, _, _dir) = fixture();
        assert_eq!(s.meta("k"), None);
        s.set_meta("k", "one").unwrap();
        s.set_meta("k", "two").unwrap();
        assert_eq!(s.meta("k").as_deref(), Some("two"));
    }
}

