# The Ghost.md library

Ghost.md keeps notes as a folder of plain Markdown files. The folder is the library: open it in Obsidian, a file
manager, Syncthing or a text editor and every note is there, readable and editable, with nothing locked inside
the app. Ghost.md adds only what Markdown can't hold on its own: a small hidden folder with an index to find
things fast, and the facts about a note that aren't text (its recording's phrases and length).

Matt's brief: "a folder and sub folders full of purely markdown files with a small flat file things like sqlite
or json files for indexing so we can keep our whole library in these files … it should all render to valid
markdown but store metadata we can specially format such as linked notion tickets and to-do lists." His
choices: a folder he picks, his own folders with titles as file names, Obsidian-compatible metadata, and a
hidden `.glyph` folder for everything else. Not all of that is built: the list of phases at the end says what is.

The library is in Rust, `src-tauri/src/library/`. The page reaches it through the store commands
(`src/app/core/store.ts`); in a browser there is no library, and notes live in `localStorage`.

## The folder

Today the library is a fixed folder in the app's own storage, `<app_data_dir>/Library`. Picking a folder of one's
own is phase 2, not built.

```
<app_data_dir>/
  Library/                      the library
    Inbox/                      where new notes land, and a note with no workspace
    workspaces/
      Work/                     a note filed in the Work workspace
        AttackFM.md
        HelloTrade.md
    .glyph/                     Ghost.md's own, rebuildable, hidden from most apps
      library.json              { "version": 1, "created": …, "movedFrom": …, "movedNotes": … }
      index.sqlite              the index: a cache, rebuilt from the files at any time
      notes/<id>.json           what a note has that isn't text: its recording's length and phrases
  recordings/<id>.wav           a note's kept recording, beside the library rather than in it
  images/<name>                 the pictures notes show
```

Filing a note in a workspace moves its file into `workspaces/<the workspace>/`, and taking it out of one moves it
back to Inbox (`src/app/core/noteFolders.ts`). A note can also sit anywhere else in the folder: a file put there
by another app is read where it is.

Deleting `.glyph` loses no writing: the index is rebuilt from the files. What goes is each recording's phrases, which
line its words up with its sound, and the undo of recent voice commands.

## A note

A note is one `.md` file named after its title: the first heading, or the first line of words. Characters a
file name can't hold, or a sync service refuses (`/ \ : * ? " < > |`, and `# ^ [ ]`), are dropped with any bold
marks, a title longer than 80 characters is cut at a word, an empty one is "Untitled", and a clash gets " 2", " 3"
(`src-tauri/src/library/names.rs`). The name comes from the first line of the words the page sends, so a canvas or a
book, whose words open with the page's own front matter, is named from that block's opening `---` rather than from
its `title:`. When the title changes, the file is renamed. The id in its front matter keeps it the same note wherever it moves.

**A new note has no file until it has words.** Ghost.md opens a new note the moment + is tapped, but a note
opened and left empty would be an "Untitled.md" in the folder. Until its first words it is a draft, held in
memory: the open note finds it, the list leaves it out. The first words write the file, with the draft's
created time. A note Ghost.md started as a draft in this run, whose words are all taken out again, with nothing
else set (no pin, archive, recording, or front matter beyond `id`, `created`, `source`), goes back to being a draft
and its file is removed. Pinning or archiving a draft writes its file even without words. A file Ghost.md didn't
start this way is never removed for being empty.

```markdown
---
id: 7c1e0d9a-3f4b-4c55-9a51-2d6f1f0e8b13
created: 2026-09-14T10:32:10.123Z
pinned: true
---

# AttackFM bug bash

Friday, all hands.

- [ ] Fix the seek bar drift on two devices [notion](https://www.notion.so/3d6522a4…) 📅 2026-09-20
- [x] Downloads stuck on the discover list ✅ 2026-09-14
- [ ] Ship the APK

| Bug | Owner | Status |
| --- | --- | --- |
| Seek bar drift | Matt | Open |

![](image/2b0c4a6e-1f7d-4b8a-9c3e-5d2a7f10e4b6.jpg)
```

### Front matter: YAML, as Obsidian's Properties write it

The library writes these keys, and only these (`src-tauri/src/library/frontmatter.rs`):

| Key | Meaning | Written when |
| --- | --- | --- |
| `id` | The note's identity, stable across renames and moves | Ghost.md first saves the file |
| `created` | When the note was first written, ISO 8601 | Ghost.md first saves the file |
| `pinned` | `true`: at the top of the list | pinned |
| `archived` | When it was archived, ISO 8601 | archived |
| `source` | Where it came from, when that isn't typing: `capture` | recorded |

- **Updated** isn't a key. The file's own modified time is when it was last changed, so a save doesn't rewrite
  a date.
- **Unknown keys, comments and formatting are kept exactly as they were.** Ghost.md only rewrites a line that holds
  a key it manages, and only when that value changes. A file without front matter gets it only when Ghost.md has
  something to store. The reader is not a YAML library, on purpose: a library would write the block back in its own
  style.

The page keeps a few keys of its own in a block at the top of the note's words (`src/app/core/frontMatter.ts`):
`title:`, which names a canvas or a book, since neither has a first line to rename it in; `book: true`, which makes a
note a book (docs/BOOKS.md); and `authors:`, the names a note was written by, the AI among them
(`src/app/core/authors.ts`). The library does not merge that block into its own. A named book's file therefore opens
with two blocks, the library's and then the page's, and an app that reads only the first shows the second as text.

