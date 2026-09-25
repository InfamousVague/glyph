//! The notes as a library of Markdown files (docs/LIBRARY.md), and NOT ONE
//! `tauri::` TYPE IN THIS MODULE, for the reason note.rs gives.
//!
//! The files are the truth; `.glyph/index.sqlite` is a cache that makes the
//! list instant, and it is rebuilt from the files whenever they disagree. A
//! `Library` answers the calls the page makes of its notes (list, get, create,
//! update, delete, pin, archive, recording, formatted version, a note from
//! another device) with a `note::Note`: a note is an id and a body, and it is
//! also a file.
//!
//! - **Saving** writes the body under the note's front matter. Only the keys
//!   Glyph manages are touched (frontmatter.rs), and the file is renamed when
//!   its title changes (names.rs). A new note is written into `Inbox/`.
//! - **Pinning and archiving** change a front matter line and keep the file's
//!   modified time, so a pin doesn't move a note up the list.
//! - **What isn't text** (a recording's phrases, the formatted version) is
//!   `.glyph/notes/<id>.json` (sidecar.rs).
//! - **Reading** checks the files against the index first (index.rs). A file
//!   changed by another app is read again, a new one is indexed, and a
//!   vanished one leaves the list.
//!
//! The rest of the library, each in its own file: the dates front matter
//! writes (dates.rs), voice commands' guarded writes and their undo
//! (mutations.rs), `library.json` and the one move from the old database
//! (move_in.rs), and the files themselves behind a trait (vault.rs).

mod dates;
pub mod frontmatter;
mod index;
mod move_in;
mod mutations;
pub mod names;
mod sidecar;
pub mod vault;

pub use move_in::open_and_move_in;

use std::collections::{HashMap, HashSet};
use std::path::Path;

use rusqlite::Connection;

use crate::note::{now_ms, Note, Recording};
use dates::iso;
use frontmatter::{join, split, FrontMatter, Value};
use index::Row;
use names::{file_stem, title_of, unique_name};
use sidecar::Sidecar;
use vault::{FsVault, Vault};

/// Where new notes go.
pub const INBOX: &str = "Inbox";

#[derive(Debug)]
pub enum LibraryError {
    Io(std::io::Error),
    Index(rusqlite::Error),
    Store(String),
}

impl std::fmt::Display for LibraryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LibraryError::Io(e) => write!(f, "the library's files: {e}"),
            LibraryError::Index(e) => write!(f, "the library's index: {e}"),
            LibraryError::Store(e) => write!(f, "the old notes: {e}"),
        }
    }
}

impl std::error::Error for LibraryError {}

impl From<std::io::Error> for LibraryError {
    fn from(e: std::io::Error) -> Self {
        LibraryError::Io(e)
    }
}

impl From<rusqlite::Error> for LibraryError {
    fn from(e: rusqlite::Error) -> Self {
        LibraryError::Index(e)
    }
}

pub type Result<T> = std::result::Result<T, LibraryError>;

pub struct Library {
    vault: Box<dyn Vault>,
    index: Connection,
    /// New notes with no words yet, which have no file (docs/LIBRARY.md): a
    /// note opened and left empty would otherwise be an "Untitled.md" in the
    /// person's folder. The first words write the file.
    drafts: HashMap<String, Note>,
    /// Notes this process started as drafts: one whose words are all taken out
    /// again, with nothing else set on it, goes back to being a draft.
    drafted: HashSet<String>,
}

fn folder_of(path: &str) -> &str {
    path.rfind('/').map_or("", |at| &path[..at])
}

fn in_folder(folder: &str, name: &str) -> String {
    if folder.is_empty() { name.to_string() } else { format!("{folder}/{name}") }
}

/// Whether a path from another device can be a note's here: relative, `.md`, no dot folders or `..`.
fn library_path(path: &str) -> bool {
    path.to_ascii_lowercase().ends_with(".md") && path.split('/').all(|part| !part.is_empty() && !part.starts_with('.'))
}

