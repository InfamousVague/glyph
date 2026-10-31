//! The trash as a folder: `Library/.trash/`, as Obsidian keeps its own (Matt,
//! 2026-10-31: "Trash: a `.trash/` folder, as Obsidian does"; docs/MARKDOWN_FIRST.md
//! §11 decision 2).
//!
//! Trashing a note moves its file to `.trash/<its path>` - `workspaces/Work/Plan.md`
//! goes to `.trash/workspaces/Work/Plan.md` - with its versions file beside it,
//! and restoring moves it back to that path, or into `Inbox/` when the folder it
//! came from is gone. A name already taken where it lands gets the usual number
//! (`Plan 2.md`). What is kept beside a note by id (`.glyph/notes/<id>.json`)
//! does not move: it is not under the note's path. Emptying the trash is
//! `delete_note`, which takes a file at any path.
//!
//! The file's modified time is kept by the move, so a note comes back to its
//! place in the list; and the index row keeps its revision, since the body did
//! not change. The scan reads `.trash/` (vault.rs walks that one dot folder at
//! the root) and marks each file there `trashed` in the index (index.rs), so the
//! Trash and a restore work from the files, and a library restored from a
//! backup opens with its trashed notes trashed, not live. Nothing else in the
//! library treats a trashed note differently: the list carries it with its
//! `.trash/…` path, and the app keeps it out of every screen but the Trash
//! (lib/core/trash.dart `isTrashedPath`).
//!
//! Old builds never see these files: their walk skipped every dot folder, and
//! `library_path` refused a path under one from another device, so a note
//! trashed here is, on an old build, a live file in the synced trash map, which
//! the app still writes for a release (lib/core/kept_trash.dart).

use super::names::unique_name;
use super::{folder_of, in_folder, Library, Result, INBOX};
use crate::note::Note;

/// The folder at the library's root that holds trashed notes.
pub const TRASH: &str = ".trash";

/// Whether `path` is in the trash: under `.trash/` at the root.
pub fn is_trashed_path(path: &str) -> bool {
    path.starts_with(".trash/")
}

/// `.trash/<path>`: where a live note's file goes when it is trashed.
pub fn trashed_path_of(path: &str) -> String {
    format!("{TRASH}/{path}")
}

/// `<path>` for `.trash/<path>`: where a trashed note's file came from; `None` for a path not in the trash.
pub fn live_path_of(path: &str) -> Option<&str> {
    path.strip_prefix(".trash/").filter(|rest| !rest.is_empty())
}

/// A file's own stem: `workspaces/Work/Plan 2.md` → `Plan 2`. The file's, not the title's, so a note whose file was
/// not named for its title (a vault's own) keeps its name through the trash and back.
fn file_stem_of(path: &str) -> &str {
    let name = path.rsplit('/').next().unwrap_or(path);
    name.strip_suffix(".md").or_else(|| name.strip_suffix(".MD")).unwrap_or(name)
}

impl Library {
    /// Moves note `id`'s file (and its versions) into `.trash/` at its own path, answering the note as it now is -
    /// or `None` when nothing answers to that id. A note already in the trash is answered as it is; a draft with
    /// no file is written first, so there is a file to trash and to bring back.
    pub fn trash_note(&mut self, id: &str) -> Result<Option<Note>> {
        let _writing = super::writing();
        self.written(id)?;
        let Some(row) = self.row(id)? else { return Ok(None) };
        if row.trashed {
            return self.get_note(id);
        }
        let to = self.free_path(&trashed_path_of(folder_of(&row.path)), file_stem_of(&row.path));
        self.move_note_file(id, &row.path, &to)
    }

