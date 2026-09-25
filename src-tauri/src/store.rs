//! The database the notes lived in before 1.3.0, `<app_data_dir>/glyph.sqlite`,
//! read once to move them into the library - and NOT ONE `tauri::` TYPE IN
//! THIS FILE, for the reason note.rs gives.
//!
//! Since 1.3.0 the notes are Markdown files (library/, docs/LIBRARY.md). The
//! first launch that finds this file writes every note in it out as a file
//! (`library::move_in`) and renames it `glyph.sqlite.moved`, and nothing opens
//! it again. So `open`, `list_notes` and `get_note` are all the app reaches.
//! The writers after them are for the tests alone, which build an old
//! database to prove the move reads every column of one.
//!
//! `open` still applies the whole schema and adds whatever column an older
//! database lacks, exactly as it did when this was the store: the reads name
//! every column, and a database from any build back to 0.3 has to answer them.

use rusqlite::{Connection, OptionalExtension};
use std::path::Path;
use std::time::Duration;

use crate::note::Note;
#[cfg(test)]
use crate::note::{now_ms, Recording};

/// How long a statement waits for another opener to let go of the write lock.
///
/// Sized for when two processes were meant to write this file - the capture
/// service committing a transcript as the app saved a keystroke - so in
/// practice it was never reached, and with nothing else opening the file now
/// it never will be. Kept so the file is opened the way it always was.
const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

/// The columns every read in this module selects, in the order `row_to_note`
/// unpacks them.
///
/// One constant rather than the same five names written out four times: a
/// SELECT that grows a column in one query and not the others fails at the far
/// end of an `invoke`, in a `row_to_note` that is reading the wrong index,
/// which is a long way from the edit that caused it.
const NOTE_COLUMNS: &str = "id, body, created_at, updated_at, source, starred, archived_at, recording_ms, segments, formatted, formatted_for, formatted_model, revision";

/// `NOTE_COLUMNS` for the list: the same shape, with `segments` read as NULL.
/// A recording's segments are the text of every phrase with its timing - about
/// 10 KB for ten minutes of talk - and the list is fetched every time the app
/// comes to the front. The tapes need only the length; the player asks for
/// one note, and gets its segments from `get_note`.
const LIST_COLUMNS: &str = "id, body, created_at, updated_at, source, starred, archived_at, recording_ms, NULL, NULL, formatted_for, formatted_model, revision";

