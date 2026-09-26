# The library on disk

_Every note is a Markdown file in a folder. An index beside the files makes the list instant, and the files win whenever the two disagree._

## The rule

`src-tauri/src/library/mod.rs` opens with it: the files are the truth, and `.glyph/index.sqlite` is a cache. The index holds each note's whole body, so the list draws without opening a file, and it is checked against the files before it answers. Nothing in it is ever the only copy of a note's words. Two things it keeps exist nowhere else: each note's revision, and the undo record of voice commands. Neither is a note, and losing them loses no writing.

The library has no `tauri::` type in it, on purpose (`src-tauri/src/note.rs` says why): a process with no webview must be able to link it, so every path it needs is handed in by the caller. `commands.rs` opens one `Library` at launch and holds it behind a mutex for the life of the process. If it cannot open, the launch fails, because an empty list that silently drops what is typed into it is worse than not starting.

## Where things are on disk

`src-tauri/src/paths.rs` resolves every directory in one place. Under the app's data directory:

| Folder | Holds |
|---|---|
| `Library/` | the notes as `.md` files, and `.glyph/` |
| `recordings/` | a spoken note's kept audio, `<id>.wav` |
| `images/` | pictures in notes, a random name with `.jpg`, `.png` or `.webp` |
| `models/` | Whisper's and the language models' files |
| `ota/` | downloaded frontends and update state |