/// Whether a file's name is already its title's: `Stem.md`, or `Stem 2.md` for a clash.
fn named_for(path: &str, stem: &str) -> bool {
    let name = path.rsplit('/').next().unwrap_or(path);
    let Some(bare) = name.strip_suffix(".md").or_else(|| name.strip_suffix(".MD")) else { return false };
    bare == stem || bare.strip_prefix(stem).and_then(|rest| rest.strip_prefix(' ')).is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
}

/// A new file's front matter: its source, unless it is the editor, which a
/// missing `source` already means.
fn born_from(source: &str) -> FrontMatter {
    let mut front = FrontMatter::new();
    if source != "editor" {
        front.set("source", Some(Value::Text(source.to_string())));
    }
    front
}

/// Every key Glyph manages, written from `note`'s own facts: its id, when it
/// was created, its source (none for the editor), its pin and its archive. For
/// a note that arrives whole - by sync, or from the old database - rather than
/// one being edited here.
fn stamp(front: &mut FrontMatter, note: &Note) {
    front.set("id", Some(Value::Text(note.id.clone())));
    front.set("created", Some(Value::Text(iso(note.created_at))));
    front.set("source", (note.source != "editor").then(|| Value::Text(note.source.clone())));
    front.set("pinned", note.starred.then_some(Value::Bool(true)));
    front.set("archived", note.archived_at.map(|at| Value::Text(iso(at))));
}

impl Library {
    /// The library in a folder this process can reach with `std::fs`.
    pub fn open_fs(root: &Path) -> Result<Library> {
        Library::open(Box::new(FsVault::new(root)?))
    }

    /// The library in `vault`: its `.glyph` folder made, its birth recorded,
    /// its index opened and checked against the files.
    pub fn open(vault: Box<dyn Vault>) -> Result<Library> {
        let glyph = vault.glyph_dir();
        std::fs::create_dir_all(glyph.join("notes"))?;
        move_in::ensure_manifest(&glyph)?;
        let index = index::open(&glyph)?;
        let mut library = Library { vault, index, drafts: HashMap::new(), drafted: HashSet::new() };
        library.scan()?;
        Ok(library)
    }

    /// A free path for a file named for `stem` in `folder`: `Stem.md`, or
    /// `Stem 2.md` and on while those are taken.
    fn free_path(&self, folder: &str, stem: &str) -> String {
        in_folder(folder, &unique_name(stem, |name| self.vault.exists(&in_folder(folder, name))))
    }

    /// Every note, newest edit first, without what its sidecar keeps: what the
    /// list screen draws, after the files are checked against the index.
    pub fn list_notes(&mut self) -> Result<Vec<Note>> {
        self.scan()?;
        let rows = self.rows_newest_first()?;
        Ok(rows.into_iter().map(|row| self.note_of(row, false)).collect())
    }

    /// One note, whole, as its file now says - or a draft with no file yet, or
    /// `None` when nothing answers to that id.
    pub fn get_note(&mut self, id: &str) -> Result<Option<Note>> {
        let Some(row) = self.row(id)? else { return Ok(self.drafts.get(id).cloned()) };
        // The file may have been changed, moved or removed by another app since the index last looked.
        if !self.vault.exists(&row.path) {
            self.scan()?;
            return Ok(self.row(id)?.map(|row| self.note_of(row, true)));
        }
        let text = self.vault.read(&row.path)?;
        let (_, body) = split(&text);
        if body != row.body {
            self.scan()?;
            return Ok(self.row(id)?.map(|row| self.note_of(row, true)));
        }
        Ok(Some(self.note_of(row, true)))
    }

