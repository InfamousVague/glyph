//! Starting over: the one command that empties the phone of what Glyph made.
//!
//! `reset_local_data({ models })` removes every note from the library (the
//! files, what is kept beside them, and the index), the recordings and
//! pictures, the Notion sign-in, and - only when asked - the models directory,
//! whisper's and the formatter's alike. The page clears what it keeps itself
//! (preferences, the guide's seen flag, the refine queue) and reloads.
//!
//! Directories are removed whole and not recreated: every writer in the crate
//! creates its directory before it writes (`images::adopt`,
//! `model_files::fetch`, the recorder), so an absent directory is the same
//! as a fresh install. A model that is loaded stays mapped in memory until the
//! engine idles out, which is harmless: the page reads presence off the file.
//!
//! Developer settings only. There is no confirmation here because the page
//! asks twice; a command reachable from the console with no confirmation is
//! a command the console can already do, file by file.

use std::path::{Path, PathBuf};

use tauri::{AppHandle, State};

use crate::commands::NotesStore;
use crate::paths;

/// Where the things a reset removes are kept on this device, each `None` where
/// the platform gave no directory - which leaves nothing there to remove.
struct Kept {
    recordings: Option<PathBuf>,
    images: Option<PathBuf>,
    notion: Option<PathBuf>,
    models: Option<PathBuf>,
}

/// Removes a directory and everything in it; a missing one is already done.
fn remove_dir(dir: Option<&Path>, what: &str) -> Result<(), String> {
    let Some(dir) = dir else { return Ok(()) };
    crate::fsx::remove_dir_if_present(dir).map_err(|e| format!("could not remove the {what} at {}: {e}", dir.display()))
}

/// Everything a person made on this phone goes; the models too if `models`.
#[tauri::command]
pub fn reset_local_data(app: AppHandle, store: State<'_, NotesStore>, models: bool) -> Result<(), String> {
    let kept = Kept {
        recordings: paths::recordings_dir(&app).ok(),
        images: paths::images_dir(&app).ok(),
        notion: crate::notion::account_path(&app).ok(),
        models: paths::models_dir(&app).ok(),
    };
    reset(&store, &kept, models)
}

/// The reset itself, in the order it has always run: the notes, then the
/// recordings and pictures, then the Notion sign-in, then - if asked - the
/// models. The first failure stops it and is the answer.
fn reset(notes: &NotesStore, kept: &Kept, models: bool) -> Result<(), String> {
    notes.lock().clear().map_err(|e| e.to_string())?;
    remove_dir(kept.recordings.as_deref(), "recordings")?;
    remove_dir(kept.images.as_deref(), "pictures")?;
    // The Notion sign-in: a reset leaves no account behind.
    if let Some(path) = &kept.notion {
        crate::fsx::remove_file_if_present(path).map_err(|e| format!("could not forget the Notion account: {e}"))?;
    }
    if models {
        remove_dir(kept.models.as_deref(), "models")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Library;
    use std::sync::Mutex;

    /// A phone's worth of what a person made, under one temporary directory.
    fn phone() -> (PathBuf, NotesStore, Kept) {
        let root = std::env::temp_dir().join(format!("glyph-reset-{}", uuid::Uuid::new_v4()));
        let mut library = Library::open_fs(&root.join("Library")).unwrap();
        library.save_note("n1", "# Kept until now\n\n![](image/a.jpg)\n", "capture").unwrap();
        for file in ["recordings/n1.wav", "images/a.jpg", "models/ggml-base.en-q5_1.bin"] {
            std::fs::create_dir_all(root.join(file).parent().unwrap()).unwrap();
            std::fs::write(root.join(file), b"bytes").unwrap();
        }
        std::fs::write(root.join("notion.json"), br#"{"accessToken":"secret_x"}"#).unwrap();
        let kept = Kept {
            recordings: Some(root.join("recordings")),
            images: Some(root.join("images")),
            notion: Some(root.join("notion.json")),
            models: Some(root.join("models")),
        };
        (root, NotesStore(Mutex::new(library)), kept)
    }

    #[test]
    fn a_reset_takes_everything_a_person_made_and_leaves_the_models() {
        let (root, notes, kept) = phone();
        reset(&notes, &kept, false).unwrap();
        assert!(notes.lock().list_notes().unwrap().is_empty());
        assert!(!root.join("Library/Inbox/Kept until now.md").exists());
        assert!(!root.join("recordings").exists() && !root.join("images").exists(), "removed whole, not emptied");
        assert!(!root.join("notion.json").exists(), "no account is left signed in");
        assert!(root.join("models/ggml-base.en-q5_1.bin").exists(), "a 60 MB download is not thrown away unasked");
        reset(&notes, &kept, false).unwrap();
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_reset_asked_to_takes_the_models_too() {
        let (root, notes, kept) = phone();
        reset(&notes, &kept, true).unwrap();
        assert!(!root.join("models").exists());
        notes.lock().save_note("n2", "after the reset", "editor").unwrap();
        assert_eq!(notes.lock().list_notes().unwrap().len(), 1, "the library carries on");
        let _ = std::fs::remove_dir_all(&root);
    }
}
