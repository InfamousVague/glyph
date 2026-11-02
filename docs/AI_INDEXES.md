# Self-maintaining indexes

Matt, 2026-11-02, from a list of AI ideas: "Self-maintaining indexes: for any folder or org, the AI keeps an index
note (what's here, the key decisions, who owns what) and updates it as notes change. New teammates read one page
instead of fifty."

The code is `lib/ai/indexes/`; the tests `test/ai/indexes/`.

## 1. Where the index lives

**In the folder's own page**, not a note beside it. A folder already has a page (docs/TEAMSPACES.md,
lib/core/page_tree.dart): its `index.md`, at an organization's top its `Home.md`, else the note named as the folder
is. That page is what the sidebar opens for the folder and what a teamspace's home draws, so it is the one page a new
teammate reads first; a second "Index" note would be one more page to find. A folder with no page is given one when
the index is turned on (`<folder>/index.md`, `# <Folder>`, made the way a drag's order makes one: `PageMover`), and
an organization with no home page is given its `Home.md` from the template.

**The AI owns one fenced section and nothing else.** Everything the person wrote on the page stays theirs, byte for
byte:

```markdown
<!-- ghost:index updated=2026-11-02T14:05:00Z by=Claude -->
## What's here

Two or three sentences on what the folder is for.

### Planning
- [[Roadmap 2027]] — the year's three bets and who leads each.
- [[Hiring plan]] — two engineers in Q1, a designer in Q2.

### Meetings
- [[Standup 2026-11-01]] — the sync bug, and the release slipping a day.

## Key decisions
- 2026-10-28 · Move sync to the new server — [[Sync rewrite]]

## Who owns what
- **alice** — [[Roadmap 2027]], [[Sync rewrite]]

## Recently changed
- [[Standup 2026-11-01]] · 2026-11-01
<!-- /ghost:index -->
```

- HTML comments, because every markdown reader (GitHub, Obsidian, a text editor) hides or tolerates them, and the
  app's editor reads them as comments. A ```` ```ghost-index ```` fence would draw as a code block anywhere but here.
- A page without the markers gets the section appended at its end (after the person's words); a page with them has
  only what is between them replaced. A page with an opening marker and no closing one is left alone and the run
  fails ("The index's end marker is missing"), so a half-deleted section never eats the person's words.
- The opening marker carries when it was last brought up to date (`updated=`, UTC) and who wrote it (`by=`), so
  "Updated 2 h ago" is read from the file and is the same on every device and in a clone of the Library folder.

**Every claim links to its source.** Each line under a theme, each decision and each owner line names its note as a
`[[link]]`, and the links are written by the app from the notes it read, never from the AI's words: the AI answers
about note number 3, and the app writes note 3's title. A title the AI made up cannot become a link. `[[` and `]]` in
the AI's words are taken out.

## 2. The settings, in the page's front matter

Markdown-first (docs/MARKDOWN_FIRST.md): the switch and its options are the page's front matter, so they sync to the
team with the page and a clone keeps them.

| key | values | meaning |
| --- | --- | --- |
| `index` | `on` | the index is kept (absent or anything else: not) |
| `index-every` | `15m`, `hourly` (default), `nightly` | how often, at most, a dirty index is refreshed |
| `index-by` | a device id (lib/ai/summary_handoff.dart `thisDevice`) | the one device that writes it |
| `index-by-name` | `Mac`, `phone` | what the other devices say ("Kept by the Mac") |

## 3. Updating

- **Dirty.** The keeper listens to the library (the notes-changed signal: `NoteLibrary` is a `ValueListenable`). A
  note in the folder (at any depth, out of the trash and the archive, the page itself left out) whose `updatedAt` is
  after the index's `updated=`, or a note the index links that is gone, makes it dirty.
- **When.** A dirty index is refreshed once its `index-every` has passed since `updated=`: 15 minutes, an hour, or
  nightly (after 3 in the morning, on a day it was not yet refreshed). The keeper looks once a minute and as notes
  change; it never runs two refreshes at once.
- **Incremental.** A refresh reads only the changed notes (and the previous section): the previous section is parsed
  back into its entries (theme, one-liner, decisions per note), entries of notes changed or gone are dropped, and
  only the changed notes are sent to the AI. The overview is asked again from the themes and one-liners (short), and
  kept as it was when that ask fails. Owners and Recently changed are not the AI's: they are read from front matter
  (`authors:`, `owner(s):`, `assignee(s):`) and from `updatedAt`, for every note, every time.
- **Full rebuild** on demand (the More's Rebuild): every note read again.
- **Shown** as "Updated 2 h ago · Refresh" on the folder's index card; "Updating… 3 of 12" with Stop while it runs,
  and in the activity tray (lib/core/background_jobs.dart, kind `ai`, Stop wired to cancel).

## 4. The AI

Whatever is connected, in the order the app's assistant answers (lib/assistant/assistant.dart `chatBy`):

1. **Local only on** → the on-device model alone (lib/ai/backend.dart `generate`), never a cloud provider.
2. Else the assistant's provider: Claude (lib/claude/messages_api.dart) or another (OpenAI, Gemini, Aster, a custom
   endpoint) through its client, all read with `aiText` (lib/assistant/provider.dart).
3. Else the on-device model, where one is on the device.
4. Else nothing: the card says why ("Connect an AI in Settings › AI, or get a model for this device").

Notes go in batches (about 60,000 characters a request to a cloud model, 12,000 to the device's, each note cut at
6,000 / 2,500), and each answer is a JSON array the app validates item by item (a number it did not send, a missing
one-liner, or a malformed date is dropped, not trusted).

**Cost.** Before the first build of a big folder (or a Rebuild), the estimate is said and asked (lib/activity/
activity_cost.dart `askJobCost`): "48 notes · ~3 min", over two minutes asking first.

## 5. Organizations: one writer

An organization's folder page is an org note, synced to every member like any other. To keep two members' devices
from rewriting it at once, **only the device that turned the index on writes it** (`index-by:`). Every other device
reads the index as it syncs, shows "Kept by alice's Mac · Updated 2 h ago", and offers **Take over**, which writes its
own id into `index-by:` (the person chose it, so it is not a race: the last one to press it writes). A lease that
expired on its own would mean two devices deciding at once, from clocks that disagree, which is what this avoids.

Personal folders follow the same rule, so a person's Mac and phone never both rewrite it either.

## 6. Where it is turned on

- **A folder's menu** (right-click, lib/notes/folder_menu.dart): "Keep an index…", which opens the index's sheet.
- **A teamspace's home** (lib/orgs/ui/teamspace_home.dart): an "Index" card under the home page.
- **Simple mode** (`preferences.value.simple`): the card is one switch, "Keep an index", with "Updated … · Refresh";
  how often, Rebuild and Take over are behind More, which opens in place.

## 7. Tests

`test/ai/indexes/`: only the fenced section is rewritten; links point at real notes (made-up ones dropped);
incremental refresh sends only the changed notes; the single-writer rule; Local only picks the device and never a
cloud provider; the JSON validation; the card in simple mode. Screens in `build/feature-shots/ai-indexes/`. No test
calls a real AI.
