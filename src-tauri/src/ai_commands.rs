//! The Tauri seam for formatting on the phone: five commands, two events, and
//! nothing the engine does not already do.
//!
//! `llm/` owns the model and stays free of `tauri::` types, like `whisper/`.
//! This module resolves the app's data directory, holds the engine and the
//! runs in progress in managed state, and turns progress into `app.emit`.
//! Which model, which prompt, how many tokens: every one of those is the
//! page's decision, sent with the request, so the prompt can be tuned over
//! the air without a new binary.
//!
//! THE CONTRACT WITH THE PAGE:
//!
//! - `ai_device() -> { totalRamBytes, availableRamBytes, cores, fastCores,
//!   chip, chipMaker, phone, phoneName, freeDiskBytes }`, facts for the page
//!   to judge which models fit (`llm/device.rs`).
//! - `ai_models() -> [{ id, file, bytes, present, path }]`, the catalogue with
//!   what is on this phone. Names and descriptions live on the page.
//! - `ai_fetch_model({ id }) -> ModelInfo`, emitting `ai://model-progress`
//!   `{ id, receivedBytes, totalBytes }`. One download at a time.
//! - `ai_delete_model({ id }) -> ModelInfo`: the file goes, and the engine
//!   drops it from memory if it was loaded.
//! - `ai_generate({ id, model, system, context?, prompt, maxTokens,
//!   temperature }) -> Output`, resolving when the run ends; while it runs,
//!   `ai://progress` carries `{ id, phase, partial, ... }` about every 120 ms
//!   with everything written so far, and last with phase `done`, `error` or
//!   `cancelled`. Runs queue: a second request waits for the first.
//! - `ai_cancel({ id }) -> bool`: the run stops within a chunk; its
//!   `ai_generate` then rejects with "cancelled".
//!
//! On iOS every command exists with the same signature and rejects, or answers
//! "not present": the model there will be Apple's, and a page written against
//! one surface needs no platform switch to load.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};

use crate::llm::model::{self, LlmSpec};
// A lock some earlier command panicked while holding is recovered, not
// obeyed; see `crate::lock`.
use crate::lock::lock;

#[cfg(not(target_os = "ios"))]
use crate::llm::engine::{Llm, Request};
#[cfg(not(target_os = "ios"))]
use std::sync::OnceLock;

#[cfg(target_os = "ios")]
const NOT_ON_IOS: &str = "Formatting on the phone is not available on iOS yet.";

/// What the page asks for.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GenerateRequest {
    pub id: String,
    pub model: String,
    pub system: String,
    #[serde(default)]
    pub context: Option<String>,
    pub prompt: String,
    pub max_tokens: u32,
    #[serde(default = "default_temperature")]
    pub temperature: f32,
    /// Let a model that can reason do so before it answers, and stream the
    /// reasoning with the answer (native generation 13). Absent means no:
    /// the empty thought goes in, as every formatting pass wants.
    #[serde(default)]
    pub think: bool,
    /// With `think`: the most tokens the thinking may run before it is closed
    /// for the model and the answer begins. 0 is no limit.
    #[serde(default)]
    pub think_budget: u32,
}

fn default_temperature() -> f32 {
    0.3
}

/// One model of the catalogue, with whether this phone has it.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub id: String,
    pub file: String,
    pub bytes: u64,
    pub present: bool,
    pub path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ModelProgress {
    id: String,
    received_bytes: u64,
    total_bytes: u64,
}

#[derive(Default)]
pub struct AiState {
    /// Started on the first generation, never before: a launch pays nothing
    /// for a feature it may not use.
    #[cfg(not(target_os = "ios"))]
    llm: OnceLock<Llm>,
    /// The cancel flag of every run in flight, by the page's id.
    runs: Mutex<HashMap<String, Arc<AtomicBool>>>,
    /// One download at a time: two would write the same `.part` at once.
    #[cfg(not(target_os = "ios"))]
    fetching: tauri::async_runtime::Mutex<()>,
}

impl AiState {
    #[cfg(not(target_os = "ios"))]
    fn llm(&self) -> &Llm {
        self.llm.get_or_init(Llm::start)
    }

