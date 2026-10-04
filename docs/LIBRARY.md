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

The library is the app's own folder, `<app_data_dir>/Library`, until the person chooses another with the Library
folder plugin (see "Choosing the folder" below). The layout here is the app's own folder's.

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
  jobs/                         a meeting's write-up while it is under way (Android, DESIGN §127)
    config.json                 what the page chose: the model, the prompts, the piece rule, the two settings
    <id>.progress               how far it has got: the phase, the speech found, the phrases, the notes per piece
    <id>.json                   the summary it wrote, until the page takes it into the note
  images/<name>                 the pictures notes show, a film's poster among them
  video/<name>                  the films notes play, on the phone they were added on (Android, DESIGN §141)
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
(`src-tauri/src/library/names.rs`). The name comes from the first line of the words the page sends, with the page's
own front matter at their top skipped by the page's rule (`frontMatterEnd`), so a canvas or a notebook is named by that
block's `title:`, and a note whose block has none, such as one an AI signed, by its first line under the block. Until
2026-09-27 all of them were named from the block's opening `---`, as `---.md`, `--- 2.md` and so on; such a file takes
its name the next time its note is saved. When the title changes, the file is renamed. The id in its front matter keeps it the same note wherever it moves.

**A new note has no file until it has words.** Ghost.md opens a new note the moment + is tapped, but a note
opened and left empty would be an "Untitled.md" in the folder. Until its first words it is a draft, held in
memory: the open note finds it, the list leaves it out. The first words write the file, with the draft's
created time. A note Ghost.md started as a draft in this run, whose words are all taken out again, with nothing
else set (no pin, archive, recording, or front matter beyond `id`, `created`, `source`), goes back to being a draft
and its file is removed. Pinning or archiving a draft writes its file even without words. A file Ghost.md didn't
start this way is never removed for being empty. A new note the app gave words to from its blank page, a template or
a name tapped as its title (DESIGN §144), has a file at once. Left without a word of the person's own, the page takes
it back, as it takes back a journal's untouched entry (`src/app/core/untouched.ts`). A new note is filed in `Inbox/`,
or in the folder of the workspace being looked at when it was made.

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

The library writes these keys, and only these (`src-tauri/src/library/mod.rs`: a note's first save, `stamp`,
`set_starred` and `set_archived`; `src-tauri/src/library/frontmatter.rs` reads and writes the block):

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
`title:`, which names a canvas or a notebook, since neither has a first line to rename it in; `book: true`, which
makes a note a notebook (docs/BOOKS.md); `authors:`, the names a note was written by, the AI among them
(`src/app/core/authors.ts`); and `look:`, `map` or `reading`, how the note is drawn (`src/app/core/look.ts`, DESIGN
§144). The library does not merge that block into its own. A named notebook's file therefore
opens with two blocks, the library's and then the page's, and an app that reads only the first shows the second as text.
A ticket's properties are that block too (`type: ticket`, its own `id: GHO-12`, its status; docs/TICKETS.md): its `id:`
is the page's, never the library's, and a save keeps the block whole (`a_tickets_front_matter_is_the_pages_and_is_kept_whole`
in `src-tauri/src/library/tests.rs`). A ticket written in another app with its keys in the file's only block is the
case not handled yet: the library reads that `id:` as the note's own.

Keys for a note's tags, its Notion board and its GitHub repo (`tags`, `notion-board`, `project`) are phase 4. The
reader and writer take any top-level key, and a test in `src-tauri/src/library/frontmatter.rs` reads and writes
`tags` and writes `notion-board`; nothing tests `project`. Nothing in the app writes any of the three yet: a note's
links are kept by their plugins (docs/PLUGINS.md). When they are written, plugin keys are to be flat (`notion-board`, not nested), so
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
- **Films** are their poster linked to them, `[![video 0:12](image/<poster>)](video/<name>)`, on a line of their own.
  The poster is a picture like any other. The film is `<app_data_dir>/video/<name>`, outside the library too, and it
  never leaves the phone it was added on: not by sync, a share, or Google's cloud backup (docs/MARKDOWN.md).

Every note renders as valid Markdown on GitHub, in Obsidian, and in any CommonMark renderer that treats a front
matter block as metadata.

## The index

`.glyph/index.sqlite` (for a folder the person chose, `<app_data_dir>/index/<key>.sqlite`) holds a row per note: id, path, the whole body, title, created, modified time and size,
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
When a note is deleted in Ghost.md, its file, its sidecar, its recording and the pictures and films only it used all
go, and a film no note has named for a week goes at the next day's sweep (`src-tauri/src/videos.rs`).
Nothing yet clears a sidecar or a recording whose note was deleted by another app.

