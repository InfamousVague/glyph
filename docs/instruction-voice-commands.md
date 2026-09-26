# Instruction-aware voice commands

## One reader

A spoken instruction is read once, after Done, by one reader,
`src/app/ai/instruction.ts`: the AI's runs said in words ("fix the spelling",
"make this a list") are those runs on the note; a command naming another note
("add eggs to Groceries") is read by the rules below and, on a name they cannot
match, the on-device model, and offered on the confirm card
(`src/app/ai/ConfirmCard.tsx`) before anything is written; a command that named
a note there is no note for fails closed with its reason; anything else is an
ask about the note, but only after "hey Ghost", and without it the words are
the note's. An instruction spoken into a note it continues opens the note with
the run on it; one said as a fresh recording is saved as a note of its words.

The reader once took instructions typed into a bar at the foot of the note too.
The bar was removed (DESIGN §122); the reader keeps its typed path, which only
its tests use.

## Safety boundary

Whisper phrase commits are listen-only: they update the visible accumulated transcript and nothing else. They do not derive a title, create or update a note, route a command, or invoke a model. Only an explicit Done/stop obtains the complete final transcript and classifies it once. A wake word still works, but is not required when the final utterance itself begins with narrowly gated explicit command language (`make`, `create`, `new`, `add`, `put`, `append`, or `I need/want a new…`). The gate is anchored at the beginning, so ordinary prose that merely mentions command words later—and quoted or reported commands—is not eligible. The deterministic parser runs against that complete transcript first; `ai_infer_command` receives that same complete transcript once only on a parser miss.

A leading wake word or filler (`Hey Ghost,`, `Okay, um,`, `can you`) is stripped before the gate, so it no longer turns a command into a note of its own words; a command reported mid-sentence still stays ordinary.

A finished recording may add to a note or make a new list, and nothing else. The recorder acts on what `src/app/ai/instruction.ts` makes of the classifier's answer (`src/app/capture/finalInstruction.ts`), and only one refusal reaches the screen: a command that named a note there is no note for, or more than one ("No unambiguous note matches “Camping”. Nothing changed."), and nothing is saved then. A table, a board, a book or a chapter is turned down by the classifier ("That command is not supported from a voice capture. Nothing changed."), but that reason is never shown. After "Hey Ghost", such a command said into an open note opens the note with an AI ask carrying its words, and one said as a fresh recording, or from the lock screen, is saved as a note of its words. Without the keyword, its words are the note's. A move of the recording ("move this to Groceries") and a card move are not recognised at Done at all, since the gate above does not take "move", so they end the same way. Nor is a card for a lane: the lane rule needs the board being recorded into, and Done does not pass it, so "add call Sam to Doing" is read like any command naming a note the rules cannot find. The on-device model may read it as an addition to a note called Doing, offered when there is one and refused when there is not; with no model, it ends as the others do. These shapes are still read a phrase at a time by `src/app/capture/take.ts`, which only the voice test suite drives (docs/VOICE_TESTS.md).

Natural append forms include `add to the note labeled Go …`, `add to my note called "Go" …`, `add to the note named Go …`, `add to Go …`, and `add to the to-do list …`. When the words after the title announce a list (`a list with …`, `a to-do list of …`, `the following items: …`), they become separate items (`src/app/capture/spokenList.ts`): US `City State` pairs are told apart by the state even with no commas, so `parkersburg west virginia marietta ohio` is two bullets, `Parkersburg, West Virginia` and `Marietta, Ohio`. A finished recording may also create a list: `make a new list called Comic books` offers an empty titled list, and `… called Comic books and add to the list Spider-Man, Batman and Superman` (or `… with …`, `…, add … to it`, `… Add these: …`) offers the title with those items; confirming creates the note through `apply_command_mutation` and moves the recording to it. A title that only contains `with` (`Books with pictures`) stays whole unless several items follow. When the rules hear a note name they cannot match, the on-device model reads the transcript once before the command is rejected; a list it returns is split by the app, not the model, and each item is escaped as literal text. The title is matched against actual titles case- and punctuation-insensitively, and only the words after the matched title are payload. Missing and non-unique targets reject rather than choosing a note, and nothing is saved. The classifier also rejects new-note, destructive, compound, and other unsupported final instruction shapes, but the recorder treats those as it treats a table or a book, above: an AI ask on an open note after the keyword, otherwise a note of the words. If inference is unavailable or invalid, it never executes an action: without the keyword the complete transcript falls back to an ordinary note and says so, and after the keyword it is an ask, as above.

The native model can produce only this allowlisted intent set:

- `append { target, content, placement }`
- `create { target, content? }`
- `none { reason }`

`target` is a spoken title, never a database id. The model never receives note bodies and cannot return ids, offsets, or Markdown decisions. Model content is serialized as escaped literal Markdown text, so headings, links, images, emphasis, code fences, tables, HTML, and list syntax cannot become model-owned structure. llama.cpp generation uses the native `llm::command::GRAMMAR`; there is no IPC field for a grammar. Rust parses the entire output with unknown fields denied and validates action-specific fields, lengths, control characters, and truncation. TypeScript validates the IPC value again.

The selected formatting model is used only when it is installed. Otherwise the already-installed Qwen3.5 2B model is the fallback. Ghost.md never downloads a model for a command and never calls remote AI. If another llama.cpp run is active, inference returns unavailable rather than queueing behind or disturbing it. iOS returns unavailable for inference while deterministic commands remain functional.

## Mutation boundary

TypeScript resolves inferred title strings to `resolved`, `ambiguous`, or `not-found`, and creates final Markdown with deterministic placement rules. A confirmation card shows the exact action before any write.

