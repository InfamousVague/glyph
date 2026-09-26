# Commands after Hey Ghost

_A recording can change another note instead of becoming one. What it can do in this version, how to say it, and why it always asks first._

## A command is a recording of its own

No microphone is ever left listening for Ghost.md's name. A command is only heard inside a recording you started, and it is read once, from the whole recording, after you tap Done. While you talk, your words show on the page like any others, and nothing is acted on.

So a command is a recording on its own: open the recorder, say the command, tap Done. Anything said after it is read as part of it.

## The keyword

“Hey Ghost” opens a command. “Hi Ghost”, “OK Ghost” and “So Ghost” work too. “Ghost” on its own does not, because a note may begin “Ghost stories…”. The old word still works: “Glyph”, alone or after hey, hi, OK or so.

The keyword has to come first. “Hey Ghost, um, can you add eggs to Groceries” is fine, since the lead-ins after it are dropped. Anything before it puts it inside a sentence: “Um, hey Ghost, add eggs to Groceries” and “Okay, um, hey Ghost, …” are kept as words. A command said inside a sentence, “I told Sam, add eggs to Groceries”, stays words too.

## What a finished recording can do

Two things: add to a note you name, and make a new list. In these examples Groceries already holds a list, and Chores and Work do not.

| Say | The card | What lands |
|---|---|---|
| “Hey Ghost, add oat milk and rye bread to Groceries.” | Add to Groceries · Oat milk · Rye bread · In its list | Two items on the end of its list |
| “Hey Ghost, new item for Groceries, oat milk.” | Add to Groceries · Oat milk · In its list | One item |
| “Hey Ghost, add these to Groceries: eggs, butter and flour.” | Three lines, in its list | Three items |
| “Hey Ghost, add a to-do call the bank to Chores.” | Add to Chores · Call the bank · In its list | `- [ ] Call the bank` |
| “Hey Ghost, add to Work Sam called about the invoice.” | Add to Work · Sam called about the invoice. · As a new paragraph | A paragraph at the end |
| “Hey Ghost, make a new list called comic books with Batman, Superman and Robin.” | Create Comic Books · three lines · As a new list | A new note, Comic Books, with three bullets |

“Make a list called packing” makes the list with nothing in it yet.

## Where the words go

- **Into the note's list, in its own style.** A numbered list gets the next numbers, a to-do list gets boxes, a `*` list gets `*`. The list's style wins over what you said: “a to-do” added to a list of plain bullets lands as a bullet.
- **When a note has several lists**, one short thing said plainly goes into the list whose heading and items share most words with it. Several things, or a thing said with its kind (“a list item …”), go on the end of the last list.
- **A note with no list yet** takes what you say as a paragraph, unless it is called Groceries, Grocery, Shopping or List, which start bullets, or To do, Todo, Task or Tasks, which start to-dos.
- **Say the kind of thing** to decide it yourself: “a list item”, “a bullet”, “a task” or “a to-do” before the words makes them one item of that kind.

## Naming the note

A name is matched loosely: “the”, “my” and a trailing “note” or “list” are dropped, and case and punctuation do not count. When the rules make nothing of a recording that opens like a command, or hear a name they cannot match, the language model on your phone reads the words once. It is only asked when it is already there: Ghost.md never downloads a model for a command.

With a model on the phone, a name that matches no note, or more than one, is refused, and the recorder says why as it closes: “No note called “Camping”. Nothing changed.” No words from that recording are saved.

Without one, it depends on how the command was said. Where the rules themselves heard a name they cannot find, as in “new item for Camping, eggs” or “add a table to Camping”, it is refused the same way: “No unambiguous note matches “Camping”. Nothing changed.” Where they could not read the command at all, as in “add eggs to Camping”, a new recording keeps it as words, and a note's own Speak takes it as an ask about that note.

## Why it asks first

A spoken name can be misheard, so nothing changes until you tap. The card shows the lines exactly as they will land, and where. **Cancel** leaves everything as it was. **Add**, or **Create** for a new list, writes what the card showed, and only if the note is still as it was when the card was drawn. If it changed in between, nothing is added: “Groceries changed after the preview, so nothing was added.”