/// The schema, exactly as DESIGN.md section 5 specifies it, applied on every
/// open.
///
/// `IF NOT EXISTS` rather than a version table and a migration step, because
/// there was no leader to run a migration: the app and the capture service
/// were each to open this file whenever the OS woke them, in either order. The
/// `captures` and `command_mutations` tables are never read; creating them
/// keeps every database this module opens the same shape.
///
/// The index exists because the list screen was always
/// `ORDER BY updated_at DESC`.
const SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        body TEXT NOT NULL,
        created_at INTEGER,
        updated_at INTEGER,
        source TEXT
    );
    CREATE TABLE IF NOT EXISTS captures (
        id TEXT PRIMARY KEY,
        note_id TEXT,
        audio_path TEXT,
        model TEXT,
        duration_ms INTEGER,
        state TEXT
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
    CREATE INDEX IF NOT EXISTS notes_updated_at ON notes (updated_at DESC);
    CREATE INDEX IF NOT EXISTS command_mutations_note ON command_mutations (note_id, created_at DESC);
";

/// Columns added after the first schema, each with the DDL that adds it.
///
/// This is where `SCHEMA`'s argument ("statements a second opener can repeat
/// harmlessly") gets made for the first time. SQLite has no `ADD COLUMN IF NOT
/// EXISTS`, so each is added only when `PRAGMA table_info` says it is missing -
/// and a "duplicate column" error is taken as success, because it means another
/// opener added it between our look and our statement. Every added column is
/// NULLable or has a DEFAULT, so a row written by a build that has never heard
/// of it still reads back.
///
/// - `starred`: pinned to the top of the list by a swipe (0.3.2).
/// - `archived_at`: when it was swiped away into the archive, NULL for a note
///   in the list. A time rather than a flag so the archive can sort by it.
/// - `formatted`: the version the on-device model wrote from the body -
///   expanded, reorganised, as markdown (0.4.0; retired in 0.6.0; back in
///   0.9.0). The body is never touched by it.
/// - `formatted_for`: a hash of the exact body `formatted` was made from, so
///   the page can tell a formatted version is stale once the note is edited.
///   The page computes it; this column only keeps it.
/// - `project_id`: RETIRED with 0.6.0 (the project a note was formatted with).
///   Still added, so a database any build opens has the same shape; never read.
/// - `formatted_model`: which model wrote `formatted` (0.9.0), for the line
///   under the Formatted view.
/// - `recording_ms`: how long the kept recording of a spoken note is, NULL for a
///   note with none (0.6.0). The audio itself is a file beside the database,
///   `recordings/<id>.wav`, written by the capture layer; see `recording_file`.
/// - `segments`: the recording's committed phrases as JSON,
///   `[{"text", "startMs", "endMs"}]`, so the player can follow the words.
const ADDED_COLUMNS: &[(&str, &str)] = &[
    ("starred", "ALTER TABLE notes ADD COLUMN starred INTEGER NOT NULL DEFAULT 0"),
    ("archived_at", "ALTER TABLE notes ADD COLUMN archived_at INTEGER"),
    ("formatted", "ALTER TABLE notes ADD COLUMN formatted TEXT"),
    ("formatted_for", "ALTER TABLE notes ADD COLUMN formatted_for INTEGER"),
    ("project_id", "ALTER TABLE notes ADD COLUMN project_id TEXT"),
    ("recording_ms", "ALTER TABLE notes ADD COLUMN recording_ms INTEGER"),
    ("segments", "ALTER TABLE notes ADD COLUMN segments TEXT"),
    ("formatted_model", "ALTER TABLE notes ADD COLUMN formatted_model TEXT"),
    ("revision", "ALTER TABLE notes ADD COLUMN revision INTEGER NOT NULL DEFAULT 1"),
];

fn add_missing_columns(conn: &Connection) -> rusqlite::Result<()> {
    let mut stmt = conn.prepare("PRAGMA table_info(notes)")?;
    let present: Vec<String> = stmt.query_map([], |row| row.get::<_, String>(1))?.collect::<rusqlite::Result<_>>()?;
    for (column, ddl) in ADDED_COLUMNS {
        if present.iter().any(|p| p == column) {
            continue;
        }
        match conn.execute(ddl, []) {
            Ok(_) => {}
            Err(rusqlite::Error::SqliteFailure(_, Some(message))) if message.contains("duplicate column") => {}
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

/// What can go wrong in here, which is SQLite and nothing else.
///
/// A hand-written enum rather than `thiserror`, which is already in this tree
/// twice (1.0.69 and 2.0.20, both arriving under tauri) and would therefore
/// compile no new code. It would still put a derive macro between the reader
/// and two `write!` calls, and the entire error surface of this module is two
/// variants that differ only in which sentence a person should read first: the
/// database would not open at all, or one statement failed. A dependency that
/// saves four lines and costs a layer of indirection is not a saving.
///
/// Both variants carry the `rusqlite::Error` rather than a flattened string,
/// so a caller that wants to tell `SQLITE_BUSY` from a corrupt file still can.
/// The move into the library does not: it says why in a sentence.
#[derive(Debug)]
pub enum StoreError {
    /// The file could not be opened, or the schema could not be applied to it.
    /// Nothing else in the module can have run.
    Open(rusqlite::Error),
    /// One statement failed against a database that opened cleanly.
    Query(rusqlite::Error),
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StoreError::Open(e) => write!(f, "the notes database could not be opened: {e}"),
            StoreError::Query(e) => write!(f, "the notes database refused a statement: {e}"),
        }
    }
}

impl std::error::Error for StoreError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            StoreError::Open(e) | StoreError::Query(e) => Some(e),
        }
    }
}

