//! The backup's doors (backup.rs; docs/DESIGN.md §204 and §213 of ../glyph): `../glyph/src-tauri/src/backup_commands.rs`,
//! whose commands take Tauri's `AppHandle` and `State` and so cannot be included. What a request is, the one
//! backup that may run and how a failure is said are that file's own lines between the marks; `kept::tests`
//! holds them to the original. The backup itself, backup.rs, is included whole (lib.rs).
//!
//! The commands, each as its `#[tauri::command]` there, taking the JSON the page sent:
//!
//! - `backup_last {tree}` -> `{backedUpAt, notes}` or `null`: the last backup a drive holds, by its tree.
//! - `backup_files {tree}` -> `[{path, size}]`: every file the drive's Ghost.md folder holds from the last
//!   backup, for Settings' tree.
//! - `backup_run {request: {tree, backedUpAt, readme}}` (a job, work.rs) -> `{notes, files, written, unchanged,
//!   removed, bytes}`: every note and versions file in the library, and the pictures, films and recordings, onto
//!   the drive, with `backup://progress` (`{done, total, files, of}`) a few times a second. One at a time.
//! - `backup_cancel` -> `null`: stops it between files; its job then ends with "The backup was stopped."
//!
//! What differs:
//!
//! - **`backup_run` is a job.** The Tauri command was `async`, on a thread of Tauri's; here a command that
//!   wrote a drive inside `ghost_invoke` would hold every save behind it, so it answers `{id}` at once and ends
//!   with `job://end`. The one backup is claimed before the id is answered: a second is refused at once, in the
//!   original's words. Its progress event is the web's, with no id in it, there being one backup.
//! - **The state is this process's** ([`STATE`]), where Tauri managed one.
//! - **No `backup_drives` and no `backup_eject` here.** The Mac's are Swift's (macos/Runner/FilesChannel.swift):
//!   the app is sandboxed, where the Tauri app is not, so `diskutil` is not its to run and a drive is written only
//!   once the person has granted it in a panel. A `drive` is taken on the Mac alone ([`mac_drive`]): a mount of
//!   its own under `/Volumes`, as the original's `listed` asks, written as a folder. Windows' are its target's.
//!   Android's drives are the activity's (android/…/glyph/files/BackupDrives.kt), and a backup goes by its `tree`.
//! - **With the test hooks** (the Mac's library for Dart's tests, and `cargo test`) a request may name a `folder`
//!   instead: a directory standing in for a drive's root, written as the Mac's drives are (`backup::FolderTarget`).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use serde::Deserialize;
use serde_json::Value;

use crate::backup::{self, Media, Progress, Target};
use crate::dispatch::{read, Core};

// copied:begin
#[derive(Default)]
pub struct BackupState {
    running: AtomicBool,
    cancel: AtomicBool,
}

/// Where the page asks a backup to go: a Mac drive's path or an Android drive's tree, and what it writes there.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRequest {
    #[serde(default)]
    pub drive: Option<String>,
    #[serde(default)]
    pub tree: Option<String>,
    pub backed_up_at: String,
    pub readme: String,
}

#[cfg(target_os = "android")]
fn android_tree(tree: &str) -> Result<(Box<dyn Target>, Option<u64>), String> {
    let target = crate::saf::TreeTarget::new(tree)?;
    Ok((Box::new(target), None))
}

#[cfg(not(target_os = "android"))]
fn android_tree(_tree: &str) -> Result<(Box<dyn Target>, Option<u64>), String> {
    Err("Only the Android app backs up through a drive's tree.".into())
}

/// Claims the one backup that may run; the guard lets it go however it ends.
struct Running<'a>(&'a BackupState);

impl<'a> Running<'a> {
    fn claim(state: &'a BackupState) -> Result<Self, String> {
        if state.running.swap(true, Ordering::SeqCst) {
            return Err("A backup is already under way.".into());
        }
        state.cancel.store(false, Ordering::SeqCst);
        Ok(Self(state))
    }
}

impl Drop for Running<'_> {
    fn drop(&mut self) {
        self.0.running.store(false, Ordering::SeqCst);
    }
}

/// The failure as the page says it: a sentence of the backup's own, or the system's words for what went wrong.
fn said(error: std::io::Error) -> String {
    match error.kind() {
        std::io::ErrorKind::StorageFull | std::io::ErrorKind::Interrupted => error.to_string(),
        std::io::ErrorKind::PermissionDenied => "Ghost.md can’t write to that drive. It may be locked or read-only.".into(),
        _ => format!("The backup could not be written: {error}"),
    }
}
// copied:end

/// The one backup's state, for the life of the process.
static STATE: BackupState = BackupState { running: AtomicBool::new(false), cancel: AtomicBool::new(false) };