### Stopped audio and lifecycle

On Done, native capture first writes audio under the fresh capture id while classification and confirmation are pending. On a confirmed append it atomically moves (or appends) that WAV to the confirmed note before recording metadata is updated; cancellation and rejection discard only the temporary audio. A take said into a note that already has a recording is the exception: its sound went on the end of that note's own file, so the file is the note's whole tape, and it is never moved or removed by a command, an instruction, a refusal or a cancelled card (`letGo` in `src/app/capture/CaptureScreen.tsx`, DESIGN §123). The note keeps the longer tape, with a few seconds of the spoken command at its end. Unavailable inference finalizes an ordinary note under that original capture id, so both its transcript and audio remain available. This prevents an incomplete phrase from assigning a recording to the wrong note. The confirmation remains on the capture screen, so a normal background/foreground cycle retains both the in-memory final transcript and its temporary WAV; process termination before a decision can leave an unreachable temporary WAV, which is safe but currently not garbage-collected. The transcript is never intentionally dropped for inference failure: that path finalizes a normal note immediately.

List semantics are application policy, not an inference privilege. `Groceries`,
`Grocery`, `Shopping`, and `List` default to ordinary bullets; `To Do`, `Todo`,
`Task`, and `Tasks` default to unchecked task items. A list that already has
items retains its own bullet/task/number style. These defaults apply when the
model returns `placement: null` and to deterministic add commands alike.

Confirmed append/create writes call `apply_command_mutation`. Ghost.md 1.6.0’s Markdown-file Library compares both the previewed note revision and body while holding its writer lock, writes the new body, and records a durable guarded undo in the Library index. For an append targeting the note currently being captured, Ghost.md pauses autosaves, flushes the current transcript through the serialized draft queue, previews against the returned revision, then hands the post-command base back to later autosaves. This prevents a stale draft from overwriting the command or duplicating the transcript. Undo succeeds only while that exact command result is current. Its log survives restart; on launch Ghost.md re-offers a recent interrupted Undo once, in a toast (`src/app/shell/useHousekeeping.ts`), while a later edit makes Undo return a conflict rather than overwrite newer work.

The active Library index carries a monotonic `revision` for each Markdown file and increments it on body saves, command writes, external file changes, and command undo. The legacy SQLite migration store also gains the same column so old libraries can be imported safely.

Ordinary note persistence also separates birth from edit. `create_note` may
insert only a new id; `update_note` updates only the exact existing revision.
Editor, capture drafts, plugins, refinement, and table writes have no upsert
path. Therefore a queued write holding a deleted id receives a conflict and
cannot recreate the row. Every launch of the recorder waits for the deferred
deletes to be final before the capture mounts or reads its candidates
(`src/app/capture/launch.ts`, `src/app/shell/useCaptureRoute.ts`).

## Inference session isolation

Each `CaptureScreen` is a fresh keyed mount whose transcript, pending command,
and inference refs start empty; unmount cancels any active inference, and Done
waits on the one pass over the final transcript.
Each native generation calls `clear_kv_cache()` before prefill. The only reused
state is a snapshot captured after the immutable system/template prefix and
before the per-job user remainder. `src-tauri/src/llm/prompt.rs` tests that user utterances
are outside that prefix. Previous Speak text is therefore neither a frontend
prompt input nor part of the restored llama KV state.

## Evaluation

`src/app/capture/instructionCorpus.json` is the repeatable language corpus. Its test executes deterministic cases and production-contract fixture inference, asserting action, target, content, placement, rejection, and no-mutation failure paths. It covers clean and messy AttackFM append requests, create with and without content, ambiguous and missing targets, destructive and compound requests, quoted/numeric payloads, and ordinary memo prose. `src/app/capture/standaloneSpeak.test.ts` executes Kevin's four separate Speak sessions through the same parser, Markdown placement, and CAS store contracts.

The Whisper prompt supports a fixed vocabulary but not per-session dynamic note titles. It now biases command terms and `Groceries`/`Grocery list`. An unsafe ASR title such as `Brofries` is never silently rewritten: confirmation shows that heard title, and a later `grocery` request does not match or mutate it.

Run contract and deterministic evaluation with:

```sh
npm test -- --run src/app/capture/instructionIntent.test.ts src/app/capture/instructionCorpus.test.ts src/app/capture/instructionMutation.test.ts src/app/capture/route.test.ts src/app/capture/listAppend.test.ts src/app/core/store.test.ts
cd tools/host-tests && cargo test
```

`cargo test --lib` in `src-tauri/` also runs `llm::command::tests`,
`library::tests` and `store::tests`, but it builds the whole crate first: tauri pulls the desktop
windowing stack (`tao` -> `dbus` -> `libdbus-sys`, which needs `dbus-1.pc` and
the dbus headers) and the crate builds llama.cpp and whisper.cpp, several
minutes of C++ for tests that never load a model. On a Linux host without
`libdbus-1-dev` it fails before any test runs.

`tools/host-tests` is a small cargo workspace that compiles the active `src-tauri/src/library/mod.rs`, the legacy migration `src-tauri/src/store.rs`, `src-tauri/src/llm/command.rs` and `src-tauri/src/llm/prompt.rs`, with the `src-tauri/src/note.rs` and `src-tauri/src/fsx.rs` they share, from the real source tree with `#[path]`—no copies—against only their direct dependencies. These modules contain no `tauri::` type; the harness stops compiling if that boundary changes.

A physical Android run with an installed Qwen3.5 2B or larger catalogue model is still required to measure inference accuracy, latency, cancellation, and concurrent Whisper responsiveness. No model fixture is downloaded by tests.
