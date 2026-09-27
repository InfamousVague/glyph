# Instruction-aware voice commands

## Two readers

A committed phrase is read as it is said by the live reader, `src/app/capture/liveRoute.ts`, for one family of
command: words for a note you name ("hey Ghost, add a note to House TODOs", "add call Sam to Work", "move this to
Groceries", "remind me to …", "new note"), and a take-back: "scratch that", "actually …", "no wait, four" or "scratch
that, add it to X instead" takes back the last thing said in the recording (gone, replaced, one word changed, or sent
to X), with a chip and Undo (`src/app/capture/takeBack.ts`, DESIGN §130). It switches the recorder's page to that
note, or sends the words there, and draws them where they will go; it stores nothing. At Done each note is written
once (below).

Everything else a recording asks for is read once, after Done, by `src/app/ai/instruction.ts`, and only when the live
reader did nothing: the AI's runs said in words ("fix the spelling", "make this a list") are those runs on the note; a
command naming another note said without the keyword ("add eggs to Groceries") is read by the rules below and, on a
name they cannot match, the on-device model, and offered on the confirm card (`src/app/ai/ConfirmCard.tsx`) before
anything is written; a command that named a note there is no note for fails closed with its reason; anything else is
an ask about the note, but only after "hey Ghost", and without it the words are the note's. An instruction spoken into
a note it continues opens the note with the run on it; one said as a fresh recording is saved as a note of its words,
without the keyword, and the chip says the recording could not do it.

The reader at Done once took instructions typed into a bar at the foot of the note too. The bar was removed (DESIGN
§122); the reader keeps its typed path, which only its tests use.

## Safety boundary

Whisper partials are display only. A committed phrase is read by one narrow live reader (`capture/liveRoute.ts`) for one family of command: words for a note you name ("add … to X", "put … on X", "move this to X", and "X: …" or "for X, …" after the keyword), words for the note being written ("remind me to …"), and "new note". With "Commands start with hey Ghost" on, it reads only a phrase that opens with the keyword, or a known mishearing of it before a command for a note named clearly (`liveCommand.ts` `misheardShape`). It switches only to one clear match, never to a book, and never to a shared note over the lock screen. An unsure name, or a name that matches nothing but comes near a title, gets a card that takes a tap or a spoken title and otherwise keeps the words here, in the order they were said; no card offers a book. The recorder draws the words where they will go as they are said, but nothing is stored before Done. At Done each note is read fresh and written once, adding only, at one spot (the end of a list, or of the note), through `apply_command`, which checks body and revision. A conflict makes the words a note of their own. Not this note and Discard store nothing, and Undo in the opened note is an edit in its editor. The live reader never deletes or replaces text it did not write in this recording: a take-back removes only the last thing this recording said, keyword or not, shows what went with Undo for four seconds, marks the stretch so the better words never restore it, never engages the reader, and stores nothing, since nothing is stored before Done. It never makes a table, a board or a book, never moves a card, and never runs an AI run; words said for a lane of the board being written to go into that lane (`capture/place.ts`). A run or ask said mid-take is queued for the note that opens after Done. Everything else is read once, from the complete transcript, at Done, and only when the live reader did nothing.

A note's name is found by its words (`capture/noteFind.ts`): the distinctive words must all be in the title, the kind words (to-do, task, chore, job, list, item, stuff, thing, note, page) only back a match up, and to-do has one spelling on both sides, so "house chores" and "the house list items" are House TODOs. Both readers use it. The Guide's chapters and canvases are never candidates (`capture/candidates.ts`). Where the words go in the note is `capture/place.ts`: the list they fit, by heading and items, a to-do list for a to-do, or the end.

The reader at Done keeps its gate: a wake word, or a final utterance that begins with narrowly gated explicit command language (`make`, `create`, `new`, `add`, `put`, `append`, or `I need/want a new…`). The gate is anchored at the beginning, so ordinary prose that merely mentions command words later—and quoted or reported commands—is not eligible. A leading wake word, filler before it (`Um, hey Ghost,`), a known mishearing of it followed by a command (`Hey, like, add…`), and lead-ins (`Okay, um,`, `can you`, and after the keyword `like` or `I want to`) are stripped before the gate. After a mishearing only a command for a note named clearly counts, as for the live reader, and then only as a card: never a run, an ask or a refusal. After a tapped "New note", the reader reads only what was said after it. The deterministic parser runs against the complete transcript first; `ai_infer_command` receives that same complete transcript once only on a parser miss.