/// A drive named without a backup's request: `backup_last` and `backup_files`.
#[derive(Deserialize)]
struct Named {
    #[serde(default)]
    drive: Option<String>,
    #[serde(default)]
    tree: Option<String>,
    /// A directory standing in for a drive's root: read only with the test hooks.
    #[serde(default)]
    folder: Option<String>,
}

#[derive(Deserialize)]
struct Run {
    request: BackupRequest,
    /// As [`Named::folder`].
    #[serde(default)]
    folder: Option<String>,
}

/// The drive a request names, as a `Target`, with its room where it is known.
fn target_of(drive: Option<&str>, tree: Option<&str>, folder: Option<&str>) -> Result<(Box<dyn Target>, Option<u64>), String> {
    #[cfg(any(test, feature = "test-hooks"))]
    if let Some(folder) = folder {
        return Ok((Box::new(backup::FolderTarget { root: folder.into() }), None));
    }
    let _ = folder;
    if let Some(drive) = drive {
        let root = mac_drive(std::path::Path::new(drive)).ok_or_else(|| "That drive isn’t plugged in any more.".to_string())?;
        let free = free_bytes(&root);
        return Ok((Box::new(backup::FolderTarget { root }), free));
    }
    if let Some(tree) = tree {
        return android_tree(tree);
    }
    Err("Choose a drive to back up to.".into())
}

/// A path the page names as a drive, on the Mac: a folder directly under `/Volumes` that is a mount of its own
/// (not the boot volume's link to `/`, nor a folder left there). Which mounts are removable is Swift's to say
/// (see the header); this only refuses every other place on the computer.
#[cfg(target_os = "macos")]
fn mac_drive(path: &std::path::Path) -> Option<std::path::PathBuf> {
    use std::os::unix::fs::MetadataExt;
    if path.parent() != Some(std::path::Path::new("/Volumes")) {
        return None;
    }
    let link = std::fs::symlink_metadata(path).ok()?;
    if link.file_type().is_symlink() || !link.is_dir() {
        return None;
    }
    // In the sandbox `/Volumes` itself may not be read; the boot volume is asked instead.
    let home = std::fs::metadata("/Volumes").or_else(|_| std::fs::metadata("/")).ok()?;
    (link.dev() != home.dev()).then(|| path.to_path_buf())
}

#[cfg(not(target_os = "macos"))]
fn mac_drive(_path: &std::path::Path) -> Option<std::path::PathBuf> {
    None
}

/// The room left on the drive, as the original's `free_bytes`.
#[cfg(unix)]
fn free_bytes(path: &std::path::Path) -> Option<u64> {
    use std::os::unix::ffi::OsStrExt;
    let c = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    // SAFETY: a NUL-terminated path and a zeroed struct of the right type.
    if unsafe { libc::statvfs(c.as_ptr(), &mut stat) } != 0 {
        return None;
    }
    #[allow(clippy::unnecessary_cast)]
    Some(stat.f_bavail as u64 * stat.f_frsize as u64)
}

#[cfg(not(unix))]
fn free_bytes(_path: &std::path::Path) -> Option<u64> {
    None
}

const COMMANDS: &[&str] = &["backup_last", "backup_files", "backup_run", "backup_cancel"];

/// Whether `command` is one of this file's.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

fn answer<T: serde::Serialize>(value: T) -> Result<Value, String> {
    serde_json::to_value(value).map_err(|e| format!("the answer could not be written: {e}"))
}

/// The backup itself, onto `target`: `backup_run`'s work, on its job's thread.
fn run_onto(core: &Core, state: &BackupState, target: &dyn Target, free: Option<u64>, request: &BackupRequest, progress: impl FnMut(Progress)) -> Result<backup::Backed, String> {
    let texts = {
        let library = core.notes().lock();
        library.texts().map_err(|e| format!("The notes could not be read: {e}"))?
    };
    let data = core.data_dir();
    let media = [
        Media { dir: data.join(crate::paths::IMAGES), name: "Pictures" },
        Media { dir: data.join(crate::paths::VIDEO), name: "Films" },
        Media { dir: data.join(crate::paths::RECORDINGS), name: "Recordings" },
    ];
    let items = backup::plan(texts, &media).map_err(|e| format!("The notes could not be listed: {e}"))?;
    backup::run(target, &items, &request.readme, &request.backed_up_at, free, &state.cancel, progress).map_err(said)
}

