# Pictures and voice memos

_How a picture gets into a note and where it is kept, the + beside the line and the places and films it adds, the recording behind a spoken note, and the voice memos that play from it._

## Putting a picture in

- **The + beside the line.** On an empty line, tap the + in the margin and choose A picture, as below.
- **Add image.** Press and hold in a note, or right-click, and choose Add image. On Android it opens the phone's own picker, and on the Mac and in a browser tab a file chooser. On the Mac a file that is not a picture is refused, and a HEIC photo the Mac cannot open says to save it as a JPEG first. The iPhone build, which is not released, has no picker yet: there Add image says this build cannot add pictures, and pasting is the way in.
- **Paste.** Paste a picture with the keyboard, or with Paste in the press-and-hold menu where the menu offers it. Any text that came along in the same paste, such as a web page's address, is dropped: the picture is what was meant.
- **Drop.** Dropping a picture works on a canvas, where it becomes a card ([[Canvases, cards and lines]]). A note does not take a dropped picture.

The picture goes in on the line you were on if that line is empty, or holds only a list's dash or a to-do's box, or else on a new line under it. The caret moves below it, so you carry on writing underneath. It never splits a line in two. Under a list, a quote or a table it leaves a blank line first, so it is not read as part of them.

## The + beside the line

Rest the caret on an empty line, and a small **+** comes into the margin beside it. An empty line is one with no words: nothing at all, or only a list's dash, a to-do's box or a quote's mark, beside which the + sits smaller and further out, so the two never read as one. Type a letter and the + goes. There is none on a line with words, in a block of code, in the front matter, while you only read, or while the AI is writing into the note.

Tap it, or click it, and it turns into a × and a short list opens beside it. The keyboard stays up and the caret stays where it was. On the Mac the arrow keys move through the list, Return chooses, Escape closes it, and Left goes back from More.

| Row | What it puts in |
|---|---|
| A picture | A picture from the phone's picker, on a line of its own |
| A video | A film from the phone's Photo Picker, on a line of its own, drawn as a still you tap to play. On Android only |
| A place | Where you are now, as a line naming the place, with its map under it |
| The date and time | The date and time as the row shows it, such as 28 Sept 2026, 14:05, where the caret is |
| A table | A small table, its first heading picked out to write over |
| A note | A link to another note: type part of its title and choose it |
| A to-do | A to-do's box. An empty list item becomes a to-do. |
| More | The rest, on a second page of the same list |

More holds a heading, a bulleted list, a numbered list, a quote, a callout, a choice, a block of code, a divider, a board, a chart, a canvas drawn in a frame, a footnote, a tag, a counter, a sum, and each effect that is switched on, named as it is said, such as Heated words. Each comes with a little to write over. A footnote's number goes at the end of the words just above, and its line at the end of the note. Back, at the top, goes to the first page, and so does the back gesture. More and Back never scroll out of sight, however little room the keyboard leaves.

Each is one Undo, and what it puts in is there at once. A row the device cannot do is not in the list: the Mac has no place, since it cannot say where it is, and no picture yet. Only the Android app has A video, and only once it is the newest, since the app itself picks and keeps the film. A row a setting holds off is greyed, with the setting named.

## A place

A place is one line, a link to where it is:

```
[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
```

Under a line of words it leaves a blank line first, so no other app reads it as the end of your sentence. Away from the caret the line reads as the name alone, with the map under it. Tap the map to open the place in your maps app. A note can hold as many places as you like. Where the note itself was written is another thing, kept at the top of the note with its own map.

The name is asked of OpenStreetMap while the phone finds where you are, when Place names is on in Settings › Account › Location. When no name comes within a few seconds the line keeps the coordinates, and the name is written in afterwards only if you have done nothing in the note since. Under Local only the row is greyed, and a place already in a note shows its map quiet, with no tiles. A shared note leaves its places out unless you tick **Share the places in it** ([[Sharing a note or a notebook]]). Other apps show the line as a link.

## A video

**A video** opens the phone's Photo Picker. It asks for no permission: the app sees only the film you choose. The film is kept as it was filmed, with a still from near its start, and a long one takes a moment to copy once you have chosen it, while the note says "Adding the video." One film is added at a time. The phone keeps at least 500 MB free, so a film that would fill it is refused, and says so. MP4, MOV and WebM films are kept, and any other kind is refused in words.

A film is one line, its still linked to it:

```
[![video 0:12](image/5f0c2e9a….jpg)](video/8d1e4b7c….mp4)
```

Away from the caret the line reads video 0:12, with the still under it and the length at its foot. Tap it to play, with sound, and tap again to pause. The corner opens it full screen, and the back gesture closes it. Nothing plays by itself, and one film plays at a time.

