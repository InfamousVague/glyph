# Notebooks

Called books until 2026-09-28 (docs/DESIGN.md §142). The key, the ids and the code still say book.

A notebook is a collection of notes in an order, with an index. Matt (2026-09-22): "add a Book feature it should be
a collection of organized notes with an index." Like a board (docs/BOARDS.md) and a canvas (docs/CANVAS.md), a
notebook is a note, and it reads as one anywhere Markdown is read.

## The shape

The notebook note's body is its index: a list of `[[links]]` to its pages, in order.

```markdown
---
title: "Field guide"
book: true
---
# Field guide

What to know before the walk.

- [[Introduction]]
- [[Trees]]
  - [[Oaks]]
  - [[Pines]]
- [[Birds]]
```

- **One line of front matter makes it a notebook:** `book: true`. Without it, a note with a list of links is a note
  with a list of links. The `title:` names it, as a canvas note is named, since the index view has no heading to
  rename it in.
- **A page is any note, found by its title.** A link to a title with no note yet is a page still to be written; the
  index says so, and opening it makes the note, starting with the title as its heading (App.tsx `openTitle`, the
  same as any `[[link]]`).
- **Order is the list's order; a part is indentation.** A page indented under the one before it is numbered under it
  (2.1, 2.2). One level; deeper indentation reads as the same level.
- **The notebook's own words stay.** Lines that are not pages - a paragraph before the list, notes to self - are
  kept where they are and shown over the index.
- **A link's heading or alias is not the title:** `[[Trees#Oaks|the oaks]]` is the page Trees.
- **A page is an item that opens with its link.** `- [[Trees]] — the big ones` is a page. `- The oaks are in
  [[Trees]].` is the notebook's words about a page, and stays in the preface.
- **A numbered index is its numbered list.** In an index written `1. [[…]]`, `2. [[…]]`, a bullet list beside it at
  the top level, such as the notebook's canvases or further reading, is about the notebook rather than in it, and
  shows in the preface. Bullets indented under a numbered page are still its pages. A page added to a numbered index
  takes the next number, or it would be a bullet the index skips.

The code calls a page a chapter (`chaptersOf`, `Chapter`), as it did when a notebook was a book.

## In the app

- **Making one.** The + offers a Notebook beside a Note and a Canvas (`src/app/notes/NewSheet.tsx`), and opens the
  New notebook sheet (`src/app/book/NewBookSheet.tsx`): its name, and which notes are its pages - the library's
  titles under a search, a tap puts one in and a second takes it out, the pages so far listed above in the order
  chosen, each movable a place or left out. *Make the notebook* writes one note with that index and opens it; closing
  the sheet makes nothing. The palette's *New notebook* opens the same sheet. Rename it later from its tab's menu or
  its settings, as a canvas is.
- **Notebooks** on the home page (`src/app/home/HomeScreen.tsx`, `bookNotes` in `src/app/home/dashboard.ts`), the
  group called Library until §142: a card per notebook - its name, how many pages, the first few of them - between
  Tapes and Recent; a tap opens the index. A notebook is not also a Recent card.
- **The index view** (`src/app/book/BookView.tsx`) stands where the note's words would be, the Markdown a toggle away
  in the header, as a canvas's JSON is. Each page is a row that opens the note; a page not written yet is drawn
  waiting. Every row moves up or down a place, or comes out of the notebook - the note it names is never touched.
  *Add a page* names a new one and opens it at once; *Add a note you have* ticks any number from the library's
  titles, less the notebook's own and those already in it, and adds them in the order ticked.
- **A page wears the notebook** (BookBar): under its header, the notebook's title with the page's place (2 of 5) and
  the pages either side; a tap on the notebook opens the index. Found by title (`src/app/book/book.ts` `bookOf`): the
  first notebook in the library whose index names the note. A note can be in more than one notebook; the bar shows
  the first.