/// One of this file's commands, for the open core.
pub fn call(core: &Arc<Core>, command: &str, args: Value) -> Result<Value, String> {
    match command {
        // The last backup a drive holds, by its tree.
        "backup_last" => {
            let Named { drive, tree, folder } = read(command, args)?;
            let (target, _) = target_of(drive.as_deref(), tree.as_deref(), folder.as_deref())?;
            answer(backup::last(target.as_ref()))
        }
        // Every file the drive's Ghost.md folder holds from the last backup, for Settings' tree.
        "backup_files" => {
            let Named { drive, tree, folder } = read(command, args)?;
            let (target, _) = target_of(drive.as_deref(), tree.as_deref(), folder.as_deref())?;
            answer(backup::held(target.as_ref()).map_err(said)?)
        }
        // The backup: every note and versions file in the library, and the pictures, films and recordings, onto
        // the drive.
        "backup_run" => {
            let Run { request, folder } = read(command, args)?;
            let running = Running::claim(&STATE)?;
            let core = Arc::clone(core);
            let id = crate::work::start("backup", move |_job| {
                let _running = running;
                let (target, free) = target_of(request.drive.as_deref(), request.tree.as_deref(), folder.as_deref())?;
                let backed = run_onto(&core, &STATE, target.as_ref(), free, &request, |progress| crate::events::emit("backup://progress", &progress))?;
                answer(backed)
            })?;
            Ok(serde_json::json!({ "id": id }))
        }
        // Stops the backup under way, between files; it answers "The backup was stopped."
        "backup_cancel" => {
            STATE.cancel.store(true, Ordering::SeqCst);
            Ok(Value::Null)
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;
    use serde_json::json;
    use std::time::Duration;

    fn core() -> (Arc<Core>, TempDir) {
        let root = TempDir::new("backup-commands");
        let core = Arc::new(Core::open(&root.join("data"), &root.join("cache")).unwrap());
        (core, root)
    }

    fn request(at: &str) -> BackupRequest {
        BackupRequest { drive: None, tree: None, backed_up_at: at.into(), readme: "What this is.\n".into() }
    }

    #[test]
    fn a_backup_carries_the_notes_by_their_folders_and_the_media_and_the_next_writes_only_what_changed() {
        let (core, root) = core();
        core.call("create_note", json!({"id": "n1", "body": "# Plan\n\n![](image/a.jpg)\n", "source": "editor"})).unwrap();
        core.call("create_note", json!({"id": "n2", "body": "# Milk\n", "source": "editor"})).unwrap();
        core.call("versions_write", json!({"id": "n1", "text": "{}"})).unwrap();
        for file in ["images/a.jpg", "video/f.mp4", "recordings/n1.wav", "recordings/.orphans.json"] {
            std::fs::create_dir_all(root.join("data").join(file).parent().unwrap()).unwrap();
            std::fs::write(root.join("data").join(file), b"bytes").unwrap();
        }
        let drive = backup::FolderTarget { root: root.join("drive") };
        let state = BackupState::default();
        let mut told = Vec::new();
        let backed = run_onto(&core, &state, &drive, None, &request("2026-10-05T20:00:00.000Z"), |progress| told.push(progress)).unwrap();
        assert_eq!((backed.notes, backed.files, backed.written, backed.unchanged, backed.removed), (2, 6, 6, 0, 0));
        for file in ["Inbox/Plan.md", "Inbox/Plan.versions", "Inbox/Milk.md", "Attachments/Pictures/a.jpg", "Attachments/Films/f.mp4", "Attachments/Recordings/n1.wav", "README.txt", ".ghostmd-backup.json"] {
            assert!(root.join("drive/Ghost.md").join(file).is_file(), "{file} is on the drive");
        }
        assert!(!root.join("drive/Ghost.md/Attachments/Recordings/.orphans.json").exists(), "a dot file is the app's own");
        assert_eq!(std::fs::read_to_string(root.join("drive/Ghost.md/README.txt")).unwrap(), "What this is.\n");
        assert_eq!(told.first().map(|p| (p.done, p.files, p.of)), Some((0, 0, 6)));
        assert_eq!(told.last().map(|p| (p.done == p.total, p.files)), Some((true, 6)));

        // A note changed, one deleted: only the first is written, and the second is taken off.
        core.call("update_note", json!({"id": "n1", "body": "# Plan\n\nMore.\n", "expectedRevision": 1})).unwrap();
        core.call("delete_note", json!({"id": "n2"})).unwrap();
        let again = run_onto(&core, &state, &drive, None, &request("2026-10-06T08:00:00.000Z"), |_| {}).unwrap();
        assert_eq!((again.notes, again.written, again.removed), (1, 1, 1));
        assert!(!root.join("drive/Ghost.md/Inbox/Milk.md").exists());
        assert_eq!(backup::last(&drive), Some(backup::Last { backed_up_at: "2026-10-06T08:00:00.000Z".into(), notes: 1 }));

        // Stopped before it starts: the page's own sentence, and the last manifest still true.
        state.cancel.store(true, Ordering::SeqCst);
        core.call("update_note", json!({"id": "n1", "body": "# Plan\n\nMore still.\n", "expectedRevision": 2})).unwrap();
        assert_eq!(run_onto(&core, &state, &drive, None, &request("2026-10-07T08:00:00.000Z"), |_| {}), Err("The backup was stopped.".into()));
        assert_eq!(backup::last(&drive).map(|last| last.backed_up_at), Some("2026-10-06T08:00:00.000Z".into()));
    }

    #[test]
    fn a_drive_is_named_by_its_tree_and_only_a_phone_has_one() {
        let (core, _root) = core();
        assert!(has("backup_run") && has("backup_last") && has("backup_files") && has("backup_cancel") && !has("backup_drives"));
        assert_eq!(call(&core, "backup_last", json!({})), Err("Choose a drive to back up to.".into()));
        assert_eq!(call(&core, "backup_last", json!({"drive": "/Volumes/KINGSTON"})), Err("That drive isn’t plugged in any more.".into()));
        // No other place on the computer is a drive: not a folder, not the boot volume by its link.
        assert_eq!(call(&core, "backup_last", json!({"drive": "/tmp"})), Err("That drive isn’t plugged in any more.".into()));
        assert_eq!(call(&core, "backup_last", json!({"drive": "/Volumes/../Users"})), Err("That drive isn’t plugged in any more.".into()));
        assert_eq!(mac_drive(std::path::Path::new("/Volumes/Macintosh HD")), None);
        #[cfg(not(target_os = "android"))]
        assert_eq!(call(&core, "backup_files", json!({"tree": "content://x/tree/y"})), Err("Only the Android app backs up through a drive's tree.".into()));
        assert!(call(&core, "backup_run", json!({})).unwrap_err().starts_with("invalid args for command `backup_run`: missing field `request`"));
        assert_eq!(said(std::io::Error::new(std::io::ErrorKind::PermissionDenied, "EACCES")), "Ghost.md can’t write to that drive. It may be locked or read-only.");
        assert_eq!(said(std::io::Error::other("the stick came out")), "The backup could not be written: the stick came out");
    }

    /// The only test that claims the process's one backup: the command, start to end, as the app asks it.
    #[test]
    fn the_command_answers_an_id_reports_as_it_goes_and_ends_with_what_it_did() {
        let (core, root) = core();
        core.call("create_note", json!({"id": "n1", "body": "# Kept\n", "source": "editor"})).unwrap();
        let drive = root.join("drive").display().to_string();
        std::fs::create_dir_all(root.join("drive")).unwrap();
        assert_eq!(call(&core, "backup_last", json!({"folder": drive})), Ok(Value::Null));
        assert_eq!(call(&core, "backup_files", json!({"folder": drive})), Ok(json!([])));

        let started = call(&core, "backup_run", json!({"request": {"backedUpAt": "2026-10-05T20:00:00.000Z", "readme": "R\n"}, "folder": drive})).unwrap();
        let id = started["id"].as_str().unwrap().to_string();
        let ended = crate::events::tests::wait_for(Duration::from_secs(20), |event, payload| event == crate::work::END && payload["id"] == id.as_str()).expect("the backup ends");
        assert_eq!(ended["kind"], "backup");
        let bytes = std::fs::metadata(root.join("drive/Ghost.md/Inbox/Kept.md")).unwrap().len();
        assert_eq!(ended["ok"], json!({"notes": 1, "files": 1, "written": 1, "unchanged": 0, "removed": 0, "bytes": bytes}));
        assert!(!crate::events::tests::heard(|event, payload| event == "backup://progress" && payload["of"] == 1).is_empty(), "it says how far it has got");
        assert_eq!(call(&core, "backup_last", json!({"folder": drive})), Ok(json!({"backedUpAt": "2026-10-05T20:00:00.000Z", "notes": 1})));
        let files = call(&core, "backup_files", json!({"folder": drive})).unwrap();
        assert_eq!(files.as_array().unwrap().iter().map(|file| file["path"].as_str().unwrap()).collect::<Vec<_>>(), ["Inbox/Kept.md", "README.txt", ".ghostmd-backup.json"]);
        assert_eq!(call(&core, "backup_cancel", json!({})), Ok(Value::Null));
        // Let go when it ended: the next may start, and its start forgets the stop asked for meanwhile.
        let again = call(&core, "backup_run", json!({"request": {"backedUpAt": "2026-10-05T21:00:00.000Z", "readme": "R\n"}, "folder": drive})).unwrap();
        let id = again["id"].as_str().unwrap().to_string();
        let ended = crate::events::tests::wait_for(Duration::from_secs(20), |event, payload| event == crate::work::END && payload["id"] == id.as_str()).expect("the second ends");
        assert_eq!((ended["ok"]["written"].as_u64(), ended["ok"]["unchanged"].as_u64()), (Some(0), Some(1)));
    }
}
