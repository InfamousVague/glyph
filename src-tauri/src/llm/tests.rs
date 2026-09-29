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
    crate::lock::lock(&SERIAL)
}

fn chosen() -> &'static LlmSpec {
    let id = std::env::var("GLYPH_LLM_MODEL").unwrap_or_else(|_| model::DEFAULT.id.to_string());
    model::find(&id).unwrap_or_else(|| panic!("GLYPH_LLM_MODEL={id} is not in the catalogue"))
}

fn model_path() -> Option<PathBuf> {
    // A model file outside the catalogue, to measure one before it is offered: `GLYPH_LLM_FILE=Qwen3.5-0.8B-Q4_K_M.gguf`.
    if let Ok(file) = std::env::var("GLYPH_LLM_FILE") {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../models/llm").join(file);
        return path.exists().then_some(path);
    }
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
    page_prompt_in("format/prompt.ts", name)
}

/// The repository, or `GLYPH_REPO_DIR` - for a test binary pushed to a phone or an emulator, where the path this crate
/// was compiled at doesn't exist (as whisper's tests take `GLYPH_MODELS_DIR`). Only the page files the prompts are
/// read from need to be there.
fn repo_dir() -> PathBuf {
    std::env::var_os("GLYPH_REPO_DIR").map(PathBuf::from).unwrap_or_else(|| Path::new(env!("CARGO_MANIFEST_DIR")).join(".."))
}

/// A prompt from any page file under `src/app/`, by the name of its `String.raw` constant.
fn page_prompt_in(file: &str, name: &str) -> String {
    let source = std::fs::read_to_string(repo_dir().join("src/app").join(file))
        .unwrap_or_else(|_| panic!("{file} is in the repository"));
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
        grammar: None,
        background: false,
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
    assert!(prompt.starts_with("You are the editor inside Ghost.md"), "{prompt:.80}");
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

/// A meeting's write-up is a background job on the same worker: a page
/// request that arrives while one runs preempts it (`guards::abort_with("busy")`
/// on the flag every background job watches), and is served next rather than
/// behind the whole piece.
#[test]
fn a_foreground_request_preempts_a_background_job_and_is_served_next() {
    let _one = serial();
    let _flags = crate::lock::lock(&crate::guards::TEST_SERIAL);
    let Some(path) = model_path() else { return };
    crate::guards::clear_abort();
    let (loading, loaded) = std::sync::mpsc::channel();
    let mut background = request("write-up:n1:piece-1", &page_prompt("RECORDING_NOTES_PROMPT"), &"We talked about the launch and the venue and the press list. ".repeat(120), 200);
    background.background = true;
    let piece = engine().generate(&path, background, crate::guards::abort_jobs(), move |progress| {
        let _ = loading.send(progress.phase);
    });
    // Sent once the background job is in hand: from its load on, it counts as running.
    assert_eq!(loaded.recv().ok(), Some(Phase::Loading));
    let page = engine().generate(&path, request("page", &page_system_prompt(), SPOKEN, 16), Arc::default(), |_| {});
    assert_eq!(piece.recv().expect("the piece answers"), Err(Failure::Cancelled));
    assert_eq!(crate::guards::abort_reason(), "busy", "and says why, so the write-up holds uncounted");
    assert!(page.recv().expect("the page's request answers").is_ok());
    crate::guards::clear_abort();
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

/// The write-up's compiled-in prompts (write_up.rs) are the page's, word for word: a fresh install whose page has
/// not written `jobs/config.json` yet must write the same summary the page would ask for. No model needed.
#[test]
fn the_write_ups_compiled_in_prompts_are_the_pages() {
    use crate::write_up::{fill, prompts, thousands};
    assert_eq!(prompts::SUMMARY, page_prompt("RECORDING_SUMMARY_PROMPT"));
    assert_eq!(prompts::NOTES, page_prompt("RECORDING_NOTES_PROMPT"));
    let piece = page_prompt("PIECE_CONTEXT");
    assert_eq!(prompts::PIECE, piece);
    assert_eq!(fill(&piece, &[("n", "2"), ("m", "5")]), "Part 2 of 5 of one recording.");
    let parts = page_prompt("NOTES_CONTEXT");
    assert_eq!(prompts::PARTS, parts);
    assert!(fill(&parts, &[("words", &thousands(41_230))]).contains("41,230"));
    assert_eq!(thousands(41_230), "41,230");
}

/// The recording's summary (RECORDING_SUMMARY_PROMPT) over a meeting with two other speakers: only the recorder's
/// own actions ("I need to write the release notes") get a box, and Priya's and Tom's never do.
#[test]
fn recording_summary_boxes_only_the_recorders_own_actions() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let budget = crate::write_up::summary_budget(MEETING.len());
    let (result, _) = run(&path, request("meeting", &page_prompt("RECORDING_SUMMARY_PROMPT"), MEETING, budget), Arc::default(), |_| {});
    let output = result.expect("a generation");
    let text = output.text.trim();
    eprintln!("{text}");
    assert!(text.starts_with('#'), "starts with a heading:\n{text}");
    let boxed: Vec<&str> = text.lines().filter(|l| l.trim_start().starts_with("- [ ]")).collect();
    assert!(!boxed.is_empty(), "the recorder's own actions are boxed:\n{text}");
    let lower = |l: &&str| l.to_lowercase();
    assert!(boxed.iter().map(lower).any(|l| l.contains("release notes") || l.contains("demo room") || l.contains("keys")), "the I lines:\n{text}");
    for line in boxed.iter().map(lower) {
        assert!(!line.contains("priya") && !line.contains("tom"), "another person's action is never boxed:\n{text}");
    }
}

/// The notes on one piece (RECORDING_NOTES_PROMPT): items and nothing else.
#[test]
fn recording_notes_are_items_only() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let prompt = format!("{}\n\n{MEETING}", crate::write_up::fill(crate::write_up::prompts::PIECE, &[("n", "1"), ("m", "3")]));
    let budget = crate::write_up::notes_budget(MEETING.len());
    let (result, _) = run(&path, request("notes", &page_prompt("RECORDING_NOTES_PROMPT"), &prompt, budget), Arc::default(), |_| {});
    let output = result.expect("a generation");
    let text = output.text.trim();
    eprintln!("{text}");
    let lines: Vec<&str> = text.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    assert!(!lines.is_empty());
    for line in &lines {
        assert!(line.starts_with("- "), "an item, nothing else:\n{text}");
    }
    assert!(lines.len() <= 12, "at most twelve:\n{text}");
}

