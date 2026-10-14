//! The language model's commands and events (the `voice` feature): what `tauri/src-tauri/src/ai_commands.rs`
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
//! - `ai_infer_command {request: {id, utterance, titles?, preferredModel}}` (job) -> `{status: "intent", intent, model}`
//!   or `{status: "unavailable", reason}`: one spoken command read under this binary's own prompt and grammar.
//! - `ai_voice_step {request: {id, transcript, titles?, stage, kind?, draft?, preferredModel}}` (job) ->
//!   `{status: "answer", answer, raw, model}`, `{status: "refused", reason}` or `{status: "unavailable", reason}`:
//!   one step of reading a finished recording ("sort", "plan" with the `kind` sorting found, or "polish" with the
//!   app's `draft`), under this binary's own prompts and grammars (llm/command.rs). Titles only, never a body.
//! - `ai_diagnostics` -> `{engineStarted, modelLoaded, runs: [{id, what, ageMs}], events: [{at, line}]}`: the
//!   engine as the voice log sees it, so a step that did not answer can say why.
//!
//! What differs from ai_commands.rs:
//!
//! - **No Tauri state**: the runs in flight are this process's ([`RUNS`]).
//! - **`native_status`** -> `{nativeGeneration, nativeVersion}`: the two fields of the Tauri app's `ota_status`
//!   that the capture and the formatter gate on (`hasNativeGeneration`, `binaryVersion`). This app has no
//!   over-the-air bundle and so no `ota_status`. [`NATIVE_GENERATION`] says what the number promises here.
//! - **Nothing for Tauri's Exit** (`ai_commands::shutdown` stopped the worker so C++'s static destructors never
//!   met a decode): an Android process is not exited by its app, and the Mac target that will need it is stage 10's.

use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

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

const COMMANDS: &[&str] = &["ai_device", "ai_models", "ai_fetch_model", "ai_delete_model", "ai_generate", "ai_unload", "ai_cancel", "ai_infer_command", "ai_voice_step", "ai_diagnostics"];

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
    /// The titles of the person's notes, so the model can tell which one was meant. Titles only: never a body or an id.
    #[serde(default)]
    pub titles: Vec<String>,
    pub preferred_model: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct VoiceStepRequest {
    pub id: String,
    /// The whole finished recording.
    pub transcript: String,
    /// The titles of the person's notes: never a body or an id.
    #[serde(default)]
    pub titles: Vec<String>,
    /// "sort", "plan" with the `kind` sorting found, or "polish" with a `draft`.
    pub stage: String,
    #[serde(default)]
    pub kind: Option<String>,
    /// For "polish": the app's draft, as the plan's JSON.
    #[serde(default)]
    pub draft: Option<String>,
    pub preferred_model: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "status", rename_all = "kebab-case")]
pub enum VoiceStepResult {
    /// The model's JSON, checked to be one whole object, and its raw text for the voice log.
    Answer { answer: Value, raw: String, model: String },
    /// A destructive request: not given to the model at all.
    Refused { reason: String },
    Unavailable { reason: String },
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

/// How long a voice step waits for the model, queueing and loading included, before it gives up and lets the
/// recording be saved as a note.
const STEP_WAIT: Duration = Duration::from_secs(120);
/// The polish is only an improvement on a draft that already works: it gets less time.
const POLISH_WAIT: Duration = Duration::from_secs(60);
/// Lines the diagnostics keep.
const EVENTS_KEPT: usize = 200;

/// One generation in flight.
struct Run {
    cancel: Arc<AtomicBool>,
    what: &'static str,
    started: Instant,
}

/// What `ai_diagnostics` says about one run in flight.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunInfo {
    id: String,
    what: String,
    age_ms: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Event {
    /// Unix milliseconds.
    at: u64,
    line: String,
}

/// The engine as the app can see it, for the voice log: is a model in memory, what is running or waiting, and the
/// last things that happened.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Diagnostics {
    pub engine_started: bool,
    pub model_loaded: bool,
    pub runs: Vec<RunInfo>,
    pub events: Vec<Event>,
}

/// The run of every generation in flight, by the app's request id.
static RUNS: Mutex<Option<HashMap<String, Run>>> = Mutex::new(None);

