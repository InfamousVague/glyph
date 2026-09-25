//! The Tauri half of a model download, shared by the two seams that have
//! models: `capture_commands` (whisper's live and refine models) and
//! `ai_commands` (the formatting models).
//!
//! `whisper::model` owns the download itself - the mirrors, the resume, the
//! SHA-256 that decides what is accepted - and takes no Tauri types, so that
//! a process with no Tauri in it could drive it. What it cannot know is the
//! app around it: where models live on this device, which mirrors the newest
//! signed update manifest moved the app to (`ota::services`), how a download
//! reports progress to the page, and that two taps on "download" must be one
//! download. Those were written out three times, once per download command,
//! and live here once.
//!
//! The progress event keeps the payload each seam has always sent:
//! `{ receivedBytes, totalBytes }` for whisper's models, and the same with the
//! model's `id` first for the formatting models, whose page tracks several.

use std::path::PathBuf;

use tauri::{AppHandle, Runtime};

use crate::whisper::model::{self, ModelSpec, ModelStatus};

#[cfg(not(target_os = "ios"))]
use std::path::Path;

/// Where models live on this device, or `None` where none can: iOS builds no
/// engine to run one (see `unsupported`), and a platform with no data
/// directory has nowhere to keep one. NOT a relative path in that case, which
/// would answer for whatever file happens to sit in the process's working
/// directory.
pub fn models_here<R: Runtime>(app: &AppHandle<R>) -> Option<PathBuf> {
    if cfg!(target_os = "ios") {
        None
    } else {
        crate::paths::models_dir(app).ok()
    }
}

/// Whether `spec` is on this device: its status in the models directory, or
/// absent where there is none ([`models_here`]).
pub fn status_here<R: Runtime>(app: &AppHandle<R>, spec: &ModelSpec) -> ModelStatus {
    match models_here(app) {
        Some(dir) => model::status(&dir, spec),
        None => ModelStatus::absent(spec),
    }
}

/// The progress event's payload, as the page reads it.
#[cfg(not(target_os = "ios"))]
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Progress {
    #[serde(skip_serializing_if = "Option::is_none")]
    id: Option<String>,
    received_bytes: u64,
    total_bytes: u64,
}

/// Downloads `spec` into `dir` unless it is already there (`model::fetch`),
/// emitting `event` with [`Progress`] as the bytes arrive, and answers with
/// its status.
///
/// `one_at_a_time` is held for the whole download, so that a second tap waits
/// for the first rather than writing the same `.part` beside it. `mirrors`
/// turns the mirrors a signed update manifest has moved the app to into the
/// list to try - the moved ones first, the compiled ones after
/// (`model::mirrors`) - and is asked only once the gate is held, so a download
/// that waited uses the newest list. `id` rides on every event when the page
/// needs to know which model it is hearing about.
#[cfg(not(target_os = "ios"))]
pub async fn fetch_reporting(
    app: &AppHandle,
    dir: &Path,
    one_at_a_time: &tauri::async_runtime::Mutex<()>,
    spec: &ModelSpec,
    mirrors: impl FnOnce(&[String]) -> Vec<String>,
    event: &'static str,
    id: Option<&str>,
) -> Result<ModelStatus, String> {
    use tauri::Emitter;
    let _one_download = one_at_a_time.lock().await;
    let emitter = app.clone();
    let mirrors = mirrors(&crate::ota::services(app).model_mirrors);
    let id = id.map(str::to_string);
    model::fetch(dir, spec, &mirrors, move |received, total| {
        // A page not there to hear it (reloading, or closed) is not a failed download.
        let _ = emitter.emit(event, Progress { id: id.clone(), received_bytes: received, total_bytes: total });
    })
    .await
}

#[cfg(all(test, not(target_os = "ios")))]
mod tests {
    use super::*;

    #[test]
    fn the_progress_payload_is_the_one_each_seam_always_sent() {
        let whisper = Progress { id: None, received_bytes: 10, total_bytes: 60 };
        assert_eq!(serde_json::to_string(&whisper).unwrap(), r#"{"receivedBytes":10,"totalBytes":60}"#);
        let formatting = Progress { id: Some("qwen3.5-4b".into()), received_bytes: 10, total_bytes: 60 };
        assert_eq!(serde_json::to_string(&formatting).unwrap(), r#"{"id":"qwen3.5-4b","receivedBytes":10,"totalBytes":60}"#);
    }
}
