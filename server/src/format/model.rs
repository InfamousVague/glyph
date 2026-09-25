//! The conversation with Ollama: one call per chunk, admitted or withdrawn at the first token, and the whole note
//! assembled from the chunks. What each call asks is `prompt.rs`'s.
//!
//! The model is asked to POINT, never to write. It returns a title and a set of
//! pointers into the transcript - phrases to bold, action items, enumerations,
//! where sections start - and the phone applies them to the words it already
//! has. Two things follow from that, and both are the reason for the design:
//!
//! - Output is bounded. On this box (Xeon E-2286G, no GPU) generation is the
//!   slow half of a call. A rewrite costs as many tokens as the note has -
//!   about 800 for a 591-word note, and more every minute Matt talks - where
//!   annotations are held by the schema's ceilings to a few hundred however
//!   long the note is (263 MEASURED for 198 words).
//! - The model CANNOT change what Matt said. The worst a bad answer can do is
//!   bold the wrong phrase, and `shape.rs` removes anything that is not a
//!   verbatim piece of the input before the phone ever sees it.
//!
//! ONE SLOT, NOT TWO. Ollama is configured with `OLLAMA_NUM_PARALLEL=2`, and
//! that reads like a spare lane beside AttackFM's. It is not, for this model:
//! Ollama 0.33 starts the qwen3.5:9b runner as `llama-server -c 4096 -np 1`
//! (read off `ps` on the box, 2026-09-12). Every call this service makes to it
//! queues behind AttackFM's calls, and every call that RUNS holds AttackFM's
//! only slot. Hence the admission gate in `call` and the output ceilings in
//! `prompt.rs`'s schema - the two things that bound what a phone can take from
//! it. `prompt.rs` also says what a chat must never carry, and why.

use super::chunks::chunks;
use super::prompt::{self, NUM_PREDICT};
use super::shape::{self, Annotations, Raw, Tally};
use serde_json::{json, Value};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// The model that annotates: qwen3.5:9b, the chat model AttackFM keeps loaded.
///
/// MEASURED ON THE BOX on 2026-09-12 with `glyph-api bench` against
/// server/bench/spoken-200.txt and spoken-600.txt (198 and 591 spoken words: a
/// title-worthy opening, a spoken list, two tasks, a date, a time and a topic
/// change). One warm-up, then three counted runs. Load average 10 to 16 on the
/// 12 threads throughout - AttackFM's own chat calls queued end to end on this
/// runner, beside its whisper-cli large-v3 job at about 400% CPU.
///
///   model        words  limits    answered  median of 3  kept    output
///   qwen3.5:9b   198    endpoint  0 of 4    -            -       busy at 15 s
///   qwen3.5:9b   591    endpoint  0 of 4    -            -       busy at 15 s
///   qwen3.5:9b   198    4 min     3 of 4    143.9 s      34/36   263 tok, 57-64 s
///   qwen3.5:9b   198    4 min v1  1 of 4    over 240 s   33/35   350 tok, 85 s
///   llama3.2:3b  198    4 min v1  0 of 4    over 240 s   -       never ran
///   gemma4:12b   -      -         not run
///   gpt-oss:20b  -      -         not run
///
/// "endpoint" is the service's own 45-second budget and admission gate; "4 min"
/// lifts both to see what an answer costs; "v1" is the first prompt, before
/// the schema ceilings. Time to first token in the 4-minute runs was 39 to 81
/// seconds, almost all of it waiting behind AttackFM (prompt evaluation took
/// 1.0-1.4 s cached, 28 s cold). Quality where it answered was right: the
/// title, the shopping list, both tasks, the date and time, the book-club
/// section, and one or two pointers per run dropped as not verbatim.
///
/// The target was under 8 seconds for 200 words, and NOTHING on this box meets
/// it: at the measured 4.1-4.6 tokens a second, 8 seconds is 35 tokens, which
/// is less than the shopping list alone. llama3.2:3b never got to run - with
/// OLLAMA_MAX_LOADED_MODELS=2, loading a third model waits to evict one of
/// AttackFM's two, and it loaded only as its fourth call expired, by evicting
/// nomic-embed-text. gemma4:12b needs the same eviction and generates at 2.4
/// tokens a second by AttackFM's own measurement (ai.rs); gpt-oss:20b is 13 GB
/// against 12 GB available, so it would evict qwen3.5:9b itself.
///
/// So this is not the model that answers fastest; it is the only one that
/// costs AttackFM nothing to TRY. It is already loaded, so asking never
/// evicts; the admission gate withdraws a call that is still queued; and
/// `breaker.rs` stops asking for ten minutes after an admitted call
/// overruns. On the box as measured the phone gets a 503 and keeps its own
/// formatting, which is the failure it was designed to absorb. Making it
/// ANSWER is a decision about the box, not this line - room for a third
/// runner with a small model beside AttackFM's, or AttackFM's queue drained -
/// and `GLYPH_API_MODEL` in the unit tries another model without a rebuild.
pub const MODEL: &str = "qwen3.5:9b";