/// The review prompt the page sends after a recording (src/app/review/prompt.ts).
fn review_prompt() -> String {
    page_prompt_in("review/prompt.ts", "REVIEW_PROMPT")
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

/// The command pass (src/app/capture/understand.ts): what the phone's models make of spoken commands the rules miss,
/// as speech recognition wrote them, and how long each takes. Scored against what the command asked for; printed,
/// not asserted, because this is the measurement a model is chosen by.
///
///   GLYPH_LLM_MODEL=qwen3.5-2b cargo test --release --lib llm::tests::understands_spoken_commands -- --ignored --nocapture
///   GLYPH_LLM_FILE=Qwen3.5-0.8B-Q4_K_M.gguf cargo test --release --lib llm::tests::understands_spoken_commands -- --ignored --nocapture
#[test]
#[ignore]
fn understands_spoken_commands() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let system = page_prompt_in("capture/understand.ts", "COMMAND_PROMPT");
    let titles = ["Groceries", "HelloTrade launch", "AttackFM bug bash", "Weekend trip", "Work", "Reading list"];
    let notes = titles.iter().map(|t| format!("- {t}")).collect::<Vec<_>>().join("\n");
    // What was said after the keyword, and what it asks for: the action, and the note (empty when none).
    let cases: [(&str, &str, &str); 24] = [
        ("Add eggs to my groceries.", "add", "Groceries"),
        ("Add X to my grocery list.", "add", "Groceries"),
        ("Put oat milk on the shopping list.", "add", "Groceries"),
        ("Can you stick bread in groceries", "add", "Groceries"),
        ("Put call Sam on the work list.", "add", "Work"),
        ("Put all some of the work list.", "add", "Work"),
        ("Add a task to hello trade launch, ship the pricing page.", "add", "HelloTrade launch"),
        ("New to do for the attack FM bug bash. The login button is broken.", "add", "AttackFM bug bash"),
        ("Add the Dune books to my reading list.", "add", "Reading list"),
        ("For the weekend trip note, book the ferry.", "add", "Weekend trip"),
        ("Remember in the trip note to pack the tent.", "add", "Weekend trip"),
        ("Switch to my groceries.", "switch", "Groceries"),
        ("Go to the hello trade note.", "switch", "HelloTrade launch"),
        ("Carry on in work.", "switch", "Work"),
        ("Move this to the weekend trip.", "switch", "Weekend trip"),
        ("New note.", "new", ""),
        ("New load.", "new", ""),
        ("Start a fresh note.", "new", ""),
        ("Add a table to the bug bash with columns bug, owner and status.", "table", "AttackFM bug bash"),
        ("Make a table.", "table", ""),
        ("Add eggs to my holiday plans.", "none", ""),
        ("The weather is lovely today.", "none", ""),
        ("What time is it?", "none", ""),
        ("Switch to the garden note.", "none", ""),
    ];
    let (mut right, mut total_ms) = (0, 0u128);
    for (words, want, note) in cases {
        let started = std::time::Instant::now();
        let mut req = request("command", &system, &format!("Notes:\n{notes}\n\nCommand: {words}"), 96);
        req.temperature = 0.0;
        let (result, _) = run(&path, req, Arc::default(), |_| {});
        let ms = started.elapsed().as_millis();
        total_ms += ms;
        let text = result.map(|o| o.text).unwrap_or_else(|e| format!("error: {e}"));
        let answer = text.trim().replace('\n', " ");
        let action_ok = answer.contains(&format!("\"action\":\"{want}\"")) || answer.contains(&format!("\"action\": \"{want}\""));
        let note_ok = note.is_empty() || answer.contains(&format!("\"{note}\""));
        let ok = action_ok && note_ok;
        if ok {
            right += 1;
        }
        println!("{} {ms:>5} ms  {words:<62} {answer}", if ok { "ok  " } else { "MISS" });
    }
    println!("\n{right}/{} right, {:.0} ms mean", cases.len(), total_ms as f64 / cases.len() as f64);
}