Keys for a note's tags, its Notion board and its GitHub repo (`tags`, `notion-board`, `project`) are phase 4. The
reader and writer handle them, and a test round-trips them, but nothing writes them yet: a note's links are kept by
their plugins (docs/PLUGINS.md). When they are written, plugin keys are to be flat (`notion-board`, not nested), so
Obsidian's Properties panel can show and edit them.

### The body: GitHub-flavoured Markdown

- **To-dos** are task list items, `- [ ]` and `- [x]`.
- **Dates on to-dos** use the Obsidian Tasks emoji: `📅` due, `⏳` scheduled, `🛫` start, `✅` done, `🔁`
  recurring, `⏫ 🔼 🔽` priority. They sit at the end of the item.
- **A list item linked outside Ghost.md** keeps its words plain and ends with a mark: a link whose words are the
  plugin's name, `[notion](https://www.notion.so/…)`, before any Tasks dates. It renders as an ordinary link
  anywhere, and Ghost.md draws it as a small pill.
- **Tables** are GFM tables. **Links to other notes** are ordinary relative Markdown links or `[[wiki links]]`
  (docs/MARKDOWN.md).
- **Pictures** are `![](image/<name>)` on a line of their own, a relative path. The file is
  `<app_data_dir>/images/<name>`, outside the library, so another app opening the folder does not find it. Pictures
  inside the library, in an attachments folder, are phase 3.

Every note renders as valid Markdown on GitHub, in Obsidian, and in any CommonMark renderer that treats a front
matter block as metadata.

## The index

`.glyph/index.sqlite` holds a row per note: id, path, the whole body, title, created, modified time and size,
source, pinned, archived, whether the id is written in the file yet, recording length, the formatted version's
hash and model, and a revision that counts every write (`src-tauri/src/library/index.rs`). Keeping the body is what
lets the list open instantly and search stay fast. A second table keeps the voice commands' writes, for their undo
(docs/instruction-voice-commands.md). It is never the truth:

- **Opening the library** walks the folder. A file whose modified time and size match its row is skipped;
  anything else is read again. A row without a file is dropped. A note opened whose file reads differently from its
  row is read again, even when its time and size did not change.
- **A file without an `id`** (written by another app) gets one in the index at once, and in its front matter the
  next time Ghost.md saves that note.
- **Two files with the same `id`** (a copy made outside Ghost.md): the one the index already knew keeps it, and the
  copy gets a new one, written to its front matter when next saved.
- **A new index version** drops the tables and walks the folder from scratch. There is no rebuild button.

## What isn't text: `.glyph/notes/<id>.json`

```json
{ "recordingMs": 184000, "segments": [{ "text": "Bug bash on Friday.", "startMs": 0, "endMs": 1900 }] }
```

A note with none of these has no sidecar. The sidecar also has room for a formatted version (`formatted`,
`formattedFor`, `formattedModel`) from before 1.8.0, when the model's words went beside a note. Since DESIGN §114
they land in the note itself, and nothing writes those fields now; sync still carries what an older note has.

A note's kept recording is `<app_data_dir>/recordings/<id>.wav`, outside the library (`src-tauri/src/recordings.rs`).
When a note is deleted in Ghost.md, its file, its sidecar, its recording and the pictures only it used all go.
Nothing yet clears a sidecar or a recording whose note was deleted by another app.

## Moving in

The first time a Ghost.md with the library opens, every note in the old database is written out as a file
(`src-tauri/src/library/move_in.rs`):

- **Where:** in Inbox, named by its title.
- **Front matter:** its id and created time, pinned, archived and source.
- **The rest:** its recording's phrases and its formatted version into `.glyph/`.

A note with no words and nothing set (no pin, archive, recording or formatted version) is left behind: the old app
saved a new note the moment it was opened, so these are notes opened and left, and would each be an empty
"Untitled.md".

The old database is kept beside it, renamed `glyph.sqlite.moved`, and `library.json` records the move. Nothing
is deleted. The rename happens only once every note is written: a move that stops halfway (the app killed,
the storage full) leaves the database in place, and the next launch finishes it, since a note already in the
library is never written twice.

## Seeing the folder

The sidebar's Browse files button shows the library where the device shows folders (`src/app/core/libraryFiles.ts`,
native generation 18). On a Mac that's Finder (`library_reveal`). On the phone it's the Files app, where Ghost.md
lists the library as a place of its own
(`src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/files/LibraryDocuments.kt`, a DocumentsProvider).
It's read-only there: another app can open, copy and share a note, but can't change one behind the library's back,
where the index and sync wouldn't see it. `.glyph/` is hidden.

## Phases

1. **Built (1.3.0, native generation 15).** This spec, and the library in Rust behind the store commands the page
   already uses, in app storage (`<app_data_dir>/Library`), with the move from the database.
2. **Planned.** Settings › Library: pick a folder with Android's folder picker (the Storage Access Framework), and
   move the library there, recordings and pictures with it.
3. **Partly built.** Folders in the app: Inbox, and a folder for each workspace, are built. Making folders of
   one's own, moving notes between them, and pictures in an attachments folder are not.
4. **Planned.** Plugin links (Notion board, GitHub repo) and tags into front matter.
