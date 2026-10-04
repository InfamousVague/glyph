//! Starting over: the one command that empties the phone of what Glyph made.
//!
//! `reset_local_data({ models })` removes every note from the library (the
//! files, what is kept beside them, and the index), the recordings, pictures
//! and films, what waits in the cache's `picked/` to be kept, the meetings'
//! write-ups (`jobs/`), the Notion sign-in, the Slack webhooks, and - only
//! when asked - the models directory, whisper's and the formatter's alike. The
//! page clears what it keeps itself (preferences, the guide's seen flag, the
//! refine queue) and reloads; on Android it cancels the write-ups' WorkManager
//! chain first (`GlyphHost.cancelWriteUps`), which Rust cannot reach.
//!
//! A LIBRARY IN A FOLDER OF THE PERSON'S IS NEVER EMPTIED (docs/DESIGN.md
//! §187): an Obsidian vault, a Dropbox folder or a backup drive is theirs, and
//! "everything Glyph made" is not the notes they keep there. The reset forgets
//! the folder instead - the choice, its index and the `.glyph/` an Android
//! folder keeps in the app's storage - and goes back to the app's own folder,
//! which it empties as it always did. Every file in the chosen folder stays,
//! `.glyph/` in it included.
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
use crate::library::root::Root;
use crate::paths;

/// Where the things a reset removes are kept on this device, each `None` where
/// the platform gave no directory - which leaves nothing there to remove.
struct Kept {
    /// `<app_data_dir>`, where the library's setting is, and a chosen folder's index.
    data: Option<PathBuf>,
    recordings: Option<PathBuf>,
    images: Option<PathBuf>,
    videos: Option<PathBuf>,
    picked: Option<PathBuf>,
    jobs: Option<PathBuf>,
    notion: Option<PathBuf>,
    slack: Option<PathBuf>,
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
        data: paths::data_dir(&app).ok(),
        recordings: paths::recordings_dir(&app).ok(),
        images: paths::images_dir(&app).ok(),
        videos: paths::videos_dir(&app).ok(),
        picked: paths::picked_dir(&app).ok(),
        jobs: paths::jobs_dir(&app).ok(),
        notion: crate::notion::account_path(&app).ok(),
        slack: crate::slack::webhooks_path(&app).ok(),
        models: paths::models_dir(&app).ok(),
    };
    reset(&store, &kept, models)
}