/// How long a call may wait for its FIRST token before it is abandoned.
///
/// The first token is the only signal Ollama gives that a request has the
/// runner rather than a place in its queue, so this is the admission gate. A
/// call still queued when it expires is cancelled - the connection drops and
/// Ollama removes it - having cost AttackFM nothing, and the phone gets a 503
/// it treats as "no polish this time".
///
/// Fifteen seconds is the 45-second budget minus what a useful answer needs
/// once admitted: about 120 tokens of annotations at the measured 4.1 tokens a
/// second is thirty seconds of generation. A call that is not generating by
/// second fifteen cannot finish, and letting it take the slot anyway would
/// spend AttackFM's time on an answer that is thrown away at second 45.
pub const ADMISSION_WAIT: Duration = Duration::from_secs(15);

/// Bytes of transcript per model call. See `chunks.rs` for why there are
/// chunks at all: about 1,500 tokens of text, plus the prompt, plus
/// `NUM_PREDICT`, sits inside the shared runner's 4,096-token context with
/// room to spare.
const CHUNK_BYTES: usize = 6_000;

/// Why a call produced nothing. Every one of these is a 503 on the wire.
#[derive(Debug)]
pub enum Failure {
    Unavailable(String),
    /// Not admitted: no first token inside `ADMISSION_WAIT`, so the runner was
    /// busy with somebody else's work and the call was withdrawn from the queue.
    Busy,
    TimedOut,
    Unusable(String),
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Failure::Unavailable(why) => write!(f, "the model is unavailable: {why}"),
            Failure::Busy => write!(f, "the model is busy with other work"),
            Failure::TimedOut => write!(f, "the model timed out"),
            Failure::Unusable(why) => write!(f, "the model returned an unusable answer: {why}"),
        }
    }
}

/// What Ollama reported about one call, summed across chunks.
#[derive(Debug, Default, Clone, Copy)]
pub struct Timing {
    /// From sending the request to its first token: queue wait, model load
    /// and prompt evaluation together, which is what the admission gate sees.
    pub first_ms: u64,
    pub prompt_tokens: u64,
    pub prompt_ms: u64,
    pub eval_tokens: u64,
    pub eval_ms: u64,
    pub load_ms: u64,
}

impl Timing {
    fn add(&mut self, other: Timing) {
        self.first_ms += other.first_ms;
        self.prompt_tokens += other.prompt_tokens;
        self.prompt_ms += other.prompt_ms;
        self.eval_tokens += other.eval_tokens;
        self.eval_ms += other.eval_ms;
        self.load_ms += other.load_ms;
    }
}

pub struct Outcome {
    pub annotations: Annotations,
    pub tally: Tally,
    pub timing: Timing,
    pub chunks: usize,
    /// How many chunks were annotated before the deadline. Equal to `chunks`
    /// unless a long note ran out of time - see `annotate`.
    pub completed: usize,
}

pub struct Ollama {
    http: reqwest::Client,
    base: String,
    model: String,
    thinking: tokio::sync::OnceCell<bool>,
    health: Mutex<Option<(Instant, bool)>>,
}

/// How long a health answer is reused. The health route is unauthenticated,
/// and without this every hit on it would be a request to Ollama.
const HEALTH_TTL: Duration = Duration::from_secs(10);

