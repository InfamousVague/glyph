//! How this crate touches files, where the same few moves used to be written
//! out by hand at every site: a file written whole or not at all, a JSON file
//! read with a fallback, a removal where "already gone" is success, a directory
//! made before it is written into, and the one rule for an id that is about to
//! become a file name.
//!
//! The first four had five to nine copies each, and the copies had drifted
//! apart in exactly the ways that matter only on a bad day. Three atomic writers used a
//! fixed `.part` name and left it behind when the rename failed; one used a
//! unique name and cleaned up; only one flushed its bytes to disk before the
//! rename; `library.json` was written in place. The versions here keep the
//! safest behaviour any copy had, so every caller now gets all of it.
//!
//! What stays out on purpose: the streamed downloads (a model's `.part` in
//! `whisper::model`, the APK in `ota.rs`) hash as they write and resume or
//! restart on their own terms, so they keep their own files; and a best-effort
//! `let _ = remove_file(..)` that ignores every error is not a removal that
//! tolerates NotFound, so those sites stay as they are.
//!
//! NOT ONE `tauri::` TYPE, so `store`, `library/`, `whisper/` and `llm/` can
//! use it without breaking their rule (store.rs's header says why they have it).

use std::io::{self, Write as _};
use std::path::Path;

use serde::de::DeserializeOwned;

// ---- whole files ----------------------------------------------------------------

/// Writes `bytes` to `path` whole or not at all.
///
/// The bytes go to a hidden, uniquely named file beside the target - so the
/// rename is on one file system, and two writers at once never share, and
/// garble, one temporary file - are flushed to disk, and are then renamed over
/// the target. A process killed at any point leaves the previous file or the
/// new one, never a truncated one. On any failure after the temporary file
/// exists, it is removed: a `.tmp` left behind is invisible to the library's
/// walk and the picture scheme (neither takes a dot file) but it is storage
/// nothing will ever read.
pub fn write_atomically(path: &Path, bytes: &[u8]) -> io::Result<()> {
    write_whole(path, bytes, false)
}

/// [`write_atomically`], for a file only this user may read: on unix the
/// temporary file is created with mode 0600, so the bytes are never readable
/// by anyone else under either name. For the Notion token (notion.rs).
pub fn write_private(path: &Path, bytes: &[u8]) -> io::Result<()> {
    write_whole(path, bytes, true)
}

fn write_whole(path: &Path, bytes: &[u8], private: bool) -> io::Result<()> {
    let name = path
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, format!("not a file path: {}", path.display())))?;
    let temp = path.with_file_name(format!(".{}.{}.tmp", name.to_string_lossy(), uuid::Uuid::new_v4().simple()));
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    if private {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
    #[cfg(not(unix))]
    let _ = private;
    // A create that fails has made nothing, so there is nothing to remove.
    let mut file = options.open(&temp)?;
    let written = (|| {
        file.write_all(bytes)?;
        file.sync_all()?;
        // Closed before the rename, which Windows refuses for an open file.
        drop(file);
        std::fs::rename(&temp, path)
    })();
    if written.is_err() {
        // The write already failed; a temporary file that will not go either
        // is one more thing nothing can do anything about.
        let _ = std::fs::remove_file(&temp);
    }
    written
}

// ---- JSON -----------------------------------------------------------------------

/// The JSON in `path` as a `T`, or `None` when the file is missing, unreadable
/// or not that shape. Every caller treats those three the same way - there is
/// nothing there worth reading - so they are not told apart.
pub fn read_json<T: DeserializeOwned>(path: &Path) -> Option<T> {
    serde_json::from_slice(&std::fs::read(path).ok()?).ok()
}

/// [`read_json`], with `fallback` for a file that is missing, unreadable or not
/// that shape: the state a first launch starts from.
pub fn read_json_or<T: DeserializeOwned>(path: &Path, fallback: T) -> T {
    read_json(path).unwrap_or(fallback)
}

// ---- removing -------------------------------------------------------------------

/// Removes a file; one that is already gone is already done.
pub fn remove_file_if_present(path: &Path) -> io::Result<()> {
    match std::fs::remove_file(path) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        other => other,
    }
}

/// Removes a directory and everything in it; one that is already gone is
/// already done.
pub fn remove_dir_if_present(dir: &Path) -> io::Result<()> {
    match std::fs::remove_dir_all(dir) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        other => other,
    }
}

// ---- directories ----------------------------------------------------------------

/// Creates `dir` and its parents unless they exist, with the one sentence the
/// crate says when it cannot. Every writer makes its directory before writing
/// rather than assuming it: a first launch, and a reset, leave none.
pub fn make_dir(dir: &Path) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))
}

// ---- names that become paths -----------------------------------------------------

/// The longest id [`plain_id`] accepts. A note id is a 36-character uuid; the
/// room above that is for ids minted elsewhere, and the cap is what keeps
/// `<id>.json` and `<id>.wav` inside every file system's name limit.
pub const PLAIN_ID_MAX: usize = 128;

