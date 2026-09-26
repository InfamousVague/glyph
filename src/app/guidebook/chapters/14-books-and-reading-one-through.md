# Books, and reading one through

_A book is a note whose body is its index: links to its chapters, in order. This book is one._

## A book is a note

One line of front matter makes a note a book: `book: true`. Its `title:` names it, and the rest of the body is the index, a list of links to its chapters in the order they are read. This book's own index, cut down to one part:

```markdown
---
title: "Ghost.md: The Guide"
book: true
---
# Ghost.md: The Guide

## Part III · Notes that are something else

13. [[Boards made of list items]]
14. [[Books, and reading one through]]
15. [[Canvases, cards and lines]]
```

In any other Markdown app it reads as a table of contents, and in one that knows wiki links, such as Obsidian, every chapter is a link there too.

- **A chapter is any note, found by its title.** A title with no note yet is a chapter still to be written: the index draws it waiting, and opening it makes the note, with the title as its heading.
- **The order is the list's order.** A chapter indented one level under another is part of it, numbered 2.1, 2.2. Deeper indentation reads as the same level.
- **A chapter is an item that opens with its link.** `- [[Lists and to-dos]] — the short version` is a chapter. `- The to-dos are in [[Lists and to-dos]].` is the book's own words about one.
- **A numbered index is its numbered list.** Beside `1.`, `2.`, a bullet list at the top level is about the book, not in it, and a chapter added to the index takes the next number.
- **The book's own words stay.** What comes before the first chapter is shown over the index, and what comes after the last under it, as this book's "Five things worth knowing" is. Headings between chapters, such as this book's Parts, stay in the Markdown; the index numbers the chapters straight through.

## Making one

The + offers a Book beside a Note and a Canvas, and opens the New book sheet. Give it a name, then pick its pages from your notes under Find a note: a tap puts one in and a second takes it out. The pages chosen stand above the list in order, to move up or down, drag by their grip or leave out. Make the book writes one note with that index and opens it; closing the sheet makes nothing.

The index shows no heading to rename a book in. Rename it from its tab's menu, or the More sheet's Name field.

## The index

A book is drawn as its index, where a note's words would be. The switch in the header goes between the Index and its Markdown.

| In the index | What it does |
| --- | --- |
| Tap a chapter | Opens it, or makes it if it is not written yet. |
| The arrows | Move a chapter one place up or down. |
| The grip | Drags a chapter to a new place: at once with a mouse, after a short hold on a phone. |
| The cross | Takes a chapter out of the book. Its note is never touched. |
| Add a chapter | Names a new one. Add and open puts it in and opens it; Add as a canvas makes it an empty canvas. |
| Add a note you have | Tick any of your notes; they go in in the order you ticked them. |
| Read straight through | Every chapter on one page, with a rail of their titles to jump between them. Index goes back. |

A canvas is a note found by its title like any other, so a book can hold one. It wears the canvas's mark after its title, opens as a canvas, and in the read-through says to open it.

Every change here is a change to the book note's Markdown, saved the way typing is. A book edited in another app draws the same index here.

## Reading a chapter

A chapter wears its book. Under the note's header, a bar gives the book's title, the chapter's place in it ("2 of 5") and the chapters either side; a tap on the title opens the index. At the foot of the page, Previous and Next go on to the chapters either side. A note in two books wears the first in your library whose index names it.

**One tab.** A page opened from inside a book, from the index, the bar, the foot, the Book index at the side or the read-through, takes the book's tab rather than a new one. A link in a chapter's words still opens a tab of its own.

**Where you left off.** A book remembers whether it was last at its index, in a chapter, or reading straight through. Open it from outside, from the home page, the sidebar, search or a link, and it goes back there, to the line you were at. From inside the book, the bar's book button, its tab, Back and Forward go to the index, so there is always a way back to it.

## Books in the library

- The home page's **Library** sits between Pinned and Recent: a card per book, with its name, how many pages it has and the first four of them. A book is not also a Recent card.
- A note that is a chapter wears a small book mark and the book's name, in the sidebar and on its card.
- The **Book index** button at the right end of the top bar shows the book's index at the side of the page, the open chapter marked.

## Chapter numbers without a book

A chapter can carry its number in its title, and the numbers put chapters in order when no book does:

```
Boards made of list items · Ch. 13
Boards made of list items (Chapter 13)
Boards made of list items · Chapter XIII
13 · Boards made of list items
Chapter 13: Boards made of list items
```

"Ch." or "Chapter" and an Arabic or Roman number go at the end, after a middle dot, a dash, a comma or a colon, or in brackets; a number in front is read too. A bare number at the end, as in "Top 10", is not a chapter number.

When the open note has a number and no book names it, the **Book index** button shows its run: the numbered chapters that belong with it, in order. They belong together when each page's first link, other than to another numbered chapter, goes to the same note; with no such link, when they share a folder. A chapter alone is no run, and with nothing to show there is no button.

## Sharing, and by voice

A whole book can be shared as one read-only link, its index and every written chapter: see [[Sharing a note or a book]].

Books are not made or filled by voice at present. The recorder reads a command once, when you stop, and the only commands it carries out itself are adding to a note and making a new list, so "Hey Ghost, make a book called Field guide" and "Hey Ghost, add a chapter to the field guide" change no book. Said into a note's own Speak, words like these go to the AI as a spoken ask about that note instead ([[Spoken asks and the review]]). Use the + and the index.

## Read next

- [[Canvases, cards and lines]]
- [[Sharing a note or a book]]
- [[Links between notes]]
