//! The engine against a real model, with the page's real prompt.
//!
//! Needs a model in `models/llm/` (the same files `llm::model::CATALOGUE`
//! pins; `node scripts/fetch-model.mjs llm` puts them there), and says plainly
//! when one is missing rather than passing by doing nothing. The system prompt
//! is read out of src/app/format/prompt.ts, so what is measured here is what
//! the phone sends.
//!
//! `GLYPH_LLM_MODEL` picks the model by id (default: the catalogue's default),
//! so the same tests measure every candidate:
//!
//!   GLYPH_LLM_MODEL=qwen3.5-2b cargo test --lib llm::tests -- --nocapture
//!
//! The tests share one engine - loading gigabytes per test would be most of the
//! suite's time - and run one at a time under [`SERIAL`], because the prefix
//! snapshot is one slot and a test that proves reuse cannot have another
//! test's prompt land between its two runs.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use super::engine::{Failure, Llm, Output, Phase, Progress, Request, MAX_CONTEXT_TOKENS};
use super::model::{self, LlmSpec};

static SERIAL: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    SERIAL.lock().unwrap_or_else(|p| p.into_inner())
}

fn chosen() -> &'static LlmSpec {
    let id = std::env::var("GLYPH_LLM_MODEL").unwrap_or_else(|_| model::DEFAULT.id.to_string());
    model::find(&id).unwrap_or_else(|| panic!("GLYPH_LLM_MODEL={id} is not in the catalogue"))
}

fn model_path() -> Option<PathBuf> {
    let spec = chosen();
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../models/llm").join(spec.spec.file);
    let present = std::fs::metadata(&path).is_ok_and(|m| m.len() == spec.spec.bytes);
    if !present {
        eprintln!("SKIPPED: {} is not in models/llm/ - `node scripts/fetch-model.mjs llm` to test the engine", spec.spec.file);
    }
    present.then_some(path)
}

fn engine() -> &'static Llm {
    static ENGINE: OnceLock<Llm> = OnceLock::new();
    ENGINE.get_or_init(Llm::start)
}

/// The system prompt the page sends, from the page's source.
fn page_system_prompt() -> String {
    page_prompt("SYSTEM_PROMPT")
}

/// One of the page's prompts (src/app/format/prompt.ts), by the name of its
/// `String.raw` constant, so what the Mac measures is what the phone sends.
fn page_prompt(name: &str) -> String {
    let source = std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/app/format/prompt.ts"))
        .expect("prompt.ts is in the repository");
    // The declaration, not the docblock's mention of `String.raw` above it.
    let opener = format!("{name} = String.raw`");
    let start = source.find(&opener).unwrap_or_else(|| panic!("{name} is a String.raw literal")) + opener.len();
    let end = start + source[start..].find('`').expect("the literal closes");
    source[start..end].trim().to_string()
}

/// A spoken note as the recorder writes it: cues applied, no other shape.
const SPOKEN: &str = "# Weekend plans\n\nok so this weekend I need to call the plumber about the leaking kitchen tap before thursday because it's getting worse. also remember to buy oat milk fresh bread eggs and coffee on the way home. the quarterly report for northwind is due next monday morning so I should block friday afternoon for it\n\nalso talked to sam about the cabin, we're thinking the second week of october, she'll check with her brother about the dates and I need to book the ferry once we know";

fn request(id: &str, system: &str, note: &str, max_tokens: u32) -> Request {
    Request {
        id: id.to_string(),
        system: system.to_string(),
        context: None,
        prompt: note.to_string(),
        max_tokens,
        temperature: 0.3,
        think: false,
        think_budget: 0,
    }
}

/// Runs `request` to the end, returning its result and every progress event.
fn run(path: &Path, request: Request, cancel: Arc<AtomicBool>, mut on: impl FnMut(&Progress) + Send + 'static) -> (Result<Output, Failure>, Vec<Progress>) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let sink = Arc::clone(&events);
    let answer = engine().generate(path, request, cancel, move |progress| {
        on(&progress);
        sink.lock().unwrap().push(progress);
    });
    let result = answer.recv().expect("the engine answers");
    let events = std::mem::take(&mut *events.lock().unwrap());
    (result, events)
}