    /// Moves note `id`'s file (and its versions) out of `.trash/` to the path it had - or into `Inbox/` when the
    /// folder it came from is gone - answering the note as it now is, or `None` when nothing answers to that id. A
    /// note not in the trash is answered as it is.
    pub fn restore_note(&mut self, id: &str) -> Result<Option<Note>> {
        let _writing = super::writing();
        let Some(row) = self.row(id)? else { return Ok(None) };
        if !row.trashed {
            return self.get_note(id);
        }
        let Some(was) = live_path_of(&row.path) else { return self.get_note(id) };
        let folder = folder_of(was);
        let folder = if folder.is_empty() || self.vault.folder_exists(folder) { folder } else { INBOX };
        let to = in_folder(folder, &unique_name(file_stem_of(was), |name| self.vault.exists(&in_folder(folder, name))));
        self.move_note_file(id, &row.path, &to)
    }

    /// The note's file and versions moved from `from` to `to`, the row following: the time the file shows and its
    /// revision are kept, since a move is not an edit.
    fn move_note_file(&mut self, id: &str, from: &str, to: &str) -> Result<Option<Note>> {
        self.rename_note_file(from, to)?;
        let entry = self.vault.stat(to)?;
        let kept = self.vault.keep_modified(to, entry.modified_ms).unwrap_or(entry);
        self.index_file(&kept)?;
        self.get_note(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    fn read(root: &std::path::Path, path: &str) -> String {
        std::fs::read_to_string(root.join(path)).unwrap()
    }

    #[test]
    fn a_trashed_path_is_under_the_trash_folder_at_the_root() {
        assert!(is_trashed_path(".trash/Inbox/Plan.md") && is_trashed_path(".trash/Plan.md"));
        assert!(!is_trashed_path("Inbox/Plan.md") && !is_trashed_path("Work/.trash/Plan.md") && !is_trashed_path(".trashy/Plan.md"));
        assert_eq!(trashed_path_of("workspaces/Work/Plan.md"), ".trash/workspaces/Work/Plan.md");
        assert_eq!(live_path_of(".trash/workspaces/Work/Plan.md"), Some("workspaces/Work/Plan.md"));
        assert_eq!(live_path_of("workspaces/Work/Plan.md"), None);
        assert_eq!(live_path_of(".trash/"), None);
    }

    #[test]
    fn trashing_moves_the_file_and_its_versions_under_the_trash_at_its_own_path_and_restoring_moves_them_back() {
        let root = TempDir::new("trash-move");
        let mut library = Library::open_fs(&root).unwrap();
        let mut note = library.save_note("n1", "# Plan\n\nwords\n", "editor").unwrap();
        note.path = Some("workspaces/Work/Plan.md".into());
        let filed = library.apply_note(&note).unwrap();
        library.set_starred("n1", true).unwrap();
        assert!(library.write_versions("n1", "# Ghost.md versions 1\n").unwrap());
        std::thread::sleep(std::time::Duration::from_millis(20));

        let trashed = library.trash_note("n1").unwrap().unwrap();
        assert_eq!(trashed.path.as_deref(), Some(".trash/workspaces/Work/Plan.md"));
        assert_eq!((trashed.updated_at, trashed.revision, trashed.starred), (filed.updated_at, filed.revision, true), "a move is not an edit");
        assert!(!root.join("workspaces/Work/Plan.md").exists() && !root.join("workspaces/Work/Plan.versions").exists());
        assert_eq!(read(&root, ".trash/workspaces/Work/Plan.versions"), "# Ghost.md versions 1\n");
        assert!(read(&root, ".trash/workspaces/Work/Plan.md").ends_with("# Plan\n\nwords\n"));
        // Trashed again, it stays where it is.
        assert_eq!(library.trash_note("n1").unwrap().unwrap().path.as_deref(), Some(".trash/workspaces/Work/Plan.md"));

        // The list still carries it, at its trashed path, and the index knows it as trashed.
        let listed = library.list_notes().unwrap();
        assert_eq!(listed.len(), 1);
        assert!(library.row("n1").unwrap().unwrap().trashed);
        assert_eq!(library.read_versions("n1").unwrap().as_deref(), Some("# Ghost.md versions 1\n"), "its versions are found beside it in the trash");

        let back = library.restore_note("n1").unwrap().unwrap();
        assert_eq!(back.path.as_deref(), Some("workspaces/Work/Plan.md"));
        assert_eq!(back.updated_at, filed.updated_at);
        assert!(!library.row("n1").unwrap().unwrap().trashed);
        assert_eq!(read(&root, "workspaces/Work/Plan.versions"), "# Ghost.md versions 1\n");
        assert!(!root.join(".trash/workspaces/Work/Plan.md").exists());
        // Restored again, it stays.
        assert_eq!(library.restore_note("n1").unwrap().unwrap().path.as_deref(), Some("workspaces/Work/Plan.md"));
        assert_eq!(library.trash_note("nobody").unwrap(), None);
        assert_eq!(library.restore_note("nobody").unwrap(), None);
    }

    #[test]
    fn a_name_taken_in_the_trash_or_back_home_gets_a_number_and_a_gone_folder_restores_to_the_inbox() {
        let root = TempDir::new("trash-names");
        let mut library = Library::open_fs(&root).unwrap();
        library.save_note("a", "# Plan\n", "editor").unwrap();
        library.trash_note("a").unwrap();
        // A second note of the same name, trashed: the trash already holds `Plan.md`.
        library.save_note("b", "# Plan\n", "editor").unwrap();
        assert_eq!(library.trash_note("b").unwrap().unwrap().path.as_deref(), Some(".trash/Inbox/Plan 2.md"));
        // A third takes the name at home meanwhile, so the first comes back numbered.
        library.save_note("c", "# Plan\n", "editor").unwrap();
        assert_eq!(library.restore_note("a").unwrap().unwrap().path.as_deref(), Some("Inbox/Plan 2.md"));
        // `b` came from `Inbox/Plan 2.md`: the file's own name is kept, numbered on from it where that is taken.
        assert_eq!(library.restore_note("b").unwrap().unwrap().path.as_deref(), Some("Inbox/Plan 2 2.md"));

        // A note from a folder that is gone by the time it is restored lands in the Inbox.
        let mut filed = library.save_note("d", "# Deep\n", "editor").unwrap();
        filed.path = Some("workspaces/Old/Deep.md".into());
        library.apply_note(&filed).unwrap();
        library.trash_note("d").unwrap();
        std::fs::remove_dir_all(root.join("workspaces/Old")).unwrap();
        assert_eq!(library.restore_note("d").unwrap().unwrap().path.as_deref(), Some("Inbox/Deep.md"));
        // One whose folder is still there goes back to it.
        let mut kept = library.save_note("e", "# Kept\n", "editor").unwrap();
        kept.path = Some("workspaces/Work/Kept.md".into());
        library.apply_note(&kept).unwrap();
        library.trash_note("e").unwrap();
        assert_eq!(library.restore_note("e").unwrap().unwrap().path.as_deref(), Some("workspaces/Work/Kept.md"));
    }

    #[test]
    fn a_library_opened_over_a_trash_folder_indexes_its_notes_as_trashed_and_the_rest_as_live() {
        let root = TempDir::new("trash-restore");
        for (file, text) in [
            ("Inbox/Live.md", "---\nid: live\n---\n# Live\n"),
            (".trash/Inbox/Old.md", "---\nid: old\n---\n# Old\n"),
            (".trash/workspaces/Work/Gone.md", "# Gone\n"),
            // Another app's trash inside a folder is still no note, and nor is anything in another dot folder.
            ("Work/.trash/Deeper.md", "# Deeper\n"),
            (".trash/.obsidian/workspace.md", "not a note"),
        ] {
            std::fs::create_dir_all(root.join(file).parent().unwrap()).unwrap();
            std::fs::write(root.join(file), text).unwrap();
        }
        let mut library = Library::open_fs(&root).unwrap();
        let mut paths: Vec<String> = library.list_notes().unwrap().into_iter().map(|n| n.path.unwrap()).collect();
        paths.sort();
        let mut rows: Vec<(String, bool)> = ["live", "old"].iter().map(|id| library.row(id).unwrap().unwrap()).map(|r| (r.path, r.trashed)).collect();
        rows.sort();
        assert_eq!(paths, [".trash/Inbox/Old.md", ".trash/workspaces/Work/Gone.md", "Inbox/Live.md"]);
        assert_eq!(rows, [(".trash/Inbox/Old.md".to_string(), true), ("Inbox/Live.md".to_string(), false)]);
        // Restored, the one with a folder goes home; emptied, the other is gone with its row.
        assert_eq!(library.restore_note("old").unwrap().unwrap().path.as_deref(), Some("Inbox/Old.md"));
        let gone = library.list_notes().unwrap().into_iter().find(|n| n.path.as_deref() == Some(".trash/workspaces/Work/Gone.md")).unwrap();
        assert!(library.delete_note(&gone.id).unwrap());
        assert!(!root.join(".trash/workspaces/Work/Gone.md").exists());
        assert_eq!(library.list_notes().unwrap().len(), 2);
    }

    #[test]
    fn a_note_another_device_trashed_or_restored_moves_here_too() {
        let root = TempDir::new("trash-sync");
        let mut library = Library::open_fs(&root).unwrap();
        let mut note = library.save_note("n1", "# Plan\n", "editor").unwrap();
        note.path = Some("workspaces/Work/Plan.md".into());
        let mut theirs = library.apply_note(&note).unwrap();
        // Trashed there: its path arrives under `.trash/`, and the file follows it here.
        theirs.path = Some(".trash/workspaces/Work/Plan.md".into());
        let applied = library.apply_note(&theirs).unwrap();
        assert_eq!(applied.path.as_deref(), Some(".trash/workspaces/Work/Plan.md"));
        assert!(root.join(".trash/workspaces/Work/Plan.md").is_file() && !root.join("workspaces/Work/Plan.md").exists());
        assert!(library.row("n1").unwrap().unwrap().trashed);
        // Restored there: back it comes.
        theirs.path = Some("workspaces/Work/Plan.md".into());
        assert_eq!(library.apply_note(&theirs).unwrap().path.as_deref(), Some("workspaces/Work/Plan.md"));
        assert!(!library.row("n1").unwrap().unwrap().trashed);
        // Any other dot folder is still refused: the note is given a free name in the Inbox instead.
        theirs.path = Some(".obsidian/Plan.md".into());
        assert_eq!(library.apply_note(&theirs).unwrap().path.as_deref(), Some("workspaces/Work/Plan.md"));
        // A note new to this device that arrives trashed is written into the trash.
        let fresh = Note { id: "n2".into(), path: Some(".trash/Inbox/Later.md".into()), ..theirs.clone() };
        assert_eq!(library.apply_note(&fresh).unwrap().path.as_deref(), Some(".trash/Inbox/Later.md"));
    }

    #[test]
    fn emptying_the_trash_deletes_the_files_and_a_save_in_the_trash_stays_there() {
        let root = TempDir::new("trash-empty");
        let mut library = Library::open_fs(&root).unwrap();
        library.save_note("n1", "# Plan\n", "editor").unwrap();
        library.write_versions("n1", "v").unwrap();
        library.trash_note("n1").unwrap();
        // An edit from another app, or a tag renamed across every note, to a trashed note: the file stays in the trash,
        // renamed there for its new title.
        let saved = library.save_note("n1", "# Plan B\n", "editor").unwrap();
        assert_eq!(saved.path.as_deref(), Some(".trash/Inbox/Plan B.md"));
        assert!(library.delete_note("n1").unwrap());
        assert!(!root.join(".trash/Inbox/Plan B.md").exists() && !root.join(".trash/Inbox/Plan B.versions").exists());
        assert!(library.list_notes().unwrap().is_empty());
    }
}
