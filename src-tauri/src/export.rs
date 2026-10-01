//! Everything Ghost.md keeps, as one zip a person can carry away: every note as
//! its Markdown file in its folders, the pictures, films and recordings the
//! notes show and play, and the page's settings (docs/DESIGN.md §167).
//!
//! Matt: "Please add a feature that allows me to plug in a USB drive and export
//! the entire app onto a folder or zip file with ghostmarkdown_<datetime>.7z or
//! something". A zip rather than a 7z: a Mac, Windows, Android's Files app and
//! every Linux desktop open a zip with nothing installed, and a 7z needs an app
//! on all of them. Inside it is one folder of the archive's own name, so
//! opening it makes `ghostmarkdown_2026-10-01_21-42-05/` and not a scatter of
//! files beside the archive.
//!
//! ```text
//! ghostmarkdown_2026-10-01_21-42-05/
//!   README.txt          what this is and how to open it (the page writes it)
//!   manifest.json       when, from which app, and how many of each
//!   settings.json       the page's settings, without an account or a key
//!   Library/            the notes, as docs/LIBRARY.md has them, with .glyph's
//!                       phrases and library.json; not its index, a cache
//!   images/  video/  recordings/
//! ```
//!
//! What is left out is what the app can make again or must not carry: the
//! models (gigabytes, downloaded again), the index (rebuilt from the files),
//! a meeting's write-up under way, the over-the-air builds, and the Notion
//! token. A file being written as the export reads is read whole either way,
//! since the library writes through a temporary file and a rename
//! (fsx.rs `write_atomically`), and the temporary file itself is left out.
//!
//! The archive is written as a stream (no seek), so the same writer serves a
//! file the Mac's save panel chose and a document Android's picker made on a
//! USB drive, which arrives as a descriptor (export_commands.rs). Text is
//! deflated; pictures, films and recordings are stored as they are, since
//! they are compressed already or barely shrink. Zip64 takes over past 4 GB.
//!
//! No Tauri type here, so tools/host-tests runs these tests on any machine.

use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use serde::Serialize;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, DateTime, ZipWriter};

/// A folder of the app's data and the name it has in the archive.
pub struct Source {
    pub dir: PathBuf,
    pub name: &'static str,
}

/// A file the page wrote for the archive: the README and the settings.
pub struct Extra {
    pub name: String,
    pub bytes: Vec<u8>,
}

/// One file to copy in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub path: PathBuf,
    /// Its name in the archive, under the root folder: `Library/Inbox/Milk.md`.
    pub name: String,
    pub size: u64,
    pub modified: Option<SystemTime>,
}

/// How far an export has got, by bytes read and by files.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Progress {
    pub done: u64,
    pub total: u64,
    pub files: u64,
    pub of: u64,
}

/// What an export wrote.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Exported {
    /// The archive's name.
    pub name: String,
    /// Notes: the Markdown files in the library.
    pub notes: u64,
    /// Every file copied in, notes among them, the page's own files not.
    pub files: u64,
    /// Their bytes as they were.
    pub bytes: u64,
    /// The archive's bytes.
    pub written: u64,
}

/// What a person reads when an export is stopped.
pub const CANCELLED: &str = "The export was stopped.";

/// An archive's name as the page proposes it: `ghostmarkdown_` and a time, `.zip`, and nothing a drive cannot hold.
pub fn valid_name(name: &str) -> bool {
    let Some(stem) = name.strip_suffix(".zip") else { return false };
    !stem.is_empty()
        && stem.len() <= 96
        && stem.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
        && !stem.starts_with('.')
}

/// The folder inside the archive: its name without `.zip`.
pub fn root_of(name: &str) -> &str {
    name.strip_suffix(".zip").unwrap_or(name)
}

/// Whether a file under a source is left out: the library's index (a cache, with its journal files), and a write
/// still under way (fsx.rs's `.<32 hex>.tmp`, a download's `.part`).
fn left_out(source: &str, relative: &Path) -> bool {
    let name = relative.file_name().and_then(|n| n.to_str()).unwrap_or("");
    if name.ends_with(".part") {
        return true;
    }
    if let Some(hex) = name.strip_prefix('.').and_then(|n| n.strip_suffix(".tmp")) {
        if hex.len() == 32 && hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return true;
        }
    }
    source == "Library" && relative.starts_with(".glyph") && name.starts_with("index.sqlite")
}

