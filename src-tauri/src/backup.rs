//! Every note Ghost.md keeps, backed up as plain files onto a removable drive (docs/DESIGN.md §204). Matt: "add a
//! section to the settings called "Backup" it should prompt the user to plugin a removable drive to backup all the
//! notes in the app to workspace folders and such under a Ghost.md folder on the root of the drive".
//!
//! Not the export (export.rs), which makes one zip to carry away: a backup is a folder anyone can open, kept up to
//! date by the next backup to the same drive.
//!
//! ```text
//! <the drive>/Ghost.md/
//!   README.txt                what this is (the page writes it)
//!   .ghostmd-backup.json      when, and what each file was when it was written
//!   Inbox/  Workspaces/<name>/  Organizations/<name>/   the notes, as the library files them, with each
//!                                                       one's .versions file beside it
//!   Attachments/Pictures/  Attachments/Films/  Attachments/Recordings/
//! ```
//!
//! A second backup to the same drive writes only what changed since the first: the manifest says what each file was
//! when it was written (a note by a hash of its words, a picture by its size and time), and a file the drive still
//! holds at that size is left alone. A note gone from the app since is taken off the drive, but only a file this
//! backup wrote: nothing else in `Ghost.md/`, and nothing outside it, is ever touched.
//!
//! The drive is a `Target`: a folder on the Mac's `/Volumes` (`FolderTarget`), or on Android the drive's own tree,
//! reached through the Storage Access Framework (saf.rs `TreeTarget`). No Tauri type here, so the tests run on any
//! machine.

use std::collections::BTreeMap;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Instant, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

/// The folder the backup keeps on the drive's root.
pub const FOLDER: &str = "Ghost.md";
/// What the last backup wrote, inside `FOLDER`.
pub const MANIFEST: &str = ".ghostmd-backup.json";
/// The README, inside `FOLDER`.
pub const README: &str = "README.txt";

/// Where a backup is written: paths are relative to the drive's root, with forward slashes.
pub trait Target {
    /// A file's size, or `None` where there is none.
    fn size(&self, path: &str) -> io::Result<Option<u64>>;
    /// A file's words, or `None` where there is none.
    fn read_text(&self, path: &str) -> io::Result<Option<String>>;
    /// The whole file, its folders made.
    fn write_text(&self, path: &str, text: &str) -> io::Result<()>;
    /// `source` copied whole to `path`, its folders made.
    fn copy_file(&self, path: &str, source: &Path) -> io::Result<()>;
    /// A file gone; one already gone is no error.
    fn remove(&self, path: &str) -> io::Result<()>;
}

/// What one file of the backup holds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Body {
    /// A note or its versions file, by its words.
    Text(String),
    /// A picture, film or recording, copied from where the app keeps it.
    File { source: PathBuf, size: u64, modified_ms: i64 },
}

/// One file of the backup, by its path under `FOLDER`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    pub path: String,
    pub body: Body,
}

impl Item {
    fn size(&self) -> u64 {
        match &self.body {
            Body::Text(text) => text.len() as u64,
            Body::File { size, .. } => *size,
        }
    }

    fn mark(&self) -> Mark {
        match &self.body {
            Body::Text(text) => Mark { size: text.len() as u64, hash: Some(format!("{:016x}", fnv1a(text.as_bytes()))), modified: None },
            Body::File { size, modified_ms, .. } => Mark { size: *size, hash: None, modified: Some(*modified_ms) },
        }
    }
}

/// What a file was when the backup wrote it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Mark {
    size: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    modified: Option<i64>,
}

/// `.ghostmd-backup.json`.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    #[serde(default)]
    app: String,
    #[serde(default)]
    backed_up_at: String,
    #[serde(default)]
    notes: usize,
    #[serde(default)]
    files: BTreeMap<String, Mark>,
}

/// The last backup a drive holds, as Settings says it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Last {
    pub backed_up_at: String,
    pub notes: usize,
}

/// How far a backup has got: bytes and files.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub done: u64,
    pub total: u64,
    pub files: usize,
    pub of: usize,
}

