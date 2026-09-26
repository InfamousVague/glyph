# Formats that stay Markdown

_Boards, books, canvases, linked tasks and voice memos, and the standard they all keep: nothing a note needs is stored beside it, and all of it is plain text another app can read._

## The rule

A new kind of note in Ghost.md is plain text in the note's own file. Mostly that is Markdown a person could type, which reads as words in any other app; a canvas is the one exception in kind, JSON Canvas, the open format Obsidian writes. No sidecar holds a board's columns or a book's order. Some things are kept beside the notes: the library's index, which is a cache; a note's sidecar in `.glyph/notes/<id>.json`, with a recording's length and phrases and the formatted version; and a little device-side state, such as a board's remembered height and which recording a memo's id names. Losing any of it loses nothing a note says.

Every format below answers three questions. What is it as plain text? Which module is the only one that spells it? What does the editor draw from it?

## The item line

A list item's grammar is spelled once, in `src/app/core/itemSyntax.ts`:

```markdown
- [ ] Write the pricing page [notion](https://…) [3/8] ^pricing-page
```

| Part | As written | Its atom |
|---|---|---|
| The marker | `-`, `*`, `+`, `1.` or `1)` | `MARKER` |
| A to-do's box | `[ ]`, `[x]` or `[X]`, standing as a word | `BOX` |
| A choice's box | `( )` or `(x)`, after a bullet only | `CHOICE` |
| The bookmark | `§§` | `BOOKMARK` |
| The mark | `[notion](…)`: a link to an `http` or `https` address whose words are one lowercase name | `MARK` |
| A counter | `[3/8]` | `COUNTER` |
| The anchor | `^pricing-page`, last | `ANCHOR` |

The order is words, then mark, then anchor, with counters and the bookmark allowed among them. The anchor needs whitespace before its caret and nothing after it but a mark or a counter, which is what leaves `E = mc^2^` a superscript. The atoms are regex sources with no groups of their own, so they compose into larger patterns without renumbering them.

The module exists because the grammar was once written out about twenty-five times, and the copies disagreed: a `* [x]` item went to Notion titled "[x] Done thing". Now a line is a to-do everywhere or nowhere. `listLead(line)` pulls a line apart; `wordsEnd(line)` is where the caret goes when a card or a link lands on an item, before the tail, so what is typed next goes on the words. `isDoneName` says which board column is Done: a name that starts or ends with the word.

## The anchor is the generic link

An anchor names an item so anything can point at it. A board's fence points at it. So does `[[#^ask-sam]]` anywhere in the same note, and `[[Launch week#^photos]]` from another. A canvas `file` node with a `subpath` of `#^photos` opens its note on that item. One name, many pointers, and it reads as text everywhere.

When Ghost.md makes an anchor (`anchorFor`, `core/boards/items.ts`) it takes the first three words that carry meaning, lower case, filler left out: "Add ability to auto-tag notes" is `add-ability-auto`. An anchor already in a note is never renamed, since something may point at it.

## Boards

A board is anchored items and a fence whose info string is `board`, optionally with settings after the word (`board height=18`). Each line of the fence is a column naming anchors:

```text
This week: pricing-page, beta-list
Waiting on Sam: photos
Done: launch-date
```

`src/app/core/boards.ts` is the door, and only re-exports. The work is in `src/app/core/boards/`, one job a module, each pure and tested:

| Module | Its job |
|---|---|
| `items.ts` | Items read as cards, `[[#^id]]` pointers, `anchorFor` |
| `fence.ts` | The fence read and written, `height=`, where each board is, which lines sit inside any fence |
| `columns.ts` | Columns as data: a card moved, dropped or taken off; ticked cards drawn in Done |
| `settle.ts` | A tick carried to every fence, so the Markdown agrees with the boxes |
| `make.ts` | Boards and cards made from a note's own lists: `boardFrom`, `boardFromList`, `addToBoard`, `newCard` |
| `lanes.ts` | Lanes found and filled by voice: `lanesOf`, `matchLane`, `addToLane`, `moveToLane` |

Every transform answers new text or new columns and never changes what it was given. `readBoard` reads an id loosely (`Fix Login` is `fix-login`, but only when the note has that anchor) and `writeBoard` writes it the one way. An id in two lanes belongs to the first.

A tick is where the halves meet. `editor/taskToggle.ts` and `editor/doneSync.ts` put the box's change and `settleFences(state, ticks)` from `editor/boards.ts` into one transaction, so the fence moves in the same edit and the same Undo. An anchor a tick adds is appended to the end of its line, never written by replacing the line, because the tick changes a character at its start and two overlapping changes cannot both apply. `editor/boards/` holds the drawing: the widget, card edits, the drag, the + field, the height remembered across launches.

## Books

A book is a note whose front matter says `book: true` and whose body is an index of wiki links. `src/app/book/book.ts`:

- `isBookBody` reads `book` through `frontMatterValue`, taking `true` or `yes`.
- `chaptersOf` takes every list item that opens with a link, one level deep by indentation. A `#heading` or `|alias` in the link is not the title. Beside a numbered index, a top-level bullet list is about the book, not in it.
- `numbered` gives "1", "2", "2.1". `withChapter`, `withoutChapter`, `withChapterMoved` and `withChapterAt` edit the index and never touch a chapter note; a chapter added to a numbered index takes the next number.
- `bookWords` is the book's own words before and after its chapters. `bookOf` finds the first book whose index names a note by title, and `bookIndex` does every page at once for a list.