// ---- blanks the AI fills (docs/DESIGN.md §145, 16.2) --------------------------------------------------------------

/// The fill bar's cases as the page builds them: every case's messages at each rung, the prompts by their names, and
/// what the answers must hold (src/app/ai/fills.fixture.json, written and kept equal to the builder by
/// src/app/ai/fills/message.test.ts). So what the Mac measures is what the phone sends, today's date line included.
fn fills_fixture() -> serde_json::Value {
    let text = std::fs::read_to_string(repo_dir().join("src/app/ai/fills.fixture.json")).expect("the fills fixture is in the repository");
    serde_json::from_str(&text).expect("the fills fixture is JSON")
}

/// A fill's system prompt from its names, joined as the page joins the third rung's core and block.
fn fill_system(names: &serde_json::Value) -> String {
    names.as_array().expect("prompt names").iter().map(|name| page_prompt_in("ai/fills/prompts.ts", name.as_str().expect("a name"))).collect::<Vec<_>>().join("\n\n")
}

/// `[N] words`, a space after the bracket, as src/app/ai/fills/read.ts reads an answer line.
fn fill_line(line: &str) -> Option<(usize, String)> {
    let rest = line.trim_start().strip_prefix('[')?;
    let close = rest.find(']')?;
    if close == 0 || close > 2 {
        return None;
    }
    let n = rest[..close].parse().ok()?;
    let after = rest[close + 1..].strip_prefix(' ')?;
    Some((n, after.trim().to_string()))
}

