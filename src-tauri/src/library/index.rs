//! `.glyph/index.sqlite`: the cache over the library's files that makes the
//! list instant. Only a cache - a missing or older one is rebuilt from the
//! files, and a file changed by another app is read into it again - so the
//! files are always the truth and nothing here is ever the only copy of a
//! note. (The command mutations recorded for undo are the one thing kept here
//! and nowhere else, and they are an undo's memory, not a note.)

use std::collections::{HashMap, HashSet};
use std::path::Path;

use rusqlite::{Connection, OptionalExtension};

use super::dates::parse_iso;
use super::frontmatter::split;
use super::names::title_of;
use super::sidecar::Sidecar;
use super::vault::Entry;
use super::{Library, Result};
use crate::note::{new_id, Note};

/// The index's shape. A different one is dropped and rebuilt: it is only a cache.
const INDEX_VERSION: i64 = 2;

const INDEX_SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        body TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL,
        size INTEGER NOT NULL,
        source TEXT NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        archived_at INTEGER,
        id_in_file INTEGER NOT NULL DEFAULT 0,
        recording_ms INTEGER,
        formatted_for INTEGER,
        formatted_model TEXT,
        revision INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS command_mutations (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        before_body TEXT,
        after_body TEXT NOT NULL,
        before_revision INTEGER,
        after_revision INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        undone_at INTEGER
    );
    CREATE INDEX IF NOT EXISTS command_mutations_note ON command_mutations (note_id, created_at DESC);
";

/// Opens the index in `glyph`, dropping and rebuilding its tables when they
/// are of another `INDEX_VERSION`.
pub(super) fn open(glyph: &Path) -> Result<Connection> {
    let index = Connection::open(glyph.join("index.sqlite"))?;
    let _: String = index.query_row("PRAGMA journal_mode=WAL", [], |row| row.get(0))?;
    index.busy_timeout(std::time::Duration::from_secs(5))?;
    let version: i64 = index.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if version != INDEX_VERSION {
        index.execute_batch("DROP TABLE IF EXISTS notes; DROP TABLE IF EXISTS command_mutations;")?;
        index.execute_batch(INDEX_SCHEMA)?;
        index.execute_batch(&format!("PRAGMA user_version = {INDEX_VERSION};"))?;
    }
    Ok(index)
}

/// One note as the index has it.
pub(super) struct Row {
    pub(super) id: String,
    pub(super) path: String,
    pub(super) body: String,
    pub(super) created_at: i64,
    pub(super) modified_at: i64,
    pub(super) source: String,
    pub(super) pinned: bool,
    pub(super) archived_at: Option<i64>,
    pub(super) recording_ms: Option<i64>,
    pub(super) formatted_for: Option<i64>,
    pub(super) formatted_model: Option<String>,
    pub(super) revision: i64,
}

/// Every column a row is read from and written with, in `row_of`'s order.
/// `id_in_file` (whether the file's own front matter carries the id) is
/// written for every file and read by nothing yet.
const ROW_COLUMNS: &str = "id, path, body, created_at, modified_at, source, pinned, archived_at, id_in_file, recording_ms, formatted_for, formatted_model, revision";

/// Unpacks a row selected as `ROW_COLUMNS`.
fn row_of(row: &rusqlite::Row<'_>) -> rusqlite::Result<Row> {
    Ok(Row {
        id: row.get(0)?,
        path: row.get(1)?,
        body: row.get(2)?,
        created_at: row.get(3)?,
        modified_at: row.get(4)?,
        source: row.get(5)?,
        pinned: row.get::<_, i64>(6)? != 0,
        archived_at: row.get(7)?,
        recording_ms: row.get(9)?,
        formatted_for: row.get(10)?,
        formatted_model: row.get(11)?,
        revision: row.get::<_, Option<i64>>(12)?.unwrap_or(1),
    })
}

impl Library {
    /// The indexed note with `id`, if there is one.
    pub(super) fn row(&self, id: &str) -> Result<Option<Row>> {
        Ok(self.index.query_row(&format!("SELECT {ROW_COLUMNS} FROM notes WHERE id = ?1"), [id], row_of).optional()?)
    }

    /// The indexed note whose file is at `path`, if there is one.
    pub(super) fn row_at(&self, path: &str) -> Result<Option<Row>> {
        Ok(self.index.query_row(&format!("SELECT {ROW_COLUMNS} FROM notes WHERE path = ?1"), [path], row_of).optional()?)
    }

