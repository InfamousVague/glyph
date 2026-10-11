//! The language model's commands and events (the `voice` feature): what `../glyph/src-tauri/src/ai_commands.rs`
//! is to the Tauri app, command for command, over the same engine (`llm/`, included as it is). Which model,
//! which prompt, how many tokens: every one of those is the app's decision, sent with the request.
//!
//! Everything runs on this device. Nothing here speaks to a network but a model's download (models.rs).
//!
//! THE COMMANDS ("job" as in capture.rs: `{id}` at once, the value is its `job://end`'s `ok`):
//!
//! - `ai_device` -> `{totalRamBytes, availableRamBytes, cores, fastCores, chip, chipMaker, phone, phoneName,
//!   freeDiskBytes}`, each null where it could not be read.
//! - `ai_models` -> `[{id, file, bytes, present, path}]`, the catalogue with what is on this device.
//! - `ai_fetch_model {id, mirrors?}` (job) -> the model's `{id, file, bytes, present, path}`, emitting
//!   `ai://model-progress {id, receivedBytes, totalBytes}`. One download at a time.
//! - `ai_delete_model {id}` -> the model, now absent: the file and a half-downloaded one go, every run is
//!   cancelled and the engine drops it from memory first.
//! - `ai_generate {request: {id, model, system, context?, prompt, maxTokens, temperature?, think?,
//!   thinkBudget?}}` (job) -> `{text, promptTokens, outputTokens, ms, cachedTokens, prefillMs, loadMs,
//!   tokensPerSecond, truncated, thinking}`; while it runs, `ai://progress {id, phase, promptTokens,
//!   promptTokensDone, outputTokens, tokensPerSecond, elapsedMs, partial, thinking, message?, hardware?}` about
//!   every 120 ms with everything written so far (`id` is the REQUEST's, not the job's), and last with phase
//!   `done`, `error` or `cancelled`. Runs queue. A cancelled run's job ends with the err "cancelled".
//! - `ai_cancel {id}` -> whether there was a run with that request id to stop.
//! - `ai_unload` -> `null`: the loaded model is dropped now rather than after five idle minutes.
//! - `ai_infer_command {request: {id, utterance, preferredModel}}` (job) -> `{status: "intent", intent, model}`
//!   or `{status: "unavailable", reason}`: one spoken command read under this binary's own prompt and grammar.
//!
//! What differs from ai_commands.rs:
//!
//! - **No Tauri state**: the runs in flight are this process's ([`RUNS`]).
//! - **`native_status`** -> `{nativeGeneration, nativeVersion}`: the two fields of the Tauri app's `ota_status`
//!   that the capture and the formatter gate on (`hasNativeGeneration`, `binaryVersion`). This app has no
//!   over-the-air bundle and so no `ota_status`. [`NATIVE_GENERATION`] says what the number promises here.
//! - **Nothing for Tauri's Exit** (`ai_commands::shutdown` stopped the worker so C++'s static destructors never
//!   met a decode): an Android process is not exited by its app, and the Mac target that will need it is stage 10's.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::dispatch::{read, Core};
use crate::llm::command::{self, CommandIntent};
use crate::llm::engine::Request;
use crate::llm::model::{self, LlmSpec};
use crate::lock::lock;

/// The Tauri app's native generation whose voice and AI commands are all here: recordings kept at stop (6),
/// thinking (13), the hardware in a progress report (14), meetings, the write-up and `ai_unload` (20), other
/// apps' sound in a meeting (25). The generations between and after are not voice or AI (films, phone notices,
/// the backup's tree) and this number says nothing of them: only the capture and the formatter may gate on it.
pub const NATIVE_GENERATION: u32 = 25;

const COMMANDS: &[&str] = &["ai_device", "ai_models", "ai_fetch_model", "ai_delete_model", "ai_generate", "ai_unload", "ai_cancel", "ai_infer_command"];

/// Whether `command` is one of this file's that works on the open core's directories.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

/// Whether `command` is this file's one that needs no core.
pub fn has_without_core(command: &str) -> bool {
    command == "native_status"
}