/// A generation's answers by the case's own blank numbers: its `[N]` lines, or with one blank asked, a bare answer.
fn fill_answers(text: &str, blanks: &[usize]) -> std::collections::HashMap<usize, Vec<String>> {
    let mut out: std::collections::HashMap<usize, Vec<String>> = blanks.iter().map(|b| (*b, Vec::new())).collect();
    let mut numbered = false;
    for line in text.lines() {
        if let Some((n, words)) = fill_line(line) {
            numbered = true;
            if let Some(blank) = blanks.get(n.wrapping_sub(1)) {
                if !words.is_empty() {
                    out.entry(*blank).or_default().push(words);
                }
            }
        }
    }
    if !numbered && blanks.len() == 1 {
        out.insert(blanks[0], text.lines().map(str::trim).filter(|l| !l.is_empty()).map(str::to_string).collect());
    }
    out
}

/// An item as a person reads it: a list's mark, a box, a step's number and quotes off.
fn fill_item(line: &str) -> String {
    let mut t = line.trim();
    for lead in ["- [ ] ", "- [x] ", "- ", "* "] {
        if let Some(rest) = t.strip_prefix(lead) {
            t = rest;
        }
    }
    let figures = t.chars().take_while(char::is_ascii_digit).count();
    if figures > 0 && t[figures..].starts_with(". ") {
        t = &t[figures + 2..];
    }
    t.trim_matches(|c| c == '"' || c == '“' || c == '”').trim_end_matches('.').trim().to_string()
}

/// One generation as it came back.
struct FillRun {
    text: String,
    blanks: Vec<usize>,
    prompt_tokens: u32,
    cached_tokens: u32,
    output_tokens: u32,
    ms: u64,
    truncated: bool,
}

/// Runs one case's generations at one rung, one after another, as the page's queue would.
fn run_fill_case(path: &Path, case: &serde_json::Value, rung: &str) -> Vec<FillRun> {
    case["rungs"][rung]
        .as_array()
        .expect("generations")
        .iter()
        .map(|generation| {
            let blanks: Vec<usize> = generation["blanks"].as_array().unwrap().iter().map(|b| b.as_u64().unwrap() as usize).collect();
            let mut req = request("fill", &fill_system(&generation["system"]), generation["prompt"].as_str().unwrap(), generation["max_tokens"].as_u64().unwrap() as u32);
            req.temperature = 0.0;
            let (result, _) = run(path, req, Arc::default(), |_| {});
            match result {
                Ok(output) => FillRun { text: output.text, blanks, prompt_tokens: output.prompt_tokens, cached_tokens: output.cached_tokens, output_tokens: output.output_tokens, ms: output.ms, truncated: output.truncated },
                Err(failure) => FillRun { text: format!("ERROR {failure:?}"), blanks, prompt_tokens: 0, cached_tokens: 0, output_tokens: 0, ms: 0, truncated: false },
            }
        })
        .collect()
}

