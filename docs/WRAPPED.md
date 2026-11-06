# Wrapped

Matt, 2026-11-05: "create a plugin called "Wrapped" which gives you a "ghost markdown wrapped" kinda like spotify
wrapped but go through all the notes in the app in the backround slowly with whatever agent is connected detect stale
notes, unfinished items which we can chose to check off or remove from the list, suggested reorginizations and more".
Then: "Have this plugin add a card to the home page to view the wrapped section or in the sidebar dock".

Then, 2026-11-06: "Wrapped should also give weekly reports and work using the attached AI such as Claude".

A personal plugin in the AI category, off until added in Settings › Plugins. Code: `lib/plugins/wrapped/`. Tests:
`test/plugins/wrapped/`.

## The counts

`stats.dart`, with no AI, made again whenever the story opens: notes written in the period (by `createdAt`) and their
words, notes edited, the busiest month, weekday and hour, the longest run of days with a note written or edited, the
notes most linked to by `[[title]]`, the top tags and folders, to-dos done and open, meetings (`meeting:` front
matter) and recordings, plugins on. Periods: this year, the last 12 months, all time. Only the person's own notes:
an organization's are never counted or read. Notes in the Trash are left out.

## Which AI

Wrapped asks the AI the person has connected, by Cleanup's own list and rule (`lib/plugins/cleanup/ai.dart`
`connectedAis`, `defaultAiId`): Claude with its plugin on and the person's key kept, OpenAI, Gemini, a custom endpoint
or Aster each set up, or the model on the device; Local only leaves the device's alone. The one asked is the one picked
in **Which AI** on Wrapped's Settings page where it is still connected, else the app's own choice for the assistant,
else the first. The row says the AI's name ("Claude") and model; with more than one connected, Change lists them (Cleanup's
rows, `weekly_section.dart` `WrappedWhichAi`). The pick is kept in Wrapped's file (`chosenAi`). There is no shared picker
widget in the app: Cleanup and the contradiction finder each draw their own, so Wrapped draws Cleanup's rows. Every ask
goes through the provider's own client with its spending meter. With no AI the Wrapped and the weekly report are the
counts alone. Tested against a fake Messages API: with Claude connected, both the gists and the week's ask go to Claude;
OpenAI picked, to OpenAI (`test/plugins/wrapped/weekly_test.dart`).

## The pass

`pass.dart`, `service.dart`. Never starts by itself the first time: **Make my Wrapped** (the Settings page, the
Wrapped page, the home card) says what it will send and about what it costs, always the first time (`JobEstimate`
with `asksAlways`, through `askJobCost`): notes to read, asks, tokens, dollars where Claude's price table knows the
model, else "on your <AI> key". It spends the person's own key, through the AI they have connected (Cleanup's
`connectedAis`: Claude, OpenAI, Gemini, a custom endpoint, Aster, or the model on the device; the app's assistant
choice first). With no AI the Wrapped is the counts alone.

- **Gently.** A cloud model gets 6 notes an ask (1,200 characters each) with 8 s between asks; the device's model 2
  notes (500 characters) with 20 s between. Held while anything else runs on the Activity tray, a recording or a
  meeting, looked at again every 15 s ("Paused while the app is busy").
- **Kept as it goes.** Each answer is written to the state at once. A run asked for and not finished
  (`wanted`) goes on when the app is next open, or the plugin switched back on; only the notes not yet read are sent.
- **Cheap when nothing changed.** Each read keeps the hash of the words it was read from; a second Wrapped sends only
  the notes whose words changed.