/// Every file under the sources, in a stable order (each folder's names sorted), symbolic links and what is left out
/// skipped. A source that is not there is nothing to copy.
pub fn entries(sources: &[Source]) -> io::Result<Vec<Entry>> {
    let mut found = Vec::new();
    for source in sources {
        if !source.dir.is_dir() {
            continue;
        }
        walk(&source.dir, &source.dir, source.name, &mut found)?;
    }
    Ok(found)
}

fn walk(base: &Path, dir: &Path, source: &str, found: &mut Vec<Entry>) -> io::Result<()> {
    let mut children: Vec<_> = std::fs::read_dir(dir)?.filter_map(Result::ok).collect();
    children.sort_by_key(|child| child.file_name());
    for child in children {
        let kind = child.file_type()?;
        let path = child.path();
        if kind.is_symlink() {
            continue;
        }
        if kind.is_dir() {
            walk(base, &path, source, found)?;
            continue;
        }
        if !kind.is_file() {
            continue;
        }
        let relative = path.strip_prefix(base).unwrap_or(&path).to_path_buf();
        if left_out(source, &relative) {
            continue;
        }
        let Some(parts) = relative.iter().map(|part| part.to_str()).collect::<Option<Vec<_>>>() else {
            // A name that is not UTF-8 cannot be written into a zip as itself; such a file was not made by the app.
            continue;
        };
        let meta = child.metadata()?;
        found.push(Entry { path, name: format!("{source}/{}", parts.join("/")), size: meta.len(), modified: meta.modified().ok() });
    }
    Ok(())
}

/// Whether a file is worth deflating: words, not media.
fn deflated(name: &str) -> bool {
    let ext = name.rsplit_once('.').map(|(_, ext)| ext.to_ascii_lowercase()).unwrap_or_default();
    matches!(ext.as_str(), "md" | "markdown" | "txt" | "json" | "canvas" | "csv" | "svg" | "yaml" | "yml" | "html" | "css" | "js")
}

/// A time as a zip holds it: the local wall clock (`offset_minutes` east of UTC), two-second steps, 1980 to 2107.
pub fn zip_time(at: SystemTime, offset_minutes: i32) -> DateTime {
    let secs = at.duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0) + i64::from(offset_minutes) * 60;
    let (year, month, day) = civil_from_days(secs.div_euclid(86_400));
    let in_day = secs.rem_euclid(86_400);
    let (hour, minute, second) = ((in_day / 3600) as u8, ((in_day % 3600) / 60) as u8, (in_day % 60) as u8);
    if !(1980..=2107).contains(&year) {
        return DateTime::default();
    }
    DateTime::from_date_and_time(year as u16, month, day, hour, minute, second).unwrap_or_default()
}

/// Days since 1970-01-01 as a calendar date (Howard Hinnant's algorithm).
fn civil_from_days(days: i64) -> (i64, u8, u8) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u8;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u8;
    let year = yoe + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

/// Counts what passes through, so the archive's size is known without a seek.
struct Counted<W> {
    inner: W,
    count: u64,
}

impl<W: Write> Write for Counted<W> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let n = self.inner.write(buf)?;
        self.count += n as u64;
        Ok(n)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.inner.flush()
    }
}

/// An I/O failure as a person reads it: a drive too small, one formatted for files under 4 GB, one taken out.
pub fn said(error: &io::Error) -> String {
    match error.kind() {
        io::ErrorKind::StorageFull => "The drive is full.".into(),
        io::ErrorKind::FileTooLarge => {
            "The drive can’t hold a file this big. It is probably formatted as FAT32, which stops at 4 GB; a drive formatted as exFAT can hold it.".into()
        }
        io::ErrorKind::NotFound | io::ErrorKind::BrokenPipe => "The drive went away before the export finished.".into(),
        io::ErrorKind::PermissionDenied | io::ErrorKind::ReadOnlyFilesystem => "That drive can’t be written to.".into(),
        _ => format!("The export could not be written: {error}"),
    }
}

fn zip_said(error: zip::result::ZipError) -> String {
    match error {
        zip::result::ZipError::Io(error) => said(&error),
        other => format!("The export could not be written: {other}"),
    }
}

/// How often progress is said, at most.
const TELL_EVERY_MS: u128 = 200;
/// How much is read at a time, and how often a stop is looked for inside a large file.
const BLOCK: usize = 1 << 20;

