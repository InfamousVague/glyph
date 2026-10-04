//! A folder chosen on Android, reached through the Storage Access Framework
//! (docs/DESIGN.md §185): the second `Vault`, which vault.rs's header promised.
//!
//! Android hands an app a folder elsewhere on the phone (a Syncthing folder, a
//! folder on a card, a Dropbox or Drive folder through that app's own
//! provider) as a tree URI from its picker, and the files in it have document
//! ids, not paths: `std::fs` cannot reach them. So each call here is a call into
//! Kotlin (`Documents`: the crate's saf.rs over JNI to files/LibraryTree.kt),
//! with the same relative paths every other vault takes, and nothing above the
//! `Vault` trait knows the difference.
//!
//! What SAF cannot do, and what is done instead:
//!
//! - **`.glyph/` needs real paths** (the sidecars are files, and the index is
//!   SQLite), so it is in the app's storage, `<app_data_dir>/trees/<key>/`
//!   (root.rs), never in the folder.
//! - **A file's modified time cannot be set**, and a pin keeps it so a pin does
//!   not move a note up the list. So the time a note is to show is kept here,
//!   in `kept-times.json` beside the sidecars, against the time and size the
//!   file really has: while those are unchanged the note shows the kept time,
//!   and the moment another app changes the file it shows the real one.
//! - **A write is not atomic.** There is no rename over an existing document,
//!   so a note is written in place (Kotlin opens it "wt"). A note is a few
//!   kilobytes, written in one go; a process killed in the middle of one could
//!   leave it cut short, which an app's own folder never can.

use std::collections::HashMap;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

use super::vault::{Entry, Vault};

/// The calls a folder reached through SAF answers, by relative path. Kotlin's, in the app; a folder's, in a test.
pub trait Documents: Send {
    /// Every `.md` file under the folder, at any depth, but none in a dot folder or with a dot name.
    fn list(&self) -> io::Result<Vec<Entry>>;
    /// A file's words; `NotFound` when it is not there.
    fn read(&self, path: &str) -> io::Result<String>;
    /// The whole file, written in place, its folders made; answers its new stat.
    fn write(&self, path: &str, text: &str) -> io::Result<Entry>;
    fn rename(&self, from: &str, to: &str) -> io::Result<()>;
    /// A file gone; one already gone is no error.
    fn remove(&self, path: &str) -> io::Result<()>;
    /// A file's time and size, or `None` when it is not there.
    fn stat(&self, path: &str) -> io::Result<Option<Entry>>;
}

/// The time a note shows, kept against the time and size its file really has.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
struct Kept {
    real: i64,
    size: u64,
    shown: i64,
}

/// `kept-times.json`, beside the sidecars.
const KEPT_FILE: &str = "kept-times.json";

pub struct TreeVault<D: Documents> {
    docs: D,
    glyph: PathBuf,
    kept: Mutex<HashMap<String, Kept>>,
}

/// Whether a path from the index or the page may name a file in the folder: relative, forward slashes, no `..`.
fn checked(path: &str) -> io::Result<&str> {
    if path.is_empty() || path.starts_with('/') || path.split('/').any(|part| part.is_empty() || part == "..") {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, format!("not a library path: {path}")));
    }
    Ok(path)
}

impl<D: Documents> TreeVault<D> {
    /// The folder `docs` reaches, with its `.glyph/` at `glyph` in the app's own storage.
    pub fn new(docs: D, glyph: &Path) -> io::Result<TreeVault<D>> {
        std::fs::create_dir_all(glyph)?;
        let kept = crate::fsx::read_json_or(&glyph.join(KEPT_FILE), HashMap::new());
        Ok(TreeVault { docs, glyph: glyph.to_path_buf(), kept: Mutex::new(kept) })
    }

    fn save(&self, kept: &HashMap<String, Kept>) {
        let _ = crate::fsx::write_atomically(&self.glyph.join(KEPT_FILE), serde_json::to_string(kept).unwrap_or_default().as_bytes());
    }

    /// `entry` with the time the note is to show: the kept one while the file is as it was kept.
    fn shown(&self, mut entry: Entry, kept: &HashMap<String, Kept>) -> Entry {
        if let Some(k) = kept.get(&entry.path) {
            if k.real == entry.modified_ms && k.size == entry.size {
                entry.modified_ms = k.shown;
            }
        }
        entry
    }

