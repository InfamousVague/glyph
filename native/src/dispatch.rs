//! The commands, by the names the web page gave Tauri's `invoke`, each doing what its `#[tauri::command]` in
//! `../glyph/src-tauri/src/commands.rs` (and `library_commands.rs` for `library_root`) does: take the lock,
//! call one `Library` function, turn its error into the sentence a person reads.
//!
//! What differs from commands.rs:
//!
//! - **No Tauri.** Arguments arrive as the JSON object the page sent (camelCase keys) and are read here, where
//!   Tauri's macro read them; the answer is JSON. An argument that is missing or of the wrong kind is an `Err`
//!   naming the command, as Tauri's is.
//! - **`init {dataDir, cacheDir}`** is `commands::install`: Tauri resolved the directories from its `AppHandle`
//!   in `setup`, and here the app says them (lib/core/native/device_paths.dart). A second `init` with the same
//!   directories is fine, so a hot restart or a second isolate need not know whether it is first; with
//!   different ones it is refused, since the library already open belongs to the first.
//! - **`new_id`** answers `note::new_id()`, so Dart mints ids with the generator Rust's capture uses.
//! - `ApplyCommandRequest::into_mutation`, `delete_with_files` and `status_of` are those files' own, moved here
//!   because the files name Tauri. Their tests came with them.
//!
//! - **Stage 7's commands live in files of their own** and are only handed on from here: the account's keys and
//!   the sealed wire (crypto.rs) and Yjs documents (crdt.rs) are answered before the library is looked for, so
//!   they need no `init` and never wait on the notes' lock; the files sync carries (files.rs, `sync_put_file`
//!   among them) are answered with the library's directories.
//!
//! - **Stage 8C's commands live in files of their own** too (the `voice` feature): dictation (capture.rs), the
//!   language model (ai.rs), a meeting's write-up and tapes (recording.rs), over models.rs's downloads. Each
//!   lists its commands and events; `call_on` hands them the open core for its directories.
//!
//! - **`reset_local_data {models}`** is reset.rs's, its lines held in kept/reset.rs.
//!
//! Not here yet, each waiting for the stage that needs it: `set_note_formatted`, `library_reveal`, and the folder
//! plugin's moves (`library_choose_folder`, `library_inspect`, `library_move`, `library_use_app_folder`).

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::kept::recordings::recording_file;
use crate::library::root::Root;
use crate::library::Library;
use crate::note::{CommandMutation, Note, RecordedSegment, Recording};

/// The notes' library, opened by `init` and held for the life of the process: commands.rs's `NotesStore`, with
/// its reasons (one `Library` keeps the index warm; a `Mutex` because the index's connection is not `Sync`).
pub struct NotesStore(pub Mutex<Library>);

impl NotesStore {
    /// The guard, recovered if some earlier command panicked while holding it (`crate::lock` says why).
    pub(crate) fn lock(&self) -> std::sync::MutexGuard<'_, Library> {
        crate::lock::lock(&self.0)
    }
}

/// A command the person confirmed from its preview, as the page sends it.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ApplyCommandRequest {
    mutation_id: String,
    note_id: String,
    kind: String,
    before_revision: Option<i64>,
    before_body: Option<String>,
    after_body: String,
    source: String,
}

impl ApplyCommandRequest {
    /// The mutation this asks for, or why none may be written: checked whole
    /// before the library is touched.
    fn into_mutation(self) -> std::result::Result<CommandMutation, String> {
        // The crate's one rule for an id from the page: the note id may become a
        // recording's or a sidecar's file name, and the mutation id is held to the
        // same bound.
        use crate::fsx::plain_id;
        if !plain_id(&self.mutation_id) || !plain_id(&self.note_id) {
            return Err("a command mutation needs plain bounded ids".into());
        }
        if !matches!(self.source.as_str(), "editor" | "capture") {
            return Err("a command mutation has an unsupported source".into());
        }
        if !matches!(self.kind.as_str(), "append" | "create") {
            return Err("only append and create command mutations are supported".into());
        }
        if self.kind == "create" && (self.before_revision.is_some() || self.before_body.is_some()) {
            return Err("a create command cannot replace an existing note".into());
        }
        if self.kind == "append" && (self.before_revision.is_none() || self.before_body.is_none()) {
            return Err("an append command needs the previewed note revision".into());
        }
        Ok(CommandMutation {
            id: self.mutation_id,
            note_id: self.note_id,
            kind: self.kind,
            before_revision: self.before_revision,
            before_body: self.before_body,
            after_body: self.after_body,
            source: self.source,
        })
    }
}

