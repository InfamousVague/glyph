# The engines on the device

_Whisper and llama.cpp run inside the app, behind two thin seams. What each one is, how its model arrives verified, and how the page drives it._

## Two engines, two seams

`src-tauri/src/whisper/` and `src-tauri/src/llm/` hold not one `tauri::` type. Each takes plain slices, paths and callbacks, so a process with no Tauri in it could drive it. The seams that know they are inside an app are `capture_commands.rs` and `ai_commands.rs`. They resolve directories, hold state, and turn engine events into `app.emit`. Both have a `shutdown` that `lib.rs` calls on exit, because a C++ decode still running while static destructors run is a crash at quit.

There is one ggml. whisper.cpp and llama.cpp both vendor it, and two copies in one library link without error and crash at run time. `src-tauri/vendor/whisper-rs-sys` builds whisper.cpp against the ggml of `llama-cpp-2`, which `src-tauri/Cargo.toml` pins exactly, at `=0.1.156`, for that reason.

iOS builds neither engine. In `src-tauri/Cargo.toml`, `whisper-rs`, `llama-cpp-2`, `reqwest` and `sha2` sit under `[target.'cfg(not(target_os = "ios"))'.dependencies]`. The pure halves still compile there (`vad`, `stream`, `text`, `wav`, both catalogues, `llm/prompt.rs`, `llm/command.rs`, `llm/device.rs`, `llm/hardware.rs`), and every command keeps its name and refuses through `unsupported.rs`, so the page is written against one surface.

## Whisper: a live model and a careful one

`whisper/model.rs` is the catalogue. `ACTIVE` is the model the app captures with, and changing it is one line.

| Model | Size | Word errors, clean / noisy | Used for |
|---|---|---|---|
| base.en q5_1 | 59.7 MB | 10.0% / 11.0% | Live capture (`ACTIVE`) |
| small.en q5_1 | 190 MB | 6.1% / 7.0% | Better words after Done (`REFINE`) |

The rates were measured on 73 LibriSpeech dev-clean clips, clean and with pink noise (`whisper::tests::accuracy`). small.en streams at 0.21x real time on the arm64 emulator, so it cannot keep up with speech, but it goes over a 59 s recording in 11.9 s there. large-v3-turbo scored 3.6% and took 54 s for the same minute. DESIGN §22 has the rest.

The live model stays loaded for the life of the process. The refine model is loaded for one pass and dropped. [[From microphone to Markdown]] has the streaming rules and the VAD.

`whisper/tests.rs` hears synthesised speech. It makes its fixture with macOS `say` and `afconvert`, so no audio is committed, and checks the key words, the commits landing in the pauses, and silence producing nothing. Without the model in `models/` (`npm run fetch:model`) each test prints `SKIPPED` and passes, so a green run proves nothing about Whisper unless the file is there. The benchmark, the cue-vocabulary run and the accuracy run are `#[ignore]`, and run by hand.

## One verified download

Both catalogues go through `model_files.rs`. Its one promise is in its header: a file at a model's real name has been verified. A download writes `<name>.part`, hashes every byte with SHA-256 as it arrives, and renames only on a match. So `status` can answer "present" from the name and size, without hashing gigabytes every time it is asked.

A cut connection is picked up with a `Range` request, up to eight times from the last byte that arrived. A server that answers with the whole file again starts the hash over. An HTTP error, such as a 404, is not retried on that mirror. The timeouts are for connecting (15 s) and for reading (30 s), never for the whole transfer. Progress is reported at most once per 1%.

The mirrors are tried in order. The hash is pinned in the binary, so the order is about reliability, never about trust.

| Order | Mirror |
|---|---|
| 1 | Any a signed update manifest has moved the app to (`ota::services`) |
| 2 | `https://attack.fm/glyph/models` |
| 3 | Hugging Face: at a pinned revision for the language models, at `resolve/main` for Whisper's |

`model_downloads.rs` is the Tauri half. It holds a gate for the whole download, so two taps on Get are one download. Each seam has its own gate (`fetching` and `fetching_refine` in `CaptureState`, `fetching` in `AiState`), so a voice model and a language model can download at the same time. The page checks Local only before it asks for any download.

## llm/: the catalogue

`llm/model.rs` lists four GGUFs, all Q4_K_M and all Apache-2.0. The names a person reads are `MODELS` in `src/app/core/ai.ts`, keyed by the same ids. [[The models on your phone]] is the user's view.

| Id | Size | Note |
|---|---|---|
| `qwen3.5-2b` | 1.28 GB | Quick; the fallback for voice commands |
| `qwen3.5-4b` | 2.74 GB | The default (`DEFAULT`) |
| `qwen3.5-9b` | 5.68 GB | The most careful; wants 12 GB of memory |
| `gemma-4-e4b` | 4.98 GB | A different voice; runs like a 4B |

## A generation

`llm/engine.rs` is one worker thread, `glyph-llm`. It loads a model for the first job, keeps it for every job naming the same file, and drops it after five idle minutes, an unload, or a job for another file. Jobs arrive on a channel, so a second generation waits for the first. No layers go to a GPU. Generation takes between two and six threads.

`llm/generate.rs` runs one job:

