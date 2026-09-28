//! Films in notes (native generation 21, docs/DESIGN.md §141): where they are
//! kept, how the page plays them, and when they go.
//!
//! Matt asked for a menu that adds "geotag cards images videos and more". A
//! note refers to a film as a poster picture linked to it, on a line of its
//! own:
//!
//! ```text
//! [![video 0:12](image/<poster>.jpg)](video/<uuid>.mp4)
//! ```
//!
//! The poster is an ordinary picture in `images/` (images.rs), so every
//! picture pipeline carries it: sync, a share, a deleted note's clean-up. The
//! film is `<app_data_dir>/video/<uuid>.<mp4|m4v|mov|webm>`, and it stays on
//! the phone it was added on: it is never synced or shared, and the Android
//! manifest's backup rules keep `video/` out of Google's cloud backup, where a
//! long film would take the app past its quota and stop the notes' backup with
//! it. A move to a new phone by cable is meant to carry it; whether Smart
//! Switch honours the rules has not been tried.
//!
//! The Android shell picks a film with the Photo Picker, copies it into
//! `<app_cache_dir>/picked/` and makes its poster there
//! (media/VideoPick.kt); `save_video` adopts both from there, and nowhere
//! else, all or nothing. An answer the page never asked for (a reload, or the
//! process gone while the picker was up) is thrown away with `discard_picked`,
//! and what even that misses goes in the launch sweep of `picked/`.
//!
//! The page plays a film through the `vid` scheme, `http://vid.localhost/<name>`,
//! in ranges (ranged.rs). The folder it plays from is found once and kept: on
//! Android the platform's answer is a trip to the main thread, and a 4K film
//! asks for a range several times a second while it plays. A deleted note
//! takes the films only it named, and a daily sweep takes a film no note has
//! named for a week: time for an Undo, a note in the trash, and sync to catch
//! up. What waits in `picked/` for over an hour goes at launch, and again each
//! time a film is kept or thrown away, since a phone can keep the app's
//! process for days and a film's copy is big.
//!
//! Every name that reaches a path is checked first, as a picture's is: a
//! plain id, then one film extension.
//!
//! The iPhone app has no video picker, so its two commands answer with their
//! refusal there (unsupported.rs), and the keeping below is unused on iOS by
//! design. The scheme and the sweeps are built there as everywhere, with
//! nothing to serve or sweep.

// On iOS the commands refuse before they keep anything: what they would call is
// unused there by design, not by accident.
#![cfg_attr(target_os = "ios", allow(dead_code))]

use std::collections::BTreeMap;
use std::io::Read as _;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{Duration, SystemTime};

use serde::{Deserialize, Serialize};

/// The URI scheme the page plays films through.
pub const SCHEME: &str = "vid";

/// The kinds of film kept. KOTLIN TWIN: media/VideoPick.kt's `EXTENSIONS`,
/// which names a picked film by its type; a test here reads it.
pub const EXTENSIONS: [&str; 4] = ["mp4", "m4v", "mov", "webm"];

/// What a person reads when a film could not be kept, whichever half failed.
const NOT_KEPT: &str = "The video couldn’t be kept.";

/// How long a film no note names is kept before the sweep takes it.
const UNNAMED_FOR: Duration = Duration::from_secs(7 * 24 * 60 * 60);
/// How often the sweep of `video/` looks.
const SWEEP_EVERY: Duration = Duration::from_secs(24 * 60 * 60);
/// How long a file waits in `picked/` before the launch sweep takes it: a copy
/// still being written has a fresh time, and an adopted one is already gone.
const PICKED_FOR: Duration = Duration::from_secs(60 * 60);
/// The sweep's memory, inside `video/`: a dot file, which is never a film's name.
const ORPHANS: &str = ".orphans.json";

/// Whether `name` is a film name this module will turn into a path: a plain id
/// of at most 64 characters (a uuid), then one film extension.
pub fn valid_name(name: &str) -> bool {
    let Some((stem, extension)) = name.rsplit_once('.') else { return false };
    stem.len() <= 64 && crate::fsx::plain_id(stem) && EXTENSIONS.contains(&extension)
}

/// The atoms an older QuickTime film may open with in place of `ftyp`: the
/// format predates it, and a `.mov` from an older camera or editor starts
/// with its padding, its media or its index.
const QUICKTIME_FIRST: [&[u8; 4]; 6] = [b"wide", b"free", b"skip", b"mdat", b"moov", b"pnot"];

