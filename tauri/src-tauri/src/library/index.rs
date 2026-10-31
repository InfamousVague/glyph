//! `.glyph/index.sqlite` (or `<app_data_dir>/index/<key>.sqlite` for a folder
//! the person chose, root.rs): the cache over the library's files that makes the
//! list instant. Only a cache - a missing or older one is rebuilt from the
//! files, and a file changed by another app is read into it again - so the
//! files are always the truth and nothing here is ever the only copy of a
//! note. (The command mutations recorded for undo are the one thing kept here
//! and nowhere else, and they are an undo's memory, not a note.)

use std::collections::{HashMap, HashSet};
use std::path::Path;

use rusqlite::{Connection, OptionalExtension};

use super::dates::parse_iso;
use super::frontmatter::{is_issue_key, join, read, split};
use super::names::{file_stem, title_of};
use super::sidecar::Sidecar;
use super::vault::Entry;
use super::{folder_of, named_for, Library, Result};
use crate::note::{new_id, Note};

/// The index's shape. A different one is dropped and rebuilt: it is only a cache. 3 (2.3.94): `stat_modified_at`,
/// the file's own time beside the note's (`modified_at`, the later of the file's time and its `updated:` key).
/// 4: `trashed`, whether the file is under `.trash/` (trash.rs).
const INDEX_VERSION: i64 = 4;

const INDEX_SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        body TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL,
        stat_modified_at INTEGER NOT NULL DEFAULT 0,
        size INTEGER NOT NULL,
        source TEXT NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        archived_at INTEGER,
        id_in_file INTEGER NOT NULL DEFAULT 0,
        recording_ms INTEGER,
        formatted_for INTEGER,
        formatted_model TEXT,
        revision INTEGER NOT NULL DEFAULT 1,
        trashed INTEGER NOT NULL DEFAULT 0
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

/// Opens the index at `file` (`.glyph/index.sqlite` in the app's own folder,
/// `<app_data_dir>/index/<key>.sqlite` for a folder of the person's: root.rs
/// says why), dropping and rebuilding its tables when they
/// are of another `INDEX_VERSION`.
///
/// The version check and the rebuild run under one process-wide lock. Two
/// handles are opened in one process now (the app's `NotesStore`, and a
/// meeting's write-up on its own thread with no Tauri around it), and after a
/// version bump both would find the old number: without the lock the second
/// could `DROP TABLE` the rows the first had just rebuilt and filled, and an
/// hour's meeting would be indexed by neither until the next scan. With it,
/// the second reads the new version and drops nothing.
pub(super) fn open(file: &Path) -> Result<Connection> {
    static OPENING: std::sync::Mutex<()> = std::sync::Mutex::new(());
    if let Some(dir) = file.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let index = Connection::open(file)?;
    let _: String = index.query_row("PRAGMA journal_mode=WAL", [], |row| row.get(0))?;
    index.busy_timeout(std::time::Duration::from_secs(5))?;
    let _one_at_a_time = crate::lock::lock(&OPENING);
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
    /// In the trash: its file is under `.trash/` (trash.rs). The path says so too; the column is for asking the
    /// index without reading every path.
    pub(super) trashed: bool,
}