/// `?` inside this module means `Query`, and `open` says `Open` by hand.
///
/// The conversion is deliberately one-directional like this rather than
/// symmetric: there are many fallible statements and exactly one open, so
/// the common case is the one that gets the operator and the rare case is the
/// one that gets spelled out.
impl From<rusqlite::Error> for StoreError {
    fn from(error: rusqlite::Error) -> Self {
        StoreError::Query(error)
    }
}

pub type Result<T> = std::result::Result<T, StoreError>;

/// Unpacks a row selected as `NOTE_COLUMNS`.
///
/// `created_at`, `updated_at` and `source` are nullable in the schema (that is
/// DESIGN section 5's DDL, kept verbatim) even though no build ever wrote a
/// NULL into them. Reading them as optional and defaulting keeps a row written
/// by hand, during a capture bring-up, from failing the whole move.
fn row_to_note(row: &rusqlite::Row<'_>) -> rusqlite::Result<Note> {
    Ok(Note {
        id: row.get(0)?,
        body: row.get(1)?,
        created_at: row.get::<_, Option<i64>>(2)?.unwrap_or(0),
        updated_at: row.get::<_, Option<i64>>(3)?.unwrap_or(0),
        source: row.get::<_, Option<String>>(4)?.unwrap_or_default(),
        starred: row.get::<_, Option<i64>>(5)?.unwrap_or(0) != 0,
        archived_at: row.get::<_, Option<i64>>(6)?,
        recording_ms: row.get::<_, Option<i64>>(7)?,
        // Unreadable JSON reads as no segments rather than failing the note:
        // the words are in the body either way.
        segments: row
            .get::<_, Option<String>>(8)?
            .and_then(|json| serde_json::from_str(&json).ok()),
        formatted: row.get::<_, Option<String>>(9)?,
        formatted_for: row.get::<_, Option<i64>>(10)?,
        formatted_model: row.get::<_, Option<String>>(11)?,
        path: None,
        revision: row.get::<_, Option<i64>>(12)?.unwrap_or(1),
    })
}

/// An open database, and the only thing in this module that holds state.
pub struct Store {
    conn: Connection,
}

impl Store {
    /// Opens the database at `path` (creating it if absent) and makes sure the
    /// schema is there - see `SCHEMA` and `ADDED_COLUMNS`.
    ///
    /// The path is a parameter rather than something this function works out,
    /// which is note.rs's rule in one signature: the move passes
    /// `<app_data_dir>/glyph.sqlite`, and this function cannot tell who called.
    ///
    /// WAL is asked for with a query rather than a `PRAGMA` execute because
    /// `journal_mode` answers with a row, and an unconsumed row is an error in
    /// rusqlite. The answer is then not checked, on purpose: a filesystem that
    /// cannot support WAL leaves SQLite on a rollback journal, which reads the
    /// notes just the same. Refusing to open them over that would lose them.
    pub fn open(path: &Path) -> Result<Store> {
        let conn = Connection::open(path).map_err(StoreError::Open)?;
        conn.query_row("PRAGMA journal_mode=WAL", [], |row| row.get::<_, String>(0))
            .map_err(StoreError::Open)?;
        conn.busy_timeout(BUSY_TIMEOUT).map_err(StoreError::Open)?;
        conn.execute_batch(SCHEMA).map_err(StoreError::Open)?;
        add_missing_columns(&conn).map_err(StoreError::Open)?;
        Ok(Store { conn })
    }

    /// Every note, newest edit first - with `id` breaking a tie, so the same
    /// data always lists in the same order - and without the recording's
    /// phrases or the formatted text (`LIST_COLUMNS`), which the move reads
    /// note by note with `get_note`.
    pub fn list_notes(&self) -> Result<Vec<Note>> {
        let sql = format!("SELECT {LIST_COLUMNS} FROM notes ORDER BY updated_at DESC, id");
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map([], row_to_note)?;
        let mut notes = Vec::new();
        for note in rows {
            notes.push(note?);
        }
        Ok(notes)
    }