/// The last [`EVENTS_KEPT`] things the engine did, for `ai_diagnostics`.
static EVENTS: Mutex<VecDeque<Event>> = Mutex::new(VecDeque::new());

/// One download at a time: two would write the same `.part` at once.
static FETCHING: Mutex<()> = Mutex::new(());

fn runs<R>(with: impl FnOnce(&mut HashMap<String, Run>) -> R) -> R {
    with(lock(&RUNS).get_or_insert_with(HashMap::new))
}

/// Raises every run's cancel flag.
fn cancel_all() {
    runs(|runs| runs.values().for_each(|run| run.cancel.store(true, Ordering::Relaxed)));
}

fn log(line: impl Into<String>) {
    let at = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0);
    let mut events = lock(&EVENTS);
    if events.len() >= EVENTS_KEPT {
        events.pop_front();
    }
    events.push_back(Event { at, line: line.into() });
}

/// A run's entry in [`RUNS`], removed when this drops: on success, on an error, on a panic and when the job that
/// holds it is dropped. Nothing else removes it, so one failed request can never leave the engine looking busy.
struct RunGuard {
    id: String,
    what: &'static str,
    started: Instant,
}

impl Drop for RunGuard {
    fn drop(&mut self) {
        runs(|runs| runs.remove(&self.id));
        log(format!("{} {} finished after {} ms", self.what, self.id, self.started.elapsed().as_millis()));
    }
}

/// Records a run and says what it is queued behind.
fn begin(id: &str, what: &'static str, cancel: &Arc<AtomicBool>) -> RunGuard {
    let started = Instant::now();
    let ahead = runs(|runs| {
        let ahead = runs.len();
        runs.insert(id.to_string(), Run { cancel: Arc::clone(cancel), what, started });
        ahead
    });
    log(if ahead == 0 { format!("{what} {id} started") } else { format!("{what} {id} queued behind {ahead} run(s)") });
    RunGuard { id: id.to_string(), what, started }
}

