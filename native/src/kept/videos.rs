//! Films in notes, kept: the items of `tauri/src-tauri/src/videos.rs` that name no `tauri::` type, word for
//! word. What a deleted note takes with it, a picked film and its poster adopted from the cache's `picked/`
//! (`save`, `discard`), the weekly sweep of films no note names and the hourly one of `picked/`. `kept::tests`
//! holds what is between the marks to the original.
//!
//! What is not here is the `vid` scheme (`serve`), which a WebView played a film through: the Flutter app plays
//! a film from its file with the phone's own player (android/…/ghost_md/FilmPlayer.kt), so nothing serves it.
//! The two commands (`save_video`, `discard_picked`) and the launch sweep (`install`) take a Tauri `AppHandle`
//! there; here they are files.rs's and dispatch.rs's, over the same functions.

use std::collections::BTreeMap;
use std::io::Read as _;
use std::path::Path;
use std::time::{Duration, SystemTime};

use serde::{Deserialize, Serialize};

// copied:begin
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
// copied:end

/// The Tauri command `save_video` without its `AppHandle`: a picked film and its poster adopted, and what has
/// waited in `picked` for over an hour swept, whichever way it went.
pub fn save_video(picked: &Path, videos: &Path, images: &Path, path: &Path, poster: &Path) -> Result<SavedVideo, String> {
    let saved = save(picked, videos, images, path, poster);
    sweep_picked(picked, SystemTime::now());
    saved
}

/// The Tauri command `discard_picked` without its `AppHandle`.
pub fn discard_picked(picked: &Path, path: &Path) -> Result<(), String> {
    let discarded = discard(picked, path);
    sweep_picked(picked, SystemTime::now());
    discarded
}

