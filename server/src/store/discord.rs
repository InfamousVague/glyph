//! Ghost in a Discord call (src/discord.rs, docs/DISCORD_CALLS.md): which Discord user speaks for which account, the
//! short codes a device makes to link one, and the bookings a Discord call is kept as.
//!
//! A LINK is one Discord user and one account, both ways: a Discord user is linked to one account at most (linked
//! again with another account's code, the link moves there), and an account to one Discord user (a new Discord user
//! linked to it takes the old one's place). It keeps the Discord user's id (a snowflake, digits) and the name they
//! had when they linked, in the CLEAR: the bot reads the id on every `/ghost join` and has no key, and the device
//! shows the name. Revoked by the device (`DELETE /api/v1/discord/link`) and gone with the account. And `calls`, the
//! Discord plugin's "Join Discord calls" switch (Matt, 2026-10-26: Discord calls belong to the Discord plugin): on
//! when linked, and while it is off the bot answers `/ghost join` with where to turn it on. Kept on the link, as the
//! bot must read it and has no key; a new link starts on.
//!
//! A CODE is what a device shows for `/ghost link <code>`: only its SHA-256 is kept, with the account and when it
//! lapses (ten minutes on). One an account at a time; a new one replaces it, a used one is deleted, and those lapsed
//! are deleted whenever a code is made or redeemed.
//!
//! A DISCORD CALL is a booking in `meet_bookings` like any meeting (store/meet.rs), uid `discord:<its id>`, its url
//! the voice channel's (`https://discord.com/channels/<guild>/<channel>`), so it is listed, skipped, swept and given
//! its take as a Meet is, and the Meet bot's `due` passes it over (`meet_due`: the Meet bot would refuse its link).

use super::Store;
use super::MeetBooking;
use rusqlite::params;

/// The tables, made beside store.rs's own at every open (`schema`).
pub(super) const SCHEMA: &str = r#"
-- Ghost in a Discord call (server/src/discord.rs, docs/DISCORD_CALLS.md; store/discord.rs). A Discord user linked to an
-- account: the user's id and the name they had, in the clear (the bot has no key), one each way. And a link code a
-- device made, ONLY its SHA-256, until it lapses ten minutes on or is used. Both go with the account.
CREATE TABLE IF NOT EXISTS discord_links (
    discord_user TEXT PRIMARY KEY,
    account_id   INTEGER NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    linked_at    INTEGER NOT NULL,
    calls        INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS discord_link_codes (
    code_hash  TEXT PRIMARY KEY,
    account_id INTEGER NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
    expires_at INTEGER NOT NULL
);
"#;

/// A Discord call's booking uid starts with this: what tells one from a Meet's (`meet_due` passes it over).
pub const DISCORD_UID: &str = "discord:";

/// A link as the routes read one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscordLink {
    pub discord_user: String,
    pub account: i64,
    pub name: String,
    /// Seconds, as every table's moments are.
    pub linked_at: i64,
    /// Whether Ghost joins this person's Discord calls: the plugin's switch.
    pub calls: bool,
}

fn link(r: &rusqlite::Row<'_>) -> rusqlite::Result<DiscordLink> {
    Ok(DiscordLink { discord_user: r.get(0)?, account: r.get(1)?, name: r.get(2)?, linked_at: r.get(3)?, calls: r.get::<_, i64>(4)? != 0 })
}

const BOOKING_COLUMNS: &str = "id, account_id, uid, url, title, starts_at, ends_at, state, detail, sequence, series";

fn booking(r: &rusqlite::Row<'_>) -> rusqlite::Result<MeetBooking> {
    Ok(MeetBooking {
        id: r.get(0)?,
        account: r.get(1)?,
        uid: r.get(2)?,
        url: r.get(3)?,
        title: r.get(4)?,
        starts_at: r.get(5)?,
        ends_at: r.get(6)?,
        state: r.get(7)?,
        detail: r.get(8)?,
        sequence: r.get(9)?,
        series: r.get(10)?,
    })
}

impl Store {
    // --- codes -----------------------------------------------------------------------------------

    /// A new code for `account`, kept as `hash` until `expires_at` (seconds), in place of any it had; lapsed ones go.
    pub fn put_discord_code(&self, account: i64, hash: &str, expires_at: i64, now: i64) -> rusqlite::Result<()> {
        let conn = self.lock();
        conn.execute("DELETE FROM discord_link_codes WHERE expires_at <= ?1 OR account_id = ?2", params![now, account])?;
        conn.execute("INSERT INTO discord_link_codes (code_hash, account_id, expires_at) VALUES (?1, ?2, ?3)", params![hash, account, expires_at])?;
        Ok(())
    }

    /// The code `hash` used at `now` (seconds): its account if it was one and had not lapsed, and the code gone either
    /// way (a code is good once). Lapsed ones go too.
    pub fn take_discord_code(&self, hash: &str, now: i64) -> Option<i64> {
        let conn = self.lock();
        let account = conn
            .query_row("SELECT account_id FROM discord_link_codes WHERE code_hash = ?1 AND expires_at > ?2", params![hash, now], |r| r.get::<_, i64>(0))
            .ok();
        let _ = conn.execute("DELETE FROM discord_link_codes WHERE code_hash = ?1 OR expires_at <= ?2", params![hash, now]);
        account
    }

    /// Whether `account` has a code that has not lapsed at `now` (seconds).
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn discord_code_waiting(&self, account: i64, now: i64) -> bool {
        self.one("SELECT 1 FROM discord_link_codes WHERE account_id = ?1 AND expires_at > ?2", params![account, now], |r| r.get::<_, i64>(0)).is_some()
    }

    // --- links -----------------------------------------------------------------------------------