/// What a backup did.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Backed {
    /// Notes on the drive now.
    pub notes: usize,
    /// Every file the backup holds, notes, versions and media.
    pub files: usize,
    /// Written this time.
    pub written: usize,
    /// Left as they were, already the same on the drive.
    pub unchanged: usize,
    /// Taken off the drive, gone from the app since the last backup.
    pub removed: usize,
    /// Bytes written this time.
    pub bytes: u64,
}

/// 64-bit FNV-1a: a note's words told from another's, not a seal.
fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// Whether `path` may name a file under the drive's folder: relative, forward slashes, no `..`, no empty part.
pub fn checked(path: &str) -> io::Result<&str> {
    if path.is_empty() || path.starts_with('/') || path.contains('\\') || path.split('/').any(|part| part.is_empty() || part == "." || part == "..") {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, format!("not a backup path: {path}")));
    }
    Ok(path)
}

/// A note's path in the library as the drive has it: the library's own folders by the names Settings gives them
/// (`workspaces/Work/Plan.md` is `Workspaces/Work/Plan.md`, `orgs/Team/…` is `Organizations/Team/…`), and the rest
/// (`Inbox/…`, a folder of the person's own) as it is.
pub fn library_path(path: &str) -> String {
    if let Some(rest) = path.strip_prefix("workspaces/") {
        return format!("Workspaces/{rest}");
    }
    if let Some(rest) = path.strip_prefix("orgs/") {
        return format!("Organizations/{rest}");
    }
    path.to_string()
}

/// Whether a library path is a note, not its versions file: what the backup counts as notes.
fn is_note(path: &str) -> bool {
    path.to_ascii_lowercase().ends_with(".md")
}

/// The media folders the backup copies, each under `Attachments/` by the name it has there.
pub struct Media {
    pub dir: PathBuf,
    pub name: &'static str,
}

/// Every file of a backup: the library's notes and versions files (`texts`, as `Library::texts` answers them), then
/// each media folder's files, its own dot files and a write's temporary file left out. A media folder that is not
/// there yet is nothing to copy.
pub fn plan(texts: Vec<(String, String)>, media: &[Media]) -> io::Result<Vec<Item>> {
    let mut items = Vec::with_capacity(texts.len());
    for (path, text) in texts {
        let path = library_path(&path);
        if checked(&path).is_err() {
            continue;
        }
        items.push(Item { path, body: Body::Text(text) });
    }
    for folder in media {
        let mut found = Vec::new();
        walk(&folder.dir, &folder.dir, &mut found)?;
        found.sort();
        for (relative, source) in found {
            let meta = std::fs::metadata(&source)?;
            let modified_ms = meta.modified().ok().and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_millis() as i64).unwrap_or(0);
            let path = format!("Attachments/{}/{relative}", folder.name);
            if checked(&path).is_err() {
                continue;
            }
            items.push(Item { path, body: Body::File { source, size: meta.len(), modified_ms } });
        }
    }
    Ok(items)
}

/// Every file under `dir`, by its path from `root`, with no dot file or dot folder, nor a `.tmp` a write left.
fn walk(root: &Path, dir: &Path, out: &mut Vec<(String, PathBuf)>) -> io::Result<()> {
    let entries = match std::fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e),
    };
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') || name.ends_with(".tmp") {
            continue;
        }
        let path = entry.path();
        let kind = entry.file_type()?;
        if kind.is_dir() {
            walk(root, &path, out)?;
        } else if kind.is_file() {
            let relative = path.strip_prefix(root).map_err(io::Error::other)?.to_string_lossy().replace('\\', "/");
            out.push((relative, path));
        }
    }
    Ok(())
}

fn in_folder(path: &str) -> String {
    format!("{FOLDER}/{path}")
}

/// The manifest the last backup left on the drive; none, or one that will not read, is an empty one: every file is
/// then written again, and nothing is taken off.
fn last_manifest(target: &dyn Target) -> Manifest {
    match target.read_text(&in_folder(MANIFEST)) {
        Ok(Some(text)) => serde_json::from_str(&text).unwrap_or_default(),
        _ => Manifest::default(),
    }
}