Inside `Library/`, `.glyph/` holds `library.json` (the library's birth, and the one move from the old database), `index.sqlite`, and `notes/<id>.json`, a sidecar per note for what is not text. Pictures and recordings live outside the library: a note links a picture as `![](image/<name>)`. Four directory names are also spelt in Kotlin, and a test in `paths.rs` reads the Kotlin sources, so renaming one side alone fails that test.

## Saving a note

`Library::save_note` writes the body under the note's front matter. `frontmatter.rs` is not a YAML library, on purpose: a library would parse the block and write it back in its own style, with keys reordered and comments gone. It keeps the block as lines, reads the few top-level keys Glyph knows, and rewrites only the lines of a key whose value changes. Unknown keys, nested maps, comments and the person's quoting come back byte for byte. A save always writes `id`, so every file Glyph saves has a block.

The library writes five keys: `id`, `created` (ISO 8601, `dates.rs`), `source` (left out for a typed note, `capture` for a spoken one), `pinned: true` and `archived: <when>`. There is no `updated`: the file's own modified time is when the note last changed. The page keeps a block of its own at the top of the words, for the keys the library does not manage: a book's or a canvas's `title:`, a book's `book: true`, and the `authors:` of a note written with an AI (`src/app/core/frontMatter.ts`). That block is part of the body, so such a file opens with two blocks, the library's and then the page's.

A new note goes into `Inbox/`, named after its title. `names.rs` (`title_of`) takes the first line of words and goes further than the page's `noteTitle`: a heading's `#`s, a quote's `>`, a list or task marker, emphasis and code marks, a link's address (its words stay), bare addresses, a picture line and a trailing plugin mark such as `[notion](…)` all go. Then it makes a safe file name. It drops the characters a file system refuses, and also `#`, `^`, `[`, `]` and control characters, removes emphasis marks, collapses spaces, and trims a trailing dot and any leading one. The stem is at most 80 characters (`MAX_STEM`), cut at the last space when that falls past the halfway mark. An empty stem is `Untitled`, and a clash gets ` 2`, ` 3` and on. When a saved note's title changes, its file is renamed within its folder. An edit under the same title leaves a numbered name alone.

**A second known gap.** `title_of` does not skip the page's own front matter. A note whose words open with a block, such as every book and every canvas, is titled `---`, and its file is `---.md`, `--- 2.md` and on. The list and the tabs show the right name, because `noteTitle` skips the block and reads `title:`.

## Drafts until the first words

A new note has no file until it has words. `save_note` with a blank body and no row keeps the note in memory as a draft: `get_note` finds it, and the list leaves it out. The first words write the file, with the draft's own created time. A note this process started as a draft, emptied again with nothing else set (no pin, archive or sidecar, and no front matter beyond `id`, `created` and `source`), goes back to being a draft, and its file is removed. Pinning, archiving or keeping a recording writes a draft's file without words. A file Glyph did not start this way is never removed for being empty.

## Inbox and the workspace folders

`Inbox/` is `INBOX` in `mod.rs`. Workspaces decide the rest. `src/app/core/noteFolders.ts` moves a filed note's file to `workspaces/<name>/`, and moves a note taken out of its workspace back to `Inbox/`. The name loses the characters a folder cannot hold and any dots or spaces at its ends, and is cut to 60 characters. The page never touches the disk: it hands `store_apply` the note with a new `path`, and `Library::apply_note` renames the file if that path is free. A path from outside must be relative, end in `.md`, and hold no dot folder and no `..` (`library_path`). A path already taken leaves the file in its folder.

## Pin and archive are not edits

`set_starred` and `set_archived` go through `set_front`. It rewrites the front matter line, then puts the file's modified time back (`Vault::keep_modified`), so a pin does not move a note up the list. A recording's length and phrases (`set_recording`) and the on-device model's formatted version (`set_formatted`) go in the sidecar, `.glyph/notes/<id>.json` (`sidecar.rs`), and the body and its time stand. A sidecar is written only under an id that could be a file name (`fsx::plain_id`). It is written whole or not at all, and removed when it empties.

## Reading what another app changed

`list_notes` calls `scan` first (`index.rs`), which walks the folder. A file whose modified time and size match its row is skipped. Anything else is read into the index again, and a row with no file is dropped. `get_note` reads the note's file and scans if the file has gone or its body differs from the row's. A file without an `id` gets one in the index at once, and in its front matter the next time Glyph saves it. Two files with the same `id`, such as a copy made in Finder, are told apart: the file the index already knew keeps the id, and the copy gets a new one.

**The known gap.** Another app can change a file and leave its size and modified time as they were: a same-length edit on a coarse clock, or an editor that sets the time back. Then `get_note` sees the body differ and asks `scan`, `scan` passes the file over, and the answer is the index's old copy. A write that follows carries on from that stale body. The fix, bad704c, made `get_note` re-read that file whatever its time and size. It was reverted in d909b9d because it changes what `update_note`, `apply_command` and `latest_command_undo` answer after such an edit (a refusal where today they carry on), and it waits to land on its own. On a phone no other app can reach the library, so this is a desktop problem.

## A revision per file

Every row carries a `revision`, and the page writes against it. `create_note` refuses an id already in use. `update_note` writes only the revision it was given, and a missing or changed note is a refusal, never a new file, so a stale autosave cannot bring a deleted note back. `index_file` moves the revision on whenever a file's body changed, however it changed. A note that arrives by sync takes the revision it came with (`apply_note`). The revision lives only in the index, so a rebuilt index starts every note at 1 again. An index of another shape (`INDEX_VERSION`, now 2) is dropped and rebuilt, since it is only a cache.

## Voice commands' guarded writes

`mutations.rs` is what a confirmed Hey Ghost command writes through. `apply_command` applies the previewed Markdown only while the note's revision and body are exactly what the preview was made from, and records the change in the index's `command_mutations` table. `undo_command` reverses it only while the note is exactly what the command left. Anything else is a conflict, answered with the note as it now is. `commands.rs` checks the request whole before anything is written: plain bounded ids, a source of `editor` or `capture`, a kind of `append` or `create`, and no field it does not name. `latest_command_mutation` offers again the newest command from the last ten minutes that still stands, for an app that was stopped mid-undo.

## The one move from SQLite

Before 1.3.0 the notes were rows in `glyph.sqlite`, and `src-tauri/src/store.rs` is now only the reader of that file. The first launch with the library (`move_in.rs`, `open_and_move_in`) writes every note out into `Inbox/`. It keeps each note's id, times, pin, archive, source, recording phrases and formatted version, and sets each file's modified time to the note's own. A note with no words and nothing set is left behind, since the old app saved a note the moment it opened. Only when every note is out does `library.json` record the move, and the database becomes `glyph.sqlite.moved`, with its `-wal` and `-shm` beside it. A move that stops halfway finishes at the next launch, because a note already in the library is never written twice.

## The vault

Every read and write of a note goes through the `Vault` trait in `vault.rs`, with relative paths and forward slashes. `FsVault`, over `std::fs`, is the only implementation, and the tests in `library/tests.rs` run it over temporary folders rather than a stand-in. The trait was made for a folder picked through Android's Storage Access Framework, whose files have no paths. That second vault is not built. `FsVault` refuses a path with `..`, an empty part or a leading `/`, and writes each file whole through a hidden temporary file beside it, which the walk skips.

## The page's door

`src/app/core/store.ts` is the one way the page reaches notes. It is a typed remote control for the commands in `commands.rs`: `list_notes`, `get_note`, `create_note`, `update_note`, `delete_note`, `set_note_starred`, `set_note_archived`, `set_note_recording`, `store_apply`, and the three command-mutation calls. `set_note_formatted` is still a command in `commands.rs`, and nothing on the page calls it now. Every write through `store.ts` sends `glyph:note-saved` on `window`, which sync listens for, except `applyNote` (`store_apply`): that note came from sync, or a workspace moved its file, and the next pass finds it either way. In a browser, for `npm run dev`, the same functions keep notes in `localStorage` under `glyph-notes`, with the same guarantees: a create refuses a taken id, and an update checks the revision.

Deleting a note removes its file, sidecar and row. Then each of its pictures that no other note still shows goes (`Library::image_in_use`), and then its recording.

## Why the trash, workspaces and tabs are preferences

The trash (`core/trash.ts`), the workspaces and which note is filed where (`core/workspaces.ts`), and the open tabs and their groups are all fields of `core/preferences.ts`, not columns in the index. A column in Rust is a native change, and it ships only with a new APK. A preference ships over the air and syncs with the person's settings. So a note thrown away on the phone is in the trash on the Mac too, and its file is untouched until the trash is emptied.

## Seeing the folder

The sidebar's Browse files button (`notes/NoteTree.tsx`, `core/libraryFiles.ts`) is offered only where the binary has it: native generation 18 or later, or an Android activity that offers `browseFiles`. On a Mac it calls `library_reveal`, which opens `Library/` in Finder. On Android it asks the activity, and the Files app shows the library as a place called Ghost.md (`files/LibraryDocuments.kt`, a `DocumentsProvider`). There, folders come first and dot files are hidden. It is read-only: a note can be opened, copied and shared, but never changed behind the index's back.

## Testing it without Tauri

`tools/host-tests` compiles `note.rs`, `fsx.rs`, `store.rs`, `library/` and the command parser from their real files with `#[path]`, against only the dependencies they use. Their tests then run on a machine that cannot build the Tauri stack. If a `tauri::` type creeps into any of them, that crate stops compiling.

## Where LIBRARY.md is wrong

| docs/LIBRARY.md says | The code |
|---|---|
| Pictures live in `attachments/`, linked relatively | They live in the app's `images/`, linked as `image/<name>` |
| Recordings are `.glyph/recordings/<id>.wav` | They are `recordings/<id>.wav` in the app's data directory, outside the library |
| Front matter includes `tags`, `notion-board` and `project` | The library writes `id`, `created`, `source`, `pinned` and `archived`. The page's own keys (`title:`, `book:`, `authors:`) sit in a second block at the top of the words |
| A note's file is named after its title | A note whose words open with a block of their own, such as a book or a canvas, is named `---.md` |
| The index has a folder column | It has none. It keeps the whole body, a revision, and the command undo table |
| Rebuild in Settings › Library | There is no such setting and no rebuild command. Delete `.glyph/index.sqlite` and the next launch rebuilds it |
| Folders are the person's own, at any depth | The app makes `Inbox/` and `workspaces/<name>/`. Other folders are read, never made |
| Deleting `.glyph` loses only recordings and AI versions | The recordings' audio is not in it. What goes is every sidecar (a recording's length and phrases, the formatted versions), each note's revision and the command undo record |

LIBRARY.md half-knows the first two: a later paragraph says phase 1 keeps recordings and pictures in the app's storage, while its folder picture and its example note still show `attachments/` and `.glyph/recordings/`. Its list of dropped characters also leaves out `#`, `^`, `[` and `]`, and it gives no stem limit. Phase 2 (a folder the person picks) and phase 4 (Notion and project keys in front matter) are not built. Phase 3 is built only in part: `Inbox/` and the workspace folders exist, and `attachments/` does not.

## Read next

- [[Sync and the end-to-end keys]]
- [[Reading a command, writing it safely]]
- [[Where the docs and the code disagree]]
