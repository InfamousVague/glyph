//! One command for each engine, to prove it works through the C functions (the `voice` feature): not the
//! capture's or the formatter's commands, which are stage 8C's, but the smallest thing that loads a model file
//! and reports by events the way those will. Both are long jobs (work.rs): `{id}` at once, then events, then
//! `job://end`.
//!
//! - **`engine_smoke_transcribe {model, wav}`**: whisper.cpp over a 16 kHz WAV file with the model file at
//!   `model`. One `engine://loaded {id, engine: "whisper", loadMs}`, then `job://end` with
//!   `{text, segments: [{text, startMs, endMs}], audioMs, loadMs, ms, threads}` (`ms` is the transcription alone).
//! - **`engine_smoke_generate {model, prompt, system?, maxTokens?}`**: llama.cpp with the GGUF at `model`, on
//!   the shared worker (`llm::shared`). The web's own `ai://progress` events as the tokens arrive (its payload's
//!   `id` is the job's), then `job://end` with the web's `ai_generate` answer (`llm::engine::Output`: `text`,
//!   `outputTokens`, `tokensPerSecond`, `loadMs`, `ms` …). The model is unloaded afterwards: a smoke test should
//!   not keep half a gigabyte for the five minutes the formatter would.
//!
//! `job_cancel {id}` stops either within one graph computation; the job then ends with an `err`.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicI32;
use std::sync::Arc;
use std::time::Instant;

use serde::Deserialize;
use serde_json::{json, Value};

use crate::llm::engine::Request;
use crate::whisper::engine::{whisper_threads, Engine, Session};

const COMMANDS: &[&str] = &["engine_smoke_transcribe", "engine_smoke_generate"];

pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