/// Whether a film's first bytes are what its extension says: an ISO box with
/// `ftyp` at byte 4 for MP4 and QuickTime (or, for QuickTime, one of its older
/// first atoms), EBML's magic for WebM.
fn sniffed(first: &[u8], extension: &str) -> bool {
    let atom = first.get(4..8);
    match extension {
        "webm" => first.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]),
        "mov" => atom.is_some_and(|atom| atom == b"ftyp" || QUICKTIME_FIRST.iter().any(|first| atom == &first[..])),
        _ => atom == Some(b"ftyp"),
    }
}

/// `path` as a file directly inside `picked`, once both are canonicalised (so
/// a symlink or a `..` cannot reach a file elsewhere), or `None`.
fn inside_picked(picked: &Path, path: &Path) -> Option<std::path::PathBuf> {
    let picked = picked.canonicalize().ok()?;
    let file = path.canonicalize().ok()?;
    (file.parent() == Some(picked.as_path()) && file.is_file()).then_some(file)
}

/// Moves a picked film from `picked` into `videos` under a fresh name, and
/// answers the name. Refuses any path that is not a file directly inside
/// `picked`, and anything that is not a film by its extension and its first
/// bytes, or is empty.
pub fn adopt(picked: &Path, videos: &Path, path: &Path) -> Result<String, String> {
    adopt_by(picked, videos, path, |from, to| std::fs::rename(from, to))
}

/// `adopt`, with the rename it tries first given: the cache and the data
/// directory can be on different mounts, where a rename always fails.
fn adopt_by(picked: &Path, videos: &Path, path: &Path, rename: impl Fn(&Path, &Path) -> std::io::Result<()>) -> Result<String, String> {
    let refuse = || NOT_KEPT.to_string();
    let file = inside_picked(picked, path).ok_or_else(refuse)?;
    let extension = file
        .extension()
        .and_then(|e| e.to_str())
        .map(str::to_ascii_lowercase)
        .filter(|e| EXTENSIONS.contains(&e.as_str()))
        .ok_or_else(refuse)?;
    let mut first = [0u8; 12];
    let read = std::fs::File::open(&file).and_then(|mut f| f.read(&mut first)).map_err(|_| refuse())?;
    if read == 0 || !sniffed(&first[..read], &extension) {
        return Err(refuse());
    }
    std::fs::create_dir_all(videos).map_err(|_| refuse())?;
    let name = format!("{}.{extension}", uuid::Uuid::new_v4());
    let target = videos.join(&name);
    // A rename where it can be; the cache and the data directory can be on
    // different mounts, and then it is a copy and a delete. A copy that fails
    // half way leaves nothing behind.
    if rename(&file, &target).is_err() {
        if std::fs::copy(&file, &target).is_err() {
            let _ = std::fs::remove_file(&target);
            return Err(refuse());
        }
        let _ = std::fs::remove_file(&file);
    }
    Ok(name)
}

/// A film and its poster, as the note's line names them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct SavedVideo {
    pub video: String,
    pub poster: String,
}

/// Adopts a picked film into `videos` and its poster into `images`, both or
/// neither: if either cannot be kept, what was kept goes, and so do the picked
/// files.
fn save(picked: &Path, videos: &Path, images: &Path, path: &Path, poster: &Path) -> Result<SavedVideo, String> {
    let throw_away = || {
        let _ = discard(picked, path);
        let _ = discard(picked, poster);
    };
    let Ok(poster_name) = crate::images::adopt(picked, images, poster) else {
        throw_away();
        return Err(NOT_KEPT.to_string());
    };
    match adopt(picked, videos, path) {
        Ok(video) => Ok(SavedVideo { video, poster: poster_name }),
        Err(refused) => {
            let _ = std::fs::remove_file(images.join(&poster_name));
            throw_away();
            Err(refused)
        }
    }
}

/// Deletes one file directly inside `picked`. A file already gone is done; a
/// path anywhere else is refused and left.
fn discard(picked: &Path, path: &Path) -> Result<(), String> {
    if !path.exists() {
        return Ok(());
    }
    let file = inside_picked(picked, path).ok_or_else(|| "That is not a picked file.".to_string())?;
    crate::fsx::remove_file_if_present(&file).map_err(|e| e.to_string())
}