- **The context is sized to the job**: the prompt plus the most it may write, rounded up to 512 tokens, at least 1,024 and at most 8,192 or the model's training window. A kept context is made again only when it is too small, or more than twice too big.
- **The prefix is snapshotted.** `llm/prompt.rs` renders the conversation with a sentinel where the note goes, and cuts there. The prefix (the template, the system prompt, any context) is the same from one note to the next. `clear_kv_cache()` runs before every generation; then the prefix's state is restored from its snapshot when its tokens match, or decoded and snapshotted. Only the note's own tokens are paid for each time.
- **Thinking is kept apart.** A template with `<think>` gets an empty thought when a run asks for none, which switches reasoning off. A run that asks streams its thought first, and past `think_budget`, `THOUGHT_CUTOFF` closes it in the model's own voice. `Output.thinking` says the text starts with reasoning, and the page parts the two (`splitThinking` in `ai/runs.ts`).
- **Sampling** is close to greedy, with a mild repeat penalty. A command run is its grammar and greedy, and the grammar only ever comes from the binary.
- **Every count is checked before C++**, which throws on bad input, and Rust cannot catch that.

`llm/report.rs` decides when the page hears how a run is going: at most every 120 ms and at each change of phase, with the whole text so far, which `ai_commands.rs` emits as `ai://progress`. Each report carries `llm/hardware.rs`'s reading of the phone: the app's memory, what is free, CPU as a percent of one core, threads and cores, and the hottest thermal zone where the phone lets it be read. All of it comes from `/proc` and `/sys`, with no permission.

`ai_commands.rs` holds `ai_device`, `ai_models`, `ai_fetch_model`, `ai_delete_model`, `ai_generate` and `ai_cancel`, and `ai_infer_command` for voice commands ([[Reading a command, writing it safely]]). `ai_generate` never takes a grammar from the page.

## The page's side

| File | What it does |
|---|---|
| `core/ai.ts` | `listModels`, `useModels`, `modelSpec`, and `generate`, which listens for progress before it invokes |
| `ai/available.ts` | Whether the AI can run here, and which model: the chosen one, else the biggest no bigger, else the smallest |
| `ai/runs.ts` | One run at a time; a second waits as `queued`, and a new run on the same note replaces the old |
| `format/pipeline.ts` | `prepareNote`: tidies, protects tables and links, and puts them back |
| `format/prompt.ts`, `ai/prompts.ts` | The runs' prompts and token budgets, on the page so they can change over the air; the review's prompt is `review/prompt.ts`, and the command prompt is in the binary |
| `ai/landing.ts`, `ai/land.ts` | Where each finished line lands in the note, as tracked changes |
| `format/gist.ts` | The one line under each note on the home page |
| `ai/useNoteReview.ts` | The review after a recording, in four stages |

**Lines, not tokens.** `runs.ts` cuts the model's text at its last newline. `lines` only ever grows by whole lines, and `partial` is the one under the pen. A finished line never changes, which is what lets the editor land it at once. `landing.ts` reads like a reader, not a diff: each new line is looked for among the next eight old ones (`LOOKAHEAD`). The same line is kept. A line sharing half its words or more is that line rewritten, and only the words that differ are marked. Anything else is new, and old lines passed over are struck. `land.ts` never strikes or rewrites a line the person wrote while the run was going.

**Links and tables as tokens.** A small model cannot copy a hundred-character address. `format/links.ts` swaps each link for `link-1`, `link-2` before the note goes in, and back after. A link whose token is lost comes back on its words, or at the end of the note. `format/tables.ts` swaps each table for a line shaped like a picture, `![table-1](table)`, because the 4B dropped a bare `[table-1]` as noise. Tables go first, so a link in a cell is never touched. `format/clean.ts` turns old Notion task links into the mark form before the model, and straightens bullets, task boxes and doubled links after it.

**Prompts.** `format/prompt.ts` holds `SYSTEM_PROMPT`, `SUMMARIZE_PROMPT`, `ENHANCE_PROMPT` and `GIST_PROMPT` as `String.raw` literals, because `src-tauri/src/llm/tests.rs` reads prompts out of page files by name (`page_prompt_in`) and measures what the phone sends; it reads `REVIEW_PROMPT` from `review/prompt.ts` the same way. `ai/prompts.ts` builds `FIX_PROMPT`, `SHAPE_PROMPT`, `CONTINUE_PROMPT` and `ASK_PROMPT` from shared pieces, which that reader cannot follow, so nothing on the Mac measures them. `llm/tests.rs` measures commands with `COMMAND_PROMPT` from `capture/understand.ts`, which nothing on the page sends any more; the prompt `ai_infer_command` sends is `COMMAND_SYSTEM`. Temperature is 0.3 for the runs and the gist (`TEMPERATURE` in `format/prompt.ts`); the review's thinking run uses 0.2, and a command 0.

**The gist** asks the smallest model on the phone for 40 tokens, one note at a time, newest first, and only while the app is on screen. It calls `generate` directly, but steps aside while any run is going.

**The review** in `useNoteReview.ts` has four stages. Listening again is small.en over the take, through `listenAgain`. Comparing is `review/diff.ts`, where the two models heard differently. Thinking is a run with reasoning on, on a Qwen model where there is one (`thinkingModel`). Landing puts each finding into the note as a tracked change. [[Spoken asks and the review]] is the user's view of it.

## Read next

- [[The library on disk]]
- [[Asking the AI to work on a note]]
- [[Tests, and the report that ships]]