    fn forget(&self, path: &str) {
        let mut kept = crate::lock::lock(&self.kept);
        if kept.remove(path).is_some() {
            self.save(&kept);
        }
    }
}

impl<D: Documents> Vault for TreeVault<D> {
    fn markdown(&self) -> io::Result<Vec<Entry>> {
        let listed = self.docs.list()?;
        let mut kept = crate::lock::lock(&self.kept);
        // A kept time for a file another app took away, or changed, is no longer anything's.
        let before = kept.len();
        kept.retain(|path, k| listed.iter().any(|e| &e.path == path && e.modified_ms == k.real && e.size == k.size));
        if kept.len() != before {
            self.save(&kept);
        }
        let mut out: Vec<Entry> = listed.into_iter().map(|e| self.shown(e, &kept)).collect();
        out.sort_by(|a, b| a.path.cmp(&b.path));
        Ok(out)
    }

    fn read(&self, path: &str) -> io::Result<String> {
        self.docs.read(checked(path)?)
    }

    fn write(&self, path: &str, text: &str) -> io::Result<Entry> {
        let entry = self.docs.write(checked(path)?, text)?;
        // A write is an edit: the file shows its own time from here, unless the caller keeps another.
        self.forget(path);
        Ok(entry)
    }

    fn rename(&self, from: &str, to: &str) -> io::Result<()> {
        self.docs.rename(checked(from)?, checked(to)?)?;
        let mut kept = crate::lock::lock(&self.kept);
        if let Some(mut k) = kept.remove(from) {
            // A rename is not an edit, whatever time the provider gives the moved file.
            if let Ok(Some(now)) = self.docs.stat(to) {
                k.real = now.modified_ms;
                k.size = now.size;
                kept.insert(to.to_string(), k);
            }
            self.save(&kept);
        }
        Ok(())
    }

    fn remove(&self, path: &str) -> io::Result<()> {
        self.docs.remove(checked(path)?)?;
        self.forget(path);
        Ok(())
    }

    fn exists(&self, path: &str) -> bool {
        checked(path).ok().and_then(|path| self.docs.stat(path).ok().flatten()).is_some()
    }

    fn stat(&self, path: &str) -> io::Result<Entry> {
        let entry = self.docs.stat(checked(path)?)?.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, format!("{path} is not in the folder")))?;
        let kept = crate::lock::lock(&self.kept);
        Ok(self.shown(entry, &kept))
    }

    fn keep_modified(&self, path: &str, modified_ms: i64) -> io::Result<Entry> {
        let mut entry = self.docs.stat(checked(path)?)?.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, format!("{path} is not in the folder")))?;
        let mut kept = crate::lock::lock(&self.kept);
        kept.insert(path.to_string(), Kept { real: entry.modified_ms, size: entry.size, shown: modified_ms });
        self.save(&kept);
        entry.modified_ms = modified_ms;
        Ok(entry)
    }

    fn glyph_dir(&self) -> PathBuf {
        self.glyph.clone()
    }
}

/// A folder on disk standing in for one reached through SAF, as SAF has it: no time can be set, and a write is a
/// write in place. For tests here and in library_root.rs.
#[cfg(test)]
pub struct FolderDocuments(pub PathBuf);

#[cfg(test)]
impl FolderDocuments {
    fn entry(&self, path: &str) -> io::Result<Option<Entry>> {
        match std::fs::metadata(self.0.join(path)) {
            Ok(meta) => Ok(Some(Entry { path: path.to_string(), modified_ms: meta.modified().map_or(0, crate::note::ms_since_epoch), size: meta.len(), evicted: false })),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e),
        }
    }

    fn walk(&self, dir: &Path, prefix: &str, out: &mut Vec<Entry>) -> io::Result<()> {
        for item in std::fs::read_dir(dir)? {
            let item = item?;
            let name = item.file_name().to_string_lossy().to_string();
            if name.starts_with('.') {
                continue;
            }
            let rel = if prefix.is_empty() { name.clone() } else { format!("{prefix}/{name}") };
            if item.file_type()?.is_dir() {
                self.walk(&item.path(), &rel, out)?;
            } else if name.to_ascii_lowercase().ends_with(".md") {
                out.extend(self.entry(&rel)?);
            }
        }
        Ok(())
    }
}