    /// The files against the index: changed files read again, new ones indexed, vanished ones dropped.
    pub fn scan(&mut self) -> Result<()> {
        let entries = self.vault.markdown()?;
        let known: HashMap<String, (i64, i64)> = {
            let mut stmt = self.index.prepare("SELECT path, modified_at, size FROM notes")?;
            let rows = stmt.query_map([], |row| Ok((row.get::<_, String>(0)?, (row.get::<_, i64>(1)?, row.get::<_, i64>(2)?))))?;
            rows.collect::<rusqlite::Result<_>>()?
        };
        let present: HashSet<&str> = entries.iter().map(|e| e.path.as_str()).collect();
        let gone: Vec<String> = known.keys().filter(|path| !present.contains(path.as_str())).cloned().collect();
        for path in gone {
            self.index.execute("DELETE FROM notes WHERE path = ?1", [&path])?;
        }
        for entry in &entries {
            if known.get(&entry.path) == Some(&(entry.modified_ms, entry.size as i64)) {
                continue;
            }
            self.index_file(entry)?;
        }
        Ok(())
    }

    /// One file read into the index: its id (from its front matter, from the
    /// row already at its path, or a new one for a copy of another note's
    /// file), its dates and flags, and what its sidecar says, with the
    /// revision moved on when the body changed.
    pub(super) fn index_file(&mut self, entry: &Entry) -> Result<()> {
        let Ok(text) = self.vault.read(&entry.path) else { return Ok(()) };
        let (front, body) = split(&text);
        let front = front.unwrap_or_default();
        let at_path = self.row_at(&entry.path)?;
        let named = front.text("id").filter(|id| !id.trim().is_empty());
        let (id, id_in_file) = match named {
            Some(id) => match self.row(&id)? {
                // The same id at another path that still exists: this file is a copy, and gets its own.
                Some(other) if other.path != entry.path && self.vault.exists(&other.path) => (new_id(), false),
                _ => (id, true),
            },
            None => (at_path.as_ref().map(|r| r.id.clone()).unwrap_or_else(new_id), false),
        };
        let previous = self.row(&id)?;
        let prior_revision = previous
            .as_ref()
            .or(at_path.as_ref())
            .map(|row| if row.body == body { row.revision } else { row.revision.saturating_add(1) })
            .unwrap_or(1);
        let created_at = front
            .text("created")
            .and_then(|t| parse_iso(&t))
            .or(previous.as_ref().map(|r| r.created_at))
            .or(at_path.as_ref().map(|r| r.created_at))
            .unwrap_or(entry.modified_ms);
        let archived_at = front.text("archived").and_then(|t| parse_iso(&t)).or_else(|| front.flag("archived").then_some(entry.modified_ms));
        let sidecar = self.sidecar(&id);
        self.index.execute("DELETE FROM notes WHERE path = ?1 OR id = ?2", rusqlite::params![entry.path, id])?;
        self.index.execute(
            &format!("INSERT INTO notes ({ROW_COLUMNS}, title, size) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)"),
            rusqlite::params![
                id,
                entry.path,
                body,
                created_at,
                entry.modified_ms,
                front.text("source").unwrap_or_else(|| "editor".to_string()),
                front.flag("pinned") as i64,
                archived_at,
                id_in_file as i64,
                sidecar.recording_ms,
                sidecar.formatted_for,
                sidecar.formatted_model,
                prior_revision,
                title_of(body),
                entry.size as i64,
            ],
        )?;
        Ok(())
    }

    /// The note a row stands for; `full` adds what its sidecar keeps, which the
    /// list leaves out.
    pub(super) fn note_of(&self, row: Row, full: bool) -> Note {
        let sidecar = if full { self.sidecar(&row.id) } else { Sidecar::default() };
        Note {
            id: row.id,
            body: row.body,
            created_at: row.created_at,
            updated_at: row.modified_at,
            source: row.source,
            starred: row.pinned,
            archived_at: row.archived_at,
            recording_ms: row.recording_ms,
            segments: if full { sidecar.segments } else { None },
            formatted: if full { sidecar.formatted } else { None },
            formatted_for: row.formatted_for,
            formatted_model: row.formatted_model,
            path: Some(row.path),
            revision: row.revision,
        }
    }

    /// Every indexed note, most recently modified first, ties broken by id so
    /// the same files always list in the same order.
    pub(super) fn rows_newest_first(&self) -> Result<Vec<Row>> {
        let mut stmt = self.index.prepare(&format!("SELECT {ROW_COLUMNS} FROM notes ORDER BY modified_at DESC, id"))?;
        let rows = stmt.query_map([], row_of)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Whether any note still refers to the picture `name` as `(image/<name>)`,
    /// so a deleted note's pictures go only when nothing else shows them.
    /// `instr` rather than `LIKE`, where the `_` in a name would be a wildcard.
    pub fn image_in_use(&self, name: &str) -> Result<bool> {
        let needle = format!("(image/{name})");
        Ok(self.index.query_row("SELECT EXISTS(SELECT 1 FROM notes WHERE instr(body, ?1) > 0)", [needle], |row| row.get::<_, i64>(0))? != 0)
    }
}
