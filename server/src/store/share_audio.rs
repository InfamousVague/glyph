//! A shared meeting's recording (src/shares.rs, docs/SHARING.md "A meeting's recording"): ciphertext the owner's device
//! sealed a part at a time under the share's own key, kept as a file beside the account's recordings, because it is
//! tens of megabytes where a share is a few, with a row in `share_audio` saying which upload it is and how big.
//!
//! An upload is parts first, then a commit. Each part lands in a folder of its own for that upload
//! (`<data>/recordings/<account>/share-audio/<share>.<upload>.staging/<n>.part`), so parts can be sent again one at a
//! time on a bad connection; the commit checks that every part from 0 is there and nothing past, and writes them into
//! one file as the reader reads it - each part as its length, four bytes big-endian, then its bytes - beside the old
//! one, renamed into place only once the row is ready. So a reader gets the old recording or the new one, never half.
//! An upload begun for another id clears the share's other unfinished ones: the latest device to start is the one
//! that finishes.
//!
//! What a share's recording may take, and what the account's may, are the caller's limits: everything kept and every
//! part waiting, for that share and for the whole account. The files live under the account's own folder, so the
//! account going takes them with it (`delete_account`), and the share going takes its own (`delete_share`).

use super::Store;
use rusqlite::{params, OptionalExtension};
use std::io::Write;
use std::path::{Path, PathBuf};

/// Why a part or a commit was refused.
#[derive(Debug, PartialEq, Eq)]
pub enum AudioWrite {
    /// No share has that id, or it is another account's: answered alike, so asking teaches nothing.
    NoShare,
    /// It would take the share's recording past its limit.
    TooLarge,
    /// It would take the account's shared recordings past theirs.
    AccountFull,
    /// A commit named parts that have not all arrived.
    Missing,
    /// Something below the rules failed.
    Failed,
}

impl From<rusqlite::Error> for AudioWrite {
    fn from(_: rusqlite::Error) -> Self {
        AudioWrite::Failed
    }
}

impl From<std::io::Error> for AudioWrite {
    fn from(_: std::io::Error) -> Self {
        AudioWrite::Failed
    }
}

/// A shared recording as the reader is given it: where its file is, how long, which upload it was, and when.
#[derive(Debug, PartialEq, Eq)]
pub struct ShareAudio {
    pub path: PathBuf,
    pub size: u64,
    pub upload: String,
    pub updated: i64,
}

/// The bytes a part takes in the kept file beyond its own: its length.
const FRAME: u64 = 4;

impl Store {
    fn share_audio_dir(&self, account: i64) -> PathBuf {
        self.recordings.join(account.to_string()).join("share-audio")
    }

    fn share_audio_path(&self, account: i64, share: &str) -> PathBuf {
        self.share_audio_dir(account).join(format!("{share}.bin"))
    }

    fn share_audio_staging(&self, account: i64, share: &str, upload: &str) -> PathBuf {
        self.share_audio_dir(account).join(format!("{share}.{upload}.staging"))
    }

    /// The share's owner, if it has one.
    fn share_owner(&self, share: &str) -> Option<i64> {
        self.one("SELECT account_id FROM shares WHERE id = ?1", params![share], |r| r.get(0))
    }