A finished recording may add to a note or make a new list, and nothing else. The recorder acts on what `src/app/ai/instruction.ts` makes of the classifier's answer (`src/app/capture/finalInstruction.ts`), and only one refusal reaches the screen: a command that named a note there is no note for, or more than one ("No unambiguous note matches “Camping”. Nothing changed."), and nothing is saved then. A table, a board, a book or a chapter is turned down by the classifier ("That command is not supported from a voice capture. Nothing changed."), but that reason is never shown. After "Hey Ghost", such a command said into an open note opens the note with an AI ask carrying its words, and one said as a fresh recording, or from the lock screen, is saved as a note of its words, without the keyword. Without the keyword, its words are the note's.

Natural append forms include `add to the note labeled Go …`, `add to my note called "Go" …`, `add to the note named Go …`, `add to Go …`, `add to house to-dos, …` (up to the comma, or the best few words that name a note), and `add to the to-do list …`. What introduced the words ("The note is …", "it says …") is not added. When the words after the title announce a list (`a list with …`, `a to-do list of …`, `the following items: …`), they become separate items (`src/app/capture/spokenList.ts`): US `City State` pairs are told apart by the state even with no commas, so `parkersburg west virginia marietta ohio` is two bullets, `Parkersburg, West Virginia` and `Marietta, Ohio`. A finished recording may also create a list: `make a new list called Comic books` offers an empty titled list, and `… called Comic books and add to the list Spider-Man, Batman and Superman` (or `… with …`, `…, add … to it`, `… Add these: …`) offers the title with those items; confirming creates the note through `apply_command_mutation` and moves the recording to it. A title that only contains `with` (`Books with pictures`) stays whole unless several items follow. When the rules hear a note name they cannot match, the on-device model reads the transcript once before the command is rejected; a list it returns is split by the app, not the model, and each item is escaped as literal text. The title is matched against actual titles case- and punctuation-insensitively, and only the words after the matched title are payload. Missing and non-unique targets reject rather than choosing a note, and nothing is saved. The classifier also rejects new-note, destructive, compound, and other unsupported final instruction shapes, but the recorder treats those as it treats a table or a book, above: an AI ask on an open note after the keyword, otherwise a note of the words. If inference is unavailable or invalid, it never executes an action: without the keyword the complete transcript falls back to an ordinary note and says so, and after the keyword it is an ask, as above.

The native model can produce only this allowlisted intent set:

- `append { target, content, placement }`
- `create { target, content? }`
- `none { reason }`

`target` is a spoken title, never a database id. The model never receives note bodies and cannot return ids, offsets, or Markdown decisions. Model content is serialized as escaped literal Markdown text, so headings, links, images, emphasis, code fences, tables, HTML, and list syntax cannot become model-owned structure. llama.cpp generation uses the native `llm::command::GRAMMAR`; there is no IPC field for a grammar. Rust parses the entire output with unknown fields denied and validates action-specific fields, lengths, control characters, and truncation. TypeScript validates the IPC value again.

The selected formatting model is used only when it is installed. Otherwise the already-installed Qwen3.5 2B model is the fallback. Ghost.md never downloads a model for a command and never calls remote AI. If another llama.cpp run is active, inference returns unavailable rather than queueing behind or disturbing it. iOS returns unavailable for inference while deterministic commands remain functional.

## Mutation boundary

TypeScript finds inferred title strings as it finds a spoken name (`noteFind.ts`: `resolved`, `unsure`, or `missing`), and creates final Markdown with deterministic placement rules. A confirmation card shows the exact action before any write.

### Stopped audio and lifecycle