/// The engine's state and last events: `ai_diagnostics`. Reads only.
fn diagnostics() -> Diagnostics {
    let llm = crate::llm::started();
    let mut in_flight: Vec<RunInfo> =
        runs(|runs| runs.iter().map(|(id, run)| RunInfo { id: id.clone(), what: run.what.to_string(), age_ms: run.started.elapsed().as_millis() as u64 }).collect());
    in_flight.sort_by(|a, b| b.age_ms.cmp(&a.age_ms));
    let events = lock(&EVENTS).iter().cloned().collect();
    Diagnostics { engine_started: llm.is_some(), model_loaded: llm.is_some_and(|llm| llm.loaded()), runs: in_flight, events }
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

#[derive(Deserialize)]
struct Step {
    request: VoiceStepRequest,
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
            // In the table before the command answers, so an `ai_cancel` sent straight after it finds the run. The
            // guard goes with the job, however it ends, or with the closure if the job never starts.
            let run = begin(&request.id, "format", &cancel);
            started("generate", move |_| {
                let id = request.id.clone();
                let answer = crate::llm::shared().generate(std::path::Path::new(&status.path), Request::from(request), cancel, |progress| crate::events::emit("ai://progress", &progress));
                let received = answer.recv();
                // The run is over however it ended, so its cancel flag goes before an error is answered.
                drop(run);
                let output = received.map_err(|_| "the formatting engine went away".to_string())?.map_err(|failure| {
                    log(format!("format {id} failed: {failure}"));
                    failure.to_string()
                })?;
                said(output)
            })
        }
        "ai_unload" => {
            if let Some(llm) = crate::llm::started() {
                llm.unload();
            }
            Ok(Value::Null)
        }
        "ai_cancel" => {
            let ById { id } = read(command, args)?;
            Ok(Value::Bool(runs(|runs| runs.get(&id).map(|run| run.cancel.store(true, Ordering::Relaxed)).is_some())))
        }
        "ai_infer_command" => {
            let Infer { request } = read(command, args)?;
            started("infer-command", move |_| said(infer(&dir, request)))
        }
        "ai_voice_step" => {
            let Step { request } = read(command, args)?;
            started("voice-step", move |_| said(voice_step(&dir, request)))
        }
        "ai_diagnostics" => said(diagnostics()),
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

/// The command model's standing instructions: ai_commands.rs's `COMMAND_SYSTEM`, which a test holds to it.
// copied:begin
const COMMAND_SYSTEM: &str = r#"Read what someone said into a notes app and work out whether they asked for a change to their notes, and if so what they want in the end. They talk naturally: the request can come after other talk ("so I was thinking… can you make me a list"), and a request someone else was given, or talk about adding things later, is not one. Answer with JSON. Allowed actions: append to an existing note, create a new note, or none.
- Their notes are listed first. For append, "target" should be one of those titles, allowing for misheard words.
- append: "target" is only the note's title as spoken, without words like "my", "the", "note", "list", "labeled", "called" or "named". "content" is only what to add, in the speaker's words, without the command or the title. "placement" is "list" when they ask for a list, items, bullets or points; "tasks" for tasks, to-dos or check boxes; "bugs" for bugs or issues; "notes" for a paragraph or a note; otherwise null.
- When they name several things to add (movies, places, groceries), placement is "list" even if they did not say "list".
- For "list" and "tasks", separate the items in "content" with "; " and keep each item whole: "Paris, Texas; Austin, Texas".
- create: "target" is the new note's title and "content" is its body, or null.
- "Make a list called X and add A and B" is one request: create X with content "A; B".
- none: destructive (delete, remove, clear) or unsupported requests; "unclear" when it is ordinary talk, not a request.
Never invent content or a title. Output exactly one object in the required schema.

Examples:
Notes: Go, Work
Said: add to my note labeled Go a list with Parkersburg West Virginia Marietta Ohio and Detroit Michigan
{"action":"append","target":"Go","content":"Parkersburg, West Virginia; Marietta, Ohio; Detroit, Michigan","placement":"list"}
Said: put call Sam and book the flights on my work to-do list
{"action":"append","target":"Work","content":"call Sam; book the flights","placement":"tasks"}
Said: add to the note called Weekend trip that we should book the ferry early
{"action":"append","target":"Weekend trip","content":"we should book the ferry early","placement":null}
Said: add eggs milk and bread to groceries
{"action":"append","target":"groceries","content":"eggs; milk; bread","placement":"list"}
Said: make a new note called Packing
{"action":"create","target":"Packing","content":null}
Said: ok so I was watching stuff last night, can you make me a list called movies with Jaws, Alien and Heat
{"action":"create","target":"Movies","content":"Jaws; Alien; Heat"}
Said: I told Sam I would add the photos to the album later
{"action":"none","reason":"unclear"}
Said: delete everything in my Go note
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
    let _run = begin(&request.id, "command", &cancel);
    let engine_request = Request {
        id: request.id.clone(),
        system: COMMAND_SYSTEM.into(),
        context: None,
        prompt: command::user_prompt(utterance, &request.titles),
        // Room for a spoken list of a dozen places; a truncated answer fails closed.
        max_tokens: 384,
        temperature: 0.0,
        think: false,
        think_budget: 0,
        grammar: Some(command::GRAMMAR),
        // A voice command is the person waiting: it goes before, and preempts, a write-up's piece.
        background: false,
    };
    let answer = crate::llm::shared().generate(std::path::Path::new(&status.path), engine_request, Arc::clone(&cancel), |_| {});
    match answer.recv_timeout(STEP_WAIT) {
        Err(why) => CommandInferenceResult::Unavailable { reason: waited_in_vain(&request.id, &cancel, why, STEP_WAIT) },
        Ok(Ok(output)) => match command::parse(&output.text, output.truncated) {
            Ok(intent) => CommandInferenceResult::Intent { intent, model: spec.id.into() },
            Err(reason) => CommandInferenceResult::Unavailable { reason },
        },
        Ok(Err(failure)) => CommandInferenceResult::Unavailable { reason: failure.to_string() },
    }
}

