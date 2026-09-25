//! `.glyph/library.json`, the library's own record of itself, and the one
//! move it has ever needed: the notes of the database they lived in before
//! 1.3.0 (`store.rs`), written out as files the first time the app opens
//! with the library.
//!
//! A move that stops halfway - the app killed, the storage full - is finished
//! by the next launch, because a note already in the library is never written
//! twice, and the old database is renamed away only once every note is out.

use std::path::Path;

use serde::{Deserialize, Serialize};

use super::dates::iso;
use super::frontmatter::{join, FrontMatter};
use super::names::{file_stem, title_of};
use super::sidecar::Sidecar;
use super::{Library, LibraryError, Result, INBOX};
use crate::note::now_ms;
use crate::store::Store;

/// The old database's file name in the app's data directory (DESIGN section 5).
pub const DB_FILE: &str = "glyph.sqlite";

/// `.glyph/library.json`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    version: u32,
    created: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    moved_from: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    moved_notes: Option<usize>,
}

/// Writes a fresh `library.json` into `glyph` unless one is there: the
/// library's birth, stamped now.
pub(super) fn ensure_manifest(glyph: &Path) -> Result<()> {
    let manifest = glyph.join("library.json");
    if !manifest.exists() {
        let fresh = Manifest { version: 1, created: iso(now_ms()), moved_from: None, moved_notes: None };
        crate::fsx::write_atomically(&manifest, serde_json::to_string_pretty(&fresh).unwrap_or_default().as_bytes())?;
    }
    Ok(())
}

/// Opens the library in `root`, and the first time, moves every note of the
/// old database at `<data_dir>/glyph.sqlite` into it as a file.
///
/// The old database is kept, renamed `glyph.sqlite.moved` (with its `-wal`
/// and `-shm` beside it), and only once every note is written out and the move
/// is recorded. A move that fails is said in the log and left for the next
/// launch; the library still opens, with what it already has.
pub fn open_and_move_in(root: &Path, data_dir: &Path) -> std::result::Result<Library, String> {
    let mut library = Library::open_fs(root).map_err(|e| e.to_string())?;
    let old = data_dir.join(DB_FILE);
    if old.exists() && !library.moved_in() {
        let store = Store::open(&old).map_err(|e| e.to_string())?;
        match library.move_in(&store) {
            Ok(moved) => {
                drop(store);
                library.mark_moved_in(DB_FILE, moved).map_err(|e| e.to_string())?;
                for suffix in ["", "-wal", "-shm"] {
                    let from = data_dir.join(format!("{DB_FILE}{suffix}"));
                    if from.exists() {
                        let _ = std::fs::rename(&from, data_dir.join(format!("{DB_FILE}.moved{suffix}")));
                    }
                }
                eprintln!("[glyph] moved {moved} notes from {DB_FILE} into the library");
            }
            Err(e) => eprintln!("[glyph] the move into the library stopped, and will finish next launch: {e}"),
        }
    }
    Ok(library)
}

impl Library {
    fn manifest(&self) -> Manifest {
        crate::fsx::read_json_or(&self.vault.glyph_dir().join("library.json"), Manifest::default())
    }

    /// Whether the old database's notes were already written out.
    pub fn moved_in(&self) -> bool {
        self.manifest().moved_from.is_some()
    }

    /// Every note of the old database as a file in `Inbox/`, keeping its id, times, pin, archive, source,
    /// recording phrases and formatted version. A note already in the library is left alone, so a move
    /// that stopped halfway finishes the next time. Answers how many notes are in the library from it.
    pub fn move_in(&mut self, old: &Store) -> Result<usize> {
        let notes = old.list_notes().map_err(|e| LibraryError::Store(e.to_string()))?;
        let mut moved = 0;
        for listed in notes {
            if self.row(&listed.id)?.is_some() {
                moved += 1;
                continue;
            }
            let Some(note) = old.get_note(&listed.id).map_err(|e| LibraryError::Store(e.to_string()))? else { continue };
            // The old app saved a new note the moment it opened, so a note opened and left
            // has no words and nothing set: it isn't brought in as an empty "Untitled.md".
            let untouched = note.body.trim().is_empty() && !note.starred && note.archived_at.is_none() && note.recording_ms.is_none() && note.formatted.is_none();
            if untouched {
                continue;
            }
            let mut front = FrontMatter::new();
            super::stamp(&mut front, &note);
            let path = self.free_path(INBOX, &file_stem(&title_of(&note.body)));
            self.vault.write(&path, &join(Some(&front), &note.body))?;
            self.write_sidecar(&note.id, &Sidecar::from(&note))?;
            // The list keeps its order: the file says it was last changed when the note was.
            let entry = self.vault.keep_modified(&path, note.updated_at)?;
            self.index_file(&entry)?;
            moved += 1;
        }
        Ok(moved)
    }