/// Where a note's files are kept, each `None` where the platform gave no
/// directory, which leaves those files alone.
struct Kept {
    images: Option<PathBuf>,
    videos: Option<PathBuf>,
    recordings: Option<PathBuf>,
    jobs: Option<PathBuf>,
}

/// `delete_note`'s work, given where pictures, films, recordings and write-ups
/// are kept.
fn delete_with_files(notes: &NotesStore, kept: &Kept, id: &str) -> std::result::Result<bool, String> {
    let (images, videos, recordings, jobs) = (kept.images.as_deref(), kept.videos.as_deref(), kept.recordings.as_deref(), kept.jobs.as_deref());
    let mut library = notes.lock();
    // The body is read before the row goes: it is the only list of the
    // pictures the note had. They go after it, so a failed delete never
    // leaves a note pointing at pictures that are gone, and one another note
    // also shows (a copied line) is kept. The lock is held for that check,
    // which reads the index the delete has just changed.
    let body = library.get_note(id).ok().flatten().map(|note| note.body);
    let removed = library.delete_note(id).map_err(|e| e.to_string())?;
    if let (Some(body), Some(images)) = (&body, images) {
        crate::kept::images::remove_unreferenced(images, &library, body);
    }
    if let (Some(body), Some(videos)) = (&body, videos) {
        crate::kept::videos::remove_unreferenced(videos, &library, body);
    }
    drop(library);
    if let Some(file) = recordings.and_then(|dir| recording_file(dir, id)) {
        let _ = std::fs::remove_file(file);
    }
    // A write-up for a note that is gone has nothing to write into; its
    // progress goes under the lock every writer of it takes (jobs.rs).
    if let Some(jobs) = jobs.filter(|_| crate::fsx::plain_id(id)) {
        let _one = crate::lock::lock(&crate::guards::PROGRESS_FILE);
        let _ = std::fs::remove_file(crate::jobs::progress_path(jobs, id));
        let _ = std::fs::remove_file(crate::jobs::result_path(jobs, id));
    }
    Ok(removed)
}

/// Where the library is, as the page shows it: library_commands.rs's `Status`.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    /// `app`, `folder` or `tree`: what the setting says.
    kind: &'static str,
    /// The chosen folder's path, on the Mac.
    path: Option<String>,
    /// Its name: the folder's own, or the one Android's picker showed.
    name: Option<String>,
    /// False while a chosen folder cannot be reached and the app's own is open instead.
    reachable: bool,
    /// Notes in the library that is open.
    notes: usize,
    /// The app's own folder.
    own: Option<String>,
}

fn named(path: &Path) -> String {
    path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| path.display().to_string())
}

fn status_of(data: &Path, store: &NotesStore) -> Status {
    let chosen = Root::read(data);
    let library = store.lock();
    let reachable = chosen == Root::App || !library.in_own_folder();
    let (path, name) = match &chosen {
        Root::App => (None, None),
        Root::Folder { path } => (Some(path.display().to_string()), Some(named(path))),
        Root::Tree { name, .. } => (None, Some(name.clone())),
    };
    Status { kind: chosen.kind(), path, name, reachable, notes: library.note_count().unwrap_or(0), own: Some(crate::library_root::own_folder(data).display().to_string()) }
}

/// The app's two directories and the library open in the first: what Tauri's managed state and `AppHandle`
/// were to commands.rs.
pub struct Core {
    data: PathBuf,
    cache: PathBuf,
    notes: NotesStore,
}

// What each command takes, as the page sends it. A field Tauri's command had as an `Option` may be left out.

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Init {
    data_dir: PathBuf,
    cache_dir: PathBuf,
}

#[derive(Deserialize)]
struct ById {
    id: String,
}

#[derive(Deserialize)]
struct Create {
    id: String,
    body: String,
    source: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Update {
    id: String,
    body: String,
    expected_revision: i64,
}

#[derive(Deserialize)]
struct Starred {
    id: String,
    starred: bool,
}

#[derive(Deserialize)]
struct Archived {
    id: String,
    archived: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SetRecording {
    id: String,
    recording_ms: Option<i64>,
    segments: Option<Vec<RecordedSegment>>,
}

#[derive(Deserialize)]
struct Apply {
    note: Note,
}

#[derive(Deserialize)]
struct ApplyCommand {
    request: ApplyCommandRequest,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Undo {
    mutation_id: String,
}

#[derive(Deserialize)]
struct Reset {
    models: bool,
}

#[derive(Deserialize)]
struct WriteVersions {
    id: String,
    text: String,
}

/// A command's arguments read from what was sent, or the sentence that says what was wrong with them.
pub(crate) fn read<T: DeserializeOwned>(command: &str, args: Value) -> Result<T, String> {
    serde_json::from_value(args).map_err(|e| format!("invalid args for command `{command}`: {e}"))
}

fn answer<T: Serialize>(value: T) -> Result<Value, String> {
    serde_json::to_value(value).map_err(|e| format!("the answer could not be written: {e}"))
}

impl Core {
    /// `commands::install`: the data directory made, and the library opened where `library-root.json` says (the
    /// app's own folder, or one the person chose), bringing the pre-1.3.0 database in the first time.
    pub fn open(data: &Path, cache: &Path) -> Result<Core, String> {
        crate::fsx::make_dir(data)?;
        let library = crate::library_root::open(data, true)?;
        Ok(Core { data: data.to_path_buf(), cache: cache.to_path_buf(), notes: NotesStore(Mutex::new(library)) })
    }