impl Ollama {
    pub fn new(base: &str, model: &str) -> Self {
        Self {
            http: reqwest::Client::builder()
                .connect_timeout(Duration::from_secs(3))
                .build()
                .expect("a reqwest client with no custom TLS always builds"),
            base: base.trim_end_matches('/').to_string(),
            model: model.to_string(),
            thinking: tokio::sync::OnceCell::new(),
            health: Mutex::new(None),
        }
    }

    pub fn model(&self) -> &str {
        &self.model
    }

    /// Whether Ollama answers and has this model pulled. Cached briefly.
    pub async fn reachable(&self) -> bool {
        if let Ok(guard) = self.health.lock() {
            if let Some((at, up)) = *guard {
                if at.elapsed() < HEALTH_TTL {
                    return up;
                }
            }
        }
        let up = async {
            let tags: Value = self
                .http
                .get(format!("{}/api/tags", self.base))
                .timeout(Duration::from_secs(3))
                .send()
                .await
                .ok()?
                .json()
                .await
                .ok()?;
            let pulled = tags["models"]
                .as_array()?
                .iter()
                .any(|m| m["name"].as_str() == Some(self.model.as_str()));
            Some(pulled)
        }
        .await
        .unwrap_or(false);
        if let Ok(mut guard) = self.health.lock() {
            *guard = Some((Instant::now(), up));
        }
        up
    }

    /// Whether the model is a reasoning model, asked once and remembered.
    ///
    /// Thinking is switched OFF for this job - the answer is a list of quoted
    /// phrases, and a reasoning model left to think spends hundreds of CPU
    /// tokens deliberating before it writes one. But `think: false` is only
    /// sent to models that report the capability: AttackFM's client found
    /// models that REFUSE the flag outright (ai.rs, on Qwen 2.5), and a request
    /// refused over an option that would have done nothing is a 503 for no
    /// reason.
    async fn thinks(&self, deadline: Instant) -> Result<bool, Failure> {
        self.thinking
            .get_or_try_init(|| async {
                let shown: Value = self
                    .http
                    .post(format!("{}/api/show", self.base))
                    .timeout(remaining(deadline)?)
                    .json(&json!({ "model": self.model }))
                    .send()
                    .await
                    .map_err(transport)?
                    .error_for_status()
                    .map_err(|e| Failure::Unavailable(e.to_string()))?
                    .json()
                    .await
                    .map_err(|e| Failure::Unavailable(e.to_string()))?;
                Ok(shown["capabilities"]
                    .as_array()
                    .is_some_and(|caps| caps.iter().any(|c| c.as_str() == Some("thinking"))))
            })
            .await
            .copied()
    }

