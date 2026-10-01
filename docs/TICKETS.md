# Tickets as notes

A ticket in Ghost.md is a note. Its fields are the note's front matter, its words are the note's words, and its key
is a link any note can make. Nothing is stored beside it, and the file reads as a ticket in any other Markdown app:
Obsidian shows the front matter as properties, GitHub draws it as a table over the file, and `[[GHO-12]]` is a link.

Matt asked: "What other notion and jira like features can we code with custom markdown to add to our app like tickets
and such". Of the ideas that came back he picked three, "Do 1, 2 and 3 in parallel": fields on a to-do, tickets as
notes, and a query fence. This is the second. The grammar the three share is docs/DESIGN.md §156; this feature is §157.

## The shape

```markdown
---
type: ticket
id: GHO-12
status: In progress
assignee: Sam
priority: high
due: 2026-10-03
estimate: 3
blocked-by: "[[GHO-9]]"
---
# Fix the login loop

Signing in on the phone sends you back to the sign-in page once the cookie has expired.
```

- **`type: ticket`** makes the note a ticket. That is the whole of the rule (`isTicket`, `src/app/core/properties.ts`).
- **`id:`** is its key: the notebook's key, a dash and a number, `GHO-12`, as Jira writes an issue's.
- **The rest are its properties**, each with a kind a panel can pick it by and a query can compare it by:

| Key | Kind | What it holds |
| --- | --- | --- |
| `status` | status | one of the notebook's workflow, `To do`, `In progress` |
| `assignee` | person | a name, `Sam`, the same person as `@sam` in a to-do (core/taskFields.ts `samePerson`) |
| `priority` | priority | `highest`, `high`, `medium`, `low`, `lowest`: the five of Obsidian Tasks and Jira |
| `due`, `start` | date | an ISO day, `2026-10-03` (core/days.ts) |
| `estimate` | number | `3`, `2.5 days` (the number it starts with) |
| `blocked-by` | links | other tickets, `"[[GHO-9]]"` or `["[[GHO-9]]", "[[GHO-10]]"]` |
| `parent` | link | one ticket, `"[[GHO-3]]"` |
| `labels` | list | `[bug, ui]` |

A list is written across, never down the page: the front matter rule the whole app keeps (core/frontMatter.ts) takes
no YAML list written as `  - item`, so a block with one is not front matter. A value YAML would read as something else
is quoted when the app writes it: a note link, which opens with `[`, a colon and a space, a ` #`. Any other key a
ticket has (its `authors:`, a `title:`) stays where it is and is drawn as before.

## The notebook's key

A notebook numbers its tickets: `key: GHO` in its front matter, set in its More sheet as **Ticket key**, two to ten
capitals and digits starting with a letter (`PROJECT_KEY`). The field takes it in any case, writes it in capitals the
moment it is a key, and says what is wrong while it is not one. Empty takes it off.

```markdown
---
title: "Ghost.md"
book: true
key: GHO
statuses: [Backlog, To do, In progress, In review, Done]
---
# Ghost.md

- [[Fix the login loop]]
- [[Fix the session cookie]]
```

**The next number** is one more than the highest any note names for that key, in an `id:` or anywhere in its words,
across the whole library and the Trash (`nextIssueId`, `src/app/book/tickets.ts` `nextTicketId`). Nothing stores a
counter, which would be one more thing to sync and to go wrong; and a number is never given twice while anything still
names it, so a link to a deleted ticket never finds a new one. A `[[GHO-40]]` written before GHO-40 exists makes the
next ticket GHO-41.

**The workflow** is the notebook's `statuses:`, or Backlog, To do, In progress, In review, Done. Every status stands
somewhere, as Jira's categories do: not started, under way, or done (`statusCategory`). Done, Closed, Won't do and
Cancelled are done; In progress, In review and anything "In …" are under way; Backlog and To do are not started; a
name none of those know is placed by where it is in the workflow, first not started and last done. The category is the
status's colour wherever it is drawn: the faint ink, blue, green.

## Making one

- **New ticket**, beside Add a page in a notebook with a key (`src/app/book/BookView.tsx`): a title, and what it starts
  with, just the title or a ticket's template. The line goes into the index as a page's does, and App makes the note
  (`openTicketWithin`): `type: ticket`, the next id, and the workflow's first open status, To do in the default, after
  Backlog (`firstOpenStatus`).
- **Bug report** and **Feature**, two of the app's own templates (`src/app/notes/noteTemplates.ts`), on a new note's
  blank page and in New ticket's choices. A Bug report is Steps to reproduce, Expected and Actual; a Feature is Problem,
  Proposal and Done when. Their front matter carries `id: "{{next-id}}"`, which the template filler fills with the next
  key of the notebook the note is made in, and leaves out, line and all, where there is none (core/template.ts). They
  are pages of your Templates notebook like the rest, and a ticket's page passes its ticket's keys to the note it makes
  (notes/ownTemplates.ts).