/// What a case's answers came to against the bar: whether every expectation held, whether every line was an `[N]`
/// line for an asked blank, and what missed.
fn judge_fill_case(case: &serde_json::Value, runs: &[FillRun]) -> (bool, bool, Vec<String>) {
    let mut answers: std::collections::HashMap<usize, Vec<String>> = std::collections::HashMap::new();
    for run in runs {
        for (blank, lines) in fill_answers(&run.text, &run.blanks) {
            answers.entry(blank).or_default().extend(lines);
        }
    }
    let mut misses = Vec::new();
    let texts = |v: &serde_json::Value| -> Vec<String> { v.as_array().map(|a| a.iter().filter_map(|s| s.as_str().map(str::to_lowercase)).collect()).unwrap_or_default() };
    for expect in case["expect"].as_array().unwrap() {
        let blank = expect["blank"].as_u64().unwrap() as usize;
        let lines = answers.get(&blank).cloned().unwrap_or_default();
        let first = lines.first().cloned().unwrap_or_default();
        let lower = lines.join(" / ").to_lowercase();
        let is_unknown = first.trim_start().to_uppercase().starts_with("UNKNOWN");
        let items: Vec<String> = lines.iter().map(|l| fill_item(l)).filter(|l| !l.is_empty()).collect();
        let any = texts(&expect["any"]);
        if !any.is_empty() && !any.iter().any(|w| lower.contains(w.as_str())) {
            misses.push(format!("blank {blank} holds none of {any:?}: {first:?}"));
        }
        let none = texts(&expect["none"]);
        if expect.get("items").is_some() {
            let wanted = expect["items"].as_u64().unwrap() as usize;
            let new: Vec<&String> = items.iter().filter(|i| !none.contains(&i.to_lowercase())).collect();
            if new.len() < wanted {
                misses.push(format!("blank {blank} gave {} new items of {wanted}: {items:?}", new.len()));
            }
        } else if none.iter().any(|w| lower.contains(w.as_str())) {
            misses.push(format!("blank {blank} holds one of {none:?}: {first:?}"));
        }
        match expect.get("unknown").and_then(serde_json::Value::as_bool) {
            Some(true) if !is_unknown => misses.push(format!("blank {blank} is not UNKNOWN: {first:?}")),
            Some(false) if is_unknown || first.is_empty() => misses.push(format!("blank {blank} is UNKNOWN or empty: {first:?}")),
            _ => {}
        }
        if let Some(range) = expect.get("words").and_then(serde_json::Value::as_array) {
            let (low, high) = (range[0].as_u64().unwrap() as usize, range[1].as_u64().unwrap() as usize);
            let count = first.split_whitespace().count();
            if count < low || count > high {
                misses.push(format!("blank {blank} has {count} words: {first:?}"));
            }
        }
        if expect.get("title").is_some() && (first.contains('#') || first.trim_end().ends_with('.')) {
            misses.push(format!("blank {blank} is no title: {first:?}"));
        }
    }
    let raw_none = texts(&case["raw_none"]);
    for run in runs {
        for line in run.text.lines().map(str::trim) {
            if raw_none.iter().any(|lead| line.to_lowercase().starts_with(lead.as_str())) {
                misses.push(format!("a line carries on the note's own list: {line:?}"));
            }
            if line.contains("{?") {
                misses.push(format!("an answer holds a blank: {line:?}"));
            }
        }
    }
    if case["in_order"].as_bool() == Some(true) {
        let order: Vec<usize> = runs.iter().flat_map(|r| r.text.lines().filter_map(fill_line).map(|(n, _)| n).collect::<Vec<_>>()).collect();
        if order.windows(2).any(|w| w[0] > w[1]) {
            misses.push(format!("the answers came out of order: {order:?}"));
        }
    }
    let numbered = runs.iter().all(|run| run.text.lines().filter(|l| !l.trim().is_empty()).all(|l| fill_line(l).is_some_and(|(n, _)| n >= 1 && n <= run.blanks.len())));
    (misses.is_empty(), numbered, misses)
}

/// A catalogue model's file, when it is on this Mac, for the tests that go through every model present.
fn present_model(spec: &LlmSpec) -> Option<PathBuf> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../models/llm").join(spec.spec.file);
    std::fs::metadata(&path).is_ok_and(|m| m.len() == spec.spec.bytes).then_some(path)
}

#[test]
fn the_fill_prompts_read_from_the_page() {
    let prompt = page_prompt_in("ai/fills/prompts.ts", "FILL_PROMPT");
    assert!(prompt.starts_with("You fill blanks in a note"), "{prompt:.80}");
    assert!(prompt.ends_with("(ohayō gozaimasu)"), "{prompt}");
    assert!(prompt.contains("UNKNOWN") && !prompt.contains("Never invent"), "{prompt}");
    let web = page_prompt_in("ai/fills/prompts.ts", "FILL_WEB_PROMPT");
    assert!(web.starts_with("You fill one blank in a note") && web.ends_with("[1] Rain showers, 18 to 24 °C"), "{web}");
    for name in ["FILL_CORE", "FILL_ANSWER", "FILL_NUMBER", "FILL_TITLE", "FILL_SUMMARY", "FILL_ITEMS", "FILL_CELL", "FILL_TRANSLATE"] {
        let block = page_prompt_in("ai/fills/prompts.ts", name);
        assert!(!block.is_empty(), "{name} is read");
        if name != "FILL_CORE" {
            assert!(block.contains("Example."), "{name} carries its worked example");
        }
    }
    // Every case names prompts the page has, at every rung.
    let fixture = fills_fixture();
    for case in fixture["cases"].as_array().unwrap().iter().chain(fixture["eye"].as_array().unwrap()) {
        for rung in ["1", "2", "3"] {
            for generation in case["rungs"][rung].as_array().unwrap() {
                assert!(!fill_system(&generation["system"]).is_empty());
                assert!(generation["prompt"].as_str().unwrap().starts_with("Today is Monday 28 September 2026."));
            }
        }
    }
}

