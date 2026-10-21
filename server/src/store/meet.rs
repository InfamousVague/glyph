//! Ghost in a Google Meet (src/meet.rs, docs/MEET.md): the meetings an account has booked Ghost into, and the
//! recordings it brought back, sealed.
//!
//! A booking keeps what the bot needs to join - the Meet link, the title it shows, when - in the CLEAR, because the bot
//! has to read them and has no key. Only until the meeting is over: the hourly sweep (`sweep_meet`) blanks a booking's
//! title and link an hour after it ended and deletes it after thirty days. Times are in milliseconds, as the app keeps
//! every moment; `created_at` and `updated_at` are seconds, as every other table's are.
//!
//! A recurring meeting is two kinds of row. The SERIES' own (uid `<UID>`, `series` set: what expanding it needs) is
//! never due, listed or counted; its `starts_at` and `ends_at` are the latest occurrence it booked, as the rule makes
//! it, and it keeps the link and the title while it is `series` (occurrences to come), for each occurrence it books.
//! Each OCCURRENCE is a booking like any other (uid `<UID>#<its start as the rule makes it, ms>`, the uid a changed
//! occurrence's RECURRENCE-ID gives it too), with its own id, state and takes, and is swept like any other.
//!
//! A take is kept ONLY sealed: its key wrapped to the account's encryption public key (`wrapped`), and the recording
//! with its captions sealed under that key, as a file under `<data>/recordings/<account id>/meet/<take id>.take`
//! beside the account's recordings (megabytes, so not a column), which goes with the account's folder. A take waits
//! until one of the account's devices has opened it and deletes it. A take names its booking but does not depend on
//! it: the booking is swept after thirty days, and the recording is the person's until a device takes it.

use super::Store;
use rusqlite::{params, OptionalExtension, Row};
use std::io::Write;
use std::path::PathBuf;

/// A booking as the routes read and write one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeetBooking {
    pub id: String,
    pub account: i64,
    /// The invite's UID (`<UID>#<RECURRENCE-ID ms>` for one changed occurrence), or `now:<id>` for "join now".
    pub uid: String,
    /// The Meet link; empty once the sweep has blanked it.
    pub url: String,
    pub title: Option<String>,
    pub starts_at: i64,
    pub ends_at: i64,
    pub state: String,
    pub detail: Option<String>,
    pub sequence: i64,
    /// A series' own row: its `meet::ics::Series`, as JSON. None for an occurrence, and for every other booking.
    pub series: Option<String>,
}

/// A take as a device lists it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeetTake {
    pub id: String,
    pub meeting: String,
    pub wrapped: String,
    pub size: i64,
    pub at: i64,
}

const BOOKING_COLUMNS: &str = "id, account_id, uid, url, title, starts_at, ends_at, state, detail, sequence, series";