/// Whether `id` may become a file name: 1 to [`PLAIN_ID_MAX`] ASCII letters,
/// digits, `-` and `_`, and nothing else.
///
/// Ids reach the crate from the page and from other devices, and one that is
/// not that - a `../`, a slash, a dot, a space - must never name a file to
/// write, read or delete. Checked once here for every place an id turns into a
/// path (a recording, a note's sidecar, a picture's stem), so the places cannot
/// disagree about what is safe; they used to, by their length caps.
pub fn plain_id(id: &str) -> bool {
    (1..=PLAIN_ID_MAX).contains(&id.len()) && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_plain_ids_become_file_names() {
        for id in ["0f8e7c1a-5d2b-4e8f-9a3c-1b2d3e4f5a6b", "a", "note_1", "A-Z", &"x".repeat(PLAIN_ID_MAX)] {
            assert!(plain_id(id), "{id}");
        }
        let too_long = "x".repeat(PLAIN_ID_MAX + 1);
        for id in ["", "..", "../x", "a/b", "a\\b", "a.wav", "a b", "caf\u{e9}", "\u{0}", too_long.as_str()] {
            assert!(!plain_id(id), "{id:?}");
        }
    }

    fn temp(label: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("glyph-fsx-{label}-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn names(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        names.sort();
        names
    }

    #[test]
    fn a_whole_write_replaces_the_file_and_leaves_nothing_beside_it() {
        let dir = temp("whole");
        let path = dir.join("state.json");
        write_atomically(&path, b"first").unwrap();
        write_atomically(&path, b"second, and longer").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"second, and longer");
        assert_eq!(names(&dir), ["state.json"]);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_failed_write_leaves_the_old_file_and_no_temporary_one() {
        let dir = temp("failed");
        // A directory with something in it cannot be renamed over by a file,
        // so the write gets as far as its temporary file and then fails.
        let path = dir.join("taken");
        std::fs::create_dir_all(path.join("inside")).unwrap();
        assert!(write_atomically(&path, b"bytes").is_err());
        assert_eq!(names(&dir), ["taken"], "the temporary file is removed on failure");
        assert!(path.join("inside").is_dir(), "what was there is untouched");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn writers_at_once_never_garble_the_file() {
        let dir = temp("racing");
        let path = dir.join("sources.json");
        let writers: Vec<_> = (0u8..8)
            .map(|n| {
                let path = path.clone();
                std::thread::spawn(move || {
                    for _ in 0..25 {
                        write_atomically(&path, &vec![b'a' + n; 64 * 1024]).unwrap();
                    }
                })
            })
            .collect();
        for writer in writers {
            writer.join().unwrap();
        }
        let bytes = std::fs::read(&path).unwrap();
        assert_eq!(bytes.len(), 64 * 1024);
        assert!(bytes.iter().all(|b| *b == bytes[0]), "one writer's bytes, whole");
        assert_eq!(names(&dir), ["sources.json"]);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[cfg(unix)]
    #[test]
    fn a_private_file_is_readable_by_this_user_only() {
        use std::os::unix::fs::PermissionsExt as _;
        let dir = temp("private");
        let path = dir.join("notion.json");
        write_private(&path, br#"{"accessToken":"secret"}"#).unwrap();
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        write_atomically(&dir.join("plain.json"), b"{}").unwrap();
        assert_ne!(std::fs::metadata(dir.join("plain.json")).unwrap().permissions().mode() & 0o077, 0, "only the private write narrows it");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn json_that_is_missing_or_not_the_shape_is_the_fallback() {
        let dir = temp("json");
        let path = dir.join("known.json");
        assert_eq!(read_json_or(&path, vec![7u32]), [7]);
        std::fs::write(&path, b"{ half a file").unwrap();
        assert_eq!(read_json::<Vec<u32>>(&path), None);
        std::fs::write(&path, b"[1, 2, 3]").unwrap();
        assert_eq!(read_json_or(&path, Vec::<u32>::new()), [1, 2, 3]);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_removal_of_something_already_gone_succeeds_and_a_real_failure_does_not() {
        let dir = temp("remove");
        let file = dir.join("notion.json");
        std::fs::write(&file, b"{}").unwrap();
        remove_file_if_present(&file).unwrap();
        assert!(!file.exists());
        remove_file_if_present(&file).unwrap();
        let folder = dir.join("recordings");
        std::fs::create_dir_all(folder.join("deep")).unwrap();
        assert!(remove_file_if_present(&folder).is_err(), "a directory is not a file that is already gone");
        remove_dir_if_present(&folder).unwrap();
        assert!(!folder.exists());
        remove_dir_if_present(&folder).unwrap();
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_directory_that_cannot_be_made_says_which() {
        let dir = temp("make");
        let file = dir.join("a-file");
        std::fs::write(&file, b"").unwrap();
        make_dir(&dir.join("new/and/nested")).unwrap();
        assert!(dir.join("new/and/nested").is_dir());
        let error = make_dir(&file.join("under")).unwrap_err();
        assert!(error.starts_with("cannot create ") && error.contains("a-file"), "{error}");
        let _ = std::fs::remove_dir_all(dir);
    }
}