/// Adopts a film the Android shell picked into `<app_cache_dir>/picked/`, and
/// its poster beside it, and answers both names for the note's line. Off the
/// main thread: a film that has to be copied across mounts is a gigabyte's
/// work. Native generation 21.
#[tauri::command(async)]
pub fn save_video(app: tauri::AppHandle, path: String, poster: String) -> Result<SavedVideo, String> {
    #[cfg(target_os = "ios")]
    return crate::unsupported::on_ios(crate::unsupported::VIDEOS, (app, path, poster));
    #[cfg(not(target_os = "ios"))]
    {
        let not_kept = |_| NOT_KEPT.to_string();
        let picked = crate::paths::picked_dir(&app).map_err(not_kept)?;
        let videos = crate::paths::videos_dir(&app).map_err(not_kept)?;
        let images = crate::paths::images_dir(&app).map_err(not_kept)?;
        let saved = save(&picked, &videos, &images, Path::new(&path), Path::new(&poster));
        sweep_picked(&picked, SystemTime::now());
        saved
    }
}

/// Throws away a file the shell left in `<app_cache_dir>/picked/` for an answer
/// the page was not waiting for: a film and its poster picked before a reload.
/// Native generation 21.
#[tauri::command]
pub fn discard_picked(app: tauri::AppHandle, path: String) -> Result<(), String> {
    #[cfg(target_os = "ios")]
    return crate::unsupported::on_ios(crate::unsupported::VIDEOS, (app, path));
    #[cfg(not(target_os = "ios"))]
    {
        let picked = crate::paths::picked_dir(&app)?;
        let discarded = discard(&picked, Path::new(&path));
        sweep_picked(&picked, SystemTime::now());
        discarded
    }
}

/// The films a note's body names as `(video/<name>)`, in order, without
/// repeats. Names that are not valid are skipped.
pub fn referenced(body: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut rest = body;
    while let Some(at) = rest.find("](video/") {
        let after = &rest[at + "](video/".len()..];
        let Some(end) = after.find(')') else { break };
        let name = &after[..end];
        if valid_name(name) && !names.iter().any(|n| n == name) {
            names.push(name.to_string());
        }
        rest = &after[end..];
    }
    names
}

/// Removes from `videos` the films a deleted note named, unless another note
/// in `library` still does. Best effort, as the pictures' is.
pub fn remove_unreferenced(videos: &Path, library: &crate::library::Library, body: &str) {
    for name in referenced(body) {
        if library.video_in_use(&name).unwrap_or(true) {
            continue;
        }
        let _ = std::fs::remove_file(videos.join(&name));
    }
}

/// What the sweep remembers between launches: when it last looked, and when
/// it first found each film no note named.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Orphans {
    /// Milliseconds since the epoch.
    swept_at: u64,
    /// Film name to the time it was first found unnamed.
    unnamed: BTreeMap<String, u64>,
}

fn millis(time: SystemTime) -> u64 {
    time.duration_since(SystemTime::UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
}

/// The films in `videos` that no note names (`in_use` says which are named),
/// looked at no more than once a day: each is noted the first time it is
/// found unnamed and deleted once it has stayed unnamed for a week. A film
/// named again is forgotten. Answers what was deleted.
pub fn sweep(videos: &Path, now: SystemTime, in_use: impl Fn(&str) -> bool) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(videos) else { return Vec::new() };
    let memory = videos.join(ORPHANS);
    let mut orphans: Orphans = crate::fsx::read_json_or(&memory, Orphans::default());
    let now_ms = millis(now);
    // A clock that went back looks again rather than waiting a day that may never come.
    if orphans.swept_at <= now_ms && now_ms - orphans.swept_at < SWEEP_EVERY.as_millis() as u64 {
        return Vec::new();
    }
    let films: Vec<String> = entries.filter_map(|e| e.ok()?.file_name().into_string().ok()).filter(|name| valid_name(name)).collect();
    let mut unnamed = BTreeMap::new();
    let mut removed = Vec::new();
    for name in films {
        if in_use(&name) {
            continue;
        }
        let first = orphans.unnamed.get(&name).copied().filter(|&at| at <= now_ms).unwrap_or(now_ms);
        if now_ms - first >= UNNAMED_FOR.as_millis() as u64 {
            if std::fs::remove_file(videos.join(&name)).is_ok() {
                removed.push(name);
            }
            continue;
        }
        unnamed.insert(name, first);
    }
    orphans = Orphans { swept_at: now_ms, unnamed };
    if let Ok(json) = serde_json::to_vec(&orphans) {
        let _ = crate::fsx::write_atomically(&memory, &json);
    }
    removed
}

