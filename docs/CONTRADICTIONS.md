# Contradiction finder

Matt, 2026-11-02, choosing from a list of AI ideas: "Contradiction finder: spots when a newer note disagrees with an
older one (e.g. 'release is Thursday' in one, 'release moved to Monday' in a later meeting) and flags the stale one
inline, 'superseded by …', so old notes stop misleading you or the AI."

The plugin is `contradictions` ("Contradiction finder", AI shelf, off until added). Its code is in two folders of its
own so it does not meet the sessions building Cleanup, Ask the org, Self-maintaining indexes and Note decay alerts:

- `lib/ai/contradictions/`: the pure parts and the run. `candidates.dart` (which pairs of notes are worth asking
  about), `compare.dart` (the prompt, and reading the AI's JSON strictly), `findings.dart` (a finding, the file it is
  kept in, Mark superseded's markdown), `ai.dart` (which AI answers), `runner.dart` (the background run, its schedule,
  its job in the activity tray).
- `lib/plugins/contradictions/`: the plugin (manifest, the inline mark through the registry's `suggest`), its page in
  Settings, the sheet the mark opens, and the quiet line on the home page.

## What the person sees

**An inline mark on the older note's line.** A quiet pill at the end of the stale line, "Out of date?", drawn by the
editor's line suggestions (lib/editor/items/suggestions.dart) as Notion's and GitHub's words are: a decoration, never
written into the note. Pressing it opens a small sheet:

- the newer note's title and its words ("Release moved to Monday"), what disagrees in a line, and when it was found;
- **Open newer note**;
- **Mark superseded**, which writes one readable line under the stale one, through the editor so it is one undo step:

  ```markdown
  Release is Thursday.
  > Superseded by [[Standup 2026-11-02]] (2026-11-02): “release moved to Monday”
  ```

  A blockquote was chosen over a footnote because it reads the same in Obsidian, GitHub, iA Writer and plain text, it
  sits next to the line it qualifies, and `[^c1]` footnotes are already the shared notes' comments (docs/TEAMSPACES.md).
  Under a list item it is indented to the item's text, so it stays inside the item and the list is not broken. A line
  already followed by a `> Superseded by` line is never marked again.
- **Not a conflict**, which dismisses it. The dismissal is remembered by the older note, its line's words and the newer
  note, so the same disagreement found again on a later run never comes back.

**A list of open findings** on the plugin's page in Settings, each with the two notes, the two quotes, and Open, Not a
conflict. **A quiet line on the home page**, "2 notes may be out of date   Review", in the notices (lib/notes/notices.dart
`JobNotice`'s look), which opens the page. Nothing at all with no open findings.

Only high-confidence findings are shown: the AI's confidence must be at least 0.8 (under More, the person can make it
0.7 or 0.9).

## How it runs

**Schedule** (the page's first card): Off, When a note is saved, or Nightly (the default). Nothing runs on its own until
the person has run it once by hand with **Check now**, which is where the cost is said (below). When a note is saved,
the run waits two minutes after the last save and checks only pairs that include the notes saved since. Nightly, it
runs once a day while the app is open, after 3 in the morning or on the first open after that.

**1. Candidates, cheaply, on the device** (candidates.dart, no AI). Each note is read for its *keys*: `[[links]]` and
`#tags`, `@people`, the words of its title, dates and weekdays ("Thursday", "Nov 12", "2026-11-12"), and numbers that
carry a unit or a sign ("$40k", "12%", "v2.4", "3 weeks"). Two notes are a candidate pair when they share enough of
them: a link between them or a shared `[[link]]`, `@person` or `#tag` counts 2, a shared title word or date 1, one note's title word in the other's
words 1 each way, and a pair needs 3, with at least one date, weekday or number in each, since a contradiction is almost always about when,
how much or who. Then only the lines of each note that hold a key or a fact are kept as the excerpt, numbered, up to
1,200 characters a note. Pairs are ranked by score and by how new the newer note is, at most 60 a run. A pair already
asked about at the same two revisions is never asked again (`checked` in the file).

**2. The AI compares**, six pairs to a request, and answers JSON only:

```json
{"findings": [{"pair": 1, "older": "A", "older_quote": "Release is Thursday", "newer": "B",
  "newer_quote": "release moved to Monday", "what": "The release day moved from Thursday to Monday.",
  "confidence": 0.93}]}
```

**3. Validation** (compare.dart `readFindings`), strict, since the AI may invent: the JSON is found even inside a code
fence or with words around it; a pair number the request did not have, an `older` that is not the older note by
`updatedAt`, a quote that is not in that note's words (compared with spaces, case and quote marks made alike), a
confidence that is not a number from 0 to 1 or is under the threshold, and an empty `what` are each dropped. One
finding per older line: the most confident wins.

## Which AI

"Whatever AI is connected", through the provider layer every other AI feature uses (ai.dart `chooseContradictionAi`):

- **Local only on** (Settings › AI): the on-device model only (lib/ai/backend.dart `generate`, the model
  `modelNow` picks). With no model on the device, the run waits and the page says "Needs a model on this device".
- Otherwise the **chat's choice** (lib/assistant/assistant.dart `AssistantChoice.chatBy`, Settings › AI › Assistant):
  Claude with the person's key, or OpenAI, Gemini, a custom endpoint or Aster through their routes, each counted by its
  own spending meter (lib/claude/claude_spend.dart `meterClaude`) and refused at its monthly limit.
- With none of them set up, the on-device model.

Nothing of a note goes anywhere until the plugin is added and run once by hand.

## Scope and organizations

A run is made of *scopes*, and a prompt never holds notes of two scopes:

- **Personal**: every note not under `orgs/`. Under More, "Within each folder only" narrows it to notes in the same
  top folder (`workspaces/Work/…` against `workspaces/Work/…`).
- **Each organization**: the notes under `orgs/<Org>/`, checked against the same organization's notes only. Off until
  "Organization notes" is turned on (under More in Simple), since it sends a team's words to the person's AI. There is
  no organization-level AI policy in the app today; when one comes (Home.md front matter, as the project tools'
  `plugins:` are), the runner's `orgAllowed` is where it is asked.

## Kept in the files

Markdown-first (docs/MARKDOWN_FIRST.md): the findings and dismissals are state kept beside the notes, so a git restore
keeps them and a dismissed disagreement does not come back on a fresh device.

- Personal: `Library/.glyph/contradictions.json`.
- An organization's: `Library/orgs/<Org>/.glyph/contradictions.json`, inside the organization's own folder, so its quotes
  never land in the personal file nor in a personal git backup that leaves the organization out.

```json
{
  "version": 1,
  "findings": [{"id": "…", "older": "<note id>", "olderTitle": "Plan", "olderQuote": "Release is Thursday",
    "newer": "<note id>", "newerTitle": "Standup", "newerQuote": "release moved to Monday",
    "what": "…", "confidence": 0.93, "found": "2026-11-02T09:00:00Z", "state": "open"}],
  "checked": {"<older id>|<newer id>": "<older revision>:<newer revision>"}
}
```

`state` is `open`, `dismissed` or `superseded`. A finding whose older note is gone is dropped on the next run. Where the
library has no folder Dart can reach (an Android SAF tree), the same JSON is kept in the device's storage instead, as
the library config is. The vault walk skips dot folders, so the file is never read as a note.

The settings (schedule, threshold, the two More switches, when the last run was) are the device's, under
`glyph-contradictions-settings`.

## Cost, progress and Stop

**Check now** counts the candidate pairs first and asks before a big run (lib/activity/activity_cost.dart `askJobCost`,
over two minutes: "48 note pairs · ~3 min"). The run is a job in the activity tray (`contradictions`, kind Writing, the
plugin's own): "Checking for contradictions · 12 of 48 pairs", with Stop, and at its end "2 notes may be out of date"
with View, which opens the page. Stop ends it after the request in flight; what it found by then is kept.

## Simple mode

The page shows the schedule, Check now and the findings. The threshold, Within each folder only and Organization
notes are under a More row that opens in place, as every plugin's fancier settings are (docs: glyph-simple-mode).

## Tests

`test/ai/contradictions/`: candidates (keys read, pairs scored, scopes never mixed, the cap, checked pairs skipped),
compare (the prompt, every way the JSON is refused), findings (the file read and written, dismissal remembered, Mark
superseded's markdown in a paragraph and under a list item), ai (Local only takes the device model and never a cloud
one), runner (a run with a fake AI end to end: findings kept, org notes never in a personal prompt, Stop).
`test/plugins/contradictions/`: the inline mark on the right line and gone once superseded, the sheet's buttons, the
page in Simple and Advanced, the home line; pictures in `build/feature-shots/contradictions/`.

## Touches outside its folders

Kept small, so the sessions working beside it meet as little as possible:

- `lib/plugins/types.dart` `Suggestion.open`, `lib/editor/items/suggestions.dart` and `note_plugins.dart`: a line's word
  may open something in its own context (the sheet) instead of running; `lib/editor/ai/blanks.dart` follows the new
  press's shape.
- `lib/plugins/registry.dart` `offersChanged()`: a found or settled finding asks the open note's line words again.
- `lib/plugins/built_in.dart`, `brands.dart` `ownPlugins`, `lib/market/market_items.dart` and
  `lib/settings/settings_css.dart`: the plugin, its own mark, and the new `slate` hue (every other hue was taken).
- `lib/root/root_contradictions.dart` (a part of ghost_root.dart, as the git backup's is), three lines in
  `ghost_root.dart` to make, start and dispose it, and one in `root_parts.dart` `_notices()` for the home line.

## Known limits

- The book is the Library's file, not the account's synced settings: a dismissal on the phone reaches the Mac through a
  shared folder or the git backup, not through sync.
- A nightly run on the device's model does not yet wait for the recorder as the summary queue does
  (lib/ai/summaries.dart's holds); a cloud AI takes no cores.
- A finding whose older line was edited since is not marked (its words are no longer there) until the next run.

## Open questions for Matt

1. Organization notes are off by default (a team's words go to the person's AI). On by default, or a team-wide switch
   in the organization's Home.md?
2. Nightly by default once added and run once, or When a note is saved?
3. The mark's word: "Out of date?" (now), "Superseded?", or "Newer note"?
4. Should findings and dismissals follow the account (synced settings) as well as live in the Library's file?
