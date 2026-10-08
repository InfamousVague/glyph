//! The library's folder, moved and gone back from (docs/DESIGN.md §187): `../glyph/src-tauri/src/library_commands.rs`,
//! whose commands take Tauri's `AppHandle` and `State` and open the Mac's folder panel, so it cannot be included
//! whole. What a folder is said to hold, the move itself and what a reset forgets are that file's own lines
//! between the marks, and `kept::tests` holds them to the original; its tests came with them.
//!
//! The commands, each as its `#[tauri::command]` there, taking the JSON the page sent:
//!
//! - `library_inspect {uri}` (Android) -> `{kind: "tree", path: null, name, markdown, obsidian, notes}`: the folder
//!   the phone's picker granted (android/…/glyph/files/LibraryTree.kt, reached through saf.rs) looked into, with
//!   nothing written there, and held.
//! - `library_move` -> `{notes, adopted, renamed, same, removed, status}`: the folder held becomes the library.
//! - `library_use_app_folder {copy}` -> the same: back to the app's own folder, with a copy of every note or none.
//!
//! `library_root` is dispatch.rs's, as it was before a folder could be chosen.
//!
//! What differs:
//!
//! - **The folder held** is the open core's ([`LibraryPick`] in dispatch.rs's `Core`), where Tauri managed it.
//! - **No `library_choose_folder`**: the Mac's folder panel is the Mac target's, stage 10. [`look_into_folder`],
//!   which that command stood on, is here with its test for the day it is, and is called by nothing else yet.
//! - **A move is not a long job** (work.rs): it holds the notes' lock from its first read to its last write, so
//!   no other command could be answered meanwhile whichever thread it ran on.

// Until the Mac has a panel only `look_into_folder`'s test calls it. (It carries the Tauri app's
// `cfg_attr(mobile, …)`: Cargo.toml tells the compiler that name is expected, and it is never set here.)
#![allow(dead_code)]

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::dispatch::{named, read, status_of, NotesStore, Status};
use crate::library::root::Root;
use crate::library::Copied;
use crate::library_root;

// copied:begin
/// The folder picked and looked into, until it is moved into or another is picked.
#[derive(Default)]
pub struct LibraryPick(Mutex<Option<Root>>);

/// A folder picked and looked into.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Candidate {
    kind: &'static str,
    path: Option<String>,
    name: String,
    /// Markdown files already in it: each becomes a note.
    markdown: usize,
    /// An `.obsidian` folder in it.
    obsidian: bool,
    /// The notes that will be copied in from where the library is now.
    notes: usize,
}

/// What a move did.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Moved {
    /// Notes written into the new folder.
    notes: usize,
    /// The new folder's own Markdown files, now notes.
    adopted: usize,
    /// Notes given " 2" because a file of that name was there.
    renamed: usize,
    /// Notes the new folder already had, word for word.
    same: usize,
    /// Notes taken out of the app's own folder once they were in the new one.
    removed: usize,
    status: Status,
}

/// A folder on the Mac, looked into without a thing written there, or why it cannot be the library.
#[cfg_attr(mobile, allow(dead_code))]
fn look_into_folder(data: &Path, store: &NotesStore, path: &Path) -> Result<Candidate, String> {
    if !path.is_dir() {
        return Err(format!("{} is not a folder.", path.display()));
    }
    let library = store.lock();
    if let Some(current) = library.folder() {
        if same_folder(&current, path) {
            return Err("That folder is already where your notes are.".into());
        }
        if library_root::overlap(&current, path) {
            return Err("That folder is inside the library, or holds it. Choose one beside it.".into());
        }
    }
    if library_root::overlap(data, path) {
        return Err("That folder is in Ghost.md's own storage, or holds it. Choose a folder of yours.".into());
    }
    use crate::library::vault::Vault as _;
    let markdown = crate::library::vault::FsVault::looking(path).markdown().map(|files| files.len()).map_err(|e| format!("{} could not be read: {e}", path.display()))?;
    Ok(Candidate {
        kind: "folder",
        path: Some(path.display().to_string()),
        name: named(path),
        markdown,
        obsidian: path.join(".obsidian").is_dir(),
        notes: library.note_count().unwrap_or(0),
    })
}

fn same_folder(a: &Path, b: &Path) -> bool {
    let real = |p: &Path| p.canonicalize().unwrap_or_else(|_| p.to_path_buf());
    real(a) == real(b)
}

fn moved(copied: &Copied, removed: usize, status: Status) -> Moved {
    Moved { notes: copied.notes, adopted: copied.adopted, renamed: copied.renamed, same: copied.same, removed, status }
}

