# Home-screen widgets (Android)

Twelve widgets in the app's own Glacier look, each one entry in the picker and drawn for whatever size the launcher
makes it, from a single cell to four by four and wider on the opened Fold.

- The first four (Matt, 2026-10-20: "make a exact matching UI to the glacier UI we use in Ghost to make a few home
  screen widgets including one to record a voice note, one to show todos and one to show calendar events and one last
  one to show recent notes, available in large and medium widgets"): **Voice note**, **To-dos**, **Calendar**,
  **Recent notes**.
- Eight more (Matt, 2026-10-21: "Please add more widgets and sizes shoot for 12 widgets"): **Quick capture**,
  **Pinned notes**, **Today**, **Search**, **A note**, **A folder**, **Ask AI**, **Next up**.
- And for every one of them (Matt, 2026-10-21: "Make sure they're various sizes I want to have more 2xN and 1x1 also
  make sure they take up 100% of avail space"): a cell (1×1) wherever one makes sense, real columns two cells across
  (2×1 to 2×4), and the widget's ground and what is in it filling the whole of the room the launcher gives.

They replace Quick note, Today and Pinned notes (below). The iPhone's are docs/WIDGETS.md (another branch's); the data
each side reads is the same shape where both have it (below).

## Where a person finds them

Long-press the home screen, Widgets, Ghost.md. Each is placed at the size its entry says and resized from its corners
to any other. Most have the home page's section heading at their top (a mark, a name, a count or the date, and one
round button at its end, the dock's `.round`), and a tap on the heading opens the app; a cell high or a cell each way
puts the heading away and gives the room to what the widget is for.

| widget          | placed at | sizes it is drawn for                                   | no 1×1 because                          |
| --------------- | --------- | ------------------------------------------------------- | --------------------------------------- |
| Voice note      | 4×2       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide          |                                         |
| To-dos          | 4×2       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide          |                                         |
| Calendar        | 4×2       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide          |                                         |
| Recent notes    | 4×2       | 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide (two columns) | a list of notes needs a row's width     |
| Quick capture   | 4×1       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide          |                                         |
| Pinned notes    | 4×2       | 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide (two columns) | as Recent notes                         |
| Today           | 4×2       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide          |                                         |
| Search          | 4×1       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide          |                                         |
| A note          | 2×2       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide          |                                         |
| A folder        | 4×2       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide (two columns) |                                    |
| Ask AI          | 2×2       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide          |                                         |
| Next up         | 2×2       | 1×1, 2×1, 4×1, 2×2 to 2×4, 4×2, 4×3, 4×4, wide (the rest beside it) |                             |

Recent notes and Pinned notes say two cells by one at least (`minResizeWidth` 110dp); a launcher that makes one a
single cell anyway gets the first note's mark and name, a tap from it.

### The first four

- **Voice note**: the dock's one filled ring, Speak, made big. A tap records a voice note at once: `ghostmd://voice`,
  the icon's Voice note, which opens the app straight into the recorder (the dock's own recorder, not Talk to Claude,
  whatever the dock's microphone is set to); the microphone opens on that tap and never before. Beside the ring, the
  last recording: its name, its length and when ("Standup", "4:12 · 20 min ago"), a tap from its note. Large: "Tap to
  record" beside the ring, and under it the last three recordings as the home page's rows. The round button is a new
  note to type in. A cell: the ring alone, "Record" under it. A cell high: the ring at the dock's own size beside the
  last recording. A column: the ring in the middle of it, as big as the column and its height leave (to 136dp), its
  words under it; three cells high or more, the recordings' names under that.
- **To-dos**: the open to-dos from every note in the To-dos view's groups, **Overdue**, **Today**, **Later** and
  **Someday** (its words: lib/simple/todos_groups.dart), each group an eyebrow with its count. A row is the To-dos
  view's: the round tick (red where overdue), the words, and under them the due day's chip as a note's line draws it
  (red once passed, amber on the day, the second ink after; "Yesterday", "Today", "Friday", "3 days ago") and the note
  it is in ("Ticket" for a ticket). **The tick ticks the to-do without opening the app** (below); a tap on the words
  opens the note at that line. The round button is a new note. A cell: how many are open, and under it how many are
  overdue, in the red. A cell high: the first group's first one. A column: the words over two lines where they need
  them, the chip under them without the note's name, the rows as tall as their words make them.
- **Calendar**: from today, each day that has anything (Today, Tomorrow, then the weekday): its events (the time and
  until when, or All day; a ring; the title; the calendar and the place) beside the to-dos due that day (a dot, red
  and its day said where overdue), as the app's calendar of to-dos shows events beside to-dos. Today's take the overdue
  to-dos too. An event that has ended goes. The heading says today's date. With the Calendar plugin off: "Turn on
  Calendar in Ghost.md", Settings › Plugins › Calendar. A tap on an event opens the app; on a to-do, its note. A cell:
  the day's number as a desk calendar's page, and the weekday with how many things are on it. A cell high: the next
  ones, no days' eyebrows. A column: the date alone heads it ("Oct 21"), and each row puts when under the words.
- **Recent notes**: the notes written in last as the home page's rows: the kind's mark (a page, a cassette, a
  notebook, a canvas), the name, how it starts (a tape's length first), and when ("20 min ago", "Yesterday",
  "Tuesday", "October 3", lib/notes/when.dart's words). Large and wide (420dp and more: the Fold opened), two columns.
  A tap opens the note where it was left; the round button is a new note. A column: "Recent" heads it, and each row
  drops its when for the name's room.

### The eight more

- **Quick capture**: the dock's round buttons for what the app makes from outside it: **Note** (`ghostmd://new`),
  **Voice note** (the filled Speak, `ghostmd://voice`), **Checklist** (`ghostmd://checklist`: a new note from the
  built-in "A checklist", as its card on a new note's blank page makes one: the caret in its name, a to-do under it,
  taken back if it is left without a word), **Scan** (`ghostmd://scan`, the icon's Scan document: Google's scanner
  into a new note's PDF; nothing on a phone without it), and with room **Today** and **Search**. A cell: the pen alone.
  A cell high: as many rings as the width holds (two at 2×1, five at 4×1). A column: the rings stacked, each with its
  word, sharing the height. Four by two: a row of four with their words (six, wide). Large: the + sheet's rows, each
  with what it makes in the + sheet's words. No heading button of its own: its buttons are the widget. There is no
  "photo": the app has no photo-to-new-note; Scan is the camera's way in.
- **Pinned notes**: the notes pinned to the top, in Recent notes' rows and sizes, the one written in last first.
  "Nothing pinned" where there are none.
- **Today**: today's note (lib/notes/daily_notes.dart: the note named by the day, which the + sheet's Today and the
  icon's Today's note open or make, in the folder and from the template Settings › Daily notes says), its first lines
  after its name as the note says them (A note's lines, below), its to-dos ticked in place. The heading's round button
  is the pen, `ghostmd://today`, which opens it, or makes it the first time. Before it is written: "Nothing written
  today", a tap that starts it. The day is the phone's: the note the app handed over yesterday is not today's once
  midnight has come. A cell: the day's number, the weekday, and a dot before it once today's note has words. A cell
  high: the pen's ring, the day, and how the note starts.
- **Search**: the home page's search field, a pill with the dock's magnifier and "Search notes", which opens the palette
  (`ghostmd://search`). The field is its heading. Under it, "Recent" and the notes written in last (the app keeps no
  recent searches): their names, or as the home page's rows where it is large. A cell: the magnifier's ring. A cell
  high: the field alone.
- **A note**: one note, chosen as the widget is placed (below): its kind's mark and name as the heading, the pen at its
  end (the note, where it was left), and under it its first lines as the note says them: words over two lines at most,
  a heading in a row's weight, a list's bullet and its depth, a quote with its bar, a to-do with the To-dos view's round
  tick, which **ticks it without opening the app**, as To-dos' does, and a ticked one in the third ink with its disc.
  Front matter, fenced blocks (a board, code, comments), pictures alone on their line, tables and rules are left out.
  A tap on a line opens the note at it. A cell: its mark's ring and its name. A cell high: its row (its name, how it
  starts, when). **Deleted or in the Trash**: "This note was deleted", and a tap chooses another. Chosen while the app
  was closed and not yet handed over: its name, and "Its lines show once Ghost.md has opened".
- **A folder**: one workspace or folder, chosen as the widget is placed, an organization's among them ("Acme ›
  Design", lib/core/workspaces.dart `workspacePathName`, as the app lists them): its name with its parents' as the
  heading, how many notes are in it and in the folders under it, and those notes in Recent notes' rows and sizes, the
  one written in last first (as choosing it on the home page shows them). Its round button is **+, a new note filed
  there** (`ghostmd://new?into=<workspace>`: the folder browser's New note, lib/root/root_commands.dart `_new(into)`,
  which files a new note in the level shown; an organization's folder's note is the team's by that filing). A cell:
  the + with the folder's name. Gone: "This folder is gone", a tap chooses another.
- **Ask AI** (its name in the picker; inside, the app's own words, Claude): Talk to Claude, the dock's plain ring with
  its rim and its mic in Claude's orange (lib/claude/claude_dock.dart `ClaudeTalkButton`), `ghostmd://talk`, which
  opens the ear as the dock's does (nothing listens before the tap); and the chat, Claude's orange disc with its mark
  in ivory at the heading's end, `ghostmd://chat`. Only where the app shows them, as the dock does: the Claude plugin on
  and an API key on this device (lib/root/ghost_root.dart `_claudeShown`). Otherwise "Turn on Claude in Ghost.md" or
  "Add your Claude API key", Settings › Plugins › Claude, and a tap opens that page (the links open it too, where
  Claude is not shown when they arrive). A ring with nothing to hear (the recorder holds the microphone) opens the
  chat instead. A cell: the ring alone, "Talk". A column: the ring as big as it has room for. Large: the ring as big as
  the room above the chat's row.
- **Next up**: the one next thing (HomeData.nextUp): today's timed event on now or next, else the to-do most overdue,
  then today's; then the rest of today, and today's all-day events last. The thing is an eyebrow of when ("Now", "In
  25 min", "In 2 hr 10 min"; red "Overdue · 3 days", amber "Due today"), its words large over two lines, and under them
  its time and calendar or the note a to-do is in; a tap opens the app, or a to-do's note at its line. Then, with
  room, "Then" and the rest (beside it, wide). A cell: the time it starts ("Now" once on), or with no event how many
  to-dos are due by today, red where any is overdue; "All clear" with nothing. A cell high: the eyebrow and the words
  on one line. Its own alarm draws it again as its event starts and as it ends (non-waking, within a minute), so "In
  5 min" becomes "Now" and the next thing takes its place when they happen; the minutes between are the quarter-hour
  clock's.

### Choosing what A note and A folder show

Placing either opens the widget's configuration (home/WidgetPick.kt, `APPWIDGET_CONFIGURE`): a plain page in the
widgets' look and the app's theme, "Choose a note" with a field to find one by its name over the notes as the home
page's rows (the pinned first, then the ones written in last, 200 of them: `picks`), or "Choose a folder" over every
workspace and folder by its path. A tap keeps the choice for that widget and closes; leaving it takes the new widget
away, as Android does. From Android 12 the widget's Reconfigure (`reconfigurable`) opens it again, and a gone note's or
folder's widget opens it on a tap. Where the app runs, choosing calls it (`chosen` on the channel) and the note's lines
are handed over at once; where it does not, at its next pass, and the widget shows the note's name until then.

## Sizes, and filling the room

The size a widget is drawn at is the launcher's room for it (HomeData.Fit, held by HomeDataTest), measured on the
Pixel launcher at 420dpi (a cell 75dp across and 82dp high; two cells 159 by 181; four 330 by 380):

| fit     | when                                           | e.g.            |
| ------- | ---------------------------------------------- | --------------- |
| TINY    | under 120dp each way                           | 1×1             |
| SLIM    | under 120dp high, wider                        | 2×1, 4×1        |
| NARROW  | 120dp high or more, under 215dp across         | 1×N, 2×2 to 2×4 |
| MEDIUM  | 215dp across or more, under 230dp high         | 3×2, 4×2        |
| LARGE   | 215dp across or more, 230dp high or more       | 4×3, 4×4        |
| (wide)  | LARGE and 420dp across or more                 | the Fold opened |

From Android 12 the launcher says each size the widget is drawn at (upright and on its side) and a view is made for
each (`RemoteViews(Map<SizeF, RemoteViews>)`), so it turns and resizes with nothing asked of the app; before 12, the size
it says for this orientation.

**Filling the room**: every widget's root is the frame (layout/ghost_w_frame.xml), `match_parent` both ways with the
page as its ground and, from Android 12, the launcher's own corners (`system_app_widget_background_radius`), so the
ground is the whole of what the launcher gives, edge to edge (the gaps between widgets are the launcher's grid). Its
columns are the body's whole height, so what is in them is placed in it: lists take as many rows as fit (a row's
height read at the phone's text size, a column's to-do and a note's lines as tall as their words wrap), a microphone's
ring grows with its room (`setViewLayoutWidth`, Android 12), Quick capture's rings share the width and its stack the
height, and one thing alone (Next up's, a microphone) sits in the middle of the room rather than at its top. What is
left under a list is less than a row. A heading's padding is the frame's only inset.

**One entry each in the picker**, as before: a launcher resizes a widget in place, and twelve things in five sizes
would be sixty entries.

## How the Glacier look is matched

- **Colours** come from the stylesheets themselves: tool/widget_look.dart resolves each with the app's own token engine
  (lib/app/token_sheet.g.dart, `Tokens.root`) in the paper look and the dark one, and writes them as ARGB to
  `res/values/ghost_widget_tokens.xml` (`ghost_w_light_*`, `ghost_w_dark_*`), each with the CSS it came from:
  the page (`--glacier-bg`), a card's hairline (`--glacier-border-subtle`), the four inks (`--app-ink` to
  `--app-ink-4`), the ring's edge (`--glacier-border-strong`), what is drawn on the ink (`--app-paper`), the reds and
  amber of a due chip and their washes (`color-mix(...)` as field_chips.dart mixes them), the pressed wash (6% of the
  ink). Claude's orange and ivory are lib/claude/claude_mark.dart's, the same in both looks (`ghost_w_claude`,
  `ghost_w_claude_ivory`). test/home_screen/widget_look_test.dart fails when a stylesheet changes and the files do not;
  `GHOST_WRITE=1 flutter test test/home_screen/widget_look_test.dart` writes them again.
- **Light and dark follow the app's theme**, as the app is drawn: Dark (the app's own default) on a phone that is
  light, Light where the app is set to Light, and the phone's mode where it is set to System; a named theme (Dawn,
  Boreal, Ember) by its side, in the plain greys. Every layout and drawable names its colours as attributes
  (`?attr/ghost_w_ink`), and the frame's root carries the look as a theme (layout/ghost_w_frame_dark.xml, `_light`,
  `_system`: `android:theme="@style/GhostW.Theme.Dark"` around the shared frame), which the rows added to it inherit;
  GhostW.Theme.System is Light in values and Dark in values-night. The app hands its theme's side over as `look`.
  WidgetPick lays the same attributes over a plain Material window.
- **Lengths and type sizes** are the tokens' too, a CSS pixel as a dp and a type size as an sp (so the phone's text
  size still applies), resolved at 412 CSS pixels across (the Fold's cover screen): `--glacier-space-*`,
  `--glacier-radius-sm/md/lg`, `--app-ring`, `--glacier-font-size-xs` to `xl`, and the due chip's 0.92em, 0.35em and
  0.95em. The ground's corners are the launcher's own from Android 12, the card's `radius-lg` before.
- **The face is the phone's own sans, not Inter**: a launcher draws a widget from a restricted context of the app's,
  and TextView loads no font resource there (`Context.canLoadUnsafeResources`), so an Inter put in res/font comes out
  as the phone's sans regardless (tried: a line Inter sets 384px wide drew 357px, Roboto's). The weights are the app's
  for each job (values-v28: `textFontWeight` 400, 500, 600, 700; regular, medium and bold before Android 9). The styles
  (res/values/ghost_widget_styles.xml) are the app's for each job: HomeHeading (sm, semibold, the second ink),
  `.app-eyebrow` (xs, bold, capitals 0.08em apart), HomeRow's name (md semibold), the To-dos view's words (md) and
  line under them (sm, the third ink), when (xs, figures of one width), and a cell's one word (xl semibold).
- **Icons** are the paths the app draws (lib/art/lucide.g.dart and lib/art/icons.dart's own), written by the same tool
  as vector drawables in white with the wash (a third of the ink inside the icon's body, as AppIcon fills it) and
  tinted by their ImageView: the four's, and for the eight the dock's magnifier, the pin, the folder (`workspace`),
  the clock, the note settings' Make a list (`list-checks`) and Summarize (`scan-text`) marks, and Claude's mark
  filled from its path; the few that cannot be tinted (a chip's calendar, the tick's check) in their colour resource.
- **Shapes** are the app's: the dock's filled ring (Speak) and `.round` ring (the page inside the strong border, 1.5
  wide), Talk to Claude's orange-rimmed ring and Claude's orange disc, the To-dos view's tick (a 22 ring, 1.5 wide; 2
  and red where overdue; a disc of the ink with the check once ticked), the field chip, the query calendar's event ring
  and to-do dot, the home page's search pill, a quote's bar.

## The data (lib/home_screen; android/…/ghost_md/home)

The app hands over what each widget draws on `ghost_md/home_screen` (`put {kind, json}`), each only when it is another
than the last, from the reminders' pass a moment after the notes, the Trash, the plugins, the calendars, the
workspaces' filings or Claude's key change (lib/root/phone_extras.dart), and again each time the app comes back to the
front. The phone keeps each in SharedPreferences, so the widgets draw with the app closed. No background service, no
collection service.

| kind        | what                                                                                       | made by (home_data.dart) | drawn by                |
| ----------- | ------------------------------------------------------------------------------------------ | ------------------------ | ----------------------- |
| `todos`     | the open to-dos due by a week on (tickets among them), then 30 with no date                | `homeTodos`              | To-dos, Calendar, Next up |
| `notes`     | the 16 notes touched last (not archived, blank, in the Trash, the Guide's or a template)   | `homeNotes`              | Recent notes, Search    |
| `voice`     | the last three recordings, by when they were made                                          | `homeRecordings`         | Voice note              |
| `calendar`  | whether the Calendar plugin is on, and the events from today to a week on                  | `calendarJson`           | Calendar, Next up       |
| `look`      | the app theme's side: `dark`, `light` or `system`                                          | `lookJson`               | every one               |
| `pins`      | the 16 pinned notes, the one written in last first                                         | `homePins`               | Pinned notes            |
| `daily`     | the day, and that day's note (`dailyNoteOf`) as its row and its first 24 lines             | `dailyJson`              | Today                   |
| `pages`     | the notes the A note widgets show (asked of the phone: `chosen`) as their lines, and those gone | `homePages`         | A note                  |
| `picks`     | the 200 notes A note may be set to, the pinned first                                       | `homePicks`              | WidgetPick, A note      |
| `folders`   | every workspace and folder (80) by its path, with how many notes and its 12 written in last | `homeFolders`           | A folder, WidgetPick    |
| `assistant` | whether the Claude plugin is on and an API key is entered                                  | `assistantJson`          | Ask AI                  |
| `recent`    | the notes opened last, for the icon's shortcuts (as before)                                | `namedNotes`             | the icon                |

A line of a note (`PageLine`) is `{line, kind, words, match?, depth?}`: its number in the note from 1 (front matter
counted, as the tick reads the body), `text`, `heading`, `bullet`, `quote`, `todo` or `done`, its words with the
Markdown's marks off (a link's words for the link), and for a to-do the words its line is found by again to tick it
(tick_item.dart `itemWords`). The other shapes are the shared widget snapshot's (the iPhone's
lib/home_screen/widget_snapshot.dart, `HomeWidgetSnapshot`): a to-do is `{note, line, words, match, title, due?,
priority?}`, a note `{id, title, line, updated, pinned?}` with Android's `kind` and `ms` besides, the calendar
`{calendar, events}` with an all-day event's days (`start`, and `end` the day after its last) and a timed one's UTC
moments. The phone also takes that snapshot whole as `widgets` and keeps it as `todos`, `notes` and `calendar`
(HomeScreen.kt, HomeData.split), so either side's Dart can feed it.

The other way, `chosen`: the app asks the phone which notes its A note widgets show, by id (each widget's kept by
WidgetPick as `chose:<widget id>`, let go when the widget is taken off), and hands `pages` over for them; a note gone
from the library or in the Trash is said in `gone`. Where the app runs, the phone calls `chosen` on it as a widget is
set to another note, and the app's next pass comes at once.

The widgets word days and times themselves (HomeData.kt, held by HomeDataTest): the groups, "Tomorrow", "20 min
ago", "0:40", "In 25 min", "Overdue · 3 days", the phone's own weekday and date. So two alarms of the app's draw them
again with nothing asked of it, neither waking the phone, and only while a widget is placed: midnight (within ten
minutes of it: "Tomorrow" becomes "Today", a to-do overdue, Today's note yesterday's) and about every quarter of an hour
(RTC, inexact: held while the phone sleeps and delivered as it wakes, so "20 min ago" and an ended event are right when
someone looks); and a third for Next up alone, at its event's start or end. A restart, an update and a new zone arm
them again and draw everything.

**Ticking from a widget** (To-dos, A note, Today): from Android 12 the tick is a real CheckBox (RemoteViews' compound
buttons, drawn as the To-dos view's ring); before, a picture to press. Either sends the app's own broadcast
(`.home.WidgetTicks`, not exported), which takes the to-do off To-dos, Calendar and Next up at once, draws it ticked
on A note and Today at once (HomeData.tickedIn), and writes the tick through the app's library
(reminders/GhostBackground.kt: handed to the running app, or with it closed a WorkManager job runs an engine of its
own on lib/reminders/background_tick.dart, the same edit as a tap on the box). The line is found by its number and its
words (tick_item.dart), so a note edited since does not tick the wrong line. A ticked line has nothing to press: the
widget ticks, and untick is the note's.

## The links

Each a `ghostmd://` link the widget's press opens the one activity at (home/Doors.kt), which the app follows
(lib/home_screen/phone_entries.dart). The eight added three, each something the app already did from inside it:
`ghostmd://new?into=<workspace>` (the folder browser's New note), `ghostmd://checklist` (the blank page's "A checklist"
card), `ghostmd://talk` and `ghostmd://chat` (the dock's two Claude rings). The rest are the icon's and the four's:
`new`, `voice`, `today`, `search`, `scan`, `note/<id>?line=&find=`.

## The three it replaced

Quick note (`.home.QuickNoteWidget`), Today (`.home.TodayWidget`) and Pinned notes (`.home.PinnedWidget`) keep their
receivers, so a widget already on a home screen keeps working: each class is now a subclass of the one it became and
draws it at the size it was placed at. Quick note (a new note and a voice note) is **Quick capture** now, Pinned notes
the **Pinned notes** again, and the old Today (the to-dos due) the **To-dos**; the new Today is today's note, another
thing. (In 2.3.12 Quick note drew the Voice note and Pinned notes the Recent notes, for want of anything nearer.) Their
provider xml says `android:widgetFeatures="hide_from_picker"`, so from Android 9 the picker offers only the twelve. The
old midnight alarm, armed to the Today widget, is let go the first time the new clock is armed. The `today` and `pinned`
kinds are no longer handed over; the phone takes them and keeps nothing.

## Files

- Dart: lib/home_screen/home_data.dart (`homeTodos`, `homeNotes`, `homeRecordings`, `calendarJson`, `homePins`,
  `pageLines`, `homePages`, `homePicks`, `dailyJson`, `homeFolders`, `assistantJson`), home_screen_data.dart (the pass),
  home_host.dart (the kinds, `chosen`), phone_entries.dart (the links), lib/root/phone_extras.dart (what the pass is
  given), lib/root/ghost_root.dart (`_PhoneDoor`: the links followed), lib/root/root_commands.dart (`_new`: a new note
  filed in a folder or from a template); test/home_screen/home_data_test.dart, phone_entries_test.dart,
  widget_look_test.dart; tool/widget_look.dart.
- Kotlin (android/app/src/main/kotlin/com/mattssoftware/ghost_md/home): Widgets.kt (the providers, the clocks, the
  tick), WidgetViews.kt (the frame, the sizes, the four), MoreWidgetViews.kt (the eight), WidgetPick.kt (choosing a
  note or a folder), HomeData.kt (reading and wording, the sizes, Next up; pure), HomeScreen.kt (the channel, the kept
  data, the choices, the alarms, the shortcuts), Doors.kt (the links); android/app/src/test/…/home/HomeDataTest.kt;
  android/app/src/debug/…/home/WidgetGallery.kt (debug builds only: every size of a widget side by side, for the
  pictures).
- Resources: layout/ghost_w_*.xml (the frame, the tile, the rows, the capture cells, the field, the lines, the
  previews, the configuration), layout-v31/ghost_w_todo_row*.xml and ghost_w_check_row.xml (the box),
  drawable/ghost_w_*.xml, drawable-nodpi/ghost_w_preview_*.webp (the picker's pictures before Android 12),
  values(-night)/ghost_widget_tokens.xml (made), values(-v28)/ghost_widget_styles.xml, values/ghost_home_screen.xml
  (the words), xml/ghost_widget_{voice,todos,calendar,notes,quick,pins,daily,search,note,folder,ask,next}.xml and the
  three old ones.
- Manifest: the twelve receivers (exported, as a provider must be), `.home.WidgetPick` (exported for the launcher),
  `.home.WidgetClock` and `.home.WidgetTicks` (not exported), and the old three.

## Pictures (docs/widgets/android)

From the `ghostflutter2` emulator (Android 16, 1248x1972, Pixel launcher). `sizes-<widget>-<look>.webp` is every size of
a widget side by side, drawn by WidgetGallery (debug builds) exactly as the launcher is handed them, at the dp the
Pixel launcher gives each (left: 1×1 74×82, 2×1 159×82, 4×1 329×82, 2×2 159×181, 4×2 329×181, 2×3 159×280, wide
414×280; right: 2×4 159×379, 4×4 329×379; the display at 336dpi so they fit), with made-up notes, events and
recordings written into the widgets' kept data: all twelve dark (and A note gone, `sizes-notegone-dark`, and Ask AI
with Claude off, `sizes-askoff-dark`), and To-dos, Quick capture, Today, A note, Ask AI and Next up light too. From
the launcher itself at 420dpi: `launcher-placed-dark` (Quick capture at 2×1, To-dos, A note set to a real note through
WidgetPick and its lines handed over at once by the running app, Pinned notes), `launcher-note-ticked-dark` (a to-do
ticked on A note, drawn ticked at once), `launcher-note-deleted-dark` (A note whose note is not in the library, after
the app's pass), `pick-note-dark` (the configuration). The pictures of the four from 2.3.12 stay: todos-*, calendar-*,
notes-*, voice-*, picker-dark, legacy-three-dark, wide-tablet-dark, voice-ring-opens-recorder.

Proven there: the twelve in the picker with their previews; placing A note opened the configuration and drew the
chosen note; the tick drew the line ticked at once; the app's pass said a note gone and the widget said so; choosing
again while the app ran handed the note's lines over at once; every widget's ground filled the launcher's bounds for
it, its corners the launcher's.

## Not done

- Inter (above): the phone's sans in its place.
- A named theme's tint (Dawn, Boreal, Ember) is not drawn, only its side; nor the app's own text size setting (the
  phone's is).
- A calendar's own colour: the app draws every event in its ink (a ring), with no colour per calendar, and so do the
  widgets.
- An event opens the app's home page: there is no page of an event to open.
- No recent searches under Search: the app keeps none; the notes written in last instead.
- No photo button on Quick capture: the app has no photo-to-new-note flow (a picture goes into a note from inside
  it); Scan document is the camera's way in. Quick capture's 1×1 is the pen, not a choice of the person's: choosing
  would be a configuration screen for one button.
- A folder's heading opens the app's home page, not the folder: there is no link to a folder.
- Next up's "In 25 min" is worded when drawn: between its start and end alarms the quarter-hour clock keeps it within
  about fifteen minutes.
- A journal's entry: Today is today's daily note (one a day), not a journal's entries; the + sheet's "Entry in …" has
  no link of its own.
- The pictures before Android 12 (`previewImage`) are the widgets drawn by WidgetGallery at the size each is placed
  at, not the preview layouts themselves.
