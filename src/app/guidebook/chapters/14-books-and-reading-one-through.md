# Notebooks, and reading one through

_A notebook is a note whose body is its index: links to its pages, in order. This Guide is one._

## A notebook is a note

One line of front matter makes a note a notebook: `book: true`. Its `title:` names it, and the rest of the body is the index, a list of links to its pages in the order they are read. This Guide's own index, cut down to one part:

```markdown
---
title: "Ghost.md: The Guide"
book: true
---
# Ghost.md: The Guide

## Part III · Notes that are something else

13. [[Boards made of list items]]
14. [[Notebooks, and reading one through]]
15. [[Canvases, cards and lines]]
```

In any other Markdown app it reads as a table of contents, and in one that knows wiki links, such as Obsidian, every page is a link there too.

- **A page is any note, found by its title.** A title with no note yet is a page still to be written: the index draws it waiting, and opening it makes the note, with the title as its heading.
- **The order is the list's order.** A page indented one level under another is part of it, numbered 2.1, 2.2. Deeper indentation reads as the same level.
- **A page is an item that opens with its link.** `- [[Lists and to-dos]] — the short version` is a page. `- The to-dos are in [[Lists and to-dos]].` is the notebook's own words about one.
- **A numbered index is its numbered list.** Beside `1.`, `2.`, a bullet list at the top level is about the notebook, not in it, and a page added to the index takes the next number.
- **The notebook's own words stay.** What comes before the first page is shown over the index, and what comes after the last under it, as this Guide's "Five things worth knowing" is. Headings between pages, such as this Guide's Parts, stay in the Markdown; the index numbers the pages straight through.

A notebook was called a book once. The line that makes one still says `book: true`, so a book made then is a notebook now, and a notebook made now is still one in an older copy of the app.

## Making one

The + offers a Notebook beside a Note and a Canvas, and opens the New notebook sheet. Give it a name, then pick its pages from your notes under Find a note: a tap puts one in and a second takes it out. The pages chosen stand above the list in order, to move up or down, drag by their grip or leave out. Make the notebook writes one note with that index and opens it; closing the sheet makes nothing. **New notebook** in the command palette opens the same sheet.

The index shows no heading to rename a notebook in. Rename it from its tab's menu, or the More sheet's Name field.

## The index

A notebook is drawn as its index, where a note's words would be. The switch in the header goes between the Index and its Markdown.

| In the index | What it does |
| --- | --- |
| Tap a page | Opens it, or makes it if it is not written yet. |
| The arrows | Move a page one place up or down. |
| The grip | Drags a page to a new place: at once with a mouse, after a short hold on a phone. |
| The cross | Takes a page out of the notebook. Its note is never touched. |
| Add a page | Names a new one. Add and open puts it in and opens it; Add as a canvas makes it an empty canvas. |
| Add a note you have | Tick any of your notes; they go in in the order you ticked them. |
| Read straight through | Every page, one after another, with a rail of their titles to jump between them. Index goes back. |

A canvas is a note found by its title like any other, so a notebook can hold one. It wears the canvas's mark after its title, opens as a canvas, and in the read-through says to open it.

Every change here is a change to the notebook note's Markdown, saved the way typing is. A notebook edited in another app draws the same index here.

## Reading a page

A page wears its notebook. Under the note's header, a bar gives the notebook's title, the page's place in it ("2 of 5") and the pages either side; a tap on the title opens the index. At the foot of the page, Previous and Next go on to the pages either side. A note in two notebooks wears the first in your library whose index names it.

**One tab.** A page opened from inside a notebook, from the index, the bar, the foot, the Notebook index at the side or the read-through, takes the notebook's tab rather than a new one. A link in a page's words still opens a tab of its own.

**Where you left off.** A notebook remembers whether it was last at its index, on a page, or reading straight through. Open it from outside, from the home page, the sidebar, search or a link, and it goes back there, to the line you were at. From inside the notebook, the bar's notebook button, its tab, Back and Forward go to the index, so there is always a way back to it.

## Notebooks in the library

- The home page's **Notebooks** sit above Recent: a card per notebook, with its name, how many pages it has and the first four of them. A journal's card counts its entries and lists the four newest. A notebook is not also a Recent card, and neither is a journal's entry.
- A note that is a page wears a small mark and the notebook's name, in the sidebar and on its card.
- The **Notebook index** button at the right end of the top bar shows the notebook's index at the side of the page, the open page marked.

## Chapter numbers without a notebook

A chapter can carry its number in its title, and the numbers put chapters in order when no notebook does:

```
Boards made of list items · Ch. 13
Boards made of list items (Chapter 13)
Boards made of list items · Chapter XIII
13 · Boards made of list items
Chapter 13: Boards made of list items
```

