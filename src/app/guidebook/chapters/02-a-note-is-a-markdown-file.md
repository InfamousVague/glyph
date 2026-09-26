# A note is a Markdown file

_Every note is one plain text file with a name you can read. What its name is made from, what Ghost.md keeps beside it, and where the folder lives._

## One note, one file

A note is a single `.md` file of plain Markdown. Open it in any text editor and it reads as what you wrote.

The file is named after the note's first line of words:

- A heading's `#`s are taken off, and so are the other marks: a list's dash or number, a to-do's box, a quote's `>`, stars, underscores, tildes and backticks.
- A link keeps its words and loses its address. A bare web address is left out.
- A line that is only a picture is skipped, so a note that opens with a photo is named by the words under it.

So a note that begins `- [ ] [Buy milk](https://…) on the way home` is filed as `Buy milk on the way home.md`.

Characters that some computers, phones or sync services refuse are dropped from the name: `/ \ : * ? " < > |`, and `# ^ [ ]` as well. Runs of spaces become one, and a dot or a space at the end goes. A long title is cut at a word, near eighty characters. A title that cleans away to nothing is `Untitled.md`, and a second note with the same name is `Weekend trip 2.md`, then `Weekend trip 3.md`.

When the first line changes, the file is renamed to match. It stays the same note: an id at the top of the file follows it through every rename and move.

A canvas and a book are named by a `title:` line in a small block at the top of their text, and that is the name the app shows everywhere. Their files do not follow it yet. A file's name is taken from the first line of the text, and for them that line is the block's opening `---`, so they are written as `---.md`, then `--- 2.md` and on. The same happens to a note of words once an AI has written in it, because its `authors:` line goes in a block at the top of its text too ([[Asking the AI to work on a note]]). In the app, that note is still named by its first line of words.

## A new note has no file yet

Tap **+** › **Note** and a note opens at once, but nothing is written to the folder until it has words. A note opened and left empty never becomes an `Untitled.md`. Take every word back out of a note you have just started, before you have pinned it or recorded into it, and its file goes again. Pinning or archiving an empty note does write its file.

## Inbox, and the workspaces' folders

New notes land in `Inbox/`. File a note in a workspace and its file moves to `workspaces/<the workspace's name>/`; take it out again and it goes back to `Inbox/`. The folder's name is the workspace's, with the characters a folder cannot hold taken out. Only where the file sits changes, never the words.

A note can also sit anywhere else in the folder, at any depth. Ghost.md reads every `.md` file in it, except inside folders whose names start with a dot, such as `.obsidian` or `.git`.

## The hidden .glyph folder

Beside the notes is one hidden folder, `.glyph`, which holds only what Markdown cannot:

| In .glyph | What it is |
|---|---|
| `index.sqlite` | A copy of every note's words, name, dates and flags, so the list opens at once, and a record of recent spoken commands, so one can be undone. For the notes it is only a cache: when it and the files disagree, the files win and it is rebuilt from them. |
| `notes/<id>.json` | A note's sidecar: how long its recording is, the phrases of it with their times, and the AI's formatted version of the note. A note with none of these has no sidecar at all. |
| `library.json` | A short record of when the library was made. |

Deleting `.glyph` loses no writing. The index is built again from the files. What goes is what only `.glyph` held: which notes have a recording and when each of its words was said, so a note's tape no longer shows, though its sound is still kept; any AI version of a note; and the memory that lets a spoken command be undone.

## Where the folder is, and how to see it

The library is a folder called `Library` in Ghost.md's own storage, on each device. It cannot be moved yet: there is no setting to choose another folder, and no button to rebuild the index, because it mends itself.

Pictures and recordings are kept beside the folder, in the app's storage, not inside it. A picture's line still reads as a picture in another app, but that app will not find the picture's file next to the note. A shared note's Download as Markdown carries its pictures with it ([[Sharing a note or a book]]).

To see the folder, use **Browse files**, the folder button in the sidebar's top row.

- **On Android** it opens the phone's Files app at a place called Ghost.md, with its folders, `Inbox` and `workspaces` among them, and each note as its `.md`. It is read-only there: Files can open, read, copy and share a note, but not change one, because a change made behind the app's back would never reach its list or your other devices. `.glyph` is hidden.
- **On a Mac** it opens the folder in Finder, where it is an ordinary folder.
- An install older than 1.7.2 has no Browse files button.

In a browser tab there is no folder. Notes are kept in that browser's own storage, and pictures in its database, on that computer only unless you sign in and sync.

## A file changed somewhere else

Ghost.md checks the files against its index whenever it reads the list or opens a note. A file changed by another app is read again, a new `.md` file joins the list, and one that has gone leaves it.

So a note written in Obsidian and put into the folder on a Mac opens as it is: its words, its folder and its front matter are kept. A file with no id is given one, written into its front matter the next time Ghost.md saves it. A copy of a note's file, made outside the app, gets an id of its own.

## The front matter Ghost.md writes

A file may start with a block of `key: value` lines between two `---` lines. This is front matter, the same block Obsidian's Properties write. Ghost.md keeps every line of it as it found it: other keys, comments, spacing and quotes. It changes only the keys it manages, and only when their values change.

```
---
id: 7c1e0d9a-3f4b-4c55-9a51-2d6f1f0e8b13
created: 2026-09-14T10:32:10.123Z
source: capture
pinned: true
---
# Weekend trip
```

| Key | What it says | When it is written |
|---|---|---|
| `id` | Which note this is, whatever the file is called | When the file is first written |
| `created` | When the note was first written | When the file is first written |
| `source` | `capture` for a spoken note. A typed note has none. | When a spoken note is first written |
| `pinned` | `true`: pinned. The line goes when it is unpinned. | When the note is pinned |
| `archived` | When it was archived | When the note is archived |

There is no "updated" key: the file's own modified time says when it last changed. Pinning and archiving keep that time as it was, because a pin is not an edit: a note pinned today is not a note changed today.

A second, smaller block can sit at the top of the note's own text, holding what the note itself is named or made of:

| Key | What it says |
|---|---|
| `title` | The name of a canvas or a book, which the app names them by |
| `book` | `true` on a book's index |
| `authors` | Who wrote it, once an AI has written in it: the account's name first, when there is one, then the AI's. The app's own model signs as Ghost, and Claude, writing through the connector, as Claude: `authors: Sam, Claude` |

So a canvas's file opens with two blocks: the file's own, with its id and created time, and then the canvas's, with its title. Another Markdown app reads only the first as front matter and shows the second as words.

## Read next

- [[Finding your way around]]
- [[What stays on your phone]]
- [[The library on disk]]
