//! The move into a folder of the person's, and back out (docs/LIBRARY.md
//! "Choosing the folder"; root.rs keeps where it is). Matt's examples are an
//! Obsidian vault, iCloud Drive or Dropbox, Syncthing and a backup drive: each
//! is a folder that may already be full of Markdown, and Ghost.md takes it as
//! it is. The folder becomes the library, every `.md` in it a note (the scan
//! indexes any `.md`, and an id goes into its front matter the first time
//! Ghost.md saves it), and the app's notes go in beside them, each at the path
//! it had (`Inbox/Plan.md`, `workspaces/Work/Roadmap.md`), with " 2" where a
//! file of that name is there already.
//!
//! IN THREE STEPS, so a note is never in neither place. `copy_into` writes every
//! note into the new folder - its words and front matter as they are, its
//! modified time, its sidecar, its versions file, its revision - and removes
//! nothing; a failure part way takes back exactly the files it wrote, and the
//! library stays where it was. The caller then switches `library-root.json`.
//! Only after that does `forget_copied` take the notes out of where they were,
//! and only from the app's own folder: leaving a folder of the person's, for
//! another or for the app's own, copies and leaves every file where it is
//! (Matt: a reset, and so a move, must never delete a person's own folder).
//!
//! A NOTE ALREADY THERE BY ITS ID (a folder chosen before and gone back from):
//! the same words are the same note, which is not written twice; other words
//! are another note under the same id, so the app's goes in beside it with an
//! id of its own, and neither is written over.

use rusqlite::params;

use super::frontmatter::{join, split, Value};
use super::index::Row;
use super::versions::versions_path;
use super::{folder_of, Library, Result};
use crate::note::new_id;

/// What a copy into another folder did, and the notes it can take out of this one.
#[derive(Debug, Default)]
pub struct Copied {
    /// Notes written into the new folder.
    pub notes: usize,
    /// Notes the new folder had of its own, before: its Markdown files, now the library's notes too.
    pub adopted: usize,
    /// Notes written under another name, a file of theirs being in the way.
    pub renamed: usize,
    /// Notes the new folder already had, word for word, under the same id.
    pub same: usize,
    /// Every note of this library that is now in the new one: `(id, path here)`.
    taken: Vec<(String, String)>,
}

/// A file the copy wrote, to take back if it stops part way.
struct Wrote {
    id: String,
    path: String,
    versions: bool,
}

/// A file's own name without `.md`: what a clash numbers (`Plan 2.md`).
fn own_stem(path: &str) -> &str {
    let name = path.rsplit('/').next().unwrap_or(path);
    name.strip_suffix(".md").or_else(|| name.strip_suffix(".MD")).unwrap_or(name)
}

impl Library {
    /// Every note here written into `to`, which keeps what it already had. Removes nothing from either: on an
    /// error, the files written into `to` are taken back out, and `self` is as it was.
    pub fn copy_into(&mut self, to: &mut Library) -> Result<Copied> {
        let _writing = super::writing();
        self.scan()?;
        let adopted: i64 = to.index.query_row("SELECT COUNT(*) FROM notes", [], |row| row.get(0))?;
        let mut copied = Copied { adopted: adopted as usize, ..Copied::default() };
        let mut wrote = Vec::new();
        let rows = self.rows_newest_first()?;
        for row in &rows {
            if let Err(e) = self.copy_note(to, row, &mut copied, &mut wrote) {
                for file in wrote.iter().rev() {
                    to.take_back(file);
                }
                return Err(e);
            }
        }
        to.carry_mutations(self)?;
        Ok(copied)
    }

