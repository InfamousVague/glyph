# Stage 8's AI (8I, 8J, 8K, 8L) and the plugin list (9E): what is in lib/, and every seam left for the root

Written 2026-10-09. The pieces are ported and tested by themselves; none of them is called from `lib/root` yet. This
is the list of what `lib/root` (`ghost_root.dart`, `voice_wiring.dart`, `note_desk.dart`) has to call, in the order
a launch and then an open note need them. Each file's own header says the same of itself, with what differs from
the page.

## What is where

| Piece | Files | From `tauri/src/app` |
| ----- | ----- | ----------------------- |
| The plugins that ship | `lib/plugins/built_in.dart` | the foot of `plugins/registry.ts` |
| A spoken instruction's reader | `lib/ai/instruction.dart` (`lib/capture/run_of.dart` and `lib/capture/ui/read_instruction.dart` ask it) | `ai/instruction.ts` |
| The newer prompts | `lib/ai/prompts.dart` | `ai/prompts.ts` |
| The fills | `lib/ai/fills/{queue,web,edits,lane,source,fill_landing}.dart` | `ai/fills/*.ts` |
| A note's run | `lib/ai/{land,start,note_landing,summary_ask}.dart` | `ai/land.ts`, `start.ts`, `useLanding.ts` |
| The summary queue | `lib/ai/{summaries,job_config}.dart` | `ai/summaries.ts`, `jobConfig.ts` |
| The gist | `lib/format/gist.dart` | `format/gist.ts` |
| The review | `lib/ai/{review,review_simulation,note_review,review_stage}.dart` | `ai/review.ts`, `reviewSimulation.ts`, `useNoteReview.ts` |
| The editor's AI surface | `lib/editor/ai/{ai_changes,blanks,fill_panel,wisp_arrivals,wisp_ripples}.dart`, `lib/ai/{ai_strip,note_ai}.dart`, `lib/format/{ai_card,thinking}.dart` | `editor/aiChanges.ts`, `blanks.ts`, `fillPanel.ts`, `wispArrivals.ts`, `wispRipples.ts`, `useNoteAi.ts`, `ai/AiStrip.tsx`, `format/AiCard.tsx`, `Thinking.tsx` |
| The at-work scene | `lib/scene/*.dart` | `scene/*` |

The confirm card (`ai/ConfirmCard.tsx`) was already `lib/capture/ui/capture_cards.dart`'s.

## At launch, once

