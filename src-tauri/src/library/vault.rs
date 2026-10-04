//! The library's files, behind one small trait.
//!
//! In the app's own storage, and in a folder chosen on the Mac, `std::fs`
//! reaches everything (`FsVault`). A folder chosen on Android is reached
//! through the Storage Access Framework instead, whose files have no paths:
//! that is the second `Vault`, tree.rs's `TreeVault`, over the same calls, and
//! nothing above this trait knows which one it is using. So every read and
//! write of a note goes through here, with relative paths (`Work/AttackFM.md`,
//! forward slashes everywhere).
//!
//! A FOLDER IN iCLOUD DRIVE (docs/DESIGN.md §185). A Mac with "Optimise Mac
//! Storage" on takes a file it has not opened lately off the disk and leaves
//! `.Note.md.icloud` in its place: a dot file, which the walk skipped, so the
//! note looked deleted and the next scan dropped its row. Now the placeholder
//! answers for the note (`Entry::evicted`): the list keeps the row it had, a
//! new name never takes it, a read asks iCloud for the file and waits a little,
//! and what still has not come down is `NotDownloaded`, which the library keeps
//! showing from its index and never writes over.

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
    /// In iCloud Drive and not on this Mac (`.Note.md.icloud`): there are no words here to read, and the time is the
    /// placeholder's, so the index keeps what it had.
    pub evicted: bool,
}

/// What a read of a note iCloud has not brought down answers with: the note is there, its words are not.
#[derive(Debug)]
pub struct NotDownloaded(pub String);

impl std::fmt::Display for NotDownloaded {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} is in iCloud Drive and not on this Mac yet. It is downloading: try again in a moment", self.0)
    }
}

impl std::error::Error for NotDownloaded {}

/// Whether `error` is a note whose words have not come down from iCloud (`NotDownloaded`).
pub fn not_downloaded(error: &io::Error) -> bool {
    error.get_ref().is_some_and(|inner| inner.is::<NotDownloaded>())
}

/// `Note.md` for `.Note.md.icloud`: the note iCloud's placeholder stands for, when it stands for a note.
fn evicted_name(name: &str) -> Option<&str> {
    name.strip_prefix('.').and_then(|n| n.strip_suffix(".icloud")).filter(|real| real.to_ascii_lowercase().ends_with(".md") && !real.starts_with('.'))
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
    /// The `.glyph` folder as a real path, for what isn't text (and the index, in the app's own folder).
    fn glyph_dir(&self) -> PathBuf;
    /// The library's folder, where it has a path: the Mac's Reveal and the export walk it. None through SAF.
    fn folder(&self) -> Option<PathBuf> {
        None
    }
    /// Asks for a note that is not on this device yet (`Entry::evicted`) to be brought down. Nothing by default.
    fn fetch(&self, _path: &str) {}
}

/// How long a read waits for iCloud to bring a note down before it says the note is not here yet. Short: every
/// command the app makes waits on the library meanwhile.
const EVICTED_WAIT_MS: u64 = 3_000;

pub struct FsVault {
    root: PathBuf,
    /// The placeholders iCloud was already asked to bring down in this process, so a scan on every list does not
    /// ask again for each.
    asked: std::sync::Mutex<std::collections::HashSet<PathBuf>>,
}

impl FsVault {
    pub fn new(root: &Path) -> io::Result<FsVault> {
        std::fs::create_dir_all(root.join(".glyph"))?;
        Ok(FsVault { root: root.to_path_buf(), asked: Default::default() })
    }

    /// A folder looked into and not yet taken: nothing is made in it, not even `.glyph/`, so a folder the person
    /// picks and then thinks better of is left exactly as it was.
    pub fn looking(root: &Path) -> FsVault {
        FsVault { root: root.to_path_buf(), asked: Default::default() }
    }