#[test]
fn the_prompt_read_from_the_page_is_the_prompt() {
    let prompt = page_system_prompt();
    assert!(prompt.starts_with("You are the editor inside Glyph"), "{prompt:.80}");
    assert!(prompt.ends_with("no code fence around it."), "{prompt}");
}

#[test]
fn rewrites_a_spoken_note_as_markdown_keeping_its_facts() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let (result, events) = run(&path, request("rewrite", &page_system_prompt(), SPOKEN, 1024), Arc::default(), |_| {});
    let output = result.expect("a generation");
    eprintln!(
        "\n===== {} : {} prompt tokens ({} cached), {} out in {} ms (prefill {} ms, load {} ms), {:.1} tok/s =====\n{}\n=====",
        chosen().id, output.prompt_tokens, output.cached_tokens, output.output_tokens, output.ms, output.prefill_ms, output.load_ms, output.tokens_per_second, output.text
    );

    // Every fact that matters has to survive the rewrite, whatever its shape.
    let text = output.text.to_lowercase();
    for fact in ["plumber", "thursday", "oat milk", "northwind", "monday", "sam", "october", "ferry"] {
        assert!(text.contains(fact), "the rewrite lost {fact:?}:\n{}", output.text);
    }
    // And it is a markdown note, not a chat: a heading, no preamble, no fence.
    assert!(output.text.trim_start().starts_with('#'), "starts with a heading:\n{}", output.text);
    assert!(!output.text.contains("```"), "no code fence:\n{}", output.text);
    assert!(!output.truncated);

    // The events told the story in order and ended on the whole text.
    assert!(events.iter().all(|e| e.id == "rewrite"));
    let phases: Vec<Phase> = events.iter().map(|e| e.phase).fold(Vec::new(), |mut seen, phase| {
        if seen.last() != Some(&phase) {
            seen.push(phase);
        }
        seen
    });
    assert_eq!(phases.last(), Some(&Phase::Done), "{phases:?}");
    let prefill = phases.iter().position(|p| *p == Phase::Prefill);
    let generating = phases.iter().position(|p| *p == Phase::Generating);
    assert!(prefill.is_some() && prefill < generating, "{phases:?}");
    let done = events.last().unwrap();
    assert_eq!(done.partial, output.text);
    // The text arrived as it was written, not all at the end.
    let streamed = events.iter().filter(|e| e.phase == Phase::Generating && !e.partial.is_empty()).count();
    assert!(streamed > 3, "{streamed} streaming reports");
}

/// A typed developer note: terse, with a code name, a URL and a list mid-sentence.
const TYPED: &str = "glyph formatter todo\n- streaming looks laggy on the fold, maybe batch the progress events to 100ms\n- when the note has an image the model dropped the ![](image/9f2a.jpg) line last time, check the prompt\n- ask sam if the 9b is worth it on 12gb\n- settings: model picker needs sizes, download progress, remove\nrelease as 0.9.0 apk not ota because gen 10\nlink https://attack.fm/glyph/install.html";

/// A meeting, spoken: several people, decisions, dates.
const MEETING: &str = "ok standup with priya and tom. priya says the export bug is fixed and it's in review, should land tuesday. tom is blocked on the api keys for the staging box, I said I'd get them to him today. we agreed to move the launch to the 24th because the store review takes a week. priya wants to add dark mode before launch, tom thinks it can wait, we'll decide friday. I need to write the release notes and book the demo room for the 24th at 2";

/// Prints the rewrite of each sample so the prompt can be judged by eye:
/// `cargo test --lib llm::tests::prints -- --ignored --nocapture`.
#[test]
#[ignore]
fn prints_sample_rewrites_for_the_eye() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    for (name, note) in [("spoken", SPOKEN), ("typed", TYPED), ("meeting", MEETING)] {
        let (result, _) = run(&path, request(name, &page_system_prompt(), note, 1024), Arc::default(), |_| {});
        let output = result.expect("a generation");
        eprintln!(
            "\n===== {} / {name}: {} out in {} ms, {:.1} tok/s{} =====\n{}\n=====",
            chosen().id, output.output_tokens, output.ms, output.tokens_per_second, if output.truncated { " TRUNCATED" } else { "" }, output.text
        );
    }
}

