# Boards in markdown

A kanban board in a Glyph note is plain markdown. Nothing is stored beside the note, nothing is lost opening it
somewhere else, and a person reading the raw file sees the same board in words.

Matt: "define and create a markdown standard we use to create kanban boards and task management boards entirely
within markdown, linking the tasks in the board to a task on the page", and later "come up with a generic way to
link list items to the board".

## The shape

Two ordinary pieces of markdown, which is the whole standard.

**1. An item carries an anchor.** Any list item may end with `^` and a name:

```markdown
- [ ] Ship the pricing page ^ship-page
- [x] Pick a launch date ^pick-date
- Ask Sam which photos are cleared ^ask-sam
1. Unplug it ^unplug
```

The anchor names that item so something else can point at it. It is the block id other markdown tools write the same
way, and it reads as plain text anywhere. A bullet, a numbered step and a to-do all take one: **the anchor is the
generic link**, and a board is only the first thing that uses it.

Glyph names the anchors it makes from the item's first three words that carry meaning, leaving out filler: "Add
ability to auto-tag notes" is `add-ability-auto`, not `add-ability-to`. An anchor already in a note is never renamed,
since something may already point at it.

The anchor must have a space before it and nothing after it but the end of the line, which is what keeps it apart
from a superscript: `E = mc^2^` and `- the 2 ^nd^ of June` are superscripts, `- Ship it ^ship-page` is an anchor.

**2. A fenced `board` block lays the columns out.** Each line is a column: its name, a colon, then the anchors of the
items in it, in the order they sit:

````markdown
```board
To do: ship-page, ask-sam
In progress: unplug
Done: pick-date
```
````

That is all. A renderer that knows nothing about boards shows a code block and a list of items, both readable. Glyph
draws the columns as a board and the items as cards.

## Pointing at an item from the words

The same anchor works in the middle of a sentence:

```markdown
The pricing page is waiting on [[#^ask-sam]].
```

`[[#^anchor]]` is an item in this note; `[[Note title#^anchor]]` is one in another note (`editor/wikiLinks.ts` owns
the title half, `core/boards.ts` the anchor half). It is drawn as a quiet link and tapping it goes to the line. An
anchor nothing answers is drawn dotted rather than hidden, so a name that has gone can be seen.

This is why the anchor is worth having on every kind of item, not only on the ones a board names: one name, pointed
at from a column, from a sentence, or from another note.

## The rules

- **A card is an item.** A card shows the words of the item with that anchor, and its tick box is that item's tick
  box. Tapping the words puts the caret on the item in the note: the card and the item are the same thing.
- **An item with no box is a card with no box.** A bullet or a numbered step is a card with a dot where the tick
  would be: something on the board that is not work to be finished.
- **An anchor names one item.** The first item with that anchor wins; a second is ignored.
- **A card whose item is gone** is drawn as a missing card with its anchor, so nothing disappears silently.
- **An item with no card** is an ordinary list item. A board never has to hold every item in the note.
- **A column called Done means done.** An item ticked anywhere is drawn in the Done column if the board has one, and
  ticking a card moves it there; unticking puts it back in the first column. Dragging a card into Done ticks it, and
  dragging it out unticks it. A board with no Done column leaves the ticks to the items.
- **Column names are free.** "To do", "Waiting on Sam", "This week": anything up to the colon, and the same name
  twice is one column.
- **Empty columns stay.** `Blocked:` with nothing after it is a column with no cards, not a mistake.
- **A note may hold several boards.** Each fence is its own board; anchors are shared across the note, so the same
  item can sit on two boards.

## What Glyph does with it

- `src/app/core/boards.ts` reads and writes both pieces, and is the only place that knows the syntax.
- `src/app/editor/boards.ts` draws the board in a note, and puts the caret in the fence when it is tapped for editing,
  the way a table steps aside (`editor/tables.ts`).
- Moving a card, ticking it, or adding one rewrites the fence and the item line as a person would have typed them.
- `src/app/core/boardNote.ts` is the example note, added from Settings.
- A note that is already a list becomes a board from More → **Make a board**: every item is given a name at the end,
  and a fence of `To do / Doing / Done` goes in under the title, with whatever is ticked already in Done. A list
  inside a block of code is left alone. Nothing else about the note changes, and one Undo puts it back.
- A card says its item's words with the markdown taken off — a link reads as its own words, not its URL — and shows
  three lines at most. The note below always has the whole thing.

## On a phone

Matt: "add a way to tap and drag to re organize items in lanes and make the UI / UX of these boards friendlier on
mobile". What that means on the page:

- **Press and hold a card, then drag it.** A copy of the card follows the finger and the card itself opens as the
  gap where it will land, in its own column or another. Letting go writes the fence: `putCardAt` puts the card at the
  place the gap was showing, so a card can be reordered inside a lane and not only moved between them.
- Before the hold is up, the finger scrolls the board as it always did. Held against either edge, the board scrolls
  itself along so a card can be taken to a column that is off the screen.
- The chevrons stay. They do the same thing a tap at a time, for a hand that would rather not drag and for anything
  driving the app by keyboard, and every control on a card is a thumb's width.
- Columns snap as they scroll, one to a screen, and a column's name stays at the top while its cards go by.
- An empty column says it will take a card while one is held, rather than being a blank space.
- **+** on a column opens a field at the top of it. The words come first: Enter (or Add) writes
  `- [ ] the words ^anchor` under the board's last item, with the anchor named after the words, and puts the card at
  the top of that column. The field stays open and empty for the next card, and Escape closes it. Nothing is written
  until there are words, so no card is ever named `^item`, and no caret goes into the note to leave a box without its
  space. The board is redrawn in place as cards arrive, which is what keeps the field, and the phone's keyboard,
  between them.
- The anchor at the end of a line is drawn small and faint: the line reads as its words, and the name is there when
  it is wanted.
