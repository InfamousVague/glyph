//! Where the library lives: the app's own folder, or a folder the person chose
//! (docs/LIBRARY.md "Choosing the folder", docs/DESIGN.md §185). Matt: "include
//! #6 as a plugin", #6 being "An Obsidian vault, iCloud Drive or Dropbox. Notes
//! are already plain Markdown files. Letting you choose where the library
//! folder lives would make Obsidian, backups and other editors work for free."
//!
//! ONE FILE SAYS WHICH: `<app_data_dir>/library-root.json`, absent for the
//! app's own folder. Rust reads it here and nowhere else (`Root::read`): the
//! app at launch and every reopen (library_root.rs), a meeting's write-up over
//! JNI with no Tauri in the process, the export, Reveal and the reset all come
//! through that one function. Kotlin reads it too, from its own `Context`
//! (files/LibraryTree.kt, the twin paths.rs's test holds to this name).
//!
//! THE INDEX IS NEVER IN A CHOSEN FOLDER. SQLite in WAL mode is three files
//! that change together, and a sync service (iCloud Drive, Dropbox, Syncthing)
//! copies them one at a time at moments of its own: a torn index at best, and
//! with two Macs on one Dropbox folder, each writing the other's, an
//! `index (conflicted copy).sqlite` beside it. It is only a cache, so for a
//! chosen folder it lives in the app's storage, at `index/<key>.sqlite`, the
//! key a hash of where the folder is. What else is in `.glyph/` stays in the
//! folder: `library.json` and `notes/<id>.json` are small JSON written whole,
//! which sync carries as it carries the notes, so a recording's phrases go
//! wherever its note goes. Through Android's Storage Access Framework the
//! folder has no paths SQLite or a sidecar could use, so `.glyph/` itself is in
//! the app's storage too, at `trees/<key>/` (tree.rs).
//!
//! The app's own folder keeps the layout it always had, index and all, so a
//! person who never chooses a folder has nothing moved.

use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// `<app_data_dir>/library-root.json`. KOTLIN TWIN: `files/LibraryTree.kt`,
/// `File(context.dataDir, "library-root.json")`.
pub const ROOT_FILE: &str = "library-root.json";

/// `<app_data_dir>/index/`: a chosen folder's index, `<key>.sqlite` with its `-wal` and `-shm`.
pub const INDEXES: &str = "index";

/// `<app_data_dir>/trees/`: an Android folder's `.glyph/`, `<key>/`.
pub const TREES: &str = "trees";

/// Where the library is.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Root {
    /// `<app_data_dir>/Library`, as it has always been.
    App,
    /// A folder on the computer, by its path: the Mac's.
    Folder { path: PathBuf },
    /// A folder Android's picker granted, by its tree URI, and the name the picker showed for it.
    Tree {
        uri: String,
        #[serde(default)]
        name: String,
    },
}

impl Root {
    /// What `library-root.json` says, or the app's own folder when there is none. A file that cannot be read is
    /// said in the log and is the app's own folder too: the chosen folder is still there, untouched, to choose again.
    pub fn read(data_dir: &Path) -> Root {
        let path = data_dir.join(ROOT_FILE);
        if !path.exists() {
            return Root::App;
        }
        crate::fsx::read_json(&path).unwrap_or_else(|| {
            eprintln!("[glyph] {ROOT_FILE} could not be read: the library opens in the app's own folder");
            Root::App
        })
    }

    /// Keeps this as where the library is, whole or not at all; the app's own folder is no file at all.
    pub fn write(&self, data_dir: &Path) -> io::Result<()> {
        let path = data_dir.join(ROOT_FILE);
        if *self == Root::App {
            return crate::fsx::remove_file_if_present(&path);
        }
        std::fs::create_dir_all(data_dir)?;
        crate::fsx::write_atomically(&path, serde_json::to_string_pretty(self).unwrap_or_default().as_bytes())
    }

