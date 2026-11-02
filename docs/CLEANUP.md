# Cleanup

The Cleanup plugin (Matt, 2026-11-02: "spawn a task making a 'cleanup' plugin that allows us to use whatever AI we
choose that's connected to clean up and sort the notes in a given folder") reads the notes of one folder, asks the AI
the person chooses what would tidy and sort them, shows every suggestion on a review screen, and applies only the ones
the person ticks. The AI thinks; Ghost.md does the moving, renaming and editing, with the app's own moves and the
Trash, and keeps a record of each run so the whole run can be taken back.

The code is `lib/plugins/cleanup/`. Off until added in the Market (`standard: false`), in the AI shelf.

## Where it starts

- **A folder's menu** in All notes (a right-click on its tile, chip or sidebar row, a finger's hold on a tile; lib/notes/
  folder_menu.dart): *Clean up with AI…*, while the plugin is on.
- **A folder page's ••• menu** in the spaces' tree (lib/notes/note_tree_spaces.dart): the same row, an organization's
  own workspace's page included.

The row stands after Rename… (and Set template…), before Move to's list of places.
- **Its page in Settings** (Settings › Cleanup, or the Market's Open): a folder picker, which lists every folder,
  personal or an organization's, the organization's own workspace included.

Each opens the plugin's page with the folder chosen. The page says, before anything runs, exactly what is sent and to
whom.

## The page

1. **Folder**: the one chosen, its path ("HelloTrade › Meetings"), how many notes are in it and in the folders under it.
2. **AI**: a picker of the AIs this device can ask *now*, defaulting to the app's own choice (Settings › AI ›
   Assistant, `AssistantChoice.chatBy`), then the on-device model:
   - Claude, where its plugin is on and a key is kept;
   - OpenAI, Gemini, Custom AI model, Aster, each where its plugin is on and set up (`AiPlugged.ready`);
   - **On this device**, the phone's or the Mac's own model, where the engine is here and a model is downloaded
     (lib/ai/available.dart `modelFor`).
   With **Local only** on (lib/core/preferences.dart), the cloud AIs are not listed at all (their plugins are held off
   by the registry, and the page asks again itself): only On this device. The list is read again as a run starts, and
   a run refuses a cloud AI while Local only is on. Nothing else is ever sent anywhere.
3. **What to do**: the passes, each a switch (below). In Simple mode only the three basic ones show and the rest wait
   behind a *More* row that opens in place (GHST-103).
4. **What is sent** (a footnote, word for word): "Each note's title, the folder it is in and its first 600 characters
   go to <AI>, 40 notes at a time. A note's whole text is sent only when Tidy asks to fix its formatting. Nothing is
   sent until you press Look for changes." (Local model: 12 notes at a time, 400 characters; "stays on this device".)
5. **Look for changes**: estimates first (below), then runs in the Activity tray with Stop.
6. **The review** (below), then **Applied** with Undo, and **Past runs**, each with Undo while it can be.

## The passes

| Pass | Default | What it proposes | How it is applied |
|---|---|---|---|
| **Sort** | on | Sub-folders and which notes go in each. Existing folders first; at most 3 new ones a run, and only directly inside the chosen folder unless *Deeper folders* is on. | New folders with `WorkspaceStore.addWorkspace(name, 'ink', parent)`; each note with the drag's own move (lib/notes/folder_drag.dart `moveCarried`), only where `folderVerdict` says `moves`. |
| **Titles** | on | A better title for notes with none, "Untitled", a date alone, or one that doesn't match the words. | The title line rewritten (`# New title`; a front matter `title:` set instead where the note has one; a heading put above a note whose title is its first line of prose, so no words go). Never a note other notes link to by its title. |
| **Duplicates** | on | Notes that are the same note twice: the same meeting copied, "X (shared)", a repeated paste. One is kept, the others merged into it. | The kept note gains any line of the others it does not already have, under `## From “<title>”`; the others go to the **Trash**. |
| **Tidy** | on | Broken Markdown: stray `#`, mixed list markers, empty sections, headings that skip levels. | A second ask with the whole note; accepted only if every word of the note is still there in the same order (formatting only). *Rewrite for clarity* (off; under More) lets the words change. |
| **Tags and links** | off | `tags:` for notes, and `[[links]]` between notes of the folder that are about the same thing. | Tags added to front matter `tags:` (lib/core/properties.dart `withProperty`); links as a last line, `Related: [[A]] · [[B]]`. |
| **Stale** | off | Notes that look abandoned or empty. | Into the **Archive** (`NoteLibrary.archive`). Never the Trash. |