/// Deletes every file in `picked` last written more than an hour before `now`:
/// a picture or a film the shell left there for an answer that never reached a
/// page. A copy still being written has a fresh time and is left. Answers how
/// many went.
pub fn sweep_picked(picked: &Path, now: SystemTime) -> usize {
    let Ok(entries) = std::fs::read_dir(picked) else { return 0 };
    let mut removed = 0;
    for entry in entries.flatten() {
        let Ok(meta) = entry.metadata() else { continue };
        if !meta.is_file() {
            continue;
        }
        let old = meta.modified().ok().and_then(|at| now.duration_since(at).ok()).is_some_and(|age| age > PICKED_FOR);
        if old && std::fs::remove_file(entry.path()).is_ok() {
            removed += 1;
        }
    }
    removed
}

/// At launch, off the main thread: the sweep of `picked/`, and of `video/`
/// against the library.
pub fn install(app: &tauri::App) {
    use tauri::Manager as _;
    let handle = app.handle().clone();
    // A sweep that cannot start is tried again at the next launch: nothing waits on it.
    let _ = std::thread::Builder::new().name("glyph-video-sweep".into()).spawn(move || {
        if let Ok(picked) = crate::paths::picked_dir(&handle) {
            sweep_picked(&picked, SystemTime::now());
        }
        let Ok(videos) = crate::paths::videos_dir(&handle) else { return };
        let Some(store) = handle.try_state::<crate::commands::NotesStore>() else { return };
        // A film whose use cannot be checked is kept.
        sweep(&videos, SystemTime::now(), |name| store.lock().video_in_use(name).unwrap_or(true));
    });
}

/// `<app_data_dir>/video`, found once: it never moves while the app runs.
static PLAYED_FROM: OnceLock<PathBuf> = OnceLock::new();

/// Serves `<app_data_dir>/video/<name>` to the page's `<video>`, in ranges.
pub fn serve<R: tauri::Runtime>(app: &tauri::AppHandle<R>, request: &tauri::http::Request<Vec<u8>>) -> tauri::http::Response<Vec<u8>> {
    let videos = match PLAYED_FROM.get() {
        Some(dir) => Some(dir.clone()),
        None => crate::paths::videos_dir(app).ok().map(|dir| PLAYED_FROM.get_or_init(|| dir).clone()),
    };
    serve_in(videos.as_deref(), request)
}

