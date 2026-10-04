//! A note's versions file (src/app/core/versions/file.ts): `<Title>.versions`,
//! beside the note's `.md`, so it is a file a person can see, copy and send, and
//! it goes wherever the note goes. The page writes what is in it; this module
//! only keeps it beside its note - written with it, moved with it when the note
//! is renamed or filed elsewhere, and deleted with it.
//!
//! It is not a note: `FsVault::walk` lists `.md` files only, so the index never
//! sees it.

use super::{Library, Result};

/// The versions file of the note at `path`: `Work/Plan.md` → `Work/Plan.versions`.
pub(super) fn versions_path(path: &str) -> String {
    let bare = path.strip_suffix(".md").or_else(|| path.strip_suffix(".MD")).unwrap_or(path);
    format!("{bare}.versions")
}

impl Library {
    /// Note `id`'s versions file as it is, or `None` where it has none (or no file yet: a draft).
    pub fn read_versions(&mut self, id: &str) -> Result<Option<String>> {
        let Some(row) = self.row(id)? else { return Ok(None) };
        let path = versions_path(&row.path);
        if !self.vault.exists(&path) {
            return Ok(None);
        }
        Ok(Some(self.vault.read(&path)?))
    }

    /// Keeps `text` as note `id`'s versions file, whole or not at all, answering whether
    /// there was a note to keep it beside. A draft is written as a file first.
    pub fn write_versions(&mut self, id: &str, text: &str) -> Result<bool> {
        let _writing = super::writing();
        if !self.written(id)? {
            return Ok(false);
        }
        let Some(row) = self.row(id)? else { return Ok(false) };
        self.vault.write(&versions_path(&row.path), text)?;
        Ok(true)
    }

    /// Renames a note's file, and its versions file with it when it has one.
    pub(super) fn rename_note_file(&mut self, from: &str, to: &str) -> Result<()> {
        self.vault.rename(from, to)?;
        let (was, now) = (versions_path(from), versions_path(to));
        if self.vault.exists(&was) {
            // The note moved whatever happens to its versions: a file in the way keeps them where they were.
            if !self.vault.exists(&now) {
                self.vault.rename(&was, &now)?;
            }
        }
        Ok(())
    }

    /// A note's versions file gone, with the note.
    pub(super) fn remove_versions(&mut self, path: &str) {
        let _ = self.vault.remove(&versions_path(path));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn a_notes_versions_file_is_named_for_its_markdown_file() {
        assert_eq!(versions_path("Inbox/Plan.md"), "Inbox/Plan.versions");
        assert_eq!(versions_path("Work/Deep/Old.MD"), "Work/Deep/Old.versions");
        assert_eq!(versions_path("Plan 2.md"), "Plan 2.versions");
    }

    #[test]
    fn the_versions_file_sits_beside_its_note_and_goes_where_it_goes() {
        let root = TempDir::new("versions");
        let mut library = Library::open_fs(&root).unwrap();
        library.save_note("n1", "# Plan\nwords", "editor").unwrap();
        assert_eq!(library.read_versions("n1").unwrap(), None);
        assert!(library.write_versions("n1", "# Ghost.md versions 1\n").unwrap());
        assert_eq!(std::fs::read_to_string(root.join("Inbox/Plan.versions")).unwrap(), "# Ghost.md versions 1\n");
        // Not a note: the list is the one note still.
        assert_eq!(library.list_notes().unwrap().len(), 1);

        // Renamed with its title.
        library.save_note("n1", "# Launch plan\nwords", "editor").unwrap();
        assert!(!root.join("Inbox/Plan.versions").exists());
        assert_eq!(library.read_versions("n1").unwrap().as_deref(), Some("# Ghost.md versions 1\n"));
        assert!(root.join("Inbox/Launch plan.versions").exists());

        // Filed elsewhere, from another device.
        let mut note = library.get_note("n1").unwrap().unwrap();
        note.path = Some("workspaces/Work/Launch plan.md".into());
        library.apply_note(&note).unwrap();
        assert!(root.join("workspaces/Work/Launch plan.versions").exists());

        // Deleted with it.
        assert!(library.delete_note("n1").unwrap());
        assert!(!root.join("workspaces/Work/Launch plan.versions").exists());
    }

    #[test]
    fn a_draft_is_written_as_a_file_to_keep_its_versions_and_a_missing_note_keeps_none() {
        let root = TempDir::new("versions-draft");
        let mut library = Library::open_fs(&root).unwrap();
        assert!(!library.write_versions("nobody", "x").unwrap());
        library.save_note("d1", "", "editor").unwrap();
        assert!(library.write_versions("d1", "# Ghost.md versions 1\n").unwrap());
        assert!(library.read_versions("d1").unwrap().is_some());
    }
}
