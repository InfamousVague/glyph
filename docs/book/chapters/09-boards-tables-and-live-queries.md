# Boards, tables and live queries

Three ways to lay out what's in your notes. A **board** puts list items in columns. A **table** puts words in rows and columns. A **query** gathers what matches from every note and shows it as a list, a table, a board, a calendar, a timeline or a count.

All three are plain Markdown. Opened in another app, a board reads as a list, a table as a table, and a query as a few lines of text.

Boards and queries are in Advanced. In Simple, they're behind **More** on the **+**. With a keyboard, type `/` on an empty line and then a word, such as `board` or `table`, to find the same rows.

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

The board draws each named item as a card. A card *is* its item: tick the card and the line in the note is ticked. Tap a card's words to go to its line.

A column called **Done** means done. Ticking an item moves its card into Done, and moving a card into Done ticks it. A bullet or a numbered step is a card with no box.

Elsewhere in the note, `[[#^book-cabin]]` points at an item by its name: tap it to go there.

### Making a board

- **The + beside an empty line** › **A board**, then **Fresh columns** (To do, Doing and Done) or **From your tickets**, which puts in a ticket query drawn as a board (see below).
- **From a list you have.** Press and hold an item and choose **Board from list**, or **Add to board** to put one item on a board that's already there.
- **From the whole note.** More sheet › **Make a board**: every item in the note becomes a card.

When Ghost.md names an item for you, it uses the first few words that carry meaning, such as `book-cabin`. A name already in a note is never changed, because something may point at it.

### Working with cards

- **Add a card:** the **+** on a column opens a **New card** field at its top. Type, then press your keyboard's done key or **Add**. The card's item is written into the note under the board's last one, as a to-do with its own name. The field stays open for the next; leave it empty to close it.
- **Move a card:** press and hold it, then drag it, within its column or to another. The arrows on a card move it one column at a time.
- **The card's more button** opens its menu: **Move to** another column, **Tick** or **Untick**, **Go to the line**, or **Take off the board**. Taking a card off leaves its item in the note. A plugin can add rows here too, such as sending the item to Notion.
- **Set the height:** drag the line under the board. The columns then scroll inside it. The height is written on the fence as `height=`. Double-tap the line to go back to the board's own height.
- **Edit the fence:** tap the board between its cards and it steps aside for its lines, ready to type.
- **Copy the board:** a board drawn as columns can't be selected, so with the caret on it, press and hold and choose **Copy board**. It copies the fence and the items it names, as text.

Every change to a board is one edit, so Undo takes back exactly the last thing you did. A card whose item has gone shows only its name, so you can see it and take it off.

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
| `from:` | What to look through: `tasks` (to-dos), `tickets`, `notes` or `events`, and where |
| `where:` | What has to be true, such as `status != Done` or `assignee = Sam` |
| `sort:` | The order, by one field or several, each `asc` or `desc`: `sort: priority, due desc` |
| `group:` | A heading, or a board lane, for each value: `group: assignee` |
| `columns:` | The fields a table shows, and a list or board shows beside each one |
| `total:` | A number to add up, under each group and at the end: `total: estimate` |
| `limit:` | How many at most |
| `show:` | How to draw it: `table`, `list`, `board`, `calendar`, `gantt` or `count` |

Every line can be left out. `sort by:` and `group by:` work too, as they do in Dataview.

**Where to look.** After the kind, `from:` can narrow it down, and the pieces can be combined with `or`, `not` and brackets:

- `from: tickets [[Product]]`: the pages of the notebook called Product, or the notes that link to that note.
- `from: tasks #bug`: only notes with that tag.
- `from: tasks @sam`: only what's for Sam.
- `from: notes "cabin"`: only notes with those words.

**Tests.** `where:` compares a field with `=`, `!=`, `<`, `<=`, `>` and `>=`, or uses `contains` and `is empty` (`is not empty`). Join tests with `and`, `or` and `not`, with brackets to group them. A field on its own tests that it says something. A day can be written `2026-10-30`, `today`, `today+7` or `today-2w`. Put words in quotes to keep them as words.

**Fields.** A to-do has `text`, `due`, `start`, `scheduled`, `done`, `priority`, `assignee`, `status` (To do or Done), `checked`, `recurs`, `note` and `tags`, plus any `[name:: value]` of your own. A note has `title`, `created`, `updated`, `notebook`, `tags` and any front-matter key. A ticket has those and its own: `id`, `status`, `assignee`, `priority`, `due`, `start`, `estimate`, `blocked-by`, `parent` and `labels`. Upper or lower case and spaces or dashes don't matter: `Due Date` and `due-date` are the same field.

**Events.** `from: events` lists what's on your calendars, with `title`, `start`, `end`, `allday`, `time`, `location` and `calendar`. It needs the Calendar plugin. A to-do calendar (`from: tasks` with `show: calendar`) shows the day's events too, more quietly.

A query that can't be read isn't run. It says what's wrong, and on which line.

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

A drawn query has a switcher for its view: **Table**, **List**, **Board**, **Calendar**, **Timeline** and **Count**. Beside it are two buttons:

- **Build the query** (the sliders) opens a sheet where you pick, without typing: **List** (To-dos, Tickets, Notes or Events), **Only** (such as **Due this week**, **Overdue**, **Not done** or **Changed this week**), **Group** (**No grouping**, **By status**, **By person** or **By priority**) and **Show**. The query behind the sheet changes as you pick. A `where:` you wrote yourself shows as **Your own**, to change with the pencil.
- **Edit the query** (the pencil) opens its lines, to type.

A query that finds nothing says "Nothing matches this query yet."

### Working in a query

What a query shows is the real thing, so you can change it from there:

- **Tick a to-do** in a list or table, and it's ticked in its note.
- **Tap a name** to open the note, at the to-do's line.
- **Tap a value** (a status, a priority, a person or a date) to pick another. It's written into the note it came from.
- **Drag a card to another lane** on a board grouped by status, or by a field of plain words, and that field is set to the lane's. A row of a grouped list or table can be dragged between groups the same way. Lanes of dates, people or priorities can't be dragged across.
- **Add a ticket on a board.** The **+** on a lane opens a **New ticket** field. Type its title and press the done key or **Add**: the ticket is made with that lane's value, so it lands where you typed it. The field stays open for the next.

A query drawn as a board keeps a height, as a board does: drag the line under it. A timeline is drawn with today marked; tickets with no start or due day are counted under it.

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

See also: [[Lists, to-dos and tickets]], [[Notebooks and journals]], [[AI on your device]], [[Plugins, one by one]], [[Markdown and the Ghost.md marks]]
