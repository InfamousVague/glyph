# Spoken asks and the review

_Talk to the AI about a note instead of into it, and let the slower models check a recording once you stop._

## Asking by voice

Open a note and talk into it. Use the microphone in its tools (**Talk into this note**), or **Add** on its tape if it already has a recording. Say what you want done, and tap Done:

> "Fix the spelling."

The words are read as an instruction, not written into the note. The note opens with the run on it: the strip under the header, the model's lines landing as they finish, and every change marked for Keep or Revert, just as in [[Asking the AI to work on a note]].

Before you say anything, the recorder's card shows two of these under "To ask the AI".

## What you can say

| Say | The run | What it does |
|---|---|---|
| "Fix the spelling" | Fix spelling | Spelling, grammar and punctuation, and not a word more. The note comes back line for line. |
| "Summarise this" | Summarize | The point of the note and its tasks, in far fewer words, above the note. |
| "Make this a list" | Make a list | Tasks, a list or a table out of what is there. |
| "Tidy this up" | Format | Tidy and organise, keeping every word that matters. |
| "Flesh it out" | Enhance | Every thought finished and the note made fuller, without inventing. |
| "Carry on" | Continue | Carries on from the last line in the note's own voice, under it. |
| "Hey Ghost, make it sound friendlier" | Ask | Anything else is a free ask. The model does what you said to the note's words. |

Each run answers to more than one phrasing:

- **Fix spelling**: "fix the grammar", "correct the typos", "check the spelling", "proofread".
- **Summarize**: "summarise it", "sum it up", "give me a summary".
- **Format**: "format", "tidy up", "clean it up", "organise it".
- **Enhance**: "expand on this", "flesh it out", "elaborate", "make it fuller".
- **Continue**: "keep going", "keep writing", "write more", "go on".
- **Make a list**: "turn this into a table", "make this a checklist", "turn these into tasks".

"Hey Ghost", "OK Ghost", "Hi Ghost" or "Glyph" first are all fine and never needed for these, said alone; a free ask, or a run with more words after it, needs one. "Ghost" on its own is not the keyword. A "please" or "can you" after the keyword makes no difference.

A free ask only counts when the keyword opens the take. The strip then shows your own words in quotes: "“make it sound friendlier” with Qwen3.5 4B, 9.4 tokens a second, 0:12." The named runs, such as "Fix the spelling" said first into a note, need no keyword, but without it a run is the whole of what you said: "Carry on" is the run, and "Continue the discussion with Sam tomorrow" or "Fix the spelling of the name on the sign" is a sentence, written into the note. After the keyword only the start of the take is read, so a take into a note that begins "Hey Ghost, continue", "Hey Ghost, format" or even "Hey Ghost, go on" is taken as that run, and none of it is written into the note.

An ask said first is the whole take: say it on its own, then tap Done. Nothing else you say in that take is written into the note. An ask said in the middle of a recording runs on the note that opens after Done, and the chip says so. Words that name another note, such as "Add eggs to Groceries", are a command rather than an ask: they go into that note as you say them. See [[Spoken commands]].

## Where an ask runs

An ask said first runs only when you talk into a note that already exists, on an unlocked phone; said first in a new recording, its words are kept as the note. An ask said in the middle of a recording runs on the note that opens after Done, and that includes the new note a new recording makes. Over the lock screen an ask never runs, and nor does one said after the recording went to another note: the chip says it was left out. The card of things to say before the first word suggests asks only on a note's own Speak. A locked phone never shows a note to whoever is holding it.

If the AI cannot run (because no model is on the phone yet, say), the note still opens, and a message gives the reason in the same sentence as in [[The models on your phone]].

## The sound of an ask

A note that already has a recording keeps it as one tape, and each new take is added to the end. So the few seconds of your ask stay at the end of that tape, after the note's last words, and you only hear them if you play the tape to its very end. Cutting them out would mean removing the whole tape, and the app never does that for an ask. If the note had no recording yet, nothing is kept: the sound of the ask is thrown away.

## Better words

Settings › Recording › Better words (on Android and the Mac) is on by default. After you tap Done, the larger speech model goes over the recording in the background and fixes words the live model misheard. Settings puts its cost at a few seconds of the phone's time for each minute of speech.

- It waits while the recorder is on screen, because both models need the same cores.
- It only replaces the note's words if the note still reads exactly as Done saved it. If you have edited the note since, your edit wins.
- It leaves out the commands you said.
- If the app closed before it got to a recording, it runs the next time the app opens.
- The first time it runs, it downloads the larger model, about 190 MB. Until that model is on the phone, or while Local only is on, notes keep the words they were heard with live.

With the review on as well, which is the default, the review does this listening itself, straight after Done. The differences it finds are weighed by the review and offered in the note as marked changes, instead of being swapped in quietly.

## The review after recording

Settings › Recording › Review after recording is on by default too. When you stop, the note opens, and two slower models check the fast one's work. The recording is already saved when the review starts, so leaving the note at any point loses nothing: the review stops, and Better words goes over the recording in the background as it would have without it.

The strip under the header follows each stage:

1. **Listening again.** The larger speech model goes over the recording: "Listening again, 40%. The slower speech model is listening to the recording again."
2. **Comparing.** It finds the places where the two speech models heard different words: "Comparing. 3 places where the two models heard different words."
3. **Thinking.** The language model thinks the note through out loud: "Qwen3.5 4B is thinking it through, 9.4 tokens a second, 0:12." Once it starts on its answer, the line says it is writing what it found. Tap the strip to read its thinking as it arrives.
4. **Landing.** Each thing it found goes into the note as a tracked change, with Keep and Revert.

It checks four things:

| Check | What it looks for |
|---|---|
| Words | Where the two transcripts disagree, and which one is right. |
| Structure | Whether each list, heading, to-do and table is what you meant. |
| Commands | Whether each spoken command did what you said, with nothing lost and no command words left behind in the note. |
| Names | People, projects and features spelled the way your note titles spell them. |

A finding has to quote text that is really in the note, or it is dropped, so a model that imagines a mistake cannot change words that are not there. A finding can instead add a line, and one that adds a line the note already has is dropped too. At the end, a message counts what was found, such as "Qwen3.5 4B found 2 things to look at. Each is marked in the note.", or "Qwen3.5 4B found nothing to change."

A finding about another note, one that a command in the recording changed, is written into that note directly, without marks. It is checked against that note as it reads at that moment, and dropped if its words are no longer there or the note changes under it.

The thinking is done by a Qwen: your chosen model if it is a Qwen and on the phone, otherwise the largest Qwen on the phone. Gemma thinks only when you chose it and no Qwen is here. With no model to think with, the review only marks the words the slower speech model heard differently, and a message says so. When a model did the thinking, the review appears in the note's log like any other run, such as "Review by Qwen3.5 4B in 0:48.", and its Undo puts the note back as it was before the findings landed.

The review runs only:

- in the app, not a browser tab, and one recent enough to let a model think out loud (an older app saves the note as it always did and never shows a review);
- on an unlocked phone;
- on a take saved as a note, not one read as a command or an ask, and not one written into a note you named, which opens with its Undo instead.

Listening again also needs Better words on and the larger speech model, which is fetched the first time it is needed unless Local only is on. Without them, the review has nothing to compare, and goes straight to the thinking.

## Read next

- [[Spoken commands]]
- [[Recording a note]]
- [[What stays on your phone]]