- **And under its last line** (BookFoot): Previous and Next as two wide buttons naming the pages either side, so the
  end of a page goes on to the next without scrolling back up (Matt: "add the book navigation for next and prev
  buttons at the bottom of the page"). Only Next on the first page, only Previous on the last. On the reader page
  too, where it steps only between the pages the share holds.
- **One tab.** A page opened from inside a notebook - the index, the page's bar, the right-hand aside, the
  read-through - takes the current tab's place rather than a tab of its own; a page that already has a tab is used
  and the notebook's closes (`src/app/notes/openTabs.ts` `swapOpen`). A `[[link]]` in the words still opens a tab, as
  any link does.
- **Reading straight through** (*Read straight through* in the index): the pages one after another, each drawn as its
  note reads, with a rail down the side to jump between them; a canvas page says to open it, and one not written yet
  says so. *Index* goes back.
- **It opens where it was left** (`src/app/book/bookSpot.ts`; Matt: "When opening a book re open to the same spot it
  was last opened"). A notebook remembers whether it was last at its index, on a page, or reading straight through.
  Opening it from outside - the home page's Notebooks, the sidebar, the notes list, search, a `[[link]]` - goes back
  there. A page opens in the notebook's place, at the line its note was left at (`src/app/editor/notePlace.ts`), and
  the read-through opens at the page and line it was scrolled to. From inside the notebook it does not: the page
  bar's notebook button, its tab, Back and Forward show the index as before, since otherwise there would be no way
  back to it from a page. A page taken out of the notebook, or whose note is gone, is not a spot to go back to, and
  the notebook opens at its index.
- **Reordering by drag.** The rows of the index and the pages in the New notebook sheet lift by their grip
  (`src/app/book/rowDrag.ts`): at once with a mouse, after a short hold on touch, so a scroll is still a scroll. The
  arrows stay for a place at a time.
- **A mark and the notebook's name** on a note that is a page, in the list and on the home cards, so a page reads as
  a page.
- **Not by voice:** the section below.
- **Writing is writing the note.** Every change from the view is a change to the notebook note's body, saved the way
  typing is, so the index behind the view and the view are one thing, and a notebook edited as Markdown in another
  app draws the same on the phone.
- **The guide.** Settings › About › *Ghost.md: The Guide* adds the app's own manual as a notebook: 44 chapter notes
  and their index, shipped as Markdown in `src/app/guidebook/` and read only when the row is pressed (DESIGN §125).
  Pressed again, it opens the one already there. The Guide calls its pages chapters, as a manual does.

## Not by voice

A notebook is not made or filled by voice (DESIGN §127): make one with the **+** and add its pages from its index.

A notebook is never written into by voice either. Told to add words to one after "Hey Ghost", the live reader
(`src/app/capture/liveRoute.ts`) keeps them where the recording is and says why; without the keyword they are the
recording's words, since a notebook is never a note the bare gate names ("“Field guide” is a notebook, so the words
stay here"), and no card offers a notebook. "Make a book called …" and "add a chapter to …" are read at Done by the
rules in `src/app/capture/command.ts`, which take words said for a notebook as a page (`forBook`), only so that the
reader can turn them down: after "Hey Ghost", said into an open note, they open that note with an AI ask carrying
the words; said as a fresh recording, or without the keyword, they are saved as a note's words
(docs/instruction-voice-commands.md). "Notebook" is not one of the words those rules know: "new notebook for school"
is a note's words, as it would be said.

## Journals

Matt (2026-09-28): "I'd like a journal function where we can just do entries into a book marked as a journal where we
pick the template for pages (time and date prefixed, with geo location, etc etc)". A journal is a notebook whose pages
are dated entries, each started from a template the journal keeps (docs/DESIGN.md §142).

```markdown
---
title: "Diary"
book: true
journal: true
template: "# {{date}}\n\n**{{time}}** "
entry-place: true
---
# Diary

- [[2026-09-27 21.40]]
- [[2026-09-28 14.05]]
```

- **Three keys beside `book: true`.** `journal: true` marks it. `template:` is the Markdown each entry starts as,
  written as one JSON string, which YAML reads as the text it is, so the front matter stays flat and any Markdown app
  reads it back. `entry-place: true` says entries keep where they were written (not `place:`, which is a geotag's).
  An older app draws a journal as the notebook it is and keeps every key.
- **An entry is a note named by the minute,** `2026-09-28 14.05`, in ASCII digits whatever the language, so its key
  keeps its month (`titleKey` keeps only a-z and 0-9) and its file is `2026-09-28 14.05.md`, which the index's link
  resolves to in any app. A second in the same minute is ` (2)`. Its `date:` is the wall clock with no offset, so a
  shared entry does not say which time zone it was written in, and the journal groups it by the day its clock said.
  `title:` is its name, so its heading and words can change and it keeps its line.
- **The templates:** the date and the time (the default), just the time, a morning page, a day's to-dos, and your
  own. Placeholders are Obsidian's: `{{date}}` (the home page's long day, "Monday 28 September"), `{{time}}` (a
  24-hour clock, as meeting titles have), `{{weekday}}`, `{{title}}`, `{{journal}}`, and Moment's tokens after a colon,
  words in square brackets. Looked up by their own names only, so `{{constructor}}` is left as typed. The day and the
  time come from `src/app/core/stamp.ts`, which the + writes its date with.
- **Making one:** the New notebook sheet's Journal choice, with the template, a preview of an entry made now, and
  the place switch, whose default is this device's Tag new notes. Or a notebook kept as a journal from its More
  sheet, every page where it was; and made a notebook again from there. Not the Guide.
- **New entry** (`App.tsx` `newEntry`): the record first (`src/app/core/untouched.ts`), then the line last in the
  index, at its top level, through the journal's own screen when it is open, then the note, opened with the caret at
  the end. Named past every note there is and every line the journal has, so an entry made while another is being
  taken back does not share its name. A second press while one is made does nothing. Where it was written is asked at
  the tap, when the journal keeps places, and lands with the entry's first own words.
- **Taken back when untouched.** An entry this device made and nobody wrote in is deleted, with its line and its
  waiting tag, when it is left: home, its tab closed, or the journal opened in its tab, by its bar or by Back. Not when
  another tab is shown or a capture is aimed at it, and never on the screen's unmount. Its first own keystroke makes
  it the person's there and then, before the save, so words typed and left at once are kept. Its line stays when
  another note is named by it. A launch does the same for an entry the phone let go of. No place lands on one first
  (`hasOwnWords` in `src/app/core/location.ts`).
- **Speak an entry** is the journal's mic: an entry made and recorded into, the words going on from the template's
  last line (`openEnd`, and `lead` in `src/app/capture/place.ts`), so it still starts with its time and a day's
  to-dos said aloud are to-dos. The place is asked once the recorder has gone. Said nothing, it lands on the journal
  and the entry is taken back.
- **The view** (`src/app/book/JournalView.tsx`): New entry, the journal's own words, then the entries by month,
  newest first by when each was written, whatever order the index is in. Three months open, older ones a row each. A
  page planned before a notebook was kept as a journal is under Not written yet; an entry's line with no note is not
  drawn. A row's words skip only what the template wrote for that entry, filled for its own minute. The bar and the
  foot walk the written entries in the order written, a side named by its time, or its day when written on another.
  The card counts the written entries and lists the newest by day and time, with no numbers. Opening a journal from
  outside always opens the journal (`whereLeft`).
- **Elsewhere:** two taps from home, the +'s "Entry in" row for the journal written in last, and "New entry in" in
  the palette for three, never a journal in the archive. Recent, the palette's first forty and the pickers of a
  notebook's pages leave entries out. A journal is shared an entry at a
  time (docs/SHARING.md). Two devices adding lines between syncs merge (docs/SYNC.md). Claude writes an entry with
  `add_journal_entry` (docs/MCP.md).

## Chapter numbers

A chapter can carry its number in its title. Without a notebook, the numbers put the chapters in order.

The standard is at the end of the title: "Ch.", "Chapter" or "§", then an Arabic or Roman number, after a middle dot,
a bullet, a bar, a dash, a comma or a colon, in brackets, or after a space.

    The risks, and a glossary · Ch. 8
    The risks, and a glossary (Chapter 8)
    The risks, and a glossary · Chapter VIII

A number in front is read too, since many chapters are already titled that way, before a middle dot, a bullet, a
bar or a dash:

    08 · The risks, and a glossary
    Chapter 8: The risks, and a glossary

A bare number at the end, as in "Top 10", is not a chapter number, and Roman numbers stop at C's.

**Without a notebook.** When the open note has a chapter number and no notebook's index names it, the right-hand
aside lays out its run: the numbered chapters that belong with it, in number order, the open one marked.

- **What belongs together:** chapters whose page first points at the same note, such as a "« [[The book]]" line.
  A link to another numbered chapter doesn't count. With no such link, chapters in the same folder belong together.
- **The name over the run:** that note's title, opening it if it exists, or the folder's name.
- **A chapter alone** is no run, and shows nothing.

**Nothing to show, no aside.** On a note in no notebook and with no run, and on the home page, the aside and its
toggle aren't drawn. It no longer lists the workspace's other notes.

## Where the code is

| file | what |
| --- | --- |
| `src/app/book/book.ts` | the shape: `isBookBody`, `bookNoteBody`, `chaptersOf`, `numbered`, `bookWords` (the notebook's own words either side of the index), `withChapter`, `withChapterAt`, `withoutChapter`, `withChapterMoved`, `toggledTitle`; and a note's place: `bookOf`, `bookIndex`, `placeOf`, `bodyWithoutTitle` (a page's words as the read-through draws them) |
| `src/app/book/BookView.tsx` | the index view and reading straight through |
| `src/app/book/BookNav.tsx` | `BookBar` under a page's header and `BookFoot` under its last line |
| `src/app/book/CanvasMark.tsx` | the canvas's mark after a page that is one |
| `src/app/book/bookSpot.ts` | where a notebook was left: its index, a page, or the read-through |
| `src/app/book/rows.module.css` | the rows the index and the New notebook sheet share |
| `src/app/book/NewBookSheet.tsx` | the + sheet: a name and the pages, picked and ordered |
| `src/app/book/rowDrag.ts` | `useRowDrag`: rows lifted by a grip, in the index and the sheet |
| `src/app/aside/aside.ts` | the right-hand aside's content: a notebook's index on its pages, a numbered chapter's run with no notebook, else nothing |
| `src/app/book/chapterNumber.ts` | a chapter's number read from its title |
| `src/app/book/journal.ts` | a journal's keys, its presets, an entry's name, `date:` and body, `stampOf`, and which notes are entries (`entryPages`); pure, so the MCP server bundles it |
| `src/app/core/template.ts` | a template filled (`fillTemplate`, `formatStamp`), and where a spoken entry's words go (`openEnd`) |
| `src/app/book/journalMonths.ts` | the entries by month, a row's words, the bar's time order, a journal's card and the aside's month |
| `src/app/core/untouched.ts` | the record of an entry nobody has written in yet, on this device, and of a new note given words from its blank page (DESIGN §144) |
| `src/app/notes/ownTemplates.ts` | the Templates notebook your own templates are kept in: found by `templates: true`, its pages as the blank page's cards, kept out of Recent and To do |
| `src/app/book/JournalView.tsx`, `src/app/book/TemplatePicker.tsx` | a journal drawn, and the template's choice with its preview and the place switch |
| `src/app/core/stamp.ts` | a moment as words: `stamp`, `clockTime`, `longDay` |
| `src/app/capture/command.ts` | "make a book called …" and a page for a notebook named, read so the reader at Done turns them down (`forBook`) |
| `src/app/core/frontMatter.ts` | where a note's front matter ends, and `book:` and `title:` read and written (`frontMatterValue`, `withFrontMatterTitle`) |
| `src/app/editor/NoteScreen.tsx` | a notebook note drawn as its index, with the Markdown a toggle away; a page's bar |
| `src/app/notes/NewSheet.tsx`, `src/app/App.tsx` | the + makes one; a page's place is found for the screen |

## Canvases as pages

Matt: "Add the ability for canvases to be in books as well." A canvas is a note found by its title like any other, so
it was already a page a notebook could hold: offered by the New notebook sheet and the index's picker, opened as a
canvas, and wearing the page's bar ("Cabin trip · 2 of 3", the pages either side). What the index lacked was saying
so. A page that is a canvas, and a canvas offered in the index's picker, now wear the canvas's own mark after the
title - the one the + sheet gives a canvas - and a reader hears "Route map, a canvas" (`src/app/book/CanvasMark.tsx`,
with `bodyOf` from the note screen). A page with no note yet says nothing of what it will be.

A new page can start as a canvas: the index's "Add a page" form has "Add as a canvas" beside "Add and open", which
puts the page in the index and makes an empty canvas by that name (App.tsx `openCanvasWithin`). The New notebook
sheet marks canvases among the notes it offers, and among the pages picked.
