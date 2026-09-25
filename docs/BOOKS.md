# Books

A book is a collection of notes in an order, with an index. Matt (2026-09-22): "add a Book feature it should be a
collection of organized notes with an index." Like a board (docs/BOARDS.md) and a canvas (docs/CANVAS.md), a book is
a note, and it reads as one anywhere Markdown is read.

## The shape

The book note's body is its index: a list of `[[links]]` to its chapters, in order.

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

- **One line of front matter makes it a book:** `book: true`. Without it, a note with a list of links is a note
  with a list of links. The `title:` names it, as a canvas note is named, since the index view has no heading to
  rename it in.
- **A chapter is any note, found by its title.** A link to a title with no note yet is a chapter still to be
  written; the index says so, and opening it makes the note, starting with the title as its heading (App.tsx
  `openTitle`, the same as any `[[link]]`).
- **Order is the list's order; a part is indentation.** A chapter indented under the one before it is numbered
  under it (2.1, 2.2). One level; deeper indentation reads as the same level.
- **The book's own words stay.** Lines that are not chapters - a paragraph before the list, notes to self - are
  kept where they are and shown over the index.
- **A link's heading or alias is not the title:** `[[Trees#Oaks|the oaks]]` is the chapter Trees.
- **A chapter is an item that opens with its link.** `- [[Trees]] — the big ones` is a chapter. `- The oaks are in
  [[Trees]].` is the book's words about a chapter, and stays in the preface.
- **A numbered index is its numbered list.** In an index written `1. [[…]]`, `2. [[…]]`, a bullet list beside it at
  the top level, such as the book's canvases or further reading, is about the book rather than in it, and shows in
  the preface. Bullets indented under a numbered chapter are still its chapters. A chapter added to a numbered index
  takes the next number, or it would be a bullet the index skips.

## In the app

- **Making one.** The + offers a Book beside a Note and a Canvas (notes/NewSheet.tsx), and opens the New book
  sheet (book/NewBookSheet.tsx): its name, and which notes are its pages - the library's titles under a search, a tap
  puts one in and a second takes it out, the pages so far listed above in the order chosen, each movable a place or
  left out. *Make the book* writes one note with that index and opens it; closing the sheet makes nothing. Rename it
  later from its tab's menu or its settings, as a canvas is.
- **The Library** on the home page (home/HomeScreen.tsx, `bookNotes` in home/dashboard.ts): a card per book - its
  name, how many pages, the first few of them - between Pinned and Recent; a tap opens the index. A book is not
  also a Recent card.
- **The index view** (book/BookView.tsx) stands where the note's words would be, the Markdown a toggle away in the
  header, as a canvas's JSON is. Each chapter is a row that opens the note; a chapter not written yet is drawn
  waiting. Every row moves up or down a place, or comes out of the book - the note it names is never touched.
  *Add a chapter* names a new one and opens it at once; *Add a note you have* ticks any number from the library's
  titles, less the book's own and those already in it, and adds them in the order ticked.
- **A chapter wears the book** (BookBar): under its header, the book's title with its place (2 of 5) and the
  chapters either side; a tap on the book opens the index. Found by title (book/book.ts `bookOf`): the first book
  in the library whose index names the note. A note can be in more than one book; the bar shows the first.
