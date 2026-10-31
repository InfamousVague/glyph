# Markdown first: what a Library folder in git gives back

Matt, 2026-10-31: "We're in a really solid spot with the app to launch to the public. Go through all of our new features
and address any that are not savable in the markdown files themselves and our custom markdown, and address how we can
move those things over. Our value proposition is that we can be hosted anywhere for super cheap since it's all simply
markdown files; the whole backup can be done from git. I also want to add a plugin to back up on git."

This document is the audit that followed (ten areas, each read by one agent and checked by a skeptic against the code),
the gaps it found, the target layout, the migration plan and the design of the git plugin. Nothing here was built yet.
Items the skeptic refuted are left out; where the skeptic corrected a reading, the correction is what stands.

## 1. The principle

The test for every piece of state the app keeps is one question: if a person had ONLY the Library folder (the markdown
files and whatever plain sidecars sit beside them) in a git repository, cloned it onto a fresh device and pointed
Ghost.md at it, what would they lose?

"Portable" here means exactly that. The Library folder is the unit of backup. A fresh device opening a clone of it must
show the same notes, in the same folders, with the same pins, history, tickets, boards, canvases, recordings and
pictures. What belongs to the person's account (keys, sign-ins, share links) or to a device (where it was scrolled
to, which tabs were open) may stay out, but the document must say so. What belongs to the library and is kept
anywhere else today is a gap.

Three places hold state that is not the files:

- the one sealed preferences blob (`glyph-preferences`, lib/core/preferences.dart `Preferences.toJson`), part of which
  syncs between a person's devices (lib/sync/prefs.dart `syncedPrefs`) and part of which does not;
- device storage (`SharedPreferences` through lib/core/stored.dart and stored_device.dart), keyed `glyph-*`;
- the secure store (lib/account/keystore.dart, lib/sync/sealed_keys.dart) and glyph-api.

The audit's job was to sort every field, flag, list, ledger, claim, cache and counter into one of: already in the
file, should be in the file, should be in a committed library config, should stay transient, must stay secret, or
needs Matt.

## 2. The library on disk today

`<app data>/Library/` is the library (tauri/src-tauri/src/paths.rs `LIBRARY`; the Flutter app embeds the same Rust
library through native/src/lib.rs). A chosen folder (Settings › Library) or an Android SAF tree can stand in for it
(library/root.rs `Root::{App, Folder, Tree}`).

| Path | What it holds |
|---|---|
| `Inbox/<Title>.md` | A note. The Rust library writes five keys into the file's first front matter block: `id`, `created`, `pinned`, `archived`, `source` (library/mod.rs `stamp`, `set_front`). Everything after that block is the body the app edits. |
| `workspaces/<Workspace>/[<Sub>/]<Title>.md` | A note filed in a personal folder. The directory mirrors the folder's name and nesting (lib/core/note_folders.dart). |
| `orgs/<Org>/[<Workspace>/]<Title>.md` | A team note, plaintext on disk like any other (lib/team/folders.dart). |
| `<Title>.versions` beside a note | Plain-text version history: `v<n> <ISO> <who> <hash>` head lines and `=N`/`-`/`+` diff lines, a full snapshot every 50 (lib/core/versions_file.dart). Renamed, moved and deleted with the note (library/versions.rs). |
| `.glyph/index.sqlite` (+ `-wal`, `-shm`) | The notes index: a cache, dropped and rebuilt whenever the files disagree (library/index.rs). For a chosen folder it lives at `<app data>/index/<key>.sqlite` instead; for a SAF tree the whole `.glyph/` lives at `<app data>/trees/<key>/`. The voice-command undo log (`command_mutations`) is the one thing kept there and nowhere else. |
| `.glyph/library.json` | `{version, created, movedFrom?, movedNotes?}`: the library's birth and the 2025 move from the SQLite store (library/move_in.rs). |
| `.glyph/notes/<id>.json` | `{recordingMs, segments:[{text,startMs,endMs}], formatted, formattedFor, formattedModel}` (library/sidecar.rs). The recording's length and timed phrases, and the on-device model's formatted copy. Plain JSON, keyed by the note id that is also in the note's front matter. |

A note with page-level properties (a ticket, a notebook, a journal, a canvas, a geotagged note) is on disk as TWO
front matter blocks: the library's, then the page's, which the Dart side writes at the top of the body with
`withFrontMatterValue` (lib/core/properties.dart). The Rust test
`a_tickets_front_matter_is_the_pages_and_is_kept_whole` asserts this layout and tauri/docs/LIBRARY.md admits that an
app reading only the first block shows the second as text.

Beside the Library, under `<app data>/`, and NOT inside it:

| Path | What it holds |
|---|---|
| `images/<uuid>.jpg` (+ `.jpg.ocr.txt`) | Pictures notes link as `image/<name>` (the folder and the link do not even share a name). |
| `images/files/<uuid>.<ext>` (+ `.ocr.txt`) | Attachments notes link as `file/<name>` (lib/files/attachment_store.dart). |
| `video/<uuid>.mp4` | Films notes link as `video/<name>`; never synced; `video/.orphans.json` is the sweep's memory. |
| `recordings/<note id>.wav` | A note's tape, linked to the note by file name alone (native/src/kept/recordings.rs). 16 kHz mono 16-bit: ~115 MB an hour. |
| `team/<account id>/<note id>.json` | A team note's CRDT document (lib/team/docs.dart): this device's bookkeeping, rebuilt from the org log. |
| `jobs/`, `models/`, `meet/`, `carry/`, `library-root.json`, `index/`, `trees/` | Write-up progress, whisper/LLM models, Meet decode scratch, the Tauri carry, which library this device opens, chosen-folder indexes, SAF-tree dot folders. |

So a git repository of `Library/` today carries the words, the five managed keys, every page-level key, the
`.versions` history and (if `.glyph/` is committed) the transcripts, but it carries dead `image/…`, `file/…`,
`video/…` links and no tapes; and it carries nothing of the folder metadata, the trash, which notes are meetings, or
which notes keep history.

## 3. The inventory

One table per area. "Where today" uses the audit's classes: markdown-body, front-matter, sidecar-plain,
sidecar-binary, library-dot-glyph, synced-settings, device-storage, secure-store, server, derived-cache.
Recommendations: keep, move-to-front-matter, move-to-markdown-body, move-to-plain-sidecar, move-to-library-config,
keep-transient, keep-secret-out, needs-decision. Effort: S under a day, M a few days, L a week or more.

