# Recording a note

_How a voice becomes a note: the ways in, what the recorder shows while you talk, and what happens when you stop._

## Four ways in

| Where | What you do | Where the words go |
|---|---|---|
| Home | Tap **Speak** in the dock | A new note |
| A note | Tap the microphone in the note's bar (**Talk into this note**). Once the note has a recording, tap **Add** on its tape instead | The end of that note |
| Android, any screen | Hold the side key, once Ghost.md is your digital assistant | A new note |
| Android launcher | Long-press the Ghost.md icon and choose **Record a voice note** (**Record note** where the launcher is short of room) | A new note |

Speak is also at the foot of the sidebar, and in the command palette as **Speak a new note** and **Talk into this note**. On the Mac, ⌘K opens the palette. Setting up the side key has its own chapter, [[The side key, the Fold and the Mac]].

Every way in opens the same recorder, and each recording starts fresh.

## Before the first word

The microphone opens first. The voice model loads while it listens, and what it hears in the meantime is kept, because the first words of a note are usually its subject.

Until you speak, the page shows:

- **The top line.** **New note**, or **Adding to “Groceries”** on a note's own Speak. Over the lock screen it says **Adding to your last note** and names nothing. While the recorder gets ready it says **Starting**, and after Done, **Saving**.
- **The counter**, on the right: `0:00`, counting up.
- **The ghost, listening**, and **Start talking.**
- **How this recording ends**, in a line: **Tap Done to stop.**, **Hold the side key again to stop.**, or **Press the side key to stop.** With Stop when I go quiet on, it begins **Stop talking to finish**, then names Done or the side key.
- **The Things to say card.** Up to three groups: **To shape it** (“Bullet point”, “The next item is …”), **To send it somewhere** (naming one of your own notes when there is one), and **To ask the AI**, which appears only on a note's own Speak with the phone unlocked. The card takes no taps. Saying a line is how you use it, and it goes the moment words arrive.

## While you talk

Words appear as they are heard, on the note's own page, set as they will read: a heading as a heading, a bullet as a bullet. The phrase still being guessed is written at the end as it is heard, and it can change while the recogniser makes up its mind. With **Ghostly typing** on (Settings › Animations), new letters come in out of smoke and replaced ones go back into it. Once the recogniser settles on a phrase, it takes its marks: “Bullet point, the heating” lands as a bullet. [[Saying the marks]] has every cue.

On a note's own Speak, the note's text is above and the new words are written onto its end.

Once you have started, a pause of two and a half seconds brings one tip, such as: Say **“Check box”** to make a to-do. It goes when you talk again, and the next pause brings the next one.

Tap the top line to see which engine is listening and how much it has heard. The line shows by itself when a recording has heard a while and made nothing of it, or has had an error.

## The buttons

| Button | What it does |
|---|---|
| **Discard** | Stops and keeps nothing, words or sound. On a note's own Speak, the note is left as it was. |
| **Done** | Stops and saves. |
| **New note**, in the top line on a note's own Speak | What you have said so far is written into that note now. The rest of the recording goes into a fresh one. |

The phone's back gesture saves, the way Done does.

## Ways to stop

- **Done.**
- **The side key.** Hold it again, the way a tape recorder's key is pressed a second time. On phones where Ghost.md can tell, a single press does it.
- **The screen going off.** On Android the recorder keeps the screen on while it runs. If the screen goes off anyway, a press of the side key for instance, the recording is saved as Done would save it.
- **Stop when I go quiet**, in Settings › Recording. Off by default. When it is on, four seconds of quiet saves the recording, but only once you have started talking: opening the recorder to think never ends a note.

Settings › Recording is on Android, the phone with a side key to record from.

## What Done does

The note is written at Done, from the whole recording. Nothing is saved while you talk.

- A new recording becomes a new note, at the top of the home page. A short first sentence becomes its title.
- A note's own Speak puts the words on the end of that note and the sound on the end of its recording, so its words and its sound stay one timeline.
- A recording that lays out as nothing, no words at all or only a cue said on its own, leaves nothing behind.
- With **Review after recording** on (Settings › Recording, on by default), the note opens and the review starts: [[Spoken asks and the review]]. Otherwise a new note leaves you on the home page, and a note's own Speak takes you back to that note.
- On a locked phone, Ghost.md goes back behind the lock screen, and the note is not shown to whoever is holding the phone. The review never runs over the lock screen.

A recording that is a command, or an ask about a note, goes another way: [[Commands after Hey Ghost]].

## The sound

On the phone and the Mac, a recording's sound is kept with its note, as a tape you can play back. It is held while you talk and stored when you stop. If the phone closes Ghost.md in the middle of a recording, that recording is lost, words and sound. A press of the side key, the screen going off and the back gesture all save as Done does, so putting the phone down in the usual way keeps what you said.

## Better words

A small, fast model writes the words live so they keep up with you. **Better words** (Settings › Recording, on by default) sends a larger model over the recording afterwards. It makes fewer mistakes: in Ghost.md's own tests, about six words in a hundred where the fast model gets ten wrong. On its own it runs in the background, one note at a time, never while the recorder is open, and takes a few seconds of the phone per minute of speech. When the review runs after a recording, this second listen is the review's first step.

The larger model is about 190 MB and comes down the first time it is needed; the home page says **Getting the better voice model**. The better words go in only if the note still reads exactly as Done left it. If you have edited it in the meantime, your edit wins.

## Which engine hears you

| Where | What listens |
|---|---|
| Android phone | Whisper, on the phone |
| Mac | Whisper, on the Mac |
| A browser tab | The browser's own speech recognition, where it has one. No sound is kept and there are no better words. Without one: “Voice notes need the Ghost.md app; this browser has no speech recognition.” |
| The iPhone build, not released yet | Nothing yet: “On-device transcription is not supported on iOS yet.” |

Every engine listens for English.

## The voice model

The first time Ghost.md opens on a phone or a Mac, it fetches the voice model, about 60 MB, so the first press of the side key never waits for it. The home page says **Downloading the voice model, 12 of 60 MB. Keep Ghost.md open.** A download the phone stopped starts again the next time you come back to the app. One that failed says **The voice model didn’t download.** with **Try again**.

With **Local only** on (Settings › Formatting), nothing is downloaded, and the recorder says so: “Local only is on, so the voice model was not downloaded. Turn it off in Settings to get it.”

## Read next

- [[Saying the marks]]
- [[Commands after Hey Ghost]]
- [[The side key, the Fold and the Mac]]