A recording's summary and a meeting's transcript are text: the `## Summary` and `## Transcript` sections are in the
note's `.md`, where another app, sync and a share link read them, and nothing about them is kept in the sidecar but
the phrases the transcript was made from. A meeting written up on the phone with the app closed passes through
`<app_data_dir>/jobs/` on the way (`src-tauri/src/jobs.rs`): the transcript goes into the note from there once the
whole recording has been heard, and the summary waits in `<id>.json` until the page next runs and writes it in the
way it writes every summary. The folder is working state, not the note: deleting the note or removing its tape's
audio clears the job's files, and a reset removes the folder whole.

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

## Choosing the folder

Matt: "include #6 as a plugin", #6 being "An Obsidian vault, iCloud Drive or Dropbox. Notes are already plain Markdown
files. Letting you choose where the library folder lives would make Obsidian, backups and other editors work for
free." Settings › Plugins › **Library folder** (off until switched on; `src/app/plugins/folder/`, native generation 25)
chooses it, on the Mac and on Android (DESIGN §185).

- **Where it is** is `<app_data_dir>/library-root.json`, absent for the app's own folder: `{ "kind": "folder", "path":
  … }` on the Mac, `{ "kind": "tree", "uri": …, "name": … }` on Android. Rust reads it in one place
  (`src-tauri/src/library/root.rs` `Root::read`), and everything that opens the library opens it there
  (`src-tauri/src/library_root.rs`): the launch, a meeting's write-up over JNI, the export, Reveal, the reset. Kotlin
  reads it too (`files/LibraryTree.kt` `LibraryRoot`).
- **Choosing.** Only in the system's own folder panel (the Mac, `library_choose_folder`) or picker (Android,
  `GlyphHost.chooseLibraryFolder`, ACTION_OPEN_DOCUMENT_TREE, its grant kept with `takePersistableUriPermission`, then
  `library_inspect`). The page never sends a path. The folder is looked into and nothing is written there: how many
  Markdown files it holds and whether Obsidian keeps it, and the page says what will happen. A folder inside the app's
  storage, the library itself, or one inside it or holding it, is refused.
- **Moving in** (`library_move`, `src-tauri/src/library/relocate.rs`). The folder is taken as it is: every `.md` in it
  is a note from the first scan (an id goes into its front matter the first time Ghost.md saves it), and `.obsidian/`,
  `.trash/` and every other dot folder are left alone. The app's notes are copied in beside them at the paths they had
  (`Inbox/…`, `workspaces/<name>/…`), each with its front matter, modified time, sidecar, versions file and revision; a
  file of that name already there gives the note " 2". A note already there by its id, word for word, is not written
  twice; with other words, it goes in beside it under an id of its own. Then the setting switches, and only then do
  the notes leave the app's own folder. A copy that stops part way takes back exactly the files it wrote, and nothing
  has moved. The new library replaces the old one in the running app, drafts carried, so nothing restarts.
- **Going back** (`library_use_app_folder`) is "Bring a copy back", every note copied into the app's own folder, or
  "Start empty". The chosen folder keeps every file either way. **Ghost.md removes files only from its own folder**:
  leaving a folder of the person's for another copies too.
- **The index is never in a chosen folder.** SQLite in WAL mode is three files a sync service would copy one at a time,
  and two Macs on one Dropbox folder would each write the other's. A chosen folder's index is
  `<app_data_dir>/index/<key>.sqlite`, the key an FNV-1a hash of where the folder is. `library.json` and
  `.glyph/notes/<id>.json` stay in the folder: small JSON written whole, which sync carries like the notes, so a
  recording's phrases go where the note goes.
- **Names.** In the app's own folder a file is renamed when its note's title changes, as always. In a chosen folder only
  a file Ghost.md named (named for its title already) is: `2026-10-01.md` in an Obsidian vault keeps its name when it is
  edited here, so its daily note and every `[[link]]` to it still find it.
- **A folder that cannot be reached** (a drive unplugged, a folder moved, a grant taken back) opens the app's own folder
  for that run, and the page says so. The choice is kept and tried again at the next launch, and a folder that is not
  there is never made empty.
- **A reset** forgets the folder: the setting, `index/` and `trees/` in the app's storage. It goes back to the app's own
  folder and empties that, as it always did. Not one file in the chosen folder is touched, `.glyph/` in it included.

**iCloud Drive on the Mac.** With "Optimise Mac Storage" on, the Mac takes a file it has not opened lately off the disk
and leaves `.Note.md.icloud` in its place. That placeholder answers for the note (`src-tauri/src/library/vault.rs`): the
list keeps the row it had, a new note never takes its name, and opening it asks iCloud for the file (`brctl download`)
and waits three seconds. One that has still not come down opens with the words the index last read, and a save to it
is refused with "is in iCloud Drive and not on this Mac yet", never written over. A placeholder the index never read is
asked for, and is a note from the scan after it comes down. Newer Macs keep a dataless file under the note's own name
instead, which reads like any other and downloads as it is read.

**Android.** A folder chosen there has document ids, not paths, so it is the second `Vault`
(`src-tauri/src/library/tree.rs` `TreeVault`), each call into Kotlin over JNI (`src-tauri/src/saf.rs`, the first calls
from Rust into Kotlin; `files/LibraryTree.kt`). A path is walked by display names, one DocumentsContract query per folder
with only the columns needed, and the ids found are kept. What SAF cannot do: `.glyph/` needs real paths, so it is in
the app's storage at `<app_data_dir>/trees/<key>/`; a file's modified time cannot be set, so the time a pinned note
shows is kept there in `kept-times.json` against the time and size the file really has, and shows until another app
changes the file; and a write is in place ("wt"), not atomic. iCloud Drive has no Android app, so no folder of it can
be chosen; Dropbox and Google Drive reach the picker through their own apps, which may keep a note online only and open
it slowly. A folder on the phone, which Syncthing keeps in step, is the reliable case. While the library is in such a
folder the Files app lists no "Ghost.md" place of its own, and Browse files opens the folder itself.

Not done: a folder changed by another app is seen at the next list or open, as before, since nothing watches it; a
folder on an iPhone; pictures, films and recordings, which stay in the app's storage wherever the notes are.

## Seeing the folder

The sidebar's Browse files button shows the library where the device shows folders (`src/app/core/libraryFiles.ts`,
native generation 18). On a Mac that's Finder (`library_reveal`). On the phone it's the Files app, where Ghost.md
lists the library as a place of its own
(`src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/files/LibraryDocuments.kt`, a DocumentsProvider).
It's read-only there: another app can open, copy and share a note, but can't change one behind the library's back,
where the index and sync wouldn't see it. `.glyph/` is hidden.

## Exporting everything

Settings › Account › Export › **Export everything** writes the whole library, and everything beside it a note shows
or plays, as one zip, `ghostmarkdown_<date>_<time>.zip` on the device's clock (DESIGN §167). On the Mac the save
panel asks where, and on Android the system's picker does; a USB drive plugged in is one of the places either way.
Inside is one folder of the archive's name: `Library/` as it is here (with `.glyph/library.json` and the phrases in
`.glyph/notes/`, but not `index.sqlite`, which is rebuilt from the files), `images/`, `video/` and `recordings/`, a
`settings.json` with the page's settings (no account, password or token), a `manifest.json`, and a `README.txt` that
says what each folder is. The models, the write-ups under way, the over-the-air builds and `notion.json` stay behind.
`src-tauri/src/export.rs` writes it, as a stream, so Android's picker hands Rust the new file's descriptor and nothing
is built on the phone first; a failed or stopped export takes its half-written file away again. A browser zips the
notes and pictures it keeps. With the library in a folder of the person's, `Library/` is that folder as it is (on the
Mac, `.obsidian/` and whatever else is in it included); a folder chosen on Android has no path to walk, so its notes
and versions files are read through the library as text and `.glyph/` comes from the app's storage.

## Phases

1. **Built (1.3.0, native generation 15).** This spec, and the library in Rust behind the store commands the page
   already uses, in app storage (`<app_data_dir>/Library`), with the move from the database.
2. **Built (native generation 25), as the Library folder plugin.** Pick a folder with the Mac's folder panel or
   Android's folder picker (the Storage Access Framework), and move the library there, or take a folder of Markdown
   as it is ("Choosing the folder"). Recordings, pictures and films stay in the app's storage.
3. **Partly built.** Folders in the app: Inbox, and a folder for each workspace, are built. Making folders of
   one's own, moving notes between them, and pictures in an attachments folder are not.
4. **Planned.** Plugin links (Notion board, GitHub repo) and tags into front matter.
