//! Whisper's two models on this device: whether each is here, and its
//! download - the live model (`model::ACTIVE`) a capture transcribes with,
//! and the refine model (`model::REFINE`) that improves a saved recording.
//! Both go through `model_downloads`, the Tauri half every model download
//! shares.

use tauri::{AppHandle, State};

use super::CaptureState;
use crate::model_downloads;
use crate::whisper::model::{self, ModelStatus};

#[cfg(not(target_os = "ios"))]
use crate::paths;
#[cfg(target_os = "ios")]
use crate::unsupported::{on_ios, TRANSCRIPTION};

/// Whether the active model is on this device, where, and how big it is.
#[tauri::command]
pub fn capture_model_status(app: AppHandle) -> ModelStatus {
    // No data directory (or iOS) is a model that cannot be present: see
    // `model_downloads::models_here`.
    model_downloads::status_here(&app, &model::ACTIVE)
}

/// Downloads the active model into `<app_data_dir>/models/` if it is not there,
/// verifying its SHA-256, and answers with its status. Progress arrives as
/// `capture://model-progress`.
#[tauri::command]
pub async fn capture_fetch_model(
    app: AppHandle,
    state: State<'_, CaptureState>,
) -> Result<ModelStatus, String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (app, state));
    #[cfg(not(target_os = "ios"))]
    {
        let dir = paths::models_dir(&app)?;
        // Mirrors a signed update manifest has moved come first; the compiled
        // ones follow. See model::mirrors_with.
        model_downloads::fetch_reporting(
            &app,
            &dir,
            &state.fetching,
            &model::ACTIVE,
            model::mirrors_with,
            "capture://model-progress",
            None,
        )
        .await
    }
}

/// Whether the refine model (`model::REFINE`) is on this device.
#[tauri::command]
pub fn capture_refine_model_status(app: AppHandle) -> ModelStatus {
    model_downloads::status_here(&app, &model::REFINE)
}

/// Downloads the refine model, from the same mirrors as the live one, and
/// answers with its status. Progress arrives as
/// `capture://refine-model-progress { receivedBytes, totalBytes }`.
#[tauri::command]
pub async fn capture_fetch_refine_model(
    app: AppHandle,
    state: State<'_, CaptureState>,
) -> Result<ModelStatus, String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (app, state));
    #[cfg(not(target_os = "ios"))]
    {
        let dir = paths::models_dir(&app)?;
        model_downloads::fetch_reporting(
            &app,
            &dir,
            &state.fetching_refine,
            &model::REFINE,
            model::mirrors_with,
            "capture://refine-model-progress",
            None,
        )
        .await
    }
}

/// The model download against the real mirrors. Ignored by default because
/// they need the network and one of them downloads 60 MB; run them with
/// `cargo test capture_commands -- --ignored`. They live here rather than in
/// `whisper/model.rs` only because reqwest needs an async runtime, and the one
/// already in this crate is Tauri's.
#[cfg(all(test, not(target_os = "ios")))]
mod tests {
    use crate::whisper::model::{self, ModelSpec};

    fn temp_dir() -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("glyph-fetch-test-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    #[ignore]
    fn the_active_model_downloads_through_the_mirrors_and_verifies() {
        let dir = temp_dir();
        let mut reports = Vec::new();
        let status = tauri::async_runtime::block_on(model::fetch(
            &dir,
            &model::ACTIVE,
            &model::mirrors_with(&[]),
            |got, of| reports.push((got, of)),
        ))
        .unwrap();
        assert!(status.present);
        // At most one report per 1% (plus the final one), rising, and ending
        // on the whole file - the page draws receivedBytes / totalBytes.
        assert!(
            (10..=102).contains(&reports.len()),
            "{} progress reports",
            reports.len()
        );
        assert!(reports
            .windows(2)
            .all(|pair| pair[0].0 < pair[1].0 || pair[1].0 == model::ACTIVE.bytes));
        assert_eq!(
            reports.last(),
            Some(&(model::ACTIVE.bytes, model::ACTIVE.bytes))
        );
        assert!(!dir.join(format!("{}.part", model::ACTIVE.file)).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    #[ignore]
    fn bytes_with_the_wrong_hash_are_refused_by_every_mirror_and_leave_nothing_behind() {
        // A real 3,196-byte file that is certainly not the hash below.
        let spec = ModelSpec {
            file: "README.md",
            bytes: 3_196,
            sha256: "0000000000000000000000000000000000000000000000000000000000000000",
        };
        let dir = temp_dir();
        let error = tauri::async_runtime::block_on(model::fetch(
            &dir,
            &spec,
            &model::mirrors_with(&[]),
            |_, _| {},
        ))
        .unwrap_err();
        eprintln!("{error}");
        assert!(error.contains("does not match"), "{error}");
        assert_eq!(
            std::fs::read_dir(&dir).unwrap().count(),
            0,
            "a refused download left a file behind"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}
