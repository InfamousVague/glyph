# Where the docs and the code disagree

_Where a doc, a comment or the app's own words say one thing and the code does another, checked at 1.8.0-12. Believe the code._

Each entry gives the claim and then what the code does, both with paths.

## What the app tells you to say

- **The recorder's suggestions.** `src/app/capture/tips.ts` says "a tip is always something that works". In a pause, `tips()` suggests “move this to …”, “add a table to …”, “add a chapter to …” or “make a book called …”; while adding to a note, “new note”; and on a note with a board, “add …” or “move …” to one of its lanes. The card before the first word, `starters()`, always offers one of “move this to …”, “add a chapter to …” or “make a book called …” as its second way to send a recording. A finished recording carries out only two shapes of command, adding to a note it names and making a new list (`permitted()` in `src/app/capture/finalInstruction.ts`, reached through `readInstruction` in `src/app/ai/instruction.ts`). The others are refused, read as an ask for the AI, or kept as the note's words. The reader that does run them, `take.phrase` in `src/app/capture/take.ts`, is called only by the voice suite (`src/app/capture/voiceSuite.ts`).
- **The voice memo cue.** The pause tips (`CUES` in `src/app/capture/tips.ts`) include “Voice memo … end memo”, to keep the sound instead of the words, and `src/app/capture/voiceMemo.ts` says that what follows the cue is not written down. Only `take.phrase` reads the cue (`startsMemo`, in `src/app/capture/take.ts`). The recorder's `take.listen` does not, so “Voice memo.”, the words after it and “End memo.” are all written into the note as text.
- **Making a board by voice.** The cheat sheet's board row (`src/app/guide/marks.ts`) says to say “Hey Ghost, make this a board”. `planCommand` in `src/app/capture/command.ts` still reads that as a board, but `permitted()` refuses it at Done, and `readInstruction` passes it on as an ask. Into a note's own Speak it goes to the AI as an instruction about the note; in a new recording the words stay in the note, “Hey Ghost” and all.
- **Notion by voice.** `src/app/plugins/notion/manifest.ts` says the plugin turns items into tasks when you "swipe an item, say it, or send a whole list", and its voice permission says it hears “send that to Notion” while you record; `src/app/plugins/notion/index.tsx` offers that line as a pause tip. A plugin's voice commands are reached only through `take.phrase`. The recorder hands its phrases to `take.listen`, which only shows them (`src/app/capture/CaptureScreen.tsx`), and the reader at Done asks no plugin, so a recording never sends anything to Notion. Swiping an item and sending a list work.
- **The canvas's cue words.** [[How Ghost.md works]] (`src/app/canvas/howCanvas.ts`) says to say heading, list, done or table. Only “heading” is a cue (`src/app/capture/spoken/blocks.ts`, read by `src/app/capture/markdown.ts`). Said on their own, “list”, “done” and “table” stay words: blocks.ts calls a bare “done” a reply, not a cue, and a new recording that opens with “Table.” is given that word as its title.

## Updates and generations

- **When to raise `BUNDLE_REQUIRES`.** The header of `src-tauri/src/ota.rs` says to bump both generation numbers when the page starts depending on a new command. The page gates each feature on its own threshold instead, through `hasNativeGeneration` (`src/app/core/nativeGeneration.ts`; `FILES_GENERATION = 18` in `src/app/core/libraryFiles.ts`, `SYNC_GENERATION = 16` in `src/app/core/sync/engine.ts`), and hides it on an older binary. On main, `BUNDLE_REQUIRES` stood at 1 while `NATIVE_GENERATION` climbed to 18 at 1.7.2. Both went to 19 at 1.8.0, when every note write came to need the revision-checked commands (DESIGN §114, "The AI in the note"). Raised for one new command, it would send every older phone to the APK.
- **Store builds and the air.** The comment on `STORE` in `ota.rs` says a store build's web bundle still updates over the air, which both stores allow. That holds for Play. An App Store build runs on iOS, where the fetch and the install are not built, `ota_check` answers "Over-the-air updates are Android-only." (`src-tauri/src/unsupported.rs`), and `src/app/core/ota.ts` never asks. That answer is narrower than the code in its turn: the Mac app takes updates over the air too.

## Comments that outlived their code

- **The recorder's buttons.** The header of `src/app/capture/CaptureScreen.tsx` says Discard and Done are the only buttons. The line at the top is a button as well (it shows what the pipeline has done), and a recording aimed at a note has New note beside it.
- **A model on the desktop.** `src/app/notes/peek.ts` says a desktop has no model. `src-tauri/Cargo.toml` builds llama.cpp for every target but iOS, and `src-tauri/src/ai_commands.rs` refuses only there, so the Mac app runs a model once one is downloaded.
- **Build-time settings.** `src/vite-env.d.ts` says the page reads none. `src/app/core/account/api.ts` and `src/app/share/share.ts` read two, the service's address and the reader page's, each falling back to its public default.
- **The size of the tree.** `eslint.config.js` says the tree "is five files old" and that its one non-null assertion is the root mount in `src/main.tsx`. `src/` holds hundreds of files and, outside the tests, over a hundred `!` assertions. The reason the rule is off still holds; the counts do not.

## DESIGN.md

- **Its numbers repeat.** §30, §49, §50 and §119 each head two sections, and 34 sections have no number at all. Cite a section as DESIGN §N with its title, and never renumber.
- **It reads forward.** §117 put the note's prompt bar behind a toggle, and §122, the same day, removed the bar and the toggle with it. A section is true of the day it is dated, and a later one may undo it.

## Read next

- [[Working on Ghost.md]]
- [[Ghost.md in one page]]
