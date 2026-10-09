//! The export's doors (export.rs; docs/DESIGN.md §167 of ../glyph): `../glyph/src-tauri/src/export_commands.rs`,
//! whose commands take Tauri's `AppHandle` and `State` and open the Mac's save panel, so it cannot be included.
//! What the page asks for, which of its files the archive carries and the one export that may run are that
//! file's own lines between the marks; `kept::tests` holds them to the original. The archive itself, export.rs,
//! is included whole (lib.rs).
//!
//! The commands, each as its `#[tauri::command]` there, taking the JSON the page sent:
//!
//! - `export_fd {request: {name, offsetMinutes, page, exportedAt, files: [{name, text}]}, fd}` (Android; a job,
//!   work.rs) -> `{name, notes, files, bytes, written}`: the archive written into the document the activity's
//!   picker made (android/…/glyph/files/ExportTarget.kt), by the descriptor it opened on it, with
//!   `export://progress` (`{done, total, files, of}`) a few times a second. The descriptor is taken only when it
//!   is a new, empty file outside the app's own storage (export.rs `adopt_descriptor`). One at a time.
//! - `export_cancel` -> `null`: stops it between blocks; its job then ends with "The export was stopped."
//!
//! What differs:
//!
//! - **`export_fd` is a job**, as the backup is and for its reason (kept/backup_commands.rs): it answers `{id}`
//!   at once and ends with `job://end`, the one export claimed before the id is answered. A refused descriptor
//!   is the job's `err`, and is left open, never closed, as the original leaves it.
//! - **The folders are named from the core's directories**, where the Tauri command asked its `AppHandle`.
//! - **The manifest's `binary`** is this crate's version, the core's, where it was the Tauri app's.
//! - **No `export_save`**: the Mac's save panel is Swift's (macos/Runner/FilesChannel.swift), which makes the file
//!   and hands over a descriptor it opened on it, so the Mac exports through `export_fd` exactly as Android does.
//! - **With the test hooks** `export_fd` takes a `path` in place of `fd`: a file made there and written as the
//!   Mac's panel's would be, half an archive removed.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use serde::Deserialize;
use serde_json::Value;

use crate::dispatch::{read, Core};
use crate::export::{self, Exported, Extra, Progress, Source};

// copied:begin
/// Whether an export is running, and its stop.
#[derive(Default)]
pub struct ExportState {
    running: AtomicBool,
    cancel: AtomicBool,
}

/// A file the page wrote for the archive, as text.
#[derive(Deserialize)]
pub struct PageFile {
    pub name: String,
    pub text: String,
}

/// What the page asks for: the archive's name, the minutes its clock is east of UTC (a zip's times are the wall
/// clock's), the page's build for the manifest, and its README and settings.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportRequest {
    pub name: String,
    pub offset_minutes: i32,
    pub page: String,
    pub exported_at: String,
    pub files: Vec<PageFile>,
}

/// The page's files, only by plain names at the archive's top: never a path that would land among the notes.
#[cfg_attr(target_os = "ios", allow(dead_code))]
fn page_files(request: &ExportRequest) -> Result<Vec<Extra>, String> {
    request
        .files
        .iter()
        .map(|file| {
            let plain = !file.name.is_empty() && !file.name.starts_with('.') && file.name.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_');
            if !plain || file.name == "manifest.json" {
                return Err(format!("not a file the export carries: {}", file.name));
            }
            Ok(Extra { name: file.name.clone(), bytes: file.text.clone().into_bytes() })
        })
        .collect()
}

/// Claims the one export that may run; the guard lets it go however the export ends.
#[cfg_attr(target_os = "ios", allow(dead_code))]
struct Running<'a>(&'a ExportState);