fn booking(r: &Row<'_>) -> rusqlite::Result<MeetBooking> {
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

/// The states a booking is still live in: the bot may yet join it, or is in it.
const LIVE: &str = "('booked', 'joining', 'in_call', 'leave')";
/// A series' own row while occurrences are to come: kept whole by the sweep.
pub const SERIES: &str = "series";

impl Store {
    // --- bookings --------------------------------------------------------------------------------

    /// A new booking; none if the account already has one for that UID (two copies of one invite at once).
    pub fn insert_meet_booking(&self, b: &MeetBooking, now: i64) -> rusqlite::Result<bool> {
        let n = self.lock().execute(
            "INSERT OR IGNORE INTO meet_bookings (id, account_id, uid, url, title, starts_at, ends_at, state, detail, sequence, series, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?12)",
            params![b.id, b.account, b.uid, b.url, b.title, b.starts_at, b.ends_at, b.state, b.detail, b.sequence, b.series, now],
        )?;
        Ok(n > 0)
    }

    /// A booking written over with `b`'s link, title, times, state, detail, sequence and series (its id, account and UID
    /// stay).
    pub fn update_meet_booking(&self, b: &MeetBooking, now: i64) -> rusqlite::Result<()> {
        self.lock().execute(
            "UPDATE meet_bookings SET url = ?3, title = ?4, starts_at = ?5, ends_at = ?6, state = ?7, detail = ?8, sequence = ?9, series = ?10, updated_at = ?11
             WHERE id = ?1 AND account_id = ?2",
            params![b.id, b.account, b.url, b.title, b.starts_at, b.ends_at, b.state, b.detail, b.sequence, b.series, now],
        )?;
        Ok(())
    }

    /// Only a booking's UID: a v1 booking of one occurrence of a series, which had the series' UID, made that
    /// occurrence's (`<UID>#<start ms>`) when the series is booked whole. False if the account has that UID already.
    pub fn set_meet_uid(&self, id: &str, uid: &str, now: i64) -> bool {
        self.lock().execute("UPDATE meet_bookings SET uid = ?2, updated_at = ?3 WHERE id = ?1", params![id, uid, now]).map(|n| n > 0).unwrap_or(false)
    }

    /// A booking gone: an occurrence a series' update took away before it began, so never joined and with no take.
    pub fn delete_meet_booking(&self, id: &str) -> bool {
        self.lock().execute("DELETE FROM meet_bookings WHERE id = ?1", params![id]).map(|n| n > 0).unwrap_or(false)
    }

    /// Only a booking's state and detail, as the bot or a device moves it on.
    pub fn set_meet_state(&self, id: &str, state: &str, detail: Option<&str>, now: i64) -> bool {
        self.lock()
            .execute("UPDATE meet_bookings SET state = ?2, detail = ?3, updated_at = ?4 WHERE id = ?1", params![id, state, detail, now])
            .map(|n| n > 0)
            .unwrap_or(false)
    }

    /// The account's booking for an invite's UID.
    pub fn meet_booking_by_uid(&self, account: i64, uid: &str) -> Option<MeetBooking> {
        self.one(&format!("SELECT {BOOKING_COLUMNS} FROM meet_bookings WHERE account_id = ?1 AND uid = ?2"), params![account, uid], booking)
    }

    /// A booking by its id, whosever it is: the bot's routes, which act for the service, not for an account.
    pub fn meet_booking(&self, id: &str) -> Option<MeetBooking> {
        self.one(&format!("SELECT {BOOKING_COLUMNS} FROM meet_bookings WHERE id = ?1"), params![id], booking)
    }

    /// The account's bookings of the occurrences of the series `uid`, soonest first.
    pub fn meet_occurrences(&self, account: i64, uid: &str) -> Vec<MeetBooking> {
        let prefix = format!("{uid}#");
        self.all(
            &format!("SELECT {BOOKING_COLUMNS} FROM meet_bookings WHERE account_id = ?1 AND substr(uid, 1, length(?2)) = ?2 ORDER BY starts_at, id"),
            params![account, prefix],
            booking,
        )
    }

    /// The series, of every account, that may have an occurrence to book at `now` (ms): running, and the occurrence
    /// they booked last is over (its end as the rule made it has passed) or is not live (done, failed, skipped, called
    /// off, or never booked).
    pub fn meet_series_to_advance(&self, now: i64) -> Vec<MeetBooking> {
        self.all(
            &format!(
                "SELECT {BOOKING_COLUMNS} FROM meet_bookings s WHERE s.state = '{SERIES}' AND s.series IS NOT NULL AND (s.ends_at <= ?1 OR NOT EXISTS (
                     SELECT 1 FROM meet_bookings o WHERE o.account_id = s.account_id AND o.uid = s.uid || '#' || s.starts_at AND o.state IN {LIVE}))
                 ORDER BY s.starts_at, s.id"
            ),
            params![now],
            booking,
        )
    }

    /// The account's bookings that end at `since` (ms) or later, soonest first; a series' own row is not one.
    pub fn meet_bookings(&self, account: i64, since: i64) -> Vec<MeetBooking> {
        self.all(
            &format!("SELECT {BOOKING_COLUMNS} FROM meet_bookings WHERE account_id = ?1 AND ends_at >= ?2 AND series IS NULL ORDER BY starts_at, id"),
            params![account, since],
            booking,
        )
    }

    /// How many of the account's bookings are live and not over at `now` (ms).
    pub fn meet_upcoming(&self, account: i64, now: i64) -> i64 {
        self.one(&format!("SELECT COUNT(*) FROM meet_bookings WHERE account_id = ?1 AND ends_at > ?2 AND state IN {LIVE} AND series IS NULL"), params![account, now], |r| r.get(0))
            .unwrap_or(0)
    }

    /// The bookings the bot should be in, or on its way to, at `now` (ms): live, with a link, from `early` ms before
    /// each starts until `late` ms after it ends. Oldest first, of every account.
    pub fn meet_due(&self, now: i64, early: i64, late: i64) -> Vec<MeetBooking> {
        self.all(
            &format!("SELECT {BOOKING_COLUMNS} FROM meet_bookings WHERE state IN {LIVE} AND series IS NULL AND url != '' AND starts_at - ?2 <= ?1 AND ?1 < ends_at + ?3 ORDER BY starts_at, id"),
            params![now, early, late],
            booking,
        )
    }

    /// The hourly sweep's part for meetings, at `now` (ms): a live booking whose meeting ended `clear_for` ago or
    /// longer has missed its bot and is `failed`; such a booking, of any state, has its title and link blanked; and
    /// one that ended `kept_for` ago or longer is deleted. A series' own row is left whole while it is `series`
    /// (meet.rs moves it on first): only once it is over or called off is it blanked and deleted, by its last
    /// occurrence's end. Answers how many were blanked and how many deleted.
    pub fn sweep_meet(&self, now: i64, clear_for: i64, kept_for: i64) -> (usize, usize) {
        let mut conn = self.lock();
        let Ok(tx) = conn.transaction() else { return (0, 0) };
        let over = now - clear_for;
        let swept = (|| -> rusqlite::Result<(usize, usize)> {
            tx.execute(&format!("UPDATE meet_bookings SET state = 'failed', detail = 'missed' WHERE state IN {LIVE} AND ends_at <= ?1"), params![over])?;
            let blanked = tx.execute("UPDATE meet_bookings SET title = NULL, url = '' WHERE ends_at <= ?1 AND state != ?2 AND (title IS NOT NULL OR url != '')", params![over, SERIES])?;
            let deleted = tx.execute("DELETE FROM meet_bookings WHERE ends_at <= ?1 AND state != ?2", params![now - kept_for, SERIES])?;
            Ok((blanked, deleted))
        })();
        match swept {
            Ok(counts) => tx.commit().map(|_| counts).unwrap_or((0, 0)),
            Err(_) => (0, 0),
        }
    }

    // --- takes -----------------------------------------------------------------------------------

    fn meet_take_path(&self, account: i64, id: &str) -> PathBuf {
        self.recordings.join(account.to_string()).join("meet").join(format!("{id}.take"))
    }

    /// Keeps a sealed take: `parts` written one after another to a side file, the row inserted, and the file renamed into place
    /// before the row is committed, so a reader never finds half a take. `id` is the service's own (`fresh_id`).
    pub fn put_meet_take(&self, account: i64, id: &str, meeting: &str, wrapped: &str, parts: &[&[u8]], now: i64) -> Result<i64, ()> {
        let path = self.meet_take_path(account, id);
        let dir = path.parent().ok_or(())?.to_path_buf();
        std::fs::create_dir_all(&dir).map_err(|_| ())?;
        let part = dir.join(format!("{id}.{:016x}.part", rand::random::<u64>()));
        let size = parts.iter().map(|p| p.len()).sum::<usize>() as i64;
        let written = (|| -> std::io::Result<()> {
            let mut file = std::fs::File::create(&part)?;
            for bytes in parts {
                file.write_all(bytes)?;
            }
            file.sync_all()
        })();
        let placed = written.map_err(|_| ()).and_then(|_| {
            let mut conn = self.lock();
            let tx = conn.transaction().map_err(|_| ())?;
            tx.execute(
                "INSERT INTO meet_takes (id, account_id, meeting, wrapped, size, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![id, account, meeting, wrapped, size, now],
            )
            .map_err(|_| ())?;
            std::fs::rename(&part, &path).map_err(|_| ())?;
            tx.commit().map_err(|_| ())
        });
        if placed.is_err() {
            let _ = std::fs::remove_file(&part);
        }
        placed.map(|_| size)
    }

    /// The account's takes waiting, oldest first.
    pub fn meet_takes(&self, account: i64) -> Vec<MeetTake> {
        self.all(
            "SELECT id, meeting, wrapped, size, created_at FROM meet_takes WHERE account_id = ?1 ORDER BY created_at, id",
            params![account],
            |r| Ok(MeetTake { id: r.get(0)?, meeting: r.get(1)?, wrapped: r.get(2)?, size: r.get(3)?, at: r.get(4)? }),
        )
    }

    /// One of the account's takes and its sealed bytes, read whole; another account's is none.
    pub fn meet_take(&self, account: i64, id: &str) -> Option<(MeetTake, Vec<u8>)> {
        let take = self
            .lock()
            .query_row("SELECT id, meeting, wrapped, size, created_at FROM meet_takes WHERE id = ?1 AND account_id = ?2", params![id, account], |r| {
                Ok(MeetTake { id: r.get(0)?, meeting: r.get(1)?, wrapped: r.get(2)?, size: r.get(3)?, at: r.get(4)? })
            })
            .optional()
            .ok()
            .flatten()?;
        let bytes = std::fs::read(self.meet_take_path(account, id)).ok()?;
        Some((take, bytes))
    }

    /// A take taken: its row and its file gone. Answers whether one went.
    pub fn delete_meet_take(&self, account: i64, id: &str) -> bool {
        let gone = self.lock().execute("DELETE FROM meet_takes WHERE id = ?1 AND account_id = ?2", params![id, account]).map(|n| n > 0).unwrap_or(false);
        if gone {
            let _ = std::fs::remove_file(self.meet_take_path(account, id));
        }
        gone
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    fn booked(account: i64, id: &str, starts_at: i64, ends_at: i64, state: &str) -> MeetBooking {
        MeetBooking {
            id: id.into(),
            account,
            uid: format!("uid-{id}"),
            url: "https://meet.google.com/abc-defg-hij".into(),
            title: Some("Roadmap".into()),
            starts_at,
            ends_at,
            state: state.into(),
            detail: None,
            sequence: 0,
            series: None,
        }
    }

    #[test]
    fn a_booking_is_due_from_two_minutes_before_until_a_quarter_hour_after_and_only_while_live() {
        let (s, a, _dir) = fixture();
        s.insert_meet_booking(&booked(a.id, "m", 1_000_000, 2_000_000, "booked"), 1).unwrap();
        assert!(!s.insert_meet_booking(&booked(a.id, "m2", 0, 0, "booked").clone_with_uid("uid-m"), 1).unwrap(), "one booking a UID");
        let due = |now| s.meet_due(now, 120_000, 900_000).into_iter().map(|b| b.id).collect::<Vec<_>>();
        assert!(due(1_000_000 - 120_001).is_empty());
        assert_eq!(due(1_000_000 - 120_000), vec!["m"]);
        assert_eq!(due(2_000_000 + 899_999), vec!["m"]);
        assert!(due(2_000_000 + 900_000).is_empty());
        assert!(s.set_meet_state("m", "done", Some("meeting ended"), 2));
        assert!(due(1_500_000).is_empty(), "done is not due");
    }

    impl MeetBooking {
        fn clone_with_uid(&self, uid: &str) -> Self {
            MeetBooking { uid: uid.into(), ..self.clone() }
        }
    }

    #[test]
    fn the_sweep_blanks_what_is_over_fails_what_was_missed_and_forgets_what_is_a_month_old() {
        let (s, a, _dir) = fixture();
        let hour = 3_600_000;
        let now = 100 * 24 * hour;
        s.insert_meet_booking(&booked(a.id, "soon", now + hour, now + 2 * hour, "booked"), 1).unwrap();
        s.insert_meet_booking(&booked(a.id, "just", now - hour / 2 - hour, now - hour / 2, "done"), 1).unwrap();
        s.insert_meet_booking(&booked(a.id, "over", now - 3 * hour, now - 2 * hour, "done"), 1).unwrap();
        s.insert_meet_booking(&booked(a.id, "missed", now - 3 * hour, now - 2 * hour, "booked"), 1).unwrap();
        s.insert_meet_booking(&booked(a.id, "old", now - 31 * 24 * hour, now - 31 * 24 * hour + hour, "done"), 1).unwrap();
        assert_eq!(s.sweep_meet(now, hour, 30 * 24 * hour), (3, 1));
        let get = |id: &str| s.meet_booking(id);
        assert_eq!(get("soon").unwrap().title.as_deref(), Some("Roadmap"));
        assert_eq!(get("just").unwrap().url, "https://meet.google.com/abc-defg-hij", "over for less than an hour: kept");
        let over = get("over").unwrap();
        assert_eq!((over.title, over.url.as_str(), over.state.as_str()), (None, "", "done"));
        let missed = get("missed").unwrap();
        assert_eq!((missed.state.as_str(), missed.detail.as_deref(), missed.url.as_str()), ("failed", Some("missed"), ""));
        assert_eq!(get("old"), None);
        assert_eq!(s.sweep_meet(now, hour, 30 * 24 * hour), (0, 0), "nothing twice");
    }

    #[test]
    fn a_take_is_a_file_beside_the_recordings_read_by_its_account_alone_and_gone_with_it() {
        let (s, a, dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        assert_eq!(s.put_meet_take(a.id, "t1", "m", "wrapped", &[&b"\x01head"[..], &b"sealed"[..]], 5), Ok(11));
        let file = dir.path().join("recordings").join(a.id.to_string()).join("meet").join("t1.take");
        assert_eq!(std::fs::read(&file).unwrap(), b"\x01headsealed");
        let names: Vec<String> = std::fs::read_dir(file.parent().unwrap()).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        assert_eq!(names, vec!["t1.take".to_string()], "no .part left beside it");
        assert_eq!(s.meet_takes(a.id), vec![MeetTake { id: "t1".into(), meeting: "m".into(), wrapped: "wrapped".into(), size: 11, at: 5 }]);
        assert_eq!(s.meet_take(b.id, "t1"), None);
        assert!(!s.delete_meet_take(b.id, "t1"));
        assert_eq!(s.meet_take(a.id, "t1").unwrap().1, b"\x01headsealed");
        assert!(s.put_meet_take(a.id, "t1", "m", "w", &[&b"x"[..], &b"y"[..]], 6).is_err(), "an id is taken once");
        assert_eq!(std::fs::read(&file).unwrap(), b"\x01headsealed", "and the refused write left the first alone");
        assert!(s.delete_meet_take(a.id, "t1"));
        assert!(!file.exists());
        s.put_meet_take(a.id, "t2", "m", "w", &[&b"x"[..], &b"y"[..]], 6).unwrap();
        s.insert_meet_booking(&booked(a.id, "m", 1, 2, "booked"), 1).unwrap();
        s.delete_account(a.id, 9).unwrap();
        assert!(s.meet_takes(a.id).is_empty() && s.meet_booking("m").is_none());
        assert!(!dir.path().join("recordings").join(a.id.to_string()).exists());
    }
}