#[test]
fn a_second_run_with_the_same_prefix_restores_it_and_answers_the_same() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    // A system prompt no other test uses, so the first run cannot find it cached.
    let system = format!("{} (snapshot test)", page_system_prompt());
    let (first, _) = run(&path, request("first", &system, "call the plumber tomorrow", 40), Arc::default(), |_| {});
    let (second, _) = run(&path, request("second", &system, "call the plumber tomorrow", 40), Arc::default(), |_| {});
    let (first, second) = (first.unwrap(), second.unwrap());

    assert_eq!(first.cached_tokens, 0);
    assert!(second.cached_tokens > 0, "{second:?}");
    assert_eq!(first.prompt_tokens, second.prompt_tokens);
    assert_eq!(first.text, second.text, "a restored prefix must answer exactly as a decoded one");
    eprintln!(
        "prefix snapshot: {} of {} prompt tokens restored; prefill {} ms -> {} ms",
        second.cached_tokens, second.prompt_tokens, first.prefill_ms, second.prefill_ms
    );
}

#[test]
fn cancelling_during_prefill_stops_the_run_and_says_cancelled() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let cancel = Arc::new(AtomicBool::new(false));
    let flag = Arc::clone(&cancel);
    // Long enough to take several prefill chunks.
    let long = request("cancel", &page_system_prompt(), &"A sentence about the project. ".repeat(160), 50);
    let (result, events) = run(&path, long, cancel, move |progress| {
        if progress.phase == Phase::Prefill {
            flag.store(true, Ordering::Relaxed);
        }
    });
    assert_eq!(result, Err(Failure::Cancelled));
    assert_eq!(events.last().map(|e| e.phase), Some(Phase::Cancelled));
    assert!(events.iter().all(|e| e.phase != Phase::Generating), "{events:?}");
}

#[test]
fn a_prompt_over_the_window_is_refused_before_any_prefill() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let huge = request("huge", &page_system_prompt(), &"A sentence that goes on. ".repeat(MAX_CONTEXT_TOKENS as usize / 2), 100);
    let (result, events) = run(&path, huge, Arc::default(), |_| {});
    let Err(Failure::Error(message)) = result else { panic!("{result:?}") };
    assert!(message.contains("too long"), "{message}");
    assert!(events.iter().all(|e| e.phase != Phase::Prefill), "{events:?}");
}

#[test]
fn max_tokens_stops_a_run_and_says_so() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let (result, _) = run(&path, request("short", &page_system_prompt(), SPOKEN, 12), Arc::default(), |_| {});
    let output = result.expect("a generation");
    assert_eq!(output.output_tokens, 12);
    assert!(output.truncated);
}

/// A link goes through the model as a token (src/app/format/links.ts): the
/// page swaps `[words](https://…)` for `[words](link-1)` and back. This is
/// the half the page cannot test alone: that the model copies the token.
#[test]
fn keeps_a_link_token_where_it_was() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let note = "ok so tomorrow I need to call the dentist before ten and [buy milk](link-1) on the way home, and check <link-2> for the parcel";
    let (result, _) = run(&path, request("link", &page_system_prompt(), note, 512), Arc::default(), |_| {});
    let output = result.expect("a generation");
    let text = output.text.to_lowercase();
    assert!(text.contains("link-1"), "the markdown link's token survives:\n{}", output.text);
    assert!(text.contains("link-2"), "the bare link's token survives:\n{}", output.text);
    assert!(!text.contains("http"), "no address is invented:\n{}", output.text);
    eprintln!("{}", output.text);
}