    /// Raises every run's cancel flag.
    fn cancel_all(&self) {
        for flag in lock(&self.runs).values() {
            flag.store(true, Ordering::Relaxed);
        }
    }
}

/// Hands the state to Tauri. Called once, from `setup`. Touches nothing.
pub fn install(app: &tauri::App) {
    app.manage(AiState::default());
}

/// Cancels every run and stops the worker, waiting for it. Called on
/// `RunEvent::Exit`, for the reason `capture_commands::shutdown` gives: C++
/// with static state must not be mid-decode when the process's destructors
/// run.
pub fn shutdown(app: &AppHandle) {
    if let Some(state) = app.try_state::<AiState>() {
        state.cancel_all();
        #[cfg(not(target_os = "ios"))]
        if let Some(llm) = state.llm.get() {
            llm.shutdown();
        }
    }
}

fn info(dir: Option<&std::path::Path>, spec: &LlmSpec) -> ModelInfo {
    let status = dir.map(|d| crate::whisper::model::status(d, &spec.spec));
    ModelInfo {
        id: spec.id.to_string(),
        file: spec.spec.file.to_string(),
        bytes: spec.spec.bytes,
        present: status.as_ref().is_some_and(|s| s.present),
        path: status.map(|s| s.path).unwrap_or_default(),
    }
}

fn known(id: &str) -> Result<&'static LlmSpec, String> {
    model::find(id).ok_or_else(|| format!("Glyph does not know a model called {id}."))
}

/// What this phone has to run a model with: memory, cores, chip, free disk.
/// The page decides what fits.
#[tauri::command]
pub fn ai_device(app: AppHandle) -> crate::llm::device::Device {
    let dir = if cfg!(target_os = "ios") { None } else { crate::capture_commands::models_dir(&app).ok() };
    crate::llm::device::read(dir.as_deref())
}

/// The catalogue, with what is on this phone.
#[tauri::command]
pub fn ai_models(app: AppHandle) -> Vec<ModelInfo> {
    // No data directory (or iOS) is every model absent - and NOT a relative
    // path, which would answer for whatever sits in the working directory.
    let dir = if cfg!(target_os = "ios") { None } else { crate::capture_commands::models_dir(&app).ok() };
    model::CATALOGUE.iter().map(|spec| info(dir.as_deref(), spec)).collect()
}

/// Downloads a model into `<app_data_dir>/models/` if it is not there,
/// verifying its SHA-256. Progress arrives as `ai://model-progress`.
#[tauri::command]
pub async fn ai_fetch_model(app: AppHandle, state: State<'_, AiState>, id: String) -> Result<ModelInfo, String> {
    let spec = known(&id)?;
    #[cfg(target_os = "ios")]
    {
        let _ = (app, state, spec);
        Err(NOT_ON_IOS.to_string())
    }
    #[cfg(not(target_os = "ios"))]
    {
        use tauri::Emitter;
        let dir = crate::capture_commands::models_dir(&app)?;
        let _one_download = state.fetching.lock().await;
        let emitter = app.clone();
        let mirrors = model::mirrors_with(spec, &crate::ota::services(&app).model_mirrors);
        let name = spec.id.to_string();
        crate::whisper::model::fetch(&dir, &spec.spec, &mirrors, move |received, total| {
            let _ = emitter.emit(
                "ai://model-progress",
                ModelProgress {
                    id: name.clone(),
                    received_bytes: received,
                    total_bytes: total,
                },
            );
        })
        .await?;
        Ok(info(Some(&dir), spec))
    }
}

/// Removes a model's file (and a half-downloaded one), unloading it first if
/// the engine has it in memory. Answers with the model, now absent.
#[tauri::command]
pub async fn ai_delete_model(app: AppHandle, state: State<'_, AiState>, id: String) -> Result<ModelInfo, String> {
    let spec = known(&id)?;
    #[cfg(target_os = "ios")]
    {
        let _ = (app, state, spec);
        Err(NOT_ON_IOS.to_string())
    }
    #[cfg(not(target_os = "ios"))]
    {
        let dir = crate::capture_commands::models_dir(&app)?;
        // A run on this model ends, and the engine lets go of the file, before
        // it is removed. Unlinking a mapped file is safe on Android and macOS
        // either way; this is about giving the space back.
        state.cancel_all();
        if let Some(llm) = state.llm.get() {
            llm.unload();
        }
        let path = crate::whisper::model::path_in(&dir, &spec.spec);
        for candidate in [path.clone(), path.with_extension("gguf.part")] {
            match std::fs::remove_file(&candidate) {
                Ok(()) => {}
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => return Err(format!("cannot remove {}: {e}", candidate.display())),
            }
        }
        Ok(info(Some(&dir), spec))
    }
}

