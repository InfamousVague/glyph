# Reading a command, writing it safely

_The guards between a voice and a write: a recording is read once, at Done, and nothing it asks for is written until a tap says so._

The rules are written down in `docs/instruction-voice-commands.md`. This chapter checks each one against the code, and says where the two part.

## The boundary

While a take is recording, nothing it hears can act. Partials only draw. Committed phrases go to `take.listen`, which adds them to the page and does nothing else ([[From microphone to Markdown]]). No phrase routes a command, writes a note or calls a model.

At Done, `capture_stop` returns the complete transcript. `CaptureScreen.tsx` hands it to `readInstruction` in `src/app/ai/instruction.ts`, once. That is the only place a recording is classified.

## The reader, in order

`bareWords` first takes off a leading keyword and the lead-ins people say ("Hey Ghost,", "okay", "can you", "um"). If the keyword comes after other words, the whole take is words: "Buy milk. Hey Ghost, add eggs to Groceries" is a note that says exactly that. Then, in order:

1. **A run, said in words** (`runOf`): "fix the spelling", "summarise it", "tidy this up", "make this a list", "carry on". A run needs no keyword. Three of them are the More sheet's own (Format, Summarize and Enhance); fix, shape and continue are reached only by saying them.
2. **A command**, read by `classifyFinalTranscript` in `capture/finalInstruction.ts`: the rules first, then at most one pass of the model.
3. **An ask**: anything else, but only when the keyword opened the take.
4. **Words**: everything left.

What `finish` does with each:

| Read | What happens |
|---|---|
| `command` | The take's words are cleared and the confirm card shows the plan. Nothing is written. |
| `reject` | A note was named that no note, or more than one, matches. The reason goes on the chip as the recorder closes, the sound is let go, and no note is saved. |
| `run` or `ask`, into a note, unlocked | The note opens with the run on it. The take's words are not saved, and the sound is let go. |
| `words` | The take is saved as a note, if it lays out as anything, with a notice when the model could not be asked. |

A `run` or an `ask` said into a new recording, or over the lock screen, falls through to words. The take, keyword and all, becomes the note.

## Commands: the rules first

`finalCommandWords` in `capture/command.ts` takes off the keyword and lead-ins again, and a trailing "end" or "stop". Then comes a narrow gate, `isStandaloneCommandLike`: what is left must begin with `make`, `create`, `new`, `add`, `put`, `append`, or "I need a new" and its like. Only the very start counts, so a command reported inside a sentence ("I told her, add…") stays words. The gate is the same with the keyword or without it.

The keyword is one regular expression, `KEYWORD`. "Ghost" counts only after "hey", "hi", "OK" or "so", because a note can begin "Ghost stories". "Glyph" counts on its own, with the spellings Whisper writes for it: "glif", "gliff", "glyth" and more. `NAMED_BEFORE` and `NAMED_AFTER` keep "the Glyph note" a name. A second list, `SOUND_ALIKE` ("Life.", "Live,"), is read only by the live path below, so at Done a take that opens "Life. Add eggs…" is words.

`planCommand` reads the words into a `Plan`. It tries "make this a board" first (`MAKE_BOARD`), then a new list by name (`CREATE_LIST`), then adding to a named list (`ADD_TO_LIST`), then a direct append to a title (`DIRECT_APPEND`, "add to the note labeled Go …"), then a book, a table, the phrasings `route.ts` knows, and last any verb, a preposition and the best-matching title. A board's lanes and cards are read only when a board is passed in, and the reader at Done passes none. Titles are matched by `resolveTarget` in `route.ts`: letter pairs (Sørensen–Dice), shared words and a name that opens a title, a threshold of 0.72, and a margin of 0.08 over the runner-up. Two close titles are ambiguous, and ambiguous is refused. A direct append looks instead for the one title whose words open what follows it.

Only two kinds may leave a finished recording: `place`, words into a note, and `create-list`, a new list with its items. `permitted()` in `finalInstruction.ts` refuses every other kind: move, new note, table, book, chapter, lane, card, board, and a note named with nothing to add.

## Then the model, once

When the gate has passed and the rules either heard a name they cannot match (`no-note`) or have no plan at all, `inferInstruction` in `capture/instructionIntent.ts` calls `ai_infer_command` once, with the same words.

| Guard | Where |
|---|---|
| Destructive or compound requests ("delete", "rename", "send", "and then", two verbs) answered `none` before any model runs | `refusal` in `src-tauri/src/llm/command.rs` |
| A fixed system prompt and the words, with no note titles, bodies or ids | `COMMAND_SYSTEM` in `ai_commands.rs` |
| Output held to `GRAMMAR`: `append`, `create` or `none` | `llm/command.rs`; the page cannot send a grammar |
| The whole answer parsed, unknown fields denied, control characters and truncation refused | `parse` in `llm/command.rs` |
| Checked again on the page, key by key | `validateInference` |
| Titles resolved against real notes, never taken as ids | `resolveTarget` |
| Content escaped as literal Markdown | `literalMarkdown` in `instructionMutation.ts` |
| An installed model only: no download, no remote AI | `ai_infer_command` |
| Another run going means `unavailable`, not a queue | the `runs` check in `ai_infer_command` |