/// Summarize (SUMMARIZE_PROMPT): far fewer words, a heading first, and the
/// facts that matter still there.
#[test]
fn summarizes_a_note_to_a_fraction_keeping_its_facts() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let (result, _) = run(&path, request("summary", &page_prompt("SUMMARIZE_PROMPT"), SPOKEN, 512), Arc::default(), |_| {});
    let output = result.expect("a generation");
    let text = output.text.trim();
    eprintln!("{text}");
    assert!(text.starts_with('#'), "starts with a heading:\n{text}");
    assert!(text.len() < SPOKEN.len() * 3 / 4, "shorter than the note ({} of {} chars):\n{text}", text.len(), SPOKEN.len());
    let lower = text.to_lowercase();
    // The things to do and their whens; a summary may let a second-order
    // detail go (the report's own due date behind "block Friday for it").
    for fact in ["plumber", "thursday", "northwind", "friday", "ferry"] {
        assert!(lower.contains(fact), "keeps {fact}:\n{text}");
    }
}

/// Enhance (ENHANCE_PROMPT): at least as long as the note, every fact kept,
/// and nothing the note does not give.
#[test]
fn enhances_a_note_keeping_every_fact() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let (result, _) = run(&path, request("enhance", &page_prompt("ENHANCE_PROMPT"), SPOKEN, 1024), Arc::default(), |_| {});
    let output = result.expect("a generation");
    let text = output.text.trim();
    eprintln!("{text}");
    assert!(text.starts_with('#'), "starts with a heading:\n{text}");
    assert!(text.len() >= SPOKEN.len() * 3 / 4, "not shorter than the note ({} of {} chars):\n{text}", text.len(), SPOKEN.len());
    let lower = text.to_lowercase();
    for fact in ["plumber", "tap", "thursday", "oat milk", "bread", "eggs", "coffee", "northwind", "monday", "friday", "sam", "cabin", "october", "brother", "ferry"] {
        assert!(lower.contains(fact), "keeps {fact}:\n{text}");
    }
    assert!(!output.truncated, "had room to finish");
}


/// A table goes through the model as one picture-shaped line, `![table-1](table)`
/// (src/app/format/tables.ts), and comes back as the block. The page cannot
/// test the model's half: that it copies the line and draws no table of its
/// own. (A bare `[table-1]` was dropped as noise, prompt or no prompt.)
#[test]
fn keeps_a_table_token_on_its_own_line() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let note = "bug bash notes from friday, here's what we found\n\n![table-1](table)\n\nnext round is monday, sam owns the login one";
    let (result, _) = run(&path, request("table", &page_system_prompt(), note, 512), Arc::default(), |_| {});
    let output = result.expect("a generation");
    let text = output.text.to_lowercase();
    assert!(text.lines().any(|l| l.trim() == "![table-1](table)"), "the token is on its own line:\n{}", output.text);
    assert!(!text.contains("|--") && !text.contains("| --"), "no table of its own:\n{}", output.text);
    eprintln!("{}", output.text);
}

/// The review prompt the page sends after a recording (src/app/review/prompt.ts).
fn review_prompt() -> String {
    let source = std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/app/review/prompt.ts"))
        .expect("review/prompt.ts is in the repository");
    let opener = "REVIEW_PROMPT = String.raw`";
    let start = source.find(opener).expect("REVIEW_PROMPT is a String.raw literal") + opener.len();
    let end = start + source[start..].find('`').expect("the literal closes");
    source[start..end].trim().to_string()
}

/// A take as the review sees it: the fast model misheard "seek" and "HelloTrade",
/// and one command put an item in this note when it was meant for HelloTrade.
const REVIEW_TAKE: &str = "WHAT THE FAST SPEECH MODEL HEARD:\nBug bash on Friday. Fix the seat bar on two devices. Glyph, add update the readme to hello trade. Yes. Downloads get stuck on the discover list.\n\nWHAT THE SLOWER, MORE ACCURATE SPEECH MODEL HEARD:\nBug bash on Friday. Fix the seek bar on two devices. Glyph, add update the readme to HelloTrade. Yes. Downloads get stuck on the discover list.\n\nWHERE THEY DISAGREE (fast → slower):\n- …Friday. Fix the [seat → seek] bar on two…\n- …the readme to [hello trade. → HelloTrade.] Yes. Downloads…\n\nCOMMANDS THAT RAN:\n- Added “Update the readme” to Bug bash's list\n\nTHE PERSON'S NOTE TITLES:\nHelloTrade · Glyph Notes · Places to Go · Bug bash\n\nOTHER NOTE A COMMAND CHANGED, \"HelloTrade\":\n# HelloTrade\n\n- Ship the APK\n\nTHIS NOTE, \"Bug bash\", AS SAVED:\n# Bug bash on Friday\n\n- [ ] Fix the seat bar on two devices\n- [ ] Update the readme\n- [ ] Downloads get stuck on the discover list";