    /// One note, whole, or `None` when nothing answers to that id.
    pub fn get_note(&self, id: &str) -> Result<Option<Note>> {
        let sql = format!("SELECT {NOTE_COLUMNS} FROM notes WHERE id = ?1");
        let note = self
            .conn
            .query_row(&sql, [id], row_to_note)
            .optional()?;
        Ok(note)
    }
}

/// Writers, for the tests alone: they build the old database a move is proved
/// against. None is compiled into the app, which never writes this file.
#[cfg(test)]
impl Store {
    /// Inserts a note while its id is unused, stamped now.
    pub fn create_note(&self, id: &str, body: &str, source: &str) -> Result<Option<Note>> {
        let now = now_ms();
        let inserted = self.conn.execute(
            "INSERT INTO notes (id, body, created_at, updated_at, source)
             VALUES (?1, ?2, ?3, ?3, ?4)
             ON CONFLICT(id) DO NOTHING",
            rusqlite::params![id, body, now, source],
        )?;
        if inserted == 0 { return Ok(None); }
        self.get_note(id)
    }

    /// Replaces exactly the revision an existing writer read, stamped now.
    pub fn update_note(&self, id: &str, body: &str, expected_revision: i64) -> Result<Option<Note>> {
        let changed = self.conn.execute(
            "UPDATE notes SET body = ?2, updated_at = ?3, revision = revision + 1
             WHERE id = ?1 AND revision = ?4",
            rusqlite::params![id, body, now_ms(), expected_revision],
        )?;
        if changed == 0 { return Ok(None); }
        self.get_note(id)
    }

    /// An insert, or an edit of whatever revision is there.
    pub(crate) fn save_note(&self, id: &str, body: &str, source: &str) -> Result<Note> {
        if let Some(current) = self.get_note(id)? {
            return self.update_note(id, body, current.revision)?
                .ok_or_else(|| StoreError::Query(rusqlite::Error::QueryReturnedNoRows));
        }
        self.create_note(id, body, source)?
            .ok_or_else(|| StoreError::Query(rusqlite::Error::QueryReturnedNoRows))
    }

    /// A note's recording length and phrases, or neither with `None`.
    pub fn set_recording(&self, id: &str, recording: Option<&Recording>) -> Result<Option<Note>> {
        let (ms, json) = match recording {
            Some(r) => (Some(r.ms()), Some(serde_json::to_string(r.segments()).unwrap_or_else(|_| "[]".into()))),
            None => (None, None),
        };
        self.conn.execute(
            "UPDATE notes SET recording_ms = ?2, segments = ?3 WHERE id = ?1",
            rusqlite::params![id, ms, json],
        )?;
        self.get_note(id)
    }

    /// A note's formatted version, the hash of the body it came from, and its model.
    pub fn set_formatted(
        &self,
        id: &str,
        formatted: Option<&str>,
        formatted_for: Option<i64>,
        model: Option<&str>,
    ) -> Result<Option<Note>> {
        self.conn.execute(
            "UPDATE notes SET formatted = ?2, formatted_for = ?3, formatted_model = ?4 WHERE id = ?1",
            rusqlite::params![id, formatted, formatted_for, model],
        )?;
        self.get_note(id)
    }

    /// Stars or unstars a note, leaving `updated_at` where it was.
    pub fn set_starred(&self, id: &str, starred: bool) -> Result<Option<Note>> {
        self.conn.execute("UPDATE notes SET starred = ?2 WHERE id = ?1", rusqlite::params![id, starred as i64])?;
        self.get_note(id)
    }

