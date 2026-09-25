//! The Tauri seam for the notes: the commands the page reaches them through,
//! and deliberately little else.
//!
//! `library/` owns the notes and has to stay free of `tauri::` types - note.rs
//! says why, and it is not a stylistic preference. This module is the adapter
//! that lets a webview reach them: nearly every command here takes the lock,
//! calls one library function, and turns a `LibraryError` into a `String`.
//! The three that do more say what: `apply_command_mutation` checks what the
//! page sent before any of it is written, `delete_note` takes a note's
//! pictures and recording with it, and `sync_put_file` keeps a file that
//! arrived by sync.
//!
//! `Result<T, String>` rather than `Result<T, LibraryError>` because Tauri
//! needs the error half to be `Serialize`, and a string is what arrives in
//! JavaScript regardless: `invoke()` rejects with whatever the error
//! serialised to. A page that has to destructure an error enum to decide which
//! toast to raise is a page carrying the library's shape around for no
//! benefit - and `LibraryError`'s `Display` already writes the sentence a
//! person should read.

use std::path::Path;
use std::sync::Mutex;

use tauri::Manager;

use crate::library::Library;
use crate::note::{CommandMutation, CommandMutationResult, CommandUndoResult, Note, PendingCommandUndo, RecordedSegment, Recording};
use crate::recordings::recording_file;

/// A command the person confirmed from its preview, as the page sends it.
#[derive(Debug, serde::Deserialize)]
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

/// Applies only the already-previewed deterministic Markdown. Inference never
/// reaches this command and cannot provide ids, revisions, or note bodies.
#[tauri::command]
pub fn apply_command_mutation(
    store: tauri::State<'_, NotesStore>,
    request: ApplyCommandRequest,
) -> std::result::Result<CommandMutationResult, String> {
    let change = request.into_mutation()?;
    store.lock().apply_command(&change).map_err(|e| e.to_string())
}

/// Undoes a command, only while the note is still exactly what it left.
#[tauri::command]
pub fn undo_command_mutation(
    store: tauri::State<'_, NotesStore>,
    mutation_id: String,
) -> std::result::Result<CommandUndoResult, String> {
    store.lock().undo_command(&mutation_id).map_err(|e| e.to_string())
}

/// The command from the last ten minutes that can still be undone, if any:
/// what the page offers again after the app was stopped mid-undo.
#[tauri::command]
pub fn latest_command_mutation(
    store: tauri::State<'_, NotesStore>,
) -> std::result::Result<Option<PendingCommandUndo>, String> {
    store.lock().latest_command_undo(10 * 60 * 1_000).map_err(|e| e.to_string())
}

/// Keeps the on-device model's formatted version of a note, or clears it with
/// `null`. `formattedFor` is the page's hash of the body it was made from and
/// `model` the page's id for the model that wrote it. Native generation 10.
#[tauri::command]
pub fn set_note_formatted(
    store: tauri::State<'_, NotesStore>,
    id: String,
    formatted: Option<String>,
    formatted_for: Option<i64>,
    model: Option<String>,
) -> std::result::Result<Option<Note>, String> {
    store
        .lock()
        .set_formatted(&id, formatted.as_deref(), formatted_for, model.as_deref())
        .map_err(|e| e.to_string())
}

/// The notes' library, opened in `setup` and held for the life of the process.
///
/// One `Library` rather than one per command: opening one walks the folder
/// against its index, and keeping it keeps the index's SQLite page cache warm
/// between one debounced save and the next, on a device where the editor saves
/// 400 ms after the last keystroke and the list re-reads on every resume. A
/// `Mutex` rather than anything cleverer because the index's connection is
/// `Send` and not `Sync`, and because the webview invokes from one place
/// anyway: it costs one uncontended lock per command.
pub struct NotesStore(pub Mutex<Library>);

impl NotesStore {
    /// The guard, recovered if some earlier command panicked while holding it.
    ///
    /// A poisoned `Mutex` means a previous call died partway. The library is
    /// not the casualty: a note's file is written whole or not at all, every
    /// index statement stands alone, and the index is only a cache that the
    /// next read checks against the files. So the real choice is between
    /// recovering the guard and refusing every note operation for the rest of
    /// the process's life because one of them once panicked - which is how an
    /// app goes from having a bug to being a brick. The recovery itself is
    /// `crate::lock`'s.
    pub(crate) fn lock(&self) -> std::sync::MutexGuard<'_, Library> {
        crate::lock::lock(&self.0)
    }
}

