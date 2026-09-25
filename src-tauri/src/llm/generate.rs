//! One generation on a loaded model: the conversation framed and tokenised, a
//! context that fits made or kept, the fixed prefix restored from its snapshot
//! or decoded and snapshotted, the note decoded, and the answer sampled a
//! token at a time with its thinking closed if it runs past its budget.
//!
//! Every count is checked here before it reaches C++, which throws on bad
//! input and cannot be caught (the engine's header).

use std::num::NonZeroU32;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;

use llama_cpp_2::context::params::LlamaContextParams;
use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::llama_backend::LlamaBackend;
use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::{AddBos, LlamaChatMessage, LlamaModel};
use llama_cpp_2::sampling::LlamaSampler;
use llama_cpp_2::token::LlamaToken;
use llama_cpp_2::{LlamaStateSeqFlags, SeqState};

use super::job::{threads, Failure, Job, Output, Phase, ProgressFn, MAX_CONTEXT_TOKENS, MAX_OUTPUT_TOKENS};
use super::prompt;
use super::report::{Counts, Reporter};

/// Contexts are made in steps of this many tokens, so two notes of nearly the
/// same length share one context rather than remaking it.
const CONTEXT_STEP: u32 = 512;

/// The smallest context worth making.
const MIN_CONTEXT_TOKENS: u32 = 1024;

/// Prompt tokens decoded per `llama_decode` call. Small enough that
/// cancellation and the progress bar move within about a second on a phone
/// (llama-cpp-2 exposes no abort hook, so a call cannot be interrupted), large
/// enough that the matrix kernels still batch. Also the ubatch size, which
/// sizes the compute buffer: 128 keeps it far below the ~500 MB that 512 took.
const CHUNK: usize = 128;

/// The sampling that keeps a rewrite faithful. Close to greedy: a rewrite has
/// few right answers and heat only adds ways to drift. A mild repeat penalty
/// over the recent window, because greedy decoding of a long answer is how a
/// small model falls into a loop.
const TOP_K: i32 = 40;
const TOP_P: f32 = 0.9;
const MIN_P: f32 = 0.05;
const REPEAT_LAST_N: i32 = 256;
const REPEAT_PENALTY: f32 = 1.05;
const SEED: u32 = 42;

/// The prompt prefix already decoded, and the state that decoding left.
pub(super) struct Snapshot {
    tokens: Vec<LlamaToken>,
    state: SeqState,
}

/// The window a job needs: its prompt, the most it may write, a little slack,
/// rounded up to a step - capped by the window the model was trained on
/// (`n_ctx_train`), and never under the smallest worth making.
fn context_for(prompt_tokens: u32, max_tokens: u32, n_ctx_train: u32) -> u32 {
    let need = prompt_tokens + max_tokens + 16;
    let stepped = need.div_ceil(CONTEXT_STEP) * CONTEXT_STEP;
    stepped.clamp(MIN_CONTEXT_TOKENS, MAX_CONTEXT_TOKENS.min(n_ctx_train.max(MIN_CONTEXT_TOKENS)))
}

/// The window a job runs in and the most it may write there, or the refusal
/// the page shows when its prompt leaves no room to answer. `max_tokens` is
/// already held to [`MAX_OUTPUT_TOKENS`]; `closing_room` is what a thought
/// closed for the model adds to the answer.
fn window(prompt_tokens: u32, max_tokens: u32, closing_room: u32, n_ctx_train: u32) -> Result<(u32, u32), Failure> {
    let n_ctx = context_for(prompt_tokens, max_tokens + closing_room, n_ctx_train);
    if prompt_tokens + 64 > n_ctx {
        return Err(Failure::Error(format!(
            "This note is too long to format on the phone: {prompt_tokens} tokens of prompt, and the window is {n_ctx}. Try a shorter note, or split it."
        )));
    }
    // The most the model may write inside this window.
    Ok((n_ctx, max_tokens.min(n_ctx - prompt_tokens - 8 - closing_room)))
}

/// Whether a context kept from the last job, `have` tokens long, is made again
/// for one that needs `need`: when it is too small, or more than twice the size
/// and big enough that the memory is worth giving back to the phone.
fn needs_remake(have: u32, need: u32) -> bool {
    have < need || (have > need * 2 && have > 2 * MIN_CONTEXT_TOKENS)
}

