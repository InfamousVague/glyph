//! `glyph-api bench <model> <transcript.txt> [runs] [--unbounded]` - the model
//! choice, measured.
//!
//! Runs the PRODUCTION pipeline - the same prompt, schema, options, chunking
//! and verbatim filter the endpoint uses, called through `model::annotate` -
//! against any model the box's Ollama has pulled, and prints one JSON line
//! per run. It lives in the binary rather than in a script beside it because a
//! benchmark that re-typed the prompt would measure a prompt the phone never
//! gets, and the first edit to either would make the numbers quietly false.
//!
//! Run it ON THE BOX. Latency here is almost all CPU (the Xeon E-2286G has no
//! GPU) and contention with AttackFM's own calls on the same Ollama, and a
//! laptop measures neither.
//!
//! The first call is a warm-up and is reported but not counted: it pays for
//! loading the model when it is not already in memory, and for evaluating the
//! system prompt the first time. The p50 is over the runs after it, which is
//! what the phone sees on its second pause and every one after.
//!
//! By default the run is held to the ENDPOINT's limits - the 45-second budget
//! and the admission gate - so it reports what the phone would actually get,
//! busy refusals included. `--unbounded` lifts both to four minutes to measure
//! what an answer costs when it is allowed to finish; on a shared runner that
//! is four minutes of AttackFM's slot per call, so it is not the default.

use crate::model;
use serde_json::json;
use std::time::{Duration, Instant};

const UNBOUNDED: Duration = Duration::from_secs(240);
const ENDPOINT_BUDGET: Duration = Duration::from_secs(45);

pub async fn run(args: &[String]) -> i32 {
    let [model_name, file, rest @ ..] = args else {
        eprintln!("usage: glyph-api bench <model> <transcript.txt> [runs, default 3] [--unbounded]");
        return 2;
    };
    let runs: usize = rest.iter().find_map(|r| r.parse().ok()).unwrap_or(3);
    let unbounded = rest.iter().any(|r| r == "--unbounded");
    let (budget, admission) = if unbounded { (UNBOUNDED, UNBOUNDED) } else { (ENDPOINT_BUDGET, model::ADMISSION_WAIT) };
    let text = match std::fs::read_to_string(file) {
        Ok(text) => text,
        Err(e) => {
            eprintln!("cannot read {file}: {e}");
            return 2;
        }
    };
    let words = text.split_whitespace().count();
    let base = std::env::var("OLLAMA_URL").unwrap_or_else(|_| "http://127.0.0.1:11434".into());
    let ollama = model::Ollama::new(&base, model_name);

    let mut counted = Vec::new();
    let (mut proposed, mut kept, mut failures) = (0usize, 0usize, 0usize);
    for run in 0..=runs {
        let started = Instant::now();
        let result = model::annotate(&ollama, &text, started + budget, admission).await;
        let elapsed_ms = started.elapsed().as_millis() as u64;
        let line = match &result {
            Ok(outcome) => {
                if run > 0 {
                    counted.push(elapsed_ms);
                    proposed += outcome.tally.proposed;
                    kept += outcome.tally.proposed - outcome.tally.dropped;
                }
                let t = outcome.timing;
                json!({
                    "model": model_name, "words": words, "run": run, "warmup": run == 0,
                    "bounded": !unbounded, "elapsedMs": elapsed_ms, "firstMs": t.first_ms, "loadMs": t.load_ms,
                    "promptTokens": t.prompt_tokens, "promptMs": t.prompt_ms,
                    "evalTokens": t.eval_tokens, "evalMs": t.eval_ms,
                    "proposed": outcome.tally.proposed, "dropped": outcome.tally.dropped,
                    "listsDropped": outcome.tally.lists_dropped,
                    "annotations": outcome.annotations,
                })
            }
            Err(failure) => {
                if run > 0 {
                    failures += 1;
                }
                json!({ "model": model_name, "words": words, "run": run, "warmup": run == 0,
                        "bounded": !unbounded, "elapsedMs": elapsed_ms, "error": failure.to_string() })
            }
        };
        println!("{line}");
    }

    counted.sort_unstable();
    let p50 = counted.get(counted.len().saturating_sub(1) / 2).copied();
    println!(
        "{}",
        json!({
            "summary": true, "model": model_name, "words": words, "runs": runs, "bounded": !unbounded,
            "answered": counted.len(), "p50AnsweredMs": p50, "failures": failures,
            "validity": if proposed == 0 { None } else { Some(kept as f64 / proposed as f64) },
            "proposed": proposed, "kept": kept,
        })
    );
    0
}
