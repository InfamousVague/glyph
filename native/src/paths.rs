//! The names of the directories under the app's data and cache directories: the constants of
//! `tauri/src-tauri/src/paths.rs`, and none of its functions.
//!
//! The original resolves each directory from a Tauri `AppHandle`. Here the Flutter app resolves the two roots
//! itself (lib/core/native/device_paths.dart) and hands them to `init`, so only the names are needed: by the
//! included files (`library_root.rs` joins `LIBRARY`, `jobs.rs` names `JOBS`) and by `dispatch`.
//!
//! The test below reads the original and fails when a name differs, so a folder renamed there cannot leave this
//! app writing notes where the Tauri app would not look.

/// The notes, as Markdown files.
pub const LIBRARY: &str = "Library";

/// A spoken note's kept audio, `<id>.wav`.
pub const RECORDINGS: &str = "recordings";

/// Pictures in notes.
pub const IMAGES: &str = "images";

/// Films in notes.
pub const VIDEO: &str = "video";

/// Model files and their `.part` downloads.
pub const MODELS: &str = "models";

/// A meeting's write-up: `config.json`, `<id>.progress` and `<id>.json`.
pub const JOBS: &str = "jobs";

/// Downloaded frontends and the OTA state files: the Tauri app's, which this one has no use for.
pub const OTA: &str = "ota";

/// Under the CACHE: a picture or film the shell picked, until it is adopted.
pub const PICKED: &str = "picked";

/// Under the CACHE: the verified APK.
pub const UPDATES: &str = "updates";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_name_is_the_tauri_apps() {
        let original = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../tauri/src-tauri/src/paths.rs");
        let source = std::fs::read_to_string(&original).unwrap_or_else(|e| panic!("{}: {e}", original.display()));
        for (name, value) in [
            ("LIBRARY", LIBRARY),
            ("RECORDINGS", RECORDINGS),
            ("IMAGES", IMAGES),
            ("VIDEO", VIDEO),
            ("MODELS", MODELS),
            ("JOBS", JOBS),
            ("OTA", OTA),
            ("PICKED", PICKED),
            ("UPDATES", UPDATES),
        ] {
            let line = format!("pub const {name}: &str = \"{value}\";");
            assert!(source.contains(&line), "paths.rs no longer says {line}");
        }
        let constants = source.lines().filter(|line| line.starts_with("pub const ")).count();
        assert_eq!(constants, 9, "paths.rs has a directory this shim does not name");
    }
}