/// Writes the archive to `out`: the page's files (`extras`) and a manifest first, then every entry. `cancel` is looked
/// at between blocks; `tell` hears how far it has got, a few times a second and once at the end.
#[allow(clippy::too_many_arguments)]
pub fn write<W: Write>(
    out: W,
    name: &str,
    entries: &[Entry],
    extras: &[Extra],
    manifest: &serde_json::Value,
    offset_minutes: i32,
    cancel: &AtomicBool,
    mut tell: impl FnMut(Progress),
) -> Result<Exported, String> {
    let root = root_of(name);
    let total: u64 = entries.iter().map(|e| e.size).sum();
    let notes = entries.iter().filter(|e| e.name.starts_with("Library/") && !e.name.starts_with("Library/.") && e.name.ends_with(".md") && !e.name.contains("/.")).count() as u64;
    let mut progress = Progress { done: 0, total, files: 0, of: entries.len() as u64 };
    let mut zip = ZipWriter::new_stream(Counted { inner: out, count: 0 });
    let now = zip_time(SystemTime::now(), offset_minutes);
    let text = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated).last_modified_time(now).unix_permissions(0o644);

    let mut manifest = manifest.clone();
    if let Some(object) = manifest.as_object_mut() {
        object.insert("notes".into(), notes.into());
        object.insert("files".into(), progress.of.into());
        object.insert("bytes".into(), total.into());
    }
    let manifest = serde_json::to_vec_pretty(&manifest).map_err(|e| e.to_string())?;
    for (file, bytes) in extras.iter().map(|e| (e.name.as_str(), e.bytes.as_slice())).chain([("manifest.json", manifest.as_slice())]) {
        zip.start_file(format!("{root}/{file}"), text).map_err(zip_said)?;
        zip.write_all(bytes).map_err(|e| said(&e))?;
    }

    let mut buffer = vec![0u8; BLOCK];
    let mut told = Instant::now();
    tell(progress);
    for entry in entries {
        if cancel.load(Ordering::Relaxed) {
            return Err(CANCELLED.into());
        }
        let options = SimpleFileOptions::default()
            .compression_method(if deflated(&entry.name) { CompressionMethod::Deflated } else { CompressionMethod::Stored })
            .last_modified_time(entry.modified.map(|at| zip_time(at, offset_minutes)).unwrap_or(now))
            .unix_permissions(0o644)
            .large_file(entry.size >= u64::from(u32::MAX));
        // A file that went since the list was made (a note deleted mid-export) is simply not there.
        let mut file = match std::fs::File::open(&entry.path) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                progress.done += entry.size;
                progress.files += 1;
                continue;
            }
            Err(error) => return Err(format!("{} could not be read: {error}", entry.name)),
        };
        zip.start_file(format!("{root}/{}", entry.name), options).map_err(zip_said)?;
        loop {
            let n = file.read(&mut buffer).map_err(|e| format!("{} could not be read: {e}", entry.name))?;
            if n == 0 {
                break;
            }
            zip.write_all(&buffer[..n]).map_err(|e| said(&e))?;
            progress.done += n as u64;
            if told.elapsed().as_millis() >= TELL_EVERY_MS {
                told = Instant::now();
                tell(progress);
            }
            if cancel.load(Ordering::Relaxed) {
                return Err(CANCELLED.into());
            }
        }
        progress.files += 1;
    }
    let mut counted = zip.finish().map_err(zip_said)?.into_inner();
    counted.flush().map_err(|e| said(&e))?;
    progress.done = progress.done.max(total);
    tell(progress);
    Ok(Exported { name: name.to_string(), notes, files: progress.of, bytes: total, written: counted.count })
}

/// What a person reads when a descriptor is not the picker's file.
#[cfg_attr(not(target_os = "android"), allow(dead_code))]
pub const NOT_THE_FILE: &str = "That isn’t the file the picker made.";