Duplicates are also found without the AI across the whole folder, since a batch only sees 40 notes (text.dart
`duplicateGroups`): the same words after the title; or the same title once "(shared)", "copy", "(2)" are taken off and
runs of three words that overlap 80% or more, 55% where one of the two is marked a copy (a "(shared)" copy is often added
to after it was shared). The one kept has no copy mark, then is the longest. The app's groups come first, then the
AI's; a note is in one merge at most.

## The plan the AI answers with

One JSON object per batch. Notes and folders are given short refs (`n1`…`n40`, `f0` the chosen folder, `f1`… its
folders), never their ids, and the refs are mapped back; an answer naming anything else is dropped.

```json
{
  "folders":    [{"ref": "new1", "name": "Meetings", "parent": "f0"}],
  "moves":      [{"note": "n3", "to": "f2", "why": "A client call"}],
  "titles":     [{"note": "n1", "title": "Kiln pricing call", "why": "Untitled"}],
  "duplicates": [{"keep": "n4", "others": ["n5"], "why": "The same standup, shared"}],
  "tidy":       [{"note": "n6", "why": "Headings skip a level"}],
  "tags":       [{"note": "n7", "tags": ["pricing"], "why": "…"}],
  "links":      [{"note": "n7", "to": ["n8"], "why": "…"}],
  "stale":      [{"note": "n9", "why": "Empty since March"}]
}
```

Tidy's second ask answers `{"body": "<the whole note>"}` (or the note alone, a fence round it taken off).

**Validation** (plan.dart `readPlan`), each a test. The run never fails for a bad answer: what is wrong is dropped,
and the review says how many suggestions were dropped and why.

- No JSON in the answer, or not an object: the batch gives nothing (said on the review), the run goes on.
- A key of a pass that is off is ignored. Unknown keys are ignored.
- A ref the batch did not give is dropped. A note named twice in one pass keeps its first.
- `folders`: a name that is empty, over 60 characters, has `/`, or is the name of a folder already there (then the
  existing one is used); a parent other than `f0` (or a folder under it, with Deeper folders on); more than 3 new.
- `moves`: to the folder it is in already; to a folder outside the chosen one; to an organization other than the one
  the note is in, or out of one (checked again with `folderVerdict` as it is applied).
- `titles`: empty, the same as now, over 120 characters, more than one line, or a note linked to by its title.
- `duplicates`: `keep` among `others`, fewer than one other, a note already in another merge.
- `tags`: each tag `#`-less, letters, digits, `-`, `_`, `/`, at most 5 a note.
- `links`: to itself, more than 5 a note.
- Tidy's body: empty; formatting only (the default), any word changed, added or moved, where only the words of a
  heading with nothing under it may go; with Rewrite for clarity, under half or over twice the note's length.

## The review

Grouped by pass, each with its count and a switch for the whole group. Every item has its own tick:

- a move: the note's title, `Work › Inbox → Work › Clients`, and why;
- a new folder: its path, with the moves into it under it (unticking it unticks them);
- a title: `Old → New`;
- a merge: the kept note, the others (each "goes to the Trash"), and the lines the kept note gains;
- an edit (Tidy, tags, links): a line diff (lib/core/versions_diff.dart `diffLines`), the removed lines struck, the
  added ones marked;
- an archive: the note and why.

