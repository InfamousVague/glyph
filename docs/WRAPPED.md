# Wrapped

Matt, 2026-11-05: "create a plugin called "Wrapped" which gives you a "ghost markdown wrapped" kinda like spotify
wrapped but go through all the notes in the app in the backround slowly with whatever agent is connected detect stale
notes, unfinished items which we can chose to check off or remove from the list, suggested reorginizations and more".
Then: "Have this plugin add a card to the home page to view the wrapped section or in the sidebar dock".

A personal plugin in the AI category, off until added in Settings › Plugins. Code: `lib/plugins/wrapped/`. Tests:
`test/plugins/wrapped/`.

## The counts

`stats.dart`, with no AI, made again whenever the story opens: notes written in the period (by `createdAt`) and their
words, notes edited, the busiest month, weekday and hour, the longest run of days with a note written or edited, the
notes most linked to by `[[title]]`, the top tags and folders, to-dos done and open, meetings (`meeting:` front
matter) and recordings, plugins on. Periods: this year, the last 12 months, all time. Only the person's own notes:
an organization's are never counted or read. Notes in the Trash are left out.

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

## What is kept

`state.dart`: `.glyph/wrapped.json` in the Library, beside Cleanup's `cleanup.json` (Markdown-first: a git backup,
a shared folder and a restore carry it); the plugin's storage where the Library has no file Dart can reach. It holds
each note's hash, gist, themes and stale and gem flags; the themes and suggestions; the period and the run's times;
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

- **Settings › Plugins › Wrapped** (`pane.dart`): the period, View the story, Make or Refresh with the estimate,
  progress and Stop, the review, what is sent; Read everything again behind More in Simple.
- **The home page**: its card (`home_card.dart`) through the new `GlyphPlugin.homeCard`: not made (Make my Wrapped),
  making ("Making your Wrapped… 40%", Open), ready (period, "312 notes this year", the ghost, View). In Simple too.
- **The sidebar** (wide window and the phone's drawer) and **the bar**: a Wrapped row and "Open my Wrapped", through
  the new `GlyphPlugin.places` (`PluginPlace`), which the shell reads from every plugin that is on; none is named by
  the shell. Shown in Simple too, as My tickets is. The phone's floating dock has a fixed set of the app's own
  buttons (`dockButtonIds`) with no plugin extension, so Wrapped is not on it.
- **The Market** lists it from the registry as every plugin.

## Analytics

`wrapped_started` (notes bucket, period, provider), `wrapped_finished` (notes bucket, took), `wrapped_viewed`
(period), `wrapped_action` (kind, count bucket). Never a note's words, title or theme (docs/ANALYTICS.md).
