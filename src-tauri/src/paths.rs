//! Where the app keeps things on disk: `<app_data_dir>`, `<app_cache_dir>`,
//! and the named directories under them, resolved in this one place.
//!
//! Under `<app_data_dir>`: `Library/` (the notes, library/), `recordings/`
//! (`<id>.wav`, the capture seam), `images/` (images.rs), `video/` (films,
//! videos.rs), `models/` (whisper's and the formatter's alike), `ota/`
//! (ota.rs), and two files that are not directories and so are named where
//! they are used: `notion.json` (notion.rs) and the old `glyph.sqlite`
//! (library/move_in.rs). Under `<app_cache_dir>`: `picked/` (a picture the
//! Android shell shrank, or a film it copied with its poster, adopted by
//! images.rs and videos.rs) and `updates/` (the verified APK).
//!
//! Resolving needs an `AppHandle` (or the `App` in setup), which is why this
//! is on the Tauri side of the seam and the Tauri-free modules take a path
//! instead - `Store::open`, `Library::open_fs`, `model_files::fetch`,
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
//! SIX NAMES ARE SHARED WITH KOTLIN, which resolves them from its own
//! `Context` and has no way to ask this module: `Library`, `recordings`,
//! `jobs`, `ota`, `picked` and `updates`. Each constant names its twin, each
//! twin names this file, and a test reads the Kotlin sources, so renaming one
//! side alone fails the build's tests instead of quietly breaking the Files
//! app, a meeting's recording or its write-up, update alerts, the picker or
//! APK install on a phone. A seventh is a file, not a directory: the library's
//! setting, `library-root.json` (library/root.rs), which `files/LibraryTree.kt`
//! reads to know whether the notes are in a folder of the person's, and which
//! the same test holds to its twin. And one more is named by the Android manifest's
//! backup rules, `video/`, which they keep out of Google's cloud backup: a test
//! reads those too, so a film renamed here cannot quietly start filling a
//! person's backup.

use std::fmt::Display;
use std::path::PathBuf;

use tauri::{Manager, Runtime};

/// The notes, as Markdown files (docs/LIBRARY.md). KOTLIN TWIN:
/// `files/LibraryDocuments.kt`'s `library()`, `File(context!!.dataDir, "Library")`,
/// which serves this folder to the Files app.
pub const LIBRARY: &str = "Library";

/// A spoken note's kept audio, `<id>.wav`. KOTLIN TWIN:
/// `capture/MeetingService.kt`, `File(dataDir, "recordings")`, where the
/// meeting service writes the WAV it records as it goes.
pub const RECORDINGS: &str = "recordings";

/// Pictures in notes, `<uuid>.<jpg|png|webp>`.
pub const IMAGES: &str = "images";

/// Films in notes, `<uuid>.<mp4|m4v|mov|webm>` (videos.rs), which stay on the
/// phone they were added on. BACKUP TWIN: the Android manifest's
/// `res/xml/glyph_backup_rules.xml` and `glyph_data_extraction_rules.xml`,
/// which exclude `video/` from the cloud backup.
pub const VIDEO: &str = "video";

/// Model files and their `.part` downloads, whisper's and the formatter's in
/// one directory, so a file name must be unique across both catalogues.
pub const MODELS: &str = "models";

/// A meeting's write-up: `config.json`, `<id>.progress` and `<id>.json`
/// (jobs.rs). KOTLIN TWIN: `recordings/RecordingWorker.kt`,
/// `File(context.dataDir, "jobs")`, which lists the `.progress` files at
/// launch to enqueue the unfinished ones, and never writes there.
pub const JOBS: &str = "jobs";

/// Downloaded frontends and the OTA state files. KOTLIN TWIN:
/// `updates/UpdateCheckWorker.kt`, `File(context.dataDir, "ota")`, whose path
/// the background update check hands to `ota::peek`.
pub const OTA: &str = "ota";

/// Under the CACHE: a picture the shell picked and shrank, until
/// `save_image` adopts it, and a film it copied with its poster, until
/// `save_video` does. KOTLIN TWINS: `MainActivity.kt`'s picker,
/// `File(cacheDir, "picked")`, and `media/VideoPick.kt`'s.
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

/// `<app_data_dir>/Library`, the app's own folder for the notes: Reveal's
/// answer while the library has no folder of its own to show, and where it is
/// whenever the person has not chosen another (`library_root`). On a phone the
/// notes' folder opens through the Files app, which Kotlin serves itself.
#[cfg_attr(mobile, allow(dead_code))]
pub fn library_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(LIBRARY))
}

/// Where the library is: what `<app_data_dir>/library-root.json` says (library/root.rs `Root::read`, the one
/// reader of it), the app's own folder when it says nothing.
pub fn library_root<R: Runtime>(app: &impl Manager<R>) -> Result<crate::library::root::Root, String> {
    Ok(crate::library::root::Root::read(&data_dir(app)?))
}

/// `<app_data_dir>/recordings`.
pub fn recordings_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(RECORDINGS))
}

/// `<app_data_dir>/images`.
pub fn images_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(IMAGES))
}