    /// The bytes waiting in every unfinished upload under `dir`, and those waiting for `share` alone.
    fn staged_bytes(dir: &Path, share: &str) -> (u64, u64) {
        let (mut all, mut mine) = (0, 0);
        let Ok(entries) = std::fs::read_dir(dir) else { return (0, 0) };
        let prefix = format!("{share}.");
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if !name.ends_with(".staging") {
                continue;
            }
            let size: u64 = std::fs::read_dir(entry.path()).map(|parts| parts.flatten().filter_map(|p| p.metadata().ok()).map(|m| m.len()).sum()).unwrap_or(0);
            all += size;
            if name.starts_with(&prefix) {
                mine += size;
            }
        }
        (all, mine)
    }

    /// Clears the share's unfinished uploads, all of them or all but `keep`'s.
    fn clear_staging(&self, account: i64, share: &str, keep: Option<&str>) {
        let Ok(entries) = std::fs::read_dir(self.share_audio_dir(account)) else { return };
        let prefix = format!("{share}.");
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let Some(upload) = name.strip_prefix(&prefix).and_then(|rest| rest.strip_suffix(".staging")) else { continue };
            if keep != Some(upload) {
                let _ = std::fs::remove_dir_all(entry.path());
            }
        }
    }

    /// The bytes of every recording the account shares, kept.
    pub fn share_audio_used(&self, account: i64) -> u64 {
        self.one("SELECT COALESCE(SUM(size), 0) FROM share_audio WHERE account_id = ?1", params![account], |r| r.get::<_, i64>(0)).unwrap_or(0).max(0) as u64
    }

    /// Keeps part `n` of upload `upload` of the account's share, refused where the share is not theirs, or where the
    /// part would take the share's recording past `share_limit` bytes or the account's past `account_limit` (what is
    /// kept and what is waiting both count; the share's own recording, which the commit will replace, does not count
    /// against the share, and does against the account until then). A part sent again is written over.
    pub fn put_share_audio_part(&self, account: i64, share: &str, upload: &str, n: u32, bytes: &[u8], share_limit: u64, account_limit: u64) -> Result<(), AudioWrite> {
        if self.share_owner(share) != Some(account) {
            return Err(AudioWrite::NoShare);
        }
        self.clear_staging(account, share, Some(upload));
        let dir = self.share_audio_dir(account);
        let staging = self.share_audio_staging(account, share, upload);
        let part = staging.join(format!("{n}.part"));
        let before = std::fs::metadata(&part).map(|m| m.len()).ok();
        let (all, mine) = Self::staged_bytes(&dir, share);
        let waiting = std::fs::read_dir(&staging).map(|e| e.flatten().filter(|e| e.file_name().to_string_lossy().ends_with(".part")).count() as u64).unwrap_or(0);
        let parts = waiting + u64::from(before.is_none());
        let before = before.unwrap_or(0);
        let size = bytes.len() as u64;
        if mine - before + size + FRAME * parts > share_limit {
            return Err(AudioWrite::TooLarge);
        }
        if self.share_audio_used(account) + all - before + size > account_limit {
            return Err(AudioWrite::AccountFull);
        }
        std::fs::create_dir_all(&staging)?;
        let side = staging.join(format!("{n}.{:016x}.new", rand::random::<u64>()));
        std::fs::write(&side, bytes)?;
        if let Err(failed) = std::fs::rename(&side, &part) {
            let _ = std::fs::remove_file(&side);
            return Err(failed.into());
        }
        Ok(())
    }

    /// Makes upload `upload`, of `parts` parts, the share's recording: every part from 0 to `parts - 1` must be
    /// there and no other, and the whole within `share_limit`. Answers its size. The old recording is replaced only
    /// once the new one is whole, and the upload's folder goes either way it ends but Missing.
    pub fn commit_share_audio(&self, account: i64, share: &str, upload: &str, parts: u32, now: i64, share_limit: u64) -> Result<u64, AudioWrite> {
        if self.share_owner(share) != Some(account) {
            // Taken down while its parts came (or never this account's): what this account left for it goes.
            self.clear_staging(account, share, None);
            return Err(AudioWrite::NoShare);
        }
        let staging = self.share_audio_staging(account, share, upload);
        let names: Vec<String> = match std::fs::read_dir(&staging) {
            Ok(entries) => entries.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).filter(|n| n.ends_with(".part")).collect(),
            Err(_) => return Err(AudioWrite::Missing),
        };
        if parts == 0 || names.len() != parts as usize || !(0..parts).all(|n| names.contains(&format!("{n}.part"))) {
            return Err(AudioWrite::Missing);
        }
        let mut size = 0;
        for n in 0..parts {
            size += std::fs::metadata(staging.join(format!("{n}.part")))?.len() + FRAME;
        }
        if size > share_limit {
            let _ = std::fs::remove_dir_all(&staging);
            return Err(AudioWrite::TooLarge);
        }
        let side = self.share_audio_dir(account).join(format!("{share}.{:016x}.new", rand::random::<u64>()));
        let written = (|| -> std::io::Result<()> {
            let mut out = std::io::BufWriter::new(std::fs::File::create(&side)?);
            for n in 0..parts {
                let bytes = std::fs::read(staging.join(format!("{n}.part")))?;
                out.write_all(&(bytes.len() as u32).to_be_bytes())?;
                out.write_all(&bytes)?;
            }
            out.into_inner().map_err(|e| e.into_error())?.sync_all()
        })();
        if let Err(failed) = written {
            let _ = std::fs::remove_file(&side);
            return Err(failed.into());
        }
        let placed = (|| -> Result<(), AudioWrite> {
            let mut conn = self.lock();
            let tx = conn.transaction()?;
            // The share may have been taken down while the parts were joined: then nothing is kept.
            let owner: Option<i64> = tx.query_row("SELECT account_id FROM shares WHERE id = ?1", params![share], |r| r.get(0)).optional()?;
            if owner != Some(account) {
                return Err(AudioWrite::NoShare);
            }
            tx.execute(
                "INSERT INTO share_audio (share_id, account_id, upload, parts, size, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT(share_id) DO UPDATE SET upload = excluded.upload, parts = excluded.parts, size = excluded.size, updated_at = excluded.updated_at",
                params![share, account, upload, parts, size as i64, now],
            )?;
            std::fs::rename(&side, self.share_audio_path(account, share))?;
            tx.commit()?;
            Ok(())
        })();
        if placed.is_err() {
            let _ = std::fs::remove_file(&side);
        }
        let _ = std::fs::remove_dir_all(&staging);
        placed.map(|_| size)
    }

    /// The share's recording, for anyone who has the share's id.
    pub fn share_audio(&self, share: &str) -> Option<ShareAudio> {
        let (account, upload, size, updated): (i64, String, i64, i64) =
            self.one("SELECT account_id, upload, size, updated_at FROM share_audio WHERE share_id = ?1", params![share], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?;
        let path = self.share_audio_path(account, share);
        path.exists().then_some(ShareAudio { path, size: size.max(0) as u64, upload, updated })
    }

    /// Takes the account's share's recording down, and any upload of it not finished; another account's is left.
    /// Answers whether one was kept.
    pub fn delete_share_audio(&self, account: i64, share: &str) -> bool {
        let gone = self.lock().execute("DELETE FROM share_audio WHERE share_id = ?1 AND account_id = ?2", params![share, account]).map(|n| n > 0).unwrap_or(false);
        // The files are under the asking account's own folder: another account asking finds nothing of this one's.
        let _ = std::fs::remove_file(self.share_audio_path(account, share));
        self.clear_staging(account, share, None);
        gone
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    const MB: u64 = 1_000_000;

    fn listed(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(dir).map(|e| e.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect()).unwrap_or_default();
        names.sort();
        names
    }

    #[test]
    fn parts_become_one_file_of_framed_parts_and_only_once_every_part_is_there() {
        let (s, a, _dir) = fixture();
        s.put_share(a.id, "share", "words", 10, 500).unwrap();
        s.put_share_audio_part(a.id, "share", "up1", 1, b"world", MB, 10 * MB).unwrap();
        assert_eq!(s.commit_share_audio(a.id, "share", "up1", 2, 11, MB), Err(AudioWrite::Missing), "part 0 has not come");
        s.put_share_audio_part(a.id, "share", "up1", 0, b"hello", MB, 10 * MB).unwrap();
        assert_eq!(s.commit_share_audio(a.id, "share", "up1", 3, 11, MB), Err(AudioWrite::Missing), "a third was promised");
        assert_eq!(s.commit_share_audio(a.id, "share", "up1", 2, 12, MB), Ok(18));
        let kept = s.share_audio("share").unwrap();
        assert_eq!((kept.size, kept.upload.as_str(), kept.updated), (18, "up1", 12));
        assert_eq!(std::fs::read(&kept.path).unwrap(), [&[0, 0, 0, 5][..], b"hello", &[0, 0, 0, 5], b"world"].concat());
        assert_eq!(listed(&s.share_audio_dir(a.id)), vec!["share.bin".to_string()], "the upload's folder went with the commit");
        assert_eq!(s.share_audio_used(a.id), 18);
    }

    #[test]
    fn a_new_upload_replaces_the_old_whole_and_clears_another_upload_left_half_done() {
        let (s, a, _dir) = fixture();
        s.put_share(a.id, "share", "words", 10, 500).unwrap();
        s.put_share_audio_part(a.id, "share", "old", 0, b"first", MB, 10 * MB).unwrap();
        s.commit_share_audio(a.id, "share", "old", 1, 11, MB).unwrap();
        s.put_share_audio_part(a.id, "share", "left", 0, b"abandoned", MB, 10 * MB).unwrap();
        s.put_share_audio_part(a.id, "share", "new", 0, b"second!", MB, 10 * MB).unwrap();
        assert_eq!(s.commit_share_audio(a.id, "share", "left", 1, 12, MB), Err(AudioWrite::Missing), "the newer upload cleared it");
        assert_eq!(s.share_audio("share").unwrap().upload, "old", "the old recording plays until the new one is whole");
        assert_eq!(s.commit_share_audio(a.id, "share", "new", 1, 13, MB), Ok(11));
        assert_eq!(std::fs::read(s.share_audio("share").unwrap().path).unwrap(), [&[0, 0, 0, 7][..], b"second!"].concat());
        assert_eq!(s.share_audio_used(a.id), 11, "the account counts the one kept, not both");
    }

    #[test]
    fn only_the_share_s_owner_can_send_or_take_down_its_recording() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        assert_eq!(s.put_share_audio_part(a.id, "nothing", "up", 0, b"x", MB, MB), Err(AudioWrite::NoShare), "no share by that id");
        s.put_share(a.id, "share", "words", 10, 500).unwrap();
        assert_eq!(s.put_share_audio_part(b.id, "share", "up", 0, b"x", MB, MB), Err(AudioWrite::NoShare));
        s.put_share_audio_part(a.id, "share", "up", 0, b"mine", MB, MB).unwrap();
        assert_eq!(s.commit_share_audio(b.id, "share", "up", 1, 11, MB), Err(AudioWrite::NoShare));
        s.commit_share_audio(a.id, "share", "up", 1, 11, MB).unwrap();
        assert!(!s.delete_share_audio(b.id, "share"));
        assert!(s.share_audio("share").is_some(), "another's take-down does nothing");
        assert!(s.delete_share_audio(a.id, "share"));
        assert_eq!(s.share_audio("share"), None);
        assert!(listed(&s.share_audio_dir(a.id)).is_empty());
    }

    #[test]
    fn a_share_s_recording_and_the_account_s_are_held_to_their_limits() {
        let (s, a, _dir) = fixture();
        s.put_share(a.id, "one", "words", 10, 500).unwrap();
        s.put_share(a.id, "two", "words", 10, 500).unwrap();
        // The share's limit counts each part's four bytes of length too: 2 parts of 45 are 98 kept.
        s.put_share_audio_part(a.id, "one", "up", 0, &[1; 45], 100, 1000).unwrap();
        s.put_share_audio_part(a.id, "one", "up", 1, &[2; 45], 100, 1000).unwrap();
        assert_eq!(s.put_share_audio_part(a.id, "one", "up", 2, &[3; 1], 100, 1000), Err(AudioWrite::TooLarge));
        s.put_share_audio_part(a.id, "one", "up", 1, &[2; 46], 100, 1000).expect("a part sent again counts once");
        assert_eq!(s.commit_share_audio(a.id, "one", "up", 2, 11, 100), Ok(99));
        // The account's: 99 kept for "one", so "two" may wait with no more than 101 under 200.
        s.put_share_audio_part(a.id, "two", "up", 0, &[4; 60], 1000, 200).unwrap();
        assert_eq!(s.put_share_audio_part(a.id, "two", "up", 1, &[5; 42], 1000, 200), Err(AudioWrite::AccountFull));
        s.put_share_audio_part(a.id, "two", "up", 1, &[5; 41], 1000, 200).unwrap();
        assert!(s.delete_share_audio(a.id, "one"));
        s.put_share_audio_part(a.id, "two", "up", 2, &[6; 90], 1000, 200).expect("a recording taken down makes room");
    }

    #[test]
    fn taking_the_share_down_takes_its_recording_and_its_unfinished_upload() {
        let (s, a, _dir) = fixture();
        s.put_share(a.id, "share", "words", 10, 500).unwrap();
        s.put_share_audio_part(a.id, "share", "up", 0, b"kept", MB, MB).unwrap();
        s.commit_share_audio(a.id, "share", "up", 1, 11, MB).unwrap();
        s.put_share_audio_part(a.id, "share", "next", 0, b"waiting", MB, MB).unwrap();
        assert!(s.delete_share(a.id, "share"));
        assert_eq!(s.share_audio("share"), None);
        assert_eq!(s.share_audio_used(a.id), 0);
        assert!(listed(&s.share_audio_dir(a.id)).is_empty(), "no file and no folder left");
    }

    #[test]
    fn a_share_taken_down_while_its_parts_were_joined_keeps_nothing() {
        let (s, a, _dir) = fixture();
        s.put_share(a.id, "share", "words", 10, 500).unwrap();
        s.put_share_audio_part(a.id, "share", "up", 0, b"bytes", MB, MB).unwrap();
        s.lock().execute("DELETE FROM shares WHERE id = 'share'", []).unwrap();
        assert_eq!(s.commit_share_audio(a.id, "share", "up", 1, 11, MB), Err(AudioWrite::NoShare));
        assert!(listed(&s.share_audio_dir(a.id)).is_empty());
    }
}