/// The reset itself, in the order it has always run: the notes, then the
/// recordings, pictures, films and write-ups, then the Notion sign-in and the
/// Slack webhooks, then - if asked - the models. The first failure stops it and
/// is the answer.
fn reset(notes: &NotesStore, kept: &Kept, models: bool) -> Result<(), String> {
    {
        let mut library = notes.lock();
        if let Some(data) = &kept.data {
            // Forgotten, and the app's own folder opened in its place, before anything is cleared: a folder of the
            // person's is never the library a clear runs on. A choice that could not be reached is forgotten too.
            Root::App.write(data).map_err(|e| format!("could not forget the library's folder: {e}"))?;
            if !library.in_own_folder() {
                *library = crate::library_root::open_own(data, false)?;
            }
        }
        // And should it still be one, a chosen folder's clear only forgets its index (library/mod.rs `clear`).
        library.clear().map_err(|e| e.to_string())?;
    }
    if let Some(data) = &kept.data {
        for dir in crate::library_commands::bookkeeping(data) {
            remove_dir(Some(&dir), "library's index")?;
        }
    }
    remove_dir(kept.recordings.as_deref(), "recordings")?;
    remove_dir(kept.images.as_deref(), "pictures")?;
    remove_dir(kept.videos.as_deref(), "videos")?;
    remove_dir(kept.picked.as_deref(), "picked files")?;
    remove_dir(kept.jobs.as_deref(), "jobs")?;
    // The Notion sign-in: a reset leaves no account behind.
    if let Some(path) = &kept.notion {
        crate::fsx::remove_file_if_present(path).map_err(|e| format!("could not forget the Notion account: {e}"))?;
    }
    // The Slack webhooks: each one is a key to post to a channel, and none outlives a reset.
    if let Some(path) = &kept.slack {
        crate::fsx::remove_file_if_present(path).map_err(|e| format!("could not forget the Slack webhooks: {e}"))?;
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
    use crate::test_support::TempDir;
    use std::sync::Mutex;

    /// A phone's worth of what a person made, under one temporary directory.
    fn phone() -> (TempDir, NotesStore, Kept) {
        let root = TempDir::new("reset");
        let mut library = Library::open_fs(&root.join("Library")).unwrap();
        library.save_note("n1", "# Kept until now\n\n![](image/a.jpg)\n[![video 0:12](image/a.jpg)](video/f.mp4)\n", "capture").unwrap();
        for file in ["recordings/n1.wav", "images/a.jpg", "video/f.mp4", "video/.orphans.json", "cache/picked/p.mp4", "jobs/n1.progress", "models/ggml-base.en-q5_1.bin"] {
            std::fs::create_dir_all(root.join(file).parent().unwrap()).unwrap();
            std::fs::write(root.join(file), b"bytes").unwrap();
        }
        std::fs::write(root.join("notion.json"), br#"{"accessToken":"secret_x"}"#).unwrap();
        std::fs::write(root.join("slack.json"), br#"{"channels":{"a1":"https://hooks.slack.com/services/T0/B0/x"}}"#).unwrap();
        let kept = Kept {
            data: Some(root.to_path_buf()),
            recordings: Some(root.join("recordings")),
            images: Some(root.join("images")),
            videos: Some(root.join("video")),
            picked: Some(root.join("cache/picked")),
            jobs: Some(root.join("jobs")),
            notion: Some(root.join("notion.json")),
            slack: Some(root.join("slack.json")),
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
        assert!(!root.join("jobs").exists(), "the write-ups go with the recordings");
        assert!(!root.join("video").exists(), "the films go with the pictures");
        assert!(!root.join("cache/picked").exists() && root.join("cache").exists(), "and what waited to be kept, not the rest of the cache");
        assert!(!root.join("notion.json").exists(), "no account is left signed in");
        assert!(!root.join("slack.json").exists(), "no webhook is left to post with");
        assert!(root.join("models/ggml-base.en-q5_1.bin").exists(), "a 60 MB download is not thrown away unasked");
        reset(&notes, &kept, false).unwrap();
    }

    #[test]
    fn a_reset_never_deletes_a_folder_of_the_persons_and_goes_back_to_the_apps_own() {
        let (root, _, kept) = phone();
        let vault = root.join("Obsidian");
        for (file, text) in [("Theirs.md", "# Theirs\n"), (".obsidian/app.json", "{}"), ("Daily/2026-10-04.md", "a walk\n")] {
            std::fs::create_dir_all(vault.join(file).parent().unwrap()).unwrap();
            std::fs::write(vault.join(file), text).unwrap();
        }
        let chosen = Root::Folder { path: vault.clone() };
        chosen.write(&root).unwrap();
        let notes = NotesStore(Mutex::new(crate::library_root::open(&root, true).unwrap()));
        notes.lock().save_note("mine", "# Written into the vault\n", "editor").unwrap();
        assert!(chosen.index_file(&root).exists());

        reset(&notes, &kept, false).unwrap();
        for file in ["Theirs.md", ".obsidian/app.json", "Daily/2026-10-04.md", "Inbox/Written into the vault.md", ".glyph/library.json"] {
            assert!(vault.join(file).exists(), "{file} is the person's, and stays");
        }
        assert_eq!(Root::read(&root), Root::App, "the folder is forgotten");
        assert!(!root.join("index").exists(), "with its index");
        assert!(notes.lock().in_own_folder() && notes.lock().list_notes().unwrap().is_empty(), "and the app starts from its own folder, empty");
        assert!(!root.join("Library/Inbox/Kept until now.md").exists(), "which is cleared as it always was");
    }

    #[test]
    fn a_reset_asked_to_takes_the_models_too() {
        let (root, notes, kept) = phone();
        reset(&notes, &kept, true).unwrap();
        assert!(!root.join("models").exists());
        notes.lock().save_note("n2", "after the reset", "editor").unwrap();
        assert_eq!(notes.lock().list_notes().unwrap().len(), 1, "the library carries on");
    }
}
