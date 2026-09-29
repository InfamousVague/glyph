# Asking the AI to work on a note

_Pick a run from a note's More sheet and watch the model write into the note itself. Every change stays marked until you keep it or revert it. Or write a question where its answer belongs, and let the model fill it._

## Six runs in the More sheet, and an Ask field

Open a note and tap the three dots in its tools (**More for this note**). The group headed **AI** holds six runs:

| Run | What it does | Where its words go |
|---|---|---|
| **Format** | Tidy and organise, keeping every word that matters. | In place of the note's words |
| **Summarize** | The point of the note and its tasks, in far fewer words. | Above the note, which stays as it was |
| **Enhance** | Every thought finished and the note made fuller, without inventing. | In place of the note's words |
| **Fix spelling** | Spelling, grammar and punctuation, and not a word more. | In place of the note's words |
| **Make a list** | Tasks, a list or a table out of what is there. | In place of the note's words |
| **Continue** | Carries on from the last line in the note's own voice. | Under the note |

Tap one and the sheet closes as the run starts. While it is going, its row in the sheet shows as pressed, with a dot at its end. Under the runs is a field, **Ask it to do something with this note**. Type any instruction there, such as "make it shorter" or "put the dates in a table", and tap the arrow. It runs as a spoken ask does, and its changes are marked like any run's. On the Mac, the command palette has Fix spelling, Make a list and Continue too. When the note has a blank for the model, **Fill the blanks** follows the runs (the section below).

Format and Enhance are told to keep every fact, name, number, date and picture in the note, and to turn each thing to do into its own task line. Links and tables go to the model as placeholders, and the app puts them back afterwards, so a rewrite cannot lose one. A summary is a heading, one sentence saying what the note is for, and its tasks. It may leave a table out. The runs are told never to add a fact the note did not give. A blank is the one thing the AI may answer from what it knows, and it says so.

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

## Questions the AI answers in place

Write a question in curly brackets, with a question mark after the first one, where its answer belongs:

    Flights are cheapest to Tokyo on {?what day / time?}

The question is drawn in a small square with an icon that says what will happen. Once you stop typing, **Fill** shows at the end of the line. Tap it and the model on your phone writes its answer where the square was. **Fill the blanks** in the More sheet answers every square in the note in one go. The question can be a few words, or nothing at all: `{?}` asks the model to read the sentence around it, or the question just before it. The + beside an empty line writes one too, under **More**, and on the line under a table **Blanks in the empty cells** puts one in each empty cell.

### What happens to a square

| The square | What happens |
|---|---|
| A calculator, a calendar or a globe | The app works it out at once: a total, a count, a date, a conversion, the time in a city. The answer shows after the square, with its working a tap away, and changes when a number or the day does. The model is not asked. |
| The same, with **Can't work out** | The app saw a sum or a date it could not finish, such as two currencies or Easter. A tap says why. |
| A signal | Something live: the weather, an exchange rate, a recent result. When you tap Fill, the phone asks a public source (the list below) and the model writes the answer from what came back. |
| A crossed-out signal | Something live that no public source answers, such as today's fares, opening hours or a share price, or the phone may not look things up. It says **Can't know offline**, and the model is not asked. |
| A speech bubble with a question mark | The model answers when you tap **Fill**. |

When the app says it can't, tap its words and **Ask the model anyway** if you think it is wrong. The answer comes with a dotted line, like any other.

Where the square sits shapes the answer. As a note's whole first line with no question, it writes a title. As a whole list item it adds items, one new item a line. In a table cell it answers for that row and column. `{?in Japanese}` says the words before it in Japanese. A question as a note's whole first line stays as the title, and its answer goes under it.

### What the model's answer looks like

The answer goes into the note with a dotted line under it, the line for a fact to check later ([[The marks you can type]]). Tap it to see where it came from:

- **From this note**: its words are in a line of the note, beside what you asked.
- **From memory**: it came from what the model learnt in training.
- **From the web**: the phone asked a public source, which the panel names, and the model wrote the answer from what came back.

The model has no internet. It knows what it learnt in training, nothing newer, and it can be wrong. Asked who won the 2022 World Cup with France in the note, the 2B said France. It was Argentina.

The note keeps the source and your question beside the answer, in brackets the app hides:

    Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)

So wherever the note is read, on another phone, in a share or in another app, it says where the answer came from. Your question travels with it, shares included, until you tap **Keep as mine**.

| To | Do this |
|---|---|
| Make the answer yours | Tap it, then **Keep as mine**. The dotted line and your question go, and the words stay. |
| Ask again | Tap it, then **Ask again**. The model is told its first answer was not the one. |
| Have the question back | Tap it, then **Put the question back**. |
| Keep a worked-out answer | Tap it, then **Write it in**. It stops changing. |
| Undo a fill | Tap **Undo** beside it in the strip's log, while the note still reads as the fill left it. One press of Fill is one line there. |

In a title, an answer is written as plain words, since a title is a name and shows in every list. Its source is in the strip's log.

`[[what day?]]` is still a link to a note called "what day?". Only curly brackets ask the AI.

### Looking things up

A square with a signal is looked up by the phone itself, and only when you tap Fill. The phone asks one public source that needs no account: Open-Meteo for the weather, the European Central Bank's rates (through Frankfurter) for exchange rates, and Wikipedia and Wikidata for results, the newest of something and events after the model's training. Only the question in the braces goes (for an empty `{?}`, the words of its own sentence that ask), or the place and the day for the weather, never the rest of the note. The weather and a rate are then written by the app from the source's own figures; a Wikipedia answer lands only if its words are in what came back. Offline, the square says **Waiting for a connection**, and the lookup goes on by itself once the phone is online. **Look up blanks online** in Settings › Account › Privacy turns it off, and Local only keeps such squares waiting.

### Where it runs

Fills run on your phone, or on a Mac with the app, with a model you downloaded ([[The models on your phone]]). Once you tap Fill, the answers come even if you leave the note. In a browser and on an iPhone the squares, the worked-out answers and the dotted answers all show, and the model's answers wait for a phone.

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

If the model uses up all the room it is allowed to write in, the done line adds "It ran out of room. Try a shorter note."

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
