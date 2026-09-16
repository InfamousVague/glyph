# Boards in markdown

A kanban board in a Glyph note is plain markdown. Nothing is stored beside the note, nothing is lost opening it
somewhere else, and a person reading the raw file sees the same board in words.

Matt: "define and create a markdown standard we use to create kanban boards and task management boards entirely
within markdown, linking the tasks in the board to a task on the page."

## The shape

Two ordinary pieces of markdown, which is the whole standard.

**1. A task carries an anchor.** Any to-do line may end with `^` and a name:

```markdown
- [ ] Ship the pricing page ^ship-page
- [x] Pick a launch date ^pick-date
```

The anchor names that task so something else can point at it. It is the block id other markdown tools write the same
way, and it reads as plain text anywhere.

**2. A fenced `board` block lays the columns out.** Each line is a column: its name, a colon, then the anchors of the
tasks in it, in the order they sit:

````markdown
```board
To do: ship-page, email-list
In progress: fix-login
Done: pick-date
```
````

That is all. A renderer that knows nothing about boards shows a code block and a list of tasks, both readable. Glyph
draws the columns as a board and the tasks as cards.

## The rules

- **A card is a task.** A card shows the words of the task with that anchor, and its tick box is that task's tick
  box. Tapping the words puts the caret on the task in the note: the card and the task are the same thing.
- **An anchor names one task.** The first task with that anchor wins; a second is ignored.
- **A card whose task is gone** is drawn as a missing card with its anchor, so nothing disappears silently.
- **A task with no card** is an ordinary to-do. A board never has to hold every task in the note.
- **A column called Done means done.** A task ticked anywhere is drawn in the Done column if the board has one, and
  ticking a card moves it there; unticking puts it back in the first column. A board with no Done column leaves the
  ticks to the tasks.
- **Column names are free.** "To do", "Waiting on Sam", "This week": anything up to the colon, and the same name
  twice is one column.
- **Empty columns stay.** `Blocked:` with nothing after it is a column with no cards, not a mistake.
- **A note may hold several boards.** Each fence is its own board; anchors are shared across the note, so the same
  task can sit on two boards.

## What Glyph does with it

- `src/app/core/boards.ts` reads and writes both pieces, and is the only place that knows the syntax.
- `src/app/editor/boards.ts` draws the board in a note, and puts the caret in the fence when it is tapped for editing,
  the way a table steps aside (`editor/tables.ts`).
- Moving a card, ticking it, or adding one rewrites the fence and the task line as a person would have typed them.
- `src/app/core/boardNote.ts` is the example note, added from Settings.
- A note that is already a list of to-dos becomes a board from More → **Make a board**: every to-do is given a name at
  the end, and a fence of `To do / Doing / Done` goes in under the title, with whatever is ticked already in Done.
  Nothing else about the note changes, and one Undo puts it back.
- A card says its task's words with the markdown taken off — a link reads as its own words, not its URL — and shows
  three lines at most. The note below always has the whole thing.