    fn copy_note(&self, to: &mut Library, row: &Row, copied: &mut Copied, wrote: &mut Vec<Wrote>) -> Result<()> {
        let mut text = self.vault.read(&row.path)?;
        let mut id = row.id.clone();
        let mut path = row.path.clone();
        if let Some(there) = to.row(&row.id)? {
            if there.body == row.body {
                copied.same += 1;
                copied.taken.push((row.id.clone(), row.path.clone()));
                return Ok(());
            }
            id = new_id();
            let (front, body) = split(&text);
            let mut front = front.unwrap_or_default();
            front.set("id", Some(Value::Text(id.clone())));
            text = join(Some(&front), body);
            path = to.free_path(folder_of(&row.path), own_stem(&row.path));
            copied.renamed += 1;
        } else if to.vault.exists(&path) {
            path = to.free_path(folder_of(&row.path), own_stem(&row.path));
            copied.renamed += 1;
        }
        let entry = to.vault.write(&path, &text)?;
        let mut file = Wrote { id: id.clone(), path: path.clone(), versions: false };
        // Its place in the list: the file says it was last changed when the note was.
        let entry = to.vault.keep_modified(&path, row.modified_at).unwrap_or(entry);
        let (versions_here, versions_there) = (versions_path(&row.path), versions_path(&path));
        if self.vault.exists(&versions_here) && !to.vault.exists(&versions_there) {
            let kept = self.vault.read(&versions_here);
            match kept {
                Ok(kept) => {
                    to.vault.write(&versions_there, &kept)?;
                    file.versions = true;
                }
                Err(e) => {
                    to.take_back(&file);
                    return Err(e.into());
                }
            }
        }
        wrote.push(file);
        to.write_sidecar(&id, &self.sidecar(&row.id))?;
        to.index_file(&entry)?;
        // The page holds each note at its revision: carried, so its next save is not a conflict.
        to.index.execute("UPDATE notes SET revision = ?2 WHERE id = ?1", params![id, row.revision])?;
        copied.notes += 1;
        copied.taken.push((row.id.clone(), row.path.clone()));
        Ok(())
    }

    /// A file the copy wrote, taken out again: the note, the versions file it brought, its sidecar and its row.
    fn take_back(&mut self, file: &Wrote) {
        let _ = self.vault.remove(&file.path);
        if file.versions {
            let _ = self.vault.remove(&versions_path(&file.path));
        }
        if let Some(sidecar) = self.sidecar_path(&file.id) {
            let _ = std::fs::remove_file(sidecar);
        }
        let _ = self.index.execute("DELETE FROM notes WHERE id = ?1 AND path = ?2", params![file.id, file.path]);
    }

    /// The voice commands' undo memory, carried into `to` (index.rs: the one thing kept only in the index).
    fn carry_mutations(&mut self, from: &Library) -> Result<()> {
        const COLUMNS: &str = "id, note_id, kind, before_body, after_body, before_revision, after_revision, created_at, undone_at";
        let mut read = from.index.prepare(&format!("SELECT {COLUMNS} FROM command_mutations"))?;
        let rows = read.query_map([], |row| (0..9).map(|i| row.get::<_, rusqlite::types::Value>(i)).collect::<rusqlite::Result<Vec<_>>>())?;
        let mut write = self.index.prepare(&format!("INSERT OR IGNORE INTO command_mutations ({COLUMNS}) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"))?;
        for row in rows {
            write.execute(rusqlite::params_from_iter(row?))?;
        }
        Ok(())
    }

    /// The notes `copied` put into the new folder, taken out of this one - only when this is the app's own folder,
    /// and only once the switch is made. Answers how many went. A folder of the person's keeps every file.
    pub fn forget_copied(&mut self, copied: &Copied) -> usize {
        if !self.own {
            return 0;
        }
        let _writing = super::writing();
        copied.taken.iter().filter(|(id, path)| self.delete_file(id, path).is_ok()).count()
    }

    /// The drafts held in memory (notes with no words yet, so no file), handed to the library that takes over.
    pub fn carry_drafts_into(&mut self, to: &mut Library) {
        to.drafts.extend(self.drafts.drain());
        to.drafted.extend(self.drafted.drain());
    }

    /// Every note's file and versions file as text, by its path in the folder: the export's way to a library with
    /// no folder to walk (one reached through Android's SAF). A note iCloud has not brought down is left out.
    pub fn texts(&self) -> Result<Vec<(String, String)>> {
        let mut out = Vec::new();
        for entry in self.vault.markdown()? {
            match self.vault.read(&entry.path) {
                Ok(text) => out.push((entry.path.clone(), text)),
                Err(e) if super::vault::not_downloaded(&e) => continue,
                Err(e) => return Err(e.into()),
            }
            let versions = versions_path(&entry.path);
            if self.vault.exists(&versions) {
                out.push((versions.clone(), self.vault.read(&versions)?));
            }
        }
        Ok(out)
    }

    /// The library's `.glyph/` folder: what isn't text, and `library.json`.
    pub fn glyph_dir(&self) -> std::path::PathBuf {
        self.vault.glyph_dir()
    }

    /// How many notes the index has.
    pub fn note_count(&self) -> Result<usize> {
        let count: i64 = self.index.query_row("SELECT COUNT(*) FROM notes", [], |row| row.get(0))?;
        Ok(count as usize)
    }
}