    /// The directory `init` named for the cache. Nothing in stage 3 writes there; `picked/` will.
    pub fn cache_dir(&self) -> &Path {
        &self.cache
    }

    /// The notes, for a job's thread (work.rs): locked for one read or one write, never across its work.
    pub fn notes(&self) -> &NotesStore {
        &self.notes
    }

    /// The app's data directory, which `init` named.
    pub fn data_dir(&self) -> &Path {
        &self.data
    }

    /// One command, or the sentence that says why not.
    pub fn call(&self, command: &str, args: Value) -> Result<Value, String> {
        let store = &self.notes;
        let said = |e: crate::library::LibraryError| e.to_string();
        match command {
            // Every note, newest edit first. What the list screen draws.
            "list_notes" => answer(store.lock().list_notes().map_err(said)?),
            // One note, or `null` when nothing answers to that id.
            "get_note" => {
                let ById { id } = read(command, args)?;
                answer(store.lock().get_note(&id).map_err(said)?)
            }
            // Creates a note only while its id is unused.
            "create_note" => {
                let Create { id, body, source } = read(command, args)?;
                let note = store.lock().create_note(&id, &body, &source).map_err(said)?;
                answer(note.ok_or_else(|| "the note id already exists".to_string())?)
            }
            // Updates exactly an existing revision. A deleted row is a conflict, never an invitation to insert
            // it again.
            "update_note" => {
                let Update { id, body, expected_revision } = read(command, args)?;
                let note = store.lock().update_note(&id, &body, expected_revision).map_err(said)?;
                answer(note.ok_or_else(|| "the note was deleted or changed".to_string())?)
            }
            // Removes a note for good, with its pictures, films, recording and write-up files.
            "delete_note" => {
                let ById { id } = read(command, args)?;
                let kept = Kept {
                    images: Some(self.data.join(crate::paths::IMAGES)),
                    videos: Some(self.data.join(crate::paths::VIDEO)),
                    recordings: Some(self.data.join(crate::paths::RECORDINGS)),
                    jobs: Some(self.data.join(crate::paths::JOBS)),
                };
                answer(delete_with_files(store, &kept, &id)?)
            }
            "set_note_starred" => {
                let Starred { id, starred } = read(command, args)?;
                answer(store.lock().set_starred(&id, starred).map_err(said)?)
            }
            "set_note_archived" => {
                let Archived { id, archived } = read(command, args)?;
                answer(store.lock().set_archived(&id, archived).map_err(said)?)
            }
            // Keeps a spoken note's recording length and phrases, or forgets both with `recordingMs: null`.
            "set_note_recording" => {
                let SetRecording { id, recording_ms, segments } = read(command, args)?;
                let recording = match recording_ms {
                    Some(ms) => Some(Recording::new(ms, segments.unwrap_or_default())?),
                    None => None,
                };
                answer(store.lock().set_recording(&id, recording.as_ref()).map_err(said)?)
            }
            // Writes a note as another device has it: its own times, pin, archive, folder, phrases.
            "store_apply" => {
                let Apply { note } = read(command, args)?;
                if let Some(segments) = &note.segments {
                    Recording::new(note.recording_ms.unwrap_or(0), segments.clone())?;
                }
                answer(store.lock().apply_note(&note).map_err(said)?)
            }
            // Applies only the already-previewed deterministic Markdown.
            "apply_command_mutation" => {
                let ApplyCommand { request } = read(command, args)?;
                let change = request.into_mutation()?;
                answer(store.lock().apply_command(&change).map_err(said)?)
            }
            "undo_command_mutation" => {
                let Undo { mutation_id } = read(command, args)?;
                answer(store.lock().undo_command(&mutation_id).map_err(said)?)
            }
            // The command from the last ten minutes that can still be undone, if any.
            "latest_command_mutation" => answer(store.lock().latest_command_undo(10 * 60 * 1_000).map_err(said)?),
            "versions_read" => {
                let ById { id } = read(command, args)?;
                answer(store.lock().read_versions(&id).map_err(said)?)
            }
            "versions_write" => {
                let WriteVersions { id, text } = read(command, args)?;
                answer(store.lock().write_versions(&id, &text).map_err(said)?)
            }
            // Where the library is now.
            "library_root" => answer(status_of(&self.data, store)),
            // Starting over: every note, recording, picture, film and write-up, and the models when asked. A
            // folder of the person's is forgotten, never emptied (kept/reset.rs).
            "reset_local_data" => {
                let Reset { models } = read(command, args)?;
                answer(crate::kept::reset::reset_local_data(&self.data, &self.cache, store, models)?)
            }
            // The files sync carries: a recording, a picture, a versions file (files.rs).
            command if crate::files::has(command) => crate::files::call(&self.data, store, command, args),
            // A panic with the library's lock held, for the tests of what the boundary does with one.
            #[cfg(any(test, feature = "test-hooks"))]
            "test_panic" => {
                let _held = store.lock();
                panic!("a command dies with the lock");
            }
            _ => Err(format!("Ghost.md's core has no command named {command}.")),
        }
    }
}

/// The one core of this process, once `init` has opened it.
static CORE: Mutex<Option<Arc<Core>>> = Mutex::new(None);

/// `init`: opens the core, or agrees that it is open on these directories already.
fn init(args: Value) -> Result<Value, String> {
    let Init { data_dir, cache_dir } = read("init", args)?;
    let mut core = crate::lock::lock(&CORE);
    if let Some(open) = core.as_ref() {
        if open.data == data_dir && open.cache == cache_dir {
            return Ok(Value::Null);
        }
        return Err(format!("Ghost.md's core is already open on {}, and cannot also open {}.", open.data.display(), data_dir.display()));
    }
    *core = Some(Arc::new(Core::open(&data_dir, &cache_dir)?));
    Ok(Value::Null)
}

/// One command from the app, by name, with its arguments as JSON (`null` for none).
pub fn invoke(command: &str, args: Value) -> Result<Value, String> {
    let args = if args.is_null() { json!({}) } else { args };
    match command {
        "init" => init(args),
        "new_id" => Ok(Value::String(crate::note::new_id())),
        // Keys, sealing and documents hold tables of their own: no library, and none of its lock.
        command if crate::crypto::has(command) => crate::crypto::call(command, args),
        command if crate::crdt::has(command) => crate::crdt::call(command, args),
        // Long jobs are cancelled and listed with no library either (work.rs).
        command if crate::work::has(command) => crate::work::call(command, args),
        // Stage 8A's proof that each engine runs: a model file and a job, no library (smoke.rs).
        #[cfg(feature = "voice")]
        command if crate::smoke::has(command) => crate::smoke::call(command, args),
        // What this binary's voice and AI commands promise, said with no library (ai.rs).
        #[cfg(feature = "voice")]
        command if crate::ai::has_without_core(command) => crate::ai::call_without_core(command),
        _ => {
            // The core is taken out from under its lock before the command runs, so a slow command holds only the
            // library's own.
            let core = crate::lock::lock(&CORE).clone();
            let core = core.ok_or_else(|| format!("Ghost.md's core is not open yet, so it cannot answer {command}."))?;
            call_on(&core, command, args)
        }
    }
}

/// One command to an open core: what `invoke` comes to once it has found the process's one, and what a test
/// asks of a core of its own.
pub(crate) fn call_on(core: &Arc<Core>, command: &str, args: Value) -> Result<Value, String> {
    // What starts a job takes the `Arc`: its thread keeps the core, and answers with an id at once.
    if crate::work::has_with_core(command) {
        return crate::work::call_with_core(core, command, args);
    }
    // Stage 8C: dictation, the language model, a meeting's write-up and tapes, each on the core's directories.
    #[cfg(feature = "voice")]
    {
        if crate::capture::has(command) {
            return crate::capture::call(core, command, args);
        }
        if crate::ai::has(command) {
            return crate::ai::call(core, command, args);
        }
        if crate::recording::has(command) {
            return crate::recording::call(core, command, args);
        }
    }
    core.call(command, args)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;
    use std::path::PathBuf;

    /// A library, a pictures folder and a recordings folder, as a phone has
    /// them. The library is closed before its folder goes: fields drop in order.
    struct Phone {
        notes: NotesStore,
        root: TempDir,
    }

    impl Phone {
        fn new() -> Phone {
            let root = TempDir::new("commands");
            let notes = NotesStore(Mutex::new(Library::open_fs(&root.join("Library")).unwrap()));
            for dir in ["images", "video", "recordings", "jobs"] {
                std::fs::create_dir_all(root.join(dir)).unwrap();
            }
            Phone { notes, root }
        }

        fn file(&self, path: &str) -> PathBuf {
            self.root.join(path)
        }

        fn delete(&self, id: &str) -> Result<bool, String> {
            let kept = Kept {
                images: Some(self.file("images")),
                videos: Some(self.file("video")),
                recordings: Some(self.file("recordings")),
                jobs: Some(self.file("jobs")),
            };
            delete_with_files(&self.notes, &kept, id)
        }
    }

    #[test]
    fn a_deleted_note_takes_its_pictures_and_recording_but_not_another_notes_picture() {
        let phone = Phone::new();
        for name in ["images/mine.jpg", "images/shared.png", "images/theirs.jpg", "recordings/n1.wav", "recordings/n2.wav", "jobs/n1.progress", "jobs/n1.json", "jobs/n2.progress"] {
            std::fs::write(phone.file(name), b"bytes").unwrap();
        }
        {
            let mut library = phone.notes.lock();
            library.save_note("n1", "# Trip\n\n![](image/mine.jpg)\n![](image/shared.png)\n", "capture").unwrap();
            library.save_note("n2", "# Other\n\n![](image/shared.png)\n![](image/theirs.jpg)\n", "capture").unwrap();
        }
        assert_eq!(phone.delete("n1"), Ok(true));
        assert!(!phone.file("images/mine.jpg").exists(), "a picture only it showed goes with it");
        assert!(phone.file("images/shared.png").exists(), "one another note still shows is kept");
        assert!(!phone.file("recordings/n1.wav").exists(), "its recording goes too");
        assert!(!phone.file("jobs/n1.progress").exists() && !phone.file("jobs/n1.json").exists(), "and its write-up");
        assert!(phone.file("recordings/n2.wav").exists() && phone.file("images/theirs.jpg").exists() && phone.file("jobs/n2.progress").exists());
        assert_eq!(phone.notes.lock().get_note("n1").unwrap(), None);
        assert!(phone.notes.lock().get_note("n2").unwrap().is_some());
    }

    #[test]
    fn a_deleted_note_takes_its_films_and_their_posters_but_not_another_notes() {
        let phone = Phone::new();
        for name in ["video/mine.mp4", "video/shared.webm", "images/mine.jpg", "images/shared.jpg"] {
            std::fs::write(phone.file(name), b"bytes").unwrap();
        }
        {
            let mut library = phone.notes.lock();
            library.save_note("n1", "[![video 0:12](image/mine.jpg)](video/mine.mp4)\n[![video 0:03](image/shared.jpg)](video/shared.webm)\n", "editor").unwrap();
            library.save_note("n2", "[![video 0:03](image/shared.jpg)](video/shared.webm)\n", "editor").unwrap();
        }
        assert_eq!(phone.delete("n1"), Ok(true));
        assert!(!phone.file("video/mine.mp4").exists() && !phone.file("images/mine.jpg").exists(), "the film and its poster go with it");
        assert!(phone.file("video/shared.webm").exists() && phone.file("images/shared.jpg").exists(), "another note still names them");
    }

    #[test]
    fn deleting_a_note_already_gone_answers_false_and_still_clears_its_recording() {
        let phone = Phone::new();
        std::fs::write(phone.file("recordings/gone.wav"), b"bytes").unwrap();
        assert_eq!(phone.delete("gone"), Ok(false), "a stale list's second tap is not an error");
        assert!(!phone.file("recordings/gone.wav").exists(), "a recording no note can play is not left behind");
    }

    #[test]
    fn an_id_that_cannot_name_a_file_removes_none() {
        let phone = Phone::new();
        // Where `recordings/../escape.wav` would land if the id were joined as it came.
        std::fs::write(phone.file("escape.wav"), b"bytes").unwrap();
        // And where `jobs/../escape.progress` and its result would.
        std::fs::write(phone.file("escape.progress"), b"{}").unwrap();
        std::fs::write(phone.file("escape.json"), b"{}").unwrap();
        assert_eq!(phone.delete("../escape"), Ok(false));
        assert!(phone.file("escape.wav").exists(), "nothing outside the recordings folder is touched");
        assert!(phone.file("escape.progress").exists() && phone.file("escape.json").exists(), "nor outside the jobs folder");
    }

    #[test]
    fn with_nowhere_to_keep_files_a_delete_still_deletes_the_note() {
        let phone = Phone::new();
        std::fs::write(phone.file("images/mine.jpg"), b"bytes").unwrap();
        phone.notes.lock().save_note("n1", "![](image/mine.jpg)\n", "editor").unwrap();
        let nowhere = Kept { images: None, videos: None, recordings: None, jobs: None };
        assert_eq!(delete_with_files(&phone.notes, &nowhere, "n1"), Ok(true));
        assert!(phone.file("images/mine.jpg").exists(), "no directory given, nothing removed from one");
    }

    fn request(kind: &str, before: Option<(i64, &str)>) -> ApplyCommandRequest {
        ApplyCommandRequest {
            mutation_id: "m1".into(),
            note_id: "n1".into(),
            kind: kind.into(),
            before_revision: before.map(|(revision, _)| revision),
            before_body: before.map(|(_, body)| body.to_string()),
            after_body: "# To-Do\n\n- [ ] Wash dishes\n".into(),
            source: "capture".into(),
        }
    }

    #[test]
    fn a_command_is_checked_whole_before_anything_is_written() {
        let append = request("append", Some((3, "# To-Do\n"))).into_mutation().unwrap();
        assert_eq!((append.id.as_str(), append.note_id.as_str(), append.before_revision), ("m1", "n1", Some(3)));
        assert!(request("create", None).into_mutation().is_ok());
        let refused = |request: ApplyCommandRequest| request.into_mutation().unwrap_err();
        assert_eq!(refused(ApplyCommandRequest { note_id: "../n1".into(), ..request("create", None) }), "a command mutation needs plain bounded ids");
        assert_eq!(refused(ApplyCommandRequest { mutation_id: String::new(), ..request("create", None) }), "a command mutation needs plain bounded ids");
        assert_eq!(refused(ApplyCommandRequest { source: "model".into(), ..request("create", None) }), "a command mutation has an unsupported source");
        assert_eq!(refused(request("replace", Some((1, "x")))), "only append and create command mutations are supported");
        assert_eq!(refused(request("create", Some((1, "x")))), "a create command cannot replace an existing note");
        assert_eq!(refused(request("append", None)), "an append command needs the previewed note revision");
        // Half a preview is no preview, either way round.
        let half = |revision: Option<i64>, body: Option<&str>, kind: &str| ApplyCommandRequest {
            before_revision: revision,
            before_body: body.map(str::to_string),
            ..request(kind, None)
        };
        assert_eq!(refused(half(Some(1), None, "append")), "an append command needs the previewed note revision");
        assert_eq!(refused(half(None, Some("# To-Do\n"), "append")), "an append command needs the previewed note revision");
        assert_eq!(refused(half(Some(1), None, "create")), "a create command cannot replace an existing note");
        assert_eq!(refused(half(None, Some("# To-Do\n"), "create")), "a create command cannot replace an existing note");
    }

    #[test]
    fn the_page_cannot_send_a_command_with_more_than_the_request_names() {
        let sent = r##"{"mutationId":"m1","noteId":"n1","kind":"create","beforeRevision":null,"beforeBody":null,"afterBody":"# Hi","source":"capture"}"##;
        assert!(serde_json::from_str::<ApplyCommandRequest>(sent).is_ok());
        let smuggled = sent.replace("\"source\"", "\"grammar\":\"root\",\"source\"");
        assert!(serde_json::from_str::<ApplyCommandRequest>(&smuggled).is_err(), "deny_unknown_fields");
    }

    // From here on, this crate's own: the commands as the app calls them.

    fn core() -> (Core, TempDir) {
        let root = TempDir::new("dispatch");
        let core = Core::open(&root.join("data"), &root.join("cache")).unwrap();
        (core, root)
    }

    #[test]
    fn a_note_is_made_read_changed_and_refused_at_a_stale_revision() {
        let (core, root) = core();
        let made = core.call("create_note", json!({"id": "n1", "body": "# Plan\n\nFirst.\n", "source": "editor"})).unwrap();
        assert_eq!((made["id"].as_str(), made["revision"].as_i64(), made["path"].as_str()), (Some("n1"), Some(1), Some("Inbox/Plan.md")));
        assert!(root.join("data/Library/Inbox/Plan.md").is_file() && root.join("data/Library/.glyph/index.sqlite").is_file());
        assert_eq!(core.call("create_note", json!({"id": "n1", "body": "again", "source": "editor"})), Err("the note id already exists".into()));

        let changed = core.call("update_note", json!({"id": "n1", "body": "# Plan\n\nSecond.\n", "expectedRevision": 1})).unwrap();
        assert_eq!(changed["revision"].as_i64(), Some(2));
        assert_eq!(core.call("update_note", json!({"id": "n1", "body": "late", "expectedRevision": 1})), Err("the note was deleted or changed".into()));
        assert_eq!(core.call("get_note", json!({"id": "n1"})).unwrap()["body"], "# Plan\n\nSecond.\n");
        assert_eq!(core.call("get_note", json!({"id": "nobody"})).unwrap(), Value::Null);
        assert_eq!(core.call("list_notes", json!({})).unwrap().as_array().map(Vec::len), Some(1));

        assert_eq!(core.call("set_note_starred", json!({"id": "n1", "starred": true})).unwrap()["starred"], true);
        assert!(core.call("set_note_archived", json!({"id": "n1", "archived": true})).unwrap()["archivedAt"].is_i64());
        assert_eq!(core.call("versions_write", json!({"id": "n1", "text": "{}"})).unwrap(), true);
        assert_eq!(core.call("versions_read", json!({"id": "n1"})).unwrap(), "{}");
        assert!(root.join("data/Library/Inbox/Plan.versions").is_file());

        assert_eq!(core.call("delete_note", json!({"id": "n1"})).unwrap(), true);
        assert_eq!(core.call("delete_note", json!({"id": "n1"})).unwrap(), false);
        assert!(!root.join("data/Library/Inbox/Plan.md").exists() && !root.join("data/Library/Inbox/Plan.versions").exists());
    }

    #[test]
    fn a_recording_and_a_synced_note_are_checked_as_the_tauri_commands_check_them() {
        let (core, _root) = core();
        core.call("create_note", json!({"id": "n1", "body": "Spoken.\n", "source": "capture"})).unwrap();
        let phrases = json!([{"text": "Spoken.", "startMs": 0, "endMs": 900}]);
        let kept = core.call("set_note_recording", json!({"id": "n1", "recordingMs": 900, "segments": phrases})).unwrap();
        assert_eq!(kept["recordingMs"].as_i64(), Some(900));
        assert_eq!(core.call("get_note", json!({"id": "n1"})).unwrap()["segments"], phrases);
        assert_eq!(core.call("set_note_recording", json!({"id": "n1", "recordingMs": -1})), Err("a recording of -1 ms is not a length".into()));
        // `recordingMs` left out is `null`: the recording is forgotten.
        assert_eq!(core.call("set_note_recording", json!({"id": "n1"})).unwrap()["recordingMs"], Value::Null);

        let mut theirs = core.call("get_note", json!({"id": "n1"})).unwrap();
        theirs["segments"] = json!([{"text": "x", "startMs": 9, "endMs": 1}]);
        assert_eq!(core.call("store_apply", json!({"note": theirs})), Err("segment 0 ends before it starts".into()));
    }

    #[test]
    fn a_command_is_applied_offered_again_and_undone() {
        let (core, _root) = core();
        let request = json!({"mutationId": "m1", "noteId": "n1", "kind": "create", "beforeRevision": null, "beforeBody": null, "afterBody": "# To-Do\n", "source": "capture"});
        let applied = core.call("apply_command_mutation", json!({"request": request})).unwrap();
        assert_eq!((applied["status"].as_str(), applied["mutationId"].as_str()), (Some("applied"), Some("m1")));
        assert_eq!(core.call("latest_command_mutation", Value::Null).unwrap()["mutationId"], "m1");
        assert_eq!(core.call("undo_command_mutation", json!({"mutationId": "m1"})).unwrap()["status"], "undone");
        assert_eq!(core.call("undo_command_mutation", json!({"mutationId": "nobody"})).unwrap()["status"], "not-found");
        let bad = json!({"request": {"mutationId": "m2", "noteId": "../n", "kind": "create", "afterBody": "x", "source": "capture"}});
        assert_eq!(core.call("apply_command_mutation", bad), Err("a command mutation needs plain bounded ids".into()));
    }

    #[test]
    fn the_library_says_where_it_is() {
        let (core, root) = core();
        core.call("create_note", json!({"id": "n1", "body": "One.\n", "source": "editor"})).unwrap();
        let status = core.call("library_root", json!({})).unwrap();
        assert_eq!(status, json!({"kind": "app", "path": null, "name": null, "reachable": true, "notes": 1, "own": root.join("data/Library").display().to_string()}));
        // A folder chosen on a phone cannot be opened here (saf.rs), so the app's own is, and the page is told.
        Root::Tree { uri: "content://x/tree/y".into(), name: "Notes".into() }.write(&root.join("data")).unwrap();
        let away = Core::open(&root.join("data"), &root.join("cache")).unwrap();
        let status = away.call("library_root", json!({})).unwrap();
        assert_eq!((status["kind"].as_str(), status["name"].as_str(), status["reachable"].as_bool()), (Some("tree"), Some("Notes"), Some(false)));
    }

    #[test]
    fn a_reset_empties_the_phone_and_the_library_carries_on() {
        let (core, root) = core();
        core.call("create_note", json!({"id": "n1", "body": "# Kept until now\n", "source": "editor"})).unwrap();
        for file in ["data/recordings/n1.wav", "data/images/a.jpg", "data/video/f.mp4", "data/jobs/n1.progress", "cache/picked/p.mp4", "cache/other", "data/models/m.bin", "data/notion.json"] {
            std::fs::create_dir_all(root.join(file).parent().unwrap()).unwrap();
            std::fs::write(root.join(file), b"bytes").unwrap();
        }
        assert!(core.call("reset_local_data", json!({})).unwrap_err().starts_with("invalid args for command `reset_local_data`: missing field `models`"));
        assert_eq!(core.call("reset_local_data", json!({"models": false})), Ok(Value::Null));
        assert_eq!(core.call("list_notes", json!({})).unwrap(), json!([]));
        for gone in ["data/recordings", "data/images", "data/video", "data/jobs", "cache/picked", "data/notion.json", "data/Library/Inbox/Kept until now.md"] {
            assert!(!root.join(gone).exists(), "{gone} goes");
        }
        assert!(root.join("cache/other").exists() && root.join("data/models/m.bin").exists(), "the rest of the cache and the models stay");
        assert_eq!(core.call("reset_local_data", json!({"models": true})), Ok(Value::Null));
        assert!(!root.join("data/models").exists());
        core.call("create_note", json!({"id": "n2", "body": "After.\n", "source": "editor"})).unwrap();
        assert_eq!(core.call("list_notes", json!({})).unwrap().as_array().map(Vec::len), Some(1));
    }

    #[test]
    fn what_cannot_be_answered_is_a_sentence() {
        let (core, _root) = core();
        assert_eq!(core.call("open_the_pod_bay_doors", json!({})), Err("Ghost.md's core has no command named open_the_pod_bay_doors.".into()));
        let missing = core.call("get_note", json!({})).unwrap_err();
        assert!(missing.starts_with("invalid args for command `get_note`: missing field `id`"), "{missing}");
        let wrong = core.call("update_note", json!({"id": "n1", "body": "x", "expectedRevision": "one"})).unwrap_err();
        assert!(wrong.starts_with("invalid args for command `update_note`:"), "{wrong}");
    }

    #[test]
    fn a_panic_with_the_lock_held_leaves_the_library_usable() {
        let (core, _root) = core();
        core.call("create_note", json!({"id": "n1", "body": "Kept.\n", "source": "editor"})).unwrap();
        let died = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| core.call("test_panic", json!({}))));
        assert!(died.is_err() && core.notes.0.is_poisoned());
        assert_eq!(core.call("get_note", json!({"id": "n1"})).unwrap()["body"], "Kept.\n");
    }