/// `<app_data_dir>/video`.
pub fn videos_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(VIDEO))
}

/// `<app_data_dir>/models`.
pub fn models_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(MODELS))
}

/// `<app_data_dir>/jobs`.
pub fn jobs_dir<R: Runtime>(app: &impl Manager<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(JOBS))
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
            ("media/VideoPick.kt", format!("File(cacheDir, \"{PICKED}\")")),
            ("MainActivity.kt", format!("File(cacheDir, \"{UPDATES}\")")),
            ("capture/MeetingService.kt", format!("fun recordingsDir(context: Context): File = File(context.dataDir, \"{RECORDINGS}\")")),
            ("recordings/RecordingWorker.kt", format!("File(context.dataDir, \"{JOBS}\")")),
            ("files/LibraryTree.kt", format!("File(context.dataDir, \"{}\")", crate::library::root::ROOT_FILE)),
        ] {
            let source = kotlin(file);
            assert!(source.contains(&twin), "{file} no longer says {twin}");
            assert!(source.contains("paths.rs"), "{file} should name src-tauri/src/paths.rs beside its twin");
        }
        // The meeting service writes the tape and Discard deletes it: both through the one function above, so a
        // path changed in one place but not the other cannot write where Rust never looks, or leave an hour of
        // other people's voices behind a Discard.
        let meeting = kotlin("capture/MeetingService.kt");
        assert_eq!(meeting.matches(&format!("\"{RECORDINGS}\"")).count(), 1, "MeetingService.kt names {RECORDINGS:?} once, in recordingsDir");
        assert!(!meeting.contains("File(dataDir, "), "every path in MeetingService.kt goes through recordingsDir");
        // The bridge's id rule is Rust's (`fsx::plain_id`), its length cap included.
        let activity = kotlin("MainActivity.kt");
        let rule = format!("id.length in 1..{}", crate::fsx::PLAIN_ID_MAX);
        assert!(activity.contains(&rule), "MainActivity.isNoteId no longer says {rule}");
    }

    /// What saf.rs calls on `LibraryTree` (compiled for Android only, so the names are written out here): every one a
    /// static method of strings answering a string, and `attach` the native method saf.rs exports. A rename on
    /// either side fails here rather than as a library that will not open on a phone.
    #[test]
    fn the_folder_bridge_has_every_method_rust_calls() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("gen/android/app/src/main/java/com/mattssoftware/glyph/files/LibraryTree.kt");
        let source = std::fs::read_to_string(&path).unwrap();
        assert!(source.starts_with("package com.mattssoftware.glyph.files\n"), "saf.rs exports Java_com_mattssoftware_glyph_files_LibraryTree_attach");
        assert!(source.contains("object LibraryTree {") && source.contains("@JvmStatic private external fun attach()"));
        for signature in [
            "fun granted(tree: String): String",
            "fun inspect(tree: String): String",
            "fun list(tree: String): String",
            "fun read(tree: String, path: String): String",
            "fun write(tree: String, path: String, text: String): String",
            "fun rename(tree: String, from: String, to: String): String",
            "fun remove(tree: String, path: String): String",
            "fun stat(tree: String, path: String): String",
        ] {
            let at = source.find(signature).unwrap_or_else(|| panic!("LibraryTree.kt no longer has {signature}"));
            assert!(source[..at].trim_end().ends_with("@JvmStatic"), "{signature} must be @JvmStatic for JNI's static call");
        }
    }

    /// Films stay out of Google's cloud backup: both rules files exclude this
    /// folder under the data directory (`root` is `context.dataDir`, the
    /// `<app_data_dir>` the folder is joined to), and the manifest names both.
    /// Without them, a film, which stays on the phone it was added on, would go
    /// to the person's Drive.
    #[test]
    fn the_backup_rules_leave_films_out_of_the_cloud() {
        let android = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("gen/android/app/src/main");
        let read = |file: &str| std::fs::read_to_string(android.join(file)).unwrap_or_else(|e| panic!("{file}: {e}"));
        let exclude = format!("<exclude domain=\"root\" path=\"{VIDEO}/\" />");
        let legacy = read("res/xml/glyph_backup_rules.xml");
        assert!(legacy.contains(&exclude), "glyph_backup_rules.xml no longer says {exclude}");
        let rules = read("res/xml/glyph_data_extraction_rules.xml");
        let cloud = rules.split("<cloud-backup").nth(1).and_then(|rest| rest.split("</cloud-backup>").next()).expect("a <cloud-backup> section");
        assert!(cloud.contains(&exclude), "the cloud backup no longer leaves out {VIDEO}/");
        let transfer = rules.split("<device-transfer").nth(1).and_then(|rest| rest.split("</device-transfer>").next()).unwrap_or("");
        assert!(!transfer.contains(&exclude), "a move to a new phone by cable carries the films");
        let manifest = read("AndroidManifest.xml");
        assert!(manifest.contains("android:fullBackupContent=\"@xml/glyph_backup_rules\""));
        assert!(manifest.contains("android:dataExtractionRules=\"@xml/glyph_data_extraction_rules\""));
    }
}