- **Then one library ask**, from the one-line gists alone (never a note's words), up to 400 (60 on the device): themes,
  moves into folders there are, up to 3 new folders, near-duplicate merges, links to add, gems.
- Exact duplicates are found without the AI (Cleanup's `duplicateGroups`).
- On the Activity tray as `wrapped` with Stop and View, and on Android the foreground service with its notification
  (`ChannelBackgroundJobs`), as the Notion import and Lovart runs are. Three failed asks in a row end it with why.

## The weekly report

`weekly.dart` (pure), `service.dart` (making it), `weekly_section.dart` (on screen). "Your week in notes", once a week,
for the week before.

- **When.** Mondays at 8:00 unless changed (the day and the hour are settings). Weeks start on the locale's first day
  (`firstWeekdayOf`, CLDR's table by the device's country: Sunday in the US, Japan, Brazil…, Saturday in the Gulf,
  Monday elsewhere). A week's report is due on the first chosen day and time on or after its end.
- **Scheduled as the morning's ticket digest is** (`lib/book/ticket_digest.dart` `TicketDigestRunner`): looked at as the
  library is read at launch, as the app comes back (`AppLifecycleListener.onResume`), as the plugin is switched on, and
  on a timer to the next due moment, never more than an hour away, while the app runs. The app is not woken to make
  it: a week missed (the app not opened) is made at the next look, and only the latest due week, so a month away
  brings one report, not four.
- **Never twice.** A week is written down as made before its note is, so two looks at once make one; a note in the
  library with that week's `wrapped-week:` (made on another device, synced) counts as made too.
- **The note.** An entry of the **Weekly reports** journal (`book: true`, `journal: true`, `wrapped: weekly`, made the
  first time; found again by that key when renamed), titled "Week of 2 Nov 2026", with `date:` (its row in the journal)
  and `wrapped-week:` in its front matter. Plain Markdown, links by title, no boxes. The report and the journal are the
  app's own and never counted, read by the pass or listed in the review. A week with nothing written or edited makes
  no note.
- **Without AI** it holds: notes written and older notes edited, words written, to-dos done, added and still open,
  meetings and recordings, the busiest day, the notes come back to most, notes that crossed the stale line this week
  (not edited for 270 days, the day falling in the week), and up to 5 unfinished to-dos, each a link to its note.
  To-dos done and added are told apart from what the last report saw: each to-do by its note and the hash of its words,
  and each note's revision (for "came back to": saves since). The first report, with nothing to compare, counts the
  ticked boxes of the notes touched in the week as done and every box of the notes written in it as added.
- **With AI** (Include AI summary on, an AI connected): first the week's notes whose words changed since their last
  gist are read for one (the pass's own asks and cache, at most 60), then one ask: the counts, each of the week's notes
  as its title, folder and one-line gist (at most 40), and up to 30 open to-dos' lines (100 characters each), never a
  note's words. Back come 3 to 5 sentences on what the week was about, its themes, and 3 next steps, each one of
  Wrapped's own presses: check these to-dos off, archive this note, link these two, or open one. They are listed in the
  note and on the Wrapped page's **This week**, where Check off, Archive and Link go through the review's paths and are
  undone by Undo; Dismiss puts one away.
- **Asking first.** The first report with a cloud AI is made from the counts alone and says so; **Add the AI summary**
  on This week asks with the Activity's cost question (always, the first time) and on a yes writes the summary and
  steps into that report (the person's own edits kept) and every week's after. The device's model needs no yes.
- **What it costs.** The Settings page says it for the week so far (`weeklyEstimate`): with Claude Sonnet 5.5, a week
  of 12 notes all changed and 20 open to-dos is "~8k tokens · about $0.03 a week"; with their gists already read,
  "~2k tokens · about $0.01"; a busy week of 30 changed notes, "~17k · about $0.05". Elsewhere "on your OpenAI key";
  the device's model, nothing sent. About 340 tokens a note re-read for a gist, 35 a gist and 25 a to-do in the ask,
  and 600 back.
- **Delivery.** A notification, "Your week in notes is ready" with its line, through the phone's own notices
  (`lib/core/phone_notices.dart` `NoticesHost.post`, a tap opens the note), only where Android lets the app notify and
  Notify me is on; nothing on a desktop. The home card reads **This week** with View report for 7 days. The sidebar's
  Wrapped row, the bar's command and the dock's button open the Wrapped page, which leads with This week and View
  report (the next steps live there, so the entry opens the page rather than the note).
- **Settings** (Wrapped's Settings page, Weekly reports): on (on by default once Wrapped is on), Day, Time (on the hour,
  6:00 to 22:00), Include AI summary, Notify me. Kept in Wrapped's file. In Simple This week shows; the settings wait
  behind More.

## What is kept

`state.dart`: `.glyph/wrapped.json` in the Library, beside Cleanup's `cleanup.json` (Markdown-first: a git backup,
a shared folder and a restore carry it); the plugin's storage where the Library has no file Dart can reach. It holds
each note's hash, gist, themes and stale and gem flags; the AI picked; the weekly report's settings, the weeks made,
the last report (its note, line, summary, steps and their Undo records, its numbers) and what it saw (to-do keys and
note revisions, never words); the themes and suggestions; the period and the run's times;
each Keep, Dismiss and Later; and each press's record (before and after) for Undo. Never a note's words otherwise.
Nothing is written into a note without a press.

## The story

`story.dart`: full screen, a bold colour a card, tap the right two-thirds or swipe for the next, the left third for
the one before. Cards: your year in notes, notes written, words, busiest month/day/hour, longest streak, themes (the
AI's, else top tags), most connected note, to-dos, meetings and recordings, the one you forgot (a gem not opened in
three months; with no AI the longest note not edited in a year), and a summary. The words rise into place, and sit
still where the device asks for less motion. The ghost on the hello, streak, to-dos and forgotten cards; the mark on
the summary.

**Share** draws the summary card to a PNG and hands it to the device's share sheet (`PhoneDocuments.share`, as PDFs
and exports are shared). The picture holds numbers only (notes, words, streak, busiest month) unless the person ticks
"Include my themes in the picture".

## The review

`review.dart`, on the Wrapped page after the head (`page.dart`). Every change goes through the app's own paths
(`actions.dart`) and is recorded so **Undo** takes it back whole; a note changed since is left and named.

| List | Buttons | How it changes, and how it is undone |
|---|---|---|
| Unfinished to-dos, oldest note first, with the line over it and the line as written | Check off, Remove, Keep, Open; several ticked at once | `NoteLibrary.update` over the revision read, one write a note, counted as an edit; Undo writes the old words back over the revision it left |
| Stale notes (the AI's, Note decay alerts' pages where that plugin is on, short notes not edited in 9 months) | Archive, Trash, Later, Keep, Open | `archive` / `Trash.trashNote`, never deleted; Undo brings it out. Later hides it a month and reads it again next time |
| Suggested tidying: moves, new folders, merges | Apply, Dismiss | Cleanup's `applyCleanup` (moves checked and read back, merges with the copies to the Trash); a note in no folder by the drag's `moveCarried`; a top-level new folder made first. Undo: Cleanup's `undoCleanup`, an unfiled note filed in none again, an empty made folder removed |
| Links to add | Link, Dismiss | A `Related: [[Title]]` line through `applyCleanup`; Undo takes it off |
| May be out of date | Open, Mark superseded, Not a conflict | The contradiction finder's own (`ContradictionRunner`), where Contradictions is on |

Keep and Dismiss are remembered. In Simple the to-dos and stale notes show with their main buttons; tidying, links,
contradictions, Keep on a to-do, Later and choosing several wait behind More, which opens in place.

## Where it lives

- **Settings › Plugins › Wrapped** (`pane.dart`): This week, the period, View the story, Make or Refresh with the estimate,
  progress and Stop, the review, what is sent; Which AI, Weekly reports; the weekly settings and Read everything again behind More in Simple.
- **The home page**: its card (`home_card.dart`) through the new `GlyphPlugin.homeCard`: not made (Make my Wrapped),
  making ("Making your Wrapped… 40%", Open), this week (a weekly report of the last 7 days: "This week", its line,
  View report), ready (period, "312 notes this year", the ghost, View). In Simple too.
- **The sidebar** (wide window and the phone's drawer) and **the bar**: a Wrapped row and "Open my Wrapped", through
  the new `GlyphPlugin.places` (`PluginPlace`), which the shell reads from every plugin that is on; none is named by
  the shell. Shown in Simple too, as My tickets is. The dock has its button (`GlyphPlugin.dockButtons`, 2.4.25).
- **The Market** lists it from the registry as every plugin.

## Analytics

`wrapped_started` (notes bucket, period, provider), `wrapped_finished` (notes bucket, took), `wrapped_viewed`
(period), `wrapped_action` (kind, count bucket), `wrapped_weekly_made` (notes, to-dos done and steps, each a count
bucket), `wrapped_weekly_viewed` (steps bucket). Never a note's words, title or theme (docs/ANALYTICS.md).

## Left out

- The app is not woken to make a weekly report: no WorkManager job or launch timer, since the counts and the AI's ask
  need the app's Dart and the person's keys. A report is made while the app runs, or at its next launch.
- Two devices offline at the report's time can each make one; the second to sync is a second note for that week (both
  then count the week as made). The journal's index merges as two lines.
- To-dos done in the first report are an estimate (no earlier report to compare with); "came back to" counts saves, not
  openings, since the library keeps no record of a note opened.