/// Every column a row is read from and written with, in `row_of`'s order.
/// `id_in_file` (whether the file's own front matter carries the id) is
/// written for every file and read by nothing yet.
const ROW_COLUMNS: &str = "id, path, body, created_at, modified_at, source, pinned, archived_at, id_in_file, recording_ms, formatted_for, formatted_model, revision, trashed";

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
        trashed: row.get::<_, i64>(13)? != 0,
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

    /// The file names the index knows in `folder` (`Plan.md`, not `Inbox/Plan.md`): what `free_path` compares a
    /// new name against, by `names::same_name`.
    pub(super) fn names_in(&self, folder: &str) -> Result<Vec<String>> {
        let mut stmt = self.index.prepare("SELECT path FROM notes")?;
        let paths = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut names = Vec::new();
        for path in paths {
            let path = path?;
            if folder_of(&path) == folder {
                names.push(path.rsplit('/').next().unwrap_or(&path).to_string());
            }
        }
        Ok(names)
    }

    /// The files against the index: changed files read again, new ones indexed, vanished ones dropped. A file is
    /// known by its own time and size (`stat_modified_at`), not by the time the note shows, which its `updated:`
    /// key may set later than the file's.
    pub fn scan(&mut self) -> Result<()> {
        let entries = self.vault.markdown()?;
        let known: HashMap<String, (i64, i64)> = {
            let mut stmt = self.index.prepare("SELECT path, stat_modified_at, size FROM notes")?;
            let rows = stmt.query_map([], |row| Ok((row.get::<_, String>(0)?, (row.get::<_, i64>(1)?, row.get::<_, i64>(2)?))))?;
            rows.collect::<rusqlite::Result<_>>()?
        };
        let present: HashSet<&str> = entries.iter().map(|e| e.path.as_str()).collect();
        let gone: Vec<String> = known.keys().filter(|path| !present.contains(path.as_str())).cloned().collect();
        for path in gone {
            self.index.execute("DELETE FROM notes WHERE path = ?1", [&path])?;
        }
        for entry in &entries {
            // A note iCloud took off this Mac keeps the row it had, words and all; one this index never read is
            // asked for, and indexed at the scan after it comes down (vault.rs).
            if entry.evicted {
                if !known.contains_key(&entry.path) {
                    self.vault.fetch(&entry.path);
                }
                continue;
            }
            if known.get(&entry.path) == Some(&(entry.modified_ms, entry.size as i64)) {
                continue;
            }
            self.index_file(entry)?;
        }
        Ok(())
    }

    /// Writes a fresh id into the file at `path`, keeping its modified time, and answers the id: for the second
    /// of two files carrying one id (`index_file`). Written into the file, not only the index, so a fresh clone of
    /// the folder cannot hand the id to whichever file its walk reaches first (the critic's first finding in
    /// docs/MARKDOWN_FIRST.md §12): `Inbox/Plan (conflict from Mac).md` sorts before `Inbox/Plan.md`, and every
    /// ledger keyed by the id - filings, trash, the sidecar - would follow the copy. No sidecar comes with the new
    /// id: a copy has no recording of its own. Answers `None` for a file that cannot be read now (in iCloud and not
    /// on this Mac), which keeps the id it has.
    fn give_fresh_id(&mut self, path: &str, modified_ms: i64) -> Result<Option<(String, Entry)>> {
        let text = match self.vault.read(path) {
            Ok(text) => text,
            Err(e) if super::vault::not_downloaded(&e) => return Ok(None),
            Err(e) => return Err(e.into()),
        };
        // The file's block edited in place, whatever shape it is in (frontmatter.rs `split` keeps every other
        // line); a one-block ticket's own `id: GHO-12` moves to `issue:` rather than being written over.
        let (front, body) = split(&text);
        let mut front = front.unwrap_or_default();
        let fresh = new_id();
        front.claim_id(&fresh);
        let entry = self.vault.write(path, &join(Some(&front), body))?;
        let entry = self.vault.keep_modified(path, modified_ms).unwrap_or(entry);
        Ok(Some((fresh, entry)))
    }

    /// One file read into the index: its id (from its front matter, from the
    /// row already at its path, or a new one for a copy of another note's
    /// file), its dates and flags, and what its sidecar says, with the
    /// revision moved on when the body changed.
    ///
    /// TWO FILES, ONE ID: a conflict copy a sync service made, a copy a person
    /// took. The copy is the one not named for its title (`Plan (conflict from
    /// Mac).md` beside `Plan.md`, `Copy.md` beside `Original.md`); where both
    /// or neither are, the one indexed second. It is given a fresh id, written
    /// into it (`give_fresh_id`), whichever of the two this call is for.
    pub(super) fn index_file(&mut self, entry: &Entry) -> Result<()> {
        let Ok(text) = self.vault.read(&entry.path) else { return Ok(()) };
        let (front, body) = read(&text);
        let at_path = self.row_at(&entry.path)?;
        // A one-block ticket written by hand may say `id: GHO-12`: that is the ticket's key, not a note's id.
        let named = front.text("id").filter(|id| !id.trim().is_empty() && !is_issue_key(id));
        let (id, id_in_file) = match named {
            Some(id) => match self.row(&id)? {
                Some(other) if other.path != entry.path && self.vault.exists(&other.path) => {
                    let this_is_the_note = named_for(&entry.path, &file_stem(&title_of(&body))) && !named_for(&other.path, &file_stem(&title_of(&other.body)));
                    let other_reid = if this_is_the_note { self.give_fresh_id(&other.path, other.modified_at)? } else { None };
                    match other_reid {
                        // The other file was the copy: it has its own id now, and this file keeps the one it carries.
                        Some((fresh, moved)) => {
                            self.index.execute("UPDATE notes SET id = ?2, id_in_file = 1 WHERE path = ?1", rusqlite::params![other.path, fresh])?;
                            self.index_file(&moved)?;
                            (id, true)
                        }
                        // This file is the copy (or the other cannot be rewritten now): it gets its own, written in.
                        None => match self.give_fresh_id(&entry.path, entry.modified_ms)? {
                            Some((_, written)) => return self.index_file(&written),
                            None => (new_id(), false),
                        },
                    }
                }
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
        // When the note was last edited: the later of the file's own time and its `updated:` key. The key keeps a
        // clone's order (git stamps every file with the checkout's time, which is then later and wins, until the
        // plugin restores the times); the file's time keeps an edit made in another app, which moves the time and
        // not the key, at the top of the list.
        let modified_ms = front.text("updated").and_then(|t| parse_iso(&t)).map_or(entry.modified_ms, |updated| updated.max(entry.modified_ms));
        let sidecar = self.sidecar(&id);
        // The row is replaced in one write transaction. Two handles are open in
        // one process now (the app's, and a meeting's write-up on its own
        // thread), and both scan the same files: as two autocommitted
        // statements, the second handle's INSERT could land between the first's
        // DELETE and INSERT and fail on the path's UNIQUE constraint. As one
        // transaction it waits on SQLite's writer lock and replaces the row in
        // its turn.
        let tx = rusqlite::Transaction::new_unchecked(&self.index, rusqlite::TransactionBehavior::Immediate)?;
        tx.execute("DELETE FROM notes WHERE path = ?1 OR id = ?2", rusqlite::params![entry.path, id])?;
        tx.execute(
            &format!("INSERT INTO notes ({ROW_COLUMNS}, title, size, stat_modified_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)"),
            rusqlite::params![
                id,
                entry.path,
                &body,
                created_at,
                modified_ms,
                front.text("source").unwrap_or_else(|| "editor".to_string()),
                front.flag("pinned") as i64,
                archived_at,
                id_in_file as i64,
                sidecar.recording_ms,
                sidecar.formatted_for,
                sidecar.formatted_model,
                prior_revision,
                super::trash::is_trashed_path(&entry.path) as i64,
                title_of(&body),
                entry.size as i64,
                entry.modified_ms,
            ],
        )?;
        tx.commit()?;
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
        self.body_holds(&format!("(image/{name})"))
    }

    /// Whether any note still refers to the film `name` as `(video/<name>)`
    /// (videos.rs), by the same rule as a picture: a deleted note's film goes,
    /// and the daily sweep takes one no note has named for a week, only when
    /// nothing else names it.
    pub fn video_in_use(&self, name: &str) -> Result<bool> {
        self.body_holds(&format!("(video/{name})"))
    }

    /// Whether any note's body holds `needle` as written.
    fn body_holds(&self, needle: &str) -> Result<bool> {
        Ok(self.index.query_row("SELECT EXISTS(SELECT 1 FROM notes WHERE instr(body, ?1) > 0)", [needle], |row| row.get::<_, i64>(0))? != 0)
    }
}