    /// A short name for where it is, the same for the same place on every launch: FNV-1a of the path or URI, in
    /// hex. Not std's hasher, whose output may change with the compiler, which would orphan every index.
    pub fn key(&self) -> String {
        let place = match self {
            Root::App => "app".to_string(),
            Root::Folder { path } => format!("folder:{}", path.display()),
            Root::Tree { uri, .. } => format!("tree:{uri}"),
        };
        format!("{:016x}", fnv1a(&place))
    }

    /// A chosen folder's index, in the app's storage: `<app_data_dir>/index/<key>.sqlite`.
    pub fn index_file(&self, data_dir: &Path) -> PathBuf {
        data_dir.join(INDEXES).join(format!("{}.sqlite", self.key()))
    }

    /// An Android folder's `.glyph/`, in the app's storage: `<app_data_dir>/trees/<key>`.
    pub fn tree_glyph_dir(&self, data_dir: &Path) -> PathBuf {
        data_dir.join(TREES).join(self.key())
    }

    /// What the page calls it: `app`, `folder` or `tree`.
    pub fn kind(&self) -> &'static str {
        match self {
            Root::App => "app",
            Root::Folder { .. } => "folder",
            Root::Tree { .. } => "tree",
        }
    }
}

/// 64-bit FNV-1a.
fn fnv1a(text: &str) -> u64 {
    text.bytes().fold(0xcbf2_9ce4_8422_2325, |hash, byte| (hash ^ u64::from(byte)).wrapping_mul(0x0000_0100_0000_01b3))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn no_file_is_the_apps_own_folder_and_a_choice_is_kept_until_it_changes() {
        let data = TempDir::new("root");
        assert_eq!(Root::read(&data), Root::App);
        let vault = Root::Folder { path: PathBuf::from("/Users/matt/Obsidian/Notes") };
        vault.write(&data).unwrap();
        assert_eq!(Root::read(&data), vault);
        let text = std::fs::read_to_string(data.join(ROOT_FILE)).unwrap();
        assert!(text.contains("\"kind\": \"folder\"") && text.contains("/Users/matt/Obsidian/Notes"), "{text}");
        let tree = Root::Tree { uri: "content://com.android.externalstorage.documents/tree/primary%3ANotes".into(), name: "Notes".into() };
        tree.write(&data).unwrap();
        assert_eq!(Root::read(&data), tree);
        Root::App.write(&data).unwrap();
        assert!(!data.join(ROOT_FILE).exists(), "the app's own folder is no file at all");
        assert_eq!(Root::read(&data), Root::App);
    }

    #[test]
    fn a_file_that_cannot_be_read_opens_the_apps_own_folder() {
        let data = TempDir::new("root-broken");
        std::fs::write(data.join(ROOT_FILE), "{ not json").unwrap();
        assert_eq!(Root::read(&data), Root::App);
        std::fs::write(data.join(ROOT_FILE), r#"{"kind":"tree","uri":"content://x/tree/y"}"#).unwrap();
        assert_eq!(Root::read(&data), Root::Tree { uri: "content://x/tree/y".into(), name: String::new() }, "a name is optional");
    }

    #[test]
    fn a_chosen_folders_index_is_in_the_apps_storage_named_for_the_place() {
        let data = TempDir::new("root-index");
        let a = Root::Folder { path: PathBuf::from("/Users/matt/Dropbox/Notes") };
        let b = Root::Folder { path: PathBuf::from("/Users/matt/Dropbox/Notes 2") };
        assert_eq!(a.key(), a.clone().key(), "the same place, the same key");
        assert_ne!(a.key(), b.key());
        assert_eq!(a.key().len(), 16);
        // FNV-1a's own test vector, so the key cannot drift with a refactor.
        assert_eq!(fnv1a("a"), 0xaf63_dc4c_8601_ec8c);
        assert_eq!(a.index_file(&data), data.join("index").join(format!("{}.sqlite", a.key())));
        let tree = Root::Tree { uri: "content://x/tree/y".into(), name: "y".into() };
        assert_eq!(tree.tree_glyph_dir(&data), data.join("trees").join(tree.key()));
        assert_eq!((Root::App.kind(), a.kind(), tree.kind()), ("app", "folder", "tree"));
    }
}