- **A ticket with no key** (a Bug report from the blank page, later put in a keyed notebook) is offered its notebook's
  next one on its panel: Give it GHO-14.
- **Make this a ticket**, under More on the + in any note that is not one, nor a notebook or a canvas
  (`src/app/editor/addRows.ts` `ticketPlan`): `type: ticket`, and `status: To do` where it has no status, written into
  its front matter as one change. Its panel then offers the notebook's next key, as above.
- **By hand**, anywhere: `type: ticket` in any note's front matter.

## The panel

A ticket's front matter is drawn over its words as a panel (`src/app/editor/tickets.ts`,
`src/app/editor/TicketPanel.tsx`), Notion's properties: the key at its head, then Status, Assignee, Priority and Due,
and Start, Estimate, Blocked by, Parent and Labels where it has them or once More is pressed. A tap picks a value:

- **Status** from the notebook's workflow, each with its category's colour.
- **Assignee** from the people the library already names, every ticket's assignee and every `@person` in a to-do, the
  most named first (`peopleIn`), or a name typed; or No one.
- **Priority**, one of the five, or None.
- **Due** and **Start** from the phone's own date picker, said as Today, Tomorrow or Sat 3 Oct; a due day passed is
  red while the ticket is not done.
- **Estimate** and **Labels** typed in place, written when the field is left.
- **Blocked by** and **Parent** from the library's other tickets, found by key or title as they are typed, and
  written as links by key, one quoted, several as a list.

Each pick is one change to the front matter (`writeProperty`, through core/properties.ts `withProperty`), so one Undo
takes it back, and the key keeps the case it was written in. A ticket blocked by one that is not done says so first, a
lock and the ticket, a tap away. The keys a ticket does not know are a quiet line under the panel. That line, or the
panel's `{}` button, or the caret moved into the block, shows the lines as they are written, and the panel comes back
when the caret leaves, as every drawn block does (editor/drawnBlock.ts). A note that cannot be edited draws the panel
with nothing to pick.

## Keys as links

`[[GHO-12]]` opens the ticket whose id is GHO-12, in any case. A note titled "GHO-12" is still found first by its
title, and a key nobody has is a link to a note not written yet, dashed (App.tsx `byTitle`). The link is drawn with the
ticket's title after it and its status's dot, struck through once the ticket is done, so a note that says "waits on
[[GHO-9]]" says which.

## Where tickets are listed

A ticket says its key and status, small and in its status's colour, on the home page's cards, rows and lines, and on a
notebook's index rows (`src/app/notes/TicketMark.tsx`).

## Claude and sync

- **Claude** (docs/MCP.md): `read_note` finds a ticket by its key. A rewrite that drops the front matter whole gets
  the ticket's keys back; one that writes its own keeps what it wrote, and gets back only `type:` and `id:`, which make
  it a ticket and what its links find (`keepKeys`). A notebook keeps its `key:` and `statuses:`.
- **Sync** carries the body whole, front matter and all, and two devices changing one ticket merge as any note does
  (docs/SYNC.md).
- **The library on disk** (docs/LIBRARY.md) writes its own block, `id:` and `created:`, first, and keeps the ticket's
  block after it as the page wrote it (a test in `src-tauri/src/library/tests.rs`). An app that reads only the first
  block shows the ticket's as text, as it does a notebook's. A ticket written in another app with its keys in the
  file's only block has its `id:` read as the note's own identity; not yet handled.

## Not yet

- A table, a board or a calendar of tickets is the query fence's, and fields on a to-do the first feature's: the other two
  Matt picked, built beside this one on §156's grammar.
- Transitions between statuses are not checked: any status can follow any.
- A ticket's history (who moved it when) is not kept; the note's own versions are what there is.

## Where the code is

| file | what |
| --- | --- |
| `src/app/core/properties.ts` | the grammar: front matter as properties, a ticket's keys and kinds, statuses and their categories, issue keys, `ticketOf` |
| `src/app/book/tickets.ts` | the library's tickets: a notebook's key and next id, the first open status, a new ticket's body, which notebook a ticket is in, finding one by key or title, what it waits on, the people named |
| `src/app/editor/tickets.ts` | the panel in place of the front matter, a property written, and a key's title after its link |
| `src/app/editor/TicketPanel.tsx`, `src/app/editor/ticketRows.ts` | the panel drawn, its pickers, and what it shows |
| `src/app/notes/TicketMark.tsx` | a ticket's key and status where it is listed |
| `src/app/shell/useTickets.ts` | the library's tickets as App hands them to the note on screen |
| `src/app/notes/noteTemplates.ts`, `src/app/core/template.ts` | Bug report and Feature, and `{{next-id}}` |
| `src/app/book/BookView.tsx`, `src/app/editor/NoteSettings.tsx` | New ticket, and the notebook's Ticket key |
| `mcp/server.ts` | a ticket's keys through a rewrite, and `read_note` by key |
