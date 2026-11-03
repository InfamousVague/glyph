# Note decay alerts

Matt, 2026-11-02, picking from a list of AI ideas: "Note decay alerts: docs and pages that reference things that have
since changed (a renamed ticket, a merged PR on GitHub, an old date) get a quiet 'may be out of date' mark with the
reason."

The plugin is `lib/plugins/note_decay/`, id `note-decay`, in the Market's AI shelf, **off until added**. It never
writes a mark into a note: a mark is drawn by the editor over the line it is about, and goes when the note no longer
says the thing, or the person says it is still right.

## 1. Two layers, cheap first

### 1.1 Signals (no AI)

Read from the note and the library alone, plus two lookups outside the phone that Local only turns off. Each signal
is one line of the note (or the page's head, for the page as a whole), a **reason** in plain words, and a **stamp**:
what the source said when the signal was made, so a "Still right" is kept until the source changes again.

| Kind | What it finds | Reason, as the mark says it | Stamp |
|---|---|---|---|
| `link` | `[[Title]]` naming no note now, where a note was called that once (its versions' head titles, or the library's rename record), or naming a note in the trash or archived | "[[Spec]] was renamed to [[Spec v2]]" · "[[Spec]] is in the trash" · "[[Spec]] was archived" | the new title, or `trashed` / `archived` |
| `ticket` | `[[GHO-12]]` (or a bare `GHO-12` that is a ticket in the library) whose status is done (lib/core/properties.dart `statusCategory`) on or after the day the note was last edited, its `done:` day being when | "GHO-12 was closed on Oct 30" (the ticket's own status word: Done, Shipped, Closed…) | the ticket's status and `done:` day |
| `github` | a github.com issue or pull request link, now merged or closed after the note was last edited | "PR #12 in owner/repo was merged on Oct 30" · "Issue #40 in owner/repo was closed on Oct 30" | `merged@<day>` / `closed@<day>` |
| `date` | a date in a sentence that speaks of the future ("ships on Nov 1", "will launch 2026-10-20", "due by 3 Nov"), now past | "Nov 1 has passed; this still speaks of it as ahead" | the date |
| `figma` | a Figma frame or file link Figma says is not there (404) | "The Figma frame this links to is gone" | `gone` |
| `stale` | a teamspace doc page (a page of a `type: docs` notebook, docs/TEAMSPACES.md) not edited in three months (Settings: 1–12) while pages it links to changed since | "Not edited since Jul 2, and [[Pricing]] and [[Plans]] changed since" (page head) | the newest change among those pages |

Years: a date without one is read in the year the note was last edited, and in the next where that would put it more
than two months before the edit (a note written in December about "Jan 4").

Future tense, without a model: the sentence holds a word that looks ahead — *will, shall, going to, is/are due, due,
ships, launches, lands, releases, starts, opens, goes live, planned, scheduled, expected, upcoming, targeting, aim(s)
to, by, until, next* — and no word that looks back (*shipped, launched, released, was, were, did, happened, ago,
done*). The words are a list in `dates.dart`, tested one by one; a false mark costs one tap of Still right.

Lookups outside the phone (`github`, `figma`) are made only with the GitHub and Figma plugins connected (their own
tokens, lib/plugins/github/, lib/plugins/figma/), only for links in the note being checked, kept for an hour in
memory, and **never with Local only on**. With Local only the plugin stays on: everything else is the phone's.

### 1.2 The AI pass (its own switch, off by default)

For a page the signals flagged, or a teamspace doc page older than the threshold (30 days by default), the connected
AI reads the page and what changed in its sources (the renamed note's new title, the ticket's status and its first
lines, the PR's title and state) and answers JSON:

```json
{"outOfDate": true, "lines": [{"quote": "Billing ships on Nov 1.", "why": "GHO-12 says billing moved to December."}]}
```

Each quote is looked for in the page (whitespace and quotes folded); one that is not there is dropped, so the model
cannot mark a line the page does not have. A kept quote's line gets a mark whose reason is the model's `why`, said as
the AI's ("AI: …").

Which AI: whatever is connected (lib/assistant/app_assistant.dart `appAssistant`, as Settings › AI › Assistant
chooses it: Claude, OpenAI, Gemini, a custom endpoint, Aster), else the phone's own model (lib/ai/backend.dart) where
one is installed. **Local only: the phone's model, or nothing.** The plugin asks through one seam, `DecayModel`
(ai.dart), so tests never reach a network or a model.

## 2. What the person sees

- **A quiet mark on the line**: a faint wash of the ink behind the line's words (5%, fainter than a Lovart cue's)
  and, at the line's end, a muted "May be out of date" chip with a clock. Tapping it opens the reason ("May be out of date: GHO-12 was closed on Oct 30") with two
  actions: **Update with AI** and **Still right**. A page-wide signal (`stale`) is the same chip at the page's head.
- **Update with AI** asks the AI for edits to the marked lines, as JSON `{"edits":[{"quote","replacement"}]}`, checks
  every quote is in the page, and shows them as a diff — each old line struck, its new line under it — with Accept
  and Reject for each and for all. Nothing is applied until Accept; an accepted edit goes in as one change the
  editor's Undo takes back.
- **Still right** dismisses that signal, and it stays dismissed until its stamp changes (the ticket reopened and
  closed again, the PR merged after being closed, the note renamed again).
- **Pages that may be out of date**: a list on a teamspace's home page, on a docs notebook's index, and on the
  plugin's page in Settings — each page with its first reason and how many more.

Simple mode (`preferences.value.simple`): the plugin's page is one switch, "Check with AI" (the marks themselves are
the plugin being added), and the list; GitHub/Figma lookups and the months are behind More, which opens in place.

## 3. Where things are kept (docs/MARKDOWN_FIRST.md)

- **Dismissals are the note's**: a `decay-ok:` list in its front matter, one `kind:key@stamp` each, written with
  `withProperty` (lib/core/properties.dart). A git restore, a move, another device and an old build all keep it. Per
  note, as §6 of MARKDOWN_FIRST says per-note facts are.
- **The switches are the device's** (`glyph-note-decay`, the plugin's own storage key): on/off for the AI pass, the
  lookups, and the months. A git restore asks for them again, as for every plugin's settings.