1. **Plugins.** `installBuiltInPlugins(localOnly: () => preferences.value.localOnly)` (`lib/plugins/built_in.dart`),
   before the first screen is built. It makes the five the app's `plugins` and hands them every pass of the feed's
   rows. Then `usePluginContext(PluginContext(contextFor: plugins.contextFor, contextVersion: plugins.contextVersion))`
   (`lib/format/pipeline.dart`), so a run's system message and a note's hash carry a linked repo's briefing. And
   `claudeHandle = () => session?.handle` (`lib/plugins/claude/claude.dart`) once there is an account (set in the
   root's `initState`, 2026-10-09).
2. **Who signs a note beside the AI.** `noteOwner = () => session?.handle` (`lib/ai/start.dart`).
3. **The summary queue.** One `Summaries(...)` (`lib/ai/summaries.dart`), given what its header lists: `isTauri`
   (`() => aiBackend.available`), `preferences`, `stored`, the better-words queue's `refineHeld`, `refinePending`
   and `onRefineHold` (a `Refining`'s methods), `canNotifyNow` (the `MeetingLive`'s), `recordingJobState` and
   `takeRecordingResult` (`lib/ai/native_backend.dart`, through `RecordingJobState.fromJson` and
   `RecordingResult.fromJson`; empty and null on a binary below generation 20), `writeUpOnHost`, `answerHost`,
   `getNote` and `updateNote` (the library's `get` and `update`; a conflict must fail with words that say `changed`
   or `deleted`), `isTrashed`, `syncNow`, `syncSettled`, `record` (the feed's), `visible`, `onVisible`,
   `onNotesChanged`, `sendJobConfig` (`lib/ai/job_config.dart`). Then
   `summaries.startSummaries(changed, summarized)`: `changed` reads the library again, `summarized` shows
   "Summarized" with Open. Keep the stop it answers.
4. **The write-up's configuration.** `keepJobConfigCurrent()` (`lib/ai/job_config.dart`); keep the stop.
5. **The fills' queue.** `startFills(toast, open, getNote: …, updateNote: …, syncNow: …, onLine: …, visible: …,
   onOnline: …)` (`lib/ai/fills/queue.dart`); keep the stop. `updateNote` must fail with words that say `changed`,
   `deleted` or `revision` on a conflict. With Local only switched off, `resumeParked()`.
6. **The gists.** `refining.onRefineHold(pauseGists)` (`lib/format/gist.dart`), `gistVisible = () => <the app is on
   screen>`, and `gistsCameBack()` each time it comes back. The home page and All notes each make a `Gists()`,
   call `gists.show(notes)` when their notes change, listen to it, and pass `gists.value` as their `gists:`.
7. **The recorder.** `Recorder(reviewAvailable: reviewAvailable, enqueueSummary: (id, kind) =>
   summaries.enqueueSummary(id, SummaryKind.values.byName(kind)), …)` (`lib/ai/review.dart`, `lib/ai/summaries.dart`),
   where `lib/root/voice_wiring.dart` leaves the recorder's own no-ops today.
8. **The phone, for the AI card.** One `DeviceFactsController(cores: …, memoryGb: …)` (`lib/format/device_facts.dart`).
9. **Availability.** One `AvailabilityController()` (`lib/ai/available.dart`), refreshed as the app comes back.

## For each open note (`lib/root/note_desk.dart`)

One `NoteAi` (`lib/ai/note_ai.dart`; its header has the call written out), made with the desk and disposed of with
it:

```dart
final ai = NoteAi(noteId: …, flush: …, body: …, wisp: …, toast: …, onGetModel: …, availability: …,
    reviewHost: ReviewHost(…), openForSummaries: summaries.openForSummaries);
```

- **The editor's extensions:** `...noteAiExtensions(ai, still: t.reducedMotion)`. It brings `fillPanel()`,
  `blanks(ai.blankHooks, still:)`, `wispArrivals(typing: true)` and `aiChanges(onMarks: ai.onAiMarks)`.
  `wispArrivals` brings `wispDepartures` itself, so give the marks as `markExtensions(marks)` without
  `wispTyping: true`, or every ghost is drawn twice. The editor's maker must also fill
  `wispStill.of(t.reducedMotion)` and `wispPace.of(…)` (`lib/editor/marks/wisp_motion.dart`), which `note_desk.dart`
  does not do today.
- **The view:** `ai.attach(view)` when the editor's view exists, `ai.attach(null)` as it goes.
- **What the note was opened with:** `ai.ask(NoteAsk(kind: …, instruction: …, key: …))` for a spoken instruction
  (the recorder's `onFinish(…, ask:)`; `RunKind.of(ask.kind)` turns the recorder's word into the kind), and
  `ai.review(handoff, key)` for its review (`onFinish(…, review:)`), with a number the root counts up.
- **Over the page:** `NoteAiLayer(ai: ai, top: <where the header ends>, onRoom: (room) => <pad the page by it>,
  deviceFacts: …)` in the note screen's own stack, covering the editor (`NoteSeams.over`): the strip under the
  header, and the panel a tap on a blank or a filled answer opens (`EditorFillPanel`). Call `ai.closePanels()` when
  the note's page scrolls. (`lib/editor/view/text_panel.dart`'s `EditorTextPanels`, the panel of a mark's note, is
  stacked nowhere in `lib/` today either; it wants the same place.)
- **Over the window:** `AtWork(noteId: …, opening: ai.reviewKey, heard: ai.handoff?.heard ?? '', body: note.body,
  hasJob: ai.handoff?.job != null, stage: ai.reviewStage.value, refining: refining.refining,
  summaryDue: summaries.pendingFor(note.id))`
  (`lib/scene/at_work.dart`, whose header says where in the window's stack and why), rebuilt when `ai` or
  `ai.reviewStage` tells.
- **The More sheet:** its AI rows call `ai.runAi(kind)` and mark `ai.runningKind`; the tape's Summarize word is
  there while `ai.canSummarize`.
- **A table's cells:** `lib/editor/tables/table_box.dart` asks `drawCell` for each cell and holds what it answers
  in the cell in place of its words (`HeldCell`, laid out by `TableLayout` through a `CellHost`), puts `tablePill`
  after the last row, and is drawn again when `blankStamp` moves (2026-10-09).

## The recorder's page

`wispArrivals()` and `wispRipples(source)` in place of `lib/capture/ui/live_page.dart`'s own `liveArrivals`, where
`source` is a `RippleSource` over the microphone's level. Not done here: `lib/capture` is another hand's.

## Known, and left

- A debug build reaches no service of ours from any of this: the fills' lookups go to Open-Meteo, Frankfurter,
  Wikipedia and Wikidata alone (`lib/ai/fills/web.dart`), and only for a blank a person pressed with Look up blanks
  on.
- The fills' page fetch follows no redirect (`pageFetcher()`), where the browser's `fetch` did: a 3xx reads as
  nothing found.
- `Lucide.waves` is still not in the set (`waves-horizontal` is); nothing here draws it.
- The lander's two faults the page pins in its own tests (a dropped line counted twice; the model's version put
  above a line the person rewrote when it comes only with the finished answer) are carried over as they are, and
  pinned the same way (`test/ai/note_landing_test.dart`).