/// The answer to `request` for a film kept in `videos` (or nowhere, when the
/// platform gave no directory): by a valid name only, in ranges, and a `HEAD`
/// with the headers alone.
fn serve_in(videos: Option<&Path>, request: &tauri::http::Request<Vec<u8>>) -> tauri::http::Response<Vec<u8>> {
    let name = request.uri().path().trim_start_matches('/');
    let file = videos
        .filter(|_| valid_name(name))
        .and_then(|dir| std::fs::File::open(dir.join(name)).ok())
        .and_then(|file| file.metadata().ok().map(|meta| (file, meta.len())));
    let range = request.headers().get(tauri::http::header::RANGE).and_then(|v| v.to_str().ok());
    let head = request.method() == tauri::http::Method::HEAD;
    crate::ranged::answer(file, range, head, crate::ranged::content_type(name).unwrap_or("application/octet-stream"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Library;
    use crate::test_support::TempDir;

    const MP4: &[u8] = b"\0\0\0\x18ftypmp42\0\0\0\0 and the rest of a film";
    const WEBM: &[u8] = b"\x1A\x45\xDF\xA3\x9F\x42\x86\x81 and the rest";

    /// A phone's picked folder, pictures and films, under one temporary directory.
    struct Phone {
        root: TempDir,
    }

    impl Phone {
        fn new() -> Phone {
            let root = TempDir::new("videos");
            std::fs::create_dir_all(root.join("picked")).unwrap();
            Phone { root }
        }
        fn at(&self, path: &str) -> std::path::PathBuf {
            self.root.join(path)
        }
        fn picked(&self, name: &str, bytes: &[u8]) -> std::path::PathBuf {
            let path = self.at("picked").join(name);
            std::fs::write(&path, bytes).unwrap();
            path
        }
        fn save(&self, film: &Path, poster: &Path) -> Result<SavedVideo, String> {
            save(&self.at("picked"), &self.at("video"), &self.at("images"), film, poster)
        }
        fn count(&self, dir: &str) -> usize {
            std::fs::read_dir(self.at(dir)).map(|d| d.count()).unwrap_or(0)
        }
    }

    #[test]
    fn only_plain_film_names_are_names() {
        for name in ["0f8e7c1a-uuid.mp4", "a_b.m4v", "x.mov", "y.webm"] {
            assert!(valid_name(name), "{name}");
        }
        for name in ["", ".mp4", "../x.mp4", "a/b.mp4", "a.mkv", "a.MP4", "a.mp4.exe", "a b.mp4", "a.jpg", "a"] {
            assert!(!valid_name(name), "{name}");
        }
    }

    #[test]
    fn a_film_is_what_its_first_bytes_say() {
        assert!(sniffed(MP4, "mp4") && sniffed(MP4, "mov") && sniffed(MP4, "m4v"));
        assert!(sniffed(WEBM, "webm"));
        assert!(!sniffed(WEBM, "mp4") && !sniffed(MP4, "webm"));
        for bytes in [&b""[..], b"\0\0\0\x18ft", b"\xFF\xD8\xFF\xE0\0\x10JFIF", b"RIFF\x24\0\0\0AVI "] {
            assert!(!sniffed(bytes, "mp4"), "{bytes:?}");
        }
    }

    #[test]
    fn an_older_quicktime_film_is_one_whatever_atom_it_opens_with() {
        for first in [&b"\0\0\0\x08wide\0\0\0\x10mdat"[..], b"\0\0\0\x08free", b"\0\0\0\x08skip", b"\0\0\x10\0mdat", b"\0\0\x10\0moov", b"\0\0\0\x14pnot"] {
            assert!(sniffed(first, "mov"), "{first:?}");
            assert!(!sniffed(first, "mp4") && !sniffed(first, "m4v"), "an MP4 always opens with ftyp: {first:?}");
        }
        assert!(!sniffed(b"\0\0\0\x08junk", "mov"));
    }

    #[test]
    fn a_picked_film_and_its_poster_are_kept_under_new_names() {
        let phone = Phone::new();
        let film = phone.picked("pick-1.mp4", MP4);
        let poster = phone.picked("pick-1.jpg", b"\xFF\xD8\xFF poster");
        let saved = phone.save(&film, &poster).unwrap();
        assert!(valid_name(&saved.video) && saved.video.ends_with(".mp4"), "{saved:?}");
        assert!(crate::images::valid_name(&saved.poster) && saved.poster.ends_with(".jpg"), "{saved:?}");
        assert_eq!(std::fs::read(phone.at("video").join(&saved.video)).unwrap(), MP4);
        assert_eq!(std::fs::read(phone.at("images").join(&saved.poster)).unwrap(), b"\xFF\xD8\xFF poster");
        assert!(!film.exists() && !poster.exists(), "moved, not copied");
        // A WebM too, by its own magic.
        let webm = phone.picked("pick-2.webm", WEBM);
        let still = phone.picked("pick-2.jpg", b"\xFF\xD8\xFF");
        assert!(phone.save(&webm, &still).unwrap().video.ends_with(".webm"));
    }

    #[test]
    fn a_film_on_another_mount_is_copied_and_the_pick_let_go() {
        let phone = Phone::new();
        let film = phone.picked("pick-1.mp4", MP4);
        // The cache and the data directory on different mounts: every rename fails.
        let across = |_: &Path, _: &Path| Err(std::io::Error::other("cross-device link"));
        let name = adopt_by(&phone.at("picked"), &phone.at("video"), &film, across).unwrap();
        assert_eq!(std::fs::read(phone.at("video").join(&name)).unwrap(), MP4);
        assert!(!film.exists(), "copied, then let go from picked");
        // A copy that cannot be made leaves nothing half made, and the pick where it was.
        let film = phone.picked("pick-2.mp4", MP4);
        std::fs::remove_dir_all(phone.at("video")).unwrap();
        std::fs::write(phone.at("video"), b"a file where the folder should be").unwrap();
        assert!(adopt_by(&phone.at("picked"), &phone.at("video"), &film, across).is_err());
        assert!(film.exists());
    }

    #[test]
    fn a_film_that_cannot_be_kept_takes_its_poster_with_it() {
        let phone = Phone::new();
        // Bytes that are not a film, under a film's name: the poster was adopted first, and goes again.
        let film = phone.picked("pick-1.mp4", b"\xFF\xD8\xFF not a film");
        let poster = phone.picked("pick-1.jpg", b"\xFF\xD8\xFF poster");
        assert_eq!(phone.save(&film, &poster), Err(NOT_KEPT.to_string()));
        assert_eq!((phone.count("images"), phone.count("video"), phone.count("picked")), (0, 0, 0), "all or nothing, and nothing left in picked");
        // A poster that is not a picture: the film is never touched, and both go.
        let film = phone.picked("pick-2.mp4", MP4);
        let poster = phone.picked("pick-2.txt", b"words");
        assert_eq!(phone.save(&film, &poster), Err(NOT_KEPT.to_string()));
        assert_eq!((phone.count("images"), phone.count("video"), phone.count("picked")), (0, 0, 0));
        // An empty film, and a film by a name that is not a film's.
        for (name, bytes) in [("pick-3.mp4", &b""[..]), ("pick-3.mkv", MP4)] {
            let film = phone.picked(name, bytes);
            let poster = phone.picked("pick-3.jpg", b"\xFF\xD8\xFF");
            assert!(phone.save(&film, &poster).is_err(), "{name}");
        }
        assert_eq!(phone.count("video"), 0);
    }

    #[test]
    fn nothing_outside_the_picked_folder_is_adopted_or_discarded() {
        let phone = Phone::new();
        let elsewhere = TempDir::new("videos-elsewhere");
        let outside = elsewhere.join("secret.mp4");
        std::fs::write(&outside, MP4).unwrap();
        let poster = phone.picked("p.jpg", b"\xFF\xD8\xFF");
        assert!(adopt(&phone.at("picked"), &phone.at("video"), &outside).is_err());
        // picked/ is two below the temporary directory both live in.
        let through = phone.at("picked").join("../..").join(elsewhere.file_name().unwrap()).join("secret.mp4");
        assert!(through.exists(), "the way round is a real path to the file");
        assert!(adopt(&phone.at("picked"), &phone.at("video"), &through).is_err());
        #[cfg(unix)]
        {
            let link = phone.at("picked").join("link.mp4");
            std::os::unix::fs::symlink(&outside, &link).unwrap();
            assert!(adopt(&phone.at("picked"), &phone.at("video"), &link).is_err());
            assert!(discard(&phone.at("picked"), &link).is_err(), "a link to a file elsewhere is not a picked file");
        }
        assert!(discard(&phone.at("picked"), &outside).is_err());
        assert!(discard(&phone.at("picked"), &through).is_err());
        assert!(outside.exists(), "nothing outside picked is touched");
        assert_eq!(discard(&phone.at("picked"), &poster), Ok(()));
        assert!(!poster.exists());
        assert_eq!(discard(&phone.at("picked"), &poster), Ok(()), "gone already is done");
    }

    #[test]
    fn a_note_names_its_films_once() {
        let body = "# Harbour\n\n[![video 0:12](image/p1.jpg)](video/f1.mp4)\n- [![video 1:02:03](image/p2.jpg)](video/f2.webm)\n[again](video/f1.mp4) [no](video/../x.mp4) [no](video/f3.mkv)\n![](image/f4.mp4)";
        assert_eq!(referenced(body), ["f1.mp4", "f2.webm"]);
        assert!(referenced("no films here](video/").is_empty());
    }

    #[test]
    fn a_deleted_notes_film_goes_unless_another_note_names_it() {
        let root = TempDir::new("videos-delete");
        let videos = root.join("video");
        std::fs::create_dir_all(&videos).unwrap();
        for name in ["mine.mp4", "shared.mp4"] {
            std::fs::write(videos.join(name), MP4).unwrap();
        }
        let mut library = Library::open_fs(&root.join("Library")).unwrap();
        let body = "[![video 0:01](image/a.jpg)](video/mine.mp4)\n[![video 0:02](image/b.jpg)](video/shared.mp4)\n";
        library.save_note("other", "[![video 0:02](image/b.jpg)](video/shared.mp4)\n", "editor").unwrap();
        remove_unreferenced(&videos, &library, body);
        assert!(!videos.join("mine.mp4").exists());
        assert!(videos.join("shared.mp4").exists());
    }

    #[test]
    fn a_film_no_note_names_goes_after_a_week_and_one_named_again_stays() {
        let root = TempDir::new("videos-sweep");
        let videos = root.join("video");
        std::fs::create_dir_all(&videos).unwrap();
        for name in ["named.mp4", "dropped.mp4", "renamed.mov"] {
            std::fs::write(videos.join(name), MP4).unwrap();
        }
        std::fs::write(videos.join("notes.txt"), b"not a film").unwrap();
        let day = Duration::from_secs(24 * 60 * 60);
        let start = SystemTime::UNIX_EPOCH + Duration::from_secs(1_800_000_000);
        let named = std::cell::RefCell::new(vec!["named.mp4"]);
        let in_use = |name: &str| named.borrow().contains(&name);

        assert!(sweep(&videos, start, in_use).is_empty(), "the first look only notes them");
        assert!(sweep(&videos, start + day * 3, in_use).is_empty());
        // Named again on the fourth day: forgotten, so its week starts over when it is dropped again.
        named.borrow_mut().push("renamed.mov");
        assert!(sweep(&videos, start + day * 4, in_use).is_empty());
        named.borrow_mut().pop();
        // A week after it was first found unnamed, the dropped film goes; the one dropped again waits its own week.
        assert_eq!(sweep(&videos, start + day * 7 + Duration::from_secs(1), in_use), ["dropped.mp4"]);
        assert!(!videos.join("dropped.mp4").exists());
        assert!(videos.join("named.mp4").exists() && videos.join("renamed.mov").exists() && videos.join("notes.txt").exists());
        // Looked at twice in a day: the second look does nothing, whatever it would find.
        assert!(sweep(&videos, start + day * 7 + Duration::from_secs(60), |_| false).is_empty(), "once a day");
        assert!(sweep(&videos, start + day * 13, in_use).is_empty(), "six days unnamed is not a week");
        assert_eq!(sweep(&videos, start + day * 14 + Duration::from_secs(5), in_use), ["renamed.mov"]);
        // Nowhere to look: nothing to do.
        assert!(sweep(&root.join("none"), start, |_| false).is_empty());
    }

    #[test]
    fn the_sweep_looks_once_a_day_even_when_a_film_is_due() {
        let root = TempDir::new("videos-daily");
        let videos = root.join("video");
        std::fs::create_dir_all(&videos).unwrap();
        std::fs::write(videos.join("due.mp4"), MP4).unwrap();
        let hour = Duration::from_secs(60 * 60);
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_800_000_000);
        // Last looked an hour ago, and the film was first found unnamed eight days ago: it is due, but not today.
        let memory = Orphans { swept_at: millis(now - hour), unnamed: BTreeMap::from([("due.mp4".to_string(), millis(now - hour * 24 * 8))]) };
        std::fs::write(videos.join(ORPHANS), serde_json::to_vec(&memory).unwrap()).unwrap();
        assert!(sweep(&videos, now, |_| false).is_empty(), "looked at within the day");
        assert!(videos.join("due.mp4").exists());
        assert_eq!(sweep(&videos, now + hour * 23, |_| false), ["due.mp4"]);
    }

    /// A request as the WebView sends one to the scheme.
    fn asked(method: &str, name: &str, range: Option<&str>) -> tauri::http::Request<Vec<u8>> {
        let mut builder = tauri::http::Request::builder().method(method).uri(format!("http://vid.localhost/{name}"));
        if let Some(range) = range {
            builder = builder.header(tauri::http::header::RANGE, range);
        }
        builder.body(Vec::new()).unwrap()
    }

    #[test]
    fn the_scheme_serves_a_kept_film_by_its_name_in_ranges_and_a_head_reads_nothing() {
        use crate::test_support::header_of;
        use tauri::http::{header, StatusCode};
        let root = TempDir::new("videos-serve");
        let videos = root.join("video");
        std::fs::create_dir_all(&videos).unwrap();
        // Over the 8 MB a request with no range is answered with, as a film is.
        let long: Vec<u8> = (0..(crate::ranged::WHOLE_CAP as usize + 10)).map(|i| (i % 251) as u8).collect();
        std::fs::write(videos.join("f1.mp4"), &long).unwrap();
        std::fs::write(root.join("secret.mp4"), MP4).unwrap();

        // The card's HEAD: here, how long, and no bytes, whatever its size.
        let head = serve_in(Some(&videos), &asked("HEAD", "f1.mp4", None));
        assert_eq!((head.status(), head.body().len()), (StatusCode::OK, 0));
        assert_eq!(header_of(&head, header::CONTENT_LENGTH), Some(long.len().to_string().as_str()));
        assert_eq!(header_of(&head, header::CONTENT_TYPE), Some("video/mp4"));
        // The element's ranges, read from the film.
        let part = serve_in(Some(&videos), &asked("GET", "f1.mp4", Some("bytes=100-199")));
        assert_eq!((part.status(), part.body().as_slice()), (StatusCode::PARTIAL_CONTENT, &long[100..200]));
        // No film by that name, a name that is not a film's, and nowhere to keep films: not on this phone.
        assert_eq!(serve_in(Some(&videos), &asked("HEAD", "gone.mp4", None)).status(), StatusCode::NOT_FOUND);
        assert_eq!(serve_in(Some(&videos), &asked("GET", "../secret.mp4", Some("bytes=0-1"))).status(), StatusCode::NOT_FOUND);
        assert_eq!(serve_in(None, &asked("HEAD", "f1.mp4", None)).status(), StatusCode::NOT_FOUND);
    }

    /// What lib.rs must say for the page to play and keep films: the scheme
    /// registered by this module's name for it, both commands in the handler,
    /// and the launch sweep. Any one missing passes every other test.
    #[test]
    fn the_app_registers_the_scheme_the_commands_and_the_sweep() {
        let lib = std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src/lib.rs")).unwrap();
        for wired in [
            ".register_uri_scheme_protocol(videos::SCHEME, |ctx, request| videos::serve(ctx.app_handle(), &request))",
            "videos::save_video,",
            "videos::discard_picked,",
            "videos::install(app);",
        ] {
            assert!(lib.contains(wired), "lib.rs no longer says {wired}");
        }
    }

    #[test]
    fn what_waits_in_picked_for_over_an_hour_goes_and_a_fresh_copy_stays() {
        let phone = Phone::new();
        let old = phone.picked("old.mp4", MP4);
        let fresh = phone.picked("fresh.mp4", MP4);
        std::fs::create_dir_all(phone.at("picked/sub")).unwrap();
        let now = SystemTime::now();
        std::fs::File::options().write(true).open(&old).unwrap().set_modified(now - Duration::from_secs(61 * 60)).unwrap();
        std::fs::File::options().write(true).open(&fresh).unwrap().set_modified(now - Duration::from_secs(59 * 60)).unwrap();
        assert_eq!(sweep_picked(&phone.at("picked"), now), 1);
        assert!(!old.exists() && fresh.exists() && phone.at("picked/sub").exists());
        assert_eq!(sweep_picked(&phone.at("nowhere"), now), 0);
    }

    /// The shell names a picked film by its type (media/VideoPick.kt); a type it names that Rust would refuse is a
    /// film picked and never kept, and one Rust keeps that the shell never names is dead code on both sides.
    #[test]
    fn the_kotlin_twin_names_the_same_kinds_of_film() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("gen/android/app/src/main/java/com/mattssoftware/glyph/media/VideoPick.kt");
        let source = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
        let map = source.split("val EXTENSIONS").nth(1).and_then(|rest| rest.split(')').next()).unwrap_or_else(|| panic!("VideoPick.kt no longer says `val EXTENSIONS`"));
        let mut named: Vec<&str> = map.split(" to \"").skip(1).filter_map(|s| s.split('"').next()).collect();
        named.sort_unstable();
        named.dedup();
        let mut kept = EXTENSIONS.to_vec();
        kept.sort_unstable();
        assert_eq!(named, kept, "VideoPick.kt EXTENSIONS and videos.rs EXTENSIONS");
        assert!(source.contains("videos.rs"), "VideoPick.kt should name src-tauri/src/videos.rs beside its twin");
    }
}
