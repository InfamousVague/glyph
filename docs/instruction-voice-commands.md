# Instruction-aware voice commands

## Safety boundary

After each committed transcription, capture re-reads the full utterance before deriving a title or persisting it as note content. A wake word still works, but is not required when the utterance itself begins with narrowly gated explicit command language (`make`, `create`, `new`, `add`, `put`, `append`, or `I need/want a new…`). The gate is anchored at the beginning, so ordinary prose that merely mentions command words later is not eligible. Plugin and deterministic list/task/table routing run first; `ai_infer_command` is called only when that parser returns no plan.

The native model can produce only this allowlisted intent set:

- `append { target, content, placement }`
- `create { target, content? }`
- `none { reason }`

`target` is a spoken title, never a database id. The model never receives note bodies and cannot return ids, offsets, or Markdown decisions. Model content is serialized as escaped literal Markdown text, so headings, links, images, emphasis, code fences, tables, HTML, and list syntax cannot become model-owned structure. llama.cpp generation uses the native `llm::command::GRAMMAR`; there is no IPC field for a grammar. Rust parses the entire output with unknown fields denied and validates action-specific fields, lengths, control characters, and truncation. TypeScript validates the IPC value again.

The selected formatting model is used only when it is installed. Otherwise the already-installed Qwen3.5 2B model is the fallback. Glyph never downloads a model for a command and never calls remote AI. If another llama.cpp run is active, inference returns unavailable rather than queueing behind or disturbing it. iOS returns unavailable for inference while deterministic commands remain functional.

## Mutation boundary

TypeScript resolves inferred title strings to `resolved`, `ambiguous`, or `not-found`, and creates final Markdown with deterministic placement rules. A confirmation card shows the exact action before any write.

List semantics are application policy, not an inference privilege. `Groceries`,
`Grocery`, `Shopping`, and `List` default to ordinary bullets; `To Do`, `Todo`,
`Task`, and `Tasks` default to unchecked task items. A list that already has
items retains its own bullet/task/number style. These defaults apply when the
model returns `placement: null` and to deterministic add commands alike.

Confirmed append/create writes call `apply_command_mutation`. Ghost.md 1.6.0’s Markdown-file Library compares both the previewed note revision and body while holding its writer lock, writes the new body, and records a durable guarded undo in the Library index. For an append targeting the note currently being captured, Glyph pauses autosaves, flushes the current transcript through the serialized draft queue, previews against the returned revision, then hands the post-command base back to later autosaves. This prevents a stale draft from overwriting the command or duplicating the transcript. Undo succeeds only while that exact command result is current. Its log survives restart; on launch Glyph re-offers a recent interrupted Undo once, while a later edit makes Undo return a conflict rather than overwrite newer work.

The active Library index carries a monotonic `revision` for each Markdown file and increments it on body saves, command writes, external file changes, and command undo. The legacy SQLite migration store also gains the same column so old libraries can be imported safely.

Ordinary note persistence also separates birth from edit. `create_note` may
insert only a new id; `update_note` updates only the exact existing revision.
Editor, capture drafts, plugins, refinement, and table writes have no upsert
path. Therefore a queued write holding a deleted id receives a conflict and
cannot recreate the row. Deleting the current memo continuation forgets it
immediately, and every main-Speak launch awaits deferred deletion before the
capture mounts or reads candidates.

## Inference session isolation

Each `CaptureScreen` is a fresh keyed mount whose transcript, pending command,
and inference refs start empty; unmount and Finish cancel any active inference.
Each native generation calls `clear_kv_cache()` before prefill. The only reused
state is a snapshot captured after the immutable system/template prefix and
before the per-job user remainder. `llm/prompt.rs` tests that user utterances
are outside that prefix. Previous Speak text is therefore neither a frontend
prompt input nor part of the restored llama KV state.

## Evaluation

`src/app/capture/instructionCorpus.json` is the repeatable language corpus. Its test executes deterministic cases and production-contract fixture inference, asserting action, target, content, placement, rejection, and no-mutation failure paths. It covers clean and messy AttackFM append requests, create with and without content, ambiguous and missing targets, destructive and compound requests, quoted/numeric payloads, and ordinary memo prose. `standaloneSpeak.test.ts` executes Kevin's four separate Speak sessions through the same parser, Markdown placement, and CAS store contracts.

The Whisper prompt supports a fixed vocabulary but not per-session dynamic note titles. It now biases command terms and `Groceries`/`Grocery list`. An unsafe ASR title such as `Brofries` is never silently rewritten: confirmation shows that heard title, and a later `grocery` request does not match or mutate it.

Run contract and deterministic evaluation with:

```sh
npm test -- --run src/app/capture/instructionIntent.test.ts src/app/capture/instructionCorpus.test.ts src/app/capture/instructionMutation.test.ts src/app/capture/route.test.ts src/app/capture/listAppend.test.ts src/app/core/store.test.ts
cd tools/host-tests && cargo test
```

`cargo test --lib` in `src-tauri/` also runs `llm::command::tests` and
`store::tests`, but it builds the whole crate first: tauri pulls the desktop
windowing stack (`tao` -> `dbus` -> `libdbus-sys`, which needs `dbus-1.pc` and
the dbus headers) and the crate builds llama.cpp and whisper.cpp, several
minutes of C++ for tests that never load a model. On a Linux host without
`libdbus-1-dev` it fails before any test runs.

`tools/host-tests` is a small cargo workspace that compiles the active `library/mod.rs`, legacy migration `store.rs`, `llm/command.rs`, and `llm/prompt.rs` from the real source tree with `#[path]`—no copies—against only their direct dependencies. These modules contain no `tauri::` type; the harness stops compiling if that boundary changes.

A physical Android run with an installed Qwen3.5 2B or larger catalogue model is still required to measure inference accuracy, latency, cancellation, and concurrent Whisper responsiveness. No model fixture is downloaded by tests.
