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

A dash and a space start a bullet list, and a number, a dot and a space start a numbered one. Press Enter and the next line carries on the list. Press Enter on an empty item to end the list. Backspace takes a marker off whole. Indent an item to put it under the one above.

You can also start one from the **+** beside an empty line: **A bulleted list** or **A numbered list** (under **More** in Advanced). Press and hold an item for **Move up**, **Move down** and **Duplicate**.

## To-dos

A dash, a box, and the thing to do:

```
- [ ] Book the cabin
- [x] Pick a date
```

Tap the box to tick it, or type an `x` between the brackets. The **+** beside an empty line has **A to-do**, and, under **More**, **A to-do with a due date**, which starts one due tomorrow.

### Where your to-dos gather

- **In Simple,** the **To-dos** tab, beside **Notes**, collects every open to-do from every note: **Overdue**, **Today**, **Later** and **Someday** (no due date). Tick one there and it's ticked in its note; it waits a moment, then moves to a **Done** list at the foot, where a tap on its tick unticks it. That Done list only holds what you ticked there since you opened the tab. Tap a to-do's words to open its note at that line.
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
| `🔁 every week` | It repeats, in your words |
| `[effort:: 3]` | Any field of your own |

In a note each one is a chip. A date reads "Today", "Tomorrow", "Yesterday" or a short date, turns amber on the day and red once it has passed, and goes quiet once the to-do is ticked. A person shows their initial in a ring. With the **Contacts** plugin on (it's in the Market), a person matched to one of your phone's contacts shows their picture, and a tap on them opens their card: **Call**, **Text**, **Email**, **Open in Contacts** and **Remove**. Tap any other chip to change it.

Ghost.md reads the other Obsidian Tasks signs too (`✅` done, `➕` created, `❌` cancelled) and keeps them where they are. A repeat is shown and kept, but ticking a repeating to-do doesn't make the next one for you.

You don't have to type the signs. Press and hold a to-do (or any list item) and choose:

- **Due date:** **Today**, **Tomorrow**, **Next week** (that week's Monday), **Pick a date**, or **Remove**.
- **Priority:** one of the five, or **None**.
- **Assign:** someone the note already names, **Someone new**, or **A person** from your contacts where the Contacts plugin is on. **Remove** takes someone off.
- **Remind me** and **Remind me at a place**, where reminders are on. See [[Reminders and notifications]].

The signs are always written at the end of the line, in the order Obsidian Tasks reads them, so the to-do still works there.

## Lines that count

**Choices.** Round brackets make a choice. Tap one to pick it and clear the others in the group.

```
Where do we stay?
- ( ) Tent
- (x) Cabin
- ( ) Hotel
```

**Counters.** A count and a goal in square brackets: `- Water [3/8]`. Tap to add one, press and hold to take one away.

**Sums.** A line that starts with `= ` shows its answer after it: `= $450 + 120 * 2` shows `→ $690`. The answer is never written into the note, so it changes when a number does. Use `+`, `-`, `*`, `/`, `^` for powers, `%` after a number for a percent, and brackets. A currency sign or thousands commas come back on the answer, and a line it can't work out shows nothing. A sum can sit in a list item too: `- = $1,200 / 3`.

**Progress.** A heading with to-dos under it counts them: "1 of 2", then "All 2 done". It counts down to the next heading of the same level, so a `##` counts the `###` sections under it too. There's nothing to type.

**A choice**, **A counter** and **A sum** are under **More** on the **+** beside an empty line, if you'd rather not type them.

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

Ghost.md draws the fields as a panel at the top of the note, headed by the ticket's key: **Status**, **Assignee**, **Priority** and **Due** always, and **Start**, **Estimate**, **Blocked by**, **Parent** and **Labels** once they're set. The faint **+** line under the panel names the ones not set yet; tap it to show them all.

- **Tap a value to change it.** A status opens its list, each with a coloured dot. A person and a priority open a picker, and a day opens your device's calendar. The cross beside a day takes it off.
- **Estimate** and **Labels** are typed straight into the panel. Separate labels with commas.
- **Blocked by** and **Parent** ask you to **Find a ticket**, by its key or its title. A ticket waiting on one that isn't done says so at the top, with a lock.
- **Show the properties as text** puts the caret in the lines themselves. Any other lines you add there are listed quietly under the panel.

Every change is one edit in the front matter, so Undo takes it back.

The usual statuses are Backlog, To do, In progress, In review and Done. A due date that has passed turns red until the ticket is done.

### Making a ticket

- **From a template.** On a blank note, choose **Bug report** or **Feature**.
- **From a note you're in.** On the **+** beside an empty line, choose **Make this a ticket** (under More). It writes `type: ticket` and `status: To do`.
- **From a ticket notebook,** with **New ticket**. See below.
- **From a board of tickets.** A ticket query drawn as a board has a **+** on its lanes, and a ticket made there starts in that lane. See [[Boards, tables and live queries]].

### Ticket notebooks and keys

A notebook can number its tickets, the way a Jira project does. Open the notebook's More sheet (the three dots, **More for this note**) and type its **Ticket key**, such as `GHO`. Then:

- Its index offers **New ticket**, which makes the next one: GHO-1, GHO-2 and on.
- A ticket in that notebook with no number yet offers **Give it GHO-13**.
- A ticket made elsewhere with the notebook's key, such as a Bug report or one Claude wrote, still counts as that notebook's.
- A notebook can set its own statuses with a line like `statuses: [Backlog, To do, Doing, Done]` in its front matter. Its tickets then move through those.

The numbers are never stored: the next one is one more than the highest any note uses, the Trash included, so a deleted ticket's number isn't given out again.

```
---
book: true
key: GHO
---
# Ghost.md
- [[Fix the login loop]]
```

Link to a ticket anywhere with its key: `[[GHO-12]]` shows its title after the key and a dot in its status's colour, and is struck through once it's done. A key no ticket has yet is drawn as a link to a note still to be written.

To see tickets across all your notes, as a board, a table or a timeline, use a query. See [[Boards, tables and live queries]].

## Sending items elsewhere

With the Notion or GitHub plugin set up, a note's list items can become Notion tasks or GitHub issues.

1. In the note's More sheet, choose **Notion board** or **GitHub repo** and pick where its items go.
2. Then send an item in any of these ways:
   - Swipe the item left, past the point where the tile says it counts.
   - Press and hold it and choose **Notion** or **GitHub**.
   - Tap the faint **Notion** or **GitHub** after an item not sent yet.
   - Send them all with **Send list to Notion** or **Send list to GitHub** in the More sheet.

A sent item ends with a small mark that shows the task's state. Ticking it in the note marks the task done (or closes the issue), and a task finished in Notion, or an issue closed on GitHub, ticks the box. GitHub needs a token in the plugin's page to send issues. See [[Plugins, one by one]].

## Saying lists

When you speak a note, "bullet point" starts a list, "number one," a numbered one, and "check box" or "remember to" a to-do. "Done task" writes one already ticked, "option" a choice and "picked option" the one chosen, and "calculate" a sum. Saying "due Friday" gives the to-do a due date. See [[Speaking your notes]].

See also: [[Boards, tables and live queries]], [[Notebooks and journals]], [[Reminders and notifications]], [[Simple and Advanced]], [[Links, tags and footnotes]]