`src/app/book/chapterNumber.ts` reads a number from a title, at the end ("· Ch. 8", "(Chapter 8)", "· Chapter VIII") or at the front ("08 · …"), so chapters with no book can still be put in order. A bare "Top 10" is not a chapter number.

## Canvases

A canvas note is front matter naming it, then JSON Canvas 1.0 as the spec writes it. `src/app/canvas/jsonCanvas.ts`:

- `canvasOf(body)` skips the front matter and parses what is left when it starts with `{`.
- `parseCanvas` reads leniently: a node that is not a node is left out, with any edge to it, so one bad card does not lose the other forty.
- `serializeCanvas` writes exactly: only the spec's fields, two spaces in, a newline at the end, as Obsidian saves one.
- `canvasNoteBody` makes a new note; `withCanvas` replaces the JSON and keeps the front matter character for character.

Colours are the spec's, `"1"` to `"6"` or a hex. `canvas/cardLooks.ts` paints the six presets as the page's own hues, rose, ember, amber, moss, sea and violet, the ones a workspace wears, and keeps a hex as it is.

## Front matter, twice

Two blocks can open a note's file, and two codebases read them.

**The file's own block** is Rust's. `src-tauri/src/library/frontmatter.rs` splits it off before the page sees the body and joins it back on save, with no YAML library, so unknown keys, comments and a person's quoting come back byte for byte. The library manages five keys (`src-tauri/src/library/mod.rs`): `id`, `created`, `source` (left out for a note typed in the editor), `pinned`, and `archived`, written as a date.

**The page's block** is inside the body, so on disk it sits under the library's. `src/app/core/frontMatter.ts` is the one place the page decides where it ends:

- `FENCE` is `---` or `+++` on a line of its own.
- `frontMatterEnd(lines)` wants a fence on the first line, lines that are each a `key:` or blank, and a closing fence within 40 lines. A YAML list under a key makes the block prose to the page; Rust's reader, for the file's block, reads lists.
- `frontMatterValue(body, key)` reads one key with its quotes off.
- `quotedTitle` quotes a title so a colon stays inside it; `withFrontMatterTitle` and `withFrontMatterValue` write one key and leave every other as it was.

The page writes three keys. `title` names a canvas or a book, neither of which has a first line to rename; a rename from a note's tab writes it, and only those two offer one. `book` makes a book. `authors` (`core/authors.ts`) is comma-separated names: the phone's AI signs a note it co-wrote as `Ghost` (`ai/useLanding.ts`), and the connector adds the AI that wrote through it (`mcp/server.ts`). `core/noteTitle.ts` names a note from `title:` if there is one, else the first line of words, pictures skipped and heading marks and the bookmark taken off. It imports only the front matter rule and `itemSyntax.ts`, so the MCP server bundles the same code the list runs.

The page once answered where front matter ends three ways, and `book: true` was read out of a block the list showed as words. ==`frontMatterEnd` is why a note can no longer be front matter to one reader and prose to another.==

## Memos, pictures and marks

- **Voice memos**, `src/app/core/clips.ts`: `![voice 0:08](tape:12000-19500@k3f9x2)`, a stretch of the note's own recording in milliseconds, with the tape's id after the `@`. The words are the stretch's length, rounded to the second, as `clipMarkdown` writes them. Anywhere else it is an image reference whose words say what it is. A memo plays only while the note's tape still carries it.
- **Pictures**, `src/app/core/imageRefs.ts`: `![caption](image/<name>)`, a relative path, so a folder of notes with an `image/` folder beside it makes sense anywhere. It imports nothing, so the MCP server names a body's pictures with the same `imageNames`, built on `IMAGE_REF`.
- **Links to Notion and GitHub**, `src/app/core/itemLinks.ts`: the item keeps its words and ends with `[notion](…)` or `[github](…)`. The names are the plugins' ids (`registerMarkName`), so `[docs](…)` at the end of an item is a link, not a mark. The old form, where the words were the link, still counts as sent.

## What the docs still say

- `docs/BOARDS.md` calls `core/boards.ts` "the only place that knows the fence's syntax". It is a door of re-exports now: the fence is spelled in `core/boards/fence.ts`, and `make.ts` writes its opening line. It gives `core/boards.ts` "the anchor half" of a link into another note; that is `core/boards/items.ts`. It says WebKit paints a lane's smoke black; `art/wispFoot.ts` draws it there, inside the filter budget.
- `docs/BOOKS.md` calls `frontMatterValue` "the one front-matter read the app makes". The one rule is `frontMatterEnd`, `frontMatterValue` is one reader of it, `noteTitle.ts` reads `title:` itself, and Rust reads the file's block. Its table lists `prefaceOf`, which does not exist: the function is `bookWords`.
- `docs/CANVAS.md` and the header of `jsonCanvas.ts` say Ghost.md has no files. The library is a folder of Markdown files now (`src-tauri/src/library/`).
- The example memo in `core/clips.ts` and `editor/clips.ts`, `![voice 0:12](tape:12000-19500)`, is seven and a half seconds long. `clipMarkdown` would write `0:08` for it.

## Read next

- [[The plugin seam]]
- [[The library on disk]]
- [[Boards made of list items]]
