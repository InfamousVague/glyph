# Asking the AI to work on a note

_Pick a run from a note's More sheet and watch the model write into the note itself. Every change stays marked until you keep it or revert it._

## Three runs in the More sheet

Open a note and tap the three dots in its tools (**More for this note**). The group headed **AI** holds three runs:

| Run | What it does | Where its words go |
|---|---|---|
| **Format** | Tidy and organise, keeping every word that matters. | In place of the note's words |
| **Summarize** | The point of the note and its tasks, in far fewer words. | Above the note, which stays as it was |
| **Enhance** | Every thought finished and the note made fuller, without inventing. | In place of the note's words |

Tap one and the sheet closes as the run starts. While it is going, its row in the sheet shows as pressed, with a dot at its end. The other runs (Fix spelling, Make a list, Continue, and a free ask) are spoken, and the next chapter covers them.

Format and Enhance are told to keep every fact, name, number, date and picture in the note, and to turn each thing to do into its own task line. Links and tables go to the model as placeholders, and the app puts them back afterwards, so a rewrite cannot lose one. A summary is a heading, one sentence saying what the note is for, and its tasks; it may leave a table out. All three are told never to add a fact the note did not give.

For example, here is a note spoken in one breath:

```
ok so I need to call the plumber about the leaking tap before thursday because it's getting worse, and pick up eggs and coffee on the way home
```

Format might return it as:

```
# Call the plumber

- [ ] Call the plumber about the leaking tap before **Thursday**, because it's getting worse.
- [ ] Pick up eggs and coffee on the way home.
```

The front matter at the top of a note (the lines between the two `---` lines) is never given to the model, and the model never rewrites it. The one change a run makes there is to sign the note, as the last part of this chapter shows. If the note is linked to a GitHub repo, the model is also given what the GitHub plugin has read about that repo, for spelling its names and terms, and it is told not to add any of it to the note. A note with nothing in it yet gets the message "Nothing in the note yet."

## The strip

A strip under the note's header says in one line what is happening:

| Phase | The strip says |
|---|---|
| Waiting | Waiting for the model, which is on another note. |
| Loading | Loading Qwen3.5 4B. |
| Reading | Reading the note, 120 of 480. |
| Writing | Formatting with Qwen3.5 4B, 9.4 tokens a second, 0:12, 3 lines. |
| Done | Formatted by Qwen3.5 4B in 0:42. |

A thin bar under the line fills up as the model reads the note, and again as it writes. **Stop** sits at the end of the strip while the run is going. What has landed by then stays, and the strip says "Stopped." Tap the line while the run is going to open the AI card, with the phone's readings ([[The models on your phone]]). Once the run has ended, a cross puts the strip away.

If the model uses up all the room it is allowed to write in, the done line adds "It ran out of room; try a shorter note."

## Lines land as they finish

The model writes from top to bottom, and each line goes into the note as soon as it is finished. You watch the note change a line at a time. With the ghostly typing on, the lines arrive out of smoke.

Every change stays marked:

- Words the AI added are tinted.
- Words it took out are struck through where they were. Whole lines show as a block above the line, and single words show inline.
- At the end of each group of changes are two small words, **Keep** and **Revert**.

The note is always the text as it reads now, and that is what is saved, synced and shared. The marks are only drawn on top of it, on the phone that ran the model.

| To | Do this |
|---|---|
| Accept one change | Tap **Keep** beside it. |
| Undo one change | Tap **Revert**. The old words come back and the new ones go. |
| Accept every change | Once the run has ended, tap **Keep all** in the strip. |
| Accept by editing | Type on the changed line. The words are yours now, and the marks go. |

Revert is a single edit, so the editor's own undo brings the AI's words back, though without their marks. Keep changes nothing in the note: it only takes the marks away, so there is nothing for undo to take back.

If you leave the note and come back, the marks are still there, as long as the note still reads the same. An edit made anywhere else in the meantime (on another device, by Claude, or in the file) clears them. Once the run's line has been put away, the strip keeps one line while marks remain, with **Keep all** beside it: "3 changes from the AI are marked in the note."

## Typing while it runs

You can keep writing while the model works. Anything you type during the run is yours: it is never struck through and never rewritten. If one of the model's lines would have replaced a line you touched, the model's line is dropped. When the run ends, a message tells you: "One line the model wrote was dropped: you had written there."

## One run at a time

The phone has one set of cores, so only one model runs at a time. If you start a run on a second note, it waits, and its strip says "Waiting for the model, which is on another note." until the first run is done. If you start a second run on the same note, it replaces the first, because the newest ask is the one you meant.

A run keeps going if you leave its note. If you open the note again while the run is still going, the lines carry on landing from where they were. Lines only land in an open note, though. If the run finishes while you are away, the lines it wrote after you left are not put in, and the note is not signed, so stay on the note until the strip says the run is done.

## The run log, and Undo

While the strip shows a run, tap its line to open the note's log: every run, newest first, with what was asked, which model did it, how long it took and how it ended. For example, "Format by Qwen3.5 4B in 0:42." This phone keeps the last eight runs for each note.

**Undo**, in the strip after a run or beside any run in the log, puts the whole note back as it was before that run. It only works while the note still reads exactly as the run left it, because anything you wrote since would be lost under the old words. If the note has changed, it says "The note has changed since, so that run can’t be undone." If the undo works, it says "Put back as it was."

## The AI signs its work

When a run finishes in the open note, it adds Ghost to the note's authors. The front matter gains a line like this:

```
---
authors: yourname, Ghost
---
```

If the note had no authors yet and you are signed in, your handle goes first, because the note was yours before the AI wrote in it. A name that is already there is not added again. The note's byline then reads "By yourname and Ghost". A person is shown as their initial in a ring, and an AI as a small spark. The line is part of the note's words, so it goes wherever the note goes. A run that is stopped signs nothing, and neither does the review after a recording.

Ghost is the name the app's own model signs with, whichever of the four models did the writing.

## The gist on the home page

On the home page and in All notes, each note's card can carry one quiet line under its title, about ten words saying what the note is about. The smallest language model on the phone writes these lines in the background:

- only while Ghost.md is on screen;
- one note at a time, newest first;
- after any run on a note, which always goes first.

A note's gist is written again only when the note changes in a way that matters: its first line changes, or it grows or shrinks by a twentieth and by at least twenty characters. Fixing a typo keeps the old line. With no model on the phone there are no gists, and nothing else changes.

## Read next

- [[Spoken asks and the review]]
- [[A note is a Markdown file]]
- [[The models on your phone]]