/// Opens the library - moving the old database's notes into it the first
/// time (`library::open_and_move_in`) - and hands it to Tauri's managed state.
/// Called once, from `setup`.
///
/// `app_data_dir()` is resolved here through `paths`: `Library::open_fs` takes
/// a path precisely so that this resolution - which needs an `AppHandle`, and
/// therefore a running Tauri - stays on this side of the seam.
///
/// The directory is created rather than assumed. On a first launch nothing has
/// written there yet.
///
/// An error here fails `setup`, which fails the launch. That is the honest
/// outcome and the alternative was considered: starting with no library, letting
/// every command answer with an error, and showing an empty list. A notes app
/// that opens on an empty list invites the person to type into it, and
/// silently dropping what they then write is worse than not starting - a crash
/// is at least a fact they can act on.
pub fn install(app: &tauri::App) -> std::result::Result<(), String> {
    let dir = crate::paths::data_dir(app)?;
    crate::fsx::make_dir(&dir)?;
    let library = crate::library::open_and_move_in(&dir.join(crate::paths::LIBRARY), &dir)?;
    app.manage(NotesStore(Mutex::new(library)));
    Ok(())
}

/// Opens the notes' folder where the computer shows folders: Finder on a Mac (Matt: "add a browse local files button
/// somewhere to open the folder"). The library's own `.glyph/` stays in it, hidden as dot folders are. On a phone the
/// page asks the activity instead (MainActivity `GlyphHost.browseFiles`, files/LibraryDocuments.kt), since no other
/// app can open this app's storage. Native generation 18.
#[tauri::command]
pub fn library_reveal(app: tauri::AppHandle) -> std::result::Result<(), String> {
    #[cfg(desktop)]
    {
        use tauri_plugin_opener::OpenerExt;
        let dir = crate::paths::library_dir(&app)?;
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        app.opener().open_path(dir.to_string_lossy(), None::<&str>).map_err(|e| e.to_string())
    }
    #[cfg(mobile)]
    {
        let _ = app;
        Err("On a phone the notes' folder opens in the Files app.".into())
    }
}

/// Every note, newest edit first. What the list screen draws.
#[tauri::command]
pub fn list_notes(store: tauri::State<'_, NotesStore>) -> std::result::Result<Vec<Note>, String> {
    store.lock().list_notes().map_err(|e| e.to_string())
}

/// One note, or `null` when nothing answers to that id - which the editor
/// treats as "it was deleted elsewhere", not as a failure.
#[tauri::command]
pub fn get_note(
    store: tauri::State<'_, NotesStore>,
    id: String,
) -> std::result::Result<Option<Note>, String> {
    store.lock().get_note(&id).map_err(|e| e.to_string())
}

/// Creates a note only while its id is unused.
///
/// The id comes from the page rather than being minted here, because the page
/// has to have one before the first save lands: a new note is routed to and
/// drawn as soon as it is tapped, and an id that only exists after a 400 ms
/// debounce is an id the editor spends its first keystrokes without.
///
#[tauri::command]
pub fn create_note(
    store: tauri::State<'_, NotesStore>,
    id: String,
    body: String,
    source: String,
) -> std::result::Result<Note, String> {
    store.lock().create_note(&id, &body, &source).map_err(|e| e.to_string())?
        .ok_or_else(|| "the note id already exists".to_string())
}

/// Updates exactly an existing revision. A deleted row is a conflict, never
/// an invitation to insert it again.
#[tauri::command]
pub fn update_note(
    store: tauri::State<'_, NotesStore>,
    id: String,
    body: String,
    expected_revision: i64,
) -> std::result::Result<Note, String> {
    store.lock().update_note(&id, &body, expected_revision).map_err(|e| e.to_string())?
        .ok_or_else(|| "the note was deleted or changed".to_string())
}

/// Removes a note, answering `true` when a row actually went and `false` when
/// it had already gone - and its kept recording with it.
///
/// The recording goes whether or not the row was still there: a file whose note
/// is gone is a recording nothing can play, and nothing else would ever remove
/// it. A file that cannot be removed does not fail the delete; the note is
/// gone, which is what was asked. The pictures the body refers to go the same
/// way, except one another note still shows.
#[tauri::command]
pub fn delete_note(
    app: tauri::AppHandle,
    store: tauri::State<'_, NotesStore>,
    id: String,
) -> std::result::Result<bool, String> {
    let images = crate::paths::images_dir(&app).ok();
    let recordings = crate::paths::recordings_dir(&app).ok();
    delete_with_files(&store, images.as_deref(), recordings.as_deref(), &id)
}

/// `delete_note`'s work, given where pictures and recordings are kept (or
/// `None` where the platform gave no directory, which leaves the files alone).
fn delete_with_files(notes: &NotesStore, images: Option<&Path>, recordings: Option<&Path>, id: &str) -> std::result::Result<bool, String> {
    let mut library = notes.lock();
    // The body is read before the row goes: it is the only list of the
    // pictures the note had. They go after it, so a failed delete never
    // leaves a note pointing at pictures that are gone, and one another note
    // also shows (a copied line) is kept. The lock is held for that check,
    // which reads the index the delete has just changed.
    let body = library.get_note(id).ok().flatten().map(|note| note.body);
    let removed = library.delete_note(id).map_err(|e| e.to_string())?;
    if let (Some(body), Some(images)) = (body, images) {
        crate::images::remove_unreferenced(images, &library, &body);
    }
    drop(library);
    if let Some(file) = recordings.and_then(|dir| recording_file(dir, id)) {
        let _ = std::fs::remove_file(file);
    }
    Ok(removed)
}

