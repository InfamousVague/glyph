# Pictures, files and voice memos

A note can hold more than words: pictures, videos, PDFs and other files, scanned documents, places, and short voice memos that play from a recording. Each one is a line of Markdown, and the thing itself is kept beside your notes.

## Putting a picture in

- **The + beside an empty line** › **A picture**. Your device's own picker opens.
- **Press and hold** in a note (right-click on a Mac) and choose **Add image**.
- **Paste** a picture you've copied. Any words that came with it are dropped: the picture is what you meant. Several pictures in one paste go in one after another.

The picture goes on the line you were on if it's empty, or on a new line under it, so a sentence is never split. The caret moves below it so you can carry on writing. If a picture doesn't come in, a line under the note's header says why.

In Simple, **A picture** is the first row on the **+**. **A file**, **A video**, **Scan a document** and **A place** are under its **More**.

It's written as one line:

```
![The view from the cabin](image/2b0c4a6e.jpg)
```

The words in the square brackets are its caption, and yours to change. The picture is drawn under the line.

There's no camera inside Ghost.md and no drag and drop. Take the photo with your camera app, then add it from the picker.

**Works on:** Android, iPhone and the Mac. On the iPhone, use **Add image** or paste: the **+** doesn't offer A picture there.

### Pictures made for you

With the Lovart plugin added from the Market, `{image: …}` in a note asks Lovart to draw a picture there, and notes get a **header image**, a wide banner across the top, made when you leave them. See [[Lovart]].

## Words in pictures

On Android and the Mac, Ghost.md reads the words in your pictures and PDFs, so a search finds them. With the caret on a picture's line, **Copy the words in it** copies what it read.

Turn this off with **Read words in pictures** in Settings › Library folder, under **Files and scans**. **Read what is already in notes** goes back over the pictures you added before, and says how far it has got. The same card says how much room the files in your notes take on this device.

## Files

**The + beside an empty line** › **A file** adds any file: a PDF, a document, a spreadsheet, a sound. It's written as a link, with its size:

```
[Lease 2026.pdf](file/9f3e.pdf "2.4 MB")
```

A card under the line says what it is, such as `PDF · 2.4 MB · 12 pages`. Tap it to open the file.

PDFs open in Ghost.md's own viewer, with **Find in this PDF**, **Copy the words on this page**, **Share** and **Open with another app**. Tap the page count to **Go to page**. Other files open with another app on your device; the mark at the end of a card hands any file over that way. Off the caret's line, the link folds to the file's name.

**Scan a document** on the **+** uses your phone's document scanner and adds the scan as a PDF, named for when you made it.

Files up to 25 MB go to your other devices with their notes, sealed with your key. Larger ones stay on the device they were added on, and the card says so elsewhere. A file that isn't on this device yet says so on its card.

**Works on:** files on Android and the Mac. Scanning on Android phones with Google Play services. Not on the iPhone yet: there a file shows as the link it is.

## Videos

**The + beside an empty line** › **A video** adds a film from your phone. It's written as a picture of its first frame, linked to the film:

```
[![video 0:12](image/poster.jpg)](video/a1b2c3.mp4)
```

Tap it to play, with **Full screen** and **Pause**. It never plays by itself. A film stays on the phone it was added on; your other devices show the still and its length, and a card on another phone says "This video isn't on this phone." A shared page shows only the still.

**Works on:** Android.

## Places

**The + beside an empty line** › **A place** puts in where you are, with a map under it:

```
[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
```

Off the caret's line, only the place's name shows. Tap the map to open it in your maps app. A place on a note's first line, or the one under its title, is drawn as the note's header, the map across the page.

With **Local only** on, no map is fetched and A place is greyed out. See [[Links, tags and footnotes]].

## Voice memos

A voice memo is a short clip from a note's recording, drawn as a small player in the line. Tap it to play just that stretch. Only one plays at a time. On its own after a `- ` it reads as a bullet with a player; in the middle of a sentence it's a segment of the words. On the caret's line the mark itself shows, so you can move or delete it.

```
- The view from the deck ![voice 0:12](tape:12000-19500)
```

The numbers say where in the note's recording the clip starts and ends, in thousandths of a second. A memo can also name its recording after an `@`, such as `tape:12000-19500@k3f9x2`, so it never plays a newer recording by mistake. A memo plays from the note's own tape, so it needs that recording to be on the device. With no recording to play, it's a quiet mark with nothing to press.

Recording a note doesn't make memos by itself. They're found in notes from earlier versions of Ghost.md, and you can write one by hand on a note that has a recording.

If you remove a recording that has voice memos, Ghost.md asks a second time first, with **Remove the recording and stop its voice memos**: the memos go quiet until you undo. See [[Tapes and transcripts]].

## Where they're kept

Pictures, files and recordings are kept beside your notes, in the app's own storage, not inside the note's file. The note holds only the line that points at them.

- With an account, they sync to your other devices, encrypted like your notes: pictures, files up to 25 MB, and recordings.
- **Export everything**, in Settings › Account, puts your notes, pictures, files and, if you choose, recordings in one `.ghostex` file to take with you. Settings › Export makes one zip of everything instead. See [[Import, export and backup]].
- A note in the Trash keeps its pictures and recordings until it's deleted for good.

## Removing one

Delete the line and the picture or file is gone from the note. Undo brings it back.

See also: [[Tapes and transcripts]], [[Links, tags and footnotes]], [[Canvases, cards and lines]], [[Lovart]], [[Accounts, sync and encryption]], [[Import, export and backup]]