/// One job run on `model`, in the context kept in `ctx_slot` (made, or made
/// again bigger, as the job needs) and with the prefix kept in `snapshot`.
#[allow(clippy::too_many_arguments)]
pub(super) fn generate<'m>(
    backend: &'static LlamaBackend,
    model: &'m LlamaModel,
    ctx_slot: &mut Option<LlamaContext<'m>>,
    snapshot: &mut Option<Snapshot>,
    job: &mut Job,
    report: &mut Reporter,
    counts: &mut Counts,
    started: Instant,
    load_ms: u64,
) -> Result<Output, Failure> {
    let request = &job.request;
    let cancelled = || job.cancel.load(Ordering::Relaxed);
    let error = |what: &str, e: &dyn std::fmt::Display| Failure::Error(format!("{what}: {e}"));

    // Frame the conversation and tokenize the two halves separately, so the
    // prefix's tokens are the same run to run whatever the note is.
    let template = model.chat_template(None).map_err(|e| error("the model has no chat template", &e))?;
    let thinks = model
        .meta_val_str("tokenizer.chat_template")
        .map(|source| source.contains("<think>"))
        .unwrap_or(false);
    let messages = [
        LlamaChatMessage::new("system".into(), prompt::system_text(&request.system, request.context.as_deref()))
            .map_err(|e| error("the system prompt", &e))?,
        LlamaChatMessage::new("user".into(), prompt::SENTINEL.into()).map_err(|e| error("the note", &e))?,
    ];
    let rendered = model
        .apply_chat_template(&template, &messages, true)
        .map_err(|e| error("cannot apply the chat template", &e))?;
    // An empty thought switches reasoning off; a request that wants it gets none.
    let framed = prompt::frame(&rendered, thinks && !request.think).map_err(Failure::Error)?;
    counts.thinking = thinks && request.think;
    let prefix = model
        .str_to_token(&framed.prefix, AddBos::Never)
        .map_err(|e| error("cannot tokenize the prompt", &e))?;
    let rest = model
        .str_to_token(&format!("{}{}", request.prompt, framed.suffix), AddBos::Never)
        .map_err(|e| error("cannot tokenize the note", &e))?;

    let max_tokens = request.max_tokens.clamp(1, MAX_OUTPUT_TOKENS);
    counts.prompt_tokens = (prefix.len() + rest.len()) as u32;
    // A thought closed for the model adds its closing words to the window.
    let closing_room = if request.think && request.think_budget > 0 { 64 } else { 0 };
    let (n_ctx, max_tokens) = window(counts.prompt_tokens, max_tokens, closing_room, model.n_ctx_train())?;

    // A context that fits, made or remade.
    let remake = match ctx_slot.as_ref() {
        Some(ctx) => needs_remake(ctx.n_ctx(), n_ctx),
        None => true,
    };
    if remake {
        *ctx_slot = None;
        let params = LlamaContextParams::default()
            .with_n_ctx(NonZeroU32::new(n_ctx))
            .with_n_batch(CHUNK as u32)
            .with_n_ubatch(CHUNK as u32)
            .with_n_threads(threads())
            .with_n_threads_batch(threads());
        let ctx = model
            .new_context(backend, params)
            .map_err(|e| error(&format!("cannot make a {n_ctx}-token context"), &e))?;
        *ctx_slot = Some(ctx);
    }
    let ctx = ctx_slot.as_mut().expect("a context was just ensured");

    // Prefill: the immutable system/template prefix from its snapshot when it
    // matches, else decoded and snapshotted; then the per-job user remainder.
    // This clear is the session boundary: generated tokens and the previous
    // request's user text leave the live KV before any snapshot is restored.
    // The snapshot is captured before `rest`, so it cannot contain an earlier
    // utterance (prompt.rs tests that boundary).
    let prefill_started = Instant::now();
    ctx.clear_kv_cache();
    let mut batch = LlamaBatch::new(CHUNK, 1);
    let mut cached_tokens = 0;
    let restored = match snapshot.as_ref() {
        Some(saved) if saved.tokens == prefix => ctx.state_seq_set(&saved.state, 0).is_ok(),
        _ => false,
    };
    if restored {
        cached_tokens = prefix.len() as u32;
        counts.prompt_tokens_done = cached_tokens;
    } else {
        *snapshot = None;
        ctx.clear_kv_cache();
        decode_prompt(ctx, &mut batch, &prefix, 0, false, &job.cancel, &mut job.progress, report, counts, prefill_started)?;
        if let Ok(state) = ctx.state_seq_get(0, LlamaStateSeqFlags::empty()) {
            *snapshot = Some(Snapshot { tokens: prefix.clone(), state });
        }
    }
    decode_prompt(ctx, &mut batch, &rest, prefix.len(), true, &job.cancel, &mut job.progress, report, counts, prefill_started)?;
    let prefill_ms = prefill_started.elapsed().as_millis() as u64;

    // Generate. A command grammar is compiled from this binary's allowlist,
    // never from web input. Free-form formatting keeps its existing sampler.
    let mut sampler = if let Some(grammar) = request.grammar {
        let grammar = LlamaSampler::grammar(model, grammar, "root")
            .map_err(|e| error("cannot compile the command grammar", &e))?;
        LlamaSampler::chain_simple([grammar, LlamaSampler::greedy()])
    } else if request.temperature <= 0.0 {
        LlamaSampler::chain_simple([
            LlamaSampler::penalties(model.n_vocab(), REPEAT_LAST_N, REPEAT_PENALTY, 0.0, 0.0),
            LlamaSampler::greedy(),
        ])
    } else {
        LlamaSampler::chain_simple([
            LlamaSampler::penalties(model.n_vocab(), REPEAT_LAST_N, REPEAT_PENALTY, 0.0, 0.0),
            LlamaSampler::top_k(TOP_K),
            LlamaSampler::top_p(TOP_P, 1),
            LlamaSampler::min_p(MIN_P, 1),
            LlamaSampler::temp(request.temperature),
            LlamaSampler::dist(SEED),
        ])
    };
    let generate_started = Instant::now();
    let mut decoder = encoding_rs::UTF_8.new_decoder();
    let mut text = String::new();
    let mut logits_at = batch.n_tokens() - 1;
    let mut position = (prefix.len() + rest.len()) as i32;
    let mut truncated = false;
    // Still inside the thought (only when thinking is on), and whether it was closed for the model.
    let mut in_thought = counts.thinking;
    counts.tokens_per_second = 0.0;
    report.send(&mut job.progress, Phase::Generating, *counts, Some(String::new()));
    loop {
        if cancelled() {
            return Err(Failure::Cancelled);
        }
        if counts.output_tokens >= max_tokens {
            truncated = true;
            break;
        }
        let token = sampler.sample(ctx, logits_at);
        if model.is_eog_token(token) {
            break;
        }
        let piece = model
            .token_to_piece(token, &mut decoder, false, None)
            .map_err(|e| error("cannot decode a token", &e))?;
        text.push_str(&piece);
        counts.output_tokens += 1;
        counts.tokens_per_second = counts.output_tokens as f32 / generate_started.elapsed().as_secs_f32().max(1e-3);
        report.tick(&mut job.progress, Phase::Generating, *counts, &text);
        if in_thought && text.contains("</think>") {
            in_thought = false;
        }

        batch.clear();
        batch.add(token, position, &[0], true).map_err(|e| error("cannot queue a token", &e))?;
        position += 1;
        // A thought past its budget is closed in the model's own voice, and the
        // answer is sampled after the close as if the model had written it.
        let over_budget = in_thought && request.think_budget > 0 && counts.output_tokens >= request.think_budget;
        if over_budget {
            in_thought = false;
            let cutoff = model
                .str_to_token(prompt::THOUGHT_CUTOFF, AddBos::Never)
                .map_err(|e| error("cannot tokenize the thought's close", &e))?;
            for (i, closing) in cutoff.iter().enumerate() {
                batch.add(*closing, position, &[0], i + 1 == cutoff.len()).map_err(|e| error("cannot queue a token", &e))?;
                position += 1;
            }
            text.push_str(prompt::THOUGHT_CUTOFF);
        }
        ctx.decode(&mut batch).map_err(|e| error("decoding failed", &e))?;
        logits_at = batch.n_tokens() - 1;
    }

    Ok(Output {
        text,
        prompt_tokens: counts.prompt_tokens,
        output_tokens: counts.output_tokens,
        ms: started.elapsed().as_millis() as u64,
        cached_tokens,
        prefill_ms,
        load_ms,
        tokens_per_second: counts.tokens_per_second,
        truncated,
        thinking: counts.thinking,
    })
}