#[cfg(test)]
mod tests {
    use std::io;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::library::root::Root;
    use crate::library::vault::{Entry, FsVault, Vault};
    use crate::note::Recording;
    use crate::test_support::TempDir;

    fn put(dir: &Path, path: &str, text: &str) {
        std::fs::create_dir_all(dir.join(path).parent().unwrap()).unwrap();
        std::fs::write(dir.join(path), text).unwrap();
    }

    fn read(dir: &Path, path: &str) -> String {
        std::fs::read_to_string(dir.join(path)).unwrap_or_else(|e| panic!("{path}: {e}"))
    }

    /// The folder at `dir` taken as the library, its index where library_root.rs keeps one.
    fn chosen(data: &Path, dir: &Path) -> Library {
        std::fs::create_dir_all(dir).unwrap();
        let root = Root::Folder { path: dir.to_path_buf() };
        Library::open_chosen(Box::new(FsVault::new(dir).unwrap()), &root.index_file(data)).unwrap()
    }

    /// An Obsidian vault: its settings folder, its trash, front matter of its own, folders in folders, and a note
    /// named as one of the app's is.
    fn obsidian(vault: &Path) {
        put(vault, ".obsidian/app.json", "{\"vimMode\":true}");
        put(vault, ".trash/Old.md", "thrown away in Obsidian");
        put(vault, "Inbox/Plan.md", "---\ntags: [trip]\naliases: [The plan]\n---\n# Their plan\n");
        put(vault, "Daily/2026-10-01.md", "---\ntags: daily\n---\nWent for a walk.\n");
        put(vault, "Projects/Deep/Idea.md", "An idea with no front matter.\n");
    }

    #[test]
    fn an_obsidian_vault_is_taken_as_it_is_and_the_notes_move_in_beside_its_own() {
        let data = TempDir::new("relocate");
        let vault = data.join("Obsidian");
        obsidian(&vault);
        let mut app = Library::open_fs(&data.join("Library")).unwrap();
        let plan = app.save_note("plan", "# Plan\n\nours\n", "editor").unwrap();
        app.set_starred("plan", true).unwrap();
        app.set_recording("plan", Some(&Recording::new(2000, Vec::new()).unwrap())).unwrap();
        assert!(app.write_versions("plan", "# Ghost.md versions 1\n").unwrap());
        app.update_note("plan", "# Plan\n\nours, edited\n", plan.revision).unwrap();
        let mut road = app.save_note("road", "# Roadmap\n", "editor").unwrap();
        road.path = Some("workspaces/Work/Roadmap.md".into());
        app.apply_note(&road).unwrap();
        app.save_note("draft", "", "editor").unwrap();
        let before = app.list_notes().unwrap();

        let mut there = chosen(&data, &vault);
        assert_eq!(there.note_count().unwrap(), 3, "every Markdown file in the vault is a note, the trash's and .obsidian's not");
        let copied = app.copy_into(&mut there).unwrap();
        assert_eq!((copied.notes, copied.adopted, copied.renamed, copied.same), (2, 3, 1, 0));

        // The vault's own files, exactly as they were.
        assert_eq!(read(&vault, "Inbox/Plan.md"), "---\ntags: [trip]\naliases: [The plan]\n---\n# Their plan\n");
        assert_eq!(read(&vault, ".obsidian/app.json"), "{\"vimMode\":true}");
        assert_eq!(read(&vault, ".trash/Old.md"), "thrown away in Obsidian");
        // The app's, at the paths they had, a clash numbered, with all they carry.
        let ours = there.get_note("plan").unwrap().unwrap();
        assert_eq!(ours.path.as_deref(), Some("Inbox/Plan 2.md"));
        assert_eq!(ours.body, "# Plan\n\nours, edited\n");
        assert!(ours.starred && ours.recording_ms == Some(2000));
        let was = before.iter().find(|n| n.id == "plan").unwrap();
        assert_eq!((ours.revision, ours.updated_at), (was.revision, was.updated_at), "the page's revision and the list's order carry");
        assert_eq!(read(&vault, "Inbox/Plan 2.versions"), "# Ghost.md versions 1\n");
        assert!(vault.join(".glyph/notes/plan.json").exists(), "what isn't text travels with the folder");
        assert_eq!(there.get_note("road").unwrap().unwrap().path.as_deref(), Some("workspaces/Work/Roadmap.md"));
        assert_eq!(there.list_notes().unwrap().len(), 5);

        // The index is the app's, not the folder's: nothing there for a sync service to tear.
        assert!(!vault.join(".glyph/index.sqlite").exists());
        assert!(Root::Folder { path: vault.clone() }.index_file(&data).exists());

        // Only now, the switch made, do the notes leave the app's own folder; the drafts go with the library.
        assert_eq!(app.forget_copied(&copied), 2);
        assert!(app.list_notes().unwrap().is_empty() && !data.join("Library/Inbox/Plan.md").exists());
        assert!(!data.join("Library/Inbox/Plan.versions").exists() && !data.join("Library/.glyph/notes/plan.json").exists());
        app.carry_drafts_into(&mut there);
        assert_eq!(there.get_note("draft").unwrap().map(|n| n.body), Some(String::new()));

        // One of the vault's own notes, edited in Ghost.md: Obsidian's front matter kept, and its name, so its
        // daily note and every [[link]] to it still find it.
        let daily = there.list_notes().unwrap().into_iter().find(|n| n.path.as_deref() == Some("Daily/2026-10-01.md")).unwrap();
        let saved = there.save_note(&daily.id, "Went for a walk.\n\nAnd a swim.\n", "editor").unwrap();
        assert_eq!(saved.path.as_deref(), Some("Daily/2026-10-01.md"));
        let text = read(&vault, "Daily/2026-10-01.md");
        assert!(text.starts_with(&format!("---\ntags: daily\nid: {}\n", daily.id)), "{text}");
        // A note Ghost.md named still follows its title.
        assert_eq!(there.save_note("road", "# Roadmap for 2027\n", "editor").unwrap().path.as_deref(), Some("workspaces/Work/Roadmap for 2027.md"));
    }