Everything is ticked except, on a plan of more than 30 items, the edits (Tidy, tags and links) and the merges, which
the person ticks for themselves. A pass's switch ticks or unticks its whole group; unticking a new folder unticks the
moves into it, and ticking such a move ticks the folder again. **Apply N** applies the ticked items; **Apply all** is a
row of its own under it, never the default, and no key presses either. **Discard** forgets the plan.

## Applying

In this order, so a note is moved last and verified where it ends: new folders, titles, edits, merges (the others to
the Trash), tags and links, archives, moves.

- **Every write is over the revision that was read** (`NoteLibrary.update(id, body, revision)`): a note changed since
  the plan was made is skipped and named, never overwritten.
- **Nothing is deleted.** A merged-away note goes to the Trash (`Trash.trashNote`), restorable for 30 days; an
  organization's note in the Trash stays live for every other member, since a member's Trash is their own. Archive is
  the Archive.
- **An organization's notes stay in it.** A move is made only where `folderVerdict` answers `moves` (same organization,
  or both personal): never `asks`, never across, never to the top. A folder made inside an organization's folder is
  the organization's.
- **Verified after.** Each moved note is read again (`NoteLibrary.get`): it must still exist, be out of the Trash, be
  filed in the folder the plan said (`WorkspaceStore.workspaceOf`), and be in the same organization as before. Each
  edited note must read back as the words written. Anything that does not is listed on the page as *Not where it
  should be*, by title, and counted in the record. Counts alone are never trusted (the 2026-11-01 connector incident).

## Undo and the record

Each applied run is a record in the plugin's storage (`glyph-cleanup-runs`, the last 20 runs, this device's): when,
which folder, which AI, and for every change what it was before and after (a move's old folder, an edit's old body and
the revision it left, a trashed note's id, an archive, a new folder's id). **Undo** on the toast and on the page takes
the whole run back in one action, in the reverse order: moves back, archives out, the Trash's notes restored, bodies
written back over the revision the run left (a note changed since is left as it is and named), new folders removed if
nothing is filed in them. Undo stays on a past run until it has been undone.

## Large folders

- 40 notes a call (title, folder, first 600 characters), 12 and 400 for the on-device model. Whole bodies only for
  Tidy's second asks.
- The notes are batched in title order, so copies with the same title meet in one batch.
- **The estimate first** (lib/activity/activity_cost.dart `askJobCost`): "120 notes · 3 asks of Claude · ~1 min". Over
  two minutes it asks Start / Cancel; under, it runs.
- **The Activity tray** (lib/core/background_jobs.dart): one job, `cleanup:<folder>`, kind AI writing, the plugin's
  mark, "Reading 40 of 120 notes", with **Stop**. Stop keeps what the finished batches found and shows it for review.
- A batch the AI fails is said on the review ("1 of 3 asks failed: Claude is out of credit"); the others stand.

## Privacy

Only what the page says is sent, only to the AI the person chose, with the person's own key and through that AI's
own plugin (lib/assistant/), counted against its spending limit. Local only leaves only the on-device model. The
plugin itself declares no network permission: it reaches no host of its own.

## Tests

test/plugins/cleanup/: plan_test (the scope, the prompt, every validation rule, the batches joined), text_test (titles,
the formatting-only check, tags and links, duplicates and merges), run_test (batches, Tidy's asks, a failed ask, Stop,
the estimate, the tray's job), ai_test (connected AIs, Local only, the asks through each provider's client, the limit),
apply_test (apply, read back, Undo, a note changed since, an organization's boundary, the Trash, a move that did not
land, the record), review_test (the page, the review, ticks, Apply, Undo, Simple, Local only, the folder menu's row).
Pictures into build/feature-shots/cleanup/ with --update-goldens. No real AI is asked: the AIs are scripted.

## Not in this version

- The Claude connector (mcp/). When it comes, it must return a plan and apply only on a second call naming the
  approved item ids.
- A run that continues on another device.
- A row on a phone's folder sheet (lib/notes/workspace_sheet.dart): on a phone it is the tile's hold menu in All notes
  by folder, or the plugin's page.
- The records live in the plugin's storage on this device, not in the Library folder.
