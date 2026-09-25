//! Recordings and pictures: the one thing an account keeps that is not in SQLite. Each is a file under
//! `<data>/recordings/<account id>/<id>.bin`, because they are megabytes each, with a row in `recordings` carrying the
//! revision the bytes were written at.
//!
//! The table and the folder are called recordings because voice notes' audio came first; pictures arrived later under
//! the same route and are kept the same way (docs/SYNC.md, an `i-<ext>-<stem>` id). Renaming either would need a
//! migration the schema has no path for (store.rs says why), so the name stays and this says what it holds.

use super::{Store, WriteError};
use rusqlite::{params, Connection, OptionalExtension};
use std::path::{Path, PathBuf};

impl Store {
    fn recording_path(&self, account: i64, id: &str) -> PathBuf {
        self.recordings.join(account.to_string()).join(format!("{id}.bin"))
    }

    /// A recording's revision, read by `recording` and inside `put_recording`'s transaction alike.
    fn recording_rev_in(conn: &Connection, account: i64, id: &str) -> rusqlite::Result<Option<i64>> {
        conn.query_row("SELECT rev FROM recordings WHERE account_id = ?1 AND id = ?2", params![account, id], |r| r.get(0)).optional()
    }

    /// Stores a recording written from `base`, or refuses it with the stored revision when that has moved on; one the
    /// service has never seen is taken whatever its base. The bytes go to a side file and are renamed into place only
    /// once the row is ready, so a reader never gets half a recording.
    ///
    /// The side file is this call's own (`<id>.<random>.part`): it is written before the lock is taken, and two
    /// uploads of one recording sharing a name could interleave, one's revision and size recorded against the other's
    /// bytes. Whichever takes the lock second is refused as stale, and its side file goes, as does one whose write
    /// failed on the way.
    pub fn put_recording(&self, account: i64, id: &str, base: i64, bytes: &[u8], now: i64) -> Result<i64, WriteError<i64>> {
        let dir = self.recordings.join(account.to_string());
        std::fs::create_dir_all(&dir)?;
        let part = dir.join(format!("{id}.{:016x}.part", rand::random::<u64>()));
        std::fs::write(&part, bytes)?;
        let placed = self.place_recording(account, id, base, bytes.len(), now, &part);
        if placed.is_err() {
            let _ = std::fs::remove_file(&part);
        }
        placed
    }

    /// `put_recording` once the bytes are in `part`: the revision checked and the row written under the lock, and
    /// the bytes renamed into place before the row is committed.
    fn place_recording(&self, account: i64, id: &str, base: i64, size: usize, now: i64, part: &Path) -> Result<i64, WriteError<i64>> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let current = Self::recording_rev_in(&tx, account, id)?;
        if let Some(stored) = current {
            if stored != base {
                return Err(WriteError::Stale(stored));
            }
        }
        let rev = Self::next_rev(&tx, account)?;
        tx.execute(
            "INSERT INTO recordings (account_id, id, rev, size, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(account_id, id) DO UPDATE SET rev = excluded.rev, size = excluded.size, updated_at = excluded.updated_at",
            params![account, id, rev, size as i64, now],
        )?;
        std::fs::rename(part, self.recording_path(account, id))?;
        tx.commit()?;
        Ok(rev)
    }

    /// A recording's revision and its bytes, read whole.
    pub fn recording(&self, account: i64, id: &str) -> Option<(i64, Vec<u8>)> {
        let rev = Self::recording_rev_in(&self.lock(), account, id).ok().flatten()?;
        let bytes = std::fs::read(self.recording_path(account, id)).ok()?;
        Some((rev, bytes))
    }
}

#[cfg(test)]
mod tests {
    use super::super::{fixture, WriteError};

    #[test]
    fn recordings_are_whole_files_with_their_own_revision() {
        let (s, a, _dir) = fixture();
        let rev = s.put_recording(a.id, "n1", 0, b"audio-1", 1).unwrap();
        assert_eq!(s.recording(a.id, "n1"), Some((rev, b"audio-1".to_vec())));
        assert_eq!(s.put_recording(a.id, "n1", 0, b"stale", 2), Err(WriteError::Stale(rev)));
        assert_eq!(s.recording(a.id, "n1").unwrap().1, b"audio-1".to_vec(), "a refused write leaves the file alone");
        let next = s.put_recording(a.id, "n1", rev, b"audio-2", 3).unwrap();
        assert_eq!(s.recording(a.id, "n1"), Some((next, b"audio-2".to_vec())));
    }

    #[test]
    fn a_refused_write_leaves_no_part_file_and_an_account_s_folder_goes_with_it() {
        let (s, a, dir) = fixture();
        let rev = s.put_recording(a.id, "n1", 0, b"audio-1", 1).unwrap();
        s.put_recording(a.id, "n1", rev + 5, b"stale", 2).unwrap_err();
        let folder = dir.path().join("recordings").join(a.id.to_string());
        let names: Vec<String> = std::fs::read_dir(&folder).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        assert_eq!(names, vec!["n1.bin".to_string()], "only the stored recording, no .part beside it");
        s.delete_account(a.id).unwrap();
        assert!(!folder.exists());
        assert_eq!(s.recording(a.id, "n1"), None);
    }
}
