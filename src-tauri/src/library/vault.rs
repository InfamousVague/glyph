//! The library's files, behind one small trait.
//!
//! Phase 1 keeps the library in the app's own storage, where `std::fs` reaches
//! everything (`FsVault`). A folder the person picks on Android is reached
//! through the Storage Access Framework instead, whose files have no paths: it
//! will be a second `Vault` over the same calls, and nothing above this trait
//! will know which one it is using. So every read and write of a note goes
//! through here, with relative paths (`Work/AttackFM.md`, forward slashes
//! everywhere).

use std::io;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use crate::note::ms_since_epoch;

/// A markdown file in the library.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    /// Relative to the library, with forward slashes.
    pub path: String,
    /// Milliseconds since the epoch.
    pub modified_ms: i64,
    pub size: u64,
}

pub trait Vault: Send {
    /// Every `.md` file under the library, at any depth, except inside dot folders (`.glyph`, `.obsidian`, `.git`).
    fn markdown(&self) -> io::Result<Vec<Entry>>;
    fn read(&self, path: &str) -> io::Result<String>;
    /// Writes the whole file, creating its folders; a reader never sees half of it. Answers its new stat.
    fn write(&self, path: &str, text: &str) -> io::Result<Entry>;
    fn rename(&self, from: &str, to: &str) -> io::Result<()>;
    fn remove(&self, path: &str) -> io::Result<()>;
    fn exists(&self, path: &str) -> bool;
    fn stat(&self, path: &str) -> io::Result<Entry>;
    /// Sets the file's modified time (a front-matter-only change is not an edit), answering its stat.
    fn keep_modified(&self, path: &str, modified_ms: i64) -> io::Result<Entry>;
    /// The `.glyph` folder as a real path, for the index and what isn't text.
    fn glyph_dir(&self) -> PathBuf;
}

pub struct FsVault {
    root: PathBuf,
}

impl FsVault {
    pub fn new(root: &Path) -> io::Result<FsVault> {
        std::fs::create_dir_all(root.join(".glyph"))?;
        Ok(FsVault { root: root.to_path_buf() })
    }

    fn at(&self, path: &str) -> io::Result<PathBuf> {
        // A path from the index or the page, never trusted to stay inside the library.
        if path.split('/').any(|part| part == ".." || part.is_empty()) || path.starts_with('/') {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, format!("not a library path: {path}")));
        }
        Ok(self.root.join(path))
    }

    fn entry(&self, path: &str, full: &Path) -> io::Result<Entry> {
        let meta = std::fs::metadata(full)?;
        let modified_ms = meta.modified().ok().map_or(0, ms_since_epoch);
        Ok(Entry { path: path.to_string(), modified_ms, size: meta.len() })
    }

    fn walk(&self, dir: &Path, prefix: &str, out: &mut Vec<Entry>) -> io::Result<()> {
        for item in std::fs::read_dir(dir)? {
            let item = item?;
            let name = item.file_name().to_string_lossy().to_string();
            if name.starts_with('.') {
                continue;
            }
            let rel = if prefix.is_empty() { name.clone() } else { format!("{prefix}/{name}") };
            let kind = item.file_type()?;
            if kind.is_dir() {
                self.walk(&item.path(), &rel, out)?;
            } else if kind.is_file() && name.to_ascii_lowercase().ends_with(".md") {
                out.push(self.entry(&rel, &item.path())?);
            }
        }
        Ok(())
    }
}

impl Vault for FsVault {
    fn markdown(&self) -> io::Result<Vec<Entry>> {
        let mut out = Vec::new();
        self.walk(&self.root, "", &mut out)?;
        out.sort_by(|a, b| a.path.cmp(&b.path));
        Ok(out)
    }

    fn read(&self, path: &str) -> io::Result<String> {
        std::fs::read_to_string(self.at(path)?)
    }

    fn write(&self, path: &str, text: &str) -> io::Result<Entry> {
        let full = self.at(path)?;
        if let Some(parent) = full.parent() {
            std::fs::create_dir_all(parent)?;
        }
        // Whole or not at all, through a hidden file beside it (which `walk` skips).
        crate::fsx::write_atomically(&full, text.as_bytes())?;
        self.entry(path, &full)
    }

    fn rename(&self, from: &str, to: &str) -> io::Result<()> {
        let target = self.at(to)?;
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::rename(self.at(from)?, target)
    }

    fn remove(&self, path: &str) -> io::Result<()> {
        crate::fsx::remove_file_if_present(&self.at(path)?)
    }

    fn exists(&self, path: &str) -> bool {
        self.at(path).map(|p| p.exists()).unwrap_or(false)
    }

    fn stat(&self, path: &str) -> io::Result<Entry> {
        let full = self.at(path)?;
        self.entry(path, &full)
    }

    fn keep_modified(&self, path: &str, modified_ms: i64) -> io::Result<Entry> {
        let full = self.at(path)?;
        let when = UNIX_EPOCH + std::time::Duration::from_millis(modified_ms.max(0) as u64);
        std::fs::File::options().write(true).open(&full)?.set_modified(when)?;
        self.entry(path, &full)
    }

    fn glyph_dir(&self) -> PathBuf {
        self.root.join(".glyph")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("glyph-vault-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn the_notes_are_every_markdown_file_but_those_in_dot_folders() {
        let root = temp();
        let vault = FsVault::new(&root).unwrap();
        for file in ["Inbox/a.md", "Work/Deep/b.MD", ".obsidian/c.md", "Work/.trash/d.md", ".hidden.md", "notes.txt"] {
            std::fs::create_dir_all(root.join(file).parent().unwrap()).unwrap();
            std::fs::write(root.join(file), "x").unwrap();
        }
        let paths: Vec<String> = vault.markdown().unwrap().into_iter().map(|entry| entry.path).collect();
        assert_eq!(paths, ["Inbox/a.md", "Work/Deep/b.MD"], "sorted, forward slashes, any case of .md");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_write_or_a_rename_makes_the_folders_it_needs() {
        let root = temp();
        let vault = FsVault::new(&root).unwrap();
        let written = vault.write("Work/Trips/Hello.md", "# Hello\n").unwrap();
        assert_eq!((written.path.as_str(), written.size), ("Work/Trips/Hello.md", 8));
        vault.rename("Work/Trips/Hello.md", "Archive/2026/Hello.md").unwrap();
        assert!(!vault.exists("Work/Trips/Hello.md"));
        assert_eq!(vault.read("Archive/2026/Hello.md").unwrap(), "# Hello\n");
        vault.remove("Archive/2026/Hello.md").unwrap();
        vault.remove("Archive/2026/Hello.md").unwrap();
        assert!(!vault.exists("../outside.md") && !vault.exists("/etc/hosts"), "a path outside is never there");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_kept_modified_time_is_the_one_asked_for() {
        let root = temp();
        let vault = FsVault::new(&root).unwrap();
        vault.write("a.md", "words").unwrap();
        let kept = vault.keep_modified("a.md", 1_789_381_930_123).unwrap();
        assert_eq!(kept.modified_ms, 1_789_381_930_123);
        assert_eq!(vault.stat("a.md").unwrap(), kept);
        let _ = std::fs::remove_dir_all(&root);
    }
}