#[derive(Deserialize)]
struct Transcribe {
    model: PathBuf,
    wav: PathBuf,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Generate {
    model: PathBuf,
    prompt: String,
    #[serde(default)]
    system: String,
    max_tokens: Option<u32>,
}

/// A file the command was pointed at, or the sentence that says it is not there: before a job is started, so a
/// wrong path is the command's own `err`.
fn present(what: &str, path: &Path) -> Result<(), String> {
    if path.is_file() {
        Ok(())
    } else {
        Err(format!("There is no {what} at {}.", path.display()))
    }
}

pub fn call(command: &str, args: Value) -> Result<Value, String> {
    match command {
        "engine_smoke_transcribe" => {
            let Transcribe { model, wav } = crate::dispatch::read(command, args)?;
            present("speech model", &model)?;
            present("recording", &wav)?;
            let id = crate::work::start("transcribe", move |job| {
                let engine = Arc::new(Engine::load(&model)?);
                let load_ms = engine.loaded_in().as_millis() as u64;
                job.emit("engine://loaded", json!({ "id": job.id, "engine": "whisper", "loadMs": load_ms }));
                let audio = crate::whisper::wav::read(&wav)?;
                let mut session = Session::new(engine, job.cancel_flag())?;
                let began = Instant::now();
                let phrases = session.transcribe_timed(&audio, "", &AtomicI32::new(0))?;
                let ms = began.elapsed().as_millis() as u64;
                let text = phrases.iter().map(|phrase| phrase.text.as_str()).collect::<Vec<_>>().join(" ");
                let segments: Vec<Value> = phrases.iter().map(|p| json!({ "text": p.text, "startMs": p.start_ms, "endMs": p.end_ms })).collect();
                Ok(json!({
                    "text": text,
                    "segments": segments,
                    "audioMs": crate::whisper::samples_to_ms(audio.len()),
                    "loadMs": load_ms,
                    "ms": ms,
                    "threads": whisper_threads(),
                }))
            })?;
            Ok(json!({ "id": id }))
        }
        "engine_smoke_generate" => {
            let Generate { model, prompt, system, max_tokens } = crate::dispatch::read(command, args)?;
            present("language model", &model)?;
            let id = crate::work::start("generate", move |job| {
                let request = Request {
                    id: job.id.clone(),
                    system,
                    context: None,
                    prompt,
                    max_tokens: max_tokens.unwrap_or(32),
                    temperature: 0.0,
                    think: false,
                    think_budget: 0,
                    grammar: None,
                    background: false,
                };
                let llm = crate::llm::shared();
                let answer = llm.generate(&model, request, job.cancel_flag(), |progress| crate::events::emit("ai://progress", &progress));
                let result = answer.recv();
                llm.unload();
                match result {
                    Ok(Ok(output)) => serde_json::to_value(output).map_err(|e| e.to_string()),
                    Ok(Err(failure)) => Err(failure.to_string()),
                    Err(_) => Err("the formatting engine has stopped".to_string()),
                }
            })?;
            Ok(json!({ "id": id }))
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::events::tests::{heard, wait_for};
    use std::time::Duration;

    /// A command through `ffi::answer`, which is `ghost_invoke` without its pointers.
    fn asked(command: &str, args: Value) -> Value {
        serde_json::from_str(&crate::ffi::answer(command.as_bytes(), args.to_string().as_bytes())).unwrap()
    }

    fn models() -> Option<PathBuf> {
        let dir = std::env::var_os("GLYPH_MODELS_DIR").map(PathBuf::from)?;
        dir.is_dir().then_some(dir)
    }

    fn ended(id: &str, limit: Duration) -> Value {
        let id = id.to_string();
        wait_for(limit, move |event, payload| event == crate::work::END && payload["id"] == id.as_str()).expect("the job ends")
    }

    /// The smallest GGUF in `dir`: the quickest proof that llama.cpp loads and samples.
    fn smallest_gguf(dir: &Path) -> Option<PathBuf> {
        let mut files: Vec<(u64, PathBuf)> = std::fs::read_dir(dir).ok()?.filter_map(|e| e.ok()).map(|e| e.path()).filter(|p| p.extension().is_some_and(|x| x == "gguf")).filter_map(|p| Some((p.metadata().ok()?.len(), p))).collect();
        files.sort();
        files.into_iter().next().map(|(_, path)| path)
    }

    #[test]
    fn whisper_transcribes_the_fixture_through_the_boundary() {
        let Some(models) = models() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let (model, wav) = (models.join("ggml-base.en-q5_1.bin"), models.join("fixture.wav"));
        if !model.is_file() || !wav.is_file() {
            return eprintln!("SKIPPED: no ggml-base.en-q5_1.bin or fixture.wav in {}", models.display());
        }
        let started = asked("engine_smoke_transcribe", json!({ "model": model, "wav": wav }));
        let id = started["ok"]["id"].as_str().unwrap_or_else(|| panic!("{started}")).to_string();
        let end = ended(&id, Duration::from_secs(120));
        let said = &end["ok"];
        eprintln!("whisper base.en: {} ms of audio in {} ms, loaded in {} ms: {}", said["audioMs"], said["ms"], said["loadMs"], said["text"]);
        assert!(said["text"].as_str().is_some_and(|text| text.split_whitespace().count() >= 5), "{end}");
        assert!(said["segments"].as_array().is_some_and(|s| !s.is_empty()));
        assert!(said["audioMs"].as_u64().unwrap() > 1_000);
        let mine = heard(|_, payload| payload["id"] == id.as_str());
        assert_eq!(mine.iter().map(|(event, _)| event.as_str()).collect::<Vec<_>>(), ["engine://loaded", crate::work::END]);
    }

    #[test]
    fn llama_generates_a_few_tokens_through_the_boundary() {
        // One model in the process at a time, with the engine's own tests (llm/tests.rs) and the write-up's.
        let _one = crate::lock::lock(&crate::guards::TEST_SERIAL);
        let Some(model) = models().and_then(|dir| smallest_gguf(&dir.join("llm"))) else { return eprintln!("SKIPPED: no .gguf under GLYPH_MODELS_DIR/llm") };
        let started = asked("engine_smoke_generate", json!({ "model": model, "prompt": "Count from one to five in words.", "maxTokens": 16 }));
        let id = started["ok"]["id"].as_str().unwrap_or_else(|| panic!("{started}")).to_string();
        let end = ended(&id, Duration::from_secs(180));
        let said = &end["ok"];
        eprintln!("{}: {} tokens at {} a second, loaded in {} ms, {} ms in all: {:?}", model.file_name().unwrap().to_string_lossy(), said["outputTokens"], said["tokensPerSecond"], said["loadMs"], said["ms"], said["text"]);
        assert!(said["outputTokens"].as_u64().is_some_and(|n| (1..=16).contains(&n)), "{end}");
        assert!(said["text"].as_str().is_some_and(|text| !text.trim().is_empty()));
        let mine = heard(|event, payload| event == "ai://progress" && payload["id"] == id.as_str());
        assert!(mine.iter().any(|(_, p)| p["phase"] == "generating" && p["partial"].as_str().is_some_and(|t| !t.is_empty())), "the words arrive as they are written");
        assert_eq!(mine.last().map(|(_, p)| p["phase"].clone()), Some(json!("done")));
    }

    #[test]
    fn a_model_that_is_not_there_is_the_command_s_own_refusal() {
        let refused = asked("engine_smoke_transcribe", json!({ "model": "/nowhere/ggml.bin", "wav": "/nowhere/a.wav" }));
        assert_eq!(refused["err"], "There is no speech model at /nowhere/ggml.bin.");
        let refused = asked("engine_smoke_generate", json!({ "model": "/nowhere/m.gguf", "prompt": "hello" }));
        assert_eq!(refused["err"], "There is no language model at /nowhere/m.gguf.");
    }
}