    /// Records that the old database was moved in, so it is never moved twice.
    pub fn mark_moved_in(&self, from: &str, notes: usize) -> Result<()> {
        let mut manifest = self.manifest();
        if manifest.version == 0 {
            manifest.version = 1;
            manifest.created = iso(now_ms());
        }
        manifest.moved_from = Some(from.to_string());
        manifest.moved_notes = Some(notes);
        crate::fsx::write_atomically(&self.vault.glyph_dir().join("library.json"), serde_json::to_string_pretty(&manifest).unwrap_or_default().as_bytes())?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp() -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("glyph-move-in-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn names(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        names.sort();
        names
    }

    #[test]
    fn the_first_launch_moves_the_old_notes_in_and_puts_the_database_aside() {
        let data = temp();
        {
            let old = Store::open(&data.join(DB_FILE)).unwrap();
            old.save_note("m1", "# Kept\n\nfrom the old app", "editor").unwrap();
            // Held open, so its `-wal` and `-shm` are on disk beside it, as a killed app leaves them.
            let library = open_and_move_in(&data.join("Library"), &data).unwrap();
            assert!(library.moved_in());
        }
        let mut library = open_and_move_in(&data.join("Library"), &data).unwrap();
        assert_eq!(library.get_note("m1").unwrap().unwrap().body, "# Kept\n\nfrom the old app");
        let here = names(&data);
        assert!(here.contains(&"glyph.sqlite.moved".to_string()) && !here.contains(&DB_FILE.to_string()), "{here:?}");
        assert!(here.iter().all(|name| !name.starts_with("glyph.sqlite-")), "the journal goes aside with it: {here:?}");
        assert!(here.contains(&"glyph.sqlite.moved-wal".to_string()) && here.contains(&"glyph.sqlite.moved-shm".to_string()), "{here:?}");
        let manifest: Manifest = crate::fsx::read_json(&data.join("Library/.glyph/library.json")).unwrap();
        assert_eq!((manifest.moved_from.as_deref(), manifest.moved_notes), (Some(DB_FILE), Some(1)));
        let _ = std::fs::remove_dir_all(&data);
    }

    #[test]
    fn a_library_already_moved_into_never_reads_a_database_that_reappears() {
        let data = temp();
        let library = Library::open_fs(&data.join("Library")).unwrap();
        library.mark_moved_in(DB_FILE, 0).unwrap();
        let old = Store::open(&data.join(DB_FILE)).unwrap();
        old.save_note("late", "written after the move", "editor").unwrap();
        drop(old);
        let mut library = open_and_move_in(&data.join("Library"), &data).unwrap();
        assert_eq!(library.get_note("late").unwrap(), None, "a move happens once");
        assert!(data.join(DB_FILE).exists(), "and a file it did not move is left where it is");
        let _ = std::fs::remove_dir_all(&data);
    }

    #[test]
    fn a_new_library_records_its_birth_once() {
        let data = temp();
        let glyph = data.join(".glyph");
        std::fs::create_dir_all(&glyph).unwrap();
        ensure_manifest(&glyph).unwrap();
        let first = std::fs::read_to_string(glyph.join("library.json")).unwrap();
        assert!(first.contains("\"version\": 1") && first.contains("\"created\": \"20"), "{first}");
        ensure_manifest(&glyph).unwrap();
        assert_eq!(std::fs::read_to_string(glyph.join("library.json")).unwrap(), first);
        let _ = std::fs::remove_dir_all(&data);
    }
}