    /// Writes `body` as the note's text. A new id is a new file in `Inbox/`; `source` is only read then.
    pub fn save_note(&mut self, id: &str, body: &str, source: &str) -> Result<Note> {
        let blank = body.trim().is_empty();
        let row = self.row(id)?;
        if blank {
            match &row {
                None => return Ok(self.draft(id, body, source)),
                Some(row) if self.drafted.contains(id) && self.undraftable(row)? => {
                    let draft = Note { source: row.source.clone(), created_at: row.created_at, ..self.draft(id, body, source) };
                    self.drafts.insert(id.to_string(), draft.clone());
                    self.delete_file(id, &row.path)?;
                    return Ok(draft);
                }
                Some(_) => {}
            }
        }
        let draft = self.drafts.remove(id);
        let stem = file_stem(&title_of(body));
        let (path, front, created_at, previous_text) = match row {
            Some(row) => {
                let text = self.vault.read(&row.path).unwrap_or_default();
                let (front, _) = split(&text);
                (row.path, front.unwrap_or_default(), row.created_at, Some(text))
            }
            None => {
                let source = draft.as_ref().map_or(source, |d| d.source.as_str());
                (self.free_path(INBOX, &stem), born_from(source), draft.as_ref().map_or_else(now_ms, |d| d.created_at), None)
            }
        };
        let mut front = front;
        front.set("id", Some(Value::Text(id.to_string())));
        if front.get("created").is_none() {
            front.set("created", Some(Value::Text(iso(created_at))));
        }
        let mut path = path;
        if previous_text.is_some() && !named_for(&path, &stem) {
            let to = self.free_path(folder_of(&path), &stem);
            self.vault.rename(&path, &to)?;
            self.index.execute("UPDATE notes SET path = ?2 WHERE id = ?1", rusqlite::params![id, to])?;
            path = to;
        }
        let text = join(Some(&front), body);
        let entry = if previous_text.as_deref() == Some(text.as_str()) { None } else { Some(self.vault.write(&path, &text)?) };
        match entry {
            Some(entry) => self.index_file(&entry)?,
            None => {
                let entry = self.vault.stat(&path)?;
                self.index_file(&entry)?;
            }
        }
        self.row(id)?
            .map(|row| self.note_of(row, true))
            .ok_or_else(|| LibraryError::Index(rusqlite::Error::QueryReturnedNoRows))
    }

    /// Creates a note only while its id is unused. This is the only normal
    /// insertion path; queued writers use `update_note` and cannot recreate a
    /// deleted file.
    pub fn create_note(&mut self, id: &str, body: &str, source: &str) -> Result<Option<Note>> {
        if self.row(id)?.is_some() || self.drafts.contains_key(id) {
            return Ok(None);
        }
        self.save_note(id, body, source).map(Some)
    }

    /// Updates exactly the revision the caller read. Missing or changed notes
    /// are conflicts and never become new files.
    pub fn update_note(&mut self, id: &str, body: &str, expected_revision: i64) -> Result<Option<Note>> {
        let Some(current) = self.get_note(id)? else { return Ok(None) };
        if current.revision != expected_revision {
            return Ok(None);
        }
        let mut saved = self.save_note(id, body, &current.source)?;
        let revision = expected_revision.saturating_add(1);
        if saved.path.is_some() {
            self.index.execute("UPDATE notes SET revision = ?2 WHERE id = ?1", rusqlite::params![id, revision])?;
            saved = self.get_note(id)?.ok_or_else(|| LibraryError::Index(rusqlite::Error::QueryReturnedNoRows))?;
        } else if let Some(draft) = self.drafts.get_mut(id) {
            draft.revision = revision;
            saved = draft.clone();
        }
        Ok(Some(saved))
    }

    /// A blank note with no file, held until it has words.
    fn draft(&mut self, id: &str, body: &str, source: &str) -> Note {
        let now = now_ms();
        let draft = self.drafts.entry(id.to_string()).or_insert_with(|| Note::blank(id, source, now));
        draft.body = body.to_string();
        draft.updated_at = now;
        let draft = draft.clone();
        self.drafted.insert(id.to_string());
        draft
    }

