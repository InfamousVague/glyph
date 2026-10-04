//! The library opened where `library-root.json` says it is (library/root.rs),
//! for everything in the process that opens one: the app at launch and after a
//! move (commands.rs, library_commands.rs), a meeting's write-up over JNI with
//! no Tauri around it (write_up.rs), and the reset going home (reset.rs).
//!
//! NOT ONE `tauri::` TYPE, for the write-up's sake: it takes the app's data
//! directory as a path, as `write_up` does. It is outside library/ only
//! because a folder chosen on Android is reached through JNI (saf.rs), which
//! the Tauri-free library, compiled on its own by tools/host-tests, must not
//! name.
//!
//! A CHOSEN FOLDER THAT CANNOT BE REACHED (a backup drive unplugged, a Dropbox
//! folder moved, Android's grant taken back): the app opens its own folder for
//! this run, says so in the log and on the plugin's page (a library in its own
//! folder while the setting names another, library_commands.rs `Status`), and
//! keeps the choice, so the folder is tried again at the next launch. Nothing is made where it was: a
//! folder that is not there is never created empty, which would read as a
//! library with every note gone.

use std::path::{Path, PathBuf};

use crate::library::root::Root;
use crate::library::vault::FsVault;
use crate::library::Library;

/// `<app_data_dir>/Library`, the app's own folder.
pub fn own_folder(data_dir: &Path) -> PathBuf {
    data_dir.join(crate::paths::LIBRARY)
}

/// The library where the setting says, or the app's own folder while that cannot be reached. `move_in` is the app's
/// launch, which also brings the old database in (library/move_in.rs); a write-up opens without it.
pub fn open(data_dir: &Path, move_in: bool) -> Result<Library, String> {
    let chosen = Root::read(data_dir);
    if chosen == Root::App {
        return open_own(data_dir, move_in);
    }
    open_root(data_dir, &chosen).or_else(|e| {
        eprintln!("[glyph] the library's folder could not be opened, so the app's own is, until it can be: {e}");
        open_own(data_dir, move_in)
    })
}

/// The app's own folder, made if it is not there yet.
pub fn open_own(data_dir: &Path, move_in: bool) -> Result<Library, String> {
    let own = own_folder(data_dir);
    if move_in {
        crate::library::open_and_move_in(&own, data_dir)
    } else {
        Library::open_fs(&own).map_err(|e| e.to_string())
    }
}

/// The library at `root` itself, or why it cannot be opened: a chosen folder must already be there.
pub fn open_root(data_dir: &Path, root: &Root) -> Result<Library, String> {
    match root {
        Root::App => open_own(data_dir, true),
        Root::Folder { path } => {
            if !path.is_dir() {
                return Err(format!("{} is not there", path.display()));
            }
            let vault = FsVault::new(path).map_err(|e| format!("{}: {e}", path.display()))?;
            Library::open_chosen(Box::new(vault), &root.index_file(data_dir)).map_err(|e| e.to_string())
        }
        #[cfg(target_os = "android")]
        Root::Tree { uri, .. } => {
            let docs = crate::saf::TreeDocuments::new(uri)?;
            let vault = crate::library::tree::TreeVault::new(docs, &root.tree_glyph_dir(data_dir)).map_err(|e| e.to_string())?;
            Library::open_chosen(Box::new(vault), &root.index_file(data_dir)).map_err(|e| e.to_string())
        }
        #[cfg(not(target_os = "android"))]
        Root::Tree { .. } => Err("a folder chosen on an Android phone".into()),
    }
}

/// Whether one of two folders is the other or inside it: a library cannot move into itself, or into a folder that
/// holds it, without listing its own notes twice. Compared as the disk has them (`canonicalize`), so a link or a
/// `..` cannot hide the overlap.
pub fn overlap(a: &Path, b: &Path) -> bool {
    let real = |p: &Path| p.canonicalize().unwrap_or_else(|_| p.to_path_buf());
    let (a, b) = (real(a), real(b));
    a.starts_with(&b) || b.starts_with(&a)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn the_library_opens_where_the_setting_says_and_at_home_while_that_is_away() {
        let data = TempDir::new("library-root");
        assert!(open(&data, true).unwrap().in_own_folder());

        let vault = data.join("Vault");
        std::fs::create_dir_all(&vault).unwrap();
        std::fs::write(vault.join("Theirs.md"), "# Theirs\n").unwrap();
        Root::Folder { path: vault.clone() }.write(&data).unwrap();
        let mut library = open(&data, true).unwrap();
        assert!(!library.in_own_folder());
        assert_eq!(library.list_notes().unwrap().len(), 1);
        assert_eq!(library.folder().as_deref(), Some(vault.as_path()));

        // Unplugged: the app's own folder for now, the choice kept, and nothing made where the folder was.
        let gone = data.join("Backup drive/Notes");
        Root::Folder { path: gone.clone() }.write(&data).unwrap();
        assert!(open(&data, false).unwrap().in_own_folder());
        assert!(!gone.exists(), "a folder that is not there is never made empty");
        assert_eq!(Root::read(&data), Root::Folder { path: gone });

        Root::Tree { uri: "content://x/tree/y".into(), name: "y".into() }.write(&data).unwrap();
        assert!(open(&data, false).unwrap().in_own_folder(), "a phone's folder is not one the Mac can open");
    }

    #[test]
    fn a_folder_inside_the_library_or_round_it_overlaps() {
        let data = TempDir::new("library-overlap");
        let library = data.join("Library");
        std::fs::create_dir_all(library.join("Work")).unwrap();
        std::fs::create_dir_all(data.join("Elsewhere")).unwrap();
        assert!(overlap(&library, &library.join("Work")));
        assert!(overlap(&library.join("Work"), &data));
        assert!(overlap(&library, &data.join("Library/Work/..")));
        assert!(!overlap(&library, &data.join("Elsewhere")));
        assert!(!overlap(&data.join("Library 2"), &library), "a name that starts the same is another folder");
    }
}
