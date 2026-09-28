# The store listing

Paste each fenced block into the Play Console field it is named for (Grow › Store presence › Main store listing),
without the heading above it. The counts are Play's limits and each block's own count is under it. Plain text only:
Play keeps blank lines and nothing else, so the section names inside the full description are lines of their own in
capitals. British spelling throughout, except where a word is one of the app's own buttons (Summarize).

## App name (30 characters)

```
Ghost.md
```

8 characters. It is the name on the icon, the phone and the site. If a descriptor is wanted for search, this is still
true and 23 characters:

```
Ghost.md: notes you say
```

## Short description (80 characters)

One sentence, said the way a person would say it.

```
Say a note and it lands as Markdown while you talk, transcribed on the phone.
```

77 characters. One more, should the first read wrong on the page:

```
Say a note and it lands as Markdown, by models that run on your phone.
```

70 characters.

## Full description (4,000 characters)

```
Ghost.md is a notes app for people who think out loud. Say a note and it takes shape on the page while you talk, plain Markdown with the headings, lists and to-dos in place. Every note is one .md file on your phone, said or typed.

SPEAK
Tap Speak and talk. Say "heading, before we go" and a heading appears. "Bullet point, the heating" gets you a bullet, and "remember to book the cabin" a to-do with its box. Say "we need snacks, water, a charger and the good playlist" and the four things become a list. The cue words are taken out and your words stay as said. "Scratch that" takes back the last thing you said.

HEY GHOST
Name a note and the words go into it. Say "Hey Ghost, add a note to House TODOs", then "call an electrician about the light sockets", and the recorder switches to that note and draws the to-do under its Electrical heading as you speak. Nothing is saved until you tap Done, and then the note opens with Undo. Hey Ghost is heard inside a recording you started, and nowhere else.

THE REVIEW
When you tap Done and a model is on the phone, it reads the note through. A larger speech model listens to the tape again, a language model reads the note, and what it would change lands as marked changes, added words tinted and removed words struck through, each with Keep and Revert. From a note's menu, ask for Format, Summarize or Enhance, or say it, first thing, into the note's own Speak: "Hey Ghost, tidy this up."

TAPES
Every spoken note keeps its recording as a tape at the top of the note, to play back or add to. Tap Summarize on the tape and the phone's language model writes a Summary under the title: one line on what it was about, what was decided, and the to-dos as boxes. The Tapes shelf on the home page keeps your recordings in a row, each with its summary's first line.

MEETINGS
Record a meeting and let the screen go off. When it ends, the phone transcribes it and writes it up in the background, on the charger if the battery is low. A notification says so, with none of it on the lock screen. The summary sits under the title, and the audio stays on the phone.

THE MARKS
Headings, lists, to-dos, tables, code, footnotes and links between notes are drawn as you type, the marks left dimmed. Then seven marks of Ghost.md's own: highlight, aside, unsure, redact, shout, added, and spoiler, which sits in smoke until you tap it. And five effects that move: heat, frost, a wave, a shimmer and a haunting, each written as an emoji twice, 🔥🔥like this🔥🔥, so the note still reads anywhere. A list can be a board with cards you drag between columns. Notes gather into a book with an index. A canvas puts cards on a page with lines between them, saved as JSON Canvas.

WHAT STAYS ON YOUR PHONE
Your voice is turned into words on the phone. The formatting, the review and the summaries run on the phone too, by models downloaded once. Nothing you say or write is sent anywhere to be worked on. The microphone listens only while you record. No account is needed, and without one nothing of yours is on any server. No ads, no analytics, no tracking. Local only, in Settings, turns off update checks, downloads and every plugin that uses the network.

SYNC AND SHARING
An account is optional. Sign in and your notes are the same on your phone, on your Mac and in a browser, sealed on the device before they leave. The server cannot read them, and your password never leaves the phone. Delete the account from Settings and everything it kept goes with it. Share a note or a book as a read-only link. Its key rides in the link after the #, so the server cannot read what it holds.

PLUGINS
Send a list item to Notion as a task or to GitHub as an issue, and a box ticked in either place is ticked in both. Sign in and connect Claude, and it can read your notes and write into them.

MAC AND WEB
There is a Mac app with the same models, and a web version, linked from ghostmarkdown.com, that needs no install. On a folding phone the note unfolds with the hinge.
```

The count is in the check at the end of this file.

Two conditions on the block:

- MEETINGS describes 1.9.0, the build going to Play, and names no button. On main nothing records a meeting yet. It
  was read against `meetings/integrate` (2d8890d, 19:01 on 2026-09-27), which merges meetings/page, meetings/kotlin
  and meetings/rust. There a meeting starts from Meeting on the + sheet, and under the default Write up setting
  (Settings › Recording › Meetings: When charging or above half) a meeting stopped with the battery under half waits
  for the charger, which is what "on the charger if the battery is low" says. The branch was still moving, so read it
  again before pasting. If the AAB uploaded is 1.8.0, cut the section whole (the heading and its paragraph).
- The one emoji is inside the heat effect's own syntax, which is how the mark is written. Nothing else in the
  block is an emoji.

## What the block does not say

Nothing the app does not do: no cloud AI, no iOS app, no wake word listening in the background, no cue word for a
table or a board, no live editing with other people. Left out for room, and true: the side key held starts a note
on the lock screen, "actually, the meeting is at four" swaps the sentence before for the new one, "Hey Ghost, add a
table to" a note builds one there, asking as it goes, and the Academy and the Guide. The check below reads every fenced block in this folder for the banned words: em and en dashes,
exclamation marks, the sales vocabulary, questions asked of the reader, superlatives, "With Ghost.md" openings, and
a closing line telling anyone to download anything.

## The check

Run from this folder:

```
node check.mjs
```

It prints the counts (name, short, full, release notes, every caption's words) and any line that breaks a rule.