The card's small print says “Or say “yes” or “no”.”, but by the time it shows, the microphone has stopped. Tap. The card waits as long as you take.

Over the lock screen the card shows too, with the note's name and the lines that would land, so whoever is holding the phone can read them. An ask for the AI is not run over the lock screen, but a command is offered all the same.

Afterwards a recording started from home takes you back there, and one started from a note opens the note the command changed. The sound of a new recording goes with the command, onto the tape of the note it changed.

## Undo

A confirmed command is written with an undo that lasts ten minutes, and it works only while the note is still exactly as the command left it. The recorder has no Undo button of its own. Ghost.md offers it once, the next time Ghost.md starts within those ten minutes: “Voice command changed a note.”, or “Voice command created a note.”, with **Undo**. Any other time, edit the note.

## One thing to watch

Said on its own to a note that already has a list, or with a list word in the command such as the To do in “add oat milk to To do”, one item of two or more words is split into one item per word. “Hey Ghost, add oat milk to Groceries” offers **Oat** and **Milk**. The card shows it before anything is written, so tap Cancel and say “new item for Groceries, oat milk”, or “add a list item oat milk to Groceries”.

A note with no list yet is the other way round: “oat milk and rye bread” lands there as one item, and only a list of three or more said with commas is split.

## Asks, said into a note

Said first into a note's own Speak, with the phone unlocked, a recording can be an ask for the AI instead:

- “Hey Ghost, fix the spelling.”
- “Hey Ghost, summarise this.”
- “Hey Ghost, make this a list.”
- “Hey Ghost, tidy this up.”
- “Hey Ghost, carry on.”

The words are not written into the note, and the note opens with the AI working on it. On a note that already has a recording, their few seconds of sound stay at the end of its tape. [[Spoken asks and the review]] has the rest.

Those five, and phrasings like them, are read with or without “Hey Ghost”. So a recording into a note that begins “Go on…”, “Continue…” or “Format…” is taken as the ask, not as words. Anything else after “Hey Ghost” that is not a command is an ask about the note: “Hey Ghost, shorten the second paragraph.” In a new recording, or over the lock screen, asks are not run: the words are kept like any others.

## What the recorder suggests, and does not do yet

The Things to say card and the tips in a pause suggest more than a finished recording carries out. In this version it carries out none of these:

- “Hey Ghost, move this to Groceries.”
- “Hey Ghost, new note.”
- “Hey Ghost, make a book called Field guide.”
- “Hey Ghost, add a chapter to Field guide.”
- “Hey Ghost, add a table to Work.”
- “Hey Ghost, make this a board.”
- “Hey Ghost, send that to Notion.”

None of them is refused out loud, except a table for a note you do not have. “Add a table to this note”, as [[How to format a note]] and the cheat sheet put it, is one of those: “this” is taken for a note's name, the recording ends with “No unambiguous note matches “this”. Nothing changed.”, and none of its words are kept. In a new recording the words are kept as the note's words, “Hey Ghost” and all. In a note's own Speak, with the phone unlocked, they go to the AI as an ask about that note. A board's lane is never named either: “Hey Ghost, add fix the login to Doing” is read as naming a note called Doing, and goes the way any unknown name does. [[Where the docs and the code disagree]] lists the places that still promise them.

## The setting

**Commands start with “hey Ghost”** is in Settings › Recording, on by default. Its line says: “Off, a command can be said without it, and still asks.” In this version the switch changes only how the recorder's suggestions are worded. A finished recording is read the same either way: one that opens with add, put, append, make, create, new, or “I need a new…”, is read as a command with or without the keyword, and an ask needs the keyword whichever way the switch is set. Every command asks first, always.

So a note you dictate that happens to begin “Add salt to the water…” is checked as a command before it is kept as words, and it can be refused if it seems to name a note you do not have. Without a language model on the phone, the recorder keeps it and says “Command understanding was unavailable; saved this recording as a note.” Saying the title first avoids both.

## Read next

- [[Spoken asks and the review]]
- [[Lists and to-dos]]
- [[Where the docs and the code disagree]]
