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

use tauri::{AppHandle, State};

use crate::commands::NotesStore;
use crate::paths;

/// Removes a directory and everything in it; a missing one is already done.
fn remove_dir(dir: Option<std::path::PathBuf>, what: &str) -> Result<(), String> {
    let Some(dir) = dir else { return Ok(()) };
    crate::fsx::remove_dir_if_present(&dir).map_err(|e| format!("could not remove the {what} at {}: {e}", dir.display()))
}

/// Everything a person made on this phone goes; the models too if `models`.
#[tauri::command]
pub fn reset_local_data(app: AppHandle, store: State<'_, NotesStore>, models: bool) -> Result<(), String> {
    store.lock().clear().map_err(|e| e.to_string())?;
    remove_dir(paths::recordings_dir(&app).ok(), "recordings")?;
    remove_dir(paths::images_dir(&app).ok(), "pictures")?;
    // The Notion sign-in: a reset leaves no account behind.
    if let Ok(path) = crate::notion::account_path(&app) {
        crate::fsx::remove_file_if_present(&path).map_err(|e| format!("could not forget the Notion account: {e}"))?;
    }
    if models {
        remove_dir(paths::models_dir(&app).ok(), "models")?;
    }
    Ok(())
}
