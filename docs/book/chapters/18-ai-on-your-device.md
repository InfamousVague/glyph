# AI on your device

Ghost.md has its own AI, and it runs on your device. It tidies a note, sums it up, finishes a thought, answers a question you left in the text, writes up your meetings and checks a recording after you stop. Once a model is downloaded, it works with no connection at all, and nothing you write is sent anywhere to be read.

Works on: Android and the Mac app. Not on iPhone yet. Settings › AI is part of Advanced mode.

## Getting a model

Open **Settings › AI**. The **Model** card lists four language models. Bigger writes better, and is slower. The one you choose writes the summaries and the review after recording, runs the AI in a note's More sheet, and fills its blanks.

| Model | Download | What it is for |
| --- | --- | --- |
| Qwen3.5 2B | 1.3 GB | Quick. Good for short notes, and it can shorten long ones. |
| Qwen3.5 4B | 2.7 GB | The balance. Fits most phones. The default. |
| Qwen3.5 9B | 5.7 GB | The most careful, and the slowest. Wants 12 GB of memory. |
| Gemma 4 E4B | 5.0 GB | A different voice. Runs like a 4B, with a bigger file. |

Tap **Get** beside one to download it. A bar above the card shows how much has come down; keep Ghost.md open until it is done, and get one at a time. Tap a downloaded model to use it: it says **In use**. **Remove** takes one off the device: tap it, then **Tap again**. The model in use has no Remove while another is on the device, so pick another first. The card's foot says how much room the models take.

Models stay on the device that downloaded them: they don't sync, so get one on each phone or Mac you want to use it on.

The app never downloads a language model without asking. If you start a run with none on the device, it tells you, and offers **Get a model**.

If the model you chose isn't on the device, the biggest one there that is no bigger runs instead. If there is nothing smaller, the smallest one there runs.

The models have no internet. They know what they learnt in training, nothing newer, and they can be wrong. Check any fact a model gives you from memory.

## The AI runs on a note

Open a note and tap **More for this note** (the three dots). The **AI** group holds six runs:

| Run | What it does |
| --- | --- |
| **Format** | Tidy and organise, keeping every word that matters. |
| **Summarize** | The point of the note and its tasks, in far fewer words, above the note. |
| **Enhance** | Every thought finished and the note made fuller, without inventing. |
| **Fix spelling** | Spelling, grammar and punctuation, and not a word more. |
| **Make a list** | Tasks, a list or a table out of what is there. |
| **Continue** | Carries on from the last line in the note's own voice. |

Under them is a field, **Ask it to do something with this note**. Type any instruction, such as "make it shorter" or "put the dates in a table", and send it. You can also ask by voice: see [[Speaking your notes]].

The runs keep every fact, name, number, date, link and picture. They never touch the front matter at the top of the note.

## Watching it write

A strip under the note's header says what is happening: loading the model, reading the note, then writing, with its speed in tokens a second. **Stop** ends the run, and what has landed stays.

The model writes top to bottom, and each line lands in the note as it is finished. Every change stays marked:

- Words the AI added are tinted.
- Words it took out are struck through.
- Each group of changes has **Keep** and **Revert**.

Once the run ends, **Keep all** in the strip accepts everything. Typing on a changed line makes it yours. **Undo** in the strip puts the whole note back as it was before the run, as long as nothing has changed since.

You can keep writing while it works. What you type is never rewritten. If the model wanted to replace a line you touched, its line is dropped, and a message says so.

Only one model runs at a time. A run on a second note waits for the first, and the recorder always comes first: a run in the background stops while you record.

When a run finishes, Ghost joins the note's authors in its front matter:

```
---
authors: yourname, Ghost
---
```

## Questions the AI fills in

Write a question in curly brackets, with a question mark after the first one, where its answer belongs:

```
Flights are cheapest to Tokyo on {?what day / time?}
```

The question is drawn as a small square. **Fill** shows at the end of the line. Tap it and the answer goes where the square was. **Fill the blanks**, in More, answers every one in the note. An empty `{?}` reads the sentence around it.

Some squares never need the model. A sum, a count, a date or the time in a city is worked out by the app at once, and changes when the numbers do. Something live, like the weather or an exchange rate, is looked up when you tap Fill. Only the question goes, to Open-Meteo, Frankfurter's bank rates or Wikipedia. Turn this off with **Look up blanks online** in Settings › Account › Privacy. When the app can't work something out, it says why, and **Ask the model anyway** stays.

A model's answer has a dotted line under it, and the note keeps where it came from:

```
??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)
```

Tap the answer to see its source: from this note, from memory or from the web. Then choose:

- **Keep as mine** takes the dotted line and the question away, and keeps the words.
- **Ask again** asks for a different answer.
- **Put the question back** brings the square back.
- **Write it in**, on a worked-out answer, stops it changing.

**Fill blanks on their own**, in Settings › AI, fills the ones the device can answer a few seconds after you stop typing.

To write the brackets as plain text, put a backslash first: `\{?not a blank}`.

## The gist on home

Each card on home and in All notes can carry one quiet line under its title, about ten words on what the note is about. The smallest model on the device writes these in the background, one note at a time, newest first, and only while Ghost.md is on screen.

A gist is never written for a note while you have it open. It waits until you leave, then reads the words you left. A gist is written again only when a note changes enough to matter. With no model on the device, there are no gists.

## Meeting summaries

After a meeting, the device writes a summary under the note's title: what was said, what was decided, and the to-dos as to-dos. That goes for a meeting you recorded and one Ghost was in, on Google Meet, Zoom or Discord. It runs in the background, one note at a time. A long meeting is read in pieces, and a write-up cut short carries on where it stopped.

**Settings › Recording › Summaries** chooses which recordings get one:

- **Meetings**: every meeting, once it is done.
- **Meetings and long voice notes**: a voice note over three minutes too. Each takes the device a few minutes.
- **Off**.

On Android a meeting waits until the phone is charging or above half, unless **Write up straight away** is on, on the **Meetings** card in Settings › Recording. **Tell me when a meeting is written up**, on the same card, sends a notification when it is done. A summary is never written again by itself. To ask for one, or a new one, tap **Summarize** on the note's tape. See [[Tapes and transcripts]].

With no model on the device, a meeting waits, and says what to do: "Waiting for a summary: turn on Claude or download the summary model on this Mac, or open Ghost.md on your phone." Any of your devices that can write it, with a model or with Claude, takes it on, and the waiting one says "Being summarized on your phone." meanwhile. Only one device writes each meeting up.

Once a meeting is written up, the AI files it into the Meetings folder of the workspace it is about. **Sort meetings into workspaces**, on the same Meetings card, turns this off.

If Claude is set up in the app, meetings are written up by Claude instead. See [[Claude in Ghost.md]] and [[Meetings and the Meet bot]].

## The review after recording

When you stop a short recording, the careful model listens again and reads it through, and what it would fix lands in the note as changes with **Keep** and **Revert**, as a run's do. Switch it off with **Review after recording** in Settings › Recording. See [[Speaking your notes]].

## Local only

**Local only**, in Settings › Account › Privacy, keeps Ghost.md to what is already on the device. Nothing is downloaded and blanks aren't looked up. Models you already have keep working, since they need nothing from outside. With no model and Local only on, the app says so, and asks you to turn it off to get one.

See also: [[Speaking your notes]] · [[Meetings and the Meet bot]] · [[Claude in Ghost.md]] · [[Privacy]] · [[Settings]]