The model is the chosen formatting model when it is on the phone, else Qwen3.5 2B. An `append` whose title matches no note, or two, is refused, and no note is saved. A model's `create`, or its `none`, is not carried out either, but its reason names no note, so the take goes on as though no command had been heard: an ask with the keyword, words without it. A list is told apart by the app, not the model: `listItems` splits the content with `spokenList.ts`, which knows a US state ends a place. When the model is unavailable, a name the rules heard but could not match is refused; anything else goes on to be an ask, or words with the notice "Command understanding was unavailable; saved this recording as a note."

The model cannot carry one command into the next. Every generation calls `clear_kv_cache()`, and the only state reused is a snapshot taken after the fixed prefix, before the words (`llm/prompt.rs` tests that boundary).

## Nothing is written until the tap

`take.offerFinal` puts the plan on `ConfirmCard.tsx`, which shows the exact lines as they will land. `placeWords` in `listAppend.ts` builds both the preview and the result, so the preview is the result. The microphone has stopped, so only a tap answers. Cancel lets the sound go.

Confirm calls `apply_command_mutation`. `commands.rs` checks the request whole first: plain ids, a known source, `append` or `create`, and an append must carry the revision and body it previewed. Then `Library::apply_command` in `library/mutations.rs`, under the library's lock, applies the change only while the note's revision **and** body are exactly the preview's. A later edit, typed or synced, is a conflict, and the chip says the note changed after the preview. Each change is logged in the index's `command_mutations` table with enough to undo it, and undo is guarded the same way.

Ordinary writes are split into birth and edit; sync has its own path, `store_apply`, which writes a note as another device has it. `create_note` inserts only an unused id. `update_note` changes only the exact revision it was given. There is no upsert, so a queued write holding a deleted note's id gets a conflict and cannot bring the note back.

## The sound until the decision

`capture_stop` writes the take's audio at Done, before the reader has run. A command waiting on its card keeps that file under the capture's id. On confirm, `capture_reassign_recording` moves it, or appends it, to the note the command went to. On cancel or refusal it is discarded. The exception is §123's: a take on the end of a continued note's own tape stays there, whatever the ending, through `letGo`.

## The live path, kept for the suite

`take.ts` still holds the whole live reader: `phrase` and `tick` reading commands a phrase at a time, `guess` for the chip, tables asked for piece by piece, voice memos, spoken yes and no, and the model asked after a pause. The recorder uses none of that reading. It still calls `tick` on its clock, but with no phrase read there is nothing for it to time out, and nothing calls `guess` at all. `phrase` has one caller, `voiceSuite.ts`, which replays the 92 scripts in `voice-tests/suite.json` through it; only `voiceSuite.test.ts` imports that. The suite's host has no model, so the pass after a pause runs nowhere.

So a voice memo said into a recording today is words. The cue `voiceMemo.ts` knows is read only in `phrase`.

## Known gaps

- `tips.ts` suggests commands a recording cannot carry out, on the card before the first word and in the pauses after: "Move this to …", "New note", "Add a table to …", "Make a book called …", "Add a chapter to …", the lane commands, and "Voice memo … end memo". Said with the keyword, most of these become an ask; without it, words.
- A tip in a pause shows only after words have been heard, and a command counts only when it opens the take. A routing tip followed mid-take always ends as words.
- The confirm card still says "Or say “yes” or “no”." The microphone is off by then.
- Confirm does not wait for the change it asked for. The take's sound is moved onto the named note whatever the answer, so a change refused as a conflict still gives that note the take's sound.
- The only Undo for a voice command is a toast at launch (`shell/useHousekeeping.ts`): the newest command of the last ten minutes whose result still stands, offered once.
- `instructionCorpus.test.ts` runs its cases through `interpretWakeCommand` and `placeInstruction`, which the reader at Done does not use. The Done reader is held by `finalInstruction.test.ts`, `ai/instruction.test.ts` and `CaptureScreen.test.tsx`.
- `docs/instruction-voice-commands.md` still describes an instruction typed into a note's bar (the bar is gone, DESIGN §122), an instruction's recording that is always discarded (changed by §123), autosaves during a take, a memo continuation, a same-note preview (`previewSameNoteInstruction`, now reached only by tests), refusals that save no command prose, and an unmount that cancels inference. None of these hold at HEAD: a refused shape whose reason names no note ends as an ask or as words, and the pass at Done is awaited, never cancelled. This is the list for that doc; [[Where the docs and the code disagree]] points back to it.

## The tests that pin it

| Test | What it holds |
|---|---|
| `capture/finalInstruction.test.ts` | The Done reader: the "labeled Go" regression, lists, the model once, failing closed |
| `ai/instruction.test.ts` | The order: runs, commands, asks, words |
| `capture/CaptureScreen.test.tsx` | Done end to end, every `letGo` ending included |
| `capture/instructionCorpus.test.ts`, `instructionCorpus.json` | Ten utterances, clean and messy, through the live helpers |
| `capture/standaloneSpeak.test.ts` | Four separate Speak sessions through `planCommand`, `placeWords` and the guarded store |
| `llm::command::tests` | The grammar's shapes, and refusal before inference |
| `tools/host-tests` | `library/`, `store.rs`, `llm/command.rs` and `llm/prompt.rs`, compiled from the real files without Tauri |

## Read next

- [[The engines on the device]]
- [[Commands after Hey Ghost]]
- [[The library on disk]]