    /// One chunk, streamed so that the first token can be waited for on its own.
    ///
    /// Streaming is not for the phone - it gets one JSON answer either way. It
    /// is because a non-streaming request is indistinguishable from outside
    /// between "queued behind AttackFM" and "generating", and only the second
    /// is worth the slot. Ollama writes the response headers with the first
    /// chunk, so `admission` covers the send AND the first line.
    async fn call(&self, chunk: &str, deadline: Instant, admission: Duration) -> Result<(Raw, Timing), Failure> {
        let mut body = prompt::chat(&self.model, chunk);
        if self.thinks(deadline).await? {
            body["think"] = json!(false);
        }
        let sent = Instant::now();
        let request = self
            .http
            .post(format!("{}/api/chat", self.base))
            .timeout(remaining(deadline)?)
            .json(&body)
            .send();
        let admit_by = (sent + admission).min(deadline);
        let first = tokio::time::timeout_at(tokio::time::Instant::from_std(admit_by), async {
            let mut response = request.await.map_err(transport)?;
            if !response.status().is_success() {
                let status = response.status();
                let detail = response.text().await.unwrap_or_default();
                return Err(Failure::Unavailable(format!("{status}: {}", detail.chars().take(200).collect::<String>())));
            }
            let mut buffer = Vec::new();
            while !buffer.contains(&b'\n') {
                match response.chunk().await.map_err(transport)? {
                    Some(bytes) => buffer.extend_from_slice(&bytes),
                    None => break,
                }
            }
            Ok((response, buffer))
        })
        .await;
        // Dropping the unfinished future above closes the connection, which is
        // what takes the request back out of Ollama's queue.
        let (mut response, mut buffer) = match first {
            Err(_) if admit_by >= deadline => return Err(Failure::TimedOut),
            Err(_) => return Err(Failure::Busy),
            Ok(result) => result?,
        };
        let first_ms = sent.elapsed().as_millis() as u64;

        let mut content = String::new();
        let mut last: Option<Value> = None;
        loop {
            while let Some(end) = buffer.iter().position(|b| *b == b'\n') {
                let line: Vec<u8> = buffer.drain(..=end).collect();
                if line.trim_ascii().is_empty() {
                    continue;
                }
                let event: Value = serde_json::from_slice(&line).map_err(|e| Failure::Unusable(e.to_string()))?;
                if let Some(error) = event["error"].as_str() {
                    return Err(Failure::Unavailable(error.to_string()));
                }
                if let Some(piece) = event["message"]["content"].as_str() {
                    content.push_str(piece);
                }
                if event["done"].as_bool() == Some(true) {
                    last = Some(event);
                }
            }
            if last.is_some() {
                break;
            }
            match response.chunk().await.map_err(transport)? {
                Some(bytes) => buffer.extend_from_slice(&bytes),
                None => break,
            }
        }
        let done = last.ok_or_else(|| Failure::Unusable("the stream ended without a final message".into()))?;
        let ms = |key: &str| done[key].as_u64().unwrap_or(0) / 1_000_000;
        let timing = Timing {
            first_ms,
            prompt_tokens: done["prompt_eval_count"].as_u64().unwrap_or(0),
            prompt_ms: ms("prompt_eval_duration"),
            eval_tokens: done["eval_count"].as_u64().unwrap_or(0),
            eval_ms: ms("eval_duration"),
            load_ms: ms("load_duration"),
        };
        // A reply cut off by NUM_PREDICT is half an array and will not parse;
        // saying so beats reporting it as a JSON syntax error at column 2,811.
        if done["done_reason"].as_str() == Some("length") {
            return Err(Failure::Unusable(format!("stopped at the {NUM_PREDICT}-token ceiling")));
        }
        let raw: Raw = serde_json::from_str(&content).map_err(|e| Failure::Unusable(e.to_string()))?;
        Ok((raw, timing))
    }
}

fn remaining(deadline: Instant) -> Result<Duration, Failure> {
    deadline
        .checked_duration_since(Instant::now())
        .filter(|left| !left.is_zero())
        .ok_or(Failure::TimedOut)
}

fn transport(e: reqwest::Error) -> Failure {
    if e.is_timeout() {
        Failure::TimedOut
    } else {
        Failure::Unavailable(e.to_string())
    }
}

