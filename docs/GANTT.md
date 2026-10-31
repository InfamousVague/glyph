# Gantt charts in Markdown

Matt, 2026-10-31: "work on making a better gannt chart implementation in markdown replacing the one we have now
that's quite hard to interact with".

A Gantt chart is a ```` ```gantt ```` fence whose body is a Markdown list. Anywhere that shows the fence as text (GitHub,
Obsidian, a terminal, the share page) it reads as the plan it is; Ghost.md draws it as a chart you drag, and every drag
writes the list back, one line at a time.

````markdown
```gantt
title: Waitlist launch
workdays: true

## Research
- Interview five users [2026-11-02 → 2026-11-04] @matt #research 100%
- Read the competition [2026-11-03 +3d] @sam

## Build
- Design the waitlist [2026-11-05 → 2026-11-11] @matt #design after: Interview five users 60%
- Build the signup page [+4d] after: Design the waitlist
- ◆ Launch [2026-11-20] after: Build the signup page
- [[KLN-12]] after: Design the waitlist
```
````

## The grammar

Read by `lib/core/gantt/format.dart` (and, for the share page, `tauri/src/read/gantt.ts`).

### Front lines

A key, a colon and a value, on a line of its own, outside any task. All are optional.

| Line | Means |
| --- | --- |
| `title: Waitlist launch` | The chart's name, over it. |
| `start: 2026-11-02` | Where a task with no days of its own, and nothing to wait on, starts. Today where unsaid. |
| `zoom: week` / `month` / `quarter` | How wide a day opens: a column a day, Mondays dated, or months named. Unsaid, as wide as fits the bars. |
| `workdays: true` | Lengths count Monday to Friday, a task that waits starts on the next working day, a bar carried onto a weekend goes on to the Monday, and the weekends are shaded. |
| `today: 2026-11-04` | The day the chart takes for today (for a plan looked at as of a day). The device's today where unsaid. |
| `follow: false` | Moving a task leaves what waits on it where it is. `true`, the default, pushes it along. |
| `colour: person` | Bars coloured by their first person rather than by their section. |

### Sections

A heading (`## Build`, any level) or a name and a colon alone on a line (`Build:`). Tasks above every section are a
section with no name. A front key can't be a `Name:` section (`Start:` is the `start:` line): write `## Start`.

### Tasks

A list item (`-`, `*`, `+` or `1.`): its name, then its marks, each its own, in any order. The first mark ends the
name, so a name can't hold `@`, `#`, `[`, `after:` or `60%` as words.

| Mark | Example | Means |
| --- | --- | --- |
| Days | `[2026-11-02 → 2026-11-06]` | First and last day, both in it. `->`, `–`, `—`, `..` and `to` are read as the arrow. |
| | `[2026-11-02 +5d]` | A start and a length: `d`ays or `w`eeks (`+2w`), working days with `workdays: true`. |
| | `[2026-11-02]` | One day, or a milestone's day. |
| | `[+4d]` | A length alone: it starts the (working) day after the last thing it waits on ends. |
| Person | `@matt @sam` | Who does it; the first is who a bar is coloured by with `colour: person`. |
| Tag | `#design` | A tag, kept. |
| Waits on | `after: Research, Read up` | The tasks it starts after, by name, commas between. A ticket answers to its key or title. |
| Colour | `colour: teal` | Its bar's colour: blue, teal, green, amber, purple, red or gray. |
| Progress | `60%` | How far along; `100%` is done, drawn quiet. |
| Milestone | `- ◆ Launch [2026-11-20]` | A diamond on its day. `◇` and `<>` are read as the mark too. |

A task with no days and nothing to wait on is drawn dashed at the chart's start (or today), waiting to be dragged
somewhere; carried, it is given its days.

A name that is a `[[link]]` alone, `- [[KLN-12]]`, is a ticket. With no days of its own its days are the ticket's
`start:` and `due:`, its person the ticket's `assignee:`, and it is done when the ticket is; dragging its bar writes the
ticket's `start:` and `due:` into the ticket's own front matter. Give the line days of its own and they win, and are the
fence's to write.

A waiting loop (A after C, C after B, B after A) can't be drawn: the wait that closes it is left out and said under the
chart. A name that no task has is said too. Every other line (a blank, a sentence, a `%%` comment, a Mermaid `click`) is
kept and drawn as nothing.

## The chart

`lib/editor/gantt/gantt_chart.dart`, drawn in the app's tokens: a section's bars in its glacier hue, a person's in
theirs, every colour the ink in Calm, light and dark.