/// The last backup `target` holds, if it holds one.
pub fn last(target: &dyn Target) -> Option<Last> {
    let manifest = last_manifest(target);
    if manifest.backed_up_at.is_empty() {
        return None;
    }
    Some(Last { backed_up_at: manifest.backed_up_at, notes: manifest.notes })
}

/// Bytes still to write: what the drive does not already hold as the manifest says.
fn owed(target: &dyn Target, items: &[Item], before: &Manifest) -> io::Result<Vec<bool>> {
    items
        .iter()
        .map(|item| {
            let mark = item.mark();
            if before.files.get(&item.path) != Some(&mark) {
                return Ok(true);
            }
            Ok(target.size(&in_folder(&item.path))? != Some(mark.size))
        })
        .collect()
}

/// The backup itself: every item written to `target` under `FOLDER` that the drive does not already hold, the files
/// the last backup wrote and the app no longer has taken off, then the README and the manifest last, so a backup
/// stopped part way leaves the last manifest saying only what is true of the files it names. `free` is the drive's
/// room, when known: a backup that cannot fit is refused before it writes anything.
pub fn run(
    target: &dyn Target,
    items: &[Item],
    readme: &str,
    backed_up_at: &str,
    free: Option<u64>,
    cancel: &AtomicBool,
    mut progress: impl FnMut(Progress),
) -> io::Result<Backed> {
    for item in items {
        checked(&item.path)?;
    }
    let before = last_manifest(target);
    let owed = owed(target, items, &before)?;
    let total: u64 = items.iter().zip(&owed).filter(|(_, owed)| **owed).map(|(item, _)| item.size()).sum();
    if let Some(free) = free {
        // Room for what is owed and a little over, for the folders and the manifest.
        if total.saturating_add(1 << 20) > free {
            return Err(io::Error::new(io::ErrorKind::StorageFull, format!("The drive has {} free, and the backup needs {}.", said(free), said(total))));
        }
    }
    let of = owed.iter().filter(|owed| **owed).count();
    let mut done = 0u64;
    let mut written = 0usize;
    let mut last_said = Instant::now();
    progress(Progress { done, total, files: 0, of });
    for (item, owed) in items.iter().zip(&owed) {
        if !owed {
            continue;
        }
        if cancel.load(Ordering::SeqCst) {
            return Err(io::Error::new(io::ErrorKind::Interrupted, "The backup was stopped."));
        }
        let path = in_folder(&item.path);
        match &item.body {
            Body::Text(text) => target.write_text(&path, text)?,
            Body::File { source, .. } => target.copy_file(&path, source)?,
        }
        done += item.size();
        written += 1;
        if last_said.elapsed().as_millis() >= 150 {
            progress(Progress { done, total, files: written, of });
            last_said = Instant::now();
        }
    }
    let now: BTreeMap<String, Mark> = items.iter().map(|item| (item.path.clone(), item.mark())).collect();
    let mut removed = 0usize;
    for path in before.files.keys() {
        if now.contains_key(path) || checked(path).is_err() {
            continue;
        }
        target.remove(&in_folder(path))?;
        removed += 1;
    }
    let notes = items.iter().filter(|item| matches!(item.body, Body::Text(_)) && is_note(&item.path)).count();
    target.write_text(&in_folder(README), readme)?;
    let manifest = Manifest { app: "Ghost.md".into(), backed_up_at: backed_up_at.to_string(), notes, files: now };
    let text = serde_json::to_string_pretty(&manifest).map_err(io::Error::other)?;
    target.write_text(&in_folder(MANIFEST), &text)?;
    progress(Progress { done: total, total, files: written, of });
    Ok(Backed { notes, files: items.len(), written, unchanged: items.len() - written, removed, bytes: total })
}