/// The bar, on the chosen model (`GLYPH_LLM_MODEL`, the 4B by default) at the rung the page ships for it: every case of
/// the fixture holds, and at the first rung every line is an `[N]` line for an asked blank.
#[test]
fn fills_answer_in_their_shapes() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let fixture = fills_fixture();
    let rung = fixture["rungs"][chosen().id].as_u64().unwrap_or(2).to_string();
    let mut failed = Vec::new();
    for case in fixture["cases"].as_array().unwrap() {
        let runs = run_fill_case(&path, case, &rung);
        let (content, numbered, misses) = judge_fill_case(case, &runs);
        let shown: Vec<String> = runs.iter().map(|r| r.text.trim().replace('\n', " / ")).collect();
        eprintln!("{} rung {rung} {:<16} {}{} {:?}", chosen().id, case["name"].as_str().unwrap(), if content { "ok" } else { "MISS" }, if rung == "1" && !numbered { " (not all [N] lines)" } else { "" }, shown);
        if !content || (rung == "1" && !numbered) {
            failed.push(format!("{}: {misses:?} {shown:?}", case["name"]));
        }
    }
    let binds = fixture["binds"].as_array().is_some_and(|ids| ids.iter().any(|id| id.as_str() == Some(chosen().id)));
    if !binds {
        eprintln!("{} met the bar at no rung when it was measured, so it is printed, not held: {} missed", chosen().id, failed.len());
        return;
    }
    assert!(failed.is_empty(), "{} at rung {rung} missed the bar:\n{}", chosen().id, failed.join("\n"));
    // What the room counts the prompt as (FILL_PROMPT_TOKENS) is within 5% of what this model reads, and never under it.
    let mut probe = request("fill-tokens", &page_prompt_in("ai/fills/prompts.ts", "FILL_PROMPT"), "Answer blank 1.", 48);
    probe.temperature = 0.0;
    let real = run(&path, probe, Arc::default(), |_| {}).0.expect("a generation").prompt_tokens;
    let counted = fixture["prompt_tokens"].as_u64().unwrap() as u32;
    assert!(counted >= real && counted <= real + real / 20, "FILL_PROMPT_TOKENS is {counted}, the prompt reads as {real}");
}

