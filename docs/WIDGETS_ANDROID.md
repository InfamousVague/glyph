# Home-screen widgets (Android)

Four widgets in the app's own Glacier look, each made medium (four cells by two) and resized to large (four by four)
or anything between: **Voice note**, **To-dos**, **Calendar** and **Recent notes** (Matt, 2026-10-20: "make a exact
matching UI to the glacier UI we use in Ghost to make a few home screen widgets including one to record a voice note,
one to show todos and one to show calendar events and one last one to show recent notes, available in large and medium
widgets"). They replace Quick note, Today and Pinned notes. The iPhone's are docs/WIDGETS.md (another branch's); the
data each side reads is the same shape (below).

## Where a person finds them

Long-press the home screen, Widgets, Ghost.md. Each opens at four by two; drag its corner to make it taller (large) or
wider. Every widget has the home page's section heading at its top (a mark, its name, a count or the date, and one round
button at its end, the dock's `.round`) and a tap on the heading opens the app.

- **Voice note**: the dock's one filled ring, Speak, made big. A tap records a voice note at once: `ghostmd://voice`,
  the icon's Voice note, which opens the app straight into the recorder (the dock's own recorder, not Talk to Claude,
  whatever the dock's microphone is set to); the microphone opens on that tap and never before. Beside the ring, the
  last recording: its name, its length and when ("Standup", "4:12 · 20 min ago"), a tap from its note. Large: "Tap to
  record" beside the ring, and under it the last three recordings as the home page's rows (the cassette, the name, the
  length and how it starts, when). The round button is a new note to type in.
- **To-dos**: the open to-dos from every note in the To-dos view's groups, **Overdue**, **Today**, **Later** and
  **Someday** (its words: lib/simple/todos_groups.dart), each group an eyebrow with its count. A row is the To-dos
  view's: the round tick (red where overdue), the words, and under them the due day's chip as a note's line draws it
  (red once passed, amber on the day, the second ink after; "Yesterday", "Today", "Friday", "3 days ago") and the note
  it is in ("Ticket" for a ticket). **The tick ticks the to-do without opening the app** (below); a tap on the words
  opens the note at that line. The round button is a new note.
- **Calendar**: from today, each day that has anything (Today, Tomorrow, then the weekday): its events (the time and
  until when, or All day; a ring; the title; the calendar and the place) beside the to-dos due that day (a dot, red
  and its day said where overdue), as the app's calendar of to-dos shows events beside to-dos. Today's take the overdue
  to-dos too. An event that has ended goes. The heading says today's date. With the Calendar plugin off: "Turn on
  Calendar in Ghost.md", Settings › Plugins › Calendar. A tap on an event opens the app; on a to-do, its note.
- **Recent notes**: the notes written in last as the home page's rows: the kind's mark (a page, a cassette, a
  notebook, a canvas), the name, how it starts (a tape's length first), and when ("20 min ago", "Yesterday",
  "Tuesday", "October 3", lib/notes/when.dart's words). Large and wide (420dp and more: the Fold opened), two columns.
  A tap opens the note where it was left; the round button is a new note.

Each shows as many rows as its height holds (Recent notes says "3 more" under them; To-dos' heading counts them all
and Calendar's eyebrows count each day's). A widget a cell high (a Quick note, Today or Pinned placed before the four)
puts its heading away and shows what fits: the microphone at the dock's own size, or one row.

## How the Glacier look is matched

- **Colours** come from the stylesheets themselves: tool/widget_look.dart resolves each with the app's own token engine
  (lib/app/token_sheet.g.dart, `Tokens.root`) in the paper look and the dark one, and writes them as ARGB to
  `res/values/ghost_widget_tokens.xml` (`ghost_w_light_*`, `ghost_w_dark_*`), each with the CSS it came from:
  the page (`--glacier-bg`), a card's hairline (`--glacier-border-subtle`), the four inks (`--app-ink` to
  `--app-ink-4`), the ring's edge (`--glacier-border-strong`), what is drawn on the ink (`--app-paper`), the reds and
  amber of a due chip and their washes (`color-mix(...)` as field_chips.dart mixes them), the pressed wash (6% of the
  ink). test/home_screen/widget_look_test.dart fails when a stylesheet changes and the files do not; `GHOST_WRITE=1
  flutter test test/home_screen/widget_look_test.dart` writes them again.
- **Light and dark follow the app's theme**, as the app is drawn: Dark (the app's own default) on a phone that is
  light, Light where the app is set to Light, and the phone's mode where it is set to System; a named theme (Dawn,
  Boreal, Ember) by its side, in the plain greys. Every layout and drawable names its colours as attributes
  (`?attr/ghost_w_ink`), and the frame's root carries the look as a theme (layout/ghost_w_frame_dark.xml, `_light`,
  `_system`: `android:theme="@style/GhostW.Theme.Dark"` around the shared frame), which the rows added to it inherit;
  GhostW.Theme.System is Light in values and Dark in values-night. The app hands its theme's side over as `look`.