    #[test]
    fn leaving_a_chosen_folder_copies_and_keeps_every_file_there() {
        let data = TempDir::new("relocate-leave");
        let vault = data.join("Dropbox/Notes");
        obsidian(&vault);
        let mut there = chosen(&data, &vault);
        there.save_note("n1", "# Written here\n", "editor").unwrap();
        let mut home = Library::open_fs(&data.join("Library")).unwrap();
        let copied = there.copy_into(&mut home).unwrap();
        assert_eq!(copied.notes, 4);
        assert_eq!(there.forget_copied(&copied), 0, "a folder of the person's is never emptied");
        assert_eq!(there.list_notes().unwrap().len(), 4);
        assert!(vault.join("Inbox/Written here.md").exists() && vault.join("Projects/Deep/Idea.md").exists());
        assert_eq!(home.list_notes().unwrap().len(), 4);
        assert_eq!(read(&data, "Library/Projects/Deep/Idea.md"), "An idea with no front matter.\n");
    }

    #[test]
    fn a_note_already_there_by_id_is_not_written_twice_or_over() {
        let data = TempDir::new("relocate-same");
        let vault = data.join("Notes");
        put(&vault, "Inbox/Same.md", "---\nid: same\n---\n# Same\n");
        put(&vault, "Inbox/Fork.md", "---\nid: fork\n---\n# Fork\n\ntheirs\n");
        let mut app = Library::open_fs(&data.join("Library")).unwrap();
        app.save_note("same", "# Same\n", "editor").unwrap();
        app.save_note("fork", "# Fork\n\nours\n", "editor").unwrap();
        let mut there = chosen(&data, &vault);
        let copied = app.copy_into(&mut there).unwrap();
        assert_eq!((copied.notes, copied.same, copied.renamed), (1, 1, 1));
        assert_eq!(read(&vault, "Inbox/Fork.md"), "---\nid: fork\n---\n# Fork\n\ntheirs\n", "theirs is not written over");
        let ours = read(&vault, "Inbox/Fork 2.md");
        assert!(ours.contains("ours") && !ours.contains("id: fork\n"), "ours is beside it, under an id of its own: {ours}");
        assert_eq!(there.list_notes().unwrap().len(), 3);
        assert_eq!(app.forget_copied(&copied), 2, "both are in the folder, so both leave the app's");
    }

    /// A folder whose drive fills after `room` writes.
    struct Filling {
        inner: FsVault,
        room: AtomicUsize,
    }