/// One step of reading a finished recording (llm/command.rs): "sort" says what kind of thing it is, "plan" turns it
/// into actions with real item lists, "polish" tidies the app's own draft. Only an installed model, a native fixed
/// prompt and a native fixed grammar: ai_commands.rs's `ai_voice_step`, on a job's thread.
fn voice_step(dir: &std::path::Path, request: VoiceStepRequest) -> VoiceStepResult {
    let transcript = request.transcript.trim();
    if request.id.is_empty() || transcript.is_empty() || transcript.chars().count() > 4_000 {
        return VoiceStepResult::Unavailable { reason: "The recording was empty or too long.".into() };
    }
    let draft = request.draft.as_deref().map(str::trim).filter(|draft| !draft.is_empty() && draft.chars().count() <= 6_000);
    let (system, grammar, kind, max_tokens, what, wait): (&str, &'static str, Option<&str>, u32, &'static str, Duration) = match (request.stage.as_str(), request.kind.as_deref()) {
        ("sort", _) => (command::SORT_SYSTEM, command::SORT_GRAMMAR, None, 16, "voice sort", STEP_WAIT),
        ("plan", Some(kind @ ("add" | "new" | "mixed"))) => (command::PLAN_SYSTEM, command::PLAN_GRAMMAR, Some(kind), 640, "voice plan", STEP_WAIT),
        ("polish", _) if draft.is_some() => (command::POLISH_SYSTEM, command::PLAN_GRAMMAR, None, 640, "voice polish", POLISH_WAIT),
        _ => return VoiceStepResult::Unavailable { reason: "Unknown voice step.".into() },
    };
    if command::refusal(transcript).is_some() {
        return VoiceStepResult::Refused { reason: "Deleting, clearing or sending notes by voice is not supported.".into() };
    }
    let preferred = model::find(&request.preferred_model).filter(|spec| crate::model_files::status(dir, &spec.spec).present);
    let fallback = model::find("qwen3.5-2b").filter(|spec| crate::model_files::status(dir, &spec.spec).present);
    let Some(spec) = preferred.or(fallback) else {
        return VoiceStepResult::Unavailable { reason: "No compatible installed model is available for voice commands.".into() };
    };
    let status = crate::model_files::status(dir, &spec.spec);
    let cancel = Arc::new(AtomicBool::new(false));
    let _run = begin(&request.id, what, &cancel);
    let engine_request = Request {
        id: request.id.clone(),
        system: system.into(),
        context: None,
        prompt: match draft {
            Some(draft) if request.stage == "polish" => command::polish_prompt(transcript, draft),
            _ => command::voice_prompt(transcript, &request.titles, kind),
        },
        max_tokens,
        temperature: 0.0,
        think: false,
        think_budget: 0,
        grammar: Some(grammar),
        // A voice step is the person waiting: it goes before, and preempts, a write-up's piece.
        background: false,
    };
    let answer = crate::llm::shared().generate(std::path::Path::new(&status.path), engine_request, Arc::clone(&cancel), |_| {});
    match answer.recv_timeout(wait) {
        Err(why) => VoiceStepResult::Unavailable { reason: waited_in_vain(&request.id, &cancel, why, wait) },
        Ok(Ok(output)) => {
            log(format!(
                "voice step {} ran: load {} ms, prefill {} ms ({} cached), {} tokens at {:.1}/s, {} ms in all",
                request.id, output.load_ms, output.prefill_ms, output.cached_tokens, output.output_tokens, output.tokens_per_second, output.ms
            ));
            match command::check_answer(&output.text, output.truncated) {
                Ok(answer) => VoiceStepResult::Answer { answer, raw: output.text, model: spec.id.into() },
                Err(reason) => VoiceStepResult::Unavailable { reason: format!("{reason}: {}", output.text.chars().take(300).collect::<String>()) },
            }
        }
        Ok(Err(failure)) => {
            log(format!("voice step {} failed: {failure}", request.id));
            VoiceStepResult::Unavailable { reason: failure.to_string() }
        }
    }
}