/// Bytes as a person reads them.
pub fn said(bytes: u64) -> String {
    const UNITS: [&str; 4] = ["KB", "MB", "GB", "TB"];
    if bytes < 1000 {
        return format!("{bytes} bytes");
    }
    let mut value = bytes as f64 / 1000.0;
    let mut unit = 0;
    while value >= 1000.0 && unit < UNITS.len() - 1 {
        value /= 1000.0;
        unit += 1;
    }
    if value >= 100.0 { format!("{value:.0} {}", UNITS[unit]) } else { format!("{value:.1} {}", UNITS[unit]) }
}

/// A folder the backup goes into: on the Mac, a drive under `/Volumes`. Every write lands whole, through a temporary
/// file beside it and a rename, so a drive pulled out mid-write keeps the file it had.
pub struct FolderTarget {
    pub root: PathBuf,
}

impl FolderTarget {
    fn at(&self, path: &str) -> io::Result<PathBuf> {
        Ok(self.root.join(checked(path)?))
    }

    fn landed(&self, path: &str, write: impl FnOnce(&Path) -> io::Result<()>) -> io::Result<()> {
        let to = self.at(path)?;
        if let Some(parent) = to.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let name = to.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let temporary = to.with_file_name(format!(".{name}.ghostmd.tmp"));
        let result = write(&temporary).and_then(|()| std::fs::rename(&temporary, &to));
        if result.is_err() {
            let _ = std::fs::remove_file(&temporary);
        }
        result
    }
}