/// Keeps a spoken note's recording length and phrases (`recordingMs` with
/// `segments`), or forgets both with `recordingMs: null`. Answers with the note,
/// or `null` if it has gone. Not an edit: `updatedAt` does not move. Native
/// generation 6.
#[tauri::command]
pub fn set_note_recording(
    store: tauri::State<'_, NotesStore>,
    id: String,
    recording_ms: Option<i64>,
    segments: Option<Vec<RecordedSegment>>,
) -> std::result::Result<Option<Note>, String> {
    let recording = match recording_ms {
        Some(ms) => Some(Recording::new(ms, segments.unwrap_or_default())?),
        None => None,
    };
    store.lock().set_recording(&id, recording.as_ref()).map_err(|e| e.to_string())
}

/// Writes a note as another device has it, for sync (docs/SYNC.md): its own
/// times, pin, archive, folder, recording phrases and formatted version.
/// Answers with the note as it now is here. Native generation 16.
#[tauri::command]
pub fn store_apply(store: tauri::State<'_, NotesStore>, note: Note) -> std::result::Result<Note, String> {
    if let Some(segments) = &note.segments {
        Recording::new(note.recording_ms.unwrap_or(0), segments.clone())?;
    }
    store.lock().apply_note(&note).map_err(|e| e.to_string())
}

/// Keeps a file that arrived by sync (docs/SYNC.md): a note's recording under
/// the note's id (`kind` "recording", WAV bytes), or a picture under its own
/// name (`kind` "image"). Written whole or not at all. Native generation 16.
#[tauri::command]
pub fn sync_put_file(app: tauri::AppHandle, kind: String, name: String, base64: String) -> std::result::Result<(), String> {
    match kind.as_str() {
        "image" => {
            let images = crate::paths::images_dir(&app).map_err(|_| "There is no room to keep pictures.".to_string())?;
            crate::images::place(&images, &name, &base64)
        }
        "recording" => {
            let recordings = crate::paths::recordings_dir(&app).map_err(|_| "There is no room to keep recordings.".to_string())?;
            crate::recordings::place(&recordings, &name, &base64)
        }
        _ => Err(format!("Nothing is kept as {kind}.")),
    }
}

/// Stars or unstars a note from the list's swipe. Answers with the note, or
/// `null` if it has gone. Native generation 3.
#[tauri::command]
pub fn set_note_starred(
    store: tauri::State<'_, NotesStore>,
    id: String,
    starred: bool,
) -> std::result::Result<Option<Note>, String> {
    store.lock().set_starred(&id, starred).map_err(|e| e.to_string())
}

/// Archives a note, or brings it back. Answers with the note, or `null` if it
/// has gone. Native generation 3.
#[tauri::command]
pub fn set_note_archived(
    store: tauri::State<'_, NotesStore>,
    id: String,
    archived: bool,
) -> std::result::Result<Option<Note>, String> {
    store.lock().set_archived(&id, archived).map_err(|e| e.to_string())
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
            for dir in ["images", "recordings"] {
                std::fs::create_dir_all(root.join(dir)).unwrap();
            }
            Phone { notes, root }
        }

        fn file(&self, path: &str) -> PathBuf {
            self.root.join(path)
        }

        fn delete(&self, id: &str) -> Result<bool, String> {
            delete_with_files(&self.notes, Some(&self.file("images")), Some(&self.file("recordings")), id)
        }
    }

    #[test]
    fn a_deleted_note_takes_its_pictures_and_recording_but_not_another_notes_picture() {
        let phone = Phone::new();
        for name in ["images/mine.jpg", "images/shared.png", "images/theirs.jpg", "recordings/n1.wav", "recordings/n2.wav"] {
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
        assert!(phone.file("recordings/n2.wav").exists() && phone.file("images/theirs.jpg").exists());
        assert_eq!(phone.notes.lock().get_note("n1").unwrap(), None);
        assert!(phone.notes.lock().get_note("n2").unwrap().is_some());
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
        assert_eq!(phone.delete("../escape"), Ok(false));
        assert!(phone.file("escape.wav").exists(), "nothing outside the recordings folder is touched");
    }

    #[test]
    fn with_nowhere_to_keep_files_a_delete_still_deletes_the_note() {
        let phone = Phone::new();
        std::fs::write(phone.file("images/mine.jpg"), b"bytes").unwrap();
        phone.notes.lock().save_note("n1", "![](image/mine.jpg)\n", "editor").unwrap();
        assert_eq!(delete_with_files(&phone.notes, None, None, "n1"), Ok(true));
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
}
