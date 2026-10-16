# Features added for 2.1

Each agent's section, appended. What was added, where a person finds it, and what is not done.

## reminders (branch `feat/reminders`, 2026-10-16)

Reminders on due dates, three home-screen widgets, the icon's shortcuts and a Quick Settings tile. All of it is
Android's: an iPhone and a Mac show none of it (the last part says what an iPhone would take).

### Where a person finds it

- **A reminder on a line**: hold a to-do (or any list item) and choose **Remind me** on its menu, after Assign: In an
  hour, This evening (until five), Tomorrow at Settings' time, Pick a time (the phone's calendar, then its clock), and
  Remove where the line has one. The line shows it as a chip, an alarm clock and "Tomorrow 9:00", in the third ink;
  a tap on the chip opens the same page.
- **A due date reminds by itself**: a to-do (`- [ ]`) or a ticket with a due date and no time is reminded at nine on
  the day, or the time Settings says, and the day before where asked. A plain list item with a date and no box is a
  date, not a task, and reminds only with its own `⏰`.
- **The notification** ("Reminders" channel, high importance): the item's words, then the note's title and why ("Work
  · Due today"). A tap opens the note at that line. **Done** ticks it; **Snooze 1 hour** rings it again an hour on. Done
  is offered only for a to-do with a box and for a ticket (whose status goes to its workflow's done).
- **Settings › Notifications › Reminders**, first on the page: Remind me (on by default), Time (9:00, the phone's own
  clock to change it), The day before. Under them, what Android keeps from reminders and the way to allow it: Allow
  notifications, or Allow exact times (Android's Alarms and reminders page). Findable in Settings' search.
- **Home-screen widgets** (long-press the home screen, Widgets, Ghost.md): **Quick note** (the pen: a new note with the
  keyboard up; the microphone: a new note being recorded, the microphone opened by that tap and never before),
  **Today** (the open to-dos due today and overdue from every note, each with a box to tick and the row a tap away
  from its note at that line; "Overdue" in a muted red), **Pinned notes** (a tap opens the note). The app's dark look on
  every wallpaper; rows as many as the widget's height holds, and "2 more" under them.
- **The icon's shortcuts** (long-press the app icon): New note, Voice note, Today, Search, then the three notes opened
  last. A launcher shows what it has room for: the Pixel launcher shows four, two of the app's own and two recent notes
  (Launcher3 keeps two places for recent ones), so Today and Search are there to pin but not in its popup.
- **Quick Settings tile**: New note (edit the shade's tiles to add it). Over a locked phone it asks to unlock first.

### How it is written (plain Markdown, docs/MARKDOWN.md's rule)

- A reminder is `⏰ 2026-10-03 09:00` in the line, before the run of Obsidian Tasks' fields:
  `- [ ] Call the plumber ⏰ 2026-10-03 09:00 📅 2026-10-03`. The sign and form are the Obsidian Reminder plugin's,
  which reads them beside Tasks; Tasks itself reads the 📅 after it. Read in the one field grammar
  (lib/core/task_fields.dart: a `tasks` field with the key `reminder`), so a board card's words and a title sent to
  Notion or GitHub leave it out, as they leave out a date. The time is the phone's wall clock wherever it is.
- A ticket keeps its own time in its front matter: `remind: 2026-10-03 09:00` (read; there is no row for it in the
  ticket's panel yet).
- Nothing is written for a due date's own reminder: it is worked out.
- The settings are this device's (`glyph-reminders` in its memory, never synced): only a phone reminds.

### How it works

- **The plan** (lib/reminders/reminder_plan.dart) is pure: every note's dated items, read once per note object
  (lib/reminders/dated_items.dart; the library keeps a note the same object while it is the same), less the Trash, the
  archive, templates and canvases, ticked and cancelled items; only what is still to come, the soonest 64. A pass runs
  1.5 s after the notes, the Trash or the settings last changed (lib/root/phone_extras.dart), never per keystroke, and
  hands the phone the plan only when it is another than the last. Notes that arrive by a sync are library changes like
  any other and are planned here too. At each start and each return to the front, everything is handed over again
  (an app stopped by force has lost its alarms).
- **The alarms** (android/…/ghost_md/reminders/Reminders.kt) are kept in SharedPreferences as the day and time written,
  turned into a moment each time they are armed. **Exact where Android allows it**: `setExactAndAllowWhileIdle` before
  Android 12, and from 12 once the person allows Alarms and reminders (SCHEDULE_EXACT_ALARM; a new install on Android
  14+ starts without it). **Inexact otherwise**: `setAndAllowWhileIdle`, which still rings with the phone asleep and may
  be some minutes late. Not USE_EXACT_ALARM, which Google Play keeps for alarm clocks and calendars.
- **Restarts**: ReminderRestart arms everything again on BOOT_COMPLETED, MY_PACKAGE_REPLACED, TIME_SET,
  TIMEZONE_CHANGED and the exact-alarm permission changing, and after a restart rings once what was due in the last
  twelve hours. Alarms only: no service is started from any of them.
- **Done** is written through the app's library, never by Kotlin writing the file (GhostBackground.kt): while the app
  runs, it is handed to it (`tick` on `ghost_md/reminders`) and written into the open note's editor where that note is
  on screen (saved like typing, no conflict with the note's own save), else through `NoteLibrary.update`; with the app
  closed, a WorkManager job starts an engine of its own with no window on `lib/reminders/background_tick.dart`, which
  opens the core (deaf to its events, so a starting app keeps them), ticks the line (lib/reminders/tick_item.dart, the
  same edit as a tap on the box, boards settled) and lets the engine go. The ticked item leaves the Today widget at
  once, and its other reminders are let go before the app has read the tick.
- **The widgets** (android/…/ghost_md/home/): RemoteViews, no Compose, no collection service. They draw what the app
  last handed over on `ghost_md/home_screen` (lib/home_screen/home_screen_data.dart: Today's to-dos due up to a week
  ahead, the pinned notes, the recent notes; each only when changed), so they draw with the app closed; Today turns its
  own day at midnight by an alarm within ten minutes of it, not waking the phone. The box is a real CheckBox from
  Android 12 (RemoteViews' compound buttons), a ring to press before.
- **The ways in** are `ghostmd://` links to the one activity (lib/home_screen/phone_entries.dart): `new`, `voice`,
  `today`, `search`, and `note/<id>?line=12&find=…`. Covering screens (Settings, a sheet) are put away first, and a new
  note's keyboard is asked for again once the app is in front.

### New permissions, receivers and services

- Permissions: `SCHEDULE_EXACT_ALARM` (user-granted, Android 12+), `RECEIVE_BOOT_COMPLETED`. POST_NOTIFICATIONS was there.
- Receivers: `.reminders.ReminderAlarms` (not exported), `.reminders.ReminderRestart` (not exported; BOOT_COMPLETED,
  MY_PACKAGE_REPLACED, TIME_SET, TIMEZONE_CHANGED, SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED), `.home.WidgetTicks`
  (not exported), and the three providers `.home.QuickNoteWidget`, `.home.TodayWidget`, `.home.PinnedWidget`
  (exported, as a widget's provider must be).
- Service: `.home.NewNoteTile` (BIND_QUICK_SETTINGS_TILE). Worker: `BackgroundTick` (WorkManager, no manifest entry).
- The icon's shortcuts: `res/xml/ghost_app_shortcuts.xml` and `ghost_cutover_app_shortcuts.xml` (new, a build without
  the assistant), and the assistant's two files gained the same rows after Record note (no Voice note there: Record
  note is it). android/app/build.gradle.kts picks the file by build; a build made to be measured has none.

### Proven on the emulator (ghostflutter2, Android 16, at the Fold's cover size 1248x1972)

A reminder set two minutes ahead with Pick a time rang on its minute (exact, `exactAllowReason=permission`) with the
app in the background and again with its process killed; Done ticked the line both ways (the second through the
engine of its own: the file read back `- [x] Pay the rent ⏰ 2026-10-16 13:28`); Snooze 1 hour armed it again an hour
on; a reboot armed both alarms again; the clock moved to the next morning rang the due date's nine o'clock reminder
("Work · Due today") and turned the Today widget's day. The three widgets rendered, ticked a to-do into its note, and
opened the app at the line; the icon's popup showed New note, Voice note and two recent notes and each opened; Search
and Today opened the palette and today's entry; the tile opened a new note. Inexact alarms were not timed.

### Not done, and for the coordinator

- **Today's note**: until `feat/organize` is merged, Today makes a new entry in the journal written in last (a new
  note where there is none). Once merged, `_PhoneDoor.today()` in lib/root/ghost_root.dart should be
  `_withShell((_) { raiseKeyboardSoon(); root._organize.today(); });`.
- **Scan document** is not on the icon: `feat/files`'s `scanToNewNote()` (lib/files/plus_files.dart) is not on main.
  Once merged: a fifth row `ghostmd://scan` in the four shortcut files, a `ScanEntry` in phone_entries.dart, and
  `_PhoneDoor.scan()` calling `scanToNewNote()` then `root._library.createNote(words)` and opening it.
- **Voice note** on the icon and on Quick note is offered in every build, where Record note (the assistant's capture)
  stays behind the developer flag (Matt, 2026-10-11). It opens the dock's own Speak, a voice memo, not the assistant;
  Matt may want it behind the flag too.
- A Kotlin side cannot tell a ticked or edited note from another device while the app is closed: an alarm armed before
  rings with the words it had until the app next runs a pass.
- No row for a ticket's `remind:` in its panel; no recurrence (`🔁`) acted on; the 65th reminder onward waits for the
  next pass.
- Not measured on a real Fold (cover-screen launcher, One UI's shortcut popup, Samsung's battery rules on alarms).

### iPhone (hidden; what it would take)

- **Reminders**: UNUserNotificationCenter with `UNCalendarNotificationTrigger` needs no entitlement, only the
  notification prompt, which the store build has never shown. A Swift half of `ghost_md/reminders` (set, state, pick a
  time), a category with Done and Snooze; Done would need a background launch of a Flutter engine like Android's (an
  `UNNotificationAction` without `.foreground`), and iOS gives that a few seconds at most. Hidden until the store
  build's behaviour may change.
- **App Intents / Shortcuts** ("New note", "Append to note"): an `AppIntent` in the app target can open the app at a
  `ghostmd://` link with no new target; "Append to note" without opening the app needs an App Intents extension
  target (a second bundle, its own signing and provisioning profile, an App Group to reach the library) and a store
  review.
- **WidgetKit** (Today, Pinned, Quick note): a Widget Extension target (SwiftUI), an App Group container the app writes
  the same JSON into (`today`, `pinned`), interactive buttons from iOS 17 through App Intents for the tick, and the
  same signing and review. None of it is added.
