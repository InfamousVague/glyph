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
//! `store/prefs.rs`, `store/shares.rs`, `store/recordings.rs`, `store/orgs.rs` (organizations and who is in them),
//! `store/keys.rs` (encryption keys, organization keys and colours; docs/SHARED.md), `store/notifications.rs`
//! (what each account is told), `store/sites.rs` (published sites), `store/mail.rs` (email to a note), `store/hooks.rs` (incoming hooks) and `store/meet.rs` (Ghost
//! in a Google Meet: its bookings, and its recordings sealed as files beside the recordings) and `store/discord.rs` (Ghost in a
//! Discord call: which Discord user is which account, and the codes that link them; its tables are its own `SCHEMA`) -
//! each an `impl Store` of its own, so a caller still holds one `Store`.
//!
//! THE SCHEMA GROWS BY TABLES, AND BY COLUMNS ADDED. It is `CREATE TABLE IF NOT EXISTS`: a new table reaches the box on
//! the next start (shares did). A new column on a table that is already there does not, so it goes in the table's
//! CREATE (for a new database) and in `ADDED_COLUMNS` (an ALTER for one made before, run at every open, as
//! tauri/src-tauri/src/store.rs's `add_missing_columns`); the first was `meet_bookings.series`. Nor is there a
//! `busy_timeout`, which is safe only while the one `Mutex<Connection>` is the file's only writer.

mod accounts;
mod discord;
mod hooks;
mod keys;
mod mail;
mod meet;
mod notes;
mod org_notes;
mod notifications;
mod org_ais;
mod org_links;
mod orgs;
mod prefs;
mod recordings;
mod shares;
mod sites;