    /// Archives a note, stamped now, or brings it back.
    pub fn set_archived(&self, id: &str, archived: bool) -> Result<Option<Note>> {
        let at = archived.then(now_ms);
        self.conn.execute("UPDATE notes SET archived_at = ?2 WHERE id = ?1", rusqlite::params![id, at])?;
        self.get_note(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::note::{new_id, RecordedSegment};

    /// A database of its own per test, swept up when the test ends however it
    /// ends.
    ///
    /// A temp path and a `Drop` rather than the `tempfile` crate: this is the
    /// only place in the crate that wants one, and the crate would be a
    /// dependency bought for six lines. `Drop` rather than a tidy-up at the
    /// bottom of each test because a failing assertion panics straight past
    /// the last line, and a run that leaves its databases behind every time it
    /// catches a bug is a temp directory that fills up while you are fixing
    /// one.
    ///
    /// The sidecars matter: WAL means `-wal` and `-shm` sit beside the file,
    /// and deleting only the database leaves a journal for the next test that
    /// happens to draw the same name.
    struct TempDb {
        store: Store,
        path: std::path::PathBuf,
    }

    impl TempDb {
        fn new() -> TempDb {
            let path = std::env::temp_dir().join(format!("glyph-store-test-{}.sqlite", new_id()));
            let store = Store::open(&path).expect("a fresh database in the temp directory opens");
            TempDb { store, path }
        }
    }

    impl Drop for TempDb {
        fn drop(&mut self) {
            for suffix in ["", "-wal", "-shm"] {
                let mut name = self.path.clone().into_os_string();
                name.push(suffix);
                let _ = std::fs::remove_file(std::path::PathBuf::from(name));
            }
        }
    }

    /// Puts daylight between two writes.
    ///
    /// `updated_at` is a millisecond clock, and two saves inside one tick
    /// carry the same stamp - which is a fact about the clock, not a fault in
    /// the store, and is why `list_notes` has a tiebreak at all. A test that
    /// asserts one save is newer than another has to actually make it so.
    fn tick() {
        std::thread::sleep(Duration::from_millis(2));
    }

    fn segment(text: &str, start_ms: u64, end_ms: u64) -> RecordedSegment {
        RecordedSegment { text: text.into(), start_ms, end_ms }
    }

    #[test]
    fn a_recording_is_kept_beside_the_note_and_the_list_leaves_its_segments_out() {
        let db = TempDb::new();
        let saved = db.store.save_note("n1", "call sam", "capture").unwrap();
        assert_eq!((saved.recording_ms, saved.segments.clone()), (None, None));
        tick();

        let recording = Recording::new(4200, vec![segment("Call Sam.", 0, 1800), segment("About Friday.", 1800, 4200)]).unwrap();
        let kept = db.store.set_recording("n1", Some(&recording)).unwrap().unwrap();
        assert_eq!(kept.recording_ms, Some(4200));
        assert_eq!(kept.segments.as_deref().map(<[_]>::len), Some(2));
        assert_eq!(kept.updated_at, saved.updated_at, "keeping a recording is not an edit");

        let listed = db.store.list_notes().unwrap();
        assert_eq!(listed[0].recording_ms, Some(4200), "the list carries the length");
        assert_eq!(listed[0].segments, None, "and not the segments");

        let forgotten = db.store.set_recording("n1", None).unwrap().unwrap();
        assert_eq!((forgotten.recording_ms, forgotten.segments), (None, None));
        assert_eq!(db.store.set_recording("gone", Some(&recording)).unwrap(), None);
    }

    #[test]
    fn a_formatted_version_is_kept_beside_the_note_and_the_list_leaves_its_text_out() {
        let db = TempDb::new();
        let saved = db.store.save_note("n1", "call the plumber", "capture").unwrap();
        assert_eq!(saved.formatted, None);
        tick();

        let kept = db.store.set_formatted("n1", Some("# Plumber\n\n- [ ] Call the plumber\n"), Some(4_503_599_627_370_495), Some("qwen3.5-4b")).unwrap().unwrap();
        assert_eq!(kept.formatted.as_deref(), Some("# Plumber\n\n- [ ] Call the plumber\n"));
        assert_eq!(kept.formatted_for, Some(4_503_599_627_370_495), "a 52-bit hash round-trips");
        assert_eq!(kept.formatted_model.as_deref(), Some("qwen3.5-4b"));
        assert_eq!(kept.updated_at, saved.updated_at, "keeping a formatted version is not an edit");

        // The list carries the hash and the model, not the text again.
        let listed = db.store.list_notes().unwrap().into_iter().find(|n| n.id == "n1").unwrap();
        assert_eq!(listed.formatted, None);
        assert_eq!(listed.formatted_for, Some(4_503_599_627_370_495));
        assert_eq!(listed.formatted_model.as_deref(), Some("qwen3.5-4b"));

        // An edit keeps it: the page tells staleness by the hash, not by absence.
        let edited = db.store.save_note("n1", "call the plumber tomorrow", "editor").unwrap();
        assert!(edited.formatted.is_some());
        assert_eq!(db.store.set_formatted("n1", None, None, None).unwrap().unwrap().formatted, None);
        assert_eq!(db.store.set_formatted("gone", Some("x"), Some(1), None).unwrap(), None);
    }

    #[test]
    fn a_database_from_before_stars_gains_the_columns_and_keeps_its_notes() {
        let path = std::env::temp_dir().join(format!("glyph-store-old-{}.sqlite", new_id()));
        {
            let conn = Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE notes (id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER, updated_at INTEGER, source TEXT);
                 INSERT INTO notes VALUES ('old', 'from 0.3.1', 1, 1, 'editor');",
            )
            .unwrap();
        }
        let store = Store::open(&path).unwrap();
        let note = store.get_note("old").unwrap().unwrap();
        assert_eq!(note.body, "from 0.3.1");
        assert!(!note.starred);
        assert_eq!(note.archived_at, None);
        // Opening again - the next launch - repeats the migration harmlessly.
        drop(store);
        let again = Store::open(&path).unwrap();
        assert!(again.set_starred("old", true).unwrap().unwrap().starred);
        drop(again);
        for suffix in ["", "-wal", "-shm"] {
            let mut name = path.clone().into_os_string();
            name.push(suffix);
            let _ = std::fs::remove_file(std::path::PathBuf::from(name));
        }
    }

    #[test]
    fn a_saved_note_comes_back_out_of_the_list() {
        let db = TempDb::new();
        let saved = db.store.save_note("n1", "# Kettle\nDescale it", "editor").unwrap();
        assert_eq!(saved.id, "n1");
        assert_eq!(saved.body, "# Kettle\nDescale it");
        assert_eq!(saved.source, "editor");
        // Both stamps are set on an insert, and to the same instant.
        assert!(saved.created_at > 0);
        assert_eq!(saved.created_at, saved.updated_at);

        let listed = db.store.list_notes().unwrap();
        assert_eq!(listed, vec![saved.clone()]);
        assert_eq!(db.store.get_note("n1").unwrap(), Some(saved));
        // A note nobody wrote is absent, not an error - the whole reason
        // get_note answers with an Option.
        assert_eq!(db.store.get_note("never-written").unwrap(), None);
    }

    #[test]
    fn the_list_is_newest_edit_first_not_newest_note_first() {
        let db = TempDb::new();
        db.store.save_note("oldest", "first written", "editor").unwrap();
        tick();
        db.store.save_note("middle", "second written", "editor").unwrap();
        tick();
        db.store.save_note("newest", "third written", "editor").unwrap();

        let order: Vec<String> =
            db.store.list_notes().unwrap().into_iter().map(|n| n.id).collect();
        assert_eq!(order, ["newest", "middle", "oldest"]);

        tick();
        db.store.save_note("oldest", "first written, touched", "editor").unwrap();
        let order: Vec<String> =
            db.store.list_notes().unwrap().into_iter().map(|n| n.id).collect();
        assert_eq!(
            order,
            ["oldest", "newest", "middle"],
            "editing an old note must lift it to the top - the list sorts by updated_at, \
             and an index on the wrong column would still pass every other test here"
        );
    }
}
