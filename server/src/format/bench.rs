//! `glyph-api bench <model> <transcript.txt> [runs] [--unbounded]` - the model
//! choice, measured.
//!
//! Runs the PRODUCTION pipeline - the same prompt, schema, options, chunking
//! and verbatim filter the endpoint uses, called through `model::annotate` -
//! against any model the box's Ollama has pulled, and prints one JSON line
//! per run. It lives in the binary rather than in a script beside it because a
//! benchmark that re-typed the prompt would measure a prompt the phone never
//! gets, and the first edit to either would make the numbers quietly false.
//! The endpoint's budget and Ollama address are the route's own constants
//! (format.rs) for the same reason.
//!
//! Run it ON THE BOX. Latency here is almost all CPU (the Xeon E-2286G has no
//! GPU) and contention with AttackFM's own calls on the same Ollama, and a
//! laptop measures neither.
//!
//! The first call is a warm-up and is reported but not counted: it pays for
//! loading the model when it is not already in memory, and for evaluating the
//! system prompt the first time. The p50 is over the runs after it, which is
//! what the phone saw on its second pause and every one after.
//!
//! By default the run is held to the ENDPOINT's limits - the 45-second budget
//! and the admission gate - so it reports what the phone would actually get,
//! busy refusals included. `--unbounded` lifts both to four minutes to measure
//! what an answer costs when it is allowed to finish; on a shared runner that
//! is four minutes of AttackFM's slot per call, so it is not the default.

use super::model;
use serde_json::json;
use std::io::Write;
use std::time::{Duration, Instant};

const UNBOUNDED: Duration = Duration::from_secs(240);

const USAGE: &str = "usage: glyph-api bench <model> <transcript.txt> [runs, default 3] [--unbounded]";

/// What the command line asked for.
#[derive(Debug, PartialEq)]
struct Plan {
    model: String,
    file: String,
    /// Counted runs, after the warm-up.
    runs: usize,
    unbounded: bool,
}

impl Plan {
    /// The model and the transcript, then in any order a count of runs and `--unbounded`. `None` is the usage line.
    fn parse(args: &[String]) -> Option<Plan> {
        let [model, file, rest @ ..] = args else { return None };
        Some(Plan {
            model: model.clone(),
            file: file.clone(),
            runs: rest.iter().find_map(|r| r.parse().ok()).unwrap_or(3),
            unbounded: rest.iter().any(|r| r == "--unbounded"),
        })
    }

    /// The whole budget and the admission gate each call is held to.
    fn limits(&self) -> (Duration, Duration) {
        if self.unbounded {
            (UNBOUNDED, UNBOUNDED)
        } else {
            (super::UPSTREAM_TIMEOUT, model::ADMISSION_WAIT)
        }
    }
}

pub async fn run(args: &[String]) -> i32 {
    let Some(plan) = Plan::parse(args) else {
        eprintln!("{USAGE}");
        return 2;
    };
    let text = match std::fs::read_to_string(&plan.file) {
        Ok(text) => text,
        Err(e) => {
            eprintln!("cannot read {}: {e}", plan.file);
            return 2;
        }
    };
    let base = std::env::var("OLLAMA_URL").unwrap_or_else(|_| super::DEFAULT_OLLAMA.into());
    let ollama = model::Ollama::new(&base, &plan.model);
    measure(&plan, &ollama, &text, &mut std::io::stdout()).await;
    0
}

/// The middle of the answered times, sorted: the lower of the two middles when there is an even number of them.
fn p50(sorted: &[u64]) -> Option<u64> {
    sorted.get(sorted.len().saturating_sub(1) / 2).copied()
}