    /// The only test that touches the process's one core: the others make their own.
    #[test]
    fn init_opens_once_and_agrees_with_itself() {
        let root = TempDir::new("init");
        let (data, cache) = (root.join("data").display().to_string(), root.join("cache").display().to_string());
        assert!(invoke("new_id", Value::Null).unwrap().as_str().is_some_and(|id| id.len() == 36 && crate::fsx::plain_id(id)));
        assert_eq!(invoke("list_notes", Value::Null), Err("Ghost.md's core is not open yet, so it cannot answer list_notes.".into()));
        assert!(invoke("init", json!({"dataDir": data})).unwrap_err().starts_with("invalid args for command `init`: missing field `cacheDir`"));
        assert_eq!(invoke("init", json!({"dataDir": data, "cacheDir": cache})), Ok(Value::Null));
        assert_eq!(invoke("init", json!({"dataDir": data, "cacheDir": cache})), Ok(Value::Null));
        let other = invoke("init", json!({"dataDir": format!("{data}-2"), "cacheDir": cache})).unwrap_err();
        assert!(other.starts_with("Ghost.md's core is already open on "), "{other}");
        assert!(!std::path::Path::new(&format!("{data}-2")).exists(), "a refused init makes nothing");
        assert_eq!(invoke("list_notes", Value::Null), Ok(json!([])));
        assert!(root.join("data/Library/.glyph/library.json").is_file());
        // Closed before its folder goes.
        *crate::lock::lock(&CORE) = None;
    }
}
