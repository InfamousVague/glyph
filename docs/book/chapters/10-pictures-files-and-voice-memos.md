# Pictures, files and voice memos

A note can hold more than words: pictures, videos, PDFs and other files, scanned documents, places, and short voice memos that play from a recording. Each one is a line of Markdown, and the thing itself is kept beside your notes.

## Putting a picture in

- **The + beside an empty line** › **A picture**. Your device's own picker opens.
- **Press and hold** in a note (right-click on a Mac) and choose **Add image**.
- **Paste** a picture you've copied. Any words that came with it are dropped: the picture is what you meant.

The picture goes on the line you were on if it's empty, or on a new line under it. The caret moves below it so you can carry on writing.

It's written as one line:

```
![The view from the cabin](image/2b0c4a6e.jpg)
```

The words in the square brackets are its caption, and yours to change. The picture is drawn under the line.

There's no camera inside Ghost.md and no drag and drop. Take the photo with your camera app, then add it from the picker.

**Works on:** Android, iPhone and the Mac. On the iPhone, use **Add image** or paste: the **+** doesn't offer A picture there.

## Words in pictures

On Android and the Mac, Ghost.md reads the words in your pictures and PDFs, so a search finds them. With the caret on a picture's line, **Copy the words in it** copies what it read.

Turn this off with **Read words in pictures** in Settings › Library folder, under **Files and scans**. **Read what is already in notes** goes back over the pictures you added before.

## Files

**The + beside an empty line** › **A file** adds any file: a PDF, a document, a spreadsheet, a sound. It's written as a link, with its size:

```
[Lease 2026.pdf](file/9f3e.pdf "2.4 MB")
```

A card under the line says what it is, such as `PDF · 2.4 MB · 12 pages`. Tap it to open the file.

PDFs open in Ghost.md's own viewer, with **Find in this PDF**, **Copy the words on this page**, **Share** and **Open with another app**. Tap the page count to **Go to page**. Other files open with another app on your device.

**Scan a document** on the **+** uses your phone's document scanner and adds the scan as a PDF, named for when you made it.

Files up to 25 MB go to your other devices with their notes, sealed with your key. Larger ones stay on the device they were added on, and the card says so elsewhere.

**Works on:** files on Android and the Mac. Scanning on Android phones with Google Play services. Not on the iPhone yet: there a file shows as the link it is.

## Videos

**The + beside an empty line** › **A video** adds a film from your phone. It's written as a picture of its first frame, linked to the film:

```
[![video 0:12](image/poster.jpg)](video/a1b2c3.mp4)
```

Tap it to play, with **Full screen** and **Pause**. A film stays on the phone it was added on; your other devices show the still.

**Works on:** Android.

## Places

**The + beside an empty line** › **A place** puts in where you are, with a map under it:

```
[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
```

With **Local only** on, no map is fetched and A place is greyed out. See [[Links, tags and footnotes]].

## Voice memos

A voice memo is a short clip from a note's recording, drawn as a small player in the line. Tap it to play just that stretch.

```
- The view from the deck ![voice 0:12](tape:12000-19500)
```

The numbers say where in the note's recording the clip starts and ends, in thousandths of a second. A memo plays from the note's own tape, so it needs that recording to be on the device.

Recording a note doesn't make memos by itself. They're found in notes from earlier versions of Ghost.md, and you can write one by hand on a note that has a recording.

If you remove a recording that has voice memos, Ghost.md warns you first: the memos go quiet until you undo. See [[Tapes and transcripts]].

## Where they're kept

Pictures, files and recordings are kept beside your notes, in the app's own storage, not inside the note's file. The note holds only the line that points at them.

- With an account, they sync to your other devices, encrypted like your notes: pictures, files up to 25 MB, and recordings.
- **Export everything**, in Settings › Export, puts your notes and all of these in one file to take with you. See [[Accounts, sync and encryption]].
- A note in the Trash keeps its pictures and recordings until it's deleted for good.

## Removing one

Delete the line and the picture or file is gone from the note. Undo brings it back.

See also: [[Tapes and transcripts]], [[Links, tags and footnotes]], [[Canvases, cards and lines]], [[Accounts, sync and encryption]]