/// A step whose answer did not come: cancels it so a queued job does not run later for nobody, and says why in
/// words for the log.
fn waited_in_vain(id: &str, cancel: &AtomicBool, why: std::sync::mpsc::RecvTimeoutError, wait: Duration) -> String {
    cancel.store(true, Ordering::Relaxed);
    let reason = match why {
        std::sync::mpsc::RecvTimeoutError::Timeout => format!("The on-device model did not answer within {} seconds.", wait.as_secs()),
        std::sync::mpsc::RecvTimeoutError::Disconnected => "The on-device model engine went away.".to_string(),
    };
    log(format!("step {id}: {reason}"));
    reason
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::capture::tests::{asked, core, job};
    use crate::events::tests::heard;
    use std::time::Duration;

    #[test]
    fn the_command_prompt_is_the_tauri_apps_word_for_word() {
        let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../tauri/src-tauri/src/ai_commands.rs");
        let source = std::fs::read_to_string(&source).unwrap_or_else(|e| panic!("{}: {e}", source.display()));
        let mine = include_str!("ai.rs").split("// copied:begin\n").nth(1).and_then(|rest| rest.split("// copied:end").next()).expect("the marks").trim();
        assert!(source.contains(mine), "ai_commands.rs no longer has this COMMAND_SYSTEM, word for word");
        assert!(source.contains("max_tokens: 384,") && source.contains("grammar: Some(command::GRAMMAR),") && source.contains("model::find(\"qwen3.5-2b\")"));
    }

    #[test]
    fn a_run_leaves_the_table_when_its_guard_drops_however_it_ends() {
        let _one = lock(&crate::guards::TEST_SERIAL);
        let cancel = Arc::new(AtomicBool::new(false));
        {
            let _first = begin("guard-a", "format", &cancel);
            let _second = begin("guard-b", "voice sort", &cancel);
            assert!(runs(|runs| runs.contains_key("guard-a") && runs.contains_key("guard-b")));
        }
        assert!(runs(|runs| !runs.contains_key("guard-a") && !runs.contains_key("guard-b")), "a finished or failed run must never leave the engine looking busy");
        assert!(lock(&EVENTS).iter().any(|event| event.line.contains("guard-b queued behind")));
    }

    #[test]
    fn the_event_log_keeps_only_the_latest_lines() {
        let _one = lock(&crate::guards::TEST_SERIAL);
        for n in 0..EVENTS_KEPT + 10 {
            log(format!("line {n}"));
        }
        let events = lock(&EVENTS);
        assert_eq!(events.len(), EVENTS_KEPT);
        assert_eq!(events.back().map(|e| e.line.clone()), Some(format!("line {}", EVENTS_KEPT + 9)));
    }

    #[test]
    fn a_voice_step_is_refused_unknown_or_unavailable_before_any_model() {
        let root = crate::test_support::TempDir::new("ai-voice-step");
        let dir = root.join("data/models");
        std::fs::create_dir_all(&dir).unwrap();
        let step = |stage: &str, kind: Option<&str>, draft: Option<&str>, transcript: &str| {
            let request = VoiceStepRequest {
                id: "s1".into(),
                transcript: transcript.into(),
                titles: vec![],
                stage: stage.into(),
                kind: kind.map(Into::into),
                draft: draft.map(Into::into),
                preferred_model: String::new(),
            };
            serde_json::to_value(voice_step(&dir, request)).unwrap()
        };
        assert_eq!(step("sort", None, None, "  ")["status"], "unavailable");
        assert_eq!(step("plan", Some("note"), None, "add milk to groceries"), json!({ "status": "unavailable", "reason": "Unknown voice step." }));
        assert_eq!(step("polish", None, None, "add milk to groceries")["reason"], "Unknown voice step.");
        assert_eq!(step("sort", None, None, "delete everything in my Go note")["status"], "refused");
        assert_eq!(step("sort", None, None, "add milk to groceries"), json!({ "status": "unavailable", "reason": "No compatible installed model is available for voice commands." }));
    }

    #[test]
    fn diagnostics_say_what_the_engine_is_doing() {
        let _one = lock(&crate::guards::TEST_SERIAL);
        let said = serde_json::to_value(diagnostics()).unwrap();
        for key in ["engineStarted", "modelLoaded", "runs", "events"] {
            assert!(said.get(key).is_some(), "diagnostics has {key}");
        }
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
        let none = infer(&dir, CommandInferenceRequest { id: "c1".into(), utterance: "add milk to groceries".into(), titles: vec![], preferred_model: "qwen3.5-4b".into() });
        assert_eq!(serde_json::to_value(none).unwrap(), json!({ "status": "unavailable", "reason": "No compatible installed model is available for instruction commands." }));
        let empty = infer(&dir, CommandInferenceRequest { id: "c2".into(), utterance: "  ".into(), titles: vec![], preferred_model: String::new() });
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