pub use accounts::DeleteAccount;
pub use discord::DISCORD_UID;
pub use hooks::{HookItem, HookRow, HookWrite};
pub use keys::{AccountKey, KeyWrite, OrgKeys, Wrap};
pub use notes::NoteRow;
pub use org_notes::{OrgNoteRow, OrgNoteWrite, UpdateRow, UPDATES_KEPT};
#[cfg(test)]
pub use notifications::KEPT;
pub use notifications::{NotificationRow, NotificationWrite, SERVER_KINDS};
pub use org_ais::OrgAi;
pub use org_links::{LinkPreview, OrgLink};
pub use orgs::{InviteCaps, Member, Org, OrgRow, OrgWrite, Role};
pub use mail::{MailClaim, MailStanding, MailWrite, SealedMail};
pub use meet::{MeetBooking, SERIES as MEET_SERIES};
pub use shares::ShareWrite;
pub use sites::SiteWrite;

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
-- An organization (server/src/orgs.rs, docs/TEAMS.md): its name and hue in the clear, as handles are, and who owns
-- it. It goes with its owner's account, which `delete_account` refuses while anyone else is in it.
CREATE TABLE IF NOT EXISTS orgs (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    hue        TEXT,
    owner_id   INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS orgs_by_owner ON orgs(owner_id);
-- Who is in an organization: a row per account, joined ('member'), asked ('invited'), or asked and refused
-- ('declined', kept for a day so the asking cannot be repeated at once). The row goes with the organization and with
-- the account; who invited them is only a reference, cleared if the inviter's account goes, so an inviter leaving
-- the service takes nobody with them.
CREATE TABLE IF NOT EXISTS org_members (
    org_id     TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    role       TEXT NOT NULL,
    state      TEXT NOT NULL,
    invited_by INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    since      INTEGER NOT NULL,
    PRIMARY KEY (org_id, account_id)
);
CREATE INDEX IF NOT EXISTS org_members_by_account ON org_members(account_id);
-- An invitation by link (server/src/orgs.rs, store/org_links.rs, docs/TEAMS.md): a code anyone holding it may join
-- the organization with, made by its owner or an admin, until it expires, is used up, or is turned off - which deletes
-- the row. `id` names it to the people who manage it; `code` is the secret in the link, 128 random bits, kept as it is
-- so a manager can copy the link again. It goes with the organization; its maker is only a reference.
CREATE TABLE IF NOT EXISTS org_links (
    id         TEXT PRIMARY KEY,
    code       TEXT NOT NULL UNIQUE,
    org_id     TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    made_by    INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER,
    max_uses   INTEGER,
    uses       INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS org_links_by_org ON org_links(org_id);
-- An AI that has read or written the organization's notes through a member's connector (store/org_ais.rs): its
-- name, the member, and when it was first and last seen. A record only: not a member, no key wrap, no seat. One per
-- member and name; it goes with the member's row in the organization, and so with the organization and the account.
CREATE TABLE IF NOT EXISTS org_ais (
    id         TEXT PRIMARY KEY,
    org_id     TEXT NOT NULL,
    account_id INTEGER NOT NULL,
    name       TEXT NOT NULL,
    first_seen INTEGER NOT NULL,
    last_seen  INTEGER NOT NULL,
    UNIQUE (org_id, account_id, name),
    FOREIGN KEY (org_id, account_id) REFERENCES org_members(org_id, account_id) ON DELETE CASCADE
);
-- An account's encryption key pair (docs/SHARED.md, S3; store/keys.rs): the public key in the clear, for a member
-- wrapping an organization key to it, and the private key sealed under the account key, for the account's other
-- devices. Written once: the first registration stands, and a second is answered with it.
CREATE TABLE IF NOT EXISTS account_keys (
    account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    pub        TEXT NOT NULL,
    sealed     TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
-- A person's colour (S7): the account's own, and an organization's override of it for that organization. In the
-- clear, as an organization's hue is; a colour is not a secret. A row is absent while none is chosen.
CREATE TABLE IF NOT EXISTS account_hues (
    account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    hue        TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS org_member_hues (
    org_id     TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    hue        TEXT NOT NULL,
    PRIMARY KEY (org_id, account_id)
);
-- The organization key (S2): which generation is in force, and the key wrapped for each member under their
-- encryption key pair. Ciphertext the service cannot open. Who made or wrapped it is only a reference.
CREATE TABLE IF NOT EXISTS org_key_state (
    org_id     TEXT PRIMARY KEY REFERENCES orgs(id) ON DELETE CASCADE,
    generation INTEGER NOT NULL,
    made_by    INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    made_at    INTEGER NOT NULL
);
-- A turn the key owes (S11): a member left or was removed, so the generation in force is stale until a member's
-- device makes the next one, which clears the rows. Nothing of who: the turn is the organization's.
CREATE TABLE IF NOT EXISTS org_key_turns (
    org_id TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    at     INTEGER NOT NULL
);
-- Team notes (docs/SHARED.md, S4; store/org_notes.rs): an organization's notes as ciphertext under its key, with the
-- organization's own write counter so a member's feed cursor is per organization, the CRDT's update log beside each
-- note (S5), and the organization's sealed files - a note's versions file, its pictures - as an account's recordings.
-- Who wrote a row is only a reference. All of it goes with the organization.
CREATE TABLE IF NOT EXISTS org_revs (
    org_id TEXT PRIMARY KEY REFERENCES orgs(id) ON DELETE CASCADE,
    rev    INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS org_notes (
    org_id     TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    id         TEXT NOT NULL,
    rev        INTEGER NOT NULL,
    deleted    INTEGER NOT NULL DEFAULT 0,
    blob       TEXT,
    by_id      INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (org_id, id)
);
CREATE INDEX IF NOT EXISTS org_notes_by_rev ON org_notes(org_id, rev);
CREATE TABLE IF NOT EXISTS org_note_updates (
    org_id  TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    note_id TEXT NOT NULL,
    seq     INTEGER NOT NULL,
    blob    TEXT NOT NULL,
    by_id   INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    at      INTEGER NOT NULL,
    PRIMARY KEY (org_id, note_id, seq)
);
CREATE TABLE IF NOT EXISTS org_files (
    org_id     TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    id         TEXT NOT NULL,
    rev        INTEGER NOT NULL,
    size       INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (org_id, id)
);
CREATE TABLE IF NOT EXISTS org_keys (
    org_id     TEXT NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    generation INTEGER NOT NULL,
    wrapped    TEXT NOT NULL,
    wrapped_by INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    wrapped_at INTEGER NOT NULL,
    PRIMARY KEY (org_id, account_id, generation)
);
-- What an account is told (server/src/notifications.rs): one table, two shapes. A row the service wrote - an
-- invitation, a team change - carries its kind, who caused it, the organization and a small plaintext body; a row a
-- device wrote about its own account carries a blob sealed under the account key, which the service cannot read.
-- Every row takes the account's write counter, as notes do, so a device reads them from the same kind of feed, and a
-- change to one (read, hidden, answered) takes a new value and is fed again. Keyed by account and id, as notes are,
-- so a device's repeat of a post it was not answered on finds its own row. `from_id` is cleared, not cascaded, when
-- the account that caused a row is deleted: the row is the reader's, not the cause's.
CREATE TABLE IF NOT EXISTS notifications (
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    id         TEXT NOT NULL,
    rev        INTEGER NOT NULL,
    kind       TEXT NOT NULL,
    from_id    INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    org_id     TEXT,
    body       TEXT,
    blob       TEXT,
    state      TEXT,
    created_at INTEGER NOT NULL,
    read_at    INTEGER,
    hidden     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (account_id, id)
);
CREATE INDEX IF NOT EXISTS notifications_by_rev ON notifications(account_id, rev);
CREATE INDEX IF NOT EXISTS notifications_by_org ON notifications(org_id, kind);
-- A note or a notebook published as a site (server/src/sites.rs, docs/SITES.md): ciphertext under a key only the site's
-- link carries, as a share's is, and `meta`, what the site is of and its link's key, sealed under the account key so
-- every device of the account can list its sites. Taken down with its owner's account.
CREATE TABLE IF NOT EXISTS sites (
    id         TEXT PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    blob       TEXT NOT NULL,
    meta       TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sites_by_owner ON sites(account_id);
-- Email to a note (server/src/mail.rs, docs/MAIL.md): an account's private address, its local part lower-cased, one an
-- account; and the mail sent to it, ONLY sealed - a key wrapped to the account's encryption public key, and the mail
-- as a note sealed under that key - waiting until a device of the account files it. Both go with the account.
CREATE TABLE IF NOT EXISTS mail_addresses (
    address    TEXT PRIMARY KEY,
    account_id INTEGER NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL
);
-- Every address an account gave up - a new one made in its place, a name of its own chosen, the address turned off,
-- the account deleted - kept by the trigger below, whichever way its row went, so that no address is ever given to a
-- second account: mail meant for one person must never reach another (Matt, 2026-10-24, a name of one's own). Its
-- local part and the account it was, which may take it back; `account_id` has no REFERENCES, so the row outlives a
-- deleted account, whose id AUTOINCREMENT never hands out again, and its addresses are then nobody's for good. Kept
-- since 2026-10-24: an address replaced before that was not, which is why a chosen name may not look made (names.rs).
CREATE TABLE IF NOT EXISTS mail_addresses_retired (
    address    TEXT PRIMARY KEY,
    account_id INTEGER NOT NULL,
    retired_at INTEGER NOT NULL
);
CREATE TRIGGER IF NOT EXISTS mail_address_retires AFTER DELETE ON mail_addresses
BEGIN
    INSERT OR REPLACE INTO mail_addresses_retired (address, account_id, retired_at) VALUES (OLD.address, OLD.account_id, CAST(strftime('%s', 'now') AS INTEGER));
END;
CREATE TABLE IF NOT EXISTS mail_in (
    id          TEXT PRIMARY KEY,
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    wrapped     TEXT NOT NULL,
    blob        TEXT NOT NULL,
    size        INTEGER NOT NULL,
    received_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS mail_in_by_account ON mail_in(account_id, received_at);
-- Incoming hooks (server/src/hooks.rs, docs/INTEGRATIONS.md): an account's hooks, each found by the SHA-256 of its
-- token (the token itself is never kept), with its name and default note in the clear; and what was posted to them,
-- ONLY sealed to the account's encryption public key, waiting until a device of the account adds it to its note, or
-- for thirty days. `seq` orders the inbox and is its cursor. Both go with the account; a post outlives its hook.
CREATE TABLE IF NOT EXISTS hooks (
    id           TEXT PRIMARY KEY,
    account_id   INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    token_hash   TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL,
    note         TEXT,
    created_at   INTEGER NOT NULL,
    last_used_at INTEGER
);
CREATE INDEX IF NOT EXISTS hooks_by_account ON hooks(account_id);
CREATE TABLE IF NOT EXISTS hook_inbox (
    seq         INTEGER PRIMARY KEY AUTOINCREMENT,
    id          TEXT NOT NULL UNIQUE,
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    hook_id     TEXT NOT NULL,
    sealed      TEXT NOT NULL,
    received_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS hook_inbox_by_account ON hook_inbox(account_id, seq);
CREATE INDEX IF NOT EXISTS hook_inbox_by_age ON hook_inbox(received_at);
-- Ghost in a Google Meet (server/src/meet.rs, docs/MEET.md; store/meet.rs). A booking: an invite mailed to the
-- account's mail address, or "join now" from a device. Its link, title and times are in the CLEAR, because the bot that
-- joins has no key, and only until the meeting is over: the hourly sweep blanks `title` and `url` an hour after
-- `ends_at` and deletes the row thirty days after. `starts_at` and `ends_at` are ms. A recurring meeting is a row of
-- its own with `series` (ADDED_COLUMNS) - what expanding it needs, as JSON - beside a row for each occurrence it has
-- booked; it keeps its link while occurrences are to come. `stopped` (ADDED_COLUMNS) is 1 on a series the person told
-- Ghost to stop joining from a device: its link and title are gone, and no invite books it again. A take: a recording and its
-- captions ONLY sealed to the account's encryption public key - the key `wrapped` here, the sealed bytes a file under
-- recordings/<account>/meet/ - until a device of the account takes it. Both go with the account.
CREATE TABLE IF NOT EXISTS meet_bookings (
    id         TEXT PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    uid        TEXT NOT NULL,
    url        TEXT NOT NULL,
    title      TEXT,
    starts_at  INTEGER NOT NULL,
    ends_at    INTEGER NOT NULL,
    state      TEXT NOT NULL,
    detail     TEXT,
    sequence   INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    series     TEXT,
    stopped    INTEGER NOT NULL DEFAULT 0,
    kind       TEXT,
    UNIQUE (account_id, uid)
);
CREATE INDEX IF NOT EXISTS meet_bookings_by_start ON meet_bookings(starts_at);
CREATE INDEX IF NOT EXISTS meet_bookings_by_end ON meet_bookings(ends_at);
CREATE TABLE IF NOT EXISTS meet_takes (
    id         TEXT PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    meeting    TEXT NOT NULL,
    wrapped    TEXT NOT NULL,
    size       INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS meet_takes_by_account ON meet_takes(account_id, created_at);
-- Which services an account wants Ghost booked into (meet.rs `MeetKinds`; Matt, 2026-10-26: "Make sure the Google Meet
-- and the Zoom plugins are two different plugins"): the app's plugin switches, as JSON (`{"meet":true,"zoom":false}`),
-- so a kind added later (Discord's calls) is a key and not a column. Not a secret: which kinds of link Ghost may join
-- says nothing of a meeting. No row is every kind on.
CREATE TABLE IF NOT EXISTS meet_kinds (
    account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    kinds      TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
"#;

/// Why a write made from a revision did not happen: the one stored had moved on, and `W` is what won - a note, the
/// settings (none when the base names settings never stored) or a recording's revision - or something below the
/// rules failed. Notes, settings and recordings all answer with it, and sync.rs turns `Stale` into a 409 carrying the
/// winner, so a device can merge and try again rather than guess what it collided with.
#[derive(Debug, PartialEq, Eq)]
pub enum WriteError<W> {
    Stale(W),
    Failed,
}

/// A query that failed is the write failing; which query, the device cannot act on.
impl<W> From<rusqlite::Error> for WriteError<W> {
    fn from(_: rusqlite::Error) -> Self {
        WriteError::Failed
    }
}

/// So is a recording's file that could not be written or put in place.
impl<W> From<std::io::Error> for WriteError<W> {
    fn from(_: std::io::Error) -> Self {
        WriteError::Failed
    }
}

/// The accounts database: one connection, and the folder recordings are kept in beside it.
pub struct Store {
    conn: Mutex<Connection>,
    recordings: PathBuf,
}

/// Columns added to a table after it first reached the box: `CREATE TABLE IF NOT EXISTS` makes them in a new
/// database (SCHEMA has each), and these add them to one made before. Each is (table, column, the ALTER).
///
/// - `meet_bookings.series`: a recurring meeting's rule, DTSTART and zone, length and skipped starts, as JSON
///   (`meet::ics::Series`), on the series' own row; NULL on every occurrence's and every other meeting's (2026-10-21).
/// - `meet_bookings.stopped`: 1 on a series' own row once a device has said "Stop joining" (`DELETE
///   /api/v1/meet/series/{id}`), so a later invite of the same series (a higher SEQUENCE) does not book it again; 0 on
///   every other row (2026-10-24).
/// - `meet_bookings.kind`: the service a booking is on, `meet` or `zoom` (`meet::ics::kind` of its link), kept when
///   the sweep blanks the link, so a meeting over still says which plugin's page it is listed on (Matt, 2026-10-26: "I
///   want settings / meetings to be broken up into three plugins"). NULL on a row blanked before the column was
///   there, which the device reads as Google Meet, the only kind there was until that same day (2026-10-26).
const ADDED_COLUMNS: &[(&str, &str, &str)] = &[
    ("meet_bookings", "series", "ALTER TABLE meet_bookings ADD COLUMN series TEXT"),
    ("meet_bookings", "stopped", "ALTER TABLE meet_bookings ADD COLUMN stopped INTEGER NOT NULL DEFAULT 0"),
    ("meet_bookings", "kind", "ALTER TABLE meet_bookings ADD COLUMN kind TEXT"),
];

/// Each booking with a link and no `kind` yet given the one its link says: those booked before the column was added.
/// Cheap at every open, since only those rows match.
const KIND_FROM_LINK: &str = "UPDATE meet_bookings SET kind = CASE
     WHEN url LIKE 'https://meet.google.com/%' THEN 'meet'
     WHEN url LIKE 'https://zoom.us/%' OR url LIKE 'https://%.zoom.us/%' THEN 'zoom'
   END
 WHERE kind IS NULL AND url != ''";

/// Each of ADDED_COLUMNS its table does not have yet, added. Two starts racing to add one: the second's "duplicate
/// column" is the column being there.
fn add_missing_columns(conn: &Connection) -> rusqlite::Result<()> {
    for (table, column, ddl) in ADDED_COLUMNS {
        let mut statement = conn.prepare(&format!("PRAGMA table_info({table})"))?;
        let present: Vec<String> = statement.query_map([], |row| row.get::<_, String>(1))?.collect::<rusqlite::Result<_>>()?;
        if present.iter().any(|p| p == column) {
            continue;
        }
        match conn.execute(ddl, []) {
            Ok(_) => {}
            Err(rusqlite::Error::SqliteFailure(_, Some(message))) if message.contains("duplicate column") => {}
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

/// What every connection is opened with, the file and the tests' in-memory one alike: the cascades on, the tables, and
/// the columns added since.
fn schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.execute_batch(SCHEMA)?;
    conn.execute_batch(discord::SCHEMA)?;
    add_missing_columns(conn)?;
    conn.execute(KIND_FROM_LINK, []).map(|_| ())
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

    /// The account's next revision, taken inside a write's transaction. One counter serves notes, settings,
    /// recordings and notifications alike, which is why the feed is `rev > since` rather than a count of notes.
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
    fn a_database_made_before_a_column_was_added_gets_it_at_the_next_open() {
        // meet_bookings as it first reached the box, with a booking in it.
        let dir = TempDir::new("store-columns");
        let data = dir.path().join("glyph-api");
        std::fs::create_dir_all(&data).unwrap();
        {
            let conn = Connection::open(data.join("glyph-accounts.sqlite3")).unwrap();
            conn.execute_batch(
                "CREATE TABLE meet_bookings (id TEXT PRIMARY KEY, account_id INTEGER NOT NULL, uid TEXT NOT NULL, url TEXT NOT NULL, title TEXT,
                 starts_at INTEGER NOT NULL, ends_at INTEGER NOT NULL, state TEXT NOT NULL, detail TEXT, sequence INTEGER NOT NULL DEFAULT 0,
                 created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE (account_id, uid));
                 INSERT INTO meet_bookings VALUES ('m', 1, 'u', 'https://meet.google.com/abc-defg-hij', 'Old', 1, 2, 'booked', NULL, 0, 1, 1);",
            )
            .unwrap();
        }
        let store = Store::open(&data).unwrap();
        let old = store.meet_booking("m").unwrap();
        assert_eq!((old.title.as_deref(), old.series), (Some("Old"), None), "what was there is kept, the new column empty");
        assert_eq!(old.kind.as_deref(), Some("meet"), "the kind read from the link it was booked with");
        store.update_meet_booking(&MeetBooking { series: Some("{}".into()), ..old }, 3).unwrap();
        drop(store);
        // And opened again, nothing is added twice.
        let again = Store::open(&data).unwrap();
        assert_eq!(again.meet_booking("m").unwrap().series.as_deref(), Some("{}"));
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