/// Decodes `tokens` at `offset` in chunks, reporting prefill progress as it
/// goes, and asks for logits only at the last token when `logits_for_last`.
#[allow(clippy::too_many_arguments)]
fn decode_prompt(
    ctx: &mut LlamaContext<'_>,
    batch: &mut LlamaBatch,
    tokens: &[LlamaToken],
    offset: usize,
    logits_for_last: bool,
    cancel: &AtomicBool,
    progress: &mut ProgressFn,
    report: &mut Reporter,
    counts: &mut Counts,
    prefill_started: Instant,
) -> Result<(), Failure> {
    for (index, chunk) in tokens.chunks(CHUNK).enumerate() {
        if cancel.load(Ordering::Relaxed) {
            return Err(Failure::Cancelled);
        }
        batch.clear();
        let base = offset + index * CHUNK;
        let last_chunk = (index + 1) * CHUNK >= tokens.len();
        for (i, token) in chunk.iter().enumerate() {
            let logits = logits_for_last && last_chunk && i + 1 == chunk.len();
            batch
                .add(*token, (base + i) as i32, &[0], logits)
                .map_err(|e| Failure::Error(format!("cannot queue the prompt: {e}")))?;
        }
        ctx.decode(batch).map_err(|e| Failure::Error(format!("prefill failed: {e}")))?;
        counts.prompt_tokens_done += chunk.len() as u32;
        counts.tokens_per_second = counts.prompt_tokens_done as f32 / prefill_started.elapsed().as_secs_f32().max(1e-3);
        report.tick(progress, Phase::Prefill, *counts, "");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A training window wider than any context the engine makes.
    const WIDE: u32 = 32_768;

    #[test]
    fn a_context_is_the_job_rounded_up_to_a_step() {
        assert_eq!(context_for(1000, 100, WIDE), 1536, "1,116 tokens is three steps");
        assert_eq!(context_for(2000, 32, WIDE), 2048, "2,048 exactly is four steps, not five");
        assert_eq!(context_for(2000, 33, WIDE), 2560);
    }

    #[test]
    fn a_context_is_never_under_the_smallest_nor_over_the_largest() {
        assert_eq!(context_for(10, 10, WIDE), MIN_CONTEXT_TOKENS, "a short note still gets a whole small context");
        assert_eq!(context_for(8000, 4096, WIDE), MAX_CONTEXT_TOKENS);
    }

    #[test]
    fn a_context_is_capped_by_the_window_the_model_was_trained_on() {
        assert_eq!(context_for(4000, 1000, 4096), 4096);
        assert_eq!(context_for(10, 10, 512), MIN_CONTEXT_TOKENS, "a model trained on less than the smallest still gets the smallest");
        assert_eq!(context_for(4000, 1000, 512), MIN_CONTEXT_TOKENS);
    }

    #[test]
    fn a_prompt_that_leaves_under_64_tokens_of_the_window_is_refused() {
        assert_eq!(window(8128, 1, 0, WIDE), Ok((8192, 1)), "64 tokens left is room enough");
        let Err(Failure::Error(refusal)) = window(8129, 1, 0, WIDE) else { panic!("63 tokens left is refused") };
        assert_eq!(
            refusal,
            "This note is too long to format on the phone: 8129 tokens of prompt, and the window is 8192. Try a shorter note, or split it."
        );
        assert!(window(4040, 100, 0, 4096).is_err(), "the model's own window is the one a prompt must fit");
    }

    #[test]
    fn the_answer_is_held_to_the_room_the_window_has_left() {
        assert_eq!(window(1000, 100, 0, WIDE), Ok((1536, 100)), "a window made for the job leaves room for all of it");
        assert_eq!(window(8000, 4096, 0, WIDE), Ok((8192, 184)), "a capped window leaves what it can, less 8 of slack");
        assert_eq!(window(8000, 4096, 64, WIDE), Ok((8192, 120)), "and a thought's close takes its share first");
        assert_eq!(window(1000, 100, 64, WIDE).map(|(n_ctx, _)| n_ctx), Ok(1536), "which the window is made with room for");
        assert_eq!(window(1400, 100, 64, WIDE).map(|(n_ctx, _)| n_ctx), Ok(2048));
    }

    #[test]
    fn a_kept_context_is_made_again_only_when_too_small_or_far_too_big() {
        assert!(needs_remake(1024, 1536), "too small for the job");
        assert!(!needs_remake(1536, 1536), "exactly the size");
        assert!(!needs_remake(4096, 2048), "twice the size is kept");
        assert!(needs_remake(4608, 2048), "more than twice is given back");
        assert!(needs_remake(8192, 3072));
        assert!(!needs_remake(2048, 1000), "a context that is small anyway is kept, however much bigger");
    }
}