    /// Whether a note's file holds nothing a person set: no pin, no archive,
    /// no recording or formatting, no front matter but what a new note is given.
    fn undraftable(&self, row: &Row) -> Result<bool> {
        if row.pinned || row.archived_at.is_some() || !self.sidecar(&row.id).is_empty() {
            return Ok(false);
        }
        let text = self.vault.read(&row.path)?;
        let (front, _) = split(&text);
        Ok(front.is_none_or(|front| front.only(&["id", "created", "source"])))
    }

    /// A draft pinned, archived or given a recording becomes a file, even without words.
    fn written(&mut self, id: &str) -> Result<bool> {
        if self.row(id)?.is_some() {
            return Ok(true);
        }
        let Some(draft) = self.drafts.get(id).cloned() else { return Ok(false) };
        self.drafted.remove(id);
        self.drafts.remove(id);
        let mut front = born_from(&draft.source);
        front.set("id", Some(Value::Text(id.to_string())));
        front.set("created", Some(Value::Text(iso(draft.created_at))));
        let path = self.free_path(INBOX, &file_stem(&title_of(&draft.body)));
        let entry = self.vault.write(&path, &join(Some(&front), &draft.body))?;
        self.index_file(&entry)?;
        Ok(true)
    }

    /// A note's file, its sidecar and its row, gone.
    fn delete_file(&mut self, id: &str, path: &str) -> Result<()> {
        self.vault.remove(path)?;
        if let Some(sidecar) = self.sidecar_path(id) {
            let _ = std::fs::remove_file(sidecar);
        }
        self.index.execute("DELETE FROM notes WHERE id = ?1", [id])?;
        Ok(())
    }

    /// Removes a note, answering whether there was one to remove - a draft
    /// included. Removing one already gone is not an error: the page deletes
    /// from a list it drew some time ago.
    pub fn delete_note(&mut self, id: &str) -> Result<bool> {
        self.drafted.remove(id);
        let Some(row) = self.row(id)? else { return Ok(self.drafts.remove(id).is_some()) };
        self.delete_file(id, &row.path)?;
        Ok(true)
    }

    /// Changes front matter only, keeping the file's modified time: a pin is not an edit.
    fn set_front(&mut self, id: &str, change: impl FnOnce(&mut FrontMatter)) -> Result<Option<Note>> {
        self.written(id)?;
        let Some(row) = self.row(id)? else { return Ok(None) };
        let text = self.vault.read(&row.path)?;
        let (front, body) = split(&text);
        let mut front = front.unwrap_or_default();
        change(&mut front);
        let written = join(Some(&front), body);
        if written != text {
            let entry = self.vault.write(&row.path, &written)?;
            let kept = self.vault.keep_modified(&row.path, row.modified_at).unwrap_or(entry);
            self.index_file(&kept)?;
        }
        self.get_note(id)
    }

    /// Pins or unpins a note (`pinned: true`), answering with it - or `None` if it is gone.
    pub fn set_starred(&mut self, id: &str, starred: bool) -> Result<Option<Note>> {
        self.set_front(id, |front| front.set("pinned", starred.then_some(Value::Bool(true))))
    }

    /// Archives a note (`archived: <when>`) or brings it back, answering with it - or `None` if it is gone.
    pub fn set_archived(&mut self, id: &str, archived: bool) -> Result<Option<Note>> {
        let at = archived.then(|| Value::Text(iso(now_ms())));
        self.set_front(id, |front| front.set("archived", at))
    }