#[cfg_attr(target_os = "ios", allow(dead_code))]
impl<'a> Running<'a> {
    fn claim(state: &'a ExportState) -> Result<Self, String> {
        if state.running.swap(true, Ordering::SeqCst) {
            return Err("An export is already under way.".into());
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

// copied:end

/// The one export's state, for the life of the process.
static STATE: ExportState = ExportState { running: AtomicBool::new(false), cancel: AtomicBool::new(false) };

#[derive(Deserialize)]
struct ByDescriptor {
    request: ExportRequest,
    #[serde(default)]
    fd: Option<i32>,
    /// A file to make and write, standing in for the picker's: read only with the test hooks.
    #[serde(default)]
    path: Option<String>,
}

/// The folders the archive carries: the library where it is (the app's own folder, or the one the person chose,
/// library_root.rs), and the media under the data directory. A folder chosen on Android has no path to walk, so
/// its notes come as text instead (`library_texts`) and only its `.glyph/`, kept in the app's storage, is walked.
fn sources(core: &Core) -> Vec<Source> {
    let data = core.data_dir();
    let library = {
        let library = core.notes().lock();
        match library.folder() {
            Some(folder) => Source { dir: folder, name: "Library" },
            None => Source { dir: library.glyph_dir(), name: "Library/.glyph" },
        }
    };
    vec![
        library,
        Source { dir: data.join(crate::paths::IMAGES), name: "images" },
        Source { dir: data.join(crate::paths::VIDEO), name: "video" },
        Source { dir: data.join(crate::paths::RECORDINGS), name: "recordings" },
    ]
}

/// A library with no folder to walk (one chosen on Android): every note and versions file, read as text, under
/// `Library/` in the archive as they are in the folder. Nothing for a library with a folder, which `sources` walks.
fn library_texts(core: &Core) -> Result<Vec<Extra>, String> {
    let library = core.notes().lock();
    if library.folder().is_some() {
        return Ok(Vec::new());
    }
    let texts = library.texts().map_err(|e| format!("The notes could not be read: {e}"))?;
    Ok(texts.into_iter().map(|(path, text)| Extra { name: format!("Library/{path}"), bytes: text.into_bytes() }).collect())
}

/// Writes the whole archive into `out`, telling how far it has got.
fn write_into<W: std::io::Write>(core: &Core, state: &ExportState, request: &ExportRequest, out: W, tell: impl FnMut(Progress)) -> Result<Exported, String> {
    if !export::valid_name(&request.name) {
        return Err(format!("not an archive name: {}", request.name));
    }
    let mut extras = page_files(request)?;
    extras.extend(library_texts(core)?);
    let entries = export::entries(&sources(core)).map_err(|e| format!("The notes could not be listed: {e}"))?;
    let manifest = serde_json::json!({
        "app": "Ghost.md",
        "exported": request.exported_at,
        "binary": env!("CARGO_PKG_VERSION"),
        "page": request.page,
    });
    export::write(out, &request.name, &entries, &extras, &manifest, request.offset_minutes, &state.cancel, tell)
}

/// The file an `export_fd` writes: the picker's descriptor, adopted; or, with the test hooks, one made at `path`.
fn target(core: &Core, fd: Option<i32>, path: Option<&str>) -> Result<(std::fs::File, Option<std::path::PathBuf>), String> {
    #[cfg(any(test, feature = "test-hooks"))]
    if let Some(path) = path {
        let file = std::fs::File::create(path).map_err(|e| export::said(&e))?;
        return Ok((file, Some(path.into())));
    }
    let _ = path;
    let fd = fd.ok_or_else(|| "invalid args for command `export_fd`: missing field `fd`".to_string())?;
    #[cfg(not(any(target_os = "android", target_os = "macos")))]
    {
        let _ = (core, fd);
        Err("Only the Android app exports through its picker.".into())
    }
    #[cfg(any(target_os = "android", target_os = "macos"))]
    {
        let own = [core.data_dir().to_path_buf(), core.cache_dir().to_path_buf()];
        Ok((export::adopt_descriptor(fd, &own)?, None))
    }
}

const COMMANDS: &[&str] = &["export_fd", "export_cancel"];

/// Whether `command` is one of this file's.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

/// One of this file's commands, for the open core.
pub fn call(core: &Arc<Core>, command: &str, args: Value) -> Result<Value, String> {
    match command {
        // Android: the archive written into the document the activity's picker made, by its descriptor.
        "export_fd" => {
            let ByDescriptor { request, fd, path } = read(command, args)?;
            let running = Running::claim(&STATE)?;
            let core = Arc::clone(core);
            let id = crate::work::start("export", move |_job| {
                let _running = running;
                let (file, made) = target(&core, fd, path.as_deref())?;
                let written = write_into(&core, &STATE, &request, std::io::BufWriter::with_capacity(1 << 20, file), |progress| crate::events::emit("export://progress", &progress));
                if let (Err(_), Some(made)) = (&written, &made) {
                    // Half an archive is no archive: it goes, so the drive holds only what opens.
                    let _ = std::fs::remove_file(made);
                }
                serde_json::to_value(written?).map_err(|e| format!("the answer could not be written: {e}"))
            })?;
            Ok(serde_json::json!({ "id": id }))
        }
        // Stops the export under way, if there is one; it answers "The export was stopped."
        "export_cancel" => {
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
    use std::io::Read;
    use std::time::Duration;

    fn core() -> (Arc<Core>, TempDir) {
        let root = TempDir::new("export-commands");
        let core = Arc::new(Core::open(&root.join("data"), &root.join("cache")).unwrap());
        (core, root)
    }

    fn request(name: &str) -> ExportRequest {
        serde_json::from_value(json!({
            "name": name,
            "offsetMinutes": 60,
            "page": "flutter",
            "exportedAt": "2026-10-01T20:42:05.000Z",
            "files": [{"name": "README.txt", "text": "What this is.\n"}, {"name": "settings.json", "text": "{}\n"}],
        }))
        .unwrap()
    }

    /// The archive's files by name, each with its bytes.
    fn opened(bytes: Vec<u8>) -> Vec<(String, Vec<u8>)> {
        let mut archive = zip::ZipArchive::new(std::io::Cursor::new(bytes)).expect("the archive opens");
        (0..archive.len())
            .map(|i| {
                let mut file = archive.by_index(i).unwrap();
                let mut bytes = Vec::new();
                file.read_to_end(&mut bytes).unwrap();
                (file.name().to_string(), bytes)
            })
            .collect()
    }

    fn phone(core: &Core, root: &TempDir) {
        core.call("create_note", json!({"id": "n1", "body": "# Milk\n\n![](image/a.jpg)\n", "source": "editor"})).unwrap();
        core.call("create_note", json!({"id": "n2", "body": "# Plan\n", "source": "editor"})).unwrap();
        for file in ["images/a.jpg", "video/f.mp4", "recordings/n1.wav", "models/m.gguf", "jobs/n1.progress"] {
            std::fs::create_dir_all(root.join("data").join(file).parent().unwrap()).unwrap();
            std::fs::write(root.join("data").join(file), b"bytes").unwrap();
        }
    }

    #[test]
    fn the_archive_carries_the_library_the_media_and_the_pages_files_and_nothing_else() {
        let (core, root) = core();
        phone(&core, &root);
        let state = ExportState::default();
        let mut out = Vec::new();
        let mut told = Vec::new();
        let exported = write_into(&core, &state, &request("ghostmarkdown_2026-10-01_21-42-05.zip"), &mut out, |progress| told.push(progress)).unwrap();
        assert_eq!((exported.name.as_str(), exported.notes, exported.written), ("ghostmarkdown_2026-10-01_21-42-05.zip", 2, out.len() as u64));
        assert_eq!(told.last().map(|p| (p.done == p.total, p.files == p.of)), Some((true, true)));
        let files = opened(out);
        let names: Vec<&str> = files.iter().map(|(name, _)| name.as_str()).collect();
        let at = |name: &str| format!("ghostmarkdown_2026-10-01_21-42-05/{name}");
        assert_eq!(&names[..3], [at("README.txt"), at("settings.json"), at("manifest.json")], "the page's files and the manifest come first");
        for carried in ["Library/Inbox/Milk.md", "Library/Inbox/Plan.md", "Library/.glyph/library.json", "images/a.jpg", "video/f.mp4", "recordings/n1.wav"] {
            assert!(names.contains(&at(carried).as_str()), "{carried} is carried: {names:?}");
        }
        assert!(!names.iter().any(|name| name.contains("index.sqlite") || name.contains("models") || name.contains("jobs")), "the index, the models and a write-up are left out: {names:?}");
        let manifest: Value = serde_json::from_slice(&files[2].1).unwrap();
        assert_eq!((manifest["app"].as_str(), manifest["exported"].as_str(), manifest["page"].as_str(), manifest["notes"].as_u64()), (Some("Ghost.md"), Some("2026-10-01T20:42:05.000Z"), Some("flutter"), Some(2)));
        assert_eq!(manifest["binary"], env!("CARGO_PKG_VERSION"));
        assert_eq!(files[0].1, b"What this is.\n");
    }

    #[test]
    fn a_name_or_a_file_the_export_does_not_carry_is_refused_before_anything_is_written() {
        let (core, _root) = core();
        let state = ExportState::default();
        let mut out = Vec::new();
        assert_eq!(write_into(&core, &state, &request("../notes.zip"), &mut out, |_| {}).unwrap_err(), "not an archive name: ../notes.zip");
        for name in ["manifest.json", "Library/Inbox/x.md", ".hidden", ""] {
            let mut asked = request("ghostmarkdown_x.zip");
            asked.files[0].name = name.into();
            assert_eq!(write_into(&core, &state, &asked, &mut out, |_| {}).unwrap_err(), format!("not a file the export carries: {name}"));
        }
        assert!(out.is_empty());
        // Stopped: the page's own sentence.
        state.cancel.store(true, Ordering::SeqCst);
        core.call("create_note", json!({"id": "n1", "body": "# Milk\n", "source": "editor"})).unwrap();
        assert_eq!(write_into(&core, &state, &request("ghostmarkdown_x.zip"), &mut out, |_| {}).unwrap_err(), export::CANCELLED);
    }

    /// The only test that claims the process's one export: the command, start to end, as the app asks it.
    #[test]
    fn the_command_answers_an_id_reports_as_it_goes_and_ends_with_what_it_wrote() {
        let (core, root) = core();
        phone(&core, &root);
        assert!(has("export_fd") && has("export_cancel") && !has("export_save"));
        let path = root.join("out.zip");
        let asked = |args: Value| {
            let started = call(&core, "export_fd", args).unwrap();
            let id = started["id"].as_str().unwrap().to_string();
            crate::events::tests::wait_for(Duration::from_secs(20), |event, payload| event == crate::work::END && payload["id"] == id.as_str()).expect("the export ends")
        };
        let request = json!({"name": "ghostmarkdown_2026-10-01_21-42-05.zip", "offsetMinutes": 0, "page": "flutter", "exportedAt": "2026-10-01T21:42:05.000Z", "files": []});
        let ended = asked(json!({"request": request, "path": path}));
        assert_eq!((ended["kind"].as_str(), ended["ok"]["notes"].as_u64(), ended["ok"]["name"].as_str()), (Some("export"), Some(2), Some("ghostmarkdown_2026-10-01_21-42-05.zip")));
        assert_eq!(ended["ok"]["written"].as_u64(), Some(std::fs::metadata(&path).unwrap().len()));
        assert!(!crate::events::tests::heard(|event, payload| event == "export://progress" && payload["of"] == ended["ok"]["files"]).is_empty(), "it says how far it has got");
        assert!(opened(std::fs::read(&path).unwrap()).iter().any(|(name, _)| name.ends_with("/Library/Inbox/Milk.md")));

        // A failure leaves no half an archive, and lets the next one start.
        let bad = root.join("bad.zip");
        let mut wrong = request.clone();
        wrong["name"] = json!("no");
        assert_eq!(asked(json!({"request": wrong, "path": bad}))["err"], "not an archive name: no");
        assert!(!bad.exists());
        // With neither a descriptor nor (off the phone) a picker, it says so.
        let none = asked(json!({"request": request}));
        assert_eq!(none["err"], "invalid args for command `export_fd`: missing field `fd`");
        #[cfg(not(any(target_os = "android", target_os = "macos")))]
        assert_eq!(asked(json!({"request": request, "fd": 3}))["err"], "Only the Android app exports through its picker.");
        // The Mac's panel hands over a descriptor as the phone's does: a new, empty file is written through it.
        #[cfg(target_os = "macos")]
        {
            use std::os::fd::IntoRawFd;
            let through = root.join("through.zip");
            let fd = std::fs::File::create(&through).unwrap().into_raw_fd();
            let ended = asked(json!({"request": request, "fd": fd}));
            assert_eq!(ended["ok"]["written"].as_u64(), Some(std::fs::metadata(&through).unwrap().len()), "{ended}");
            assert!(asked(json!({"request": request, "fd": 2}))["err"].is_string());
        }
        assert_eq!(call(&core, "export_cancel", json!({})), Ok(Value::Null));
    }
}
