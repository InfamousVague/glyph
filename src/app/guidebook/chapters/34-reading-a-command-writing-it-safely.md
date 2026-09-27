# Reading a command, writing it safely

_The guards between a voice and a write: a phrase is read for one kind of command as it is said, nothing is stored until Done, and every write to a note that exists is checked against it._

The rules are written down in `docs/instruction-voice-commands.md`. This chapter checks each one against the code, and says where the two part.

## Two readers, one boundary

A partial only draws. A committed phrase is read by the live reader, `src/app/capture/liveRoute.ts`, for one family of command: words for a note you name. Everything else a recording asks for is read once, from the complete transcript, at Done, by `readInstruction` in `src/app/ai/instruction.ts`, and only when the live reader did nothing.

The live reader switches the page; it stores nothing. `CaptureScreen.tsx` applies its steps to the take and the writer, and draws the words where they will go (`place.ts` `placeTake`, the function Done writes with). At Done each note is read fresh and written once. A note that already existed is written through `apply_command_mutation`, which checks its body and its revision.

## The live reader

`liveCommand.ts` is its grammar. `hearKeyword` finds the keyword anywhere in the phrase (`findKeyword`, `KEYWORD` in `capture/command.ts`), or a mishearing of it at the very start (`MISHEARD`: "hey, like", "hey goes"), which counts only before a command for a note named clearly (`misheardShape`: a note or item said, a name with a kind word in it, "add this to X, …", a heading, or "move this to", and the name resolved at 0.85 or more). Both readers ask `misheardShape`, so a mishearing means the same to each. `commandWords` takes off the lead-ins (`LEAD_INS`). A phrase-final full stop is never a separator: Whisper cuts a phrase about 300 ms into a quiet and nearly always ends it with a stop. `readRoute` returns every reading of the shapes: a verb, a noun and a name ("add a note to …"), "new item for …", "add to …", a thing then a name at every preposition, "move this to …", the name first after the keyword ("for Groceries, …"), "new note", a heading ("… under Kitchen in Home jobs"), and a to-do for here ("remind me to …").

`noteFind.ts` finds each name. Distinctive words must all be in the title, kind words (to-do, task, chore, job, list, item, …) only back a match up, and one spelling of to-do is used on both sides. It answers `resolved` (at 0.72 or more, clear of the next by 0.08), `current` (the note being written to, or one of its headings or lanes), `unsure` (0.6 or more) or `missing` (with titles near it). The Guide's chapters and canvases are never candidates (`capture/candidates.ts`).

Then `LiveRoute`:

| Found | At the start of a new recording | Mid-take, or a note's own Speak |
|---|---|---|
| Resolved | `route`: the take goes there, for good | `insert`: those words go there, the take carries on |
| Resolved, with "move this to" | `route`, words so far and all | the same |
| The note being written to | only how the words go changes | the same |
| Unsure, after the keyword | a card | a card |
| Missing, near a title or with a note noun | a card | a card |
| Missing | the words stay here, the command goes | the same |

A book is never switched to, and over the lock screen no card is raised and no shared note is written. A card lasts eight seconds and then keeps the words here; Done, the side key, the screen going off, back and Discard all settle it at once (`close`). A name that ran to the phrase's end and scored under 1 can grow into the next phrase ("house" | "to-dos"), timed on the recording.

A keyworded phrase that is no route goes to the reader at Done when it opens the take ("Hey Ghost, fix the spelling"). Later, it is queued as an ask for the note that opens after Done, or left out of a take that went to another note. One that opened the take and was left for the reader at Done is taken out of the words, and queued or left out the same way, as soon as the live reader does anything, since the reader at Done then never runs (`late`).

A card never offers a book, and a tap on one keeps the words here. It holds only its command phrase; the words it keeps land in the order they were said (`inOrder`). A command held for its name gives up after three phrases or 4.5 s, or at once when the keyword is said again. Each phrase the live reader changed or sent elsewhere is marked for the better words (`commandSpans`), so the larger model's phrase for it is replaced by the live one, or by nothing.

## The reader at Done, in order

`bareWords` takes off a leading keyword, filler before it, a mishearing of it followed by a command, and the lead-ins; the lead-ins a command starts with ("like", "I want to") only after the keyword. If the keyword comes after other words, the whole take is words. After a mishearing, only a command for a note named clearly counts, and then only as a card: never a run, an ask or a refusal. After "New note", it reads only what was said after it, and what was said before it is written first. Then:

1. **A run, said in words** (`runOf`): "fix the spelling", "summarise it", "tidy this up", "make this a list", "carry on".
2. **A command**, read by `classifyFinalTranscript` in `capture/finalInstruction.ts`: the rules first, then at most one pass of the model.
3. **An ask**: anything else, but only when the keyword opened the take.
4. **Words**: everything left.