    /// Keeps (or with `None`, forgets) a note's recording length and phrases,
    /// beside the note rather than in it. Not an edit: the words were saved
    /// when they were said.
    pub fn set_recording(&mut self, id: &str, recording: Option<&Recording>) -> Result<Option<Note>> {
        if !self.written(id)? {
            return Ok(None);
        }
        let mut sidecar = self.sidecar(id);
        sidecar.recording_ms = recording.map(|r| r.ms());
        sidecar.segments = recording.map(|r| r.segments().to_vec());
        self.write_sidecar(id, &sidecar)?;
        self.index.execute("UPDATE notes SET recording_ms = ?2 WHERE id = ?1", rusqlite::params![id, sidecar.recording_ms])?;
        self.get_note(id)
    }

    /// Keeps (or with `None`, forgets) the formatted version of a note: the
    /// text, the page's hash of the body it came from, and which model wrote it.
    /// Not an edit: the body and its modified time stand.
    pub fn set_formatted(&mut self, id: &str, formatted: Option<&str>, formatted_for: Option<i64>, model: Option<&str>) -> Result<Option<Note>> {
        if !self.written(id)? {
            return Ok(None);
        }
        let mut sidecar = self.sidecar(id);
        sidecar.formatted = formatted.map(str::to_string);
        sidecar.formatted_for = formatted_for;
        sidecar.formatted_model = model.map(str::to_string);
        self.write_sidecar(id, &sidecar)?;
        self.index.execute("UPDATE notes SET formatted_for = ?2, formatted_model = ?3 WHERE id = ?1", rusqlite::params![id, formatted_for, model])?;
        self.get_note(id)
    }

    /// Every note gone: the files, what isn't text, the index. For a reset of a library in the app's own storage.
    pub fn clear(&mut self) -> Result<()> {
        for entry in self.vault.markdown()? {
            self.vault.remove(&entry.path)?;
        }
        let notes = self.vault.glyph_dir().join("notes");
        let _ = std::fs::remove_dir_all(&notes);
        std::fs::create_dir_all(&notes)?;
        self.index.execute("DELETE FROM notes", [])?;
        self.drafts.clear();
        self.drafted.clear();
        Ok(())
    }

    /// A note exactly as another device has it (docs/SYNC.md): its words, times,
    /// pin, archive, source, recording phrases and formatted version, in the
    /// folder it is in there when that folder is free here. Unlike a save, the
    /// times are the note's own: a note synced in is not a note edited now.
    /// Front matter this device added that Glyph doesn't manage stays.
    pub fn apply_note(&mut self, note: &Note) -> Result<Note> {
        self.drafts.remove(&note.id);
        self.drafted.remove(&note.id);
        let stem = file_stem(&title_of(&note.body));
        let wanted = note.path.as_deref().filter(|p| library_path(p));
        let (mut path, front) = match self.row(&note.id)? {
            Some(row) => {
                let text = self.vault.read(&row.path).unwrap_or_default();
                (row.path, split(&text).0.unwrap_or_default())
            }
            None => (self.free_path(wanted.map_or(INBOX, folder_of), &stem), FrontMatter::new()),
        };
        match wanted {
            Some(to) if to != path && !self.vault.exists(to) => {
                if self.vault.exists(&path) {
                    self.vault.rename(&path, to)?;
                }
                path = to.to_string();
            }
            _ if !named_for(&path, &stem) => {
                let to = self.free_path(folder_of(&path), &stem);
                if self.vault.exists(&path) {
                    self.vault.rename(&path, &to)?;
                }
                path = to;
            }
            _ => {}
        }
        let mut front = front;
        stamp(&mut front, note);
        self.vault.write(&path, &join(Some(&front), &note.body))?;
        self.write_sidecar(&note.id, &Sidecar::from(note))?;
        let entry = self.vault.keep_modified(&path, note.updated_at)?;
        self.index_file(&entry)?;
        self.index.execute("UPDATE notes SET revision = ?2 WHERE id = ?1", rusqlite::params![note.id, note.revision])?;
        self.row(&note.id)?
            .map(|row| self.note_of(row, true))
            .ok_or_else(|| LibraryError::Index(rusqlite::Error::QueryReturnedNoRows))
    }
}

#[cfg(test)]
mod tests;