/// The whole note, annotated and filtered, within `deadline`.
///
/// Chunks run one after another, never side by side, and each one passes the
/// admission gate on its own: AttackFM may have taken the runner back between
/// the first chunk and the second, and the second then waits its turn like
/// any other request rather than holding on to a slot it happened to have.
///
/// A note long enough to need several chunks can outlast the deadline. If the
/// FIRST chunk fails, the call fails - there is nothing to give. If a LATER
/// one does, what was already annotated is returned rather than thrown away:
/// the phone has formatted the whole note with its own rules already, so the
/// honest outcome is "the opening got the model's pass and the rest kept the
/// phone's", which is strictly better than a 503 that discards finished work.
/// The log line records it as partial.
pub async fn annotate(ollama: &Ollama, text: &str, deadline: Instant, admission: Duration) -> Result<Outcome, Failure> {
    let pieces = chunks(text, CHUNK_BYTES);
    let mut outcome = Outcome {
        annotations: Annotations::default(),
        tally: Tally::default(),
        timing: Timing::default(),
        chunks: pieces.len(),
        completed: 0,
    };
    for piece in pieces {
        if piece.trim().is_empty() {
            outcome.completed += 1;
            continue;
        }
        match ollama.call(piece, deadline, admission).await {
            Ok((raw, timing)) => {
                let (annotations, tally) = shape::shape(piece, raw);
                shape::merge(&mut outcome.annotations, annotations);
                outcome.tally.add(tally);
                outcome.timing.add(timing);
                outcome.completed += 1;
            }
            Err(failure) if outcome.completed == 0 => return Err(failure),
            Err(_) => break,
        }
    }
    Ok(outcome)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format::fake_ollama::{fake_ollama, stream_of};

    const NOTE: &str = "I need to call the plumber on Friday. Buy eggs, milk and bread.";

    #[tokio::test]
    async fn a_call_still_queued_at_the_admission_gate_is_withdrawn_as_busy() {
        let (base, _) = fake_ollama(false, Duration::from_secs(10), stream_of("{}", "stop")).await;
        let ollama = Ollama::new(&base, "test");
        let started = Instant::now();
        let result = annotate(&ollama, NOTE, started + Duration::from_secs(10), Duration::from_millis(300)).await;
        assert!(matches!(result, Err(Failure::Busy)), "{:?}", result.err());
        assert!(started.elapsed() < Duration::from_secs(2), "withdrawn at the gate, not at the deadline");
    }

    #[tokio::test]
    async fn a_gate_that_would_outlast_the_deadline_is_a_timeout() {
        let (base, _) = fake_ollama(false, Duration::from_secs(10), stream_of("{}", "stop")).await;
        let ollama = Ollama::new(&base, "test");
        let result = annotate(&ollama, NOTE, Instant::now() + Duration::from_millis(300), Duration::from_secs(5)).await;
        assert!(matches!(result, Err(Failure::TimedOut)), "{:?}", result.err());
    }

    #[tokio::test]
    async fn a_streamed_answer_is_assembled_filtered_and_timed() {
        let answer = r#"{"title":"Plumber and shopping","emphasis":["Friday","Saturday"],"tasks":["call the plumber"],"lists":[{"intro":"Buy","items":["eggs","milk","bread"]}],"sections":[]}"#;
        let (base, seen) = fake_ollama(true, Duration::from_millis(50), stream_of(answer, "stop")).await;
        let ollama = Ollama::new(&base, "test");
        let outcome = annotate(&ollama, NOTE, Instant::now() + Duration::from_secs(5), Duration::from_secs(2)).await.unwrap();
        assert_eq!(outcome.annotations.title.as_deref(), Some("Plumber and shopping"));
        assert_eq!(outcome.annotations.emphasis, vec!["Friday"], "Saturday was never said");
        assert_eq!(outcome.annotations.lists[0].items, vec!["eggs", "milk", "bread"]);
        assert_eq!(outcome.tally.dropped, 1);
        assert_eq!((outcome.timing.prompt_tokens, outcome.timing.eval_tokens, outcome.timing.eval_ms), (640, 90, 22_000));
        assert!(outcome.timing.first_ms >= 50);

        let body = seen.lock().unwrap()[0].clone();
        assert_eq!(body["think"], json!(false), "a thinking model is told not to");
        assert_eq!(body["stream"], json!(true));
        assert!(body["options"].get("num_ctx").is_none(), "a load option would reload AttackFM's runner");
        assert!(body.get("keep_alive").is_none());
    }

    #[tokio::test]
    async fn think_is_not_sent_to_a_model_without_it() {
        let (base, seen) = fake_ollama(false, Duration::ZERO, stream_of("{}", "stop")).await;
        let ollama = Ollama::new(&base, "test");
        annotate(&ollama, NOTE, Instant::now() + Duration::from_secs(5), Duration::from_secs(2)).await.unwrap();
        assert!(seen.lock().unwrap()[0].get("think").is_none());
    }

    #[tokio::test]
    async fn a_reply_cut_off_at_the_ceiling_is_unusable_not_a_parse_error() {
        let (base, _) = fake_ollama(false, Duration::ZERO, stream_of(r#"{"title":"Plum"#, "length")).await;
        let ollama = Ollama::new(&base, "test");
        let result = annotate(&ollama, NOTE, Instant::now() + Duration::from_secs(5), Duration::from_secs(2)).await;
        assert!(matches!(&result, Err(Failure::Unusable(why)) if why.contains("ceiling")), "{:?}", result.err());
    }

    #[test]
    fn a_past_deadline_is_a_timeout_not_a_zero_length_request() {
        assert!(matches!(remaining(Instant::now() - Duration::from_secs(1)), Err(Failure::TimedOut)));
        assert!(remaining(Instant::now() + Duration::from_secs(5)).is_ok());
    }
}