| Read | What happens |
|---|---|
| `command` | The confirm card shows the plan. A tap writes it, and the note opens with an Undo. |
| `reject` | A note was named that no note, or more than one, matches. The reason goes on the chip and no note is saved. |
| `run` or `ask`, into a note, unlocked | The note opens with the run on it. |
| `ask`, in a new recording | The words are saved as a note without the keyword, and the chip says the recording could not do it. |
| `words` | The take is saved as a note, with a notice when the model could not be asked. |

`planCommand` reads the rules' plan; its names go through `noteFind.ts`. What was introduced by "the note is" is left out (`PAYLOAD_LEAD`), a title's own "to-dos" never asks for a list, and one thing is never split word by word. Only `place` and `create-list` may leave a finished recording (`permitted()`).

## Then the model, once

When the gate has passed and the rules either heard a name they cannot match (`no-note`) or have no plan at all, `inferInstruction` in `capture/instructionIntent.ts` calls `ai_infer_command` once, with the same words.

| Guard | Where |
|---|---|
| Destructive or compound requests ("delete", "rename", "send", "and then", two verbs) answered `none` before any model runs | `refusal` in `src-tauri/src/llm/command.rs` |
| A fixed system prompt and the words, with no note titles, bodies or ids | `COMMAND_SYSTEM` in `ai_commands.rs` |
| Output held to `GRAMMAR`: `append`, `create` or `none` | `llm/command.rs`; the page cannot send a grammar |
| The whole answer parsed, unknown fields denied, control characters and truncation refused | `parse` in `llm/command.rs` |
| Checked again on the page, key by key | `validateInference` |
| Titles found against real notes, never taken as ids | `findNote` in `noteFind.ts` |
| Content escaped as literal Markdown | `literalMarkdown` in `instructionMutation.ts` |
| An installed model only: no download, no remote AI | `ai_infer_command` |
| Another run going means `unavailable`, not a queue | the `runs` check in `ai_infer_command` |

The live reader asks no model.

## Written once, and checked

`TakeWriter.writeInto` reads the note fresh, places the words with `placeTake`, and calls `apply_command_mutation`. `commands.rs` checks the request whole first: plain ids, a known source, `append` or `create`, and an append must carry the revision and body it read. Then `Library::apply_command` in `library/mutations.rs`, under the library's lock, applies the change only while the note's revision **and** body are exactly what was read. A conflict reads and places once more; a second, or a deleted note, makes the words a note of their own. Each change is logged in the index's `command_mutations` table with enough to undo it, and undo is guarded the same way.

The Undo in the note that opens (`editor/useLanding.ts`) is an edit in its editor, which takes out exactly the pieces written in. The note's own saving writes it like typing, so no second writer races the editor, and the better words wait while any note is open (`refine.ts` `holdNote`). Writes to other notes are undone through `undo_command_mutation`.

## The sound

`capture_stop` writes the take's audio at Done under the id of the note the take is aimed at by then, on the end of that note's tape when it has one. A command only the stop's transcript held, read after the stop, moves it with `capture_reassign_recording`, unless it went on the end of a note's own tape, where it stays (`letGo`, §123). A one-shot's note gets no sound.

## Known gaps

- A take killed mid-sentence loses its words: nothing is stored before Done. Only its sound was ever kept that early, and not even that before the stop.
- A table, a book, a chapter, a board made or a card moved are not carried out by either reader, and neither is a voice memo said aloud (DESIGN §127). Words for a lane of the board being written to are: the live reader names the lane like a heading, and `place.ts` adds the card.
- `instructionCorpus.test.ts` runs its cases through `interpretWakeCommand` and `placeInstruction`, which neither reader uses.

## The tests that pin it

| Test | What it holds |
|---|---|
| `capture/liveCommand.test.ts`, `capture/liveRoute.test.ts` | The grammar, and the live reader's every rule, over notes in memory |
| `capture/noteFind.test.ts` | Names against Matt's own titles |
| `capture/place.test.ts` | Where the words go in a note |
| `capture/CaptureScreen.test.tsx` | The recorder end to end: nothing stored before Done, one guarded write, the note handed back |
| `capture/finalInstruction.test.ts`, `ai/instruction.test.ts` | The reader at Done |
| `capture/voiceSuite.test.ts` | The voice suite's scripts through the live reader |
| `editor/NoteScreen.test.tsx`, `capture/landing.test.ts` | The Undo, as an edit |
| `llm::command::tests`, `tools/host-tests` | The model's grammar, and the library's guarded writes |

## Read next

- [[The engines on the device]]
- [[Commands after Hey Ghost]]
- [[The library on disk]]
