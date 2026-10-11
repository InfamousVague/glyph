//! The Library folder plugin's doors (src/app/plugins/folder/; docs/DESIGN.md
//! §187). Native generation 25. Matt: "include #6 as a plugin", #6 being "An
//! Obsidian vault, iCloud Drive or Dropbox. Notes are already plain Markdown
//! files. Letting you choose where the library folder lives would make
//! Obsidian, backups and other editors work for free."
//!
//! - `library_root`: where the library is now, and whether a chosen folder
//!   could be reached.
//! - **The Mac**, `library_choose_folder`: the system's folder panel; the folder
//!   picked is looked into (how many Markdown files, whether Obsidian keeps
//!   it) and held, and nothing is written there yet.
//! - **Android**, `library_inspect`: the activity's picker granted a folder
//!   (MainActivity `GlyphHost.chooseLibraryFolder`, files/LibraryTree.kt,
//!   answered as `window.__glyph.libraryFolder`) and the page names it here, to
//!   be looked into and held the same way.
//! - `library_move`: the folder held becomes the library (library/relocate.rs):
//!   its own Markdown files become notes, the app's notes are copied in beside
//!   them, the setting switches, and only then do the notes leave the app's
//!   own folder. The new library replaces the old one in the running app,
//!   drafts carried, so nothing restarts.
//! - `library_use_app_folder`: back to the app's own folder, with a copy of
//!   every note or with none. The chosen folder keeps every file either way.
//!
//! Only a folder the person picked in the system's own panel or picker can be
//! moved into: the page holds no path of its own to send, so a page that went
//! wrong cannot point the library at a folder nobody chose.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::Serialize;
use tauri::{AppHandle, Manager, State};

use crate::commands::NotesStore;
use crate::library::root::Root;
use crate::library::Copied;
use crate::library_root;

/// The folder picked and looked into, until it is moved into or another is picked.
#[derive(Default)]
pub struct LibraryPick(Mutex<Option<Root>>);

pub fn install(app: &tauri::App) {
    app.manage(LibraryPick::default());
}

/// Where the library is, as the page shows it.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    /// `app`, `folder` or `tree`: what the setting says.
    kind: &'static str,
    /// The chosen folder's path, on the Mac.
    path: Option<String>,
    /// Its name: the folder's own, or the one Android's picker showed.
    name: Option<String>,
    /// False while a chosen folder cannot be reached and the app's own is open instead.
    reachable: bool,
    /// Notes in the library that is open.
    notes: usize,
    /// The app's own folder.
    own: Option<String>,
}

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

fn named(path: &Path) -> String {
    path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| path.display().to_string())
}

fn status_of(data: &Path, store: &NotesStore) -> Status {
    let chosen = Root::read(data);
    let library = store.lock();
    let reachable = chosen == Root::App || !library.in_own_folder();
    let (path, name) = match &chosen {
        Root::App => (None, None),
        Root::Folder { path } => (Some(path.display().to_string()), Some(named(path))),
        Root::Tree { name, .. } => (None, Some(name.clone())),
    };
    Status { kind: chosen.kind(), path, name, reachable, notes: library.note_count().unwrap_or(0), own: Some(library_root::own_folder(data).display().to_string()) }
}

/// Where the library is now.
#[tauri::command]
pub fn library_root(app: AppHandle, store: State<'_, NotesStore>) -> Result<Status, String> {
    Ok(status_of(&crate::paths::data_dir(&app)?, &store))
}

/// The Mac: the folder panel, and the folder picked looked into and held. `null` when the panel was closed.
#[tauri::command(async)]
pub fn library_choose_folder(app: AppHandle, store: State<'_, NotesStore>, pick: State<'_, LibraryPick>) -> Result<Option<Candidate>, String> {
    #[cfg(mobile)]
    {
        let _ = (app, store, pick);
        Err("On a phone the folder is chosen in the phone's own picker.".into())
    }
    #[cfg(desktop)]
    {
        use tauri_plugin_dialog::DialogExt;
        let Some(chosen) = app.dialog().file().set_title("Choose a folder for your notes").blocking_pick_folder() else {
            return Ok(None);
        };
        let path = chosen.into_path().map_err(|e| e.to_string())?;
        let data = crate::paths::data_dir(&app)?;
        let candidate = look_into_folder(&data, &store, &path)?;
        *crate::lock::lock(&pick.0) = Some(Root::Folder { path });
        Ok(Some(candidate))
    }
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

/// Android: the folder the activity's picker granted, looked into and held.
#[tauri::command(async)]
pub fn library_inspect(store: State<'_, NotesStore>, pick: State<'_, LibraryPick>, uri: String) -> Result<Candidate, String> {
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
        Ok(Candidate { kind: "tree", path: None, name: looked.name, markdown: looked.markdown, obsidian: looked.obsidian, notes })
    }
}

/// The folder held becomes the library, the notes copied in and then out of the app's own folder.
#[tauri::command(async)]
pub fn library_move(app: AppHandle, store: State<'_, NotesStore>, pick: State<'_, LibraryPick>) -> Result<Moved, String> {
    let to = crate::lock::lock(&pick.0).take().ok_or_else(|| "Choose a folder first.".to_string())?;
    if crate::paths::library_root(&app)? == to {
        return Err("That folder is already where your notes are.".into());
    }
    let data = crate::paths::data_dir(&app)?;
    let (copied, removed) = relocate(&data, &store, &to, true)?;
    Ok(moved(&copied, removed, status_of(&data, &store)))
}

/// Back to the app's own folder: with a copy of every note (`copy`), or with none. The chosen folder keeps all its
/// files.
#[tauri::command(async)]
pub fn library_use_app_folder(app: AppHandle, store: State<'_, NotesStore>, copy: bool) -> Result<Moved, String> {
    let data = crate::paths::data_dir(&app)?;
    let (copied, removed) = relocate(&data, &store, &Root::App, copy)?;
    Ok(moved(&copied, removed, status_of(&data, &store)))
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

#[cfg(test)]
mod tests {
    use super::*;
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
        let status = status_of(&data, &store);
        assert_eq!((status.kind, status.reachable, status.notes, status.name.as_deref()), ("folder", true, 2, Some("Vault")));
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
}
