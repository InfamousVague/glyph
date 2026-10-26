# Lists, to-dos and tickets

Lists are where most plans start. In Ghost.md a list can be a shopping list, a set of steps, a row of to-dos with due dates and people, or a whole ticket tracker. All of it stays plain Markdown.

The examples in this chapter sit in code blocks, so they don't land on your own to-do list.

## Lists

```
- Oat milk
- Rye bread
- Coffee

1. Unplug it
2. Wait a minute
3. Plug it back in
```

A dash and a space start a bullet list, and a number, a dot and a space start a numbered one. Press Enter and the next line carries on the list. Backspace takes a marker off whole. Indent an item to put it under the one above.

## To-dos

A dash, a box, and the thing to do:

```
- [ ] Book the cabin
- [x] Pick a date
```

Tap the box to tick it, or type an `x` between the brackets.

### Where your to-dos gather

- **In Simple,** the **To-dos** tab collects every open to-do from every note: **Overdue**, **Today**, **Later** and **Someday**. Tick one there and it's ticked in its note.
- **In Advanced,** put a query in any note to list to-dos however you like: due this week, by person, on a calendar. See [[Boards, tables and live queries]].

### Due dates, priorities and people

A to-do can say when it's due, how much it matters and who it's for. Ghost.md uses the signs Obsidian Tasks reads:

```
- [ ] Fix the login loop @sam ⏫ 📅 2026-10-30
```

| Sign | Means |
|---|---|
| `📅 2026-10-30` | Due on that day |
| `🛫`, `⏳` | Starts, or scheduled for, a day |
| `🔺` `⏫` `🔼` `🔽` `⏬` | Highest, high, medium, low and lowest priority |
| `@sam` | Who it's for |
| `🔁` | It repeats |
| `[effort:: 3]` | Any field of your own |

In a note each one is a chip. A date reads "Today", "Tomorrow" or a short date, turns amber on the day and red once it has passed. Tap a chip to change it.

You don't have to type the signs. Press and hold a to-do and choose **Due date**, **Priority** or **Assign**. The date page offers **Today**, **Tomorrow**, **Next week** and **Pick a date**. Where reminders are on, **Remind me** and **Remind me at a place** are there too.

## Lines that count

**Choices.** Round brackets make a choice. Tap one to pick it and clear the others in the group.

```
Where do we stay?
- ( ) Tent
- (x) Cabin
- ( ) Hotel
```

**Counters.** A count and a goal in square brackets: `- Water [3/8]`. Tap to add one, press and hold to take one away.

**Sums.** A line that starts with `= ` shows its answer after it: `= $450 + 120 * 2` shows `→ $690`. The answer is never written into the note, so it changes when a number does. Use `+`, `-`, `*`, `/`, `^`, `%` and brackets.

**Progress.** A heading with to-dos under it counts them: "1 of 2", then "All 2 done". There's nothing to type.

## Tickets

A ticket is a note whose front matter says `type: ticket`. Use one for a bug, a feature or any piece of work you want to track.

```
---
type: ticket
id: GHO-12
status: In progress
assignee: Sam
priority: high
due: 2026-10-30
---
# Fix the login loop
```

Ghost.md draws the fields as a panel at the top of the note: **Status**, **Assignee**, **Priority** and **Due** always, and Start, Estimate, Blocked by, Parent and Labels once they're set. Tap a field to change it. **Show the properties as text** shows the lines themselves.

The usual statuses are Backlog, To do, In progress, In review and Done.

### Making a ticket

- **From a template.** On a blank note, choose **Bug report** or **Feature**.
- **From a note you're in.** On the **+** beside an empty line, choose **Make this a ticket** (under More). It writes `type: ticket` and `status: To do`.
- **From a ticket notebook,** with **New ticket**. See below.

### Ticket notebooks and keys

A notebook can number its tickets, the way a Jira project does. Open the notebook's More sheet and set its **Ticket key**, such as `GHO`. Then:

- Its index offers **New ticket**, which makes the next one: GHO-1, GHO-2 and on.
- A ticket in that notebook with no number yet offers **Give it GHO-13**.
- A notebook can set its own statuses with a line like `statuses: [Backlog, To do, Doing, Done]`.

```
---
book: true
key: GHO
---
# Ghost.md
- [[Fix the login loop]]
```

Link to a ticket anywhere with its key: `[[GHO-12]]` shows its title and a dot for its status, and is struck through once it's done.

To see tickets across all your notes, as a board, a table or a timeline, use a query. See [[Boards, tables and live queries]].

## Sending items elsewhere

With the Notion or GitHub plugin set up, swipe a list item left to send it as a Notion task or a GitHub issue. Ticking it in one place ticks it in the other. See [[Plugins, one by one]].

## Saying lists

When you speak a note, "bullet point" starts a list, "number one" a numbered one, and "check box" or "remember to" a to-do. "Done task" writes one already ticked, and "option" a choice. See [[Speaking your notes]].

See also: [[Boards, tables and live queries]], [[Notebooks and journals]], [[Simple and Advanced]], [[Links, tags and footnotes]]