    fn at(&self, path: &str) -> io::Result<PathBuf> {
        // A path from the index or the page, never trusted to stay inside the library.
        if path.split('/').any(|part| part == ".." || part.is_empty()) || path.starts_with('/') {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, format!("not a library path: {path}")));
        }
        Ok(self.root.join(path))
    }

    /// `Work/.Note.md.icloud` for `Work/Note.md`: where iCloud leaves its placeholder for the file.
    fn placeholder(full: &Path) -> Option<PathBuf> {
        let name = full.file_name()?.to_str()?;
        Some(full.with_file_name(format!(".{name}.icloud")))
    }

    /// The placeholder standing for `full`, while the file itself is not there and iCloud's stand-in is.
    fn evicted(full: &Path) -> Option<PathBuf> {
        if full.exists() {
            return None;
        }
        Self::placeholder(full).filter(|p| p.is_file())
    }

    /// Asks iCloud to bring the file down, once per process: `brctl download`, which every Mac has. Not from a
    /// test, and not elsewhere, where there is no iCloud to ask.
    fn ask_for(&self, full: &Path) {
        if !crate::lock::lock(&self.asked).insert(full.to_path_buf()) {
            return;
        }
        #[cfg(all(target_os = "macos", not(test)))]
        {
            let _ = std::process::Command::new("/usr/bin/brctl")
                .arg("download")
                .arg(full)
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn();
        }
    }

    /// A note iCloud took off the disk, asked for and waited on for a moment: its words, or `NotDownloaded`.
    fn read_evicted(&self, path: &str, full: &Path) -> io::Result<String> {
        self.ask_for(full);
        let until = std::time::Instant::now() + std::time::Duration::from_millis(if cfg!(test) { 200 } else { EVICTED_WAIT_MS });
        while std::time::Instant::now() < until {
            if full.is_file() {
                return std::fs::read_to_string(full);
            }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        Err(io::Error::other(NotDownloaded(path.to_string())))
    }

    fn entry(&self, path: &str, full: &Path) -> io::Result<Entry> {
        if let Some(placeholder) = Self::evicted(full) {
            let meta = std::fs::metadata(placeholder)?;
            return Ok(Entry { path: path.to_string(), modified_ms: meta.modified().ok().map_or(0, ms_since_epoch), size: 0, evicted: true });
        }
        let meta = std::fs::metadata(full)?;
        let modified_ms = meta.modified().ok().map_or(0, ms_since_epoch);
        Ok(Entry { path: path.to_string(), modified_ms, size: meta.len(), evicted: false })
    }

    fn walk(&self, dir: &Path, prefix: &str, out: &mut Vec<Entry>) -> io::Result<()> {
        for item in std::fs::read_dir(dir)? {
            let item = item?;
            let name = item.file_name().to_string_lossy().to_string();
            if name.starts_with('.') {
                // iCloud's stand-in for a note it took off this Mac is the note, until the file itself is back.
                if let Some(real) = evicted_name(&name) {
                    if item.file_type()?.is_file() && !dir.join(real).exists() {
                        let rel = if prefix.is_empty() { real.to_string() } else { format!("{prefix}/{real}") };
                        out.push(self.entry(&rel, &dir.join(real))?);
                    }
                }
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
        let full = self.at(path)?;
        if Self::evicted(&full).is_some() {
            return self.read_evicted(path, &full);
        }
        std::fs::read_to_string(full)
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
        let source = self.at(from)?;
        // A note still in iCloud moves as its placeholder, which is how Finder moves one.
        if let (Some(placeholder), Some(moved)) = (Self::evicted(&source), Self::placeholder(&target)) {
            return std::fs::rename(placeholder, moved);
        }
        std::fs::rename(source, target)
    }

    fn remove(&self, path: &str) -> io::Result<()> {
        let full = self.at(path)?;
        // Its iCloud placeholder goes with it, or the note would come down again and be back in the list.
        if let Some(placeholder) = Self::evicted(&full) {
            crate::fsx::remove_file_if_present(&placeholder)?;
        }
        crate::fsx::remove_file_if_present(&full)
    }

    fn exists(&self, path: &str) -> bool {
        self.at(path).map(|p| p.exists() || Self::evicted(&p).is_some()).unwrap_or(false)
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

    fn folder(&self) -> Option<PathBuf> {
        Some(self.root.clone())
    }

    fn fetch(&self, path: &str) {
        if let Ok(full) = self.at(path) {
            self.ask_for(&full);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn the_notes_are_every_markdown_file_but_those_in_dot_folders() {
        let root = TempDir::new("vault");
        let vault = FsVault::new(&root).unwrap();
        for file in ["Inbox/a.md", "Work/Deep/b.MD", ".obsidian/c.md", "Work/.trash/d.md", ".hidden.md", "notes.txt"] {
            std::fs::create_dir_all(root.join(file).parent().unwrap()).unwrap();
            std::fs::write(root.join(file), "x").unwrap();
        }
        let paths: Vec<String> = vault.markdown().unwrap().into_iter().map(|entry| entry.path).collect();
        assert_eq!(paths, ["Inbox/a.md", "Work/Deep/b.MD"], "sorted, forward slashes, any case of .md");
    }

    #[test]
    fn a_write_or_a_rename_makes_the_folders_it_needs() {
        let root = TempDir::new("vault");
        let vault = FsVault::new(&root).unwrap();
        let written = vault.write("Work/Trips/Hello.md", "# Hello\n").unwrap();
        assert_eq!((written.path.as_str(), written.size), ("Work/Trips/Hello.md", 8));
        vault.rename("Work/Trips/Hello.md", "Archive/2026/Hello.md").unwrap();
        assert!(!vault.exists("Work/Trips/Hello.md"));
        assert_eq!(vault.read("Archive/2026/Hello.md").unwrap(), "# Hello\n");
        vault.remove("Archive/2026/Hello.md").unwrap();
        vault.remove("Archive/2026/Hello.md").unwrap();
        assert!(!vault.exists("../outside.md") && !vault.exists("/etc/hosts"), "a path outside is never there");
    }

    #[test]
    fn a_note_icloud_took_off_the_mac_is_still_a_note() {
        let root = TempDir::new("vault-icloud");
        let vault = FsVault::new(&root).unwrap();
        std::fs::create_dir_all(root.join("Work")).unwrap();
        std::fs::write(root.join("Work/.Plan.md.icloud"), b"bplist00").unwrap();
        std::fs::write(root.join("Work/.photo.jpg.icloud"), b"bplist00").unwrap();
        std::fs::write(root.join("Here.md"), "words").unwrap();
        let entries = vault.markdown().unwrap();
        let listed: Vec<(&str, bool)> = entries.iter().map(|e| (e.path.as_str(), e.evicted)).collect();
        assert_eq!(listed, [("Here.md", false), ("Work/Plan.md", true)], "a note's placeholder is the note; a picture's is nothing");
        assert!(vault.exists("Work/Plan.md"), "so a new note never takes its name");
        assert!(vault.stat("Work/Plan.md").unwrap().evicted);
        // A test never runs brctl, so nothing brings it down and the wait ends in the error the library answers by
        // showing what its index has.
        let read = vault.read("Work/Plan.md").unwrap_err();
        assert!(not_downloaded(&read), "{read}");

        // Moved as its placeholder, and removed with it.
        vault.rename("Work/Plan.md", "Archive/Plan.md").unwrap();
        assert!(root.join("Archive/.Plan.md.icloud").exists() && !root.join("Work/.Plan.md.icloud").exists());
        vault.remove("Archive/Plan.md").unwrap();
        assert!(!vault.exists("Archive/Plan.md"));

        // Once the file is back, it is the file again.
        std::fs::write(root.join("Work/.Back.md.icloud"), b"bplist00").unwrap();
        std::fs::write(root.join("Work/Back.md"), "home").unwrap();
        assert!(vault.markdown().unwrap().iter().all(|e| !e.evicted));
        assert_eq!(vault.read("Work/Back.md").unwrap(), "home");
    }

    #[test]
    fn a_kept_modified_time_is_the_one_asked_for() {
        let root = TempDir::new("vault");
        let vault = FsVault::new(&root).unwrap();
        vault.write("a.md", "words").unwrap();
        let kept = vault.keep_modified("a.md", 1_789_381_930_123).unwrap();
        assert_eq!(kept.modified_ms, 1_789_381_930_123);
        assert_eq!(vault.stat("a.md").unwrap(), kept);
    }
}
