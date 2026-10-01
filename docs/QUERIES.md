# Queries in markdown

A query is a fenced block that lists what matches across every note: to-dos, tickets or notes. In Ghost.md it is
drawn as what it finds, live, as a list, a table, a board, a month, a timeline or a count. In any other app it is a
code block of a few readable lines, which is all it is.

Matt asked: "What other notion and jira like features can we code with custom markdown to add to our app like tickets
and such". Of the ideas that came back he picked three, "Do 1, 2 and 3 in parallel": fields on a to-do (DESIGN §158),
tickets as notes (docs/TICKETS.md, §157), and this, the database view over both. The grammar the three share is §156;
this feature is §159.

## The shape

````markdown
```query
from: tickets [[Launch]] #bug
where: status != Done and (priority >= high or due < today+7)
sort: priority, due
group: status
show: board
columns: id, title, assignee, due
total: estimate
limit: 20
```
````

One clause to a line, a name, a colon and what it says. Every clause can be left out, so `from: tasks` alone is a
query. The names are Dataview's and Obsidian Tasks' where they have one; `sort by:` and `group by:` are read too.

| Line | What it says | Left out |
| --- | --- | --- |
| `from:` | what kind of record, then where from | every note |
| `where:` | tests the records must pass | all of them (open ones, for to-dos) |
| `sort:` | fields to order by, each `asc` or `desc` | the kind's own order |
| `group:` | one field to group by | not grouped (a board: by status) |
| `show:` | `table`, `list`, `board`, `calendar`, `gantt` or `count` | a table for tickets, a list otherwise |
| `columns:` | the fields a table shows, and a list or a card beside each name | the kind's own columns |
| `total:` | fields to add up | none |
| `limit:` | how many at most | all |

A query that cannot be read is drawn as its lines and one sentence that says what is wrong and where: "Line 2, column
16: After “status =”, something to compare it with: a word, a number, a date or empty." A line it does not know is
answered with the one it probably meant ("did you mean “from”?").

## from:

First the kind: **`notes`** (the default; tickets are notes too), **`tickets`** (notes whose front matter says
`type: ticket`), or **`tasks`** (every list item with a box, in any note). `issues`, `to-dos` and the singulars are
read as the same.

Then where from, side by side for all of them, `or` for either, `not` or a dash to leave one out, brackets to say
which goes with which:

- **`#tag`**: records with that tag, or a tag inside it (`#work` has `#work/clients`). A to-do has its own tags and its
  note's front matter `tags:`; a ticket's `labels:` count as tags.
- **`[[A notebook]]`**: its pages. **`[[Any other note]]`**: the notes that link to it, as Dataview reads
  `FROM [[it]]`. `[[GHO-12]]` names a ticket by its key. A note that is not there is said under the result.
- **`@person`**: records for that person, `@sam` the same person as `assignee: Sam`.
- **`"words"`**: records whose title or words hold them.

## where:

Tests on fields, joined by `and` and `or` (and before or), `not` and brackets:

`=` `!=` `<` `<=` `>` `>=`, `contains` (also `has`, `includes`), `not contains`, `is empty`, `is not empty`, `is`,
`is not`; `==` `≠` `≤` `≥` as a keyboard types them. A field on its own is a test that it says something: `where:
blocked-by`.

The value is read for what it is: a number, a day (`2026-10-03`, `today`, `today+7`, `today-2w`, `tomorrow`,
`yesterday`), `empty`, or words. Words need no quotes (`status = In progress`) unless they hold `and` or `or`. What a
value means is the field's:

- **A priority** compares by rank, the most urgent the greatest: `priority >= high` is high and highest. None sits
  between medium and low, as Obsidian Tasks puts it.
- **A status** compares by its place in the workflow, so `status < Done` is everything before Done.
- **A day** compares as a day. A number as a sum reads one, so `$1,200 > 1000`.
- **A person** is the same person however written. **A list** (tags, labels, blocked-by, people) is equal to anything
  it holds.
- **Words** are equal whatever their case and punctuation.

A comparison with a field that says nothing is false but for `!=`, so `due < today` never lists what has no due date.
A field no record has is empty on all of them, not an error.

## Fields

Any front matter key, by its name in Dataview's form (lower case, a space a dash: `Due Date` is `due-date`). A ticket's
are read as docs/TICKETS.md has them. A to-do's are its fields (core/taskFields.ts): `due`, `start`, `scheduled`,
`done`, `created`, `cancelled`, `priority`, `assignee`, `recurs`, and any `[key:: value]`.

Every record also has `title` (`note` reads better for a to-do: the note it is in), `notebook`, `tags`, `created`,
`updated`, `kind`, `status` and `category` (where the status stands: To do, In progress, Done). A to-do has `text`
(its words), `checked`, and `line`; its `status` is its own `[status:: …]`, else Done where it is ticked.

## The defaults

- **To-dos are the open ones**, unless the query asks about being done: a `where:` or `group:` naming `checked`,
  `status`, `done` or `category`, or a board.
- **The order.** Notes, the last changed first. Tickets, the most urgent first, then the soonest due, then by key.
  To-dos, the soonest due first, then the most urgent. Nothing in a field sorts last, whichever way.
- **The columns.** Notes: title, updated. Tickets: id, title, status, assignee, priority, due. To-dos: the to-do,
  due, priority, assignee, the note.

## The ways to show it

- **list**: a row each, a to-do's box to tick, its fields beside it as they are drawn on its line.
- **table**: the columns, a total row for `total:`, scrolling sideways on a phone.
- **board**: a lane for each value of `group:`, or each status. A ticket board has every status of its notebook's
  workflow, empty ones included, as a Jira board does. Read only: a card is moved by changing its ticket.
- **calendar**: a month, Monday first, a dot on each day for each record on it (its due day, else scheduled, start,
  or `date:`), red where something on it is late. A tap on a day lists it under the month.
- **gantt**: a bar from each record's start to its due day, drawn by the app's own Mermaid, done grey, under way blue,
  late red, today marked. Records with neither day are counted under it.
- **count**: how many, and the totals.

A tap on a name opens it: a note or a ticket, or a to-do's note at its line (in the same note, the caret goes there).
A to-do's box ticks it where it is written, and a board in that note moves its card with it, as a tap on the box
itself does. The pencil at the query's head puts the caret in its lines.

## Where the code is

- `src/app/core/query/read.ts`: the grammar, and the sentence for a query that cannot be read.
- `src/app/core/query/records.ts`: the library as records, a note's reading kept while its words stay the same.
- `src/app/core/query/values.ts`: what a field says on a record, and how it compares, sorts and groups.
- `src/app/core/query/run.ts`: a query run: the defaults, the order, the groups, the totals, the cells.
- `src/app/core/query/gantt.ts`, `calendar.ts`, `fence.ts`, `tick.ts`: the timeline's Mermaid, the month, where the
  fences are, and a to-do ticked in another note.
- `src/app/core/sums.ts`: the arithmetic a total shares with a sum.
- `src/app/editor/queries.ts`, `QueryView.tsx`: the fence drawn in a note. `src/app/shell/useQueries.ts`: the library
  App hands it.