    impl Vault for Filling {
        fn markdown(&self) -> io::Result<Vec<Entry>> {
            self.inner.markdown()
        }
        fn read(&self, path: &str) -> io::Result<String> {
            self.inner.read(path)
        }
        fn write(&self, path: &str, text: &str) -> io::Result<Entry> {
            if self.room.fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1)).is_err() {
                return Err(io::Error::other("no space left on the drive"));
            }
            self.inner.write(path, text)
        }
        fn rename(&self, from: &str, to: &str) -> io::Result<()> {
            self.inner.rename(from, to)
        }
        fn remove(&self, path: &str) -> io::Result<()> {
            self.inner.remove(path)
        }
        fn exists(&self, path: &str) -> bool {
            self.inner.exists(path)
        }
        fn stat(&self, path: &str) -> io::Result<Entry> {
            self.inner.stat(path)
        }
        fn keep_modified(&self, path: &str, modified_ms: i64) -> io::Result<Entry> {
            self.inner.keep_modified(path, modified_ms)
        }
        fn glyph_dir(&self) -> PathBuf {
            self.inner.glyph_dir()
        }
    }

    #[test]
    fn a_copy_that_stops_part_way_takes_back_what_it_wrote_and_moves_nothing() {
        let data = TempDir::new("relocate-full");
        let drive = data.join("Backup");
        put(&drive, "Mine.md", "a note already on the drive\n");
        let mut app = Library::open_fs(&data.join("Library")).unwrap();
        for n in 0..4 {
            app.save_note(&format!("n{n}"), &format!("# Note {n}\n"), "editor").unwrap();
        }
        let filling = Filling { inner: FsVault::new(&drive).unwrap(), room: AtomicUsize::new(2) };
        let mut there = Library::open_chosen(Box::new(filling), &data.join("index/backup.sqlite")).unwrap();
        let error = app.copy_into(&mut there).unwrap_err();
        assert!(error.to_string().contains("no space left"), "{error}");
        let left: Vec<String> = there.vault.markdown().unwrap().into_iter().map(|e| e.path).collect();
        assert_eq!(left, ["Mine.md"], "the drive holds what it held");
        assert_eq!(there.list_notes().unwrap().len(), 1);
        assert_eq!(app.list_notes().unwrap().len(), 4, "and every note is still where it was");
    }

    #[test]
    fn a_reset_of_a_chosen_folder_forgets_it_and_deletes_nothing() {
        let data = TempDir::new("relocate-clear");
        let vault = data.join("Vault");
        obsidian(&vault);
        let mut there = chosen(&data, &vault);
        there.save_note("n1", "# Mine\n", "editor").unwrap();
        there.clear().unwrap();
        for file in ["Inbox/Plan.md", "Inbox/Mine.md", "Daily/2026-10-01.md", "Projects/Deep/Idea.md", ".obsidian/app.json", ".glyph/library.json"] {
            assert!(vault.join(file).exists(), "{file} is the person's and stays");
        }
    }

    #[test]
    fn a_note_in_icloud_and_off_this_mac_stays_in_the_list_and_is_never_written_over() {
        let data = TempDir::new("relocate-icloud");
        let drive = data.join("iCloud/Notes");
        let mut there = chosen(&data, &drive);
        there.save_note("n1", "# Trip\n\npack\n", "editor").unwrap();
        // "Optimise Mac Storage" takes it off the disk and leaves its placeholder.
        std::fs::remove_file(drive.join("Inbox/Trip.md")).unwrap();
        put(&drive, "Inbox/.Trip.md.icloud", "bplist00");
        assert_eq!(there.list_notes().unwrap().len(), 1, "not deleted");
        assert_eq!(there.get_note("n1").unwrap().unwrap().body, "# Trip\n\npack\n", "the words the index last read");
        let refused = there.save_note("n1", "# Trip\n\npack, and more\n", "editor").unwrap_err();
        assert!(refused.to_string().contains("iCloud"), "{refused}");
        assert!(!drive.join("Inbox/Trip.md").exists(), "no second file over the first");
        assert_eq!(there.save_note("n2", "# Trip\n", "editor").unwrap().path.as_deref(), Some("Inbox/Trip 2.md"), "its name is taken");
        // Back on the Mac, it is read as it is.
        std::thread::sleep(std::time::Duration::from_millis(20));
        put(&drive, "Inbox/Trip.md", "---\nid: n1\n---\n# Trip\n\npack, from the phone\n");
        std::fs::remove_file(drive.join("Inbox/.Trip.md.icloud")).unwrap();
        assert_eq!(there.get_note("n1").unwrap().unwrap().body, "# Trip\n\npack, from the phone\n");
        // A placeholder the index never read is not a note until it comes down.
        put(&drive, "Inbox/.Elsewhere.md.icloud", "bplist00");
        assert_eq!(there.list_notes().unwrap().len(), 2);
    }
}