/// What formatting answers with: the engine's output, or on iOS, where there is no engine (`llm::engine` isn't built),
/// nothing, as the command only ever refuses there.
#[cfg(not(target_os = "ios"))]
type GenerateOutput = crate::llm::engine::Output;
#[cfg(target_os = "ios")]
type GenerateOutput = ();

/// Formats: runs the page's prompt over the note with the model it names,
/// streaming `ai://progress`, and answers with the whole output at the end.
#[tauri::command]
pub async fn ai_generate(
    app: AppHandle,
    state: State<'_, AiState>,
    request: GenerateRequest,
) -> Result<GenerateOutput, String> {
    let spec = known(&request.model)?;
    #[cfg(target_os = "ios")]
    {
        let _ = (app, state, spec);
        Err(NOT_ON_IOS.to_string())
    }
    #[cfg(not(target_os = "ios"))]
    {
        use tauri::Emitter;
        let dir = crate::capture_commands::models_dir(&app)?;
        let status = crate::whisper::model::status(&dir, &spec.spec);
        if !status.present {
            return Err(format!("The model {} is not on this phone yet.", spec.id));
        }
        let cancel = Arc::new(AtomicBool::new(false));
        lock(&state.runs).insert(request.id.clone(), Arc::clone(&cancel));
        let emitter = app.clone();
        let engine_request = Request {
            id: request.id.clone(),
            system: request.system,
            context: request.context,
            prompt: request.prompt,
            max_tokens: request.max_tokens,
            temperature: request.temperature,
            think: request.think,
            think_budget: request.think_budget,
        };
        let answer = state.llm().generate(std::path::Path::new(&status.path), engine_request, cancel, move |progress| {
            let _ = emitter.emit("ai://progress", progress);
        });
        // The reply comes on a std channel from the worker thread; waiting on
        // it belongs on the blocking pool, not the async runtime.
        let result = tauri::async_runtime::spawn_blocking(move || answer.recv())
            .await
            .map_err(|e| format!("the formatting run did not finish: {e}"))?
            .map_err(|_| "the formatting engine went away".to_string())?;
        lock(&state.runs).remove(&request.id);
        result.map_err(|failure| failure.to_string())
    }
}

/// Stops a run. True if there was one to stop.
#[tauri::command]
pub fn ai_cancel(state: State<'_, AiState>, id: String) -> bool {
    match lock(&state.runs).get(&id) {
        Some(flag) => {
            flag.store(true, Ordering::Relaxed);
            true
        }
        None => false,
    }
}

#[cfg(not(target_os = "ios"))]
impl Drop for AiState {
    fn drop(&mut self) {
        self.cancel_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_request_reads_from_the_pages_json_with_a_default_temperature() {
        let json = r#"{"id":"r1","model":"qwen3.5-4b","system":"Format.","prompt":"hi","maxTokens":200}"#;
        let request: GenerateRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.max_tokens, 200);
        assert_eq!(request.temperature, 0.3);
        assert_eq!(request.context, None);
        assert!(!request.think, "a formatting pass that says nothing about thinking gets none");
        let thinking: GenerateRequest = serde_json::from_str(r#"{"id":"r2","model":"qwen3.5-4b","system":"Review.","prompt":"hi","maxTokens":900,"think":true}"#).unwrap();
        assert!(thinking.think);
    }

    #[test]
    fn an_unknown_model_is_refused_by_name() {
        assert!(known("gpt-4").unwrap_err().contains("gpt-4"));
        assert_eq!(known(model::DEFAULT.id).unwrap().id, model::DEFAULT.id);
    }
}
