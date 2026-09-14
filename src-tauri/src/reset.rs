//! Starting over: the one command that empties the phone of what Glyph made.
//!
//! `reset_local_data({ models })` removes every note from the store (and the
//! captures table with it), the recordings and pictures beside the database,
//! and - only when asked - the models directory, whisper's and the
//! formatter's alike. The page clears what it keeps itself (preferences, the
//! guide's seen flag, the refine queue) and reloads.
//!
//! Directories are removed whole and not recreated: every writer in the crate
//! creates its directory before it writes (`images::adopt`,
//! `whisper::model::fetch`, the recorder), so an absent directory is the same
//! as a fresh install. A model that is loaded stays mapped in memory until the
//! engine idles out, which is harmless: the page reads presence off the file.
//!
//! Developer settings only. There is no confirmation here because the page
//! asks twice; a command reachable from the console with no confirmation is
//! a command the console can already do, file by file.

use tauri::{AppHandle, State};

use crate::commands::{recordings_dir, NotesStore};

/// Removes a directory and everything in it; a missing one is already done.
fn remove_dir(dir: Option<std::path::PathBuf>, what: &str) -> Result<(), String> {
    let Some(dir) = dir else { return Ok(()) };
    match std::fs::remove_dir_all(&dir) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("could not remove the {what} at {}: {e}", dir.display())),
    }
}

/// Everything a person made on this phone goes; the models too if `models`.
#[tauri::command]
pub fn reset_local_data(app: AppHandle, store: State<'_, NotesStore>, models: bool) -> Result<(), String> {
    store.lock().clear().map_err(|e| e.to_string())?;
    remove_dir(recordings_dir(&app), "recordings")?;
    remove_dir(crate::images::images_dir(&app), "pictures")?;
    // The Notion sign-in: a reset leaves no account behind.
    if let Some(path) = crate::notion::account_path(&app) {
        match std::fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(format!("could not forget the Notion account: {e}")),
        }
    }
    if models {
        remove_dir(crate::capture_commands::models_dir(&app).ok(), "models")?;
    }
    Ok(())
}
