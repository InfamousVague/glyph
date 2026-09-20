# Memos

A memo is a note that is a few words and nothing else, kept with the other memos rather than among the notes.
Matt (2026-09-20): "a new type, memo, which is like a note but super small and designed to be collected in a
collection of memos", and "make the plus button ask if they want to create a canvas, note or memo".

## A memo is a tiny note

Matt chose a note of its own over an entry in one file: a memo syncs, links, searches, archives and goes to the
trash like any note, and Obsidian sees a small file. What makes it a memo is one line of front matter, the way any
note from outside carries what it is (docs/MARKDOWN.md):

```markdown
---
kind: memo
---
Ask Sam about the dog before Friday.
```

No title: the list names it by its first words, as it names any note. Its file lives in the library's `Memos/`
folder (docs/LIBRARY.md) when it is in no workspace, and in the workspace's folder when it is in one, as any note
is. `memos/memo.ts` reads and writes it.

## One collection, seen through the chosen workspace

There is one kind of place memos go, newest first (Matt chose one stream over named collections). It is a screen
of its own, `memos/MemosScreen.tsx`, from a row at the foot of the home page and a tool in the sidebar: a field at
the top to write one - Enter keeps, Shift+Enter is a new line, or Keep - and the memos as a wall of small cards
under it. A card tapped becomes a field over its own words, with Done and a bin; a memo emptied is deleted,
undoably, as a note is.

**Each card draws its words through the note's own formatter**, small, the way a home card draws a note
(notes/NotePeek.tsx `whole`): Matt chose that over the words as typed, so a `- [ ]` is a box and `**bold**` is
bold, and a card and a note never disagree about what a mark looks like.

**The wall follows the chosen workspace** (Matt: "filed and filtered"): a memo made while a workspace is chosen
is filed there and shows only there; the home page's Memos row counts that workspace's memos; with All chosen,
every memo shows. The heading names the workspace, and so does an empty wall.

Memos are out of the home page's cards, the sidebar's tree and the tabs: they are a collection, not pages.

## The +

Every + - the home dock's, the tab strip's, the sidebar's - opens one small sheet (`notes/NewSheet.tsx`): Note,
Memo or Canvas. Note is the note it always made; Memo opens the wall with the field focused; Canvas makes an empty
canvas note (docs/CANVAS.md) and opens it.