- **Signals and lookups are a cache**: recomputed from the files whenever a note is opened or the list is drawn;
  never kept.

## 4. Files

| File | What |
|---|---|
| `lib/plugins/note_decay/manifest.dart` | the manifest, its storage key, the plugin's host |
| `lib/plugins/note_decay/note_decay.dart` | the plugin (`noteDecayPlugin`), its summary and page |
| `lib/plugins/note_decay/signals.dart` | `DecaySignal`, `DecayNote`, `DecayLibrary`, the deterministic checks |
| `lib/plugins/note_decay/dates.dart` | dates in a sentence and whether it looks ahead |
| `lib/plugins/note_decay/lookups.dart` | GitHub's and Figma's answers, behind `DecayLookups` |
| `lib/plugins/note_decay/dismissals.dart` | `decay-ok:` read and written |
| `lib/plugins/note_decay/ai.dart` | `DecayModel`, the AI pass and Update with AI, quotes checked |
| `lib/plugins/note_decay/sheets.dart` | Update with AI's reviewable diff, and Still right |
| `lib/plugins/note_decay/source.dart` | the signals as marks of the shared mark (lib/plugins/out_of_date/) |
| `lib/plugins/note_decay/decay_list.dart` | Pages that may be out of date |
| `lib/plugins/note_decay/decay_pane.dart` | the plugin's page |

## 5. One mark, shared with the Contradiction finder

Contradictions compare notes with each other; decay compares a note with the world and its sources. To a reader both
say "this line may be stale", so they wear one mark (Matt, 2026-11-02, asked whether to fold them: "Yes, fold them").
`lib/plugins/out_of_date/out_of_date.dart` owns it and knows no plugin: each plugin is an `OutOfDateSource` that gives
marks (a line, a reason, a detail, actions), and `sources.dart` lists the app's, the finder's first.

- The chip at a line's end, or at the page's head, counts its reasons ("May be out of date · 2").
- The sheet lists each reason with its own plugin's rows under it: the finder's Open, Mark superseded and Not a
  conflict; this plugin's Update with AI and Still right. Putting one away leaves the others.
- While neither plugin is on, the page is never read for marks; while one is, a letter typed moves the marks and they
  are asked again once typing pauses.

## 6. Status

Built 2026-11-02, not released.

- **Wired**: the plugin in the Market's AI shelf (off until added, amber); the root starts one `NoteDecay` over the
  library (lib/root/ghost_root.dart); every open note's editor draws the marks and asks GitHub, Figma and the AI once
  as it opens (lib/root/note_desk.dart); the list on a teamspace's home (lib/orgs/ui/teamspace_home.dart), under a
  docs notebook's index (lib/book/book_view.dart) and on the plugin's page.
- **Renames** are heard on this device as the library changes (a title before and after a save) and kept under
  `glyph-note-decay-renames`: the library keeps no rename of its own, and a `[[link]]` keeps the name it was written
  with (lib/core/link_index.dart). So a rename made on another device, or before the plugin was added, is not known
  here; it is a cache, not a record, and a git restore loses it. A rename record in the files would need the
  library's own (docs/MARKDOWN_FIRST.md).
- **The AI pass** runs as a note opens, never in the background over the whole library: the lists show what the cheap
  layer finds everywhere, plus what a pass found for pages opened since the app started.
- **Ticket references** are `[[GHO-12]]` and a bare `GHO-12` that is a ticket in the library; "renamed ticket" is the
  `link` signal when a ticket is linked by its title.
- Not built: the hosted connector (mcp/) does not show marks; the contradiction finder had not landed, so the mark
  here became the one both share (§5).

Tests: test/plugins/note_decay/ (signals_test, ai_test, marks_test); pictures with `--update-goldens` in
build/feature-shots/note-decay/.

## 7. Open questions for Matt

1. Should the AI pass also run in the background over a teamspace's docs (say once a day, on Wi-Fi), so the lists
   find AI-only marks without each page being opened? It costs tokens per page.
2. Renames: keep them on the device as now, or write the old title into the renamed note (`was: [Spec]`) so every
   device and a git restore know it? That writes into a note on rename.
3. Should Still right on a team page be the team's (written in the page, as now) or each person's own?
4. ~~One mark or two~~: folded, 2026-11-02 (§5).