- **Lengths and type sizes** are the tokens' too, a CSS pixel as a dp and a type size as an sp (so the phone's text
  size still applies), resolved at 412 CSS pixels across (the Fold's cover screen): `--glacier-space-*`,
  `--glacier-radius-sm/md/lg`, `--app-ring`, `--glacier-font-size-xs` to `xl`, and the due chip's 0.92em, 0.35em and
  0.95em. The ground's corners are the launcher's own from Android 12 (`system_app_widget_background_radius`), the
  card's `radius-lg` before.
- **The face is the phone's own sans, not Inter**: a launcher draws a widget from a restricted context of the app's,
  and TextView loads no font resource there (`Context.canLoadUnsafeResources`), so an Inter put in res/font comes out
  as the phone's sans regardless (tried: a line Inter sets 384px wide drew 357px, Roboto's). The weights are the app's
  for each job (values-v28: `textFontWeight` 400, 500, 600, 700; regular, medium and bold before Android 9). Drawing
  the words as pictures would carry Inter but lose the phone's text size, TalkBack and crispness; not done. The styles
  (res/values/ghost_widget_styles.xml) are the app's for each job: HomeHeading (sm, semibold, the second ink),
  `.app-eyebrow` (xs, bold, capitals 0.08em apart), HomeRow's name (md semibold), the To-dos view's words (md) and
  line under them (sm, the third ink), when (xs, figures of one width).
- **Icons** are the paths the app draws (lib/art/lucide.g.dart and lib/art/icons.dart's own: the cassette, the pin),
  written by the same tool as vector drawables in white with the wash (a third of the ink inside the icon's body, as
  AppIcon fills it) and tinted by their ImageView; the few that cannot be tinted (a chip's calendar, the tick's check)
  are written in their colour resource.
- **Shapes** are the app's: the dock's filled ring (Speak) and `.round` ring (the page inside the strong border, 1.5
  wide), the To-dos view's tick (a 22 ring, 1.5 wide; 2 and red where overdue; a disc of the ink with the check once
  ticked), the field chip, the query calendar's event ring and to-do dot.

## The data (lib/home_screen; android/…/ghost_md/home)

The app hands over what each widget draws on `ghost_md/home_screen` (`put {kind, json}`), each only when it is another
than the last, from the reminders' pass a moment after the notes, the Trash, the plugins or the calendars change
(lib/root/phone_extras.dart), and again each time the app comes back to the front. The phone keeps each in
SharedPreferences, so the widgets draw with the app closed. No background service, no collection service.

| kind       | what                                                                                      | made by (home_data.dart) |
| ---------- | ----------------------------------------------------------------------------------------- | ------------------------ |
| `todos`    | the open to-dos due by a week on (tickets among them), then 30 with no date               | `widgetTodos`            |
| `notes`    | the 16 notes touched last (not archived, blank, in the Trash, the Guide's or a template)  | `widgetNotes`            |
| `voice`    | the last three recordings, by when they were made                                         | `widgetRecordings`       |
| `calendar` | whether the Calendar plugin is on, and the events from today to a week on                 | `calendarJson`           |
| `look`     | the app theme's side: `dark`, `light` or `system`                                         | `lookJson`               |
| `recent`   | the notes opened last, for the icon's shortcuts (as before)                               | `namedNotes`             |

The shapes are the shared widget snapshot's (the iPhone's lib/home_screen/widget_snapshot.dart, `HomeWidgetSnapshot`):
a to-do is `{note, line, words, match, title, due?, priority?}` (`words` what it says, `match` what its line is found
by to tick it), a note `{id, title, line, updated, pinned?}` with Android's `kind` and `ms` besides, the calendar
`{calendar, events}` with an all-day event's days (`start`, and `end` the day after its last) and a timed one's UTC
moments. The phone also takes that snapshot whole as `widgets` and keeps it as `todos`, `notes` and `calendar`
(HomeScreen.kt, HomeData.split), so either side's Dart can feed it; the recordings and the look stay their own.

The widgets word days and times themselves (HomeData.kt, held by HomeDataTest): the groups, "Tomorrow", "20 min
ago", "0:40", the phone's own weekday and date. So two alarms of the app's draw them again with nothing asked of it,
neither waking the phone, and only while a widget is placed: midnight (within ten minutes of it: "Tomorrow" becomes
"Today" and a to-do overdue) and about every quarter of an hour (RTC, inexact: held while the phone sleeps and delivered
as it wakes, so "20 min ago" and an ended event are right when someone looks). A restart, an update and a new zone arm
both again and draw everything.