/// The move itself, the running app's library swapped for the new one. Holds the store's lock and then every
/// other write in the process (a meeting's write-up on its own handle), in that order, which is the order every
/// command takes them in.
fn relocate(data: &Path, store: &NotesStore, to: &Root, copy: bool) -> Result<(Copied, usize), String> {
    let mut current = store.lock();
    let _writes = crate::library::hold_writes();
    let mut library = library_root::open_root(data, to).map_err(|e| format!("That folder could not be opened: {e}"))?;
    // A chosen folder that was away left the app's own open; going home from there is only forgetting the choice.
    let copied = if copy && !(to == &Root::App && current.in_own_folder()) {
        current.copy_into(&mut library).map_err(|e| format!("Nothing was moved: {e}"))?
    } else {
        Copied::default()
    };
    to.write(data).map_err(|e| format!("The notes are copied, but the choice could not be kept, so nothing was moved: {e}"))?;
    let removed = current.forget_copied(&copied);
    current.carry_drafts_into(&mut library);
    *current = library;
    Ok((copied, removed))
}

/// The folders a reset forgets: every chosen folder's index and an Android folder's `.glyph/`, all in the app's
/// storage (library/root.rs). Nothing in a chosen folder is among them.
pub fn bookkeeping(data: &Path) -> [PathBuf; 2] {
    [data.join(crate::library::root::INDEXES), data.join(crate::library::root::TREES)]
}
// copied:end

#[derive(Deserialize)]
struct Inspect {
    uri: String,
}

#[derive(Deserialize)]
struct UseAppFolder {
    copy: bool,
}

const COMMANDS: &[&str] = &["library_inspect", "library_move", "library_use_app_folder"];

/// Whether `command` is one of this file's.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

fn answer<T: Serialize>(value: T) -> Result<Value, String> {
    serde_json::to_value(value).map_err(|e| format!("the answer could not be written: {e}"))
}