- Rows are tasks under their sections, the names in a column on the left that stays as the days scroll under it.
- Bars run from the first day to the end of the last, filled as far as they are along; milestones are diamonds.
- An arrow runs from the end of each task to the start of what waits on it; today is a line down the days.
- The days along the top in two rows: months over days, weeks or months, as the zoom has room for.
- Zoom with a pinch, with ctrl or cmd and the wheel (or a trackpad's pinch), with − and +, or Week, Month, Quarter.

### What a hand does

| Gesture | Writes |
| --- | --- |
| Drag a bar | Its days, in the form its line had them (a range stays a range, `+5d` stays a length). What waits on it is pushed along just far enough to start after it, with `follow: true` (the default); its panel says so. |
| Drag a bar's end | One end: a range's day, or a length's count. `[+4d]` keeps its start its waits' while its end is carried. |
| Drag from the round at a bar's end to another bar | The other bar's `after:` names this one, and it is pushed after it. A loop is refused, with why. |
| Click an arrow | That wait taken out of the `after:`. |
| Double-click, or long-press, empty days in a row | A task on that day, under that row's task, its panel open to name it. |
| Click a bar | Its panel: name, days, person, progress, what it waits on, milestone; under More (always open in advanced mode, behind More in simple mode) the chart's follow and working days and the bar's colour. |
| Delete | The task's line, and its name from every `after:`. |
| Enter | A task under the chosen one, the working day after it, as long as it. Enter in a panel's name writes it and closes the panel, so Enter again adds the next: a list is typed a name and an Enter at a time. |
| Drag a row's name | Its line moved, into another section too. |
| ← →, shift ← → | The chosen bar a day earlier or later; its end a day shorter or longer. |
| ↑ ↓, Escape | Choose the task above or below; let go. |
| cmd/ctrl Z, shift cmd Z | The note's undo and redo. |

Each gesture is one change to the fence, written over only the lines it changes, as one step of the note's undo
(`input.gantt`). A ticket's days are the ticket's note's, and undone there.

On a phone: a tap chooses a bar and a second opens its panel as a sheet from the foot; a long press then a drag carries
it; the chosen bar's ends and its round are taken at once; a swipe anywhere else scrolls the days; a row's name is
held, then dragged, to move it.

The pencil in the chart's bar shows the fence's own lines to type, as a query's does.

## Queries: `show: gantt`

A query with `show: gantt` draws this same chart from its rows (`lib/core/gantt/query.dart`,
`lib/editor/queries/query_gantt.dart`): each row from its `start:` field to its `end:` field (`start` and `due` where
unsaid), in the query's groups, a ticket's `blocked-by:` as arrows from what blocks it. Dragging a bar, or its ends,
writes the record's own fields, as a `[[ticket]]` in a fence does. A query's rows aren't lines to write, so adding,
taking out, renaming, waits and row order are the records' own; a query's bars move one at a time (no following).

`show: timeline` (2.3.92's drawn timeline) is read as the same chart. The two were near-identical bar charts of a
query's start and due; this one does everything the timeline did (bars from fields, groups, zoom, carrying an end)
and more, so the timeline's own view is gone and its fences draw the Gantt chart, the switcher showing one Gantt.

## Mermaid gantts

A ```` ```mermaid ```` gantt keeps rendering as it did, with **Convert to interactive Gantt** under it in a note that
can be changed (`lib/core/gantt/mermaid.dart`). It rewrites the block as a ```` ```gantt ```` fence, one undo:

- `title` → `title:`; `section` → `## section`; `excludes weekends` → `workdays: true`; `tickInterval` → the nearest
  `zoom:`; `dateFormat` read to write each day as `2026-11-02`.
- `done` → `100%`; `milestone` → `◆`; `active` and `crit` → `#active` and `#crit`.
- Ids are dropped and every `after id` names the task; a task with no start (which Mermaid starts after the one above)
  gets `after:` that task.
- Mermaid's end date is the day after the bar (unless `inclusiveEndDates`), the fence's is its last day: one is taken
  off. Lengths in days and weeks carry; hours and minutes are rounded to days.

What can't carry is said, and asked about, before anything is written: `axisFormat`, `todayMarker off`, `weekday`,
`displayMode`, `%%{init}%%` directives, single days in `excludes`, `includes`, `until`, `vert` and times of day.
`click` lines and `%%` comments are kept as lines the chart reads as nothing.

## The share page

The share page reader (`tauri/src/read`) draws no diagrams (a Mermaid fence is shown as its code), so a gantt fence is
not drawn as a chart there either: it is read with `tauri/src/read/gantt.ts` and drawn as its list, readably: the
title, each section's name, each task with its days said (`2 Nov – 6 Nov`, `2 Nov, 5 days`), its people, a small bar of
how far along it is, and what it waits on; a milestone with a diamond, a task done struck through.

## Adding one

`A Gantt chart` in the + list's More and in the `/` palette writes a small one: a title, a section, two tasks the
second waiting on the first, and a milestone after them, from today, its title chosen to be written over.