impl Target for FolderTarget {
    fn size(&self, path: &str) -> io::Result<Option<u64>> {
        match std::fs::metadata(self.at(path)?) {
            Ok(meta) if meta.is_file() => Ok(Some(meta.len())),
            Ok(_) => Ok(None),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e),
        }
    }

    fn read_text(&self, path: &str) -> io::Result<Option<String>> {
        match std::fs::read_to_string(self.at(path)?) {
            Ok(text) => Ok(Some(text)),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e),
        }
    }

    fn write_text(&self, path: &str, text: &str) -> io::Result<()> {
        self.landed(path, |temporary| std::fs::write(temporary, text))
    }

    fn copy_file(&self, path: &str, source: &Path) -> io::Result<()> {
        self.landed(path, |temporary| std::fs::copy(source, temporary).map(drop))
    }

    fn remove(&self, path: &str) -> io::Result<()> {
        match std::fs::remove_file(self.at(path)?) {
            Err(e) if e.kind() != io::ErrorKind::NotFound => Err(e),
            _ => Ok(()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;

    /// A drive in memory, counting what was written to it.
    #[derive(Default)]
    struct Drive {
        files: RefCell<HashMap<String, Vec<u8>>>,
        writes: RefCell<Vec<String>>,
    }

    impl Target for Drive {
        fn size(&self, path: &str) -> io::Result<Option<u64>> {
            Ok(self.files.borrow().get(path).map(|bytes| bytes.len() as u64))
        }
        fn read_text(&self, path: &str) -> io::Result<Option<String>> {
            Ok(self.files.borrow().get(path).map(|bytes| String::from_utf8_lossy(bytes).into_owned()))
        }
        fn write_text(&self, path: &str, text: &str) -> io::Result<()> {
            self.writes.borrow_mut().push(path.to_string());
            self.files.borrow_mut().insert(path.to_string(), text.as_bytes().to_vec());
            Ok(())
        }
        fn copy_file(&self, path: &str, source: &Path) -> io::Result<()> {
            self.writes.borrow_mut().push(path.to_string());
            self.files.borrow_mut().insert(path.to_string(), std::fs::read(source)?);
            Ok(())
        }
        fn remove(&self, path: &str) -> io::Result<()> {
            self.files.borrow_mut().remove(path);
            Ok(())
        }
    }

    fn texts(pairs: &[(&str, &str)]) -> Vec<(String, String)> {
        pairs.iter().map(|(p, t)| (p.to_string(), t.to_string())).collect()
    }

    fn back_up(drive: &Drive, items: &[Item]) -> Backed {
        run(drive, items, "readme", "2026-10-05T19:30:00Z", None, &AtomicBool::new(false), |_| {}).unwrap()
    }

    #[test]
    fn names_the_library_folders_as_settings_does() {
        assert_eq!(library_path("workspaces/Work/Plan.md"), "Workspaces/Work/Plan.md");
        assert_eq!(library_path("orgs/HelloTrade/Board.md"), "Organizations/HelloTrade/Board.md");
        assert_eq!(library_path("Inbox/Note.md"), "Inbox/Note.md");
        assert_eq!(library_path("Recipes/Soup.md"), "Recipes/Soup.md");
    }

    #[test]
    fn refuses_a_path_that_could_leave_the_folder() {
        for bad in ["", "/etc/passwd", "../up.md", "a//b.md", "a/./b.md", "a\\b.md"] {
            assert!(checked(bad).is_err(), "{bad}");
        }
        assert!(checked("Workspaces/Work/Plan.md").is_ok());
    }

    #[test]
    fn writes_every_note_under_the_folder_with_its_readme_and_manifest() {
        let drive = Drive::default();
        let items = plan(texts(&[("Inbox/A.md", "# A"), ("Inbox/A.versions", "v1"), ("workspaces/Work/B.md", "# B")]), &[]).unwrap();
        let backed = back_up(&drive, &items);
        assert_eq!(backed, Backed { notes: 2, files: 3, written: 3, unchanged: 0, removed: 0, bytes: 3 + 2 + 3 });
        let files = drive.files.borrow();
        assert_eq!(files.get("Ghost.md/Inbox/A.md").map(Vec::as_slice), Some(&b"# A"[..]));
        assert!(files.contains_key("Ghost.md/Inbox/A.versions"));
        assert!(files.contains_key("Ghost.md/Workspaces/Work/B.md"));
        assert!(files.contains_key("Ghost.md/README.txt"));
        assert_eq!(last(&drive), Some(Last { backed_up_at: "2026-10-05T19:30:00Z".into(), notes: 2 }));
    }

    #[test]
    fn writes_only_what_changed_the_next_time_and_takes_off_what_is_gone() {
        let drive = Drive::default();
        back_up(&drive, &plan(texts(&[("Inbox/A.md", "# A"), ("Inbox/B.md", "# B"), ("Inbox/C.md", "# C")]), &[]).unwrap());
        drive.writes.borrow_mut().clear();
        let backed = back_up(&drive, &plan(texts(&[("Inbox/A.md", "# A"), ("Inbox/B.md", "# B, longer now")]), &[]).unwrap());
        assert_eq!((backed.written, backed.unchanged, backed.removed), (1, 1, 1));
        let writes = drive.writes.borrow();
        assert!(writes.contains(&"Ghost.md/Inbox/B.md".to_string()));
        assert!(!writes.contains(&"Ghost.md/Inbox/A.md".to_string()));
        assert!(!drive.files.borrow().contains_key("Ghost.md/Inbox/C.md"));
    }

    #[test]
    fn never_takes_off_a_file_it_did_not_write() {
        let drive = Drive::default();
        drive.files.borrow_mut().insert("Ghost.md/Mine.txt".into(), b"the person's own".to_vec());
        drive.files.borrow_mut().insert("Photos/beach.jpg".into(), b"jpg".to_vec());
        back_up(&drive, &plan(texts(&[("Inbox/A.md", "# A")]), &[]).unwrap());
        back_up(&drive, &plan(Vec::new(), &[]).unwrap());
        let files = drive.files.borrow();
        assert!(files.contains_key("Ghost.md/Mine.txt"));
        assert!(files.contains_key("Photos/beach.jpg"));
        assert!(!files.contains_key("Ghost.md/Inbox/A.md"));
    }

    #[test]
    fn writes_again_a_file_the_drive_lost_or_that_changed_there() {
        let drive = Drive::default();
        let items = plan(texts(&[("Inbox/A.md", "# A"), ("Inbox/B.md", "# B")]), &[]).unwrap();
        back_up(&drive, &items);
        drive.files.borrow_mut().remove("Ghost.md/Inbox/A.md");
        drive.files.borrow_mut().insert("Ghost.md/Inbox/B.md".into(), b"# B, edited on the drive".to_vec());
        let backed = back_up(&drive, &items);
        assert_eq!(backed.written, 2);
        assert_eq!(drive.files.borrow().get("Ghost.md/Inbox/B.md").map(Vec::as_slice), Some(&b"# B"[..]));
    }

    #[test]
    fn copies_the_media_under_attachments_and_skips_dot_files() {
        let dir = std::env::temp_dir().join(format!("glyph-backup-media-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("images/sub")).unwrap();
        std::fs::write(dir.join("images/a.png"), b"png").unwrap();
        std::fs::write(dir.join("images/sub/b.jpg"), b"jpeg").unwrap();
        std::fs::write(dir.join("images/.hidden"), b"x").unwrap();
        std::fs::write(dir.join("images/c.png.tmp"), b"x").unwrap();
        let items = plan(Vec::new(), &[Media { dir: dir.join("images"), name: "Pictures" }, Media { dir: dir.join("nowhere"), name: "Films" }]).unwrap();
        let paths: Vec<&str> = items.iter().map(|item| item.path.as_str()).collect();
        assert_eq!(paths, ["Attachments/Pictures/a.png", "Attachments/Pictures/sub/b.jpg"]);
        let drive = Drive::default();
        let backed = back_up(&drive, &items);
        assert_eq!((backed.notes, backed.files), (0, 2));
        assert_eq!(drive.files.borrow().get("Ghost.md/Attachments/Pictures/sub/b.jpg").map(Vec::as_slice), Some(&b"jpeg"[..]));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn refuses_a_backup_the_drive_has_no_room_for_before_writing_anything() {
        let drive = Drive::default();
        let items = plan(texts(&[("Inbox/A.md", &"x".repeat(2_000_000))]), &[]).unwrap();
        let error = run(&drive, &items, "readme", "now", Some(1_500_000), &AtomicBool::new(false), |_| {}).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::StorageFull);
        assert!(drive.files.borrow().is_empty());
    }

    #[test]
    fn stops_between_files_and_leaves_the_last_manifest() {
        let drive = Drive::default();
        back_up(&drive, &plan(texts(&[("Inbox/A.md", "# A")]), &[]).unwrap());
        let error = run(&drive, &plan(texts(&[("Inbox/A.md", "# A2"), ("Inbox/B.md", "# B")]), &[]).unwrap(), "readme", "later", None, &AtomicBool::new(true), |_| {}).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert_eq!(last(&drive).map(|l| l.backed_up_at), Some("2026-10-05T19:30:00Z".to_string()));
    }

    #[test]
    fn a_folder_target_writes_whole_files_and_leaves_no_temporary_one() {
        let root = std::env::temp_dir().join(format!("glyph-backup-folder-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let target = FolderTarget { root: root.clone() };
        target.write_text("Ghost.md/Inbox/A.md", "# A").unwrap();
        assert_eq!(target.size("Ghost.md/Inbox/A.md").unwrap(), Some(3));
        assert_eq!(target.read_text("Ghost.md/Inbox/A.md").unwrap().as_deref(), Some("# A"));
        let names: Vec<String> = std::fs::read_dir(root.join("Ghost.md/Inbox")).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        assert_eq!(names, ["A.md"]);
        target.remove("Ghost.md/Inbox/A.md").unwrap();
        target.remove("Ghost.md/Inbox/A.md").unwrap();
        assert_eq!(target.size("Ghost.md/Inbox/A.md").unwrap(), None);
        assert!(target.write_text("../escape.md", "x").is_err());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn says_sizes_as_a_person_reads_them() {
        assert_eq!(said(512), "512 bytes");
        assert_eq!(said(1_500), "1.5 KB");
        assert_eq!(said(2_740_937_888), "2.7 GB");
    }
}