### 3.1 Notes, folders, notebooks and the library on disk

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| Note body (the words) | markdown-body (library/mod.rs `save_note`) | Nothing | keep | No change | S |
| Note id (`id:`) | front-matter, written on first save and every rewrite; a foreign file never saved by the app has its id in the index only (index.rs `index_file`), and `set_front` rewrites only the key it changes, so a pin on an Obsidian file still writes no `id:` | Nothing for app-made notes; a foreign file gets a different id on a fresh device, so anything keyed by id in the preferences no longer points at it | needs-decision | In `set_front`, when `front.get("id")` is None add `id:` beside the changed key (one rewrite that already happens). For never-touched foreign files, key the preference maps by path when `id_in_file = 0`. Note `id_in_file` is written but read by nothing yet | S (first), M (second) |
| Created time (`created:`) | front-matter | Nothing (a foreign file without one falls back to mtime) | keep | No change | S |
| Updated time | derived-cache: the file's mtime (index.rs `entry.modified_ms`), by LIBRARY.md's choice so a save rewrites no date; pins keep the mtime (`keep_modified`). Read by list order, 'touched' labels, rule-run ids. Journal month order does NOT depend on it (lib/book/journal.dart `stampOf` falls back to `createdAt`) | `git checkout` sets every mtime to now: everything shows touched 'just now', list order collapses, 'Yesterday' labels wrong until edited | needs-decision | Either the git plugin restores each file's mtime from its last commit on checkout (nothing in the file changes, zero sync risk), or `save_note` writes `updated: <ISO>` on body saves only and `index_file` takes the LATER of the key and the mtime (so a sed or Obsidian edit still moves the note up). Not "prefer the key": that would freeze externally edited notes | S |
| Pinned (`pinned: true`) | front-matter (`set_starred`) | Nothing | keep | No change | S |
| Archived (`archived: <ISO>`) | front-matter (`set_archived`) | Nothing | keep | No change | S |
| Source (`source: capture`) | front-matter (`born_from`) | Nothing | keep | No change | S |
| Revision counter, command-mutation undo log | derived-cache (index.rs `INDEX_SCHEMA`, mutations.rs) | Revisions restart at 1 (harmless); recent voice-command undos gone | keep-transient | Ignore `.glyph/index.sqlite*` | S |
| The page's front matter as a SECOND `---` block | markdown-body (mod.rs `save_note`, frontmatter.rs `split`, lib/core/properties.dart `withFrontMatterValue`) | Nothing in git, but the pitch fails: Obsidian shows the second block as literal text (Properties sees only id/created), GitHub renders a table then loose `key: value` lines, Hugo/Jekyll read only the first. A ticket written elsewhere with one block has its `GHO-12` read as the note's id. An Obsidian vault file whose only block holds `tags:` has that block eaten by the library | move-to-front-matter | One block per file. Phase 1: every reader (index.rs, Dart `frontMatterValue`/`ticketOf`, web frontMatter.ts, MCP `keepKeys`) accepts the merged shape and reads a ticket's key from `issue:` first, legacy `id:` only when it matches `<KEY>-<n>`. Phase 2 (every device on phase 1): the writer splices `id`, `created`, `source`, `pinned`, `archived` into the page's block (frontmatter.rs `set` keeps unknown keys byte for byte) and the ticket key becomes `issue: GHO-12`. Not `key:`: that already means the project key on a notebook (`notebookKey`). Strip the library keys on read into `Note` and re-add on write so sync and the CRDT are unchanged | L |
| Recording length and phrases, formatted copy (`.glyph/notes/<id>.json`) | library-dot-glyph (sidecar.rs). Backup-to-drive does NOT carry it (`Library::texts` lists only .md and .versions); the export zip does | Only if `.glyph/` is ignored: the tape's timing and the formatted copy. Not derivable without re-transcribing | needs-decision | Short term: commit `.glyph/notes/*.json` and `library.json`, ignore `index.sqlite*` (export.rs already makes exactly this split); teach `Library::texts` to include them so the drive backup does too. Longer: `<Title>.transcript` beside the note, handled by `rename_note_file`/`delete_file` as `.versions` is, a new `FileKind`. Drop `formatted*` (a model-run cache) | S now, L for the sidecar |
| `.glyph/library.json` | library-dot-glyph (move_in.rs) | The birth date and migration record; nothing functional | keep-transient | Commit it (tiny) | S |
| The index, LinkIndex, TagIndex, NoteFacts, NoteMarks, RecordCache | derived-cache | Nothing; rebuilt | keep-transient | Ignore `.glyph/index.sqlite`, `-wal`, `-shm` | S |
| Versions file `<Title>.versions` | sidecar-plain | Nothing | keep | No change. Not `.md`, so never indexed as a note | S |
| Which notes keep a version history (`preferences.versions`) | device-storage: `Preferences.versions` is in `_keys` but NOT in `syncedPrefs` (lib/sync/prefs.dart; nor the Tauri `SYNCED_PREFS`), so despite versions_record.dart's comment the choice never travelled. Org notes default on, personal notes default off; only exceptions are stored | Personal notes that had history on stop keeping new versions after a restore (the `.versions` file is still readable). Already true today on a person's second device | move-to-front-matter | `versions: true|false` as a library-managed key (a `set_keeps_versions` beside `set_starred`), read first; else the device map; else the default. Treat an existing `.versions` beside a personal note as `true` during the transition, and have `setKeepsVersions(on)` keep v1 at once so the file exists. Fixes the cross-device bug at the same time | S |
| Folders: the workspace list (id, name, hue, parent) | synced-settings (`KeptWorkspaceStorage.write`: both the list and the filing map). The directory is only a mirror written by NoteFolders; NOTHING reads personal folders back from paths (only org folders via `TeamFolders.fileAt`, and the Obsidian import). `folderIdFor` (since 2026-10-23) derives a folder's id from account/org + lower-cased names, so re-derived ids match for folders made since; older ones are random | No folders at all in the sidebar, every note unfiled although its file sits in `workspaces/Work/`, every hue gone, empty folders gone | move-to-library-config | (1) An adopter at library open: for each note under `workspaces/A/B/`, make A and A/B with `folderIdFor` ids and file it (the `fileAt` rule applied to personal folders). (2) `Library/.glyph/config.json` `workspaces: {"Work": {"hue": "moss"}, "Work/Clients": {"id": "w-8ab1"}}` keyed by path, `id` only where it differs from `folderIdFor`; a `.keep` in empty directories. The preference stays the live sync channel | M |
| Filings: note id to workspace id (`preferences.workspaces.notes`) | synced-settings; redundant with the path for every note that has a file | Every note shows unfiled until the adopter above runs | keep | The path is the truth: fill the map from paths for any note it lacks (part of the adopter) | S (with the adopter) |
| Current workspace filter (`glyph-workspace-current`) | device-storage | The list opens at All | keep-transient | No change | S |
| Trash (`preferences.trash`) | synced-settings (`KeptTrash.trashNote`); the file is untouched until Empty or the 30-day purge; nothing on disk marks a trashed note | Every trashed note comes back live; the 30-day clock is lost; the repo "backs up" what the person deleted | move-to-front-matter | `trashed: <ISO>` as a library-managed key exactly like `archived:` (`set_trashed`, mtime kept, an index column), with `KeptTrash` a view over the index and the preference written in parallel for a release. Not a `Trash/` folder: the scan indexes every .md regardless of folder, old builds would list it, and moving files churns `.versions` paths and team rows. Trashing never conflict-copies: `set_front` keeps mtime and sync only copies when bodies differ. The purge keeps exempting org notes | M |
| List order | derived-cache | Only as far as `updated` | keep | No change | S |
| Open tabs and tab groups (`openNotes`, `tabGroups`) | synced-settings | Tabs open empty | keep-transient | No change | S |
| Reading positions (`glyph-note-places`, `-bookmarks`, `glyph-book-spots`, `glyph-folds`, `glyph-note-zoom`, `glyph-recent-notes`) | device-storage | Notes open at the top; folds reset | keep-transient | No change | S |
| Sidebar and list view state (`glyph-tree-*`, `glyph-browse-view*`, sort keys, `glyph-sidebar-list-shown`) | device-storage | Defaults | keep-transient | No change | S |
| Notebooks: `book: true`, the `[[link]]` index, chapter numbers, `key:`, `statuses:`, `cycles:`, `page-template:`, `templates:` | markdown-body / front-matter | Nothing (subject to the two-block defect); the next ticket number is `nextIssueId` over every note, never stored | keep | No change beyond the single-block merge | S |
| Journal entries (`journal: true`, `template:`, `entry-place: true`, entries with `date:`) | markdown-body | Nothing | keep | No change | S |
| Untouched-entry drafts (`glyph-entry-drafts`) | device-storage | An untouched entry is kept instead of taken back | keep-transient | No change | S |
| Daily notes setup (`preferences.more.dailyNotes`) | synced-settings: `{folder: <workspace id>, notebook: <note id>, template: <name>}` (only `template` is a name) | Today goes to the default folder and template | move-to-library-config | `config.json` `dailyNotes: {"folder": "Daily notes" (a path), "notebook": "<note id>" (ids are in the files), "template": "A day"}`; translate the path to an id on read | S |
| Smart notebooks (`preferences.more.smartNotebooks`) | synced-settings | The saved searches | move-to-library-config | `config.json` `smartNotebooks: [{id, name, query}]`. Not a note per search: every non-dot `.md` is indexed as a note and would show in lists | S |
| Templates (the Templates notebook, `templates: page`, `page-template:`, `folders:`) | markdown-body | Nothing | keep | No change | S |
| Tickets: type, key, status, assignee, priority, due, estimate, labels, parent, blocked-by, duplicate-of, cycle, watchers, spent, remind | front-matter | Nothing (subject to the two-block defect) | keep | No change beyond the merge | S |
| Time log (`## Time` lines + `spent:`) | markdown-body | Nothing | keep | No change | S |
| Running ticket timers (`ticketTimers`) | synced-settings | A timer running at the moment of loss is not logged | keep-transient | No change | S |
| Rules fence (```rules) | markdown-body | Nothing | keep | No change | S |
| Rule-run ledger, sweep claim, blocked-since (`ticketRuleRuns`, `ticketSweep`, `ticketBlocked`) | synced-settings | Coordination only | keep-transient | No change (see 3.4 for the restore seed) | S |
| Ticket history timeline | derived-cache from `.versions` | Nothing beyond `.versions` | keep | No change | S |
| Merge undo records (`glyph-ticket-merges`), ticket events told (`glyph-ticket-events-<account>`) | device-storage | Undo of a merge gone; a notification batch could re-send once (server dedupes) | keep-transient | No change | S |
| Digest claim and settings (`ticketDigest`, `ticketDigestSettings`) | synced-settings | Digest time reverts to 8:30 | keep-transient | No change (a person's preference) | S |
| Comments (`[^c1]` + ```comments) | markdown-body | Nothing | keep | No change | S |
| Boards, Gantt, queries, buttons, reminders, tags, aliases, block ids, attachment links | markdown-body | Nothing | keep | No change | S |
| Drawn heights (`glyph-board-heights`, `glyph-mermaid-heights`) | device-storage; a board fence may carry `height=18` itself | Default heights | keep-transient | No change | S |
| Canvases | markdown-body: `---\ntitle: …\n---` then JSON Canvas 1.0 (lib/canvas/json_canvas.dart `canvasNoteBody`); no `.canvas` anywhere. On disk: the library's block, the page's block, then JSON | Nothing in git, but Obsidian shows a wall of JSON (it opens only `*.canvas`) and GitHub shows text | needs-decision | Phase it: keep `.md` as the stored form now; the git plugin and the static publisher emit a derived `<Title>.canvas` (pure JSON Canvas, title from the file name) beside each canvas note, marked generated. Switch the stored form to `.canvas` only after readers ship (the vault walk admits only `.md`; the importer absorbs `.canvas`; team canvases are CRDT types; old builds would not list it) | M (derived file), L (stored form) |
| Geotag (`location:`, `place:`) and pending/refused state | front-matter; pending fix and refusal in device storage | Nothing; a pending tag for a draft is dropped | keep | No change | S |
| Meeting marks (`preferences.meetings`) | synced-settings, five writers (capture screen, voice wiring, capture route, live captions, meet_in). The file says `source: capture` but not "a meeting" or when | Meeting notes become ordinary notes; the shelf is empty | move-to-front-matter | `meeting: <ISO start>` in the page's block from every writer; an index column read at index time (sync's `recordingStaysHere` runs over rows); the map as a derived index for a release. Add the key to `undraftable`'s list | M |
| Snippets (`preferences.snippets`) | synced-settings | Back to the defaults | move-to-library-config | See 3.5: a `Snippets` note with a ```snippets fence (a dot-folder file is not indexed or synced between devices) | M |
| Attachments the notes point at (recordings, images, video, files) | sidecar-binary, SIBLINGS of `Library/`; links say `image/`, `file/` but folders are `images/`, `images/files/` | Every picture, film, PDF and tape | needs-decision | Move the stores under the library at the names the links already use: `Library/image/`, `Library/file/`, `Library/video/`, `Library/recordings/`; read the old folders as a fallback for one release; one-time move at open; Kotlin twins (MeetingService.kt, TapePlayer.kt) updated; backup and export write the same names so a backup is also a library | L |
| Where the library is (`library-root.json`), chosen-folder index, `kept-times.json` | device-storage | The device opens its own folder; the index rebuilds | keep-transient | No change | S |

Dropped after the skeptic's check: the starter-examples flag (lib/root/ghost_root.dart already seeds nothing when the
restored library holds notes).

### 3.2 Sync, account, preferences and team notes

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| Appearance and behaviour preferences (theme, experience, homeLayout, density, typeface, dock, code themes, wisp, sounds, notifications, …) | synced-settings | Defaults until the account syncs in | keep | Account preference, not library content | S |
| Recording behaviour (refine, quietStop, review, summaries, writeUp, syncMeetingRecordings) | synced-settings | Defaults | keep | No change | S |
| Device-only preferences (uiScale, sidebarStyle, meetingSound, localOnly, formatModel, menuBarAlways, soundVolume, tagNewNotes, lookUpBlanks, autoFill) | device-storage (in the blob, not in `syncedPrefs`) | Defaults, correctly | keep-transient | No change | S |
| Share links (`preferences.shares`: id, KEY, sent, lacked, place, places, recording, audio) | synced-settings; the key exists nowhere but here and the link. The local blob is plain JSON (sealing is for the wire only) | Links keep serving the last blob but the owner cannot update, list or stop them from the restored device | keep-secret-out (key) + move-to-front-matter (marker) | See 3.7: the sites model (meta sealed under the account key in context `share:<id>`) plus a non-secret `share: <id>` library-managed marker. Never a key in front matter or the repo | M |
| Calendars (`more.calendars`: iCal URLs, Google refresh token, ticked, todos) | synced-settings, in the CLEAR in the device blob (unlike `sealedKeys`) | Re-add / re-sign-in | keep-secret-out | Never in the library. Move `google.refreshToken` (and each iCal URL) into `sealedKeys` so it is not plaintext on disk | S |
| Webhooks (`more.webhooks`: url, events, scope, secret) | synced-settings, plaintext on device | Re-create; receivers need new secrets | keep-secret-out / needs-decision | Keep out of the library. Optionally seal each `secret` into `sealedKeys`. Committing `{id, url, events, scope}` to `config.json` is Matt's call: the URL is where whole notes are POSTed | S |
| Sealed keys and connections (`more.sealedKeys`) | synced-settings, each value AES-GCM sealed again | Every API key and connection re-entered unless signed in | keep-secret-out | No change; excluded from any export | S |
| Unknown preference keys (`Preferences.more`, `PrefsBridge.unknown`) | synced-settings | Whatever a newer build kept | keep | No change; this is what makes the migration safe across builds | S |
| Account sync bookkeeping (`glyph-sync-<account>-notes`: cursor, marks, before-bodies) | device-storage; `mark()` and `before` embed whole note bodies in plaintext SharedPreferences | A fresh device re-pulls; a local note that differs from the server copy with no mark becomes a conflict copy, so restore-then-sign-in can double edited notes | keep-transient | Keep off the files. Follow-ups: (1) on sign-in over an existing library, use `mergedWords` with the common `.versions` hash as the base before falling to a conflict copy (the repo HAS a merge base the device bookkeeping lacks); (2) store `mark` as a hash, not the body | M |
| Settings sync bookkeeping (`-prefs`, `-prefs-held`) | device-storage | First pass takes the account's settings whole | keep-transient | No change | S |
| Applied sealed-key times (`-keys`), keys-sync switch (`glyph-keys-sync`) | device-storage | Re-applied, idempotent | keep-transient | No change | S |
| Notes lately out of a team (`-left-teams`) | device-storage | Guard against pre-2.3.79 peers lapses | keep-transient | Retire once no old build remains | S |
| Team channel state (`-team-<org>`) | device-storage | Re-reads the org feed from 0 | keep-transient | No change | S |
| Organizations list cache (`-orgs`) | device-storage | Re-fetched | keep-transient | No change | S |
| Notifications feed cache (`-notifications`) | device-storage | Re-fed; an unsent self row lost | keep-transient | No change | S |
| Other device keys (`glyph-handoff-device`, `glyph-join-held`, `glyph-phone-notices`, `glyph-live`, `glyph-plugins`, `glyph-versions-unsent`, `glyph-slack-channels`, `glyph-slack-meetings`, `glyph-slack-meeting-queue`) | device-storage (there is no `glyph-words-owed` key; `KeptFiles.owed()` is a method) | New device id, filter resets, an invite link re-opened | keep-transient | No change | S |
| Session and the three account keys | secure-store | Sign in again with password or recovery code; the files need no key | keep-secret-out | Say in the docs: the backup is of the LIBRARY; the account (handle + password/recovery sheet) is the one thing outside it | S |
| Organization keys | secure-store (memory for the session) | Re-read from the server wrap after sign-in | keep-secret-out | No change | S |
| Team note CRDT document (`<data>/team/<account>/<note>.json`) | derived-cache, deliberately outside the library | Rebuilt by `adopt`; words typed here are in the .md and reconciled | keep-transient | No change; never in the repo (it holds one person's account id) | S |
| Org workspace identity (`org-<orgId>` vs `orgs/<Name>/`) | synced-settings + server; the folder alone cannot be re-linked | Without sign-in `orgs/Acme/` is an orphan folder of plain notes; after sign-in the rows re-link by note id, but a renamed org makes a second folder | move-to-library-config | `config.json` `orgs: {"orgs/Acme": {"org": "<id>", "name": "Acme" (raw name), "hue": "sea"}}` written by `ensureOrgWorkspace`; `reconcileOrgWorkspaces` matches by id before name | S |
| Team note markdown completeness (words, `.versions` with handles, comments with handles, recording, pictures) | markdown-body / sidecar-plain | A member keeps everything but per-keystroke authorship, membership, colours, presence | keep | Already portable | S |
| Membership, roles, invites, AIs, colours, server notifications | server | Not in the library by design | keep-secret-out | Document the second backup: the server's SQLite is the other half of "hosted anywhere" | S |
| Live presence | server (relay) | Nothing | keep-transient | No change | S |
| Line-wise merge of words (`mergedWords`) | derived-cache | Nothing | keep | Reuse for restore-then-sign-in with `.versions` as the base | M |

### 3.3 Tickets: planning and queue

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| Ticket and notebook front matter as a second block | front-matter (two blocks) | See 3.1 | needs-decision (one block) | As 3.1; ticket key becomes `issue:`; MCP `keepKeys` returns `type`/`id` so the uuid key must not be `id` in the page's sense | L |
| Ticket key and type (`id: GHO-12`, `type: ticket|epic`) | front-matter | Nothing | keep | Renamed to `issue:` with the merge, read-both first | S |
| Next ticket number | derived-cache (`nextIssueId` over every body, Trash files included) | Nothing; recomputed | keep | The git plugin must commit trashed notes' files too or a number can be reused | S |
| Workflow statuses (`statuses:`), a ticket's `status:` | front-matter | Nothing | keep | No change | S |
| Cycles (`cycles:` rule, `cycle:`, `type: cycle` notes) | front-matter | Nothing | keep | Note in TICKETS.md that `cycles:` must be a flow map, not indented YAML | S |
| Estimate, priority, labels + `label-colours:`, component | front-matter | Nothing | keep | No change | S |
| Triage state (`triage`, `triaged`, `via`, `form`, `answered`, `email`, `from`, `duplicate-of`) | front-matter | Nothing | keep | No change | S |
| Parent/epic, blocked-by, milestone links, milestone notes | front-matter | Nothing | keep | No change | S |
| Sub-ticket order | derived-cache: the library's list order (`ORDER BY modified_at DESC`), so mtime | Scrambled by a checkout; nothing written is lost | keep-transient | Sort `subTicketsOf` by `issueNumber` so the order is a pure function of the files | S |
| Stale-after (`stale-after:`) | front-matter | Nothing | keep | No change | S |
| Board columns and planning views (query `group:`, `columns:`, `show:`, `cycle:`) | markdown-body | Nothing | keep | No change | S |
| Selection (bulk bar), triage narrowing | in memory only | Nothing | keep-transient | No change | S |
| Status history, age, stale days, done-on, burndown input | sidecar-plain (`.versions`) with a fallback on mtime; nothing writes `done:` | Team tickets keep history; personal tickets without versions read age 0, never stale, done-on today after a checkout | move-to-front-matter | One `withStatus(body, status, today)` helper in properties.dart that sets `status:`, `status-since: <day>` on change, `done: <day>` when the category is done (removed on reopen); route every `withProperty(..., 'status')` site (panel, bulk, lane drag, triage, merge, carry, mcp/server.ts) through it. Read order: versions, then written keys, then mtime. Add both to `_unsaid` | S (with the helper) |
| Note `created:` day (triage order) | front-matter | Nothing | keep | Moves into the one block | S |
| Which personal notes keep versions | device-storage (see 3.1) | History stops for personal tickets | move-to-front-matter | As 3.1 | S |
| Who `me` is (`queryMe`) | server (the account's handle) | My tickets is empty until signed in | keep | Optionally `me: matt` in `config.json` for a library opened with no account | S |
| Ticket membership in a notebook, the notebook's `key:` | markdown-body | Nothing | keep | No change | S |
| Ticket templates (`{{next-id}}`) | markdown-body | Nothing | keep | No change | S |
| Derived indexes (index.sqlite, NoteFacts, RecordCache, PlanningIndex, TicketHistory, people/labels) | derived-cache | Nothing; `modified_at` and `revision` are the two non-faithful columns | keep-transient | `.gitignore` the index, keep `.glyph/notes/` tracked | S |

### 3.4 Tickets: automation and team features

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| Rules text (```rules fence) | markdown-body; a rule's id is a hash of its text | Nothing; acting needs the channel webhook, the Claude key, an account | keep | Document the grammar in docs/TICKETS.md | S |
| GitHub repos (`github:`), on-merge (`on-merge:`) on the notebook | front-matter | Nothing | keep | No change | S |
| Ticket fields, notebook key/workflow | front-matter | Nothing | keep | Commit trashed files (the counter) | S |
| Rule run ledger (`ticketRuleRuns`, incl. `merge:` ids) | synced-settings | Change-triggered runs are safe (ids carry `updatedAt`); clock rules re-fire once for every already-overdue ticket; an on-merge move re-applies once | keep-transient | Seed, never store: when `prefs.more` has NO `ticketRuleRuns` key (presence, not emptiness) and the account's prefs have arrived (or there is no account), claim `due:<day>` ids for already-overdue tickets and `mergeRunId` for already-merged PRs without running them | S |
| Blocked-since clock (`ticketBlocked`) | synced-settings | Restarts from the restore date | keep-transient | When absent, derive `began` from `ticketHistory` (last change into a Blocked status) or the first version with `blocked-by` naming a current open blocker; seed like the ledger | S |
| Sweep claim (`ticketSweep`) | synced-settings | A device claims again | keep-transient | No change | S |
| Running timers (`ticketTimers`) | synced-settings | A running timer is unlogged; logged minutes are in the note | keep-transient | No change | S |
| Time log lines, `spent:` | markdown-body / front-matter | Nothing | keep | Optional panel hint when `spent:` and the lines disagree | S |
| Watchers (`watchers:`) | front-matter | Nothing | keep | No change | S |
| Ticket-event batches owed and told (`glyph-ticket-events-<account>`) | device-storage | An unsent batch never told; the server dedupes by id | keep-transient | No change (holds comment text and handles) | S |
| Ticket-event rows (watchers' bell) | server | Past notifications gone; the record is the note and `.versions` | keep-transient | No change | S |
| Rule `notify` rows and digest rows | server | Past bell rows | keep-transient | If a durable trail is wanted: an off-by-default rules log written as the digest note is, one note a month | M |
| History timeline | sidecar-plain (`.versions`) | Enough to rebuild exactly (quick edits collapse into one entry) | keep | Commit `*.versions`; on a git conflict in one, run `mergeFiles(ours, theirs)` rather than a line merge | S |
| Per-note keeps-versions switch | device-storage (see 3.1) | Personal timelines freeze | move-to-front-matter | As 3.1 | S |
| Digest settings and claim | synced-settings | Defaults | keep-transient | No change | S |
| Digest note | markdown-body | Nothing | keep | The pattern for a rules log | S |
| Duplicate-of and merged content (`## Merged from`, moved comments) | front-matter / markdown-body | Nothing | keep | No change | S |
| Duplicate hints cache | derived-cache | Nothing | keep-transient | No change | S |
| Merge undo records (`glyph-ticket-merges`) | device-storage; `keepVersion` is gated on `keepsVersions` | For personal notes without versions, the pre-merge text exists only on the device | needs-decision | Keep a version unconditionally for the two notes whose words change substantively (target and duplicate); keep the gate for link-rewrite notes (a merge can touch dozens). With git as the backup, `git revert` is the undo for the files | S |
| GitHub token | secure-store (sealed into synced settings) | Paste again or it arrives on sign-in | keep-secret-out | No change; drop the stale `glyph-github-token` storage key from the manifest | S |
| PR link cache, ETags, checks | in memory | Refetched | keep-transient | A `pr:` front-matter key as a tap if a durable link is wanted | S |
| Device id (`glyph-handoff-device`) | device-storage | A restored device is a new device | keep-transient | Never in the library | S |

### 3.5 Editor features and custom markdown

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| Query fence (the fence IS the saved view) | markdown-body | Nothing | keep | No change | S |
| Query actions written back (tick, move, lane drafts) | markdown-body | Nothing | keep | No change | S |
| Query/gantt record caches | derived-cache (Expando) | Nothing | keep-transient | No change | S |
| Gantt fence | markdown-body | Nothing | keep | No change | S |
| Gantt ticket days written to the ticket | front-matter | Nothing | keep | No change | S |
| Gantt live zoom, selection, hover, drag | in memory; `zoom:` in the fence is the only persisted zoom | Nothing | keep-transient | If a sticky zoom is wanted, write `zoom:` into the fence | S |
| Note buttons `[label](ghost:verb?…)` | markdown-body | Nothing; a `post` button re-binds once the plugin is connected | keep | Document that channels are by name | S |
| Section folds and `<details>` toggles | device-storage (`glyph-folds`); `<details open>` is the portable default | Folds reset. Lost with the device, not with ids (ids are in the files) | keep-transient | No change | S |
| Backlinks, mentions, outline, word count, graph | derived-cache (LinkIndex) | Nothing | keep | No change | S |
| Block ids, heading anchors, Copy link to this line | markdown-body | Nothing | keep | No change | S |
| Aliases (`aliases:`) | front-matter | Nothing | keep | No change | S |
| Note and section embeds, picture embeds | markdown-body | Nothing for notes; a picture embed is a missing card until the images folder is restored | keep | Depends on the attachments move | S |
| Rich embeds oEmbed cache (`glyph-rich-embeds`) | derived-cache | Refetched | keep-transient | No change | S |
| @mentions of people and days | markdown-body | Nothing | keep | No change | S |
| Mention notice ledger: owed and sent ids (`glyph-mentions-<account>`) | device-storage | An owed notice may never be sent; the server dedupes | keep-transient | No change | S |
| Mention ledger `days` (who wrote a bare `@day` in a team note) | device-storage, never synced; so a bare team `@day` is nobody's reminder on any other device already | Every bare `@day` the person wrote in team notes stops reminding anyone | needs-decision | (a) When the editor settles a typed day in a team note with no person beside it, insert `@<me> @2026-11-06` so the existing beside-a-person rule carries authorship in the words (threads `MentionWho` into the mention extension; keep READING `days` for notes written before); or (b) a bare team `@day` reminds every member who holds the note | S–M |
| Verified pages (`verified: {by, until, words}`) | front-matter | Nothing | keep | No change | S |
| Verified expiry told ledger (`glyph-verified-told-<account>`) | device-storage | One redundant `recordAs`, collapsed by the server | keep-transient | No change | S |
| Form definition (```form) | markdown-body | Nothing | keep | No change | S |
| Form (and shared note) share id + key | synced-settings | Every published form/share link dies for the owner | needs-decision | As 3.7 (sites model + `share: <id>` marker). Prefer "shares are account state, restored by sign-in" and say so | M |
| Form standing on the service | server | Not in the library by design; filed tickets survive | keep | Forms are the one feature here that needs glyph-api; say so in docs/FORMS.md | S |
| Form inbox bookkeeping (`glyph-forms-filed`, `-said`, `-device`) | device-storage | Idempotent re-say; deterministic ticket ids | keep-transient | No change | S |
| Filed form answers (tickets) | markdown-body | Nothing of the ticket | keep | No change | S |
| Comments | markdown-body | Nothing | keep | No change | S |
| Comment author colours | server (in memory) | Ink until signed in | keep | No change | S |
| Blanks `{?q}` and `??answer??(source)` | markdown-body | Nothing | keep | No change | S |
| Snippets (`;sig`) | synced-settings | All personal expansions gone | move-to-library-config | A note `Snippets` (remembered by id in prefs) holding a ```snippets fence: `;trigger` on a line, its text indented beneath, `{date}`/`{time}`/`{datetime}`/`{cursor}` as today; Settings › Snippets edits the note; one-time import of the prefs list. A note syncs between devices and is in git; `Library/.glyph/*.md` would be neither indexed nor synced | M |
| Item link marks `[notion](url)`, `[github](url)` | markdown-body | Nothing | keep | No change | S |
| Place links and geotag | front-matter / markdown-body | Nothing; a public remote publishes `location:` lines | keep | Say so in the backup docs | S |
| Geotag pending tag and refusal | device-storage | A tag not yet written is lost | keep-transient | No change | S |
| Ticket marks on query cards | front-matter | Nothing | keep | No change | S |
| Notebook ```rules and the 'Claude rules' note | markdown-body | Nothing | keep | No change | S |

Dropped: the "note-id keyed ledgers after a bare restore" item. The note id is written into the markdown (`id:`) and
read back at index time, so a clone keeps every id; those ledgers are lost with the device, not with the library.

### 3.6 Recordings, meetings and voice

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| The recording WAV (`<data>/recordings/<note id>.wav`) | sidecar-binary outside the library; linked by note id alone; written by `capture_stop`, Kotlin's MeetingService, Meet takes, sync | No Play, no cassette, no voice memos, no Better words, no write-up re-run, no recording on a share. The transcript and summary in the body survive | needs-decision | Move under the library id-keyed: `Library/recordings/<note id>.wav` (one constant, paths.rs RECORDINGS; `r-<id>` sync ids, Kotlin, `recording_digest`, `delete_note` all keep working; no rename-with-the-title machinery). The git plugin ships a size cap (50 MB default) or LFS; a two-hour meeting is 230 MB and GitHub refuses a file over 100 MB. The app has no encoder; FLAC/Opus is a later step | L |
| `recordingMs` | library-dot-glyph (`.glyph/notes/<id>.json`, mirrored to the index); inside the library, in the export zip, NOT in the drive backup | If `.glyph/` is ignored: the note reads as never recorded | move-to-front-matter | `recording-ms: 3723000` written as Text in `set_recording` (frontmatter.rs `Value` has no number), parsed on read; sidecar as fallback for a release; add to `undraftable`'s allowed keys. Until then commit `.glyph/notes/` and add it to `Library::texts` | S |
| `segments` (timed phrases) | library-dot-glyph; ride INSIDE the note JSON on the `notes` route, merged by `withPhrases` and team/sync.dart | With the WAV back the tape plays but nothing lights up and tapping cannot seek; a meeting's `## Transcript` still carries turn-level `(0:04)` times and names, dictation has none | needs-decision | S: commit `.glyph/notes/*.json` as it is (one object per note, merges per file) and add it to the drive backup. A `<Title>.phrases` sidecar is cleaner to read but is a new `FileKind` with a second merge path for personal sync, team sync and the server: L, with the 2026-10-20 old-build warning | S now, L later |
| `formatted*` (same sidecar) | library-dot-glyph | The formatted view is empty until the model runs again | keep-transient | Strip `formatted*` from what the plugin commits, or stop writing it. Note `undraftable` treats any non-empty sidecar as "something set"; once the other fields leave it, look at front matter instead | S |
| `## Transcript` in timed turns | markdown-body | Nothing | keep | No change | S |
| `## Captions` | markdown-body (recoverable from `.versions` once dropped) | Nothing | keep | Commit `*.versions` | S |
| `## Summary` | markdown-body | Nothing | keep | No change | S |
| Kept summary record (`glyph-summaries`: which section text the app wrote) | device-storage | Every summary looks "edited"; "from before the last take" never shows | move-to-front-matter | Flat keys (frontmatter.rs `get` returns None for a nested map): `summary-model:`, `summary-at:`, `summary-for-ms:`, `summary-sha: <sha256 of the section>`; `summaryUnchanged` compares the sha; device sheet as fallback | S |
| Meeting membership (`preferences.meetings`) | synced-settings | See 3.1 | move-to-front-matter | `meeting: <ISO>`; index column; dual-write for a release | M |
| Which booking a meeting came from (`more.meetingNotes`) | synced-settings | The meetings list cannot jump to the note | move-to-front-matter | `meeting-booking: <id>` written when the take is filed; the reverse map built from the index | S |
| Meeting sort marks (`meetingSorts`, `sortMeetings`) | synced-settings | A restored meeting may be re-sorted once | move-to-front-matter | `app-filed: <workspaceId>` and `sorted: <workspaceId>|kept` (an empty value is unreadable by frontmatter.rs); `sortMeetings` stays a preference | S |
| Summary handoff claims (`summaryHandoffs`) | synced-settings | Nothing a library needs | keep-transient | No change | S |
| Voice memo marks `![voice 0:12](tape:12000-19500@k3f9x2)` | markdown-body | Nothing (needs the WAV and the tape id) | keep | No change | S |
| Tape ids (`glyph-tape-ids`) | device-storage, never synced | Every clip naming a tape id is silent even with the WAV back (`playsOn` requires a match); already so on any second device | move-to-front-matter | `tape: k3f9x2` written by `setTapeId`, cleared with the recording; read before the device map | S |
| Better words queue (`glyph-refine-queue`) | device-storage | Pending passes lost; live words stay | keep-transient | No change | S |
| Summary queue (`glyph-summary-queue`, `-transcribing`) | device-storage | A summary not yet landed is asked for again | keep-transient | No change | S |
| Write-up job files (`jobs/*.progress`, `jobs/*.json`, `jobs/config.json`) | derived-cache | A write-up in flight restarts | keep-transient | Never in the library | S |
| Speaker-naming pending list (`glyph-meet-pending`) | device-storage | `## Captions` left unnamed until Rebuild transcript | keep-transient | Optionally self-heal from the index | S |
| Live-meeting bookkeeping (`glyph-meet-live-notes`, live transcripts, server live frames) | device-storage / server | Nothing durable | keep-transient | No change | S |
| Meeting bot bookings, takes, plugin kinds | server | Nothing of a filed meeting | keep-transient | No change | S |
| Audio-removed list (`glyph-audio-removed`) | device-storage | Only the problem line's wording | keep-transient | No change | S |
| Live words during meetings (`glyph-meeting-live-words`) | device-storage, per device on purpose | Default for the device kind | keep | No change | S |
| Recording preferences (refine, summaries, writeUp, syncMeetingRecordings, meetingSound, localOnly, formatModel) | synced-settings / device | Defaults | keep | No change | S |
| Share of a meeting (words + sealed recording upload) | server | The published page is unaffected; re-sharing needs the WAV, `recordingMs`, phrases and the start | keep | Its inputs become portable through the items above | S |
| Films (`<data>/video/<uuid>.mp4`) | sidecar-binary, never synced | The film; the still and length remain | needs-decision | `Library/video/<uuid>.mp4` (one constant) excluded from the repo by default or LFS; `videos.rs referenced()` follows the path | M |
| Whisper and LLM models (`models/`) | derived-cache | Re-downloaded | keep-transient | Never in any backup | S |
| Meet decode scratch (`meet/`) | derived-cache | Nothing | keep-transient | Optionally sweep at launch | S |
| Voice log (`glyph-voice-log`) | device-storage | Debug history | keep-transient | No change | S |
| Sync fingerprints for recordings and phrases | derived-cache | Re-hashed next pass | keep-transient | No change | S |
| Claude API key for summaries | secure-store | Re-entered unless synced | keep-secret-out | No change | S |

### 3.7 Pictures, files, films, versions, shares, backup-to-drive and export

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| Picture reference `![](image/<uuid>.jpg)` | markdown-body | Nothing (the link points at a folder not in the library) | keep | Keep the form and the uuid naming (sync ids derive from it) | S |
| Picture bytes (`<data>/images/<name>`) | sidecar-binary; `images/` also holds `images/files/` and every `.ocr.txt` | Every picture is a blank card; Obsidian/GitHub show broken images | needs-decision | `Library/image/<name>`, as one move with attachments and OCR sidecars in one core pass at open; read-both for a release (`kept_path`, `AttachmentStore.pathOf`, `ReadTexts`, `remove_unreferenced`, reset.rs); write links as `image/<name>` unchanged (a per-depth `../image/` rewrite breaks `images::referenced`); backup and export write the same names | L |
| OCR sidecar (`<name>.ocr.txt`) | sidecar-plain beside the picture (outside the library) | Picture search lost until a phone re-reads; a Mac cannot | keep | Travels with the picture folder; a person may `.gitignore` it | S |
| Film reference | markdown-body | Nothing | keep | No change | S |
| Film bytes (`<data>/video/`) | sidecar-binary, never synced, never shared | The film is gone (already true on every other device) | needs-decision | Default: device-only, the README says so; (b) `Library/video/` with LFS and an off-by-default switch | M |
| Film sweep memory (`video/.orphans.json`) | derived-cache | The sweep starts again | keep-transient | Ignore dot files under media folders | S |
| Attachment reference `[Name](file/<uuid>.ext "2.4 MB")` | markdown-body | Nothing | keep | No change | S |
| Attachment bytes (`<data>/images/files/<uuid>.<ext>`) | sidecar-binary; ≤ 25 MB synced, ≤ 512 MB kept | Every PDF, scan, spreadsheet is a dead link; files over 25 MB exist on one device | needs-decision | `Library/file/<name>` as part of the pictures move; commit ≤ 25 MB (the sync line), skip larger by a size rule the plugin computes (gitignore cannot) | M (with the move) |
| File OCR sidecar | sidecar-plain | Search inside PDFs lost until re-read | keep | Travels beside the file | S |
| Words-owed ledger (`glyph-words-owed`) | device-storage | One OCR round may not reach other devices | keep-transient | No change | S |
| Read-words switch (`glyph-read-words`) | device-storage | Back on | keep-transient | No change | S |
| Legacy shared-files folder (`<data>/attachments/`) | sidecar-binary, drained at start | Effectively nothing | keep-transient | Delete the fallback once no old build is in the field | S |
| Versions file `<Title>.versions` | sidecar-plain; rewritten whole but append-stable so diffs are small, except at the 1000 cap or a `full` snapshot; damaged runs are dropped, never the file | Nothing | keep | Commit; never `merge=union`; resolve conflicts with `mergeFiles`; consider trimming past the cap in blocks of 50 | S |
| Which notes keep versions | device-storage (see 3.1) | New versions stop for personal notes; an org note switched off starts again | move-to-front-matter | As 3.1 | S |
| Versions-unsent ledger (`glyph-versions-unsent`) | device-storage | Nothing | keep-transient | No change | S |
| Versions held on a device without a core (`glyph-versions-<id>`) | device-storage | Self-migrating | keep-transient | No change | S |
| Version author identity (`by`) | sidecar-plain | Nothing; signed-out devices all write `me` | keep | Consider `me@<device>` when signed out | S |
| Share entries (id + KEY) | synced-settings; the server holds ciphertext by id only; nothing in the note | Readers keep reading the last blob; the owner cannot update, list, toggle or stop; recovery is take-down and reshare | needs-decision | (1) `share: <id>` as a library-managed non-secret marker. (2) The key in a second server blob sealed under the ACCOUNT key in context `share:<id>` holding `{v, noteId, key, place, places, recording}`, listed and opened on sign-in (lib/share/sites.dart `Sites.refresh` is the template; server/src/sites.rs the server half). A committed `shares.json` with keys would make the repo itself a secret | M |
| Share send bookkeeping (`sent`, `lacked`) | synced-settings | One extra PUT | keep-transient | Device storage once the entry leaves preferences | S |
| Shared meeting recording ledger (`ShareEntry.audio`) | synced-settings | One resend of up to 200 MB | keep-transient | `list_shares` answers `audio: {upload, parts, size, updated}` from `share_audio`; `mime`/`ms`/`chunk` go inside the sealed share blob; `sent` stays device-side | S |
| Share switches (place, places, recording) | synced-settings | A re-created share reverts to the privacy-safe defaults (an ON switch silently goes OFF) | needs-decision | Carry with the sealed `share:<id>` meta; never in front matter (would be mistaken for a tag beside `location:`) | S |
| Published sites (SiteEntry) | server (meta sealed under the account key) | Without sign-in: cannot republish or take down | keep-secret-out | The model for shares; add a `site: <id>` marker | S |
| Recent share-into targets (`glyph-share-recent`) | device-storage | Empty row | keep-transient | No change | S |
| Backup-to-drive layout | sidecar-plain copy; renames `workspaces/`→`Workspaces/`, `orgs/`→`Organizations/`, media under `Attachments/…`, skips every dot file (so no `.glyph/notes/`), no restore path | A backup folder is readable but is not a library | needs-decision | Model the git plugin on export.rs's `left_out`, not backup.rs: commit `Library/` verbatim including `.glyph/library.json` and `.glyph/notes/`. For the drive, either drop the renames and add `glyph_dir()/notes` to `plan`, or say in its README that the export, not the backup, is what restores | M |
| Backup manifest (`.ghostmd-backup.json`) | derived-cache on the drive | Next backup rewrites everything | keep-transient | Git's index replaces it | S |
| Android drive grants | device-storage | Allow the drive once more | keep-transient | No change | S |
| Export zip layout | sidecar-plain; walks `Library/` whole minus `index.sqlite*`, plus `images/`, `video/`, `recordings/`; leaves out `team/` | Already the closest thing to a portable library; media sit beside, not inside | keep | Make the export's tree the plugin's tree once media live inside; add `team/` to `sources` only if wanted (it holds one account's id) | S |
| Export `settings.json` carries share keys and sign-ins | device-storage dumped to a file: `glyph-preferences` whole, including `shares` (every id AND key), `calendars` (Google refresh token, iCal URLs) and `webhooks` secrets, while the README says "No account, password or key" | Not a loss: a risk. A zip on a USB stick publishes live read links and a refresh token | keep-secret-out | In `settingsFile`, strip `shares`, `calendars`, `webhooks` and every sealed field before encoding; a test asserts none appear. Nothing imports settings.json, so no compatibility cost | S |
| Per-device reading state exported as settings (`glyph-note-bookmarks`, `glyph-book-spots`, `glyph-workspace-current`, `glyph-plugins`) | device-storage | Resets | keep-transient | No change | S |
| Note sidecar `.glyph/notes/<id>.json` | library-dot-glyph | See 3.6 | keep (commit) | Commit `.glyph/notes/` and `library.json`, ignore only `index.sqlite*` | S |
| Library manifest `.glyph/library.json` | library-dot-glyph | A fresh one is written | keep | Commit it | S |
| Library index | derived-cache | Rebuilt; voice undo gone | keep-transient | `.gitignore` | S |
| Recordings | sidecar-binary | See 3.6 | needs-decision | As 3.6 | M–L |
| Team CRDT docs not exported or backed up (`<data>/team/<account id>/<note id>.json`) | sidecar-plain outside the library | Words are in the library and on the server; CRDT history is lost offline | keep-transient | Out of the repo (per-account device state); optionally an export source | S |

### 3.8 Plugins, integrations and library-describing settings

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| A committed library config (none exists today) | — ; precedents: `Preferences.more` carries unknown keys losslessly; export's `settingsKeys` writes a secret-free-by-intent settings file | Everything below marked move-to-library-config | move-to-library-config | `Library/.glyph/config.json` (see section 6), read through the Vault so SAF libraries work; the committed file is the truth, the synced settings a cache written FROM it. Note ids do NOT depend on committing `.glyph/notes/`: they are in each `.md` | L (the two-sources release) |
| Plugin switches (`glyph-plugins`) | device-storage; twelve travel as `plugin:<id>` sealed items, the rest are per device | Standard plugins only on a fresh device | keep | Optionally `plugins.suggested` in the config so a clone offers "This library uses Slack, GitHub…" without switching anything on; add notion, calendar, webhooks, keyboard-modes to `syncedSwitches` | S |
| Notion sign-in (`glyph-notion-account`), sign-in flight | secure-store / device | Sign in again | keep-secret-out | Nothing in files | S |
| Notion board per note (`glyph-notion-links`) | device-storage, per device on purpose (already lost on a second device) | "Linked to Notion board" gone; items already sent keep their marks | move-to-front-matter | `notion-board: <database url or id>` (LIBRARY.md already reserves the key) written when a list is first linked; the storage becomes a cache keyed by URL; read storage as fallback for a release | M |
| Notion tasks cache (`glyph-notion-tasks`) | derived-cache | Pills plain until read again | keep-transient | Nothing in files | S |
| GitHub token (`glyph-github-token`) | secure-store | Paste again or arrives on sign-in | keep-secret-out | Drop the stale storage key from the manifest | S |
| GitHub project links (`glyph-project-links`), project packs (`glyph-github-projects`) | device-storage, never synced | Which repo each note is about; the formatter's context pack; existing issue marks still tick/close (`issueAt` reads owner/repo from the URL) | move-to-front-matter | `github: owner/repo` on the note (`githubReposOf`'s parser already reads it on notebooks; `parseRepo` accepts `o/r` or a URL); a notebook's `github:` inherited by its tickets; the pack becomes a cache keyed by `owner/name` | M |
| GitHub issues cache (`glyph-github-issues`) | derived-cache | Read again | keep-transient | Nothing in files | S |
| Slack/Discord channel webhooks (`glyph-slack-webhook:<id>`, `glyph-discord-webhook:<id>`) | secure-store, each sealed into synced settings | Paste again or arrives on sign-in | keep-secret-out | Keep channel ids stable so a webhook pasted under the same id matches the channel named in the config | S |
| Slack/Discord channel names (`glyph-slack-channels`, `glyph-discord-channels`) | synced storage items (`_slackItems`/`_discordItems` in connections.dart), so account-synced, not device-only; the rules fence names channels by this name | A files-only restore without the account: the fence's `#eng` points at nothing | move-to-library-config | `config.json` `slack.channels`/`discord.channels: [{id, name}]`; on read merge by id into the synced item rather than replacing it | M |
| Post meetings to Slack/Discord (`glyph-slack-meetings`, `glyph-discord-meetings`) | synced storage items | Set again | move-to-library-config | `slack.meetings: {channel, share}`; the `on` switch stays the account's | S |
| Slack news channel per org (`glyph-slack-news`) | device-storage, one device on purpose | Set the channel again | keep-transient | Needs a claim if it ever moves | S |
| Posting bookkeeping (`glyph-slack-posted`, meeting queues, `slackMeetingPosts`, `discordMeetingPosts`) | device / synced | A meeting re-summarised could post once more | keep-transient | Nothing in files | S |
| Discord calls link and switch | server | Nothing in the library | keep-transient | Nothing in files | S |
| Lovart keys | secure-store | Paste again | keep-secret-out | Nothing in files | S |
| Lovart project and switches | device-storage; `bannersOn` defaults ON (banners resume spending once keys arrive), `designMeetingsOn` defaults off | Project remade; switches to defaults | keep-transient | Optionally `defaults.lovartBanners: false` in the config | S |
| Lovart done-lists and run state | device-storage; the banner itself is `banner:` front matter pointing at a picture outside the library | A note whose banner was removed on purpose may get one again | move-to-front-matter | `banner: none` for a removed banner (`bannerOf` already returns null for it on old builds); `## Inspiration`'s presence as the meeting's done mark | S |
| ElevenLabs key, voice, model, own voices | secure-store / synced / device | Key pasted again; voice and model to defaults | keep-secret-out | Optionally `elevenlabs: {voice, model}` in the config | S |
| Calendars | synced-settings, plaintext on device | Re-add | keep-secret-out | As 3.2 | M |
| Outgoing webhooks | synced-settings | Re-add | needs-decision | As 3.2 | M |
| Incoming webhooks (`glyph-hooks-applied`) | server / device | Nothing in the library; the default note's id is in its file, so it resolves | keep-transient | Nothing in files | S |
| Email to a note | server; filed notes are Markdown with `from:` | The address is the account's | keep | If filing rules are ever added, a ```rules fence or `mail.rules` in the config, not server-only | S |
| Reminders (`⏰`, `remind:`, `📍 [x](geo:…)`) | markdown-body | Nothing | keep | Already portable | S |
| Reminder settings (`glyph-reminders`), place-reminder asked flag | device-storage | Nine o'clock again | keep-transient | Optionally `defaults.reminderTime` in the config | S |
| Contacts (`glyph-contacts`: `{on, links}`) | device-storage | Hand matches redone (contact ids are the device's) | keep-transient | Nothing in files | S |
| Keyboard modes (`glyph-keymaps-*`) | device-storage | Back to Off | keep-transient | Add as `_storageItem`s so they follow the account | S |
| Meet/Zoom plugins and their device keys | server / device | Nothing in the library | keep-transient | Nothing in files | S |
| Meetings, meetingNotes, sort marks, handoffs | synced-settings | See 3.6 | move-to-front-matter | As 3.6 | M |
| Ticket features in Markdown (rules, labels, `label-colours`, `statuses`, `key`, `## Time`) | markdown-body | Nothing | keep | The model for everything else | S |
| Ticket bookkeeping in synced prefs | synced-settings | See 3.4 | keep-transient | Nothing in files | S |
| Digest settings | synced-settings | 8:30 again | keep | No change | S |
| Claude settings (key, model, effort, inbox, watch, meetings, limit, spend) | secure-store | Paste the key; the rest arrives on sign-in | keep-secret-out | Nothing in files | S |
| Other AI providers and Assistant choices | secure-store | As above | keep-secret-out | A LAN endpoint's base URL is a device fact | S |
| Todoist and Things | nothing kept | Nothing | keep | Nothing to do | S |
| Workspaces | synced-settings | See 3.1 (no adopter exists for personal folders) | move-to-library-config | As 3.1 | M–L |
| Smart notebooks, daily notes, snippets | synced-settings | See 3.1 / 3.5 | move-to-library-config | As above | S–M |
| Version-history switch | device-storage | See 3.1 | move-to-front-matter | As 3.1 | S |
| Trash and shares | synced-settings | See 3.1 / 3.7 | move-to-front-matter / needs-decision | As above | M |
| Plugin item marks and inline formats | markdown-body | Nothing | keep | Already portable | S |
| Account-level look-and-behaviour preferences | synced-settings | The app looks new | keep | Nothing in files | S |
| Device-only preferences and bookkeeping | device-storage | Defaults; geotagging on again by default | keep-transient | `defaults.geotag: false` in the config is the one device default worth a library override | S |

### 3.9 Interoperability and hosting

Storage items from this area that duplicate the above (attachments, canvases, trash, folders, smart notebooks,
`.versions`, the index) are counted once, in their own tables. The refuted item "note metadata outside the file"
is dropped: `created`, `pinned`, `archived`, `source` and `id` are in the front matter already; only `updated`
(mtime), `revision` and the sidecar's recording fields are outside the `.md`. The degradation table is section 7;
the hosting items are section 8. Two storage items proper:

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| Item link marks plus which board/repo a note sends to | device-storage (`glyph-notion-links`, `glyph-project-links`; connections.dart says they stay on each device) | Which Notion board / GitHub repo each list sends to | move-to-front-matter | `notion-board:` and `github: owner/repo` as in 3.8 | S |
| Voice memo clips and the note's recording | markdown-body + sidecar-binary + device (tape id) | See 3.6; the worse loss is `playsOn` muting every id-bearing clip | needs-decision | Step 1 (S): `tape:` in front matter. Step 2: recordings under the library; clips may later use a Media Fragments form `audio/<id>.wav#t=12,19.5`, keeping `tape:` readable forever | S then L |

### 3.10 The 'Back up to git' plugin

| Item | Where today | If only the files survive | Recommendation | Proposal | Effort |
|---|---|---|---|---|---|
| Git remote, branch, cadence, inclusion settings (new) | — | A restored device must be told the remote again | move-to-library-config | `config.json` `git: {remote, branch, recordings: {on, maxBytes}, orgs: {include: []}, cadence, madeBy}`; read/written through the Vault; the synced settings mirror it | S |
| Git host token (new, `glyph-git-token`) | secure-store | Paste a new token | keep-secret-out | Listed in connections.dart so it follows the account sealed; passed per call into Rust, never kept in Rust state; the commit path refuses `*token*`, `.env`, `.netrc` | S |
| The GitHub plugin's token as a push credential | secure-store | — | keep-secret-out | Do not reuse by default (its scope is Contents read); an Advanced row runs the check and explains | S |
| Pusher claim (new) | synced-settings | The next device takes the claim | keep-transient | `more.gitBackup = {claim: {by, name, at}, lastPush}` on the `SummaryHandoff` pattern; renew in minutes, not per commit (each renewal is a PUT of the whole blob) | S |
| Per-device git status (new, `glyph-git-status`) | device-storage | Recomputed | keep-transient | `{lastPushAt, lastCommit, ahead, behind, pending, lastError}` | S |
| The mirror working tree and its `.git` (`<app data>/git/<repo-id>/`) | derived-cache | Rebuilt from the library and the remote | keep-transient | backup.rs with a NEW path mapper (not `library_path`): library folder names kept; `.glyph/library.json`, `.glyph/notes/*.json` and the config taken through `glyph_dir()` (for a SAF tree they live under `trees/<key>/`); `<data>/images/<name>` → `image/<name>`; `<data>/images/files/<name>` → `file/<name>`; recordings when included; `video/` excluded. Disk doubles for pictures; cleanup on plugin removal | M (mirror); L (with a working git layer) |
| Mirror manifest (`.ghostmd-backup.json`) | derived-cache | Next commit rewrites everything | keep-transient | `.gitignore`d, or dropped for the git index once the spike shows it is as cheap | S |
| Generated `.gitignore` | sidecar-plain, committed | Nothing | keep | Section 6; regenerated every commit, a person's additions below a marker preserved | S |
| `README.md` at the repo root | sidecar-plain | Nothing | keep | From `backupReadme` plus restore steps and the plaintext warning | S |
| `.glyph/library.json`, `.glyph/notes/*.json` | library-dot-glyph | See 3.1 | keep | Commit both | S |
| `.glyph/index.sqlite*`, `<data>/index/<key>.sqlite` | derived-cache | Rebuilt; voice undo gone | keep-transient | Ignore | S |
| `<Title>.versions` | sidecar-plain | Nothing | keep + decision on the switch | Commit; `mergeFiles` on conflict; the switch as in 3.1 | S |
| Pictures, attachments | sidecar-binary | Every picture and file | needs-decision | Commit at `image/`, `file/` (≤ 25 MB) through the mapper in v1; the folder move is the cross-area decision | M |
| Recordings | sidecar-binary | The audio | needs-decision | Opt-in switch with a per-file cap (50 MB default); `recordings/` ignored while off; LFS later (gix has none; a hand-written batch client, M). Recordings without `.glyph/notes/` are audio with no phrases | M |
| Films | sidecar-binary | The film | keep-transient | Excluded, consistent with sync | S |
| Team notes under `orgs/<Org>/` | markdown-body | Nothing for the person; privacy is the question (today's drive backup copies them with no switch) | needs-decision | Default exclude every org; per-org switch in the plugin's page; the first commit says how many teammates' notes a switch includes | S |
| Team CRDT docs | derived-cache | Rebuilt from the org log | keep-transient | Never in the repo | S |
| `jobs/`, `models/`, `meet/`, `carry/`, `library-root.json`, `trees/`, `index/` | device-storage | Device bookkeeping (except `trees/<key>/` which IS a SAF library's `.glyph/`) | keep-transient | Outside the mirror; `.glyph/` always taken from `glyph_dir()` | S |
| Plugin switch, setup memory, activity tallies | device-storage | Add again; setup from step one; counts | keep-transient | Add `git-backup` to the synced switches | S |
| Commit author identity | in the commits | Nothing | keep | `<handle> <handle@users.ghostmarkdown.com>`; signed out `Ghost.md <ghost@localhost>`; trailer `Ghost-Device: <name>` | S |
| Three-way merge base (Phase 2) | derived-cache (git's merge-base) | Nothing | keep-transient | `.md` → `mergedWords`, null → keep mine and write theirs as `<Title> (conflict from <device>).md`; `.versions` → `mergeFiles`; `.glyph/notes/*.json` → prefer the side with `recordingMs` set, then theirs; binaries → theirs, differing same-name kept as `.conflict` | M |
| Restore from a URL, a folder or a `ghostmarkdown_*.zip` (new) | — | This is the restore | keep | One `ImportKind.ghostmd` keeping paths as-is (not a dated workspace); same-id collisions → `mergedWords` or a conflict copy; asks first when the account already has notes | M |
| Static site from the repo | server (today's sites are sealed) | — | needs-decision | Section 8 | L |

## 4. Already portable

Safe today, in the files, needing no work:

- The words of every note; `id`, `created`, `pinned`, `archived`, `source` in front matter.
- `<Title>.versions` (history with authors), renamed and deleted with the note.
- Every ticket key: type, key, status, assignee, priority, due, start, estimate, labels, component, parent/epic,
  blocked-by, milestone, cycle, watchers, spent, remind, triage, duplicate-of, via/form/answered/email, from.
- Notebooks (`book`, `key`, `statuses`, `cycles`, `label-colours`, `stale-after`, `github`, `on-merge`), journals,
  templates and place templates, daily notes' files.
- The ```rules, ```query, ```board, ```gantt, ```form, ```comments and ```mermaid fences, with their settings on
  the fence or in it; `[^c1]` anchors; `[label](ghost:…)` buttons.
- `## Time` logs, `## Transcript` turns with `(m:ss)` and names, `## Captions`, `## Summary`, the digest note.
- Wiki links, aliases, block ids, embeds, tags, callouts, tasks and task fields, reminders and place links, mentions,
  verified pages, blanks and `??` marks, inline marks and text effects, counters and sums, `<details>` toggles.
- Item link marks `[notion](url)`, `[github](url)`.
- The next ticket number (computed), list order (computed), backlinks and the graph (computed).
- Team notes' words, comments and history under `orgs/<Org>/`.

## 5. The gaps, ranked by what a person loses

1. **Attachments are outside the library.** Every picture, PDF, film and tape a note links is in a sibling folder
   under app data, and the links (`image/`, `file/`) do not even name the real folders (`images/`, `images/files/`).
   A repo of `Library/` has dead links and no sound. Fix: move the stores under the library at the names the links
   already use (`Library/image/`, `file/`, `video/`, `recordings/`), one-time move at open, old folders read as
   fallback for a release; until then the git plugin maps them into the repo at those names. (L)
2. **Folders.** The workspace list (ids, hues, parents) and the filing map live only in the synced blob, and nothing
   reads personal folders back from the directory tree. A restored library shows no folders and every note unfiled.
   Fix: an adopter at open that makes folders from paths with `folderIdFor` ids and files each note; a committed
   `config.json` for hues, legacy ids and empty folders. (M)
3. **Shares and their keys.** Every read-only link's id and key is only in the synced blob; the export zip leaks
   them in `settings.json` under a README that says it holds no key. Fix: the sites model (meta sealed under the
   account key on the server) plus a non-secret `share: <id>` marker in the note; strip secrets from the export now.
   (M; the export fix S)
4. **The trash.** Nothing on disk marks a trashed note; a restore brings every one back live. Fix: `trashed: <ISO>`
   as a library-managed key beside `archived:`, an index column, the preference written in parallel for a release. (M)
5. **The two front matter blocks.** Every ticket, notebook, journal, canvas and geotagged note is written as two
   `---` blocks, so Obsidian, GitHub, Hugo and Jekyll show its properties as text and a one-block ticket from another
   app is misread. Fix: one block, phased read-both then write-new, ticket key renamed to `issue:`. (L)
6. **Which notes are meetings** (and their start, booking, sort mark) is only in the synced blob. Fix: `meeting:`,
   `meeting-booking:`, `app-filed:`/`sorted:` in the page's block. (M)
7. **Which notes keep versions** is a per-device map that was never synced, so personal history stops on a restore
   (and already differs between a person's devices). Fix: `versions: true|false` as a library-managed key; an existing
   `.versions` beside a personal note reads as on. (S)
8. **Transcripts and recording length** live in `.glyph/notes/<id>.json`, which the drive backup skips. Fix now:
   commit `.glyph/notes/` and add it to `Library::texts`; `recording-ms:` into front matter. (S)
9. **Updated time** is the file's mtime, which git resets. Fix: the plugin restores mtimes from commit times on
   checkout, or `updated:` written on body saves with the index taking the later of key and mtime. (S)
10. **Status timing** for personal tickets without versions falls back to mtime. Fix: `status-since:` and `done:`
    written by one `withStatus` helper. (S)
11. **Library-describing settings** (smart notebooks, daily notes, snippets, Slack/Discord channel names, org
    identity) are only in the synced blob. Fix: `config.json` for the first four plus a `Snippets` note. (S–M)
12. **Per-note plugin links** (Notion board, GitHub repo) are per device and already lost on a second device. Fix:
    `notion-board:` and `github:` in front matter. (M)
13. **Small per-note facts** on the device: tape ids (mute every voice memo on a restore), summary provenance, Lovart
    banner opt-out, bare `@day` authorship in team notes. Fix: `tape:`, `summary-*`, `banner: none`, `@me @day`. (S each)
14. **Canvases** are JSON Canvas inside a `.md`, unreadable by Obsidian. Fix: a derived `<Title>.canvas` first, the
    stored form later. (M then L)
15. **Restore-then-sign-in doubles edited notes** because the device has no mark for them. Fix: use `.versions`
    hashes as a merge base before falling to a conflict copy. (M)

Also found, not a portability gap: calendars' Google refresh token and webhook secrets sit in the clear in the device's
preferences blob (only the wire copy is sealed); the git plugin's spike must verify gitoxide push before anything is
promised.

## 6. The target layout

The Library folder is the unit of backup. Everything a fresh device needs is under it; everything that is a device's,
an account's or a cache is outside it or ignored.

```
Library/
  Inbox/<Title>.md                 the note, ONE front matter block
  Inbox/<Title>.versions           plain-text history
  workspaces/<Workspace>/[<Sub>/]  personal folders (names and nesting are the truth; .keep in empty ones)
  orgs/<Org>/[<Workspace>/]        team notes (excluded from a personal repo by default)
  image/<uuid>.jpg (+ .ocr.txt)    pictures, at the path the notes link
  file/<uuid>.<ext> (+ .ocr.txt)   attachments, ≤ 25 MB committed
  video/<uuid>.mp4                 films, ignored by default
  recordings/<note id>.wav         tapes, opt-in with a cap (LFS later)
  .glyph/
    config.json                    the committed library config (below)
    library.json                   the library's record of itself
    notes/<id>.json                recording length and phrases (until they move)
    index.sqlite*                  IGNORED: the cache
  .gitignore                       generated
  .gitattributes                   generated: binary for image/ file/ recordings/; LFS filter when chosen
  README.md                        generated: what this is, how to restore, "anyone who can read this can read your notes"
```

The dot folder: the task's draft called the committed config `Library/.ghost/`. The skeptic's case for `.glyph/`
instead is practical: `.glyph/` is already what relocate.rs moves, what export's SAF branch walks, what
`trees/<key>/` holds for an Android SAF library, and what `glyph_dir()` answers; a second hidden folder would need the
same plumbing again. The config is read and written through the Vault, never by path, so SAF libraries work. The name
is decision 2 below; this document writes `.glyph/config.json`.

`config.json`, version 1, non-secret, keyed by path where a path exists:

| Key | Shape | Written by |
|---|---|---|
| `version` | `1` | the library |
| `workspaces` | `{"Work": {"hue": "moss"}, "Work/Clients": {"id": "w-8ab1"}}` (`id` only where it differs from `folderIdFor`) | `setWorkspaceHue`, `addWorkspace` |
| `orgs` | `{"orgs/Acme": {"org": "<22-char id>", "name": "Acme", "hue": "sea"}}` | `ensureOrgWorkspace` |
| `dailyNotes` | `{"folder": "Daily notes", "notebook": "<note id>", "template": "A day"}` | daily_notes.dart |
| `smartNotebooks` | `[{"id", "name", "query"}]` | smart_notebooks.dart |
| `slack`, `discord` | `{"channels": [{"id", "name"}], "meetings": {"channel", "share"}}` (names and ids only; never a webhook) | the plugins |
| `plugins` | `{"suggested": ["slack", "github", "keyboard-modes"]}` | the registry |
| `defaults` | `{"versions": true, "geotag": false, "lovartBanners": false, "reminderTime": "09:00"}` | Settings |
| `me` | `"matt"` (for a library opened with no account) | account wiring |
| `git` | `{"remote", "branch", "recordings": {"on", "maxBytes"}, "orgs": {"include": []}, "cadence", "madeBy"}` | the git plugin |

A guard refuses to write the file if any value looks like a secret (keys named webhook, token, refreshToken, secret,
or a URL under `slack`/`discord`/`calendars`/`webhooks`). The committed file is the truth; the synced settings are a
cache written from it, never the other way; old builds ignore it (the vault walk skips dot folders, `library_path`
refuses dot folders from remote devices, so it can never leak as a note or a sync path).

Per-note facts go in the note, never the config: `trashed`, `meeting`, `meeting-booking`, `versions`, `share`,
`site`, `recording-ms`, `tape`, `status-since`, `done`, `summary-*`, `notion-board`, `github`, `banner: none`,
`app-filed`/`sorted`. They travel with the note on a move, work on SAF, and old builds keep unknown keys byte for byte.

The generated `.gitignore`:

```
# Ghost.md: rebuilt from the files
.glyph/index.sqlite
.glyph/index.sqlite-wal
.glyph/index.sqlite-shm
.glyph/index.sqlite-journal
.ghostmd-backup.json
*.ghostmd.tmp
**/.*.part
**/*.tmp
.orphans.json
.DS_Store
# never backed up
video/
recordings/        # removed when the recordings switch is on
orgs/<Name>/       # one line per excluded organization
```

What stays out, and why:

- **Secrets**: the account session and keys, org keys, every API key and connection, Slack/Discord webhooks, the
  Notion OAuth pair, Google's refresh token, iCal URLs, outgoing webhook secrets, share keys, the git token. They are
  the account's (sealed keys) or the device's (secure store). A git backup is of the library, not the account.
- **Device state**: reading positions, folds, tabs, sidebar state, queues (refine, summary, Slack), ledgers (mentions
  told, ticket events, forms filed), caches (oEmbed, Notion/GitHub details, PR ETags), device id, library root.
- **Account coordination**: claims (sweep, digest, handoff, banner run, pusher), run ledgers, running timers, sync
  cursors and marks.
- **Caches**: the index, LinkIndex and friends, team CRDT documents (rebuilt from the org log), job progress files,
  models, decode scratch, the formatted copy of a recording.

## 7. Custom syntax and other apps

How each thing Ghost.md writes reads in Obsidian, on GitHub and in a plain viewer, and what to standardise.

| Syntax | Obsidian | GitHub | Plain viewer | Note |
|---|---|---|---|---|
| `[[Note]]`, `[[Note|alias]]`, `[[Note#Heading]]`, `aliases:` | native | literal text | text | Files named by title, so links resolve by filename |
| ` ^name`, `[[Note#^name]]` | native block ids (lower-case only) | text at line end | text | — |
| `![[Note]]`, `![[Note#^name]]`, `![[Canvas]]` | native transclusion | literal | text | — |
| Front matter (flat keys, lists and maps written across) | Properties panel | table above the file | text | Teach `frontMatterEnd` to accept indented `- item` lines so an Obsidian-edited note is not demoted to "opens with a rule" |
| The second block (today) | literal `---` and text | a rule and loose lines | text | The single-block merge fixes this |
| Ticket and notebook keys | properties (flow maps as objects) | table | text | Links inside quoted values are text there |
| `title`, `tags`, `aliases`, `look`, `banner`, `location`/`place`, `authors`, `date`, `type: milestone|cycle` | properties; Banners plugin reads `banner:` once the picture folder is in the library | table | text | A publisher must strip `location:`/`place:` as a share does (lib/share/carried.dart) |
| `verified: {by, until, words}` | object property | table | text | — |
| Task fields `📅 🛫 ⏳ ✅ ➕ ❌`, `🔺⏫🔼🔽⏬`, `🔁`, `[key:: value]`, `@person` | Tasks and Dataview live | emoji and dates as text | readable | Obsidian Tasks' order |
| `⏰ 2026-10-03 09:00`, `📍 [x](geo:…)` | Reminder plugin reads ⏰; `geo:` opens Maps | `geo:` href stripped, label kept | text | RFC 5870 |
| `[Name](geo:lat,lon)` alone on a line | link to Maps | label only | text | Privacy on publish |
| `![](image/<uuid>.jpg)`, `[x.pdf](file/…)`, `[![video]](video/…)` | broken until the folders are in the library, then native | same | same | Gap 1 |
| `![voice 0:12](tape:…@id)` | broken image | literal | text | Later: `audio/<id>.wav#t=12,19.5` Media Fragments, with `tape:` read forever |
| ```board | code block of column lines; items stay a list with ` ^names` | code | code | Publisher fallback: columns as headings |
| ```query | code block | code | code | Dataview-shaped; publisher runs it at build time or shows "live in Ghost.md" |
| ```gantt | code block whose lines read as the plan | code | code | Add fence → ```mermaid gantt as "Copy as Mermaid" and the publisher's fallback (lossy: no `follow:`, `colour:`, ticket links; never written back) |
| ```mermaid | rendered | rendered | code | Publisher uses mermaid.js; optionally `height=` on the fence like boards |
| `[^c1]` + ```comments | dangling footnote ref; code | literal `[^c1]`; code | text | Publisher: threads or hidden (default hidden) |
| ```rules | code | code | code | Readable sentences |
| ```form | code | code | code | Only works through the share page + glyph-api; say so |
| Canvas (`.md` with `title:` + JSON Canvas) | wall of JSON (opens only `*.canvas`) | JSON | JSON | Derived `<Title>.canvas` first, stored form later |
| `[Label](ghost:set?status=Done)` | link that asks the OS to open `ghost:` | label as text | link | Chosen for exactly this degradation |
| `@sam`, `@2026-11-06` | text | text | text | — |
| `{{date}}`, `{{next-id}}`, `{{cursor}}` | Templates core reads the shared ones; unknown left as typed | text | text | `id: "{{next-id}}"` is quoted so YAML survives |
| `{?question}`, `??answer??(source)` | text | text | text | — |
| `<details><summary>` | toggle | toggle | raw | Teach Rendered.tsx to draw the two tags |
| `||spoiler||`, `==highlight==(colour)`, `%%aside%%`, `??unsure??`, `@@redact@@`, `^^shout^^`, `++added++`, `>|` | `==x==` native; `%%x%%` is Obsidian's COMMENT, so an aside DISAPPEARS there; the rest literal | literal | literal | Document the `%%` collision in the cheat sheet (or pick another run, adding never removing); redaction is a look, the words are in git |
| `🔥🔥x🔥🔥` effects | emoji | emoji | emoji | — |
| `- ( )` choices, `[3/8]` counters, `= $450 + 120` sums, `§§` bookmark | characters | characters | characters | Publisher may compute sums (sums.dart is pure) |
| `#tag`, `#nested/tag`, callouts, footnotes, GFM tables and tasks | native | native (alerts, checkboxes) | text | — |
| Meeting notes ("Ghost was in this meeting…", `**Name (0:04):**` turns) | bold names and text | same | same | Timing at turn granularity survives in the words |
| `.versions` | ignored (not `.md`) | text | text | — |

Proposals to standardise: one front matter block; `issue:` for the ticket key; `.canvas` for canvases; attachments
at the linked paths; a Mermaid writer for gantts; `<details>` in the web reader; the `%%` note in the cheat sheet.

## 8. Hosting

Three renderers exist today: the Flutter editor (the truth), the Tauri web Editor used read-only by Site.tsx and the
docs, and the lezer-based Rendered.tsx used by read.html. Rendered.tsx special-cases exactly one fence, `gantt`; every
other fence is a code block, and raw `<details>` is shown as text. Published sites today are sealed blobs on glyph-api
(`/s/<id>#key`): private and zero-knowledge, tied to ghostmarkdown.com, the opposite of "host anywhere". Forms depend
on the service entirely.

The static build already exists for one case: tauri/vite.docs.config.ts and tauri/src/docs/book.ts turn docs/book/
into per-page HTML with slugs (slugs.ts) and search.json, drawn by Site.tsx, served by the Caddy block in
scripts/deploy-landing.mjs (`try_files {path} {path}/index.html /index.html`). Publishing a repo of a library is a
generalisation of that pipeline, not new machinery:

- `publish-library.mjs <Library dir> <out dir>`: pages = every `.md` under the tree (title from `# ` or `title:`);
  sidebar = folder tree plus notebook indexes (read `config.json` for hues and order); slug = `<folder>/<title-slug>`;
  `[[links]]` resolved by titleKey plus aliases; embeds always resolvable (every page is present); assets copied from
  `Library/image|file|video`; front matter stripped per carried.dart (`location`, `place`, and the places switch)
  unless opted in; comments hidden by default; search.json as today. Output is plain HTML deployable on GitHub Pages,
  Netlify or the Caddy block. Shipped as a GitHub Action template in the git plugin so a push republishes.
- One web renderer: pick Rendered.tsx (small, no HTML strings) for sites, docs and shares, and give it static
  fallbacks per fence in priority order: mermaid (mermaid.js), `<details>`, board (columns from anchors), comments
  (threads or hidden), rules and form (plain lists), query (pre-run result or a "live in Ghost.md" box), ticket front
  matter as a properties panel. A fixture-driven conformance test renders the sample notes (lib/core/sample_library.dart)
  in Flutter (golden) and in Rendered.tsx (DOM snapshot).
- Build-time queries: phase 1 is Node only with the fallbacks; phase 2 a Dart CLI (`dart run tool/publish.dart`)
  that pre-renders ```query, ```gantt and sums to `.glyph/rendered/<id>.json` for the Node build. The decision is
  whether a Dart toolchain in CI is acceptable for the Action.
- The share sheet names the two routes: "Publish privately (Ghost.md link)" and "Export as a website (folder/GitHub)".
  Forms stay a service feature; docs/FORMS.md and the book say so.

Hosting depends on gap 1: until attachments live under the library every picture on the site is broken.

## 9. The migration plan

Each slice is one release; each says what moves, how old builds and sync cope, and what proves it. The rule from the
2026-10-20 org-folders incident holds: readers ship before writers wherever a format changes, and every device is on
the reader build before any device writes the new shape.

| # | Slice | What moves | Old builds and sync | Tests | Effort |
|---|---|---|---|---|---|
| 1 | Commit what is already plain | Nothing moves. `Library::texts` gains `.glyph/library.json` and `.glyph/notes/*.json`; export strips `shares`, `calendars`, `webhooks` and sealed fields from settings.json; `subTicketsOf` sorts by issue number; `setKeepsVersions(on)` keeps v1 at once | None | relocate/backup tests list the sidecars; an export test asserts no key appears; a sort test | S |
| 2 | Small front-matter keys | `versions:` (library-managed, `.versions` presence as on during transition), `tape:`, `recording-ms:`, `summary-*`, `status-since:`/`done:` via `withStatus`, `meeting-booking:`, `app-filed:`/`sorted:`, `banner: none`, `notion-board:`, `github:` on notes, `share:`/`site:` markers; all added to `undraftable` and `_unsaid` | Unknown keys kept byte for byte by every build; preferences and device maps written in parallel for one release, read as fallback | Rust frontmatter round-trips; Dart reads key-then-fallback; a two-device sync fixture shows no conflict copy from a key write | M |
| 3 | Folders and the config | The path adopter at open; `.glyph/config.json` through the Vault with `workspaces`, `orgs`, `dailyNotes`, `smartNotebooks`, `slack`/`discord` channels and meetings, `plugins.suggested`, `defaults`, `me`; a `Snippets` note replaces `preferences.snippets` | Old builds ignore the file and keep the preference; the preference stays the live channel, the file wins on a fresh device; SAF libraries write through `trees/<key>/` | An open-from-clone test: a tree with no preferences yields the same folders, ids (`folderIdFor`) and filings; a hue round-trip; a SAF-tree test | M–L |
| 4 | Trash and meetings | `trashed:` and `meeting:` as index columns (`set_trashed` beside `set_archived`; `meeting` written from the five writers); `KeptTrash` and `Preferences.meetings` become views with the preference dual-written | An old build pushing a `NotePayload` without the field clears it on a new one, hence the dual write; the purge keeps exempting org notes; `recordingStaysHere` reads the column | Index tests for the columns; purge test; a mixed-build sync fixture | M |
| 5 | Attachments under the library | `images/` → `Library/image/`, `images/files/` → `Library/file/`, `video/` → `Library/video/`, `recordings/` → `Library/recordings/`; one move at open; read-both for a release; Kotlin twins; backup and export write the same names; `.gitattributes` | Sync carries files by kind+name, unchanged; old builds look in the old folders (fallback read); SAF libraries need `TreeTarget` writes; reset.rs must not wipe a chosen folder's `image/` | Core tests for `kept_path` both ways; `images::referenced` unchanged; backup and export layout tests; a restore from a clone renders every picture | L |
| 6 | Shares on the sites model | `share:<id>` meta sealed under the account key on the server (sites.rs copied); `list_shares` answers audio meta; `sent`/`lacked` to device storage; `preferences.shares` written in parallel for a release then dropped | Old builds read the preference; the prefs merge loses a field it no longer carries, fine | Server tests for the new blob; a sign-in-on-fresh-device test recovers every share | M |
| 7 | One front matter block | Phase A: readers accept the merged shape and `issue:` (index.rs, Dart, web frontMatter.ts, MCP `keepKeys`). Phase B, a release later: the writer merges the five keys into the page's block, writes `issue:`; migration on next save | Phase B must not ship until every device has A (GHST-107-class hazard: an old build reading a merged body takes `id: <uuid>` as the ticket key and loses `type:`); sync carries whole bodies; team CRDT docs churn once | `a_tickets_front_matter_is_the_pages_and_is_kept_whole` replaced by a one-block test; Obsidian-vault fixture whose only block holds `tags:` reads its properties; mixed-build fixture | L |
| 8 | Canvases and Mermaid | Derived `<Title>.canvas` written by the plugin and publisher; fence → Mermaid gantt writer; `<details>` in Rendered.tsx | None (derived files) | Round-trip JSON Canvas; Mermaid output snapshot | M |
| 9 | Restore-then-sign-in merge | `_merge` uses the common `.versions` hash as a base for `mergedWords` before a conflict copy; marks as hashes | Touches the "never a loss" guarantee; two-device fixtures | Fixtures with and without a shared base | M |

The git plugin (section 10) can ship after slice 1 and ride every later slice unchanged: it commits whatever `texts()`
and `glyph_dir()` give it, and its mapper is what makes slices 3 and 5 optional for the repo's shape.

## 10. The 'Back up to git' plugin

**Git implementation.** gitoxide (`gix`), pure Rust, inside the core behind a `git` cargo feature. It builds for
aarch64 Android, iOS and macOS with the toolchain the repo has (no cmake, no C), and its HTTPS transport
(`blocking-http-transport-reqwest-rust-tls`) is the reqwest+rustls already in native/Cargo.lock behind the `voice`
feature (zero marginal size on Android and Mac; about 2.5 MB on iOS where reqwest is new). It has init, object db,
index, checkout, commit, fetch, clone, shallow clone and blob/tree merge. The one thing to verify first: push. gix has
lacked a complete high-level push; if the pinned release still does, `send-pack` over smart HTTP is `POST
/git-receive-pack` with pkt-lines and a pack of the missing objects, and gix-pack and gix-transport already do the
parts (a week, the only hand-written protocol code). Fallback: git2 (libgit2) with vendored OpenSSL on Android only,
which native/Cargo.toml explicitly avoided. Shelling out to `git` is impossible on phones and not assumable on the Mac.
Spike first (two days): gix behind the feature, three targets built, size measured, `ls-remote` + shallow clone +
commit + push against a test repo.

Commands in `native/src/kept/git_backup.rs`: `git_check`, `git_init`, `git_remote_set`, `git_status`, `git_commit`,
`git_push`, `git_pull`, `git_clone`, each a `work::start` job emitting `git://progress {id, phase, done, total}` and
ending with `job://end`. The token is passed per call from Dart's secure store and held in memory for the call only.

**Repository layout.** The repo is NOT `Library/.git`; it is a mirror working tree at `<app data>/git/<repo-id>/`
written by backup.rs onto a `FolderTarget`. Reasons: a chosen folder on iCloud, Dropbox or Syncthing would sync `.git`
object by object and corrupt it (root.rs refuses the index in such folders for the same reason); an Android SAF tree
has no paths for gix, but `Library::texts()` is SAF-safe; the manifest-based incremental write already answers "what
changed since the last commit" and handles deletions. The mapper replaces `library_path`: `Inbox/`, `workspaces/`,
`orgs/` as the Library names them; `.glyph/library.json`, `.glyph/notes/*.json` and `config.json` through
`glyph_dir()` (for a SAF tree they live at `trees/<key>/`); `<data>/images/<name>` (+ `.ocr.txt`) → `image/<name>`;
`<data>/images/files/<name>` → `file/<name>`; `<data>/recordings/<id>.wav` → `recordings/<id>.wav` when included;
`video/` excluded. After slice 5 the mapper is identity. Restore is the same mapper in reverse. A Mac "this folder is
already a repo" mode is Advanced, later.

Committed by default: every `*.md` and `*.versions`, `.glyph/library.json`, `.glyph/notes/*.json` (with `formatted*`
stripped), `image/*` with OCR text (≤ 25 MB), `file/*` (≤ 25 MB), `.glyph/config.json`, the generated `README.md`,
`.gitignore` and `.gitattributes`. Opt-in: `recordings/*.wav` behind a switch with a per-file cap (50 MB default;
LFS later, hand-written, since gix has none). Never: `video/`, the index, `index/`, `trees/`, `jobs/`, `models/`,
`meet/`, `carry/`, team CRDT docs, the mirror's manifest, `library-root.json`, temp files, anything matching
`*token*`, `.env`, `.netrc`. Trashed notes' files ARE committed (the ticket counter relies on them).

**Cadence.** Commit after two minutes of quiet following the last library change, with a floor of one commit an hour
while anything is uncommitted and the device is awake, plus Back up now. One commit per quiet window, never per note
(`.versions` is the fine history and is committed). Push right after a commit on Wi-Fi or a desktop; on mobile data
deferred to the hourly tick (`WaitingOn.wifi` in the tray). Never an empty commit. Message: `Edit: <title>` for one
note, `<Handle> edited 3 notes: Launch plan, Standup, +1` for several, `Added 2 pictures` / `Deleted: <title>` as body
lines, trailer `Ghost-Device: <device name>`. Author `<handle> <handle@users.ghostmarkdown.com>`; signed out
`Ghost.md <ghost@localhost>`. No GPG.

**Remotes and auth.** HTTPS with a token, any host: GitHub (fine-grained PAT, Contents read/write on one repo),
GitLab, Gitea/Forgejo/Codeberg, Bitbucket, or a bare repo behind basic auth on the person's own box. Basic auth
`x-access-token:<token>` for GitHub, `oauth2:<token>` for GitLab, `<user>:<token>` otherwise, chosen by host. The
plugin keeps its own secret `glyph-git-token`, listed in connections.dart so it follows the account sealed. The GitHub
plugin's token is not reused by default (its scope is Contents read); an Advanced row runs the check and explains. Git
traffic goes through the core's reqwest, not `host.fetch`, so the manifest declares `hosts: []` with the network
permission's reason "the git host you add, and nothing else" (the Webhooks plugin's pattern); the Rust command refuses
non-https remotes and private-network addresses unless the person says the repo is on their own machine. SSH is
Mac-only, later, if ever.

**Multi-device.** Phase 1: one device of the account holds the pusher claim, `Preferences.more['gitBackup'] =
{claim: {by, name, at}, lastPush: {at, by, commit}}`, written and confirmed exactly as `SummaryHandoff.claim` is (the
server's revision check resolves two claimants), renewed every few minutes while pushing (each renewal is a PUT of the
whole blob), stale after 24 h; desktops preferred; other devices show "Backing up from your Mac" via
`activity.elsewhere`. Phase 2 (signed-out people or two people on one repo): every device commits and pushes, pull
before push; `.md` conflicts through `mergedWords(base, mine, theirs)` with gix's merge-base, null → keep mine and
write theirs as `<Title> (conflict from <device>).md`; `.versions` through `mergeFiles`; `.glyph/notes/*.json` prefers
the side with `recordingMs` set, then theirs; binaries theirs with a `.conflict` copy of a differing same-named file;
three failed pushes → `failed('Someone pushed changes this device can't merge', fix: JobFix.open(settings))`.

**Restore.** Market › Back up to git › "I already have a backup" (or Settings › Library › Restore): URL + token,
`git_clone` shallow into the mirror, then an import pass: each `.md` written whole with its own front matter dates via
`store_apply` at its path (`workspaces/`, `orgs/`, `Inbox/` kept, not a dated workspace), `.versions` via
`versions_write`, `.glyph/notes/*.json` copied before the index reads the note, pictures and files via
`sync_put_file_path`, recordings by kind; the index rebuilds itself. Same-id collisions: `mergedWords` or a conflict
copy. `config.json` read last sets the remote. The same pass fed by a folder or the export zip's `Library/` +
`images/` + `recordings/` gives "Restore from a folder or ghostmarkdown_*.zip", the drive backup's missing other half.
When the account already holds notes the restore asks first (a conflict storm otherwise). A SAF library on Android
works because the pass goes through the library's commands, never the filesystem.

**Privacy.** The repo is plaintext: E2E ends at the device. The card, the setup intro and the README say so in one
sentence: "Anyone who can read this repository can read your notes. Make it private." Team notes under `orgs/<Org>/`
are excluded by default with a per-org switch, and the first commit says how many teammates' notes a switch includes
(today's drive backup copies them with no switch, so the plugin is stricter). The plugin warns once that `@@redact@@`
is a look and `location:` lines go to the remote; "strip places before commit" is a switch, off by default. Shares
and sites are server-side ciphertext and are not in the repo. An encrypted-repo mode (per-file AES-GCM under a key
derived from the account key, HKDF info `glyph/v1/git`; crypto.rs has the primitives) is possible later as a switch,
off by default; it costs the "readable on GitHub" promise and is incompatible with static hosting.

**UX.** Market card: id `git-backup`, "Back up to git", "Your notes, pushed to a repo you own", category
`connections`, hue green (downloads' family, brand-free), Lucide `git-branch` (distinct from the GitHub plugin's
mark), `standard: false`, permissions `network` and `notes`, `storage: ['glyph-git-status']`, `secrets:
['glyph-git-token']`. Setup (voiced under `git-backup-*`): Intro → Open "Make a private repository" (GitHub new-repo
page, quieter "Any other git host") → Open "Make a token" (scope spelled out) → Paste (URL, Token; shape checks) →
Check (`git_check`: reachable, writable, empty or already a Ghost.md repo → offers Restore) → Done ("First backup"
with the recordings switch and Back up now as a `personStarted` job). Settings page: status row ("Last pushed 14:02 ·
up to date", "3 notes to back up", "Waiting for Wi-Fi", red "Token refused · Sign in again"); Repository, Token,
Recordings switch + cap, Organizations (per-org), Cadence (Automatic / Hourly / Only when I tap), Back up now,
Restore…; Advanced: Use my GitHub token, Repo is on my own computer, Device that backs up. Jobs: `git-backup` (kind
`sync`, fills by bytes, `showAfter: 1 s`), `git-restore` (`personStarted`, chip "Restored 312 notes · Open"),
`JobTally('backup', 'backups')`. Errors in plain words with one fix: 401/403 → "GitHub didn't accept the token" with
`JobFix.signIn('git-backup')`; non-fast-forward after three merges → `JobFix.open`; a refused large file is skipped
and named with the cap suggested; empty remote → "Create the first commit"; network blips through `retrying()`.

**Plan.** Spike (S, two days): gix vs git2 decided on size and push. Slice 1 (L, about two weeks): Rust commands over
backup.rs with the mapper, the Dart plugin (manifest, setup, page, job, sealed token), the one-pusher claim,
`config.json`'s `git` key, `.gitignore`, `.gitattributes`, README. Slice 2 (M): restore from URL, folder and zip.
Slice 3 (M): recordings switch and cap, per-org switches, Phase 2 merge. Later: LFS, SSH on the Mac, encrypted mode,
static publish.

Decisions the plugin needs from Matt are in section 11 (numbers 9 to 17).

## 11. Open decisions for Matt

Recommended answer first.

1. **Attachments under the library?** Yes: move `images/`, `images/files/`, `video/`, `recordings/` to
   `Library/image/`, `file/`, `video/`, `recordings/` (the names the links already use), id-keyed, one move at open,
   read-both for a release. Alternative: leave them and let the git plugin's mapper copy them into the repo, which
   keeps a drive backup and an Obsidian-opened folder broken.
2. **Name of the committed config folder.** `Library/.glyph/config.json`, beside library.json, because `.glyph/` is
   already moved, exported and held for SAF trees. Alternative: a new `Library/.ghost/` as the task drafted, which needs
   the same plumbing twice.
3. **One front matter block, and the ticket key becomes `issue:`.** Yes, phased reader-then-writer across two releases
   with an every-device-first gate. Alternative: keep two blocks and accept that other apps show ticket properties as
   text.
4. **Trash as `trashed:` front matter, not a `Trash/` folder.** Yes. Alternative: Obsidian's `.trash/` folder, which
   hides the files from the index at once and reads as a deletion to sync and the CRDT unless the protocol learns
   "trashed".
5. **Updated time.** The git plugin restores mtimes from commit times on checkout; no key in the file. Alternative:
   `updated:` written on body saves, with the index taking the later of key and mtime.
6. **Versions switch.** `versions: true|false` as a library-managed key, with an existing `.versions` beside a personal
   note reading as on. Alternative: sidecar presence alone, which cannot express "off" for an org note.
7. **Canvases.** Derived `<Title>.canvas` beside each canvas note now; the stored form switches to `.canvas` only after
   readers ship. Alternative: leave as `.md` and accept Obsidian cannot open them.
8. **Shares.** Account state restored by sign-in, on the sites model (meta sealed under the account key on the server)
   with a non-secret `share: <id>` marker; fix the export's settings.json now. Alternative: a committed
   `shares.json` with keys, which makes a public repo a set of live read links.
9. **gix or git2.** gix, pure Rust, after a two-day spike proves push on Android; fall back to git2 with vendored
   OpenSSL on Android only if the spike fails. The policy question is whether a C+OpenSSL build step in
   tool/build-native.sh is acceptable.
10. **Mirror working tree or `.git` inside the Library folder.** Mirror at `<app data>/git/<repo-id>/`: a second copy
    of pictures on disk, but never corrupted by iCloud, Dropbox or SAF. Inside-Library as a Mac Advanced mode later.
11. **Recordings in the repo.** Off by default with a 50 MB per-file cap when on; LFS later. Alternative: on from day
    one with LFS, which gix does not have and would be hand-written first.
12. **Team notes in a personal repo.** Exclude every organization by default with a per-org switch. Alternative:
    include orgs the person owns.
13. **Multi-device.** Phase 1 one-pusher claim only; Phase 2 every-device merge later for signed-out people and shared
    repos. Alternative: merge from the start.
14. **Cadence.** Two minutes of quiet plus an hourly floor. Alternative: hourly only (fewer commits, less battery).
15. **Encrypted-repo mode.** None in v1: the plaintext-on-GitHub promise is the point. Alternative: a switch, off by
    default, incompatible with static hosting.
16. **Films in the repo.** Never (consistent with sync), the README says so. Alternative: `video/` under LFS behind
    an off-by-default switch.
17. **Static hosting.** v1 ships the repo layout only (GitHub's own viewer renders it); a `publish` step with
    Rendered.tsx as the one web renderer comes later; decide whether a Dart toolchain in CI is acceptable for
    build-time queries.
18. **Bare `@day` in a team note.** Insert `@<me> @2026-11-06` so authorship is in the words. Alternative: a bare team
    `@day` reminds every member who holds the note.
19. **Snippets as a note.** A `Snippets` note with a ```snippets fence (syncs and is in git). Alternative: a `snippets`
    key in the config, which is in git but not synced between devices.
20. **Note ids for foreign files.** Write `id:` whenever `set_front` writes any other key (one rewrite that already
    happens); key preference maps by path for never-touched files. Alternative: stamp every foreign file at first
    scan, which rewrites an Obsidian vault on first open.
21. **Merge undo.** Keep a version unconditionally for the two notes a merge rewrites substantively; `git revert` is
    the undo for the files. Alternative: a committed `merges/` directory.
22. **Calendars and webhook secrets.** Move Google's refresh token, iCal URLs and webhook secrets into `sealedKeys` so
    they are not plaintext on the device; keep all of them out of the library. Alternative: commit `{id, url, events,
    scope}` of outgoing hooks to the config, exposing the endpoint in a public repo.

## 12. What the critic found

A last reader looked for what the audit missed. These stand beside the inventory until each is folded into its slice; the high ones change the migration plan and the plugin design.

- **High.** Conflict copies and duplicated files break id-keyed state on a fresh clone. index_file gives a second file carrying an id that already exists at another live path a NEW random id but never rewrites the file's `id:`; the vault scan is sorted by path, so on a fresh device `Inbox/Plan (conflict from Mac).md` sorts before `Inbox/Plan.md`, KEEPS the original id, and the real note gets a random one. Every id-keyed ledger (filings, trash, meetings, shares, tape ids, `.glyph/notes/<id>.json`) then points at the conflict copy. The draft's Phase-2 merge design writes exactly such copies and its 'two devices both restoring' case is never considered.
  Fix: In §10 Multi-device and §3.10 'Three-way merge base': the conflict copy must be written with a fresh `id:` in its front matter (and no `.glyph/notes` sidecar), and the restore scenario must state that two devices restoring the same tree get identical ids only when no two files share an `id:`.
  Code: `tauri/src-tauri/src/library/index.rs:171-184 (index_file: `Some(other) if other.path != entry.path ... => (new_id(), false)`)`, `tauri/src-tauri/src/library/vault.rs:187 (markdown() sorted walk)`, `tauri/src-tauri/src/library/mod.rs:201-207 (stamp writes id only on save)`

- **High.** A team member's repo restore can resurrect deleted team notes. The team push step puts 'a note new to the team' as a row; on a fresh device `ctx.state.notes` is empty, so every `orgs/<Org>/` note from the repo that gets filed into the org workspace after sign-in is pushed as new, including notes a teammate deleted after the last push and notes of members who left. The 2026-10-26 guard only protects the delete direction. The draft's 'a team member's repo' case is absent; it only discusses privacy of including orgs.
  Fix: Add a 'team member restores from a repo' scenario to §9/§10: team notes are restored from the server after sign-in, not from the repo; a restore pass must pull the org channel before any push and must never put a note whose id the server holds as `deleted`.
  Code: `lib/team/sync.dart:1-25 (push: 'a note new to the team ... is put as a row')`, `lib/team/sync.dart:853-860 (deletion guard, one direction only)`, `lib/team/sync.dart:513-536 (adopt of pulled rows)`

- **High.** iCloud-evicted notes would be committed as deletions. `Library::texts()` silently skips a file whose read fails with NotDownloaded, and backup.rs removes from the target 'a note gone from the app since the last backup' by diffing the manifest. A chosen Library on iCloud Drive (the Mac default for many people) with evicted files produces 'Deleted: <title>' commits, and the same bug already affects the drive backup the plugin is modelled on.
  Fix: In §10 Repository layout: a not-downloaded note is 'unchanged, keep the last committed blob' (or `vault.fetch` + wait), never a deletion; note the same fix for backup.rs.
  Code: `tauri/src-tauri/src/library/relocate.rs:175-189 (texts: `Err(e) if not_downloaded(&e) => continue`)`, `tauri/src-tauri/src/backup.rs:17-20 (manifest-based removal)`, `tauri/src-tauri/src/library/vault.rs:56-59 (evicted_name)`

- **High.** iOS can neither open a clone nor run the cadence. library_folder.dart answers `FolderWay.none` on iOS (no folder picker, so 'pointed Ghost.md at it' is impossible there), and ios/Runner/Info.plist declares no UIBackgroundModes, so 'commit after two minutes of quiet, hourly floor while awake, push deferred to the hourly tick' and a 230 MB push all die when the app is suspended. Android's existing long work runs through foreground services (BackgroundJobs.kt, RecordingWorker.kt), which the `work::start`-only design never mentions.
  Fix: In §10 Cadence and Restore: on iOS restore is the import pass only and commits/pushes run in the foreground or on resume (BGProcessingTask would be a new entitlement); on Android a push rides the BackgroundJobs foreground-service pattern; pushes above N MB are desktop-pusher only until resumable uploads exist.
  Code: `lib/core/library_folder.dart:235-237`, `ios/Runner/Info.plist (no UIBackgroundModes key)`, `android/app/src/main/kotlin/com/mattssoftware/ghost_md/BackgroundJobs.kt:1-12`, `android/app/src/main/AndroidManifest.xml (foregroundServiceType="mediaProcessing|specialUse")`

- **Medium.** The generated `README.md` at the repo root is a note. The vault indexes every `.md` not inside a dot folder, and `library_path` accepts it from remote devices, so opening a clone as a chosen folder (or the restore pass copying the tree 'as is') makes README a note titled by its first line and syncs it to the account. export_commands already writes `README.txt` for this reason.
  Fix: §6 and §3.10: name it `README.txt` (or put the README under `.glyph/`), and say the restore pass skips it.
  Code: `tauri/src-tauri/src/library/mod.rs:176-178 (library_path)`, `tauri/src-tauri/src/library/vault.rs:187 (any .md indexed)`, `native/src/kept/export_commands.rs:241,281 (README.txt)`

- **Medium.** Decision 5 (restore mtimes from commit times) contradicts the restore design. The Restore section writes every .md through `store_apply`/library commands 'never the filesystem', and the only `keep_modified` implementation is FsVault's `set_modified`; a SAF tree has no way to set a document's last-modified (DocumentsContract exposes it read-only, LibraryDocuments.kt only reports it). So on Android SAF and in the import pass the mtime is the restore time regardless, and list order collapses exactly as the draft fears.
  Fix: §11 decision 5: either `store_apply` takes an `updatedAt` the import pass passes (and SAF accepts that it cannot), or choose the `updated:` key; the mtime-from-commit option only works for a Mac chosen folder.
  Code: `tauri/src-tauri/src/library/vault.rs:252-257 (FsVault::keep_modified)`, `android/app/src/main/kotlin/com/mattssoftware/glyph/files/LibraryDocuments.kt:89`, `tauri/src-tauri/src/library/index.rs (entry.modified_ms as updated)`

- **Medium.** Case-insensitive and normalization-insensitive filesystems are not considered. `free_path` tests uniqueness with `vault.exists`, which is case-folded on macOS/iOS but exact on Android app data and on a git host, and names.rs does no NFC/NFD normalization. A repo written from an Android device can hold `Plan.md` and `plan.md` (or two byte-forms of `Café.md`); a Mac or iPhone checkout silently merges them, one body overwriting the other.
  Fix: §7/§10: unique_name compares case-insensitively and NFC-normalizes titles; the plugin refuses a commit that would add a path differing only by case from one already tracked.
  Code: `tauri/src-tauri/src/library/mod.rs:271-275 (free_path)`, `tauri/src-tauri/src/library/names.rs:393-401 (unique_name)`, `tauri/src-tauri/src/library/names.rs:1-3 ('made safe for every file system' claims no case/normalization rule)`

- **Medium.** The web client is never mentioned. The web build keeps notes in IndexedDB (shelf.dart/idb_shelf.dart) and legacy `glyph-notes` in localStorage: a web-only person has no Library folder to commit, and git smart-HTTP from a browser is blocked by CORS at github.com, so the plugin cannot run there at all.
  Fix: Add one line to §10: the web client is out of scope for the plugin (its backup is the export zip or a device of the account that holds the pusher claim).
  Code: `lib/web/shelf.dart:1-3`, `lib/web/idb_shelf.dart:28`, `lib/web/web_core.dart:61-67`, `lib/web/page_secure.dart:23-35`

- **Medium.** Per-note AI state on the device is not inventoried (lib/ai, lib/format): `glyph-ai-marks` holds the AI's pending, unreviewed suggested edits per note keyed by body hash (lost on restore: a person loses proposals they had not yet kept or reverted), `glyph-ai-results` the home-card gist per note (derived), `glyph-ai-log` the AI's run log, `glyph-models-cannot-run` the device's model verdicts.
  Fix: Add four rows to §3.5/§3.6: marks keep-transient but say 'un-kept AI suggestions are lost' (or needs-decision: write them into the note as `++added++` marks); gist, log, verdicts derived-cache.
  Code: `lib/ai/marks.dart:18-45`, `lib/format/results.dart:17-28`, `lib/ai/log.dart:177`, `lib/ai/support/runnable.dart:20`

- **Medium.** The restore-then-sign-in scenario ignores that personal sync carries each note's `path` in the payload and in the particulars hash: a repo that lagged a folder move, or a note the adopter filed differently, differs from the server's path for the same id, and the doc never says which path wins or whether the file moves (or doubles) on first sync.
  Fix: Add a sentence to §3.2 'Account sync bookkeeping' and slice 9: on a path mismatch for the same id the server's path wins and the local file is moved (never copied); test it in the two-device fixture.
  Code: `lib/sync/notes.dart:656 (path in the payload), :700-707 (path in particulars)`

- **Low.** The Claude spend ledger and limit live only in the secure store, so a fresh device restarts the monthly spend at zero and the cap (`anthropic-limit`) stops protecting the person; the assistant provider choices are secure-store items synced through connections, not 'Claude settings'.
  Fix: §3.8 'Claude settings' row: split out `anthropic-spend` as a ledger that resets on restore (needs-decision: keep it on the server or accept the reset) and list the assistant choices as synced secure items.
  Code: `lib/claude (secure names anthropic-spend, anthropic-limit, anthropic-inbox, anthropic-watch, anthropic-effort, anthropic-model)`, `lib/assistant/assistant.dart:30-32 (glyph-assistant-chat, glyph-assistant-meetings)`

- **Low.** The calendar plugin keeps a Google ACCESS token, the calendar list, the sign-in flight, the last-read events and per-source status in device storage in the clear, beside the refresh token the draft does mention; none of these rows appear.
  Fix: Add a §3.8 row: events/status/calendar list derived-cache; `glyph-google-token` keep-secret-out and move into the secure store with the refresh token.
  Code: `lib/calendar/store.dart:1-14 (glyph-calendar-events, -status, glyph-google-token, glyph-google-calendars, glyph-google-signin)`, `lib/plugins/calendar/calendar.dart:46`

- **Low.** §3.8 says the export's `settingsKeys` writes a 'secret-free-by-intent settings file' while §3.7 (correctly) says the same file dumps `glyph-preferences` whole with share keys and the Google refresh token. settingsKeys is `glyph-preferences, glyph-plugins, glyph-workspace-current, glyph-note-bookmarks, glyph-book-spots`.
  Fix: Fix the §3.8 precedent sentence: the export file is NOT secret-free today; the config's guard is new work, not a precedent.
  Code: `lib/core/export_all.dart:64-70,310`

- **Low.** Device keys the inventory never names, so 'exhaustive' does not hold: glyph-academy/-banner/-skip-standard (lesson progress), glyph-activity (8-day tallies), glyph-guide-*, glyph-whats-new-seen, glyph-account-gate-seen, glyph-header-toolbar, glyph-haptics, glyph-tags-sort/-closed, glyph-all-notes-sort, glyph-tree-trash-open, glyph-aside-tab/-shown, glyph-plugin-setup, glyph-developer, glyph-wip-assistant, glyph-link-previews (300-entry preview cache), glyph-place-reminders (asked flag), glyph-webhooks-status, glyph-fill-told, glyph-meet-kinds-unsent, glyph-meeting-view, glyph-meeting-alerts-asked, glyph-discord-calls-told-off, glyph-update-alerts(-now), glyph-sample-note.
  Fix: Add one 'other device bookkeeping' row to §3.2 listing these keys as keep-transient, so a reader can tell omission from oversight.
  Code: `lib/academy/lessons.dart:301`, `lib/core/activity_log.dart:100`, `lib/core/link_preview.dart:99`, `lib/reminders/place_settings.dart:40`

- **Low.** Preference fields not in any table: `linkPreviews`, `canvasSnap`, `mapTiles`, `placeNames`, `focusMode`, `focusTypewriter`, `noteView`, `topBar`, `accent`, `rounding`, `assist`, `textSize`, `noteFace`, `iconPack`, `iconStyle`, `motionSpeed`, `ripples`, `calm`, `simple`, `formatted`, `homeLayoutChosen`/`experienceChosen`/`codeChosen`/`syncMeetingRecordingsChosen`. `mapTiles`/`placeNames` are library-ish (how geotags render) and `simple` is the mode every surface reads.
  Fix: Extend the §3.2 'Appearance and behaviour' row with the full key list and move `mapTiles`/`placeNames` into the `defaults` config proposal in §6.
  Code: `lib/core/preferences.dart:496-520 (constructor defaults), :553-630 (fromJson)`

