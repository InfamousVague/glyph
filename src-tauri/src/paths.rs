//! Where the app keeps things on disk: `<app_data_dir>`, `<app_cache_dir>`,
//! and the named directories under them, resolved in this one place.
//!
//! Under `<app_data_dir>`: `Library/` (the notes, library/), `recordings/`
//! (`<id>.wav`, the capture seam), `images/` (images.rs), `models/` (whisper's
//! and the formatter's alike), `ota/` (ota.rs), and two files that are not
//! directories and so are named where they are used: `notion.json`
//! (notion.rs) and the old `glyph.sqlite` (commands.rs). Under
//! `<app_cache_dir>`: `picked/` (a picture the Android shell shrank, adopted
//! by images.rs) and `updates/` (the verified APK).
//!
//! Resolving needs an `AppHandle` (or the `App` in setup), which is why this
//! is on the Tauri side of the seam and the Tauri-free modules take a path
//! instead - `store::open`, `Library::open_fs`, `whisper::model::fetch`,
//! `ota::peek` all do, so a caller with no Tauri in its process (the
//! update-alert worker today) resolves its own.
//!
//! Before this module, ten places resolved these by hand, some answering
//! `Option` and some `Result`, with a different sentence nearly every time, and
//! the one comment that claimed `commands::install` was the only resolver had
//! stopped being true. Now there is one sentence per root, and the directories
//! answer `Result`: a caller that
//! treats "no directory" as "nothing there" says so with `.ok()`, which is the
//! choice the model status makes (no data directory is a model that cannot be
//! present - and NOT a relative path, which would answer for whatever file
//! happens to sit in the process's working directory).
//!
//! FOUR NAMES ARE SHARED WITH KOTLIN, which resolves them from its own
//! `Context` and has no way to ask this module: `Library`, `ota`, `picked`
//! and `updates`. Each constant names its twin, each twin names this file,
//! and a test reads the Kotlin sources, so renaming one side alone fails the
//! build's tests instead of quietly breaking the Files app, update alerts, the
//! picker or APK install on a phone.

use std::fmt::Display;
use std::path::PathBuf;

use tauri::{Manager, Runtime};

/// The notes, as Markdown files (docs/LIBRARY.md). KOTLIN TWIN:
/// `files/LibraryDocuments.kt`'s `library()`, `File(context!!.dataDir, "Library")`,
/// which serves this folder to the Files app.
pub const LIBRARY: &str = "Library";

/// A spoken note's kept audio, `<id>.wav`.
pub const RECORDINGS: &str = "recordings";

/// Pictures in notes, `<uuid>.<jpg|png|webp>`.
pub const IMAGES: &str = "images";

/// Model files and their `.part` downloads, whisper's and the formatter's in
/// one directory, so a file name must be unique across both catalogues.
pub const MODELS: &str = "models";

/// Downloaded frontends and the OTA state files. KOTLIN TWIN:
/// `updates/UpdateCheckWorker.kt`, `File(context.dataDir, "ota")`, whose path
/// the background update check hands to `ota::peek`.
pub const OTA: &str = "ota";

/// Under the CACHE: a picture the shell picked and shrank, until
/// `save_image` adopts it. KOTLIN TWIN: `MainActivity.kt`'s picker,
/// `File(cacheDir, "picked")`.
pub const PICKED: &str = "picked";

/// Under the CACHE: the verified APK. KOTLIN TWIN: `MainActivity.kt`'s
/// `installApk`, which accepts only a file directly inside
/// `File(cacheDir, "updates")`. Not on iOS, which has no APK.
#[cfg_attr(target_os = "ios", allow(dead_code))]
pub const UPDATES: &str = "updates";

/// `<app_data_dir>`, or the one sentence that says the platform gave none.
pub fn data_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    said(app.path().app_data_dir(), "no app data directory")
}

/// `<app_cache_dir>`, or the one sentence that says the platform gave none.
pub fn cache_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    said(app.path().app_cache_dir(), "no cache directory")
}

/// `<app_data_dir>/Library`, for the desktop's Reveal: on a phone the notes'
/// folder opens through the Files app, which Kotlin serves itself.
#[cfg_attr(mobile, allow(dead_code))]
pub fn library_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(LIBRARY))
}

/// `<app_data_dir>/recordings`.
pub fn recordings_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(RECORDINGS))
}

/// `<app_data_dir>/images`.
pub fn images_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(IMAGES))
}

/// `<app_data_dir>/models`.
pub fn models_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(MODELS))
}

/// `<app_data_dir>/ota`.
pub fn ota_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(OTA))
}

/// `<app_cache_dir>/picked`.
pub fn picked_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(cache_dir(app)?.join(PICKED))
}

/// `<app_cache_dir>/updates`. Not on iOS, which has no APK.
#[cfg_attr(target_os = "ios", allow(dead_code))]
pub fn updates_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(cache_dir(app)?.join(UPDATES))
}

/// A platform's answer, or `missing` and why.
fn said<E: Display>(found: Result<PathBuf, E>, missing: &str) -> Result<PathBuf, String> {
    found.map_err(|e| format!("{missing}: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_directory_is_one_sentence_with_the_platforms_reason() {
        assert_eq!(said(Err("unknown path"), "no app data directory"), Err("no app data directory: unknown path".to_string()));
        assert_eq!(said::<&str>(Ok(PathBuf::from("/data/glyph")), "no app data directory"), Ok(PathBuf::from("/data/glyph")));
    }

    /// The names Kotlin resolves on its own. Matched against the source as it
    /// is written, `File(<root>, "<name>")`, so a rename on either side fails
    /// here rather than on a phone.
    #[test]
    fn the_kotlin_twins_name_the_same_directories() {
        let kotlin = |file: &str| {
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("gen/android/app/src/main/java/com/mattssoftware/glyph").join(file);
            std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
        };
        for (file, twin) in [
            ("files/LibraryDocuments.kt", format!("File(context!!.dataDir, \"{LIBRARY}\")")),
            ("updates/UpdateCheckWorker.kt", format!("File(context.dataDir, \"{OTA}\")")),
            ("MainActivity.kt", format!("File(cacheDir, \"{PICKED}\")")),
            ("MainActivity.kt", format!("File(cacheDir, \"{UPDATES}\")")),
        ] {
            let source = kotlin(file);
            assert!(source.contains(&twin), "{file} no longer says {twin}");
            assert!(source.contains("paths.rs"), "{file} should name src-tauri/src/paths.rs beside its twin");
        }
    }
}