**Ticking from the widget**: from Android 12 the tick is a real CheckBox (RemoteViews' compound buttons, drawn as the
To-dos view's ring); before, a picture to press. Either sends the app's own broadcast (`.home.WidgetTicks`, not
exported), which takes the to-do off the To-dos and Calendar widgets at once and writes the tick through the app's
library (reminders/GhostBackground.kt: handed to the running app, or with it closed a WorkManager job runs an engine of
its own on lib/reminders/background_tick.dart, the same edit as a tap on the box). The line is found by its number and
its words (tick_item.dart), so a note edited since does not tick the wrong line. A to-do with no date ticks the same
way.

**Sizes**: from Android 12 the launcher says each size the widget is drawn at (upright and on its side) and a view is
made for each (`RemoteViews(Map<SizeF, RemoteViews>)`), so it turns and resizes with nothing asked of the app; before
12, the size it says for this orientation. One provider for each widget rather than a medium and a large entry: a
launcher resizes a widget in place, and eight entries for four things would crowd the picker.

## The three it replaced

Quick note (`.home.QuickNoteWidget`), Today (`.home.TodayWidget`) and Pinned notes (`.home.PinnedWidget`) keep their
receivers, so a widget already on a home screen keeps working: each class is now a subclass of the one it became and
draws it (Quick note the Voice note, Today the To-dos, Pinned notes the Recent notes) at the size it was placed at, with
the new name. Their provider xml says `android:widgetFeatures="hide_from_picker"`, so from Android 9 the picker offers
only the four (Android 8 shows the old three too, drawn as the new ones). The old midnight alarm, armed to the Today
widget, is let go the first time the new clock is armed. The `today` and `pinned` kinds are no longer handed over; the
phone takes them and keeps nothing.

## Files

- Dart: lib/home_screen/home_data.dart (`widgetTodos`, `widgetNotes`, `widgetRecordings`, `calendarJson`),
  home_screen_data.dart (the pass), home_host.dart (the kinds), lib/root/phone_extras.dart (the calendars' events and
  the plugin's switch); test/home_screen/home_data_test.dart, widget_look_test.dart; tool/widget_look.dart.
- Kotlin (android/app/src/main/kotlin/com/mattssoftware/ghost_md/home): Widgets.kt (the providers, the clock, the
  tick), WidgetViews.kt (the drawing), HomeData.kt (reading and wording, pure), HomeScreen.kt (the channel, the kept
  data, the alarms, the shortcuts); android/app/src/test/…/home/HomeDataTest.kt.
- Resources: layout/ghost_w_*.xml (the frame, the rows, the previews), layout-v31/ghost_w_todo_row.xml (the box),
  drawable/ghost_w_*.xml, values(-night)/ghost_widget_tokens.xml (made), values(-v28)/ghost_widget_styles.xml,
  xml/ghost_widget_{voice,todos,calendar,notes}.xml and the three old ones.
- Manifest: receivers `.home.VoiceNoteWidget`, `.home.TodosWidget`, `.home.CalendarWidget`,
  `.home.RecentNotesWidget` (exported, as a provider must be), `.home.WidgetClock` (not exported), and the old three.

## Pictures (docs/widgets/android)

From the `ghostflutter2` emulator (Android 16, 1248x1972 at 420dpi, Pixel launcher), the app's real notes and, for the
calendar and the recordings, made-up data written into the widgets' kept data:
todos-medium-dark, todos-large-dark, todos-large-light; calendar-large-dark, calendar-large-light, calendar-off-dark (the
plugin off); notes-medium-dark, notes-medium-light; voice-medium-dark, voice-large-dark, voice-large-light; picker-dark
(the picker's previews; only the four are offered); legacy-three-dark (a Quick note, Today and Pinned placed before,
drawn as the new ones); wide-tablet-dark (the display made 2208x1840: the launcher's own reflow, and the cell-high
widgets); voice-ring-opens-recorder (the ring's tap: the recorder, recording).

Proven there: the tick took "Book the train" off at once and the background job wrote `- [x]` into Work with the app
closed (`BackgroundTick … SUCCESS`); the ring opened the app straight into a recording; a heading opened the app; the
look followed the app's Dark on a light phone and its Light when injected; the size map turned and resized each widget
with nothing asked of the app.

## Not done

- Inter (above): the phone's sans in its place.
- A named theme's tint (Dawn, Boreal, Ember) is not drawn, only its side; nor the app's own text size setting (the
  phone's is).
- A calendar's own colour: the app draws every event in its ink (a ring), with no colour per calendar, and so do the
  widgets.
- An event opens the app's home page: there is no page of an event to open.
- The previews are layouts (Android 12+); Android 8 to 11 show the app's icon in the picker.