pub fn call_without_core(command: &str) -> Result<Value, String> {
    match command {
        "native_status" => Ok(json!({ "nativeGeneration": NATIVE_GENERATION, "nativeVersion": env!("CARGO_PKG_VERSION") })),
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

/// What the app asks for.
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
    /// Let a model that can reason do so before it answers, and stream the reasoning with the answer.
    #[serde(default)]
    pub think: bool,
    /// With `think`: the most tokens the thinking may run before it is closed for the model. 0 is no limit.
    #[serde(default)]
    pub think_budget: u32,
    /// Never sent by the app: a background job is a meeting's write-up, which comes in by its own door.
    #[serde(default)]
    pub background: bool,
}

fn default_temperature() -> f32 {
    0.3
}

/// The engine's request for what the app asked. Never a grammar: a constrained run is native-owned
/// (`ai_infer_command`), so a formatting run has none whatever the JSON carries.
impl From<GenerateRequest> for Request {
    fn from(request: GenerateRequest) -> Request {
        Request {
            id: request.id,
            system: request.system,
            context: request.context,
            prompt: request.prompt,
            max_tokens: request.max_tokens,
            temperature: request.temperature,
            think: request.think,
            think_budget: request.think_budget,
            grammar: None,
            background: request.background,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CommandInferenceRequest {
    pub id: String,
    pub utterance: String,
    pub preferred_model: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "status", rename_all = "kebab-case")]
pub enum CommandInferenceResult {
    Intent { intent: CommandIntent, model: String },
    Unavailable { reason: String },
}

/// One model of the catalogue, with whether this device has it.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub id: String,
    pub file: String,
    pub bytes: u64,
    pub present: bool,
    pub path: String,
}

/// The cancel flag of every run in flight, by the app's request id.
static RUNS: Mutex<Option<HashMap<String, Arc<AtomicBool>>>> = Mutex::new(None);

/// One download at a time: two would write the same `.part` at once.
static FETCHING: Mutex<()> = Mutex::new(());

fn runs<R>(with: impl FnOnce(&mut HashMap<String, Arc<AtomicBool>>) -> R) -> R {
    with(lock(&RUNS).get_or_insert_with(HashMap::new))
}

/// Raises every run's cancel flag.
fn cancel_all() {
    runs(|runs| runs.values().for_each(|flag| flag.store(true, Ordering::Relaxed)));
}

fn info(dir: &std::path::Path, spec: &LlmSpec) -> ModelInfo {
    let status = crate::model_files::status(dir, &spec.spec);
    ModelInfo { id: spec.id.to_string(), file: spec.spec.file.to_string(), bytes: spec.spec.bytes, present: status.present, path: status.path }
}

fn known(id: &str) -> Result<&'static LlmSpec, String> {
    model::find(id).ok_or_else(|| format!("Glyph does not know a model called {id}."))
}

#[derive(Deserialize)]
struct Fetch {
    id: String,
    #[serde(default)]
    mirrors: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct ById {
    id: String,
}

#[derive(Deserialize)]
struct Generate {
    request: GenerateRequest,
}

#[derive(Deserialize)]
struct Infer {
    request: CommandInferenceRequest,
}

fn started(kind: &'static str, work: impl FnOnce(&crate::work::Job) -> Result<Value, String> + Send + 'static) -> Result<Value, String> {
    Ok(json!({ "id": crate::work::start(kind, work)? }))
}

fn said<T: Serialize>(value: T) -> Result<Value, String> {
    serde_json::to_value(value).map_err(|e| format!("the answer could not be written: {e}"))
}

pub fn call(core: &Arc<Core>, command: &str, args: Value) -> Result<Value, String> {
    let dir = crate::models::dir(core);
    match command {
        "ai_device" => said(crate::llm::device::read(Some(&dir))),
        "ai_models" => said(model::CATALOGUE.iter().map(|spec| info(&dir, spec)).collect::<Vec<_>>()),
        "ai_fetch_model" => {
            let Fetch { id, mirrors } = read(command, args)?;
            let spec = known(&id)?;
            let mirrors = crate::models::mirrors(mirrors, |preferred| model::mirrors_with(spec, preferred));
            started("fetch-model", move |_| {
                crate::models::fetch_reporting(&dir, &FETCHING, &spec.spec, &mirrors, "ai://model-progress", Some(spec.id))?;
                said(info(&dir, spec))
            })
        }
        "ai_delete_model" => {
            let ById { id } = read(command, args)?;
            let spec = known(&id)?;
            // A run on this model ends, and the engine lets go of the file, before it is removed.
            cancel_all();
            if let Some(llm) = crate::llm::started() {
                llm.unload();
            }
            for candidate in [crate::model_files::path_in(&dir, &spec.spec), crate::model_files::part_path(&dir, &spec.spec)] {
                crate::fsx::remove_file_if_present(&candidate).map_err(|e| format!("cannot remove {}: {e}", candidate.display()))?;
            }
            said(info(&dir, spec))
        }
        "ai_generate" => {
            let Generate { request } = read(command, args)?;
            let spec = known(&request.model)?;
            let status = crate::model_files::status(&dir, &spec.spec);
            if !status.present {
                return Err(format!("The model {} is not on this phone yet.", spec.id));
            }
            let cancel = Arc::new(AtomicBool::new(false));
            let run = request.id.clone();
            // In the table before the command answers, so an `ai_cancel` sent straight after it finds the run.
            runs(|runs| runs.insert(run.clone(), Arc::clone(&cancel)));
            let asked = started("generate", {
                let run = run.clone();
                move |_| {
                    let answer = crate::llm::shared().generate(std::path::Path::new(&status.path), Request::from(request), cancel, |progress| crate::events::emit("ai://progress", &progress));
                    let received = answer.recv();
                    // The run is over however it ended, so its cancel flag goes before an error is answered.
                    runs(|runs| runs.remove(&run));
                    let output = received.map_err(|_| "the formatting engine went away".to_string())?.map_err(|failure| failure.to_string())?;
                    said(output)
                }
            });
            if asked.is_err() {
                runs(|runs| runs.remove(&run));
            }
            asked
        }
        "ai_unload" => {
            if let Some(llm) = crate::llm::started() {
                llm.unload();
            }
            Ok(Value::Null)
        }
        "ai_cancel" => {
            let ById { id } = read(command, args)?;
            Ok(Value::Bool(runs(|runs| runs.get(&id).map(|flag| flag.store(true, Ordering::Relaxed)).is_some())))
        }
        "ai_infer_command" => {
            let Infer { request } = read(command, args)?;
            started("infer-command", move |_| said(infer(&dir, request)))
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

/// The command model's standing instructions: ai_commands.rs's `COMMAND_SYSTEM`, which a test holds to it.
// copied:begin
const COMMAND_SYSTEM: &str = r#"Translate one spoken note command to JSON. Allowed actions: append to an existing note, create a new note, or none.
- append: "target" is only the note's title as spoken, without words like "my", "the", "note", "list", "labeled", "called" or "named". "content" is only what to add, in the speaker's words, without the command or the title. "placement" is "list" when they ask for a list, items, bullets or points; "tasks" for tasks, to-dos or check boxes; "bugs" for bugs or issues; "notes" for a paragraph or a note; otherwise null.
- When they name several things to add (movies, places, groceries), placement is "list" even if they did not say "list".
- For "list" and "tasks", separate the items in "content" with "; " and keep each item whole: "Paris, Texas; Austin, Texas".
- create: "target" is the new note's title and "content" is its body, or null.
- none: destructive (delete, remove, clear), compound (several different actions), unsupported, or unclear requests.
Never invent content or a title. Output exactly one object in the required schema.

Examples:
Command: add to my note labeled Go a list with Parkersburg West Virginia Marietta Ohio and Detroit Michigan
{"action":"append","target":"Go","content":"Parkersburg, West Virginia; Marietta, Ohio; Detroit, Michigan","placement":"list"}
Command: put call Sam and book the flights on my work to-do list
{"action":"append","target":"Work","content":"call Sam; book the flights","placement":"tasks"}
Command: add to the note called Weekend trip that we should book the ferry early
{"action":"append","target":"Weekend trip","content":"we should book the ferry early","placement":null}
Command: add eggs milk and bread to groceries
{"action":"append","target":"groceries","content":"eggs; milk; bread","placement":"list"}
Command: make a new note called Packing
{"action":"create","target":"Packing","content":null}
Command: delete everything in my Go note
{"action":"none","reason":"destructive"}"#;
// copied:end

/// Interprets one wake-word-qualified utterance using only an already installed model, a native fixed prompt,
/// and a native fixed grammar: ai_commands.rs's `ai_infer_command`, on a job's thread.
fn infer(dir: &std::path::Path, request: CommandInferenceRequest) -> CommandInferenceResult {
    let utterance = request.utterance.trim();
    if request.id.is_empty() || utterance.is_empty() || utterance.chars().count() > 4_000 {
        return CommandInferenceResult::Unavailable { reason: "The command was empty or too long.".into() };
    }
    if let Some(reason) = command::refusal(utterance) {
        return CommandInferenceResult::Intent { intent: CommandIntent::None { reason }, model: String::new() };
    }
    let preferred = model::find(&request.preferred_model).filter(|spec| crate::model_files::status(dir, &spec.spec).present);
    let fallback = model::find("qwen3.5-2b").filter(|spec| crate::model_files::status(dir, &spec.spec).present);
    let Some(spec) = preferred.or(fallback) else {
        return CommandInferenceResult::Unavailable { reason: "No compatible installed model is available for instruction commands.".into() };
    };
    let status = crate::model_files::status(dir, &spec.spec);
    let cancel = Arc::new(AtomicBool::new(false));
    let busy = runs(|runs| {
        if !runs.is_empty() {
            return true;
        }
        runs.insert(request.id.clone(), Arc::clone(&cancel));
        false
    });
    if busy {
        return CommandInferenceResult::Unavailable { reason: "The on-device model is already working.".into() };
    }
    let engine_request = Request {
        id: request.id.clone(),
        system: COMMAND_SYSTEM.into(),
        context: None,
        prompt: format!("Command: {utterance}"),
        // Room for a spoken list of a dozen places; a truncated answer fails closed.
        max_tokens: 384,
        temperature: 0.0,
        think: false,
        think_budget: 0,
        grammar: Some(command::GRAMMAR),
        // A voice command is the person waiting: it goes before, and preempts, a write-up's piece.
        background: false,
    };
    let answer = crate::llm::shared().generate(std::path::Path::new(&status.path), engine_request, cancel, |_| {});
    let received = answer.recv();
    runs(|runs| runs.remove(&request.id));
    match received {
        Err(_) => CommandInferenceResult::Unavailable { reason: "the command inference engine went away".into() },
        Ok(Ok(output)) => match command::parse(&output.text, output.truncated) {
            Ok(intent) => CommandInferenceResult::Intent { intent, model: spec.id.into() },
            Err(reason) => CommandInferenceResult::Unavailable { reason },
        },
        Ok(Err(failure)) => CommandInferenceResult::Unavailable { reason: failure.to_string() },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::capture::tests::{asked, core, job};
    use crate::events::tests::heard;
    use std::time::Duration;

    #[test]
    fn the_command_prompt_is_the_tauri_apps_word_for_word() {
        let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../glyph/src-tauri/src/ai_commands.rs");
        let source = std::fs::read_to_string(&source).unwrap_or_else(|e| panic!("{}: {e}", source.display()));
        let mine = include_str!("ai.rs").split("// copied:begin\n").nth(1).and_then(|rest| rest.split("// copied:end").next()).expect("the marks").trim();
        assert!(source.contains(mine), "ai_commands.rs no longer has this COMMAND_SYSTEM, word for word");
        assert!(source.contains("max_tokens: 384,") && source.contains("grammar: Some(command::GRAMMAR),") && source.contains("model::find(\"qwen3.5-2b\")"));
    }

    #[test]
    fn a_request_reads_from_the_apps_json_with_a_default_temperature_and_never_a_grammar() {
        let json = r#"{"id":"r1","model":"qwen3.5-4b","system":"Format.","context":"c","prompt":"hi","maxTokens":200,"think":true,"thinkBudget":64,"grammar":"root ::= \"x\""}"#;
        let request = Request::from(serde_json::from_str::<GenerateRequest>(json).expect("an extra key is not an error"));
        assert_eq!(request.grammar, None);
        assert_eq!((request.id.as_str(), request.context.as_deref(), request.max_tokens, request.think_budget), ("r1", Some("c"), 200, 64));
        assert!(request.think && (request.temperature - 0.3).abs() < f32::EPSILON && !request.background);
        assert!(known("gpt-4").unwrap_err().contains("gpt-4"));
    }

    #[test]
    fn the_generation_and_the_version_are_said_with_no_core() {
        let said = crate::dispatch::invoke("native_status", Value::Null).unwrap();
        assert_eq!(said, json!({ "nativeGeneration": 25, "nativeVersion": env!("CARGO_PKG_VERSION") }));
    }

    #[test]
    fn the_catalogue_says_what_is_here_and_a_missing_model_is_refused_by_name() {
        let Some((_, data, _)) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let models = asked("ai_models", json!({}));
        let models = models["ok"].as_array().unwrap();
        assert_eq!(models.iter().map(|m| m["id"].as_str().unwrap()).collect::<Vec<_>>(), ["qwen3.5-2b", "qwen3.5-4b", "qwen3.5-9b", "gemma-4-e4b"]);
        assert_eq!(models[0]["file"], "Qwen3.5-2B-Q4_K_M.gguf");
        assert_eq!(models[0]["bytes"], 1_280_835_840u64);
        assert_eq!(models[0]["path"], json!(data.join("models/Qwen3.5-2B-Q4_K_M.gguf")));
        let device = asked("ai_device", Value::Null);
        assert!(device["ok"]["cores"].as_u64().unwrap() >= 1 && device["ok"]["freeDiskBytes"].as_u64().is_some(), "{device}");
        assert!(device["ok"].as_object().unwrap().contains_key("phoneName"));
        assert_eq!(asked("ai_generate", json!({ "request": { "id": "r", "model": "gpt-4", "system": "", "prompt": "", "maxTokens": 1 } }))["err"], "Glyph does not know a model called gpt-4.");
        assert_eq!(asked("ai_fetch_model", json!({ "id": "gpt-4" }))["err"], "Glyph does not know a model called gpt-4.");
        assert_eq!(asked("ai_cancel", json!({ "id": "nobody" })), json!({ "ok": false }));
        assert_eq!(asked("ai_unload", Value::Null), json!({ "ok": null }));
    }

    /// A model that is not on the device, in a folder of the test's own: refused by name, then "downloaded" and
    /// removed again without a byte of it (a file of the right size is present, model_files.rs says why).
    #[test]
    fn a_model_is_absent_then_removed_with_its_half_download() {
        let root = crate::test_support::TempDir::new("ai-models");
        let core = Arc::new(Core::open(&root.join("data"), &root.join("cache")).unwrap());
        let refused = call(&core, "ai_generate", json!({ "request": { "id": "r", "model": "qwen3.5-2b", "system": "", "prompt": "", "maxTokens": 1 } }));
        assert_eq!(refused, Err("The model qwen3.5-2b is not on this phone yet.".into()));
        assert_eq!(call(&core, "ai_models", json!({})).unwrap()[0]["present"], false);
        let dir = root.join("data/models");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("Qwen3.5-2B-Q4_K_M.gguf.part"), b"half").unwrap();
        std::fs::write(dir.join("Qwen3.5-2B-Q4_K_M.gguf"), b"not the right size").unwrap();
        let removed = call(&core, "ai_delete_model", json!({ "id": "qwen3.5-2b" })).unwrap();
        assert_eq!((removed["id"].as_str(), removed["present"].as_bool()), (Some("qwen3.5-2b"), Some(false)));
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 0, "the file and its .part both go");
        // With no model at all a spoken command is unavailable, and a destructive one is refused before any model.
        let none = infer(&dir, CommandInferenceRequest { id: "c1".into(), utterance: "add milk to groceries".into(), preferred_model: "qwen3.5-4b".into() });
        assert_eq!(serde_json::to_value(none).unwrap(), json!({ "status": "unavailable", "reason": "No compatible installed model is available for instruction commands." }));
        let empty = infer(&dir, CommandInferenceRequest { id: "c2".into(), utterance: "  ".into(), preferred_model: String::new() });
        assert_eq!(serde_json::to_value(empty).unwrap(), json!({ "status": "unavailable", "reason": "The command was empty or too long." }));
    }

    /// The smallest catalogue model writes, streamed; a second run is stopped by its request's id; a spoken
    /// command comes back as an intent under the grammar.
    #[test]
    fn a_generation_streams_and_is_cancelled_and_a_command_is_read() {
        let _one = lock(&crate::guards::TEST_SERIAL);
        let Some((_, data, _)) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        if !data.join("models/Qwen3.5-2B-Q4_K_M.gguf").is_file() {
            return eprintln!("SKIPPED: no Qwen3.5-2B-Q4_K_M.gguf");
        }
        let request = |id: &str, max: u32| json!({ "request": { "id": id, "model": "qwen3.5-2b", "system": "You answer in one short sentence.", "prompt": "Count from one to five in words.", "maxTokens": max, "temperature": 0.0 } });
        let output = job("ai_generate", request("gen-1", 24), Duration::from_secs(300)).unwrap();
        eprintln!("qwen3.5-2b: {} tokens at {} a second, loaded in {} ms, {} ms in all: {:?}", output["outputTokens"], output["tokensPerSecond"], output["loadMs"], output["ms"], output["text"]);
        for key in ["text", "promptTokens", "outputTokens", "ms", "cachedTokens", "prefillMs", "loadMs", "tokensPerSecond", "truncated", "thinking"] {
            assert!(output.get(key).is_some(), "Output has {key}");
        }
        assert!(output["outputTokens"].as_u64().is_some_and(|n| (1..=24).contains(&n)) && !output["text"].as_str().unwrap().trim().is_empty());
        let mine = heard(|event, payload| event == "ai://progress" && payload["id"] == "gen-1");
        assert!(mine.iter().any(|(_, p)| p["phase"] == "generating" && p["partial"].as_str().is_some_and(|t| !t.is_empty())), "the words arrive as they are written");
        assert_eq!(mine.last().map(|(_, p)| p["phase"].clone()), Some(json!("done")));
        assert_eq!(asked("ai_cancel", json!({ "id": "gen-1" })), json!({ "ok": false }), "an ended run is gone from the table");

        // A long run, stopped once its first words are out.
        let begun = asked("ai_generate", request("gen-2", 2000));
        let id = begun["ok"]["id"].as_str().unwrap().to_string();
        crate::events::tests::wait_for(Duration::from_secs(120), |event, payload| event == "ai://progress" && payload["id"] == "gen-2" && payload["phase"] == "generating").expect("it starts writing");
        assert_eq!(asked("ai_cancel", json!({ "id": "gen-2" })), json!({ "ok": true }));
        let end = crate::events::tests::wait_for(Duration::from_secs(60), |event, payload| event == crate::work::END && payload["id"] == id.as_str()).unwrap();
        assert_eq!(end["err"], "cancelled");
        assert_eq!(heard(|event, payload| event == "ai://progress" && payload["id"] == "gen-2").last().unwrap().1["phase"], "cancelled");

        let read = job("ai_infer_command", json!({ "request": { "id": "cmd-1", "utterance": "add eggs milk and bread to groceries", "preferredModel": "qwen3.5-2b" } }), Duration::from_secs(300)).unwrap();
        eprintln!("ai_infer_command: {read}");
        assert_eq!((read["status"].as_str(), read["model"].as_str(), read["intent"]["action"].as_str()), (Some("intent"), Some("qwen3.5-2b"), Some("append")), "{read}");
        assert!(read["intent"]["target"].as_str().unwrap().to_lowercase().contains("groceries"));
        let refused = job("ai_infer_command", json!({ "request": { "id": "cmd-2", "utterance": "delete everything in my Go note", "preferredModel": "qwen3.5-2b" } }), Duration::from_secs(60)).unwrap();
        assert_eq!(refused, json!({ "status": "intent", "intent": { "action": "none", "reason": "destructive" }, "model": "" }));
        assert!(asked("ai_infer_command", json!({ "request": { "id": "c", "utterance": "x", "preferredModel": "m", "grammar": "x" } }))["err"].as_str().unwrap().contains("unknown field"));
        assert_eq!(asked("ai_unload", json!({})), json!({ "ok": null }));
    }
}
