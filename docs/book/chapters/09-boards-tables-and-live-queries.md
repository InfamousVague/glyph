# Boards, tables and live queries
Three ways to lay out what's in your notes. A **board** puts list items in columns. A **table** puts words in rows and columns. A **query** gathers what matches from every note and shows it as a list, a table, a board, a calendar, a timeline or a count.

All three are plain Markdown. Opened in another app, a board reads as a list, a table as a table, and a query as a few lines of text.

Boards and queries are in Advanced. In Simple, they're behind **More** on the **+**.

## Boards

A board is made of two ordinary pieces of Markdown.

**Named items.** Any list item can end with a space, a `^` and a name. The name is drawn small and faint.

**A board fence.** A block that opens with ```` ```board ```` and closes with three backticks. Each line inside is a column: its name, a colon, then the names of its cards, separated by commas.

````
```board
To do: book-cabin, pack-coffee
Waiting on Sam: sam-dog
Done: pick-weekend
```

- [ ] Book the cabin ^book-cabin
- [ ] Pack the coffee ^pack-coffee
- Sam and the dog ^sam-dog
- [x] Pick the weekend ^pick-weekend
````

The board draws each named item as a card. A card *is* its item: tick the card and the line in the note is ticked.

### Making a board

- **The + beside an empty line** › **A board**, then **Fresh columns** (To do, Doing and Done) or **From your tickets**.
- **From a list you have.** Press and hold an item and choose **Board from list**, or **Add to board** to put one item on a board that's already there.
- **From the whole note.** More sheet › **Make a board**: every item in the note becomes a card.

When Ghost.md names an item for you, it uses the first few words that carry meaning, such as `book-cabin`. A name already in a note is never changed, because something may point at it.

### Working with cards

- **Move a card:** press and hold it, then drag it to another column.
- **The card's more button** opens its menu: **Move to** another column, **Tick** or **Untick**, **Go to the line**, or **Take off the board**. Taking a card off leaves its item in the note.
- **Set the height:** drag the line under the board. The columns then scroll inside it. The height is written on the fence as `height=`. Double-tap the line to take it off.
- **Edit the fence:** tap the board between its cards and it steps aside for its lines, ready to type.

## Tables

Pipes between the cells, and a row of dashes under the first row:

```
| What  | Where  |
| :---- | -----: |
| Tent  | Garage |
| Stove | Shed   |
```

The note draws it as a real table. A colon at the left or right of a column's dashes lines that column up to that side. A colon at each end centres it.

- **Change a table:** tap it. Its pipes come back for you to edit, and it's drawn again when you leave it.
- **Make it bigger:** **+ Column** and **+ Row** sit under the table.
- **Make one:** the **+** beside an empty line › **A table**, or press and hold and choose **Style** › **Table**.

A wide table scrolls sideways. A table can also hold blanks for the AI to fill: see [[AI on your device]].

## Queries

A query is a block called `query` that lists what matches across every note. It keeps up as your notes change.

````
```query
from: tasks
where: due <= today+7
sort: due
show: list
```
````

One line each:

| Line | What it says |
|---|---|
| `from:` | What to look through: `tasks` (to-dos), `tickets`, `notes` or `events` |
| `where:` | What has to be true, such as `status != Done` or `assignee = Sam`, joined with `and` or `or` |
| `sort:` | The order, by one field or several: `sort: priority, due` |
| `group:` | A heading, or a board lane, for each value: `group: assignee` |
| `total:` | A number to add up, under each group and at the end: `total: estimate` |
| `show:` | How to draw it: `table`, `list`, `board`, `calendar`, `gantt` or `count` |

`from: tickets [[Product]]` looks only at the tickets in the notebook called Product. `from: events` needs the Calendar plugin.

### Ready-made queries

You don't have to write one. On the **+** beside an empty line, choose **A database**, then one of these:

- To-dos due this week
- Overdue to-dos
- To-dos by person
- To-dos on a calendar
- A ticket board
- Open tickets, with estimates
- A ticket timeline
- Notes changed this week
- How many to-dos are open
- Write your own

### Changing a query

A drawn query has a switcher for its view: **Table**, **List**, **Board**, **Calendar**, **Timeline** and **Count**. The pencil, **Edit the query**, opens **Build the query**, where you choose what to list, which ones, how to group them and how to show them, without typing. A query that finds nothing says "Nothing matches this query yet."

A query drawn as a board keeps a height, as a board does: drag the line under it.

## A sprint, in two queries

````
```query
from: tickets [[Product]]
where: status != Done
sort: priority, due
show: board
```

```query
from: tickets [[Product]]
total: estimate
show: table
```
````

The first is a ticket board that moves as tickets change. The second adds up what's left.

See also: [[Lists, to-dos and tickets]], [[Notebooks and journals]], [[Plugins, one by one]], [[Markdown and the Ghost.md marks]]