/// One of this file's commands, for the core open on `data`.
pub fn call(data: &Path, store: &NotesStore, pick: &LibraryPick, command: &str, args: Value) -> Result<Value, String> {
    match command {
        // Android: the folder the activity's picker granted, looked into and held.
        "library_inspect" => {
            let Inspect { uri } = read(command, args)?;
            #[cfg(not(target_os = "android"))]
            {
                let _ = (store, pick, uri);
                Err("Only the Android app chooses a folder through its picker.".into())
            }
            #[cfg(target_os = "android")]
            {
                if !uri.starts_with("content://") {
                    return Err("That is not a folder the phone's picker gave.".into());
                }
                let looked = crate::saf::inspect(&uri).map_err(|e| format!("That folder could not be read: {e}"))?;
                let notes = store.lock().note_count().unwrap_or(0);
                *crate::lock::lock(&pick.0) = Some(Root::Tree { uri, name: looked.name.clone() });
                answer(Candidate { kind: "tree", path: None, name: looked.name, markdown: looked.markdown, obsidian: looked.obsidian, notes })
            }
        }
        // The folder held becomes the library, the notes copied in and then out of the app's own folder.
        "library_move" => {
            let to = crate::lock::lock(&pick.0).take().ok_or_else(|| "Choose a folder first.".to_string())?;
            if Root::read(data) == to {
                return Err("That folder is already where your notes are.".into());
            }
            let (copied, removed) = relocate(data, store, &to, true)?;
            answer(moved(&copied, removed, status_of(data, store)))
        }
        // Back to the app's own folder: with a copy of every note (`copy`), or with none. The chosen folder keeps
        // all its files.
        "library_use_app_folder" => {
            let UseAppFolder { copy } = read(command, args)?;
            let (copied, removed) = relocate(data, store, &Root::App, copy)?;
            answer(moved(&copied, removed, status_of(data, store)))
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dispatch::status_of;
    use serde_json::json;
    use crate::test_support::TempDir;

    #[test]
    fn a_move_swaps_the_running_library_and_going_home_keeps_the_folder() {
        let data = TempDir::new("library-commands");
        let store = NotesStore(Mutex::new(library_root::open(&data, true).unwrap()));
        store.lock().save_note("n1", "# Kept\n", "editor").unwrap();
        store.lock().save_note("d1", "", "editor").unwrap();
        // Out of the app's storage, as a person's folder is.
        let home = TempDir::new("library-commands-home");
        let vault = home.join("Vault");
        std::fs::create_dir_all(vault.join(".obsidian")).unwrap();
        std::fs::write(vault.join("Theirs.md"), "# Theirs\n").unwrap();

        let looked = look_into_folder(&data, &store, &vault).unwrap();
        assert_eq!((looked.markdown, looked.obsidian, looked.notes), (1, true, 1));
        assert!(!vault.join(".glyph").exists(), "looking writes nothing");
        assert!(look_into_folder(&data, &store, &data.join("Library/Inbox")).is_err(), "not inside the app's storage");

        let to = Root::Folder { path: vault.clone() };
        let (copied, removed) = relocate(&data, &store, &to, true).unwrap();
        assert_eq!((copied.notes, copied.adopted, removed), (1, 1, 1));
        assert_eq!(Root::read(&data), to);
        let status = serde_json::to_value(status_of(&data, &store)).unwrap();
        assert_eq!((status["kind"].as_str(), status["reachable"].as_bool(), status["notes"].as_u64(), status["name"].as_str()), (Some("folder"), Some(true), Some(2), Some("Vault")));
        assert_eq!(store.lock().get_note("d1").unwrap().map(|n| n.body), Some(String::new()), "the draft came too");
        assert!(look_into_folder(&data, &store, &vault).unwrap_err().contains("already"));
        // A save after the move lands in the folder.
        store.lock().save_note("n2", "# After\n", "editor").unwrap();
        assert!(vault.join("Inbox/After.md").exists());

        // Home again with a copy: the folder keeps every file.
        let (copied, removed) = relocate(&data, &store, &Root::App, true).unwrap();
        assert_eq!((copied.notes, removed), (3, 0));
        assert_eq!(Root::read(&data), Root::App);
        assert!(store.lock().in_own_folder() && store.lock().list_notes().unwrap().len() == 3);
        assert!(vault.join("Inbox/After.md").exists() && vault.join("Inbox/Kept.md").exists() && vault.join("Theirs.md").exists());
    }

    #[test]
    fn going_home_with_no_copy_starts_from_what_the_apps_folder_has() {
        let data = TempDir::new("library-commands-empty");
        let vault = data.join("Vault");
        std::fs::create_dir_all(&vault).unwrap();
        std::fs::write(vault.join("Theirs.md"), "# Theirs\n").unwrap();
        let to = Root::Folder { path: vault.clone() };
        to.write(&data).unwrap();
        let store = NotesStore(Mutex::new(library_root::open(&data, true).unwrap()));
        let (copied, removed) = relocate(&data, &store, &Root::App, false).unwrap();
        assert_eq!((copied.notes, removed), (0, 0));
        assert!(store.lock().list_notes().unwrap().is_empty());
        assert!(vault.join("Theirs.md").exists());
    }

    // From here on, this crate's own: the commands as the app calls them.

    fn asked(data: &Path, store: &NotesStore, pick: &LibraryPick, command: &str, args: Value) -> Result<Value, String> {
        call(data, store, pick, command, args)
    }

    #[test]
    fn the_folder_held_is_moved_into_once_and_home_is_gone_back_to() {
        let data = TempDir::new("library-commands-call");
        let store = NotesStore(Mutex::new(library_root::open(&data, true).unwrap()));
        store.lock().save_note("n1", "# Kept\n", "editor").unwrap();
        let home = TempDir::new("library-commands-call-home");
        let vault = home.join("Vault");
        std::fs::create_dir_all(&vault).unwrap();
        std::fs::write(vault.join("Theirs.md"), "# Theirs\n").unwrap();
        let pick = LibraryPick::default();
        assert!(has("library_move") && has("library_use_app_folder") && has("library_inspect") && !has("library_root"));

        // Nothing moves until a folder was picked in the system's own picker: the app sends no path.
        assert_eq!(asked(&data, &store, &pick, "library_move", json!({})), Err("Choose a folder first.".into()));
        assert_eq!(asked(&data, &store, &pick, "library_move", json!({"path": vault})), Err("Choose a folder first.".into()));
        // Off Android no picker grants a tree, and a tree that is not the picker's is refused before it is looked at.
        assert_eq!(asked(&data, &store, &pick, "library_inspect", json!({"uri": "content://x/tree/y"})), Err("Only the Android app chooses a folder through its picker.".into()));
        assert!(asked(&data, &store, &pick, "library_inspect", json!({})).unwrap_err().starts_with("invalid args for command `library_inspect`: missing field `uri`"));

        *crate::lock::lock(&pick.0) = Some(Root::Folder { path: vault.clone() });
        let moved = asked(&data, &store, &pick, "library_move", json!({})).unwrap();
        assert_eq!(moved, json!({"notes": 1, "adopted": 1, "renamed": 0, "same": 0, "removed": 1, "status": {"kind": "folder", "path": vault.display().to_string(), "name": "Vault", "reachable": true, "notes": 2, "own": data.join("Library").display().to_string()}}));
        assert!(vault.join("Inbox/Kept.md").exists() && !data.join("Library/Inbox/Kept.md").exists());
        assert_eq!(asked(&data, &store, &pick, "library_move", json!({})), Err("Choose a folder first.".into()), "the pick is taken by the move");
        *crate::lock::lock(&pick.0) = Some(Root::Folder { path: vault.clone() });
        assert_eq!(asked(&data, &store, &pick, "library_move", json!({})), Err("That folder is already where your notes are.".into()));

        assert!(asked(&data, &store, &pick, "library_use_app_folder", json!({})).unwrap_err().starts_with("invalid args for command `library_use_app_folder`: missing field `copy`"));
        let back = asked(&data, &store, &pick, "library_use_app_folder", json!({"copy": true})).unwrap();
        assert_eq!((back["notes"].as_u64(), back["removed"].as_u64(), back["status"]["kind"].as_str(), back["status"]["notes"].as_u64()), (Some(2), Some(0), Some("app"), Some(2)));
        assert!(vault.join("Inbox/Kept.md").exists() && vault.join("Theirs.md").exists(), "the folder keeps every file");
    }
}
