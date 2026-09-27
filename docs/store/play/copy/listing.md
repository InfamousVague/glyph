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
Say a note and it lands as Markdown, with the AI on your phone, not in a cloud.
```

79 characters.

## Full description (4,000 characters)

```
Ghost.md is a notes app for people who think out loud. Say a note and it takes shape on the page while you talk, plain Markdown with the headings, lists and to-dos in place. Every note is one .md file on your phone, said or typed.

SPEAK
Tap Speak and talk. Say "heading, before we go" and a heading appears. Say "bullet point, the heating" and you get a bullet. Say "remember to book the cabin" and you get a to-do with its box. Say "we need snacks, water, a charger and the good playlist" and the four things become a list. The cue words are taken out and your words stay as you said them. Say "scratch that" and the last thing you said is taken back.

HEY GHOST
Name a note and the words go into it. Say "Hey Ghost, add a note to House TODOs", then "call an electrician about the light sockets", and the recorder switches to that note and writes the to-do under its Electrical heading as you speak. Nothing is written until you tap Done, and then the note opens with Undo. Hey Ghost is heard inside a recording you started, and nowhere else.

THE REVIEW
When you tap Done, the phone reads the note through. A larger speech model listens to the tape again, a language model reads the note, and what it would change lands in the note as marked changes, added words tinted and removed words struck through, each with Keep and Revert. From a note's menu, ask for Format, Summarize or Enhance, or say it into the note: "Hey Ghost, tidy this up."

TAPES
Every spoken note keeps its recording as a tape at the top of the note, to play back or add to. Tap Summarize on the tape and the language model on the phone writes a Summary under the title: one line on what it was about, what was decided, and your to-dos as boxes you can tick. The Tapes shelf on the home page keeps your recordings in a row, each with its summary under it.

MEETINGS
Choose Meeting, put the phone on the table and let the screen go off. When you stop, the phone transcribes the meeting and writes it up in the background, and a notification tells you when it is done. The summary sits under the title, and the audio stays on the phone.

THE MARKS
Headings, lists, to-dos, tables, code, footnotes and links between notes are drawn as you type, the marks left dimmed on the page. Then seven marks of Ghost.md's own: highlight, aside, unsure, redact, shout, added, and spoiler, which sits in smoke until you tap it. And five effects that move, heat, frost, a wave, a shimmer and a haunting, each written as an emoji twice, 🔥🔥like this🔥🔥, so the note still reads anywhere. A list can be a board with cards you drag between columns. Notes gather into a book with an index. A canvas puts cards on a page with lines between them, saved as JSON Canvas.

WHAT STAYS ON YOUR PHONE
Your voice is turned into words on the phone. The formatting, the review and the summaries run on the phone too, by models downloaded once. Nothing is sent anywhere to be heard or written. The microphone listens only while you record. No account is needed, and without one nothing of yours is on any server. No ads, no analytics, no tracking. Local only, in Settings, keeps Ghost.md to what is already on the phone.

SYNC AND SHARING
An account is optional. Sign in and your notes are the same on your phone, your Mac and in a browser, sealed on the device before they leave. The server cannot read them, and your password itself never leaves the phone. Delete the account from Settings and everything it kept goes with it. Share a note or a book as a read-only link. Its key rides in the link after the #, so the server cannot read what it holds.

PLUGINS
Send a list item to Notion as a task or to GitHub as an issue, and a box ticked in either place is ticked in both. Connect Claude and it can read your notes and write into them.

MAC AND WEB
There is a Mac app with the same models, and a web version at ghostmarkdown.com that needs no install. On a folding phone the note unfolds with the hinge.
```

The count is in the check at the end of this file.

Two conditions on the block:

- MEETINGS describes 1.9.0, the build going to Play. If the AAB uploaded is 1.8.0, cut that section whole (the
  heading and its paragraph). If 1.9.0's word for the way in is not Meeting, change "Choose Meeting" to match.
- The one emoji is inside the heat effect's own syntax, which is how the mark is written. Nothing else in the
  block is an emoji.

## What the block does not say

Nothing the app does not do: no cloud AI, no iOS app, no wake word listening in the background, no voice cue for
tables or boards, no live editing with other people. Left out for room, and true: the side key held starts a note
on the lock screen; "actually, the meeting is at four" swaps the sentence before for the new one; the Academy and
the Guide. The check below reads every fenced block in this folder for the banned words: em and en dashes,
exclamation marks, the sales vocabulary, questions asked of the reader, superlatives, "With Ghost.md" openings, and
a closing line telling anyone to download anything.

## The check

Run from this folder:

```
node check.mjs
```

It prints the counts (name, short, full, release notes, every caption's words) and any line that breaks a rule.