/// Every model on this Mac at all three rungs, printed with the prompt's tokens, what was restored and the time, and
/// the rung each earns: the first when every case holds and every line is `[N]`, else the second when every case holds,
/// else the third. How `FILL_RUNGS` and `FILL_PROMPT_TOKENS` are chosen (docs/DESIGN.md §145, 5.8). Run with the
/// machine quiet:
///
///   cargo test --lib llm::tests::fills_rungs_compared -- --ignored --nocapture
#[test]
#[ignore]
fn fills_rungs_compared() {
    let _one = serial();
    let fixture = fills_fixture();
    let only = std::env::var("GLYPH_FILL_MODELS").ok();
    let mut table = Vec::new();
    for spec in model::CATALOGUE.iter() {
        if only.as_deref().is_some_and(|ids| !ids.split(',').any(|id| id == spec.id)) {
            continue;
        }
        let Some(path) = present_model(spec) else {
            println!("SKIPPED: {} is not on this Mac", spec.id);
            continue;
        };
        // What the prompt costs as this model reads it, its chat template included.
        let mut probe = request("fill-tokens", &page_prompt_in("ai/fills/prompts.ts", "FILL_PROMPT"), "Answer blank 1.", 48);
        probe.temperature = 0.0;
        let tokens = run(&path, probe, Arc::default(), |_| {}).0.map(|o| o.prompt_tokens).unwrap_or(0);
        println!("\n===== {}: FILL_PROMPT with a four-word message is {tokens} tokens =====", spec.id);
        let mut verdicts = Vec::new();
        for rung in ["1", "2", "3"] {
            let (mut all_content, mut all_numbered, mut ms, mut generations) = (true, true, 0u64, 0usize);
            for case in fixture["cases"].as_array().unwrap() {
                let runs = run_fill_case(&path, case, rung);
                let (content, numbered, misses) = judge_fill_case(case, &runs);
                all_content &= content;
                all_numbered &= numbered;
                generations += runs.len();
                for run in &runs {
                    ms += run.ms;
                    println!(
                        "{} r{rung} {:<16} {:>6} ms  pt {:>4} (cached {:>4}) out {:>3}{}  {}",
                        spec.id,
                        case["name"].as_str().unwrap(),
                        run.ms,
                        run.prompt_tokens,
                        run.cached_tokens,
                        run.output_tokens,
                        if run.truncated { " TRUNC" } else { "" },
                        run.text.trim().replace('\n', " / ")
                    );
                }
                if !content || !numbered {
                    println!("      {} {misses:?}{}", if content { "ok" } else { "MISS" }, if numbered { "" } else { " (not all [N] lines)" });
                }
            }
            println!("  {} rung {rung}: every case {}, every line [N] {}, {generations} generations, {ms} ms", spec.id, if all_content { "holds" } else { "does NOT hold" }, if all_numbered { "yes" } else { "no" });
            verdicts.push((all_content, all_numbered));
        }
        // The web's answers (ai/fills/web.ts): the model writes from what a source returned, or says UNKNOWN.
        let mut web_right = 0;
        let web = fixture["web"].as_array().unwrap();
        for case in web {
            let runs = run_fill_case(&path, case, "1");
            let (content, _, misses) = judge_fill_case(case, &runs);
            web_right += usize::from(content);
            for run in &runs {
                println!("{} web {:<16} {:>6} ms  pt {:>4} (cached {:>4})  {}  {}", spec.id, case["name"].as_str().unwrap(), run.ms, run.prompt_tokens, run.cached_tokens, if content { "ok  " } else { "MISS" }, run.text.trim().replace('\n', " / "));
            }
            if !content {
                println!("      {misses:?}");
            }
        }
        println!("  {} web: {web_right} of {} right", spec.id, web.len());
        let earns = if verdicts[0].0 && verdicts[0].1 {
            1
        } else if verdicts[1].0 {
            2
        } else {
            3
        };
        table.push(format!("{:<12} tokens {tokens:>4}  rung 1 holds {} and numbered {}, rung 2 holds {}, rung 3 holds {}: earns rung {earns}", spec.id, verdicts[0].0, verdicts[0].1, verdicts[1].0, verdicts[2].0));
    }
    println!("\n===== the rungs =====\n{}", table.join("\n"));
}

/// Every eye case (the spec's scenarios and a press of five blanks) on the chosen model at its rung (or
/// `GLYPH_FILL_RUNG`), with timings, for DESIGN:
///
///   GLYPH_LLM_MODEL=qwen3.5-4b cargo test --lib llm::tests::prints_fills -- --ignored --nocapture
#[test]
#[ignore]
fn prints_fills_for_the_eye() {
    let _one = serial();
    let Some(path) = model_path() else { return };
    let fixture = fills_fixture();
    let rung = std::env::var("GLYPH_FILL_RUNG").unwrap_or_else(|_| fixture["rungs"][chosen().id].as_u64().unwrap_or(2).to_string());
    for (case, rung) in fixture["eye"].as_array().unwrap().iter().map(|c| (c, rung.as_str())).chain(fixture["web"].as_array().unwrap().iter().map(|c| (c, "1"))) {
        for run in run_fill_case(&path, case, rung) {
            println!(
                "{} r{rung} {:<18} {:>6} ms  pt {:>4} (cached {:>4}) out {:>3}{}  {}",
                chosen().id,
                case["name"].as_str().unwrap(),
                run.ms,
                run.prompt_tokens,
                run.cached_tokens,
                run.output_tokens,
                if run.truncated { " TRUNC" } else { "" },
                run.text.trim().replace('\n', " / ")
            );
        }
    }
}