#[cfg(test)]
impl Documents for FolderDocuments {
    fn list(&self) -> io::Result<Vec<Entry>> {
        let mut out = Vec::new();
        self.walk(&self.0, "", &mut out)?;
        Ok(out)
    }

    fn read(&self, path: &str) -> io::Result<String> {
        std::fs::read_to_string(self.0.join(path))
    }

    fn write(&self, path: &str, text: &str) -> io::Result<Entry> {
        let full = self.0.join(path);
        std::fs::create_dir_all(full.parent().unwrap_or(&self.0))?;
        std::fs::write(&full, text)?;
        self.entry(path)?.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, path.to_string()))
    }

    fn rename(&self, from: &str, to: &str) -> io::Result<()> {
        let target = self.0.join(to);
        std::fs::create_dir_all(target.parent().unwrap_or(&self.0))?;
        std::fs::rename(self.0.join(from), target)
    }

    fn remove(&self, path: &str) -> io::Result<()> {
        crate::fsx::remove_file_if_present(&self.0.join(path))
    }

    fn stat(&self, path: &str) -> io::Result<Option<Entry>> {
        self.entry(path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Library;
    use crate::test_support::TempDir;

    fn tree(dir: &TempDir) -> TreeVault<FolderDocuments> {
        std::fs::create_dir_all(dir.join("folder")).unwrap();
        TreeVault::new(FolderDocuments(dir.join("folder")), &dir.join("app/trees/k")).unwrap()
    }

    #[test]
    fn a_kept_time_is_shown_until_another_app_changes_the_file() {
        let dir = TempDir::new("tree-kept");
        let vault = tree(&dir);
        let written = vault.write("Inbox/Plan.md", "# Plan\n").unwrap();
        let kept = vault.keep_modified("Inbox/Plan.md", 1_000).unwrap();
        assert_eq!(kept.modified_ms, 1_000);
        assert_eq!(vault.stat("Inbox/Plan.md").unwrap().modified_ms, 1_000, "the file's own time is not this, but the note's is");
        assert_eq!(vault.markdown().unwrap()[0].modified_ms, 1_000);
        assert!(written.modified_ms > 1_000);
        // Kept across a reopen, in the app's storage and not in the folder.
        assert!(dir.join("app/trees/k/kept-times.json").exists() && !dir.join("folder/.glyph").exists());
        let vault = TreeVault::new(FolderDocuments(dir.join("folder")), &dir.join("app/trees/k")).unwrap();
        assert_eq!(vault.stat("Inbox/Plan.md").unwrap().modified_ms, 1_000);
        // Renamed, still kept; changed by another app, its own time again.
        vault.rename("Inbox/Plan.md", "Work/Plan.md").unwrap();
        assert_eq!(vault.stat("Work/Plan.md").unwrap().modified_ms, 1_000);
        std::fs::write(dir.join("folder/Work/Plan.md"), "# Plan\n\nedited in another app\n").unwrap();
        assert!(vault.markdown().unwrap()[0].modified_ms > 1_000);
        assert!(!vault.exists("../app/trees/k/kept-times.json") && vault.read("/etc/hosts").is_err(), "nothing outside the folder");
    }

    #[test]
    fn a_pin_through_saf_is_still_not_an_edit() {
        let dir = TempDir::new("tree-pin");
        let mut library = Library::open_chosen(Box::new(tree(&dir)), &dir.join("app/index/k.sqlite")).unwrap();
        let saved = library.save_note("p", "# Pin me\n", "editor").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(20));
        let pinned = library.set_starred("p", true).unwrap().unwrap();
        assert!(pinned.starred);
        assert_eq!(pinned.updated_at, saved.updated_at, "a pin doesn't move the note up the list");
        assert_eq!(library.list_notes().unwrap()[0].updated_at, saved.updated_at);
        assert!(std::fs::read_to_string(dir.join("folder/Inbox/Pin me.md")).unwrap().contains("pinned: true"));
        assert!(!library.in_own_folder());
        assert!(dir.join("app/trees/k/notes").is_dir() && !dir.join("folder/.glyph").exists(), "`.glyph` is in the app's storage");
    }
}