/// A descriptor Android's picker opened on the file it made, as a file this process owns; or why it is not one to
/// write to (export_commands.rs `export_fd`). Taken only when it is a new, empty, plain file outside the app's own
/// storage (`own`): a number passed by mistake, which named the index or a recording or a pipe of the WebView's, is
/// refused and left open, never written over or closed. Unix only, which Android is; Linux has the same
/// `/proc/self/fd`, so the tests run anywhere.
#[cfg(unix)]
#[cfg_attr(not(target_os = "android"), allow(dead_code))]
pub fn adopt_descriptor(fd: i32, own: &[PathBuf]) -> Result<std::fs::File, String> {
    use std::mem::ManuallyDrop;
    use std::os::fd::FromRawFd;
    if fd < 3 {
        return Err(NOT_THE_FILE.into());
    }
    // `/proc/self/fd` first: a number that names nothing is refused before anything is made of it.
    let target = std::fs::read_link(format!("/proc/self/fd/{fd}")).map_err(|_| NOT_THE_FILE.to_string())?;
    // Looked at without being owned: dropping this closes nothing.
    let peek = ManuallyDrop::new(unsafe { std::fs::File::from_raw_fd(fd) });
    let meta = peek.metadata().map_err(|_| NOT_THE_FILE.to_string())?;
    if !meta.is_file() {
        return Err("Ghost.md can export to a drive or a folder on this phone, not to that place.".into());
    }
    if meta.len() != 0 {
        return Err(NOT_THE_FILE.into());
    }
    for dir in own {
        let dir = std::fs::canonicalize(dir).unwrap_or_else(|_| dir.clone());
        if target.starts_with(&dir) {
            return Err(NOT_THE_FILE.into());
        }
    }
    Ok(ManuallyDrop::into_inner(peek))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use zip::ZipArchive;

    fn temp(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("glyph-export-{label}-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn put(dir: &Path, name: &str, bytes: &[u8]) {
        let path = dir.join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }

    fn data() -> PathBuf {
        let data = temp("data");
        put(&data, "Library/Inbox/Milk.md", b"# Milk\n\n- [ ] Oat\n");
        put(&data, "Library/workspaces/Work/AttackFM.md", "# AttackFM 日本\n".as_bytes());
        put(&data, "Library/.glyph/library.json", b"{\"version\":1}");
        put(&data, "Library/.glyph/notes/abc.json", b"{\"segments\":[]}");
        put(&data, "Library/.glyph/index.sqlite", b"cache");
        put(&data, "Library/.glyph/index.sqlite-wal", b"cache");
        put(&data, "Library/Inbox/.0123456789abcdef0123456789abcdef.tmp", b"half a save");
        put(&data, "images/2b0c.jpg", &[0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
        put(&data, "video/clip.mp4", &[0u8; 3000]);
        put(&data, "recordings/abc.wav", b"RIFF....WAVE");
        put(&data, "models/qwen.gguf", b"not exported");
        put(&data, "notion.json", b"{\"token\":\"secret\"}");
        data
    }

    fn sources(data: &Path) -> Vec<Source> {
        ["Library", "images", "video", "recordings"].into_iter().map(|name| Source { dir: data.join(name), name }).collect()
    }

    #[test]
    fn lists_every_kept_file_and_leaves_out_the_index_the_models_and_a_save_under_way() {
        let data = data();
        let names: Vec<_> = entries(&sources(&data)).unwrap().into_iter().map(|e| e.name).collect();
        assert_eq!(
            names,
            [
                "Library/.glyph/library.json",
                "Library/.glyph/notes/abc.json",
                "Library/Inbox/Milk.md",
                "Library/workspaces/Work/AttackFM.md",
                "images/2b0c.jpg",
                "video/clip.mp4",
                "recordings/abc.wav",
            ]
        );
        std::fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn writes_one_folder_of_the_archives_name_that_any_zip_reader_opens() {
        let data = data();
        let list = entries(&sources(&data)).unwrap();
        let extras = [Extra { name: "README.txt".into(), bytes: b"Ghost.md export".to_vec() }, Extra { name: "settings.json".into(), bytes: b"{}".to_vec() }];
        let mut heard = Vec::new();
        let mut out = Vec::new();
        let done = write(&mut out, "ghostmarkdown_2026-10-01_21-42-05.zip", &list, &extras, &serde_json::json!({ "app": "Ghost.md" }), 60, &AtomicBool::new(false), |p| heard.push(p)).unwrap();
        assert_eq!((done.notes, done.files, done.written), (2, 7, out.len() as u64));
        assert_eq!(heard.last().map(|p| (p.done, p.total, p.files, p.of)), Some((done.bytes, done.bytes, 7, 7)));

        let mut zip = ZipArchive::new(Cursor::new(out)).unwrap();
        let root = "ghostmarkdown_2026-10-01_21-42-05";
        let mut names: Vec<_> = zip.file_names().map(str::to_string).collect();
        names.sort();
        assert!(names.iter().all(|n| n.starts_with(&format!("{root}/"))), "{names:?}");
        for name in ["README.txt", "settings.json", "manifest.json", "Library/Inbox/Milk.md", "video/clip.mp4"] {
            assert!(names.contains(&format!("{root}/{name}")), "{name} missing from {names:?}");
        }
        let mut read = |name: &str| {
            let mut file = zip.by_name(&format!("{root}/{name}")).unwrap();
            let mut bytes = Vec::new();
            file.read_to_end(&mut bytes).unwrap();
            (bytes, file.compression())
        };
        assert_eq!(read("Library/workspaces/Work/AttackFM.md"), ("# AttackFM 日本\n".as_bytes().to_vec(), CompressionMethod::Deflated));
        assert_eq!(read("images/2b0c.jpg"), (vec![0xff, 0xd8, 0xff, 0xe0, 1, 2, 3], CompressionMethod::Stored));
        let manifest: serde_json::Value = serde_json::from_slice(&read("manifest.json").0).unwrap();
        assert_eq!(manifest, serde_json::json!({ "app": "Ghost.md", "notes": 2, "files": 7, "bytes": done.bytes }));
        std::fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn stops_when_asked_and_says_so() {
        let data = data();
        let list = entries(&sources(&data)).unwrap();
        let stopped = write(Vec::new(), "ghostmarkdown_x.zip", &list, &[], &serde_json::json!({}), 0, &AtomicBool::new(true), |_| {});
        assert_eq!(stopped, Err(CANCELLED.to_string()));
        std::fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn says_a_full_drive_and_a_fat32_drive_in_words() {
        assert_eq!(said(&io::Error::from(io::ErrorKind::StorageFull)), "The drive is full.");
        assert!(said(&io::Error::from(io::ErrorKind::FileTooLarge)).contains("FAT32"));
    }

    #[test]
    fn takes_only_a_plain_archive_name() {
        assert!(valid_name("ghostmarkdown_2026-10-01_21-42-05.zip"));
        for bad in ["ghostmarkdown.7z", "../x.zip", "a/b.zip", ".zip", ".hidden.zip", "a b.zip"] {
            assert!(!valid_name(bad), "{bad}");
        }
        assert_eq!(root_of("ghostmarkdown_1.zip"), "ghostmarkdown_1");
    }

    #[cfg(unix)]
    #[test]
    fn takes_only_a_new_empty_file_outside_the_apps_storage_and_never_closes_one_it_refuses() {
        use std::os::fd::{AsRawFd, IntoRawFd};
        let own = temp("own");
        let drive = temp("drive");
        let open = |path: &Path| std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(path).unwrap();

        // The picker's new file on a drive: taken, and written through.
        let made = open(&drive.join("ghostmarkdown_x.zip")).into_raw_fd();
        let mut file = adopt_descriptor(made, std::slice::from_ref(&own)).unwrap();
        file.write_all(b"PK").unwrap();
        drop(file);
        assert_eq!(std::fs::read(drive.join("ghostmarkdown_x.zip")).unwrap(), b"PK");

        // A file with something in it, and one inside the app's own storage: refused, and still open after.
        std::fs::write(drive.join("full.zip"), b"already here").unwrap();
        let full = open(&drive.join("full.zip"));
        assert_eq!(adopt_descriptor(full.as_raw_fd(), std::slice::from_ref(&own)).unwrap_err(), NOT_THE_FILE);
        assert!(full.metadata().is_ok());
        let inside = open(&own.join("index.sqlite"));
        assert_eq!(adopt_descriptor(inside.as_raw_fd(), std::slice::from_ref(&own)).unwrap_err(), NOT_THE_FILE);
        assert!(inside.metadata().is_ok());

        // Standard input and a number that names nothing.
        assert_eq!(adopt_descriptor(0, &[]).unwrap_err(), NOT_THE_FILE);
        assert_eq!(adopt_descriptor(1_000_000, &[]).unwrap_err(), NOT_THE_FILE);
        std::fs::remove_dir_all(own).unwrap();
        std::fs::remove_dir_all(drive).unwrap();
    }

    #[test]
    fn dates_a_file_on_the_wall_clock_of_where_it_was_exported() {
        // 2026-10-01T20:42:05Z, an hour east.
        let at = UNIX_EPOCH + std::time::Duration::from_secs(1_790_887_325);
        let time = zip_time(at, 60);
        assert_eq!((time.year(), time.month(), time.day(), time.hour(), time.minute(), time.second()), (2026, 10, 1, 21, 42, 4));
        assert_eq!(zip_time(UNIX_EPOCH, 0), DateTime::default());
    }
}