- **And under its last line** (BookFoot): Previous and Next as two wide buttons naming the chapters either side, so
  the end of a page goes on to the next without scrolling back up (Matt: "add the book navigation for next and prev
  buttons at the bottom of the page"). Only Next on the first chapter, only Previous on the last. On the reader page
  too, where it steps only between the chapters the share holds.
- **One tab.** A page opened from inside a book - the index, the chapter bar, the right-hand aside, the read-through -
  takes the current tab's place rather than a tab of its own; a page that already has a tab is used and the book's
  closes (notes/openTabs.ts `swapOpen`). A `[[link]]` in the words still opens a tab, as any link does.
- **Reading straight through** (*Read straight through* in the index): the chapters one after another as pages, each
  drawn as its note reads, with a rail down the side to jump between them; a canvas chapter says to open it, and one
  not written yet says so. *Index* goes back.
- **It opens where it was left** (book/bookSpot.ts; Matt: "When opening a book re open to the same spot it was last
  opened"). A book remembers whether it was last at its index, in a chapter, or reading straight through. Opening it
  from outside - the home page's Library, the sidebar, the notes list, search, a `[[link]]` - goes back there. A
  chapter opens in the book's place, at the line its note was left at (editor/notePlace.ts), and the read-through
  opens at the chapter and line it was scrolled to. From inside the book it does not: the chapter bar's book button,
  its tab, Back and Forward show the index as before, since otherwise there would be no way back to it from a chapter.
  A chapter taken out of the book, or whose note is gone, is not a spot to go back to, and the book opens at its index.
- **Reordering by drag.** The rows of the index and the pages in the New book sheet lift by their grip
  (book/rowDrag.ts): at once with a mouse, after a short hold on touch, so a scroll is still a scroll. The arrows stay
  for a place at a time.
- **A book mark** on a note that is a chapter, in the list and on the home cards, so a page reads as a page.
- **By voice:** the section below.
- **Writing is writing the note.** Every change from the view is a change to the book note's body, saved the way
  typing is, so the index behind the view and the view are one thing, and a book edited as Markdown in another app
  draws the same on the phone.

## By voice

Two commands, read by the rules in capture/command.ts and asked about before they act, as every command is:

- **"Hey Ghost, make a book called Field guide"** makes the book note, empty with its index ready, beside the
  recording, which carries on where it was. Pages can follow the name: "…with Trees, Birds and the work note", each a
  note found by its spoken title or, when no note answers to it, a chapter still to write. Said without a name, the
  recorder keeps listening for one. Only make, create, start, begin and new open a book: "add a book to my reading
  list" is a book for a list.
- **"Hey Ghost, add a chapter to the field guide"** and then its name, or the name in the same breath ("add a chapter
  called Rivers to the field guide", "put Rivers in the field guide"). A book gets chapters, never words: whatever the
  rules, or the phone's command model, would have placed in a book is read again as a chapter (`forBook`), so the
  model's prompt need not know what a book is. "Add this to the field guide" and "move this to the field guide" make
  the note being recorded a chapter. A chapter the book has, the book itself, or a note with no name yet is said and
  not offered.
- The card is the one a board's lane uses (*New chapter in Field guide*, *Add*); a book's card lists its pages. In a
  pause the recorder suggests "add a chapter to …" naming a book you have, or how to make one.

## Chapter numbers

A chapter can carry its number in its title. Without a book, the numbers put the chapters in order.

The standard is at the end of the title: "Ch." or "Chapter", then an Arabic or Roman number, after a middle dot, a
dash, a comma or a colon, or in brackets.

    The risks, and a glossary · Ch. 8
    The risks, and a glossary (Chapter 8)
    The risks, and a glossary · Chapter VIII

A number in front is read too, since many chapters are already titled that way:

    08 · The risks, and a glossary
    Chapter 8: The risks, and a glossary

A bare number at the end, as in "Top 10", is not a chapter number, and Roman numbers stop at C's.

**Without a book.** When the open note has a chapter number and no book's index names it, the right-hand aside lays
out its run: the numbered chapters that belong with it, in number order, the open one marked.

- **What belongs together:** chapters whose page first points at the same note, such as a "« [[The book]]" line.
  A link to another numbered chapter doesn't count. With no such link, chapters in the same folder belong together.
- **The name over the run:** that note's title, opening it if it exists, or the folder's name.
- **A chapter alone** is no run, and shows nothing.

**Nothing to show, no aside.** On a note in no book and with no run, and on the home page, the aside and its toggle
aren't drawn. It no longer lists the workspace's other notes.

## Where the code is

| file | what |
| --- | --- |
| `src/app/book/book.ts` | the shape: `isBookBody`, `bookNoteBody`, `chaptersOf`, `numbered`, `prefaceOf`, `withChapter`, `withoutChapter`, `withChapterMoved`, `bookOf` |
| `src/app/book/BookView.tsx` | the index view, reading straight through, and `BookBar` for a chapter |
| `src/app/book/NewBookSheet.tsx` | the + sheet: a name and the pages, picked and ordered |
| `src/app/book/rowDrag.ts` | `useRowDrag`: rows lifted by a grip, in the index and the sheet |
| `src/app/aside/aside.ts` | the right-hand aside's content: a book's index on its pages, a numbered chapter's run with no book, else nothing |
| `src/app/book/chapterNumber.ts` | a chapter's number read from its title |
| `src/app/capture/command.ts` | "make a book called …" and a chapter for a book named (`forBook`, `placedOn`) |
| `src/app/capture/take.ts` | the chapter offer (the book's index with one more line) and the book offer |
| `src/app/capture/CaptureScreen.tsx` | `makeBook`: the book note written beside the take |
| `src/app/core/frontMatter.ts` | `frontMatterValue`, the one front-matter read the app makes |
| `src/app/editor/NoteScreen.tsx` | a book note drawn as its index, with the Markdown a toggle away; a chapter's bar |
| `src/app/notes/NewSheet.tsx`, `src/app/App.tsx` | the + makes one; a chapter's place is found for the screen |

## Canvases as pages

Matt: "Add the ability for canvases to be in books as well." A canvas is a note found by its title like any other, so
it was already a page a book could hold: offered by the New book sheet and the index's picker, opened as a canvas, and
wearing the chapter's bar ("Cabin trip · 2 of 3", the pages either side). What the index lacked was saying so. A
chapter that is a canvas, and a canvas offered in the index's picker, now wear the canvas's own mark after the title -
the one the + sheet gives a canvas - and a reader hears "Route map, a canvas" (book/BookView.tsx, `bodyOf` from the
note screen). A chapter with no note yet says nothing of what it will be.

A new chapter can start as a canvas: the index's "Add a chapter" form has "Add as a canvas" beside "Add and open",
which puts the chapter in the index and makes an empty canvas by that name (App.tsx `openCanvasWithin`). The New book
sheet marks canvases among the notes it offers, and among the pages picked.