/// The review with thinking on, judged by eye:
/// `cargo test --lib llm::tests::prints_a_review -- --ignored --nocapture`.
#[test]
#[ignore]
fn prints_a_review_with_its_thinking() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let mut req = request("review", &review_prompt(), REVIEW_TAKE, 1400);
    req.think = true;
    req.think_budget = 700;
    let (result, events) = run(&path, req, Arc::default(), |_| {});
    let output = result.expect("a review");
    assert!(output.thinking, "Qwen's template thinks, and thinking was asked for");
    assert!(events.iter().any(|e| e.thinking), "progress says the stream starts with thinking");
    eprintln!(
        "\n===== {} / review: {} out in {} ms, {:.1} tok/s{} =====\n{}\n=====",
        chosen().id, output.output_tokens, output.ms, output.tokens_per_second, if output.truncated { " TRUNCATED" } else { "" }, output.text
    );
    let answer = output.text.split("</think>").nth(1).expect("the thinking closes before the answer");
    assert!(answer.trim_start().starts_with('[') || answer.contains("```"), "the answer is the findings array: {answer}");
}


/// An item's mark (src/app/core/itemLinks.ts) goes through the model as
/// `[notion](link-1)` at the end of its item; the page can put a lost one
/// back, but the model keeping it in place is the half the page cannot test.
#[test]
fn keeps_an_item_mark_at_the_end_of_its_item() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let note = "ok so tomorrow I need to call the dentist before ten\n\n- [ ] buy milk on the way home [notion](link-1)\n- [ ] pick up the parcel from the post office";
    let (result, _) = run(&path, request("mark", &page_system_prompt(), note, 512), Arc::default(), |_| {});
    let output = result.expect("a generation");
    let marked: Vec<&str> = output.text.lines().filter(|l| l.to_lowercase().contains("[notion](link-1)")).collect();
    eprintln!("{}", output.text);
    assert_eq!(marked.len(), 1, "the mark is on one line:\n{}", output.text);
    let line = marked[0].trim();
    assert!(line.starts_with("- ") || line.starts_with("* ") || line.chars().next().is_some_and(|c| c.is_ascii_digit()), "on a list item:\n{line}");
    assert!(line.to_lowercase().ends_with("[notion](link-1)") || line.to_lowercase().ends_with("[notion](link-1)."), "at its end:\n{line}");
    assert!(line.to_lowercase().contains("milk"), "on the milk item:\n{line}");
}

/// The gist (GIST_PROMPT): the one line under a note's title in the list.
/// One line, a dozen words, no markdown.
#[test]
fn gists_a_note_in_one_short_line() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let (result, _) = run(&path, request("gist", &page_prompt("GIST_PROMPT"), SPOKEN, 40), Arc::default(), |_| {});
    let output = result.expect("a generation");
    let text = output.text.trim();
    eprintln!("{text}");
    let first = text.lines().next().unwrap_or("").trim();
    assert!(!first.is_empty(), "says something");
    assert!(first.split_whitespace().count() <= 14, "a dozen words or so:\n{text}");
    assert!(!first.starts_with('#') && !first.starts_with('-'), "no markdown:\n{text}");
    let lower = first.to_lowercase();
    assert!(lower.contains("plumber") || lower.contains("weekend") || lower.contains("cabin") || lower.contains("report"), "about the note:\n{text}");
}
