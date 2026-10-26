# Speaking your notes
Say what you want written, and it arrives as Markdown. Spoken cues turn into marks as you go, so "check box" makes a to-do and "heading" starts a section. Your words are heard on the device, and the microphone is on only while you record.

**Works on:** Android and the Mac. The iPhone app doesn't record yet.

## Start a voice note

- **The dock's microphone,** **Speak a voice note**. In Simple, the round mic at the bottom, **Speak a note**.
- **Inside a note,** **Talk into this note** carries on the note you're in. It's in the note's tools and its More sheet.
- **The command palette:** **Speak a new note** or **Talk into this note**. In a journal, **Speak an entry**.
- **The sidebar's** **Speak** button.
- **On Android,** press and hold Ghost.md's icon and choose **Voice note**, or add the **Voice note** widget to your home screen. On a Wear OS watch there's a **Record a note** tile.
- **The side key,** if you've made Ghost.md your phone's assistant. With Claude set up it talks to Claude; without a key on the phone it records a voice note. See [[Android extras and the watch]].

If you've put Claude's microphone on the dock, it takes the place of the voice-note mic there. Speak a note from the palette or the sidebar instead. See [[Claude in Ghost.md]].

## While you record

The recording screen shows your words as they're understood, with the cues already turned into marks. The line at the top says where they're going: **New note**, or **Adding to** a note.

Before your first words, a card of **Things to say** suggests cues to try. If you meant to record a meeting, tap **Meeting instead** on that card before you speak. When you pause, a tip comes up, such as: Say "Check box" to make a to-do.

- **Done** stops and keeps the note. The back gesture does the same.
- **Discard** throws the recording away.

There's no pause button. Stop with Done, and add more later with **Talk into this note**.

The screen stays on while you record. If the screen goes off (a press of the side key does that) or the microphone stops, the note is saved as if you'd tapped Done. To record with the screen off, record a meeting instead. See [[Meetings and the Meet bot]].

## Cues for marks

Say a cue between pauses, or on its own, so it's heard as a cue and not as words.

| Say | You get |
|---|---|
| "Title" first | The note's name, as a `#` title |
| "Heading", "Subheading" | A section, or a section inside one |
| "New paragraph", "New line" | A break in the text |
| "Bullet point", "The next item is …" | A list, and the next item on it |
| "Number one" | A numbered list |
| "Check box", "Remember to …" | A to-do |
| "Done task" | A to-do already ticked |
| "Option", "Picked option" | A choice, and the one you chose |
| "Counter zero of eight" | A counter on an item |
| "Quote" | A quote |
| "Info box" | A callout |
| "Hidden line" | A line kept blurred until it's tapped |
| "Divider" | A line across the page |
| "Calculate" and a sum | A sum with its answer |
| "Hashtag" and a word | A tag |
| "Define … as …" | A term and its meaning |
| "Emoji party popper" | 🎉 |
| "Bookmark this" | The bookmark, at the end of a line |

Some cues go around words, with "end" to close them:

- "Bold … end bold", "Italic … end italic", "Strike … end strike", "Code … end code"
- "Maths … end maths", "Superscript … end superscript", "Subscript … end subscript"
- "Note link … end link", "Link … to … end link", "Footnote … end footnote"
- "Code block … end code block", "Anchor … end anchor"

With the Marks plugin on, Ghost.md's own marks have cues too: "highlight", "aside", "unsure", "redact", "shout", "added" and "spoiler", and the effects "heated", "frosted", "wavy", "shimmering" and "haunted". For example: "the stove is heated too hot to touch end heated".

On a to-do you can also say when it's due, its priority, and who it's for: "check box call the landlord due Friday for Sam".

## Taking it back

Changed your mind mid-sentence? Say so:

- **"Scratch that"**, "strike that", "take that back", "forget that", "delete that", "never mind", "cancel that" or "ignore that" takes back the last thing you said.
- **"Actually …"**, "I mean …", "sorry, …", "no, …", "or rather …" or "no wait …" replaces it with what comes next. These are ordinary words too, so they only count when what follows corrects what you said: "the meeting is at three, actually four".
- **"Scratch that, add it to Groceries instead"** takes the last thing back out of this note and sends it to the one you name.

A chip shows what was taken back or changed, with **Undo**.

## Sending words to another note

You can send what you say into a note you already have:

- **"Add … to Groceries"** puts the words into a note whose name says it's a list, as a new item.
- **"New item for Groceries, …"** does the same.
- **"Add a note to Weekend trip, …"** adds the words to any note.
- **"Move this to Weekend trip"** sends the whole recording there.
- **"New note"** starts a fresh one while you're adding to another.

Say **"Hey Ghost"** first to make sure the words are read as a command: "Hey Ghost, add oat milk to Groceries." A chip shows what it's doing, such as "Added to Groceries", with **Undo**. If it can't tell which note you mean, it asks.

## Asking the AI

Said first into a note's own **Talk into this note**, these are read as asks rather than written down:

- "Fix the spelling"
- "Summarise this"
- "Make this a list"
- "Tidy this up"
- "Expand on this"
- "Carry on"

Mid-recording, say **"Hey Ghost"** first: "Hey Ghost, fix the spelling." It's done once you tap Done. The AI works on the note, and every change is marked for you to keep or undo. See [[AI on your device]].

## After you stop

In Settings › Recording. In Simple, these are behind **More** on that page.

- **Review after recording** (on to begin with): after you stop, a slower listen and a read-through, with what it would fix for you to keep. For recordings under three minutes.
- **Better words** (on to begin with): a larger model goes over the recording and fixes the words. A recording over three minutes gets its better words a little later.
- **Stop when I go quiet** (off to begin with): saves after four seconds of quiet, once you've started talking. Done, and the side key, still work.
- **Summaries** (Meetings, to begin with): choose **Meetings and long voice notes** to have a voice note over three minutes summarised under its title too. See [[Tapes and transcripts]].

The recording is kept with the note, as its tape. See [[Tapes and transcripts]].

## The voice model

The first time, Ghost.md downloads its voice model, about 60 MB. The home page shows how far it's got: keep Ghost.md open until it's done. If it fails, tap **Try again**. The better model for Better words is about 190 MB.

With **Local only** on, the model isn't downloaded. Turn Local only off in Settings to get it.

See also: [[Meetings and the Meet bot]], [[Tapes and transcripts]], [[Markdown and the Ghost.md marks]], [[AI on your device]]