The film stays on the phone you added it on. It is not synced, not shared, and not sent to Google's backup. Moving to a new phone by cable is meant to carry it, though that has not yet been tried with Smart Switch. The still goes wherever the note goes, as any picture does. So your other devices show the still, and say the film stays on the phone it was added on, and a shared note shows the still and says only a still is shared. On a phone where the film is not, the card says "This video isn’t on this phone." instead of offering to play. A film that is there but that the phone cannot play says "This video can’t be played on this phone." An app older than the films says to update it.

## What it is written as

A picture is one line of Markdown:

```
![A wisp of smoke](image/5f0c2e9a….jpg)
```

The words in the square brackets are its caption, which you can write or leave empty. After `image/` comes the picture's name, a long run of letters, digits and dashes given to it when it arrives and never changed; it is cut short here. The line stays on the page, dimmed like any mark, and the picture is drawn under it. Delete the line and the picture leaves the note.

Only a picture written as `image/` and a name is drawn. A picture line from another app, pointing somewhere else, stays a line of Markdown.

## Made smaller, and kept

A pasted picture is kept at most 1600 pixels on its long side, as a JPEG, turned the right way up, with white paper under a picture that had no background. The phone's picker makes a picked photo smaller the same way before the app sees it. A photo straight off the camera is several times what a note ever draws.

The app keeps its pictures in its own storage, beside the library of notes rather than inside it ([[A note is a Markdown file]]). In a browser tab, the browser keeps them in its own database.

## Where pictures go with their note

- **Sync.** Signed in, a note's pictures go with it to your other devices, sealed the way the note is ([[Accounts, sync and the key you hold]]). A picture that has not reached a device yet is drawn as soon as it arrives.
- **Sharing.** A shared note or notebook carries the pictures its pages show, since a reader has no account to fetch them from. When they will not all fit, each is sent as a smaller reading copy, and failing that, as many as fit, in the order the pages show them ([[Sharing a note or a notebook]]).
- **Download as Markdown**, on a shared page, gives a note with pictures as a zip, with the pictures in an `image` folder beside the page, where its picture lines point.

## A spoken note's recording

A note you speak keeps its recording. At the top of the note is its tape: a cassette with the note's name and the day it was made, **Play**, the time, and two words, **Add** and **Remove**.

- Tap the cassette, or Play, to hear it. The reels turn and the tape winds across as it plays, so the picture is the progress bar.
- **Add** records more into the same note. The new take goes on the end of the same tape, and its words on the end of the note.
- **Remove** takes the recording off the note, and a message offers Undo. If the note has voice memos, it asks first, because they play from the recording: "The voice memos in this note play from this recording. They'll stop until you undo." Then **Keep** leaves it, and Remove again removes it.

Signed in, the recording goes to your other devices with its note, sealed the same way the note is.

A note with no recording has no tape. Its tools have a microphone instead, Talk into this note, and once you have spoken into it, the tape appears. Recording is [[Recording a note]].

## Voice memos

A voice memo is a stretch of a note's tape kept as sound: a tune, a name nobody can spell, somebody else's voice, the way a sentence was said. A memo already in a note plays where it sits.

The recorder does not make new ones. Saying "voice memo", then talking, then "end memo" writes all of those words into the note like any others, and no clip is kept.

A clip on a bullet line is a bullet with a player on it. In the middle of a sentence it is a small player in the words. It is written like this:

```
![voice 0:12](tape:12000-24000@…)
```

That is its length, then where on the tape it starts and ends, in thousandths of a second, then after the `@` a short name for the tape it belongs to, left out here. Read in any other app, "voice 0:12" still says what it is.

In Ghost.md a small player stands in its place. Tap it to play that stretch of the tape, one memo at a time. On the line the caret is on, the written form comes back, with the player after it, to read, move or delete.

A clip plays only while the note's tape still carries it. After the recording is removed, or in a browser tab, the clip is a quiet mark, voice 0:12, with nothing to press. The name of a note's tape is kept on the device that recorded it, so for now a memo plays only there: on your other devices, even once the recording has synced, it shows as the same quiet mark.

## When a note is deleted

Moving a note to the Trash changes nothing about it: its words, recording, pictures and films wait there with it. Deleting it for good, from the Trash or by emptying the Trash, removes its file and its recording, and every picture and film it showed, except one another note still shows. A film you take out of a note is kept for a week, in case you undo, and then goes.

## Read next

- [[Recording a note]]
- [[Sharing a note or a notebook]]
- [[Canvases, cards and lines]]
