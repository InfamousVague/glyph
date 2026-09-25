//! Recordings and pictures: the one thing an account keeps that is not in SQLite. Each is a file under
//! `<data>/recordings/<account id>/<id>.bin`, because they are megabytes each, with a row in `recordings` carrying the
//! revision the bytes were written at.
//!
//! The table and the folder are called recordings because voice notes' audio came first; pictures arrived later under
//! the same route and are kept the same way (docs/SYNC.md, an `i-<ext>-<stem>` id). Renaming either would need a
//! migration the schema has no path for (store.rs says why), so the name stays and this says what it holds.

use super::Store;
use rusqlite::{params, Connection, OptionalExtension};
use std::path::PathBuf;

impl Store {
    fn recording_path(&self, account: i64, id: &str) -> PathBuf {
        self.recordings.join(account.to_string()).join(format!("{id}.bin"))
    }

    /// A recording's revision, read by `recording` and inside `put_recording`'s transaction alike.
    fn recording_rev_in(conn: &Connection, account: i64, id: &str) -> rusqlite::Result<Option<i64>> {
        conn.query_row("SELECT rev FROM recordings WHERE account_id = ?1 AND id = ?2", params![account, id], |r| r.get(0)).optional()
    }

    /// Stores a recording written from `base`. The bytes go to a side file and are renamed into place only once the
    /// row is ready, so a reader never gets half a recording.
    pub fn put_recording(&self, account: i64, id: &str, base: i64, bytes: &[u8], now: i64) -> Result<i64, Option<i64>> {
        let dir = self.recordings.join(account.to_string());
        std::fs::create_dir_all(&dir).map_err(|_| None)?;
        let dest = self.recording_path(account, id);
        let part = dest.with_extension("part");
        std::fs::write(&part, bytes).map_err(|_| None)?;
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(|_| None)?;
        let current = Self::recording_rev_in(&tx, account, id).map_err(|_| None)?;
        if let Some(stored) = current {
            if stored != base {
                let _ = std::fs::remove_file(&part);
                return Err(Some(stored));
            }
        }
        let rev = Self::next_rev(&tx, account).map_err(|_| None)?;
        tx.execute(
            "INSERT INTO recordings (account_id, id, rev, size, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(account_id, id) DO UPDATE SET rev = excluded.rev, size = excluded.size, updated_at = excluded.updated_at",
            params![account, id, rev, bytes.len() as i64, now],
        )
        .map_err(|_| None)?;
        std::fs::rename(&part, &dest).map_err(|_| None)?;
        tx.commit().map_err(|_| None)?;
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
    use super::super::fixture;

    #[test]
    fn recordings_are_whole_files_with_their_own_revision() {
        let (s, a, _dir) = fixture();
        let rev = s.put_recording(a.id, "n1", 0, b"audio-1", 1).unwrap();
        assert_eq!(s.recording(a.id, "n1"), Some((rev, b"audio-1".to_vec())));
        assert_eq!(s.put_recording(a.id, "n1", 0, b"stale", 2), Err(Some(rev)));
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