/// The warm-up and the counted runs, one JSON line each to `out`, then the summary line.
async fn measure(plan: &Plan, ollama: &model::Ollama, text: &str, out: &mut impl Write) {
    let (budget, admission) = plan.limits();
    let (model_name, unbounded, runs) = (plan.model.as_str(), plan.unbounded, plan.runs);
    let words = text.split_whitespace().count();
    let mut emit = |line: serde_json::Value| writeln!(out, "{line}").expect("the benchmark's output can be written");

    let mut counted = Vec::new();
    let (mut proposed, mut kept, mut failures) = (0usize, 0usize, 0usize);
    for run in 0..=runs {
        let started = Instant::now();
        let result = model::annotate(ollama, text, started + budget, admission).await;
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
        emit(line);
    }

    counted.sort_unstable();
    emit(json!({
        "summary": true, "model": model_name, "words": words, "runs": runs, "bounded": !unbounded,
        "answered": counted.len(), "p50AnsweredMs": p50(&counted), "failures": failures,
        "validity": if proposed == 0 { None } else { Some(kept as f64 / proposed as f64) },
        "proposed": proposed, "kept": kept,
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format::fake_ollama::{fake_ollama, stream_of};
    use serde_json::Value;

    fn args(words: &[&str]) -> Vec<String> {
        words.iter().map(|w| w.to_string()).collect()
    }

    /// `measure`'s lines, read back as JSON.
    async fn lines_of(plan: &Plan, ollama: &model::Ollama, text: &str) -> Vec<Value> {
        let mut out = Vec::new();
        measure(plan, ollama, text, &mut out).await;
        String::from_utf8(out).unwrap().lines().map(|line| serde_json::from_str(line).unwrap()).collect()
    }

    #[test]
    fn the_command_line_names_a_model_and_a_transcript_then_runs_and_bounds_in_any_order() {
        assert_eq!(Plan::parse(&args(&[])), None);
        assert_eq!(Plan::parse(&args(&["qwen3.5:9b"])), None, "a model with no transcript is the usage line");
        let plan = Plan::parse(&args(&["qwen3.5:9b", "spoken-200.txt"])).unwrap();
        assert_eq!(plan, Plan { model: "qwen3.5:9b".into(), file: "spoken-200.txt".into(), runs: 3, unbounded: false });
        let plan = Plan::parse(&args(&["m", "t.txt", "--unbounded", "5"])).unwrap();
        assert_eq!((plan.runs, plan.unbounded), (5, true));
        let plan = Plan::parse(&args(&["m", "t.txt", "7", "--unbounded"])).unwrap();
        assert_eq!((plan.runs, plan.unbounded), (7, true));
    }

    #[test]
    fn a_bounded_run_is_held_to_the_endpoint_s_own_limits() {
        let bounded = Plan::parse(&args(&["m", "t.txt"])).unwrap();
        assert_eq!(bounded.limits(), (crate::format::UPSTREAM_TIMEOUT, model::ADMISSION_WAIT));
        let unbounded = Plan::parse(&args(&["m", "t.txt", "--unbounded"])).unwrap();
        assert_eq!(unbounded.limits(), (UNBOUNDED, UNBOUNDED));
    }

    #[test]
    fn the_p50_is_the_middle_answer_and_the_lower_middle_of_an_even_count() {
        assert_eq!(p50(&[]), None);
        assert_eq!(p50(&[40]), Some(40));
        assert_eq!(p50(&[10, 20, 30]), Some(20));
        assert_eq!(p50(&[10, 20, 30, 40]), Some(20));
    }

    #[tokio::test]
    async fn the_warm_up_is_reported_and_only_the_runs_after_it_are_counted() {
        let answer = r#"{"title":"Plumber","emphasis":["Friday","Saturday"],"tasks":["call the plumber"],"lists":[],"sections":[]}"#;
        let (base, seen) = fake_ollama(false, Duration::ZERO, stream_of(answer, "stop")).await;
        let plan = Plan::parse(&args(&["test-model", "t.txt", "2"])).unwrap();
        let lines = lines_of(&plan, &model::Ollama::new(&base, "test-model"), "I need to call the plumber on Friday.").await;

        assert_eq!(lines.len(), 4, "the warm-up, two runs, the summary: {lines:?}");
        assert_eq!(seen.lock().unwrap().len(), 3, "one chat a run, the warm-up included");
        assert_eq!((lines[0]["run"].clone(), lines[0]["warmup"].clone()), (json!(0), json!(true)));
        assert_eq!((lines[2]["run"].clone(), lines[2]["warmup"].clone()), (json!(2), json!(false)));
        assert_eq!(lines[1]["words"], 8);
        assert_eq!(lines[1]["dropped"], 1, "Saturday was never said");
        assert_eq!(lines[1]["annotations"]["tasks"], json!(["call the plumber"]));
        assert_eq!(lines[1]["evalTokens"], 90);

        let summary = &lines[3];
        assert_eq!(summary["summary"], true);
        assert_eq!((summary["runs"].clone(), summary["answered"].clone(), summary["failures"].clone()), (json!(2), json!(2), json!(0)));
        assert_eq!((summary["proposed"].clone(), summary["kept"].clone()), (json!(6), json!(4)), "three offers a run, two runs counted");
        assert!((summary["validity"].as_f64().unwrap() - 4.0 / 6.0).abs() < 1e-9);
        assert!(summary["p50AnsweredMs"].is_u64());
        assert_eq!(summary["bounded"], true);
    }

    #[tokio::test]
    async fn a_model_that_never_answers_is_counted_as_failures_with_nothing_to_rate() {
        let plan = Plan::parse(&args(&["test-model", "t.txt", "2"])).unwrap();
        let lines = lines_of(&plan, &model::Ollama::new("http://127.0.0.1:9", "test-model"), "call the plumber").await;
        assert_eq!(lines.len(), 4);
        assert!(lines[..3].iter().all(|line| line["error"].as_str().is_some_and(|e| e.contains("unavailable"))), "{lines:?}");
        let summary = &lines[3];
        assert_eq!((summary["answered"].clone(), summary["failures"].clone()), (json!(0), json!(2)), "the warm-up's failure is not counted");
        assert_eq!((summary["p50AnsweredMs"].clone(), summary["validity"].clone()), (Value::Null, Value::Null));
    }
}