On Done, native capture first writes audio under the id of the note the take is aimed at by then: the fresh capture id, the note's own Speak, or the note the live reader switched the take to. A command only the stop's transcript held, read by the live reader after the stop, moves that audio to the note it went to with `capture_reassign_recording`, unless it went on the end of a note's own tape, where it stays. Classification and confirmation at Done may still be pending on a fresh capture id. On a confirmed append it atomically moves (or appends) that WAV to the confirmed note before recording metadata is updated; cancellation and rejection discard only the temporary audio. A take said into a note that already has a recording is the exception: its sound went on the end of that note's own file, so the file is the note's whole tape, and it is never moved or removed by a command, an instruction, a refusal or a cancelled card (`letGo` in `src/app/capture/CaptureScreen.tsx`, DESIGN §123). The note keeps the longer tape, with a few seconds of the spoken command at its end. Unavailable inference finalizes an ordinary note under that original capture id, so both its transcript and audio remain available. The live reader never assigns a recording from a partial phrase: only a committed one can switch the take, and the sound goes with the note the take ends in. The confirmation remains on the capture screen, so a normal background/foreground cycle retains both the in-memory final transcript and its temporary WAV; process termination before a decision can leave an unreachable temporary WAV, which is safe but currently not garbage-collected. The transcript is never intentionally dropped for inference failure: that path finalizes a normal note immediately.

List semantics are application policy, not an inference privilege. `Groceries`,
`Grocery`, `Shopping`, and `List` default to ordinary bullets; `To Do`, `Todo`,
`Task`, and `Tasks` default to unchecked task items. A list that already has
items retains its own bullet/task/number style. These defaults apply when the
model returns `placement: null` and to deterministic add commands alike.

Confirmed append/create writes, and every live-read write into a note that already existed, call `apply_command_mutation`. Ghost.md 1.6.0’s Markdown-file Library compares both the note revision and body read while holding its writer lock, writes the new body, and records a durable guarded undo in the Library index. The live reader writes one guarded write at Done per note: the note is read fresh, the take's words are placed into it (`capture/place.ts`), and a conflict reads and places once more before the words become a note of their own (`TakeWriter.writeInto`). Nothing is stored mid-take, so no draft can overwrite a command or duplicate the transcript. The note that opens after Done offers Undo as an edit in its own editor (`src/app/editor/useLanding.ts`), and reverses writes to other notes through the guarded undo. Undo succeeds only while that exact command result is current. Its log survives restart; on launch Ghost.md re-offers a recent interrupted Undo once, in a toast (`src/app/shell/useHousekeeping.ts`), while a later edit makes Undo return a conflict rather than overwrite newer work.

The active Library index carries a monotonic `revision` for each Markdown file and increments it on body saves, command writes, external file changes, and command undo. The legacy SQLite migration store also gains the same column so old libraries can be imported safely.

Ordinary note persistence also separates birth from edit. `create_note` may
insert only a new id; `update_note` updates only the exact existing revision.
Editor, capture drafts, plugins and refinement writes have no upsert
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

The live reader is held by `src/app/capture/liveCommand.test.ts` (the grammar, the keyword and its mishearings), `src/app/capture/liveRoute.test.ts` (every rule, through `capture/liveTake.ts`, the recorder's bookkeeping over notes in memory), `src/app/capture/noteFind.test.ts` (names against Matt's own 76 titles with the Guide added), `src/app/capture/place.test.ts` (where the words go), `src/app/capture/CaptureScreen.test.tsx` "adding to a note as it is said" (nothing stored before Done, one guarded write, the note handed back with its landing), `src/app/editor/NoteScreen.test.tsx` (the Undo as an edit) and the voice suite, which plays the live reader (`docs/VOICE_TESTS.md`).

`src/app/capture/instructionCorpus.json` is the repeatable language corpus. Its test executes deterministic cases and production-contract fixture inference, asserting action, target, content, placement, rejection, and no-mutation failure paths. It covers clean and messy AttackFM append requests, create with and without content, ambiguous and missing targets, destructive and compound requests, quoted/numeric payloads, and ordinary memo prose. `src/app/capture/standaloneSpeak.test.ts` executes Kevin's four separate Speak sessions through the same parser, Markdown placement, and CAS store contracts.

The Whisper prompt supports a fixed vocabulary but not per-session dynamic note titles. It now biases command terms and `Groceries`/`Grocery list`. An unsafe ASR title such as `Brofries` is never silently rewritten: confirmation shows that heard title, and a later `grocery` request does not match or mutate it.

Run contract and deterministic evaluation with:

```sh
npm test -- --run src/app/capture/liveCommand.test.ts src/app/capture/liveRoute.test.ts src/app/capture/noteFind.test.ts src/app/capture/place.test.ts src/app/capture/instructionIntent.test.ts src/app/capture/instructionCorpus.test.ts src/app/capture/instructionMutation.test.ts src/app/capture/route.test.ts src/app/capture/listAppend.test.ts src/app/core/store.test.ts
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
