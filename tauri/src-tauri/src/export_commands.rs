//! The export's doors (export.rs; docs/DESIGN.md §167). Native generation 22.
//!
//! - **The Mac** (`export_save`): the system's save panel, where a USB drive is
//!   one of the places on its side, and the archive written straight to the
//!   file chosen there. A panel closed without a choice answers `null`.
//! - **Android** (`export_fd`): the activity opens the system's picker to make
//!   the file (MainActivity `GlyphHost.chooseExport`, ACTION_CREATE_DOCUMENT;
//!   a USB drive plugged in is one of its places) and hands the page the
//!   descriptor it opened on it, which the page passes here. Nothing is built
//!   in the phone's own storage first, so a library with gigabytes of films
//!   needs no room for a second copy of itself.
//! - `export_cancel` stops whichever is running, between blocks.
//!
//! Progress is the `export://progress` event (export.rs `Progress`), a few
//! times a second. One export at a time: a second while one runs is refused.

use std::sync::atomic::{AtomicBool, Ordering};

use serde::Deserialize;
use tauri::{AppHandle, Emitter, Manager, State};

use crate::export::{self, Exported, Extra, Progress, Source};

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

pub fn install(app: &tauri::App) {
    app.manage(ExportState::default());
}

/// The folders the archive carries: the library where it is (the app's own folder, or the one the person chose,
/// library_root.rs), and the media under `<app_data_dir>`. A folder chosen on Android has no path to walk, so its
/// notes come as text instead (`library_texts`) and only its `.glyph/`, kept in the app's storage, is walked.
#[cfg_attr(target_os = "ios", allow(dead_code))]
fn sources(app: &AppHandle) -> Result<Vec<Source>, String> {
    let data = crate::paths::data_dir(app)?;
    let store = app.state::<crate::commands::NotesStore>();
    let library = {
        let library = store.lock();
        match library.folder() {
            Some(folder) => Source { dir: folder, name: "Library" },
            None => Source { dir: library.glyph_dir(), name: "Library/.glyph" },
        }
    };
    Ok(vec![
        library,
        Source { dir: data.join(crate::paths::IMAGES), name: "images" },
        Source { dir: data.join(crate::paths::VIDEO), name: "video" },
        Source { dir: data.join(crate::paths::RECORDINGS), name: "recordings" },
    ])
}

/// A library with no folder to walk (one chosen on Android): every note and versions file, read as text, under
/// `Library/` in the archive as they are in the folder. Nothing for a library with a folder, which `sources` walks.
#[cfg_attr(target_os = "ios", allow(dead_code))]
fn library_texts(app: &AppHandle) -> Result<Vec<Extra>, String> {
    let store = app.state::<crate::commands::NotesStore>();
    let library = store.lock();
    if library.folder().is_some() {
        return Ok(Vec::new());
    }
    let texts = library.texts().map_err(|e| format!("The notes could not be read: {e}"))?;
    Ok(texts.into_iter().map(|(path, text)| Extra { name: format!("Library/{path}"), bytes: text.into_bytes() }).collect())
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

/// Writes the whole archive into `out`, telling the page how far it has got.
#[cfg_attr(target_os = "ios", allow(dead_code))]
fn write_into<W: std::io::Write>(app: &AppHandle, state: &ExportState, request: &ExportRequest, out: W) -> Result<Exported, String> {
    if !export::valid_name(&request.name) {
        return Err(format!("not an archive name: {}", request.name));
    }
    let mut extras = page_files(request)?;
    extras.extend(library_texts(app)?);
    let entries = export::entries(&sources(app)?).map_err(|e| format!("The notes could not be listed: {e}"))?;
    let manifest = serde_json::json!({
        "app": "Ghost.md",
        "exported": request.exported_at,
        "binary": env!("CARGO_PKG_VERSION"),
        "page": request.page,
    });
    let emitter = app.clone();
    export::write(out, &request.name, &entries, &extras, &manifest, request.offset_minutes, &state.cancel, move |progress: Progress| {
        let _ = emitter.emit("export://progress", progress);
    })
}

/// The Mac: the save panel, then the archive written where it was told. `null` when the panel was closed.
#[tauri::command(async)]
pub fn export_save(app: AppHandle, state: State<'_, ExportState>, request: ExportRequest) -> Result<Option<Exported>, String> {
    #[cfg(mobile)]
    {
        let _ = (app, state, request);
        Err("On a phone the export is saved through the phone's own picker.".into())
    }
    #[cfg(desktop)]
    {
        use tauri_plugin_dialog::DialogExt;
        let _running = Running::claim(&state)?;
        let Some(chosen) = app.dialog().file().set_title("Export everything").set_file_name(&request.name).add_filter("Zip archive", &["zip"]).blocking_save_file() else {
            return Ok(None);
        };
        let path = chosen.into_path().map_err(|e| e.to_string())?;
        let file = std::fs::File::create(&path).map_err(|e| export::said(&e))?;
        let written = write_into(&app, &state, &request, std::io::BufWriter::with_capacity(1 << 20, file));
        if written.is_err() {
            // Half an archive is no archive: it goes, so the drive holds only what opens.
            let _ = std::fs::remove_file(&path);
        }
        written.map(Some)
    }
}

/// Android: the archive written into the document the activity's picker made, by its descriptor. The descriptor is
/// taken only when it is a new, empty file outside the app's own storage: a number the page passed by mistake, which
/// named the index or a recording, is refused and left open, never written over or closed.
#[tauri::command(async)]
pub fn export_fd(app: AppHandle, state: State<'_, ExportState>, request: ExportRequest, fd: i32) -> Result<Exported, String> {
    #[cfg(not(target_os = "android"))]
    {
        let _ = (app, state, request, fd);
        Err("Only the Android app exports through its picker.".into())
    }
    #[cfg(target_os = "android")]
    {
        let _running = Running::claim(&state)?;
        let file = adopt(&app, fd)?;
        write_into(&app, &state, &request, std::io::BufWriter::with_capacity(1 << 20, file))
    }
}

/// The picker's descriptor as a file this process owns (export.rs `adopt_descriptor`), never one inside the app's own
/// storage.
#[cfg(target_os = "android")]
fn adopt(app: &AppHandle, fd: i32) -> Result<std::fs::File, String> {
    export::adopt_descriptor(fd, &[crate::paths::data_dir(app)?, crate::paths::cache_dir(app)?])
}

/// Stops the export under way, if there is one; it answers "The export was stopped."
#[tauri::command]
pub fn export_cancel(state: State<'_, ExportState>) {
    state.cancel.store(true, Ordering::SeqCst);
}