    /// `discord_user` linked to `account` as `name`: any link either had before is let go first, so each is linked
    /// once (see the header).
    pub fn link_discord(&self, discord_user: &str, account: i64, name: &str, now: i64) -> rusqlite::Result<()> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        tx.execute("DELETE FROM discord_links WHERE discord_user = ?1 OR account_id = ?2", params![discord_user, account])?;
        tx.execute("INSERT INTO discord_links (discord_user, account_id, name, linked_at) VALUES (?1, ?2, ?3, ?4)", params![discord_user, account, name, now])?;
        tx.commit()
    }

    /// The link of a Discord user, as the bot asks on `/ghost join`.
    pub fn discord_link_of_user(&self, discord_user: &str) -> Option<DiscordLink> {
        self.one(
            "SELECT discord_user, account_id, name, linked_at, calls FROM discord_links WHERE discord_user = ?1",
            params![discord_user],
            link,
        )
    }

    /// The account's link, as its device shows it.
    pub fn discord_link_of_account(&self, account: i64) -> Option<DiscordLink> {
        self.one(
            "SELECT discord_user, account_id, name, linked_at, calls FROM discord_links WHERE account_id = ?1",
            params![account],
            link,
        )
    }

    /// The account's "Join Discord calls" switch set. Answers whether the account has a link to set it on.
    pub fn set_discord_calls(&self, account: i64, on: bool) -> bool {
        self.lock().execute("UPDATE discord_links SET calls = ?2 WHERE account_id = ?1", params![account, on as i64]).map(|n| n > 0).unwrap_or(false)
    }

    /// The account's link let go, and any code it was waiting on. Answers whether there was a link.
    pub fn unlink_discord(&self, account: i64) -> bool {
        let conn = self.lock();
        let _ = conn.execute("DELETE FROM discord_link_codes WHERE account_id = ?1", params![account]);
        conn.execute("DELETE FROM discord_links WHERE account_id = ?1", params![account]).map(|n| n > 0).unwrap_or(false)
    }

    // --- calls -----------------------------------------------------------------------------------

    /// The Discord calls the bot is on its way into, in, or told to leave, of every account, oldest first: what it
    /// polls to hear a device's "Leave now", and to find, after a restart, the calls it can no longer finish.
    pub fn discord_due(&self, now: i64) -> Vec<MeetBooking> {
        self.all(
            &format!(
                "SELECT {BOOKING_COLUMNS} FROM meet_bookings WHERE substr(uid, 1, length(?2)) = ?2 AND state IN ('booked', 'joining', 'in_call', 'leave') AND ends_at > ?1 ORDER BY starts_at, id"
            ),
            params![now, DISCORD_UID],
            booking,
        )
    }

    /// A Discord call's end moved to `at` (ms), never before its start nor after the end it had: the call is over, and
    /// its row should say when (it was booked for the most a call may last).
    pub fn end_discord_call(&self, id: &str, at: i64, now: i64) -> bool {
        self.lock()
            .execute(
                "UPDATE meet_bookings SET ends_at = MAX(starts_at, MIN(ends_at, ?2)), updated_at = ?3 WHERE id = ?1 AND substr(uid, 1, length(?4)) = ?4",
                params![id, at, now, DISCORD_UID],
            )
            .map(|n| n > 0)
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;

    #[test]
    fn a_code_is_good_once_and_only_until_it_lapses() {
        let (s, a, _dir) = fixture();
        s.put_discord_code(a.id, "h1", 600, 0).unwrap();
        assert!(s.discord_code_waiting(a.id, 1));
        assert_eq!(s.take_discord_code("h1", 599), Some(a.id));
        assert_eq!(s.take_discord_code("h1", 599), None, "used once");
        s.put_discord_code(a.id, "h2", 600, 0).unwrap();
        assert_eq!(s.take_discord_code("h2", 600), None, "lapsed at its end");
        assert!(!s.discord_code_waiting(a.id, 1), "and deleted");
        // A new one replaces the one waiting.
        s.put_discord_code(a.id, "h3", 600, 0).unwrap();
        s.put_discord_code(a.id, "h4", 600, 0).unwrap();
        assert_eq!(s.take_discord_code("h3", 1), None);
        assert_eq!(s.take_discord_code("h4", 1), Some(a.id));
    }

    #[test]
    fn a_link_is_one_each_way_and_goes_with_the_account() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        s.link_discord("111111111111111111", a.id, "matt", 5).unwrap();
        assert_eq!(s.discord_link_of_user("111111111111111111").map(|l| l.account), Some(a.id));
        // The same Discord user linked to another account: moved there.
        s.link_discord("111111111111111111", b.id, "matt", 6).unwrap();
        assert_eq!(s.discord_link_of_account(a.id), None);
        assert_eq!(s.discord_link_of_account(b.id).map(|l| l.name), Some("matt".into()));
        // A new Discord user linked to that account: takes the old one's place.
        s.link_discord("222222222222222222", b.id, "sam", 7).unwrap();
        assert_eq!(s.discord_link_of_user("111111111111111111"), None);
        assert!(s.discord_link_of_account(b.id).unwrap().calls, "a new link joins calls");
        assert!(s.set_discord_calls(b.id, false));
        assert!(!s.discord_link_of_user("222222222222222222").unwrap().calls);
        assert!(!s.set_discord_calls(a.id, true), "no link to set it on");
        assert!(s.unlink_discord(b.id));
        assert!(!s.unlink_discord(b.id));
        s.link_discord("333333333333333333", a.id, "matt", 8).unwrap();
        s.put_discord_code(a.id, "h", 600, 0).unwrap();
        s.delete_account(a.id, 9).unwrap();
        assert_eq!(s.discord_link_of_user("333333333333333333"), None);
        assert!(!s.discord_code_waiting(a.id, 1));
    }
}