"Ch." or "Chapter" and an Arabic or Roman number go at the end, after a middle dot, a dash, a comma or a colon, or in brackets; a number in front is read too. A bare number at the end, as in "Top 10", is not a chapter number.

When the open note has a number and no notebook names it, the **Notebook index** button shows its run: the numbered chapters that belong with it, in order. They belong together when each page's first link, other than to another numbered chapter, goes to the same note; with no such link, when they share a folder. A chapter alone is no run, and with nothing to show there is no button.

## Journals

A journal is a notebook of dated entries, each started from a template the journal keeps: the date and the time, a question for the morning, a to-do list. It can keep where each entry was written too.

**Making one.** In the New notebook sheet, choose Journal under the name. Instead of pages you choose what each entry starts with, see the page an entry would start as now, and decide whether entries keep where you were. **New journal** in the command palette opens the sheet on Journal. A notebook you have already can be kept as one from its More sheet, **Keep it as a journal**: its pages stay where they are, and Make it a notebook again takes that back.

| Each entry starts with | What it writes |
| --- | --- |
| The date and the time | The day as a heading, then the time in bold, ready for your words. |
| Just the time | The time in bold. |
| A morning page | The day, then a question for the morning. |
| A day's to-dos | The day, then a to-do list with its first box. |
| My own | Whatever you write, with placeholders to tap in. |

Your own template takes the placeholders Obsidian's templates use: `{{date}}` (Monday 28 September), `{{time}}` (14:05, always on a 24-hour clock), `{{weekday}}`, `{{title}}` and `{{journal}}`, and `{{date:YYYY-MM-DD}}` or `{{time:HH.mm}}` for a format of your own. Words inside a format go in square brackets, as in `{{date:D MMMM [at] HH:mm}}`, or their letters are read as the date's. Obsidian's `{{date}}` is `2026-09-28`, and here it is the long day, so write `{{date:YYYY-MM-DD}}` where the two should match. A changed template is for entries from then on.

**New entry.** A journal is drawn as its entries, by the month each was written in, newest first, with **New entry** at the top. A tap makes a note named by the minute, such as `2026-09-28 14.05`, starts it from the template, adds its line to the journal and opens it with the caret at the end. The name sorts in time order wherever notes are sorted, reads the same in every language and makes a whole file name, so the journal's links work in any Markdown app. The friendly date is the entry's heading. Two entries in one minute are `2026-09-28 14.05` and `2026-09-28 14.05 (2)`.

- **An entry you do not write in is taken back** when you leave it: go home, close its tab, or go back to the journal, and the entry and its line are gone, as a new note left without a word leaves nothing behind. Switching tabs, or recording something else, is not leaving it. One word typed makes it yours at once.
- **Speak an entry.** A journal's mic makes an entry and records into it. The words go on from its time, so a spoken entry still starts with it, and a day's to-dos said aloud become to-dos. Say nothing and you are back on the journal, with no entry left.
- **Where it was written** is the entry's own tag, with the map at its top, when the journal keeps places. It is found as the entry is made, and written in with your first words, so an entry you leave untouched keeps no place and no place name is looked up for it. The first time, the app says why before the phone asks. Local only, a Mac and a phone that was not allowed to say where it is keep no place, whatever the journal says.
- **The months.** The three newest are open, and each older month is a row that opens it. A row gives the day, the time, where, and how the entry starts. The entries are in the order they were written, whatever order their lines are in.
- **An entry's bar** walks the entries in the order they were written, so Previous is the entry before. Opening a journal from outside always opens the journal, where New entry is, not the entry you last read.
- **From home** a new entry is two taps: the + and then Entry in, for the journal you wrote in last. The command palette has New entry in for up to three journals.

## Sharing, and by voice

A whole notebook can be shared as one read-only link, its index and every written page: see [[Sharing a note or a notebook]]. A journal is shared an entry at a time: open the entry and share it from its More sheet.

Notebooks are not made or filled by voice. A notebook is never written into by voice either: words said for one stay where you are, and after "Hey Ghost" the chip says why ("“Field guide” is a notebook, so the words stay here", or "“Diary” is a journal"). A journal's entries are made by a tap on New entry or its mic. "Make a notebook called Field guide" and "add a page to the field guide" change no notebook, with or without the keyword. Said after "Hey Ghost" into a note's own Speak, words like these go to the AI as a spoken ask about that note instead ([[Spoken asks and the review]]); without it, they are the note's words. Use the + and the index.

## Read next

- [[Canvases, cards and lines]]
- [[Sharing a note or a notebook]]
- [[Links between notes]]
