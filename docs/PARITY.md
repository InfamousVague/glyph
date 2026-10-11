# Parity: Ghost.md (Tauri) against Ghost Flutter

Audited 2026-10-10 by reading both trees. Nothing was built, run or installed: every status is what the source
shows. "Wired" means reachable from `lib/main.dart` through `lib/root/`.

- **Original**: `../glyph` at `05dd0efc`. Paths below are under `src/app/` unless they start with `src-tauri/`,
  `src/read/` or `docs/`.
- **Port**: this repository. Paths are under `lib/` unless they start with `android/`, `native/`, `assets/` or
  `packages/`.
- The target is **Android**. Mac and iPhone are noted only where they differ.

## Summary

| Features enumerated | match | differs | unwired | missing | n/a |
| --- | --- | --- | --- | --- | --- |
| 687 | 509 | 98 | 34 | 21 | 25 |

A row is one thing a user can see or do. A few gaps are rows of two tables (a Settings row and the feature behind
it, a notebook's journal under both the More sheet and Journals); the three lists at the end count each once:
12 missing, 25 unwired, 39 that differ.

What the counts say, in four lines:

- **The library is ported; the root has not handed all of it over.** Each of the 34 unwired rows is code the port
  has and nothing reachable from `lib/main.dart` calls, nearly always a seam `lib/root/` never fills. Most are a
  line or two each, and three of them change what a user is told
  is true: a shared link that does not follow edits, a renamed page that falls out of its notebook, a bell with no
  dot.
- **Three renderers were missing, and are in**: Mermaid (drawn since 2026-10-10: `lib/editor/diagrams`), code
  colouring and maths (`lib/editor/code`, `lib/editor/maths`; Missing 1 and 2 below say what each is held to, and
  Differs 40 and 41 where each still differs).
- **Three build switches hide whole areas**: the side key and assistant (on always in the original, off by default
  here and never walked), the account service, and updates (on in no build at all).
- **The words are the same.** Every Settings label and footnote, palette command, + row, More row and toast was
  compared; the differences are listed in their tables and come to about a dozen sentences, apart from dates,
  whose month and day names are English everywhere.

The port's tree moved while this was written (peers were committing): most of it was read at `931a7d8`, and the
root's wiring was checked again at `976690e` (2026-10-10 13:10). Line numbers are those commits'.

## Read this first: four things a build decides

These are not rows of their own in every table. Each turns a whole area on or off, and the rows below say "match"
for them only in a build where the switch is on.

| Switch | Where | What it gates | As things stand |
| --- | --- | --- | --- |
| `--dart-define=GHOST_API=…` | root/account_wiring.dart:56-68 (`accountBase`) | Account, sync, organizations, team notes, live typing, shared links, the notifications feed, From a shared link | Off in a build given none. A build that is not a release refuses ghostmarkdown.com and attack.fm outright. The original has the service's address built in (core/account/api.ts). |
| `--dart-define=GHOST_UPDATES=…` and `core/update_keys.dart` | core/updates.dart; core/update_keys.dart:14 (`trustedUpdateKeys` is empty) | Every update: the check, the card on home, About's Updates rows | **On in no build**: the key list is empty, so `Updates.forBuild` makes nothing. |
| `--dart-define=GHOST_MODELS=…` | root/voice_wiring.dart (`voiceMirrors`); main.dart:109 | Where the voice and language models are fetched from | A build that is not a release never asks the real mirrors; Get then says it could not. |
| `GHOST_ASSISTANT=1` (Gradle) | android/app/build.gradle.kts:20-46; android/app/src/main/AndroidManifest.xml (`@bool/ghost_assistant`) | The digital assistant, the side key, the launcher shortcut | Off by default. **The original's `main` has no such switch**: its manifest declares the three services, ASSIST, CAPTURE and the shortcut unconditionally. The flag the port's comments cite lives only on the unmerged branch `voice/assistant-flag`. |

## How to read the tables

`match`: ported, wired, and the same as far as the code shows. `differs`: there, and behaves or reads differently.
`unwired`: the code is in `lib/` and nothing reachable from the root uses it. `missing`: not in the port.
`n/a`: cannot apply to a Flutter app, or the original does not offer it on Android.

Two mechanical checks stand behind the "Words" rows, both run over the whole tree: every string literal and JSX text
of the original was looked for verbatim in the port's Dart, Kotlin and assets (about 3,600 distinct fragments, 340
not found, nearly all of them code, CSS or SVG), and the port's strings were looked for in the original the other
way. What survived reading is in the tables. And every optional constructor parameter of the port's main widgets was
checked against what `lib/root/` actually passes, which is where most of the `unwired` rows come from.

The guidebook is stale in places and the code was believed: the welcome guide has four pages, not six; the home page
has no To do list, no Academy card and no tape shelf; there are four top bar styles, not six; A board and A database
are on the +'s first page; maths and diagrams are drawn (KaTeX, Mermaid), not set as code.

## 1. Launch and the way in

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Launch screen: the ghost, its eyes, the notes count | launch/LaunchScreen.tsx:177; launch/eyes.ts | launch/launch_screen.dart:76; launch/eyes.dart; root/ghost_root.dart:2150 | match | |
| Launch screen's sync line ("Syncing your devices", "In sync", "Sync will try again") | launch/LaunchScreen.tsx:177 | root/update_wiring.dart:49-54; root/ghost_root.dart:2150 | match | In a build with an account. |
| Launch screen's update line ("Checking for updates", "… is out") | launch/LaunchScreen.tsx:177 | root/update_wiring.dart:35-45 | differs | Never drawn: no build has an updater (see Updates). |
| Launch held while an over-the-air build is applied (`holdUpdate`, auto reload) | App.tsx:1655; core/ota.ts | launch/launch_screen.dart (`holdUpdate`, `claimAutoReload` never passed) | n/a | No web bundle to reload into. |
| The app opens on the home page, never on the last tab | App.tsx:152 | shell/app_shell.dart; root/ghost_root.dart:1737 | match | |
| Use without an account | App.tsx:165 | root/ghost_root.dart:291-309 | match | |
| The way into an account, first on a signed-out open | shell/AccountGate.tsx:14; shell/useAccountGate.ts | shell/account_gate.dart:58; root/ghost_root.dart:2119 | differs | Only in a build given `GHOST_API`. With none there is no gate, and a way in says "This build has no account service. Notes stay on this device." (root/account_wiring.dart:70). |
| A fresh library gets the starter notes once (three tickets and their notebook, the board, a journal with an entry, the sample note) | core/seed.ts:68-90; core/starterNotes.ts | core/sample_library.dart:604; root/ghost_root.dart:1595-1601 | differs | Same notes. The sample note is made without its "## Pictures" section and the smoke photograph (core/sampleNote.ts:36-43; core/sample_library.dart:17). |
| A library that already has notes is never seeded | core/seed.ts:86-88 | root/ghost_root.dart:1596-1598 | match | |
| Edge to edge under the phone's bars; status bar ink follows the page | src-tauri/gen/android/…/MainActivity.kt:650 (`setLightChrome`) | main.dart:57; app/ghost_app.dart:217-221 | match | |
| The back gesture never leaves the app: a sheet first, then the screen | core/back.ts:86-90 | core/back.dart:82-193; shell/app_shell.dart:594 | match | |
| Reset rebuilds the app on the welcome walkthrough | core/reset.ts | core/reset.dart; main.dart:152-168 (`_Runs`) | match | |

## 2. The welcome guide

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Four pages: Welcome, Light or dark?, Choose your model, Learn it or just start | guide/pages.ts:14 | guide/pages.dart:12 | match | The guidebook's six pages went on 2026-10-02. |
| Dots, Next at the foot, the arrow that offers to take you down, Back, Skip / Close | guide/Guide.tsx:43; guide/useBottomNudge.ts | guide/guide.dart:47; guide/bottom_nudge.dart | match | |
| Swipe right and the back gesture step back | guide/Guide.tsx | guide/swipe_nav.dart; guide/guide.dart | match | |
| Welcome page: three points, "Notes you type or say." / "Notes you type." | guide/pages/Welcome.tsx:8-25 | guide/pages/welcome.dart:26-28,81 | match | |
| Theme page: Dark, Light, Match the phone, changing as tapped | guide/pages/Theme.tsx:6-28 | guide/pages/theme.dart:24 | match | |
| Model page: four models with sizes, "get it now", the download line, "… is on the phone." | guide/pages/Model.tsx:31-57 | guide/pages/model.dart:48,79; guide/guide_models.dart; root/ghost_root.dart:601-605 | match | Reads the phone's models once voice is made. |
| Last page: "Take the Ghost.md Academy" | guide/pages/Start.tsx:17-24 | guide/pages/start.dart:45; root/ghost_root.dart:2145-2148 | match | |
| Opens by itself on a first launch; again from Settings › About and the palette | shell/useGuide.ts | guide/guide_state.dart; root/ghost_root.dart:903-904,1977-1982,2002 | match | |
| Steps aside for a recorder and comes back at its page | App.tsx:1749 | root/ghost_root.dart:2133 | match | |
| "Not yet, finish reading." for a side key held too soon | guide/Guide.tsx:90; guide/tooSoon.ts | guide/guide.dart:369; guide/too_soon.dart; root/ghost_root.dart:489-490 | match | Reached only in a build with the assistant. |
| The marks table and the habits page (`MarksTable`, `phrases.ts`) | guide/MarksTable.tsx:18 (no importer) | guide/marks_table.dart, guide/phrases.dart (not imported) | n/a | Dead in the original too since the pages were cut. |

## 3. Home

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Search over notebooks and notes, narrowing as typed, with its clear button | home/HomeFilters.tsx:91-117; notes/allNotes.ts | home/home_filters.dart:315,391 | match | |
| Filters button and panel: Show (All, Notebooks, Notes, Pinned, each with its count) | home/HomeFilters.tsx:119-153; home/homeLayout.ts:46-51 | home/home_filters.dart:170,583-586; home/home_layout.dart:47-50 | match | |
| Panel: Workspace radios (Every workspace, each by name, an organization's with its mark) | home/HomeFilters.tsx:154-184 | home/home_filters.dart:613-628 | match | |
| Panel: New workspace, New organization (signed in), Edit {name} | home/HomeFilters.tsx:185-209 | home/home_filters.dart:655-657; root/ghost_root.dart:1831-1836 | match | |
| A chip under the search for each filter on, its cross taking it off | home/HomeFilters.tsx:213-231 | home/home_filters.dart:229-249 | match | |
| Layout Spotlight: Pinned as lines, Recent as four cards, the rest by when | home/homeLayout.ts:235-247 | home/home_layout.dart:235 | match | |
| Layout Cards: Notebooks and Notes as cards, 48 at most, "N more in All notes" | home/homeLayout.ts:216-221; home/HomeScreen.tsx:245 | home/home_layout.dart:37,226-229; home/home_screen.dart:481 | match | |
| Layout Timeline: Today, Yesterday, Earlier this week, This month, Earlier | home/homeLayout.ts:117-123,227-230 | home/home_layout.dart:130-136 | match | |
| Layout List: one line each | home/homeLayout.ts:222-226 | home/home_layout.dart:232 | match | |
| A card is the note drawn small, with its gist, notebook mark, ticket mark, journal's entries | notes/NoteCard.tsx:62; notes/NotePeek.tsx | home/note_card.dart:41; home/note_peek.dart; root/ghost_root.dart:1708 | match | Pictures and a film's still are drawn in it. |
| A row: kind mark, name, how it starts, pages / cards / entries counted, a tape's length, "Recording now", when | home/HomeScreen.tsx:328-389 | home/home_rows.dart:99,170-218 | match | |
| A pinned line wears its workspace's pill | home/HomeScreen.tsx:395-420 | home/home_rows.dart:309-340 | match | |
| Swipe a card, row or line: right to pin, left to archive, further to delete, each with Undo | notes/swipe.ts; notes/SwipeRow.tsx:57; App.tsx:1314-1322 | notes/swipe_row.dart:43; core/swipe.dart; root/ghost_root.dart:1825-1828 | match | |
| A note's menu (Open, Add a comment, Pin, Archive, Delete) on a mouse's right-click | notes/noteMenu.ts:37-47; notes/NoteMenu.tsx:33 | notes/note_menu.dart:76; home/note_card.dart:114; root/ghost_root.dart:1830,2024-2040 | differs | The port also opens it on a finger's long press, at the middle of the screen. The original leaves a press and hold to the swipe (notes/noteMenu.ts:9-11). |
| Notice: an invitation waiting, with Accept and Decline | notes/Notices.tsx:146; home/HomeScreen.tsx:217 | notes/notices.dart:483; root/update_wiring.dart:105-134; root/ghost_root.dart:567 | match | |
| Notice: the voice model coming down, or failed with Try again | notes/Notices.tsx:175; home/HomeScreen.tsx:218 | notes/notices.dart:548; root/ghost_root.dart:559-568 | match | |
| Notice: an update ready (Reload / Install, progress, "didn't install") | notes/Notices.tsx:27; home/HomeScreen.tsx:216 | notes/notices.dart:96-108; root/ghost_root.dart:566 | differs | Never drawn: no build has an updater. Reload can never apply. |
| The organizations you are in, a card each, with who is here | home/HomeOrganizations.tsx:45; home/HomeScreen.tsx:221 | home/home_organizations.dart:157; home/home_screen.dart:540 | match | |
| Filtered to an organization: its recent events beside the notes | home/HomeOrgEvents.tsx:43; home/HomeScreen.tsx:249 | home/home_org_events.dart:79; home/home_screen.dart:494 | match | |
| Empty states with the ghost: "A blank page.", "Nothing in X yet.", "Nothing has “…”.", "Nothing is pinned." | home/HomeScreen.tsx:226-237 | home/home_screen.dart:461-462,788 | match | |
| "All notes · N" at the foot | home/HomeScreen.tsx:243-246 | home/home_screen.dart:481 | match | |
| The dock: Write a note, Speak, Search and commands | home/HomeScreen.tsx:259-274 | home/home_screen.dart:944-963 | match | |
| Pull down to refresh: a sync, waited five seconds at most, then the notes read again | App.tsx:141-144; core/sync/engine.ts:285 | notes/pull_to_refresh.dart:70; root/ghost_root.dart:1771,1829,1861 | differs | The port only reads the library again. `SyncEngine.syncWithin` (sync/engine.dart:450) has no caller. |
| The page glides to its top when the workspace, filter or layout changes | core/glideToTop.ts; home/HomeScreen.tsx:126 | core/glide_to_top.dart; home/home_screen.dart | match | |
| The tape being recorded opens the meeting, not its note | App.tsx:1294-1297 | root/ghost_root.dart:779-783 | match | |
| To do list, Academy card, tape shelf, digest | home/HomeScreen.tsx:78-93 (props kept, nothing drawn) | home/dashboard.dart, academy/banner.dart (not imported) | n/a | Removed from the original's page (docs/DESIGN.md §147). |

## 4. Top bar, tabs, tab groups, back and forward

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Four bar styles: Classic, Ledger, Masthead, Islands | shell/topBar.ts:9-14; notes/NoteTabs.tsx:119 | shell/top_bar.dart:5-9; notes/note_tabs.dart:69 | match | |
| Controls: Home, sidebar, back, forward, people, bell, cog, the note's tools, the aside's icon | notes/NoteTabs.tsx:119 | notes/note_tabs.dart:69; notes/tabs/bar_parts.dart | match | |
| On a phone reading a note, the people icon, the bell and the cog step out | App.tsx:981,1497-1515 | shell/app_shell.dart:572,746-753 | match | |
| The bell wears a dot while something unread waits | App.tsx:1271-1272,1519; core/notifications/feed.ts | shell/app_shell.dart:95,757 (`unread`, default false) | unwired | The root never passes `unread`; `unreadNotifications` (orgs/ui/fed_notifications.dart:70) has no caller. |
| The people icon lists the organizations you are in | App.tsx:1516-1518 | shell/app_shell.dart; root/ghost_root.dart:1746,1765-1768 | match | |
| A tab for every note opened; its cross closes it; the + at the end | notes/NoteTabs.tsx; shell/useOpenTabs.ts | notes/tabs/tab_row.dart; shell/open_tabs.dart | match | |
| At most eight tabs | notes/openTabs.ts:16 (`MOST_TABS`) | core/tabs.dart (`mostTabs`); core/preferences.dart:467 | match | |
| A note with no words yet has no tab | core/store.ts (drafts) | root/ghost_root.dart:1397-1404,1742 | match | |
| Drag a tab along the row | notes/useTabDrag.ts; notes/tabDrag.ts | notes/tabs/tab_row.dart | match | |
| Tab menu: Rename (canvas or notebook), Add to a new group, Add to group, Remove from group, Close tab, Delete note | notes/TabMenus.tsx:57-76 | notes/tabs/tab_parts.dart:676-692 | match | |
| Group chip: fold, Rename, Colour (seven hues), Ungroup, Close group | notes/TabMenus.tsx:110-125; notes/GroupChip.tsx | notes/tabs/tab_parts.dart:519-561,736-754 | match | |
| The outline that slides from tab to tab, smoke at the row's ends | notes/useTabOutline.ts | notes/tabs/tab_row.dart | match | |
| A tab's name follows line 1 as it is typed | core/liveTitles.ts | note/note_screen.dart:412,660; shell/app_shell.dart:292 | match | |
| Tabs and groups kept, and synced with the account | core/preferences.ts (`openNotes`, `tabGroups`) | root/ghost_root.dart:1749-1762; sync/prefs.dart | match | |
| A notebook's pages keep to the notebook's one tab | App.tsx:263-268 | shell/app_shell.dart (`openNoteWithin`); root/ghost_root.dart:1036 | match | |
| Back and forward walk home, All notes and notes | shell/useTrail.ts:34; notes/visited.ts | shell/trail.dart:14; shell/visited.dart | match | |
| Rename a canvas or a notebook from its tab | App.tsx:1039-1051 | root/ghost_root.dart:1538-1547; note/open_screen.dart | match | |

## 5. The sidebar

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| A card over the note on a phone; docked as a column on a wide window with Docked chosen | notes/NotesDrawer.tsx:49; App.tsx:988-989 | notes/notes_drawer.dart:22; notes/floating_card.dart; root/ghost_root.dart:1867-1904 | match | |
| Tools: New note, New workspace, Search and commands, Show names only / each note drawn small, Browse files, Fold / Open every folder, Close | notes/NoteTree.tsx:272-298 | notes/note_tree.dart:461-479 | match | |
| Workspaces as folders that fold, with counts; notes in none; Archive (starts shut); Trash | notes/NoteTree.tsx:179-224,315; notes/tree.ts | notes/note_tree.dart:183-321; notes/tree.dart | match | |
| A workspace's "…" opens its sheet (rename, recolour, remove) | notes/NoteTree.tsx:179 | notes/note_tree.dart:301-310 | match | |
| An organization's workspace's "…" opens the organization's settings | notes/NoteTree.tsx:179; App.tsx:1591,1666 | notes/note_tree.dart:306-310 | unwired | `onOrganization` is never passed to `NoteTree` or `NotesDrawer` (root/ghost_root.dart:1667,1867), so the plain workspace sheet opens, whose organization row is disabled. |
| Trash: Restore, Delete for good, Empty asking "Delete N for good?" | notes/NoteTree.tsx:227-257 | notes/note_tree.dart:389-391,843 | match | |
| Each row a small drawing of the note, or names only (kept on the device) | notes/NoteTree.tsx:284; notes/NotePeek.tsx | notes/note_tree.dart:193; home/note_peek.dart | match | |
| A page of a notebook wears its mark | notes/BookPlaceMark.tsx; notes/NoteTree.tsx:154 | notes/book_place_mark.dart; notes/note_tree.dart:253 | match | |
| Speak and Settings at the foot | notes/NoteTree.tsx:340 | notes/note_tree.dart:505,877 | match | |
| The update's card on a wide window | App.tsx:1459,1586,1660 | root/ghost_root.dart:575-578,1683,1885 | differs | Never drawn: no updater. |
| Browse files opens the phone's Files app at the library, read-only | core/libraryFiles.ts; src-tauri/gen/android/…/files/LibraryDocuments.kt | core/library_files.dart:66-72; android/…/glyph/files/LibraryDocuments.kt; android/…/ghost_md/LibraryFiles.kt | match | The place is named "Ghost Flutter". Not on the Mac (no Finder reveal in this core). |
| A note's menu on a right-click of a row | notes/NoteTree.tsx (`onNoteContextMenu`) | notes/note_tree.dart:102,208 (`onNoteMenu`) | unwired | Never passed by the root (ghost_root.dart:1667,1867). A mouse's only, so the Mac's loss. |

## 6. All notes

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| The grid of cards, one to a row on a phone | notes/AllNotesScreen.tsx:183-188 | notes/all_notes_screen.dart:313 | match | |
| "Search your notes", every word anywhere, any case | notes/AllNotesScreen.tsx:105; notes/allNotes.ts | notes/all_notes_screen.dart:563; notes/all_notes.dart | match | |
| Order: Newest, A to Z, kept on the device | notes/AllNotesScreen.tsx:133-145 | notes/all_notes_screen.dart:601 | match | |
| "Tapes · N" and "Archived · N" toggles; the tally "N notes" / "x of y" | notes/AllNotesScreen.tsx:147-164 | notes/all_notes_screen.dart:265,284 | match | |
| The workspace pills, the chosen one's sheet | notes/WorkspaceBar.tsx; notes/AllNotesScreen.tsx:130 | notes/workspace_bar.dart:33; notes/all_notes_screen.dart:236-240 | match | |
| A press on an organization's pill or its sheet's row opens the organization | notes/AllNotesScreen.tsx:130,192; App.tsx:1281-1282 | notes/all_notes_screen.dart:239,414 | unwired | `onOrganization` and `onOrganizationSettings` are not passed (root/ghost_root.dart:1849-1866). |
| Empty and nothing-found states with the ghost | notes/AllNotesScreen.tsx:166-180 | notes/all_notes_screen.dart:293-301 | match | |
| Pull to refresh | notes/AllNotesScreen.tsx:191 | notes/all_notes_screen.dart:366 | differs | No sync, as on home. |
| A long press or right-click opens the note's menu | notes/NoteCard.tsx; notes/noteMenu.ts | root/ghost_root.dart:1862 | differs | As on home: the port adds the long press. |

## 7. The + sheet

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Note: "A page of markdown, typed or said." | notes/NewSheet.tsx:117 | notes/new_sheet.dart:233; root/ghost_root.dart:2051 | match | Opens ready to type, the keyboard up. |
| Entry in {journal}, with the template choice | notes/NewSheet.tsx:104-118; App.tsx:815-824 | notes/new_sheet.dart:214-234; root/ghost_root.dart:1235-1252 | match | |
| Canvas: "Cards on a page with lines between them." | notes/NewSheet.tsx:119 | notes/new_sheet.dart:235; root/ghost_root.dart:1653 | match | |
| Notebook: "Notes in an order with an index, or a journal of dated entries." | notes/NewSheet.tsx:120 | notes/new_sheet.dart:236; root/ghost_root.dart:1656 | match | |
| Meeting: "Record a meeting. The screen can go off. It is written up afterwards." | notes/NewSheet.tsx:121 | notes/new_sheet.dart:237; root/ghost_root.dart:2059 | match | Where the phone has the meeting service. |
| Meeting's switch for other apps' sound | notes/NewSheet.tsx:4; capture/systemSound.ts | root/ghost_root.dart:2060-2070 | match | |
| From a shared link: paste, Save a copy | notes/NewSheet.tsx:133-139; App.tsx:409-419 | notes/new_sheet.dart:242-249; root/ghost_root.dart:956-966,2057 | match | Not offered in a build with no service. |
| From an organization's +: what is made is filed in its workspace; no entry, meeting or shared link | App.tsx:679-683,1637-1642 | root/ghost_root.dart:1624-1627,2055-2059 | match | |
| A note made while a workspace is chosen is filed there | App.tsx:392-397; core/workspaces.ts | root/ghost_root.dart:1031-1038 | match | |
| A new note starts with where you are when Settings says so; the ask is introduced first | App.tsx:171-174,591-602 | root/ghost_root.dart:411-419,1635-1650 | match | |

## 8. A blank page: names and templates

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Four names under line 1 (the day in words, the date, date and time, the week), "Names for this note" | core/noteNames.ts:57-68; editor/nameChips.ts:107-130 | core/note_names.dart:56-69; note/note_screen.dart:1616-1695 | differs | Drawn as a strip under the editor, not a block after line 1. The day in words is English whatever the phone's language (core/note_names.dart:10-15). |
| A name another note has is not offered | core/noteNames.ts:68 | core/note_names.dart:69; note/note_builder.dart:85-88 | match | |
| The names wait for the keyboard and go at the first letter | core/keyboard.ts; editor/nameChips.ts | note/note_screen.dart:1368-1376 | match | Timing not compared on a device. |
| Eight template cards: A day, A meeting, A checklist, Notes on a book, A map at the top, A page to read, Bug report, Feature | notes/noteTemplates.ts:56-82; notes/TemplateCards.tsx:61 | notes/note_templates.dart:90-114; notes/template_cards.dart:47 | match | Names, sentences and bodies identical. |
| A day already taken makes "a second", and its card says so | notes/noteTemplates.ts:89; notes/TemplateCards.tsx:115 | notes/note_templates.dart:120; notes/template_cards.dart:205 | match | |
| A map at the top: dimmed with its reason under Local only or a refusal | notes/TemplateCards.tsx:111-114 | notes/template_cards.dart:99 | match | |
| Your templates: the Templates notebook, seeded the first time; its pages become the cards | notes/ownTemplates.ts:48-120; App.tsx:612-632 | notes/own_templates.dart:29-135; root/ghost_root.dart:1265-1285 | match | Toast "Your templates could not be made. Try again." on both. |
| Undo takes a template back to the blank page | editor/NoteScreen.tsx (`startFrom`) | note/note_screen.dart:604-615 | match | |
| A named or templated note nobody wrote in is taken back when left | App.tsx:933-970; core/untouched.ts:101 | root/take_back.dart; root/ghost_root.dart:373-388 | match | |

## 9. The note's screen

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Bar tools that come out of More while there is room: Share, Version history, Comment, Bookmark, Pin, Archive, Speak | editor/NoteScreen.tsx:1211-1218; editor/toolRoom.ts | note/note_screen.dart:1137-1145; note/note_tools.dart | match | |
| The view switch (Markdown / Formatted; Canvas / JSON; Index / Markdown) with its spoken words | editor/NoteTools.tsx:62-65,100 | note/note_tools.dart:44-47 | match | |
| More: the title; Talk into this note / Speak an entry | editor/NoteSettings.tsx:439-452 | note/note_settings.dart:399-410; note/note_screen.dart:1126 | match | |
| More: Name field for a canvas, notebook or journal | editor/NoteSettings.tsx:455 | note/note_settings.dart:420 | match | |
| More: Journal / "Keep it as a journal", and its page (what an entry starts with, the place switch, "Make it a journal", "Make it a notebook again") | editor/NoteSettings.tsx:251-282,456-462 | — (note/note_settings.dart:19 says so) | missing | `withJournal` / `withoutJournal` (book/journal.dart:139,142) have no caller. A journal's template can only be changed in its Markdown. |
| More: Ticket key field with its sentences | editor/NoteSettings.tsx:224-248,465 | — (`keyProblem`, book/tickets.dart:43, has no caller) | missing | Without it a notebook gets a key only by typing `key:`; New ticket is gated on the key. |
| More › Reading it: Look (Plain, Reading, Map) | editor/NoteSettings.tsx:472-489 | note/note_settings.dart:426,591-619 | match | |
| A reading note's lead line and "A line that says what it is about." | editor/openHeading.ts:132-187; editor/Editor.tsx:591 | editor/items/open_heading.dart:183 (`leadLine()` has no caller) | unwired | The Reading look sets the face and title size only. |
| More: Bookmark this line / Move or remove the bookmark | editor/NoteSettings.tsx:490-497 | note/note_settings.dart:427-431 | match | |
| The bookmark goes on the caret's line, else the line at the top of the page | editor/useBookmark.ts:64; editor/notePlace.ts:88-108 | editor/items/use_bookmark.dart:58 | differs | With no focus the port bookmarks line 1; `caretPlace` (note/note_place.dart:143) is never called. The button's lit state is not re-read after an undo. |
| More: Find and replace | editor/NoteSettings.tsx:498 | note/note_settings.dart:434; root/note_desk.dart:1240 | match | |
| More: Make a board | editor/NoteSettings.tsx:500 | note/note_settings.dart:436; note/note_screen.dart:1521 | match | |
| More › Comments: Comment; "N comments, M open" | editor/NoteSettings.tsx:506-532 | note/note_settings.dart:441-458 | match | |
| More › AI: Format, Summarize, Enhance, Fix spelling, Make a list, Continue | editor/NoteSettings.tsx:172,538-562 | note/note_settings.dart:122-129,467-481 | match | Labels and hints identical. |
| More › AI: the run that is on is pressed, with a dot | editor/NoteSettings.tsx:546,559 | note/note_settings.dart:17-18 | missing | |
| More › AI: Fill the blanks, with how many and who is asked online | editor/NoteSettings.tsx:178-184,538 | — (`fillPlanOf`, editor/ai/blanks.dart:276, has no caller) | missing | |
| More › AI: the Ask field | editor/NoteSettings.tsx:191-209 | note/note_settings.dart:482-486,689-736 | match | |
| More › Sharing rows | share/ShareRows.tsx:42; editor/NoteSettings.tsx:574 | share/ui/share_rows.dart:55; root/note_desk.dart:1256 | match | See Shared links. |
| More › Where it sits: Pin to the top / Unpin, Archive, Workspace | editor/NoteSettings.tsx:579-581 | note/note_settings.dart:497-502 | match | |
| More: Version history / Keep version history | editor/NoteSettings.tsx:583-597 | note/note_settings.dart:506-518 | match | |
| More: Add my location / Remove location, with every hint | editor/NoteSettings.tsx:142-164,599-605 | note/note_settings.dart:52-61,104-107,525-529 | match | |
| More › Linked to: each plugin's link and action, greyed with its reason | editor/NoteSettings.tsx:608-628 | note/note_settings.dart:534-551; root/note_desk.dart:1246-1249 | match | |
| More › Help: Formatting cheat sheet | editor/NoteSettings.tsx:631-634 | note/note_settings.dart:558-565 | match | |
| More: Move to Trash | editor/NoteSettings.tsx:637-639 | note/note_settings.dart:573 | match | |
| Version history page: versions by day, what a version changed, Restore version N | editor/VersionHistory.tsx:142-178 | note/version_history.dart:104,360-544 | match | |
| Version history: Name field, Save a version now, Stop keeping history | editor/VersionHistory.tsx:214-239 | note/version_history.dart:500-544 | match | |
| Version history: Share the versions file | editor/VersionHistory.tsx:229-232; core/versions/share.ts:12-43 | note/version_history.dart:264,520 | unwired | `NoteSeams.shareVersionsFile` is never given (root/note_desk.dart:1232-1330), so the row is off. On Android the original copies the file's text and says so. |
| Workspace page: pick, new, take out; an organization's asks twice | editor/WorkspacePicker.tsx:16 | note/workspace_picker.dart:21 | match | |
| The byline ("By x and Ghost") | authors/Byline.tsx:43 | note/byline.dart:25 | match | |
| A note opens where it was left; a bookmark wins | editor/notePlace.ts:133-219 | note/note_place.dart:168-277 | match | |
| Pinch to size the words, 0.7 to 2, kept | editor/pinchZoom.ts:14-106 | note/pinch_zoom.dart:22-39 | match | |
| Pull down in a note to refresh | editor/NoteScreen.tsx:1258 | — | missing | A note's page has no pull to refresh in the port. |
| While a tape plays, the transcript takes the page and the note waits under it | editor/NoteScreen.tsx:960-961,1341-1343 | note/note_screen.dart:1380-1381; tapes/transcript_words.dart | differs | The port lists the phrases under the note's words all the time. |
| A picture that did not come in says why in a line under the header | editor/NoteScreen.tsx:1251-1253 | root/note_desk.dart:817-820 | differs | A toast. |
| A save refused for good | editor/useNoteSaving.ts:146-156 (silent) | note/note_screen.dart:341 | differs | Port-only line: "This note changed somewhere else. What you write here now is not being saved." |
| A page renamed keeps its place in its notebooks and journals | editor/useNoteSaving.ts:121-127; book/followRename.ts:17 | book/follow_rename.dart:26 (not imported) | unwired | A renamed page drops out of its notebook's index. |
| The note unfolds with the hinge on a folding phone | core/unfold.ts:122 | core/unfold.dart:50; note/note_screen.dart:353,1433 | match | Never seen move (README). |
| Tags: `#web` chips; All notes' search finds them | editor/tags.ts:15; notes/allNotes.ts | editor/items/tags.dart:83; notes/all_notes.dart | match | There is no tag browser in either. |

## 10. The editor: Markdown

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Headings 1 to 6 by `#`; a line of dashes under a paragraph is not a heading | editor/glyphHighlight.ts:30-35; editor/language.ts:40 | editor/view/glyph_highlight.dart:40-47; editor/syntax/language.dart:52 | match | |
| Bold, italic, both, strikethrough, inline code | editor/glyphHighlight.ts:37-40 | editor/view/glyph_highlight.dart:52-58,79 | match | |
| Superscript `^nd^`, subscript `~2~` | editor/extended.ts:48,276-281 | editor/view/extended.dart:47,318-322 | match | |
| Links three ways; an address shown short, whole on the caret's line | editor/links.ts:150-157; core/shortUrl.ts:13-21 | editor/media/links.dart:142-204; core/short_url.dart:19-27 | match | |
| A tap on a link in the words puts the caret in it | editor/links.ts:114-117 | editor/media/links.dart:30-32 | match | |
| A backslash makes a mark mean itself | editor/viewMode.ts:35-41 | editor/view/view_mode.dart:47-55 | match | |
| Emoji `:name:`, 150 names | core/emoji.ts:13 | core/emoji.dart | match | |
| Maths `$…$` set as code where it cannot be drawn | editor/extended.ts:258,373 | editor/view/extended.dart:302,458-463 | match | The original's fallback is the port's only look. |
| Maths drawn as a formula (KaTeX), inline | editor/mathsDrawn.ts:132-173; editor/Editor.tsx:336 | editor/maths/maths.dart; editor/maths/formula.dart; packages/flutter_math_fork | differs | Drawn by flutter_math_fork, a port of KaTeX with KaTeX's faces, kept in the repo (packages/flutter_math_fork: its README names the nineteen places it was changed to agree with KaTeX). Thirty formulas and a hundred and fifteen pieces of them, held against KaTeX 0.16 (test/editor/maths/katex_test.dart), are as tall and as deep to a hundredth of an em, every one, and the seven KaTeX refuses are refused. Of eighty-three families of KaTeX's commands seven are not read (the test holds the list: `\phase`, `\angl`, `\edef`, `\set`, `CD`, `\copyright`) and a formula with one is shown as its source. The rows of `align`, `gather`, `equation` and `alignat` are numbered at the right of their line, counted through the note from its top, where the web's number is counted through what is drawn (Differs 41). A formula that cannot be read says so on a long press, in a panel, not a browser's tooltip. |
| A `$$` block on lines of its own, set in the middle of the page | editor/mathsDrawn.ts:141-157 | editor/maths/maths.dart | match | |
| Lists `-`, `*`, `+`, `1.`, `1)`, nested, with a hanging indent | core/itemSyntax.ts:31-33; editor/glyphLines.ts:44-93 | core/item_syntax.dart; editor/view/glyph_lines.dart:47-70 | match | |
| To-do boxes | editor/glyphHighlight.ts:52 | editor/view/glyph_highlight.dart:80 | match | |
| Quotes and quotes in quotes | editor/glyphLines.ts:32,124-127 | editor/view/glyph_lines.dart:39,98-101 | match | |
| Callouts: NOTE, TIP, IMPORTANT, WARNING, CAUTION | editor/extended.ts:65,283-336 | editor/view/extended.dart:63,324-437 | match | |
| A rule `---`; two spaces as a line break | editor/glyphHighlight.ts:48; editor/language.ts:39 | editor/view/glyph_highlight.dart:39,64 | match | |
| A table drawn off the caret, with alignment colons | editor/tables.ts:58-243 | editor/tables/tables.dart:87-104; editor/tables/table_box.dart:255 | match | |
| Tap a table to edit its pipes; "+ Column" and "+ Row" | editor/tables.ts:193-216 | editor/tables/table_box.dart:177-214 | match | |
| A block of code drawn as one card | editor/glyphLines.ts:34-35,119-122 | editor/view/glyph_lines.dart:41-42,93-96 | match | |
| Code coloured by its language | editor/language.ts:3,35-41 (`@codemirror/language-data`) | editor/code/code_highlight.dart; editor/code/languages.dart; editor/code/stream/js | differs | 142 of the pack's 143 languages are read: thirty-two by the web's own Lezer grammars' tables, run by a port of Lezer's parser; twelve of the pack's older modes ported to Dart by hand; and the other ninety-eight older modes run from their own JavaScript by a small reader of it (editor/code/stream/js). test/editor/code/conformance_test.dart holds a sample of every one to the web's runs, run for run. The one not read, Angular Template, no fence can ask for: its only name has a space in it. |
| Code themes: Pastel, Ink, GitHub, Solarized, One Dark, Dracula, Nord | editor/codeThemes.ts:18-31 | editor/looks/code_themes.dart:16-25,145-171 | match | |
| A `mermaid` block drawn as its diagram, with the reason when it cannot be | editor/mermaid.ts:36,195,218; editor/Editor.tsx:398 | editor/diagrams/diagrams.dart; editor/diagrams/store.dart; assets/diagrams/; android/…/ghost_md/DiagramRenderer.kt; apple/DiagramRenderer.swift | differs | Mermaid itself (the same 12.0.0) in a web view nobody sees, and the picture of it in the note. It is a bitmap made for the note's width, not an SVG; while its words change under it the block keeps the picture it has, where the page shows the words in between; a diagram that names a picture on the internet draws without it. |
| A definition: the term, then `: its meaning` | editor/extended.ts:51,243-254 | editor/view/extended.dart:50,288-299 | match | |
| Front matter as quiet keys, folded to a line of key names | editor/extended.ts:129-232 | editor/view/extended.dart:121-278 | match | |
| HTML kept as text, never run | editor/language.ts:46 | editor/code/code_highlight.dart | match | Its tags coloured as code, a script's and a style's words by their own languages. |
| The two views: Markdown keeps the marks dimmed, Formatted hides them off the caret's line | editor/viewMode.ts:19-76 | editor/view/view_mode.dart:30-85 | match | |
| "Write something." on an empty note | editor/Editor.tsx:419 | editor/placeholder.dart:33 | match | |

## 11. The editor: Ghost.md's marks and the five effects

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Spoiler (smoke until the caret is in it) | plugins/marks/index.tsx:64-71; editor/wispFormat.ts:49-71 | plugins/marks.dart:94; editor/marks/wisp_format.dart:56-70 | match | |
| Highlight, and a colour by name (blue, red, amber, green, teal, purple, gray) | plugins/marks/index.tsx:47-86 | plugins/marks.dart:75-103 | match | |
| Aside, Unsure, Shout, Added | plugins/marks/index.tsx:87-105,126-141 | plugins/marks.dart:104-119,133-148 | match | |
| Redact: a bar of ink that lifts at the caret | plugins/marks/index.tsx:106-125 | plugins/marks.dart:122-132; editor/marks/format_looks.dart:8-24 | match | |
| A note on a mark `(…)`, hidden, shown on a tap | editor/markNotes.ts:40-152 | editor/marks/mark_notes.dart:44-150 | match | |
| A note's or a footnote's panel closes when the page scrolls | editor/textPanel.ts:57 | editor/view/text_panel.dart:46-49 | differs | Nothing closes it on a scroll. |
| Hidden line `>\|` | editor/wispFormat.ts:73-79 | editor/marks/wisp_format.dart:85-115 | match | |
| Heat | plugins/marks/index.tsx:142-150; editor/textEffects.ts | plugins/marks.dart:150-157; editor/marks/text_effects.dart:35-39 | differs | Each letter bent through a field anchored to the page, not one field over the span. |
| Frost | plugins/marks/index.tsx:151-158 | plugins/marks.dart:158-165; editor/marks/text_effects.dart:40-43 | differs | No shader of its own yet: a dilated letter shape and tiled noise. |
| Wave, Shimmer, Haunt | plugins/marks/index.tsx:159-182 | plugins/marks.dart:166-189 | match | |
| Two on each side; they nest; they lift at the caret; they hold still under reduced motion | editor/language.ts:55-88; editor/textEffects.ts:161-490 | editor/syntax/language.dart:66-100; editor/marks/text_effects.dart:123-604 | match | |
| With the Marks plugin off they are plain characters | editor/Editor.tsx:317 | root/note_desk.dart:167,541 | match | |
| Words deleted by hand leave as smoke only with Ghostly typing on | editor/NoteScreen.tsx:1417 | root/note_desk.dart:549-553; ai/note_ai.dart:442 | differs | The note's editor always has typing's smoke: the switch reaches only what the AI writes. |

## 12. The editor: the small marks in a line

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Tags as chips | editor/tags.ts:15-36 | editor/items/tags.dart:83 | match | |
| A person `@name` with an initial in a ring | editor/fieldChips.ts:137-140 | editor/items/field_chips.dart:158-161 | match | |
| Due date chip: Tomorrow, Sat 3 Oct, red when passed, amber on the day | editor/fieldChips.ts:72-117 | editor/items/field_chips.dart:89-146 | differs | English day and month names whatever the phone's language. |
| Start, scheduled, done, repeat, the five priorities, `[key:: value]` | editor/fieldChips.ts:54-147 | editor/items/field_chips.dart:77-168 | match | |
| A tap on a date, priority or person chip opens its choices | editor/taskFields.ts:81-89; editor/ContextMenu.tsx:88-94 | editor/items/field_items.dart:170-253 | differs | A menu hung from the chip, where the original turns the band to that field's page (`openFields`, editor/band/context_band.dart:209, is never called). |
| Date page: Today, Tomorrow, Next week, Pick a date (the phone's calendar), Remove | editor/FieldItems.tsx:83-109 | editor/items/field_items.dart:82-106; core/phone_day.dart | match | |
| Priority page: Highest to Lowest and None; Person: Remove; Assign: people the note names, Someone new | editor/FieldItems.tsx:118-178 | editor/items/field_items.dart:107-158 | match | |
| Counter `[3/8]`: a tap adds one, a hold takes one away | editor/counters.ts:58-163 | editor/items/counters.dart:94-247 | match | |
| A sum `= 450 + 120 * 2` answered after its line | editor/sums.ts:60-64; core/sums.ts | editor/items/sums.dart:47-82; core/sums.dart | match | |
| Choices `( )`: one picked, the others cleared | editor/choices.ts:38-122 | editor/items/choices.dart:56-141 | match | |
| A footnote's marker raised; a tap shows its words | editor/footnotes.ts:60-143 | editor/items/footnotes.dart:76-164 | match | |
| `[[A note]]` opens it; a missing one is dashed and makes it | editor/wikiLinks.ts:29-126 | editor/items/wiki_links.dart:88-149 | match | |
| `[[A#^anchor]]` and `[[#^anchor]]` | editor/wikiLinks.ts:42; editor/boards/anchors.ts:42 | editor/items/wiki_links.dart:56-68; editor/items/anchors.dart:57-70 | match | |
| A tap acts on a completed tap, never on a scroll that began there | editor/wikiLinks.ts:114; editor/taskToggle.ts:47; editor/choices.ts:122 (`mousedown`) | editor/input/gestures.dart:171; editor/view/plugin.dart:331-333 (`pointerDown`) | differs | By the code a finger landing on a link, a box or a choice acts at once, even as a scroll begins. Wants trying on the Fold. |
| The bookmark `§§`: a ribbon and a line down the edge | editor/bookmarkLine.ts:71-119 | editor/items/bookmark_line.dart:84-109 | differs | No edge line for a bookmark kept on the device, nor with the caret at the signs. |
| Progress after a heading: "3 of 7", "All 7 done" | editor/headingProgress.ts:32-77 | editor/items/heading_progress.dart:58-138 | match | |
| "A name" said in an open first heading | editor/openHeading.ts:24-93 | editor/items/open_heading.dart:28-110 | match | |
| A linked item's pill and its row (Notion, GitHub) | editor/links.ts:51-147; editor/linkedRows.ts:55 | editor/media/links.dart:81-120; editor/media/linked_rows.dart:81 | match | |

## 13. The editor: pictures, films, memos, places, links

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| A picture drawn under its line, with its caption | editor/images.ts:43-79 | editor/media/images.dart:194-365 | match | |
| Add image and the +'s A picture open the phone's picker; kept at 1600 px | editor/useNotePictures.ts:61; core/imageShrink.ts:17 | root/note_desk.dart:955,969; android/…/ghost_md/Pictures.kt | match | |
| Paste a picture with the band's Paste | editor/ContextMenu.tsx:176-179 | editor/band/context_band.dart:478-481; editor/band/clipboard.dart:71-84 | match | |
| Paste a picture with a keyboard's Ctrl-V | editor/images.ts:134-164 | editor/media/images.dart:344 (`pasteImages` has no caller) | unwired | |
| A film: its still, its length, play in place, full screen | editor/videos.ts:53-455 | editor/media/videos.dart:80-272; android/…/ghost_md/FilmPlayer.kt | match | |
| The +'s A video; "Adding the video."; 500 MB kept free; MP4, MOV, WebM | editor/NoteScreen.tsx:863; src-tauri/gen/android/…/media/VideoPick.kt | root/note_desk.dart:1127-1168; android/…/ghost_md/Films.kt | match | |
| A voice memo plays where it sits; a quiet mark without its tape | editor/clips.ts:57-108 | editor/media/clips.dart:84; tapes/clip_player.dart | match | |
| A place line reads as its name, its map under it; a tap opens the maps app | editor/placeCards.ts:229; editor/MapCard.tsx:107-234 | editor/media/place_cards.dart:116; editor/media/map_card.dart:193 | match | |
| The +'s A place; "Finding where you are." | editor/NoteScreen.tsx:724 | root/note_desk.dart:1042-1120 | match | A name that comes late is not counted past the note's own tag (README). |
| The map at the top of a tagged note | editor/NoteScreen.tsx:1338 | note/note_screen.dart:1334-1361; root/note_desk.dart:1171-1185 | match | |
| A card under a line that is only a link: title, site, a line about it | editor/linkCards.ts:37-223; core/linkPreview.ts | editor/media/link_cards.dart:71-334; core/link_preview.dart | match | A long site and path is cut with an ellipsis. |
| Link previews off, and Local only, hold the fetch | core/linkPreview.ts:73-88 | root/ghost_root.dart:938-942 | match | |
| A canvas in a frame `![[…]]`: pan, zoom, Open | editor/canvasFrames.ts:111-125 | editor/media/canvas_frames.dart:123-200; root/note_desk.dart:573 | match | |

## 14. The editor: the +, the band, the keyboard

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| The + beside an empty line | editor/plusLine.ts:41-48 | editor/plus/plus_line.dart:48-55 | match | |
| No + while the AI writes into the note | editor/NoteScreen.tsx:1037 | root/note_desk.dart:823-828 | differs | The port has no such check; it hides the + while Find is up instead. |
| + rows: A picture, A video, A place, the date and time, A table, A board, A database, A note, A to-do, More | editor/addRows.ts:173-182 | editor/plus/add_rows.dart:236-246 | match | The date and time are written with English month names. |
| A place greyed with "Local only is on." | editor/addRows.ts:175 | editor/plus/add_rows.dart:238 | match | |
| A board: Fresh columns, From your tickets | editor/addRows.ts:276-281 | editor/plus/add_rows.dart:334 | match | |
| A database: To-dos due this week, Overdue to-dos, To-dos by person, To-dos on a calendar, A ticket board, Open tickets with estimates, A ticket timeline, Notes changed this week, How many to-dos are open, Write your own | core/query/templates.ts:29-43 | core/query/templates.dart:40-54 | match | |
| More: A heading, A bulleted list, A numbered list, A quote, A callout, A choice, A to-do with a due date, A block of code, A divider, Make this a ticket, A canvas, A footnote, A tag, A counter, A sum | editor/addRows.ts:202-217 | editor/plus/add_rows.dart:258-275 | match | |
| More: A diagram | editor/addRows.ts:211,366 | editor/plus/add_rows.dart:269,304 | differs | The same fence is written and never drawn. |
| More: A formula | editor/addRows.ts:212,364 | editor/plus/add_rows.dart:270,301 | match | |
| More: A blank for the AI | editor/addRows.ts:220 | editor/plus/add_rows.dart:278 | unwired | Gated by `AddConfig.blanks`, which root/note_desk.dart:944-959 never sets. |
| More: Blanks in the empty cells | editor/addRows.ts:221 | editor/plus/add_rows.dart:279 | unwired | The same gate. |
| More: Heated, Frosted, Wavy, Shimmering, Haunted words | editor/addRows.ts:222-233 | editor/plus/add_rows.dart:280-290; root/note_desk.dart:179-182 | match | |
| Which note? / Which canvas? pickers | editor/AddList.tsx:588-616 | editor/plus/add_list.dart:884-891 | match | |
| `/` on an empty line opens everything to filter (a hardware keyboard) | editor/insertPlus.ts:242-263,519-531 | editor/plus/insert_plus.dart:297-320,529-555 | match | |
| Press and hold opens the band over the words | editor/pressAndHold.ts:50-85 | editor/input/gestures.dart:278-308; root/note_desk.dart:931 | match | |
| The band over a drawn table | editor/drawnBlock.ts:62-71 | editor/input/gestures.dart:284 | differs | The port opens no band over any drawn block. |
| Band: Cut, Copy, Comment, Paste, Copy board, Find, Select all, Duplicate, Delete, Move up, Move down, Due date, Priority, Assign, Add to board, Board from list, Style, Add image | editor/ContextMenu.tsx:259-313 | editor/band/context_band.dart:518-572 | match | Labels and order identical. |
| Band: the plugin's send row (Notion, GitHub) on a list item | editor/ContextMenu.tsx:304; editor/NoteScreen.tsx:1465 | editor/band/context_band.dart:147,562 (`BandSend` built nowhere) | unwired | The swipe and the quiet word still send. |
| Style page: Bold, Italic, Struck, Code; the twelve marks; Heading, Quote, List, Numbered, To-do; Link, Table, Rule | editor/StyleItems.tsx:25-82 | editor/band/style_items.dart:55-117 | match | |
| Swipe a list item left to send it to Notion or GitHub | editor/swipeItems.ts:26-42 | editor/items/swipe_items.dart:42-48 | match | Let go short, the line snaps back at once. |
| The quiet word after a line a plugin could send | editor/suggestions.ts:36-97 | editor/items/suggestions.dart:36-69 | match | |
| A linked to-do and its task agree on done | editor/doneSync.ts:44-95 | editor/items/done_sync.dart:52-94 | match | |
| Enter carries a list on; Enter on an empty item ends it; Backspace takes a marker whole | editor/language.ts:44 | editor/commands/markdown_commands.dart; editor/input/ime.dart:12-19 | match | |
| Typing's haptics | editor/feel.ts:59-151 | editor/commands/feel.dart; editor/input/felt.dart | match | |
| Selection handles and the loupe | the WebView's own | editor/input/handles.dart:42-120 | differs | The app's own drawing. |
| Composing and autocorrect | the WebView's own | editor/input/ime.dart:1-49 | differs | The port's own client; not exercised with Samsung Keyboard (docs/STAGE4.md). |
| Spell-check underlines | editor/Editor.tsx:228 | — (editor/editor_widget.dart:27) | missing | |
| A screen reader reads the note's words | the WebView's own | — (editor/editor_widget.dart:27,482) | missing | The editor has no semantics. |
| Hardware keys: arrows, words, lines, select, move and copy lines, indent, undo and redo | editor/Editor.tsx:324 | editor/commands/commands.dart:1590-1645 | match | |
| Ctrl-C or Ctrl-X with nothing selected takes the line | CodeMirror's own | editor/editor_widget.dart:412 | differs | Does nothing. |
| An address pasted over a selection makes a link | editor/language.ts:47 (`pasteURLAsLink`) | — | missing | |
| Find and replace: Find, "n of m", previous, next, Replace, All, Done | editor/FindBar.tsx:60-131 | editor/find_bar/find_bar.dart:172-334 | match | |
| No keyboard accessory bar | — | — | n/a | Neither has one on Android. |

## 15. Comments

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| `[^c1]` as a round in its writer's colour, a ring once resolved; the words washed | editor/comments.ts:45-267 | editor/comments/comments.dart:69-374; root/note_desk.dart:577 | match | |
| The `comments` fence drawn as the list of threads | editor/comments.ts:142-228 | editor/comments/comments.dart:128-233 | match | |
| A thread's card: Reply, Resolve, Reopen, Delete thread | editor/CommentCard.tsx:133-168 | comments/ui/card.dart:354-452 | match | |
| New comment, All comments, and their sheet | editor/CommentSheet.tsx:36-69 | comments/ui/sheet.dart:97-138 | match | |
| Ways in: the band, the bar, More, Add a comment on a note's menu | editor/ContextMenu.tsx:268; editor/NoteScreen.tsx:1214 | editor/band/context_band.dart:524; note/note_screen.dart:1139; root/ghost_root.dart:2033-2036 | match | |
| Each person's colour where the note is filed in an organization | core/comments/colours.ts | comments/ui/note_colours.dart | match | |
| Comments on a canvas's cards | canvas/useCanvasComments.tsx; canvas/CommentMarks.tsx:27 | canvas/canvas_comments.dart; canvas/canvas_view.dart:1139 | match | |

## 16. Boards

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| A `board` fence drawn as columns of cards | editor/boards.ts:40-48 | editor/boards/boards.dart:112-120; root/note_desk.dart:567 | match | |
| Tap the board between its cards to show the fence | editor/boards/widget.ts:234-236 | editor/boards/boards.dart:41-44,107-109 | differs | A press on a board never moves the caret: the fence is reached from the lines round it. |
| Anchors `^name`, named from the first three words that carry meaning | core/boards/items.ts:112-130 | core/boards/items.dart:117-130 | match | |
| A card: three lines at most, a box or a dot, chips for due, priority and people | editor/boards/widget.ts:149-218; editor/boards/fields.ts:22-52 | editor/boards/board_card.dart:49-251 | match | |
| Tick moves it to Done; untick, back to the first column | editor/boards/cardEdits.ts:26-71 | editor/boards/card_edits.dart:50-88 | match | |
| Tap the words: the caret goes to the item's line | editor/boards/navigate.ts:13-20 | editor/boards/board_card.dart:187-193 | match | |
| Hold and drag a card between columns, the page scrolling at an edge | editor/boards/drag.ts:24-195 | editor/boards/board_box.dart:153-480 | match | Not carried under a real finger. |
| The chevrons; the menu (Move to …, Tick / Untick, Go to the line, Take off the board) | editor/boards/cardMenu.ts:55-65 | editor/boards/card_menu.dart:83-93 | match | Neither gives a card a plugin's rows. |
| The + by a column's name: "New card", Enter keeps the field open, Escape closes | editor/boards/composer.ts:32-86 | editor/boards/composer.dart:159-282 | match | |
| A card whose item has gone | editor/boards/widget.ts:140-159 | editor/boards/board_card.dart:46,187 | match | |
| The line under the board sets its height: drag, double-tap to reset, `height=` 5 to 60 | editor/boards/divider.ts:41-168 | editor/boards/divider.dart:60-139 | match | |
| The height line's arrow keys, Home and End | editor/boards/divider.ts:45-52 | editor/boards/divider.dart:14-16 | missing | A keyboard's only. |
| Make a board, Board from list, Add to board, Copy board | editor/NoteSettings.tsx:500; editor/ContextMenu.tsx:281-303 | note/note_settings.dart:436; editor/band/context_band.dart:537-561 | match | |
| A lane named on a board's own Speak ("Hey Ghost, add call Sam to Doing") | capture/place.ts:73,189 | capture/place.dart:169,344 | match | |

## 17. Tickets

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| `type: ticket` drawn as a card of properties over the words | editor/tickets.ts:181-280 | editor/tickets/tickets.dart:168-308; root/note_desk.dart:569 | match | |
| The `{}` button and the caret show the front matter as written | editor/TicketPanel.tsx:157-160 | editor/tickets/ticket_panel.dart:575 | match | |
| Status | editor/TicketPanel.tsx:89-95,335-346 | editor/tickets/ticket_panel.dart:280; editor/fields/field_picker.dart:207-218 | differs | The shared field sheet: icons for dots, and a "No status" row the original has not. |
| Assignee, Priority | editor/TicketPanel.tsx:96-115 | editor/tickets/ticket_panel.dart:299-320 | match | |
| Due, Start | editor/TicketPanel.tsx:116-120,234-271 | editor/tickets/ticket_panel.dart:321-335; editor/fields/field_picker.dart:266-296 | differs | A sheet (Today, Tomorrow, Next week, Pick a date, Remove) comes first; the original opens the calendar from the chip. |
| Estimate, Labels | editor/TicketPanel.tsx:121-124,274-308 | editor/tickets/ticket_panel.dart:337-356,729-772 | differs | Typed in a sheet, where the original types in place. |
| Blocked by, Parent, found by key or title | editor/TicketPanel.tsx:125-143,378-405 | editor/tickets/ticket_panel.dart:364-389,796-840 | match | |
| The line of fields still to add; the lock for a ticket waiting on another | editor/TicketPanel.tsx:163-194 | editor/tickets/ticket_panel.dart:589-704 | match | |
| New ticket in a notebook's index: just the title, Bug report, Feature | book/BookView.tsx:352-471 | book/book_view.dart:1044,1444-1545; root/ghost_root.dart:1104-1108 | match | Reached only once the notebook has a key (see More sheet). |
| The workflow: default statuses, `statuses:` of its own, grey / blue / green | core/properties.ts:217-260 | core/properties.dart:260-285 | match | |
| `[[GHO-12]]` with the title and the status's dot, struck when done; an unknown key dashed | editor/tickets.ts:204-258 | editor/tickets/tickets.dart:177-221; root/library_reads.dart:94-98 | match | The title is drawn a box to a word. |
| A ticket's key and status on its card, its row and its line in an index | notes/TicketMark.tsx:51; book/BookView.tsx:293-321 | notes/ticket_mark.dart; book/book_view.dart:1284-1410 | match | |

## 18. Queries and databases

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| A `query` fence drawn as what it finds, kept up as notes change | editor/queries.ts; editor/Editor.tsx:371 | editor/queries/queries.dart; root/note_desk.dart:571,794-796 | match | |
| `from:` tasks, tickets, notes; `#tag`, `[[notebook]]`, `@person` | core/query/read.ts:289 | core/query/read.dart:510 | match | |
| `where:` its operators, `today+7`, `priority >= high` | core/query/read.ts:61-466 | core/query/read.dart:132-698 | match | |
| `show:` list, table, board, calendar, gantt, count; `sort:`, `group:`, `columns:`, `total:`, `limit:` | core/query/read.ts:48-129 | core/query/read.dart:304-337 | match | |
| A line it cannot read, said with what is wrong | core/query/read.ts:312-597; editor/QueryView.tsx:96-104 | core/query/read.dart:661-826; editor/queries/query_view.dart:212-236 | match | Every sentence identical. |
| The view switcher, Build the query, the pencil | editor/QueryView.tsx:203-270 | editor/queries/query_view.dart:53-58,389-468 | match | |
| The builder: List, Only, Group, Show, with every choice | editor/QueryBuilder.tsx:48-139 | editor/queries/query_builder.dart:46-157 | match | |
| Tap a name to open; tick a to-do in its own note | editor/QueryView.tsx:320-341 | editor/queries/query_parts.dart:117-242; root/ghost_root.dart:1302-1304 | match | |
| A query's board: drag a card between lanes; the + on a lane adds a ticket | editor/QueryView.tsx:754-866; App.tsx:1157-1185 | editor/queries/query_board.dart:296-625; editor/queries/lane_carry.dart; root/ghost_root.dart:1133-1168 | match | |
| A query board's height line: arrow keys | editor/QueryView.tsx:985-1000 | editor/queries/query_board.dart:370 | missing | A keyboard's only. |
| Calendar: months, Mon to Sun, "Nothing on this day." | editor/QueryView.tsx:1014-1079 | editor/queries/query_view.dart:887-1117 | differs | The month's name is English (core/query/calendar.dart:87-92), where the original asks the phone's language. |
| Timeline (gantt) | editor/QueryView.tsx:1109-1132 (Mermaid's) | editor/queries/query_gantt.dart:1-181 | differs | The port's own drawing: weeks tick on Monday, names beside the bars, and no "This timeline could not be drawn here." |
| Count; a table's Total row | editor/QueryView.tsx:606 | editor/queries/query_view.dart:801,1136 | match | |

## 19. Notebooks

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| `book: true` drawn as its index | editor/NoteScreen.tsx:462; book/BookView.tsx | note/note_screen.dart:430; book/book_view.dart; root/note_desk.dart:1201 | match | |
| New notebook sheet: Name, Find a note, the pages picked in order, Make the notebook | book/NewBookSheet.tsx:73-199 | book/new_book_sheet.dart:157-272 | match | |
| Index: tap a page (made if not written), the arrows, the grip, the cross | book/BookView.tsx:286-304; book/rowDrag.ts | book/book_view.dart:1309-1413; book/row_drag.dart | match | |
| Add a page (Add and open, Add as a canvas), Add a note you have | book/BookView.tsx:352-427 | book/book_view.dart:1444-1546 | match | |
| Read straight through, with its rail | book/BookView.tsx:207-241; book/BookView.module.css:233 | book/book_view.dart:38-40,1113-1212 | differs | The way back to the index and the rail scroll away with the first page; on the page they stay at the top. |
| The notebook's own words before and after its pages | book/BookView.tsx:99 | book/book_view.dart:36-37,700-715 | differs | A `[[link]]` in them does not open. |
| A page's bar ("2 of 5", the pages either side) and its foot (Previous, Next) | book/BookNav.tsx:38-88 | book/book_nav.dart:152-370; root/note_desk.dart:1258-1259 | match | |
| A notebook remembers where it was left | book/bookSpot.ts:73-74 | book/book_spot.dart:99-125; root/ghost_root.dart:788-791 | match | |
| A renamed page keeps its place | book/followRename.ts:17 | book/follow_rename.dart:26 | unwired | See the note's screen. |
| Chapter numbers in titles put chapters in order without a notebook | book/chapterNumber.ts:70 | book/chapter_number.dart:82; aside/aside.dart:67-108 | match | |
| The aside ("Side panel"): the index beside the page, the open page marked | aside/Aside.tsx:82-186; notes/NoteTabs.tsx:338 | aside/aside_panel.dart:27-157; root/ghost_root.dart:1913-1918 | match | |

## 20. Journals

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| New journal: what each entry starts with (five choices), the preview, "With where you are" | book/TemplatePicker.tsx:44-140; book/journal.ts:45-52 | book/template_picker.dart:50-317; book/journal.dart:60-67 | match | |
| Placeholders `{{date}}`, `{{time}}`, `{{weekday}}`, `{{title}}`, `{{journal}}`, formats, the ISO week | core/template.ts:36-107 | core/template.dart:25-169 | differs | English names in en-GB or en-US order, where the original asks the phone's language. |
| New entry, named by the minute, " (2)" for a second | book/JournalView.tsx:72-73; book/journal.ts | book/journal_view.dart:122; book/journal.dart:191-203; root/ghost_root.dart:1173-1191 | match | |
| "Start the entry with": Usual, or another template | book/JournalView.tsx:157-173 | book/journal_view.dart:360-433 | match | |
| An entry nobody wrote in is taken back | App.tsx:933-970 | root/take_back.dart; root/ghost_root.dart:373-388 | match | |
| Speak an entry | App.tsx:731-765,843-885 | root/ghost_root.dart:715-750,1195-1231 | match | |
| Where each entry was written | book/journal.ts (`entryPlaceOf`) | root/ghost_root.dart:1187-1190 | match | |
| The months: three newest open, older ones a row each; an entry's day, time, place, first words | book/JournalView.tsx:49-137; book/journalMonths.ts:66-310 | book/journal_view.dart:51-277; book/journal_months.dart:15-18 | differs | Month and day names are English only. |
| An entry's bar walks the entries in the order they were written | book/BookNav.tsx:14-36; book/journalMonths.ts | book/book_nav.dart:51; root/library_reads.dart:127-130 | match | |
| Keep a notebook as a journal, change a journal's template, make it a notebook again | editor/NoteSettings.tsx:251-282,456-462 | — | missing | See the note's screen. |

## 21. Canvas

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| JSON Canvas read leniently and written exactly | canvas/jsonCanvas.ts:185-252 | canvas/json_canvas.dart:6-433 | match | |
| Cards: Words, A note ("Not in Ghost.md yet"), A link, A picture, A table, a group | canvas/Card.tsx:70-216 | canvas/card.dart:42-657 | match | |
| A chart: a card of Mermaid drawn as its diagram | canvas/Card.tsx:134; canvas/AddSheet.tsx:52 | canvas/card.dart:478,570; editor/diagrams/diagrams.dart; canvas/add_sheet.dart:85 | differs | Drawn on the card, read and open. The picture is made at the device's ratio for a canvas at its own size: zoomed in past that it softens, where the page's SVG stays sharp. |
| Double-tap empty space for a card of words | canvas/CanvasView.tsx (`DOUBLE_MS`) | canvas/canvas_view.dart:666-675 | match | |
| Add a card: Words, A note, A link, A picture, A chart, A table, A group, with their hints | canvas/AddSheet.tsx:45-85 | canvas/add_sheet.dart:72-162 | match | |
| Tap to pick, tap again to open; a title zooms to its card | canvas/CanvasView.tsx; canvas/Selection.tsx:38-70 | canvas/canvas_view.dart:392-396,625-656 | match | |
| Handles at the corners; on each side too with a mouse | canvas/Selection.tsx:24,66-67 | canvas/selection.dart:41-48,106,181 | match | Decided by platform, not by pointer. |
| The bar: write or open, draw a line, comment, colour (six and none), copy, take off | canvas/Selection.tsx:74-174 | canvas/selection.dart:232-237,380-396 | match | |
| A finger moves only the picked card; a held press lifts one; a group carries its cards | canvas/gestures.ts:22-185; canvas/edits.ts:134 | canvas/gestures.dart; canvas/edits.dart:138 | match | |
| Snapping to the grid's dots, the magnet, a tick as it lands | canvas/CanvasView.tsx:616; canvas/Selection.tsx:50 | canvas/canvas_view.dart:277,801 | match | |
| Lines: two taps, an arrow, words on the line, its cross; none to itself, twice, or to a group | canvas/lines.ts:256; canvas/LineWords.tsx:29-40; canvas/edits.ts:111 | canvas/lines.dart:274; canvas/canvas_view.dart:599-613,1247-1278 | match | |
| Pan, pinch, Fit, To card; Zoom in and out on a wide window | canvas/camera.ts:95-110; canvas/CanvasView.tsx:624-634 | canvas/camera.dart:109; canvas/canvas_view.dart:783-809 | match | |
| The keys: Delete, arrows, Alt, Ctrl/Cmd+D, Space, Escape, Shift+1, Shift+2 | canvas/CanvasView.tsx:379-452 | canvas/canvas_view.dart:688-728 | match | |
| The minimap from two cards: grow, drag, tap | canvas/Minimap.tsx:132-173; canvas/mapDetail.ts | canvas/minimap.dart:55-175; canvas/map_detail.dart | differs | A picture card is a plain block on the map. |
| Drop a note from the sidebar or a picture file onto a canvas | canvas/CanvasView.tsx (`onDrop`) | — | n/a | A computer's only; missing on the Mac. |
| A team's canvas: both edit at once, pointers in their colours, a ring on a card being written | canvas/useTeamCanvas.ts:62-88; core/team/canvas.ts | live/team_canvas.dart:18-170; root/note_desk.dart:1288-1289 | match | |
| Jump to cursor opens a canvas where a member's pointer is | notes/OrganizationScreen.tsx:421-422; App.tsx:1107-1112 | root/ghost_root.dart:338-343; root/note_desk.dart:882-883 | unwired | `_jumpTo` hands on only the caret (`seen.at?.cursor`), never the pointer, so the desk's own branch for a spot is never fed and the canvas is not centred. |
| The two example canvases | settings/ExamplesPane.tsx:26-27 | settings/panes/examples_pane.dart:46-47; root/ghost_root.dart:1987-1988 | differs | The example canvas is made without its picture card. |
| The AI on a canvas | — | — | n/a | Not built in the original either. |

## 22. Voice: the ways in and the recorder

The recorder's pure logic was compared mechanically across 42 file pairs: of 326 regex literals 320 are byte for
byte the same in the Dart and the other six were read by hand; every sentence, threshold and timing is in its
counterpart. The Kotlin the port took over (the three assistant services, MeetingService, OtherApps, SoundMix,
WavSpool, the four recordings files) differs from the original's by three to eight lines of header each.

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Speak in the dock, at the sidebar's foot, in the palette | home/HomeScreen.tsx:263-267; App.tsx:721,1585 | home/home_screen.dart:957-978; root/ghost_root.dart:709,1684,1814,2003 | match | Offered only once voice is made: an attach that fails or takes over three seconds leaves the run with no Speak (main.dart:107-113). |
| A note's mic, "Talk into this note" | editor/NoteScreen.tsx:1204,1218 | note/note_screen.dart:1126,1145 | differs | The original hides it once the note has a tape (Add takes its place); the port shows it all the same. |
| The tape's Add | tapes/NoteTape.tsx:130-135; editor/NoteScreen.tsx:1157-1164 | tapes/note_tape.dart:163; root/note_desk.dart:1302 | differs | The port does not save what is typed first, nor forget a Remove's pending Undo. |
| A journal's Speak an entry; an untouched entry spoken from its open line | App.tsx:731-765,843-885 | root/ghost_root.dart:715-750,1195-1231 | match | |
| Hold the side key (the phone's digital assistant), from any screen and over the lock screen | src-tauri/gen/android/…/AndroidManifest.xml:116-124,153-218; MainActivity.kt:532-589; capture/GlyphInteractionService.kt | android/…/AndroidManifest.xml (`.CaptureDoor`, `@bool/ghost_assistant`); android/…/ghost_md/MeetingBridge.kt:350-376; root/voice_wiring.dart:393 | differs | **Always there in the original; absent from the port unless built with `GHOST_ASSISTANT=1`.** No such build was ever made or walked (README). |
| Long-press the icon: Record a voice note / Record note | src-tauri/gen/android/app/src/channel/production/res/xml/glyph_shortcuts.xml:8-18 | android/app/src/main/res/xml/ghost_shortcuts.xml:7-18 | differs | The same words, and `android:enabled="@bool/ghost_assistant"`: absent in a default build. |
| The side key held again, or pressed, stops and saves | shell/useCaptureRoute.ts:157-161 | root/capture_route.dart:204-207 | match | Assistant builds only. |
| A locked phone steps back behind its lock at Done | MainActivity.kt:746-752; capture/CaptureScreen.tsx:899,1127 | android/…/ghost_md/MeetingBridge.kt:180-184; root/voice_wiring.dart:240-246 | differs | The lock is read once as a capture starts; the page asks at each use, so unlocking mid-take is seen only there. |
| A meeting being recorded takes every way in to its own screen | shell/useCaptureRoute.ts:116-118 | root/capture_route.dart:180-182 | match | |
| The top line: New note, Adding to "X", Adding to your last note, Adding to the note you named, Starting, Saving, the model's download, a problem | capture/screenText.ts:30-51 | capture/screen_text.dart:27-42 | match | |
| The counter; the rings from the microphone; the ghost, listening; "Start talking." | capture/CaptureScreen.tsx:1286-1323; capture/VoiceWaves.tsx | capture/ui/capture_screen.dart:1478-1636; capture/ui/voice_waves.dart | match | |
| How it ends, in a line (Tap Done to stop. / Press the side key to stop. / Hold the side key again to stop. / Stop talking to finish, …) | capture/screenText.ts:58-61 | capture/screen_text.dart:48-55 | match | |
| Things to say: To shape it, To send it somewhere, To ask the AI; "Meeting instead" | capture/SayCard.tsx:17-51; capture/tips.ts:48-195 | capture/ui/say_card.dart:45-139; capture/tips.dart:54-204 | match | |
| A tip after a pause of two and a half seconds (33 cues and four routing tips) | capture/tips.ts:48-158,199 | capture/tips.dart:54-164,207 | match | The same text in the same order. |
| The live page: words as they are heard, set as they will read, the newest kept in sight | capture/LivePage.tsx:57-136 | capture/ui/live_page.dart:256-335 | match | |
| Words arrive out of smoke (Ghostly typing) | capture/LivePage.tsx:58,93-97 | capture/ui/live_page.dart:256-266 | match | |
| Which engine is listening, on a tap of the top line | capture/diagnostics.ts:37-60 | capture/diagnostics.dart:66-90; capture/ui/capture_screen.dart:1698-1703 | match | |
| Discard, Done, New note, Not this note | capture/CaptureScreen.tsx:1205-1363 | capture/ui/capture_screen.dart:1403-1741 | match | |
| The back gesture saves; the screen going off saves; the screen is kept on | capture/CaptureScreen.tsx:1203,1225; MainActivity.kt:373-408 | capture/ui/capture_screen.dart:370,1752; android/…/ghost_md/MeetingBridge.kt:379-405 | match | |
| Stop when I go quiet (four seconds, once you have started) | capture/quiet.ts:12 | capture/quiet.dart:14-37 | match | |
| The microphone opens first, and what it hears while the model loads is kept | capture/useCaptureSession.ts:75-131; capture/audio.ts | capture/capture_session.dart:139-213; android/…/glyph/capture/DictationMic.kt | match | Android's own recorder through Dart, where the page had the WebView's. |
| Leaving the app in the middle of a take | the WebView keeps its microphone (not determined on a device) | android/…/ghost_md/MainActivity.kt:172-177; capture/device_mic.dart:183 | differs | The port closes the microphone at `onStop`, and nothing in the running app hears `closed`: by the code the rest of the take is not heard. Wants trying. |
| The microphone refused | capture/useCaptureSession.ts:136-140 (the WebView's own words) | capture/device_mic.dart:84-88 | differs | "Ghost.md needs the microphone to record." |
| The voice model fetched as the app opens; its line on home; Try again | capture/useVoiceModel.ts:56-62; notes/Notices.tsx:177-191 | capture/voice_model.dart:171-174; notes/notices.dart:561-580 | match | |
| A download that failed is tried again each time you come back to the app | capture/useVoiceModel.ts:58-62 | capture/voice_model.dart:117,174 (`onVisible` never given) | unwired | Only Try again or a relaunch retries. |
| Local only: "…so the voice model was not downloaded. Turn it off in Settings to get it." | capture/engine.ts:112 | capture/engine.dart:404-405 | match | |
| Rings rising from where the side key is, and Settings' height slider | removed 2026-10-02 | — | n/a | |

## 23. Voice: saying the marks, and spoken commands

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Title, Heading, Subheading; a short first sentence as the title | capture/spoken/blocks.ts:17-20,293-326 | capture/spoken/blocks.dart:23-28,332-338 | match | |
| New paragraph, a pause, New line, Divider | capture/markdown.ts:62-64; capture/spoken/extras.ts:58; blocks.ts:37 | capture/markdown.dart:79-81; capture/spoken/extras.dart:69; blocks.dart:52 | match | |
| Bullet point, a list in one breath, Number one, First / Then / Finally, The next item is, an announced list | capture/spoken/blocks.ts:19-35; lists.ts:22-134 | capture/spoken/blocks.dart:25-50; lists.dart:25-152 | match | |
| Check box, Remember to …, Done task, Option / Picked option, Counter zero of eight | blocks.ts:22-50; extras.ts:21 | blocks.dart:30-72; extras.dart:22 | match | |
| A due day, a priority, a person at the end of an item | capture/spoken/fields.ts:39-138; core/dayWords.ts:153 | capture/spoken/fields.dart:67-168; core/day_words.dart:168 | match | |
| Bold, italic, strike, Important, Quote, the five callouts, Hidden line | capture/spoken/inline.ts:37-112; blocks.ts:21-41 | capture/spoken/inline.dart:44-147; blocks.dart:29-62 | match | |
| Hashtag, note link, link … to …, footnote, bookmark this, define … as …, emoji, anchor, item link, superscript, subscript | capture/spoken/extras.ts:24-170 | capture/spoken/extras.dart:28-216 | match | |
| Code, a code block in fifteen languages, maths, calculate | capture/spoken/codeBlocks.ts:13-21; numbers.ts:62-117 | capture/spoken/code_blocks.dart:16-26; numbers.dart:84-174 | match | |
| The Marks plugin's cues and the five effects; a note on a mark | plugins/marks/index.tsx:68-179; extras.ts:55,150 | plugins/marks.dart:94-186; extras.dart:63,188 | match | |
| "Add a note to X, …", "new item for X", "Put this in X", "Move this to X", "New note", read without the keyword only when plainly one | capture/liveCommand.ts:223-360; capture/liveRoute.ts:1333 | capture/live_command.dart:388-576; capture/live_route.dart:1836 | match | |
| Finding the note by its words; the thresholds; to-do's spellings | capture/noteFind.ts:33-308 | capture/note_find.dart:48-426 | match | |
| Hey Ghost (hi, OK, so; Glyph), its mishearings, lead-ins, a command that waits for its name | capture/command.ts:47-84; capture/liveRoute.ts:57,1162 | capture/command.dart:49-90; capture/live_route.dart:82-83,1591 | match | |
| The cards: Add to which note?, No note called "…", New note "…", Keep here; answered by voice; eight seconds | capture/liveRoute.ts:67,810,1262; capture/CaptureCards.tsx:61-70 | capture/live_route.dart:87,1220,1755; capture/ui/capture_cards.dart:380-397 | match | |
| The chips: Looking for, Say the note for, Added to, Now on X · under H, No note called … so it stays here | capture/RouteChip.tsx:49-99 | capture/ui/route_chip.dart:105-130 | match | |
| Where the words go: the list that fits, a to-do list, a paragraph, the list's own style | capture/place.ts:195-216; capture/listAppend.ts | capture/place.dart:373-391; capture/list_append.dart | match | |
| A notebook or a journal is never written into; over the lock screen no card and no shared note | capture/liveRoute.ts:558,794,1044-1046 | capture/live_route.dart:938,1206,1493-1495 | match | |
| A new list by name: "Create Packing", Create, Cancel | capture/command.ts:178,450; ai/ConfirmCard.tsx:24-40 | capture/command.dart:433,803; capture/ui/capture_cards.dart:409-452 | match | |
| Scratch that, Actually …, No wait, "add it to X instead", each with its chip and Undo | capture/takeBack.ts:66-379; capture/RouteChip.tsx:20-48 | capture/take_back.dart:116-466; capture/ui/route_chip.dart:85-89 | match | |
| What a recording cannot do, said on its chip | capture/liveRoute.ts:1531-1535; capture/CaptureScreen.tsx:979-989 | capture/live_route.dart:2066-2071; capture/ui/capture_screen.dart:1139-1152 | match | |
| Asks for the AI said into a note (Fix the spelling, Summarise this, Make this a list, Tidy this up, Carry on, a free ask) | ai/instruction.ts:84-170; capture/finalInstruction.ts:88 | ai/instruction.dart:142-197; capture/final_instruction.dart:166 | match | |
| No always-on microphone: a command is heard only inside a recording | capture/useCaptureSession.ts | root/voice_wiring.dart:8-9 | match | |
| A voice memo, a table, a picture, a board by voice | — | — | n/a | Neither recorder has a cue. |

## 24. Voice: Done, the better words, the review

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| The note is written once, at Done; nothing laid out is nothing kept | capture/CaptureScreen.tsx:858-1166 | capture/ui/capture_screen.dart:1002-1376 | match | |
| A take into a note you named opens it with "Added to X" and Undo, ten seconds | capture/landing.ts:31-36; editor/useLanding.ts:74 | capture/landing.dart:72-88; root/note_desk.dart:716-731 | match | |
| The Undo takes out exactly what went in, here and in other notes | editor/useLanding.ts:41-73 | root/note_desk.dart:738-768; root/ghost_root.dart:1334 | differs | Not the step that also takes off a lone where-written tag when the Undo empties the note (editor/useLanding.ts:51-55). |
| The Undo offered again after the app was stopped ("Voice command created / changed a note.") | shell/useHousekeeping.ts:56-78 | — (native/src/dispatch.rs:379 answers `latest_command_mutation`; nothing asks) | missing | |
| The tape's length and phrases kept with the note | capture/CaptureScreen.tsx:1097-1105 | capture/ui/capture_screen.dart:1303-1310; core/core_library.dart:365-371 | match | Written with the whole note, where the page has a command of its own. |
| Where the app lands after Done | shell/useCaptureRoute.ts:283-384 | root/capture_route.dart:360-420 | match | |
| Better words: queued after Done, one at a time, never under the recorder, a review or an open note, only if the note still reads as saved | capture/refine.ts:106-354 | capture/refine.dart:241-542; root/note_desk.dart:636,837 | match | |
| The queue looks again when you come back to the app | capture/refine.ts:226-229 | capture/refine.dart:275,427 (`onVisible` never given) | unwired | Its other kicks still run. |
| Review after recording: handed to the note that opens | capture/CaptureScreen.tsx:1129-1153; shell/useCaptureRoute.ts:381-386 | capture/ui/capture_screen.dart:1336-1365; root/capture_route.dart:404-408 | match | See AI for the review itself. |
| A new voice note's place is tagged once the recorder has gone | shell/useCaptureRoute.ts; core/location.ts | root/ghost_root.dart:492-496 | match | |

## 25. Meetings

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| The + sheet's Meeting and its sound switch; "Meeting instead" on the recorder's card | notes/NewSheet.tsx:121-131; capture/SayCard.tsx:43-49 | notes/new_sheet.dart:237-240; root/ghost_root.dart:2059-2070; capture/ui/say_card.dart:116 | match | |
| The note's title, "Meeting, 26 Sep 14:05" | capture/meeting.ts:43-52 | capture/meeting.dart:62-73 | differs | English months in en-US or en-GB order, where the original asks the phone's language. |
| The meeting's screen: the cassette turning, its lines, Done ("Stop and write up"), Discard | capture/MeetingScreen.tsx:68-143 | capture/ui/meeting_screen.dart:176-364 | match | |
| "Let Ghost.md tell you when it is written up." with Allow | capture/MeetingScreen.tsx:89-133 | capture/ui/meeting_screen.dart:201-262; root/ghost_root.dart:763-770 | differs | The host answers "asked" before the phone has, so a phone that blocks is still marked as asked. |
| The service and its notification: Recording · 12:40, Stop, Discard, Still recording?, Writing up, Written up: {title} | src-tauri/gen/android/…/capture/MeetingService.kt; recordings/RecordingAlerts.kt:36-178 | android/…/glyph/capture/MeetingService.kt; android/…/glyph/recordings/RecordingAlerts.kt:39-181 | match | The same channel, the same words. |
| A tap on "Written up" opens the note, its summary landed first | recordings/RecordingAlerts.kt:159-178; App.tsx:422-426 | share/app_links.dart:23-28; root/ghost_root.dart:968-978 | match | |
| Other apps' sound, asked for with the screen-share prompt each time | capture/OtherApps.kt; MainActivity.kt:1055-1083 | android/…/glyph/capture/OtherApps.kt; android/…/ghost_md/MeetingBridge.kt:208-234 | match | The consent was not walked (README). |
| The write-up with the app closed; Write up straight away | recordings/RecordingWorker.kt, WriteUp.kt; settings/RecordingPane.tsx:163-169 | android/…/glyph/recordings/; settings/panes/recording_pane.dart:188-196 | match | |
| Settings' "Tell me when a meeting is written up" says when the phone blocks it | settings/RecordingPane.tsx:148-162 | settings/panes/recording_pane.dart:170-187; root/ghost_root.dart:875-883 | differs | `onAllowMeetingNotices` always answers true, so "Notifications are off for Ghost.md in the phone's settings." can never show. |
| A meeting unfinished when the app stopped is recovered at launch | MainActivity.kt:193 | android/…/ghost_md/MeetingBridge.kt:282-284 | match | |
| Trashing a meeting's note cancels its write-up; restoring asks for it again | notes/useNoteActions.ts:66-70,154-158 | notes/note_actions.dart:23-25 (`onTrashed`, `onRestored`) | unwired | The root gives `onTrashed` the place tag alone and no `onRestored` (root/ghost_root.dart:1373-1380). |
| "A meeting was written up" in the bell | ai/summaries.ts:688 | ai/summaries.dart:1095; root/voice_wiring.dart:373 | unwired | `Voice.make` is not given the feed's `record` (root/ghost_root.dart:445-453), so it is a no-op. |

## 26. Tapes and voice memos

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| The tape at a spoken note's top: its label, the day, Play / Pause, the time, the reels | tapes/NoteTape.tsx:45-128; tapes/TapeArt.tsx:42-60 | tapes/note_tape.dart:36-321; tapes/tape_art.dart | match | Played by the phone's own player (android/…/ghost_md/TapePlayer.kt). |
| Remove, with Undo; with voice memos it asks first, and Keep leaves it | tapes/NoteTape.tsx:136-156; editor/useNoteTape.ts:49-88 | tapes/note_tape.dart:164-178; root/note_desk.dart:670-701 | match | No warning tick. |
| The phrases lit as they are heard; a tap takes the tape there | tapes/NoteTape.tsx:208-257 | tapes/transcript_words.dart | match | Where they are drawn differs: see the note's screen. |
| Summarize on the tape; Replace for a summary you edited | tapes/NoteTape.tsx:157-195 | tapes/note_tape.dart:179-212; root/note_desk.dart:1307-1315 | match | |
| The tape says Summarizing, "Needs a model.", "The summary didn't come.", "The summary comes after the better words." | tapes/NoteTape.tsx:86-103,165-170 | tapes/note_tape.dart:57-78,143-155 | unwired | `NoteTape.queue` is never given (root/note_desk.dart:1298-1316). |
| "Summary is from before the last take." | tapes/NoteTape.tsx:101-102; editor/NoteScreen.tsx:1302 | tapes/note_tape.dart:153-154 (`summaryBehind`, ai/summary_keep.dart:83, has no caller) | unwired | |
| "Summarized "Title"" with Open, for ten seconds | shell/useHousekeeping.ts:100-106 | root/ghost_root.dart:525-531 | differs | "Summarized", with no title, for the toast's usual time. |
| A voice memo plays where it sits, one at a time | editor/clips.ts:36-116 | editor/media/clips.dart:169-229; tapes/clip_player.dart | differs | One player for the tape and its memos: after a memo, the tape's Play goes on from where the memo stopped. |
| A recording's row on home (the cassette, "0:40", "Recording now"); All notes' Tapes | home/HomeScreen.tsx:308-322; notes/AllNotesScreen.tsx:147-153 | home/home_rows.dart:30-105; notes/all_notes_screen.dart:265 | match | |
| The tape shelf on home | removed | — | n/a | |

## 27. AI: models, runs, the strip, blanks, the review, summaries, gists

The library under `lib/ai`, `lib/format`, `lib/editor/ai`, `lib/scene` and `lib/core/fill_*` is a faithful port: the
prompts, every strip line, toast, panel sentence and spoken ask compare the same, and the Rust that runs the model is
the original's own files, included by path (native/src/lib.rs:95-101). The gaps are in what `lib/root` hands over.
The More sheet's rows are in the note's screen's table, the palette's in the palette's, the +'s two blank rows in
the editor's, the tape's Summarize in Tapes', the spoken asks in Voice's: they are not repeated here.

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Four models, the default (Qwen3.5 4B), their sizes and sentences | core/ai.ts:40-68 | ai/backend.dart:56-82; settings/panes/ai_pane.dart:31-39 | match | The port keeps the catalogue twice. |
| Settings › AI › Model: a row each, Get, "Getting X, a of b. Keep Ghost.md open.", Use X, In use, Remove then Tap again, what is on the phone, a problem in the engine's words | settings/ModelCard.tsx:31-101 | settings/panes/ai_pane.dart:94-165; root/ghost_root.dart:857-872 | match | |
| "Can't run in this version of Ghost.md." | settings/ModelCard.tsx:85; core/runnable.ts:46-57 | settings/panes/ai_pane.dart:155; ai/support/runnable.dart:55-66 | match | |
| A download: one at a time, gone on with after a break, checked before it is kept; refused under Local only | src-tauri/src/model_files.rs:219-346; core/ai.ts:133-157 | native/src/models.rs:57-172; ai/backend.dart:717,749 | match | The same Rust. |
| Where a model comes from: attack.fm, then Hugging Face | src-tauri/src/llm/model.rs:86,98 | native/src/models.rs:47-52; root/voice_wiring.dart:85-96 | differs | A release build asks the same two. Any other build asks only where `GHOST_MODELS` says, so Get fails by design. |
| A mirror moved by a signed update | src-tauri/src/model_downloads.rs:84 | — (native/src/models.rs:14-17) | missing | Comes with updates. |
| Which model runs: the chosen one, else the biggest no bigger, else the smallest; a gist's is the smallest; a review's is a Qwen | ai/available.ts:55-74; ai/review.ts:55-61 | ai/available.dart:130-152; ai/review.dart:44-62 | match | |
| The engine: the phone's cores only, let go after five idle minutes | src-tauri/src/llm/engine.rs:245 | native/src/lib.rs:100-101 | match | The same file. |
| Why it cannot run, in a sentence: "Looking for the model.", "The AI needs a model on the phone…", its Local only form; as a toast with Get a model | ai/available.ts:86-97; editor/useNoteAi.ts:90-150 | ai/available.dart:173-185; ai/note_ai.dart:251-346 | match | |
| A note opened before the engine is up | editor/useNoteAi.ts:87 (read again as it changes) | root/note_desk.dart:478-490 (`late final`) | differs | A desk made while the root's `_aiWorld()` is still null has no AI rows, strip or drawn blanks until the note is opened again. If voice fails to attach at launch (main.dart:107-113), no note has them for that run. Wants trying on a phone. |
| A run: what is typed saved first, where the words go (in place, a summary above, a continuation under), the front matter never given | ai/start.ts:58-90 | ai/start.dart:97-131 | match | |
| "Nothing in the note yet.", "Say what to do with the note." | ai/start.ts:84-86 | ai/start.dart:124-127 | match | |
| One model at a time: a second run on the note replaces the first, another note's waits | ai/runs.ts:247-288 | ai/runs.dart:435,480 | match | |
| A run goes on when the note is left; lines land as they finish; lines you typed over are dropped, and a toast says how many | ai/useLanding.ts:30-78; ai/land.ts:156-177 | ai/note_landing.dart:63-126; ai/land.dart:198; ai/note_ai.dart:297-322 | match | |
| Links, tables, places and films carried as tokens; the GitHub plugin's briefing as context | format/pipeline.ts:34-66 | format/pipeline.dart:51-96; root/plugin_ground.dart:70-72 | match | |
| The prompts, the token budgets, the temperature | format/prompt.ts:237-254; ai/prompts.ts:166-175 | format/prompt.dart:222-236; ai/prompts.dart:150-155 | match | Compared by lines; the port's fixtures were not run. |
| The strip's line: Waiting for the model, Loading X, Reading the note a of b, Formatting with X at t tokens a second, Formatted by X in m:ss, Stopped, "It ran out of room. Try a shorter note." | ai/words.ts:30-52 | ai/words.dart:34-57 | match | |
| The strip: its bar, Stop, Put this away, Keep all, Undo ("Put back as it was.", "The note has changed since, so that run can't be undone.") | ai/AiStrip.tsx:62-173; editor/useNoteAi.ts:186-204 | ai/ai_strip.dart:245-303,546; ai/note_ai.dart:383-413 | match | |
| "N changes from the AI are marked in the note." | ai/words.ts:94-96 | ai/words.dart:92; ai/ai_strip.dart:252-258 | match | |
| The card on a tap of the line: the model, "On this phone", cores, CPU, memory, heat, tokens written, "Nothing leaves the phone." | format/AiCard.tsx:43-89 | format/ai_card.dart:105-209 | match | Before the engine reports, the port shows the phone's real cores and memory where the page had the browser's rounded ones. |
| The card's Battery ("82%, charging") | format/AiCard.tsx:83-85; format/battery.ts:34-38 | format/ai_card.dart:140; format/battery.dart:53-56 | unwired | `useBatterySource` has no caller, so there is never a reading. |
| The review's thinking, streamed in the card; the last eight runs with an Undo each; "Nothing yet." | ai/AiStrip.tsx:145-212; ai/log.ts:50,70 | ai/ai_strip.dart:320,599-682; ai/log.dart:180,206 | match | |
| The page keeps room under the strip | editor/useStripRoom.ts:14-31 | ai/note_ai.dart:497-498; root/note_desk.dart:993 | match | |
| What the AI changed, marked in the note: added words tinted, whole lines struck above, Keep and Revert on each, kept by typing on the line, there again when you come back | editor/aiChanges.ts:79-292; ai/marks.ts:38 | editor/ai/ai_changes.dart:82-179; ai/marks.dart:36-40; ai/note_ai.dart:323-373 | match | Square corners where the page rounds them. |
| Words taken out inside a line | editor/aiChanges.ts:166-167 | editor/ai/ai_changes.dart:114 | differs | One unbroken box, where the page's wraps with the line. |
| The AI's words arrive out of smoke (Ghostly typing) | editor/wispArrivals.ts | editor/ai/wisp_arrivals.dart; ai/note_ai.dart:445 | match | Drawn a letter at a time by a shader; not seen on a device. |
| A card's dot, "Changes from the AI are marked in this note" | notes/NoteCard.tsx:82-83 | home/note_card.dart:91,236-240 | unwired | `marked` is never given; `hasMarks` (ai/marks.dart:51) has no caller. |
| A card's spinner while its line is written | notes/NoteCard.tsx:80-81 | home/note_card.dart:88,235 | unwired | `working` is never given; `activeGist` (format/gist.dart:168) has no caller. |
| A blank, `{?…}`: the dashed square, its icon (calculator, calendar, globe, a question), and the words after it in each of ten states | editor/blanks.ts:21-283 | editor/ai/blanks.dart:334-386; editor/ai/blanks_paint.dart | match | One being filled does not breathe. |
| Worked out by the app itself: a total, an average, a count, days between, a weekday, a date, units, the time in a city; moving feasts refused | core/fillFacts.ts:28,318,613 | core/fill_facts.dart:390-898 | match | |
| The time in a city, said against your own: "Tokyo is 8 hours ahead of London today." | core/fillFacts.ts:607,665 | core/fill_facts.dart:955-963; editor/ai/blanks.dart:228 | differs | Always "…ahead of here today.": `BlankHooks.zone` is never given (ai/note_ai.dart:144-151). |
| Worked-out dates and weekdays in the phone's language; a zone's offset | core/fillFacts.ts:570-602 | core/fill_facts.dart:19-33,827-843 | differs | English. Offsets from a table exact for 2000 to 2040. |
| Looked up online: nine kinds, the same six addresses, "Look up blanks online" | core/fillLive.ts:23-52; ai/fills/web.ts:357-364 | core/fill_live.dart:28-62; ai/fills/web.dart:776-788 | match | |
| The asking itself | ai/fills/web.ts:339 (the browser's `fetch`) | ai/fills/web.dart:736-744 | differs | Follows no redirect (one reads as "Not found online"), gives up after ten seconds, names itself as the app. |
| "Waiting for a connection" ends when one is back | ai/fills/queue.ts:165-176,478-479 | ai/fills/queue.dart:381-415,713-714 | unwired | `startFills` is given no `onLine` or `onOnline` (root/ghost_root.dart:635-656): a parked blank is tried again only by the one-minute timer or when Local only goes off. |
| The Fill pill: Fill, Fill N, Filling, Waiting; filled by itself two and a half seconds after you pause | editor/blanks.ts:486-541 | editor/ai/blanks.dart:905-963 | match | |
| An answer kept as `??answer??(who, when, what was asked)`; its source decided by code; one from the web only if it stands in what came back | core/blanks.ts:24-341; ai/fills/source.ts:54-71; ai/fills/queue.ts:465 | core/blanks_syntax.dart:22-441; ai/fills/source.dart:66-84; ai/fills/queue.dart:700 | match | |
| An answer's panel: "X, from memory", "Asked on …", Keep as mine, Ask again, Put the question back, Write it in, Ask the model anyway | editor/fillPanel.ts:96-213 | editor/ai/fill_panel.dart:89-296 | match | The date is English. |
| The panel closes when the note scrolls | editor/fillPanel.ts:353 | editor/ai/fill_panel.dart:20-21,316; ai/note_ai.dart:377 | unwired | `closePanels` has no caller. |
| A blank filled in a note that is closed, "Filled 2 blanks in X." with Open; the first fill's toast; every press's toast; the strip's line and Undo | ai/fills/queue.ts:570-719 | ai/fills/queue.dart:829-1030; root/ghost_root.dart:635-655 | match | |
| Blanks and the pill inside a table's cells | editor/blanks.ts:691,757 | editor/ai/blanks.dart:1243; editor/tables/table_box.dart:139,201 | match | |
| The review after a recording: Listening again 40%, Comparing ("N places where the two models heard different words."), thinking it through, what it found marked in the note | ai/useNoteReview.ts:108-153; ai/review.ts:122-136 | ai/note_review.dart:213-288; ai/review.dart:139-155 | match | |
| What it found in other notes; "X found 2 things to look at…", "X found nothing to change."; no model to think with | ai/useNoteReview.ts:160-196 | ai/note_review.dart:299-342; root/ghost_root.dart:673-675 | match | |
| When it runs (the setting on, not locked, not a long take, not a take into another note); leaving the note stops it | ai/review.ts:48-52; capture/CaptureScreen.tsx:1141-1148; ai/useNoteReview.ts:81-88 | ai/review.dart:36-40; capture/ui/capture_screen.dart:1355-1362; ai/note_review.dart:160-178 | match | |
| The phone at work: the steps, the title and detail, Heat, CPU, Pace, Since, "It carries on behind the note. Nothing leaves the phone.", Stop, Back to the note | scene/AtWork.tsx:80-433; scene/steps.ts:61-254 | scene/at_work.dart:794-837; scene/steps.dart:94-310; root/ghost_root.dart:1948-1958 | match | Its drawing was not seen. |
| A summary: "## Summary" under the title, a title for a note named by its date, ticked to-dos carried over a remake, a long one read in pieces | ai/summaryText.ts:36-385; ai/start.ts:118-180 | core/summary_text.dart:30-424; ai/start.dart:159-251 | match | |
| A summary lands as marked changes in the open note; one that was ready, as the note opens | editor/useNoteAi.ts:123-135; ai/start.ts:187-206 | ai/note_ai.dart:286-293; ai/start.dart:256-281 | match | |
| The open note takes the phone's write-up the moment it lands | editor/NoteScreen.tsx:348-357 | ai/summaries.dart:637 (`onRecordingChanged` has no caller) | unwired | Taken only as a note opens (core/library.dart:242,373). |
| A note deleted for good is forgotten: its line, its runs, its marks, its kept summary, its job | notes/useNoteActions.ts:55-63 | notes/note_actions.dart:20-25 | unwired | Nothing is given to forget them (root/ghost_root.dart:1373-1380). |
| `authors:` written as a run finishes, your handle first; a stopped run signs nothing; a fill and a summary sign | ai/useLanding.ts:65-73; core/authors.ts:32-40 | ai/note_landing.dart:106-118; ai/support/authors.dart:22-37 | match | |
| A line under a card's title: the smallest model, one at a time, newest first, only with the app on screen, stepping aside for a recorder or a review | format/gist.ts:53-222 | format/gist.dart:66-288; root/ghost_root.dart:629-633 | match | |
| Which notes get a line: home's first 16 cards, All notes' first 24 | home/HomeScreen.tsx:101,138; notes/AllNotesScreen.tsx:54,79-80 | root/ghost_root.dart:631-633,1383-1393 | differs | Every note out of the trash: the phone works through the whole library. |
| Ask your notes; an ask on a selection; the GPU; AI on a canvas | — | — | n/a | None is in the original's code (`n_gpu_layers(0)`), whatever the port's README says of a selection. |
| The sentences only a browser shows ("The AI runs on the phone. Install Ghost.md on Android to use it.") | ai/available.ts:86-90 | ai/available.dart:173-178 | n/a | |

## 28. Account and sync

Everything here is in a build given `GHOST_API` (see the top). Every string of the Account page, the gate, the
recovery codes, the password and delete forms was compared and is the same.

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| An account service by default | core/account/api.ts:15 | root/account_wiring.dart:60-67; main.dart:93-101 | differs | None without the define; the real service refused in a build that is not a release. |
| Sign in; Create an account (the handle's and the password's rules and sentences) | core/account/account.ts:63-144; settings/AccountPane.tsx:129-176 | account/account.dart:36-143; settings/panes/account_pane.dart:169-242 | match | |
| Recovery codes: eight, Copy all, I've kept them | settings/AccountPane.tsx:45-60 | settings/panes/account_pane.dart:706-743 | match | |
| Lost the password: a code, a new password, a fresh sheet | core/account/account.ts:150-166 | account/account.dart:177-182 | match | A code that will not open the key says "This account's key would not open with that code."; the original says the raw failure. |
| The way in on a first signed-out open, "Use without an account" | shell/AccountGate.tsx:14-26; shell/useAccountGate.ts:27 | shell/account_gate.dart:31-115; root/ghost_root.dart:1527,2119 | differs | Not held back for a launch by the side key, and drawn over a recorder (the original has `!isRecording`). |
| Password and recovery codes: Change password, Make new recovery codes instead, Make new codes | settings/AccountPane.tsx:219-265 | settings/panes/account_pane.dart:472-546 | match | |
| Sign out: "Your notes stay on this device." | settings/AccountPane.tsx:399; core/sync/engine.ts:132-150 | settings/panes/account_pane.dart:446; sync/engine.dart:368-389 | match | |
| Delete account: what goes, the password, Delete my account, the service's refusal, the words after | settings/AccountPane.tsx:290-336 | settings/panes/account_pane.dart:351,591-605 | match | |
| The hero's status: Syncing, Synced just now, Synced 4 min ago, Waiting to sync, Sign in again to sync | settings/AccountPane.tsx:338-351; core/sync/engine.ts:82-87 | settings/panes/account_pane.dart:379-399; sync/engine.dart:105-111 | differs | After an hour the date is written "9 Oct, 16:05", not in the phone's own words. |
| "A note was changed on two devices at once…"; the unsent line | settings/AccountPane.tsx:353-362 | settings/panes/account_pane.dart:403-405 | match | |
| A device stays signed in by its own key; a 401 renews | core/account/account.ts:202-225; core/sync/engine.ts:496-499 | account/account.dart:232-250; sync/engine.dart:700-703 | match | |
| The kind of device the service is told | core/account/account.ts:73-80 ("Android", "Mac") | root/account_wiring.dart:149 | differs | Every device registers as "Ghost Flutter". Seen only by the service. |
| A list of your devices | — | — | n/a | Neither has one. |
| Sync runs at start, on return, four seconds after a change, every five minutes, one at a time | core/sync/engine.ts:53-54,226-257,516-560 | sync/engine.dart:63-66,403-434,722-763; root/account_wiring.dart:220-231 | match | |
| The steps in order: notifications, the organizations, notes, settings, team keys and team notes | core/sync/engine.ts:444-494 | sync/engine.dart:636-699 | match | |
| What travels: 34 settings | core/sync/prefs.ts:16-64 | sync/prefs.dart:36-82 | match | The same 34 keys in the same order. |
| Settings merged a key at a time; a newer build's unknown settings | core/sync/prefs.ts:75-126 | sync/prefs.dart:106-171,355-469 | differs | The port carries what it cannot read back to the account; the original drops it. Kinder. |
| A note changed on two devices is kept twice; deleted there and changed here comes back | core/sync/notes.ts:540-586 | sync/notes.dart:808-856 | match | |
| Recordings, pictures, versions files, the trash, tabs and groups; Sync meeting recordings; a recording over 64 MB stays | core/sync/notes.ts:136-151; core/sync/engine.ts:184-202 | sync/notes.dart:194-210; sync/device.dart:28-48; sync/local.dart | match | |
| Local only holds the pass off | core/sync/engine.ts:301-304 | sync/engine.dart:484-487 | match | |
| "Sync needs the newest Ghost.md." | core/sync/engine.ts:423-426 | sync/engine.dart:615-617 | n/a | The core is built with the app. |
| Live typing (trial): the switch, this device only, from the next note opened | core/live/enabled.ts:13; editor/useLiveNote.ts:15-37 | live/enabled.dart:9; live/open.dart:216-246; root/account_wiring.dart:191-193 | match | |
| The first one in brings the words; unsent changes kept as a note of their own | core/live/open.ts:28-38 | live/open.dart:229-231; root/ghost_root.dart:304-306 | match | |
| A dropped device comes back by itself | core/live/transport.ts:80,185-201 | live/transport.dart:54,189,271-281 | differs | The port lets the socket go while the app is behind another, and joins again as it returns. |
| Undo in a live note is this device's alone | editor/undoSlot.ts (`Y.UndoManager`) | live/editor_binding.dart:16-18 | differs | The editor's own history; an undo after another member wrote at the very same place can take out the wrong letters (README). |
| Versions: who kept each | core/versions/record.ts:63-65 | core/versions_record.dart:36-42,91-92; root/ghost_root.dart:282 | unwired | `VersionsRecord` is made without `keeper`, so every version is written by "me" and reads "You" for everyone. |
| Versions: kept on a two-minute pause and on leaving; an organization's notes keep them by default | editor/useVersionKeeping.ts:12-56; core/versions/record.ts:23-47 | note/version_keeping.dart:19-79; core/versions_record.dart:29-57 | match | |

## 29. Organizations and team notes

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| New organization, from Settings and from home's filters | settings/OrganizationsPane.tsx:55; home/NewOrganizationSheet.tsx:13-58 | settings/panes/organizations_pane.dart:192; orgs/ui/new_organization_sheet.dart:65-78 | match | |
| Its page: the hero, New, Invite, the other organizations as pills | notes/OrganizationScreen.tsx:163-361 | orgs/ui/organization_screen.dart:441-624 | match | |
| Notes filed there; Members with roles; Your colour; Activity | notes/OrganizationScreen.tsx:216-479 | orgs/ui/organization_screen.dart:351-436,986-1045 | match | |
| A member in the app: the dot, "here now", "editing Roadmap" | notes/OrganizationScreen.tsx:393-402 | orgs/ui/organization_screen.dart:806-850; root/ghost_root.dart:320-323 | differs | An untitled canvas reads "an untitled note". |
| The profile's button: Jump to cursor / Open the canvas / Open the note | notes/OrganizationScreen.tsx:422 | orgs/ui/organization_screen.dart:938 | differs | Always "Open the note". A note still opens at the member's caret. |
| Invite by handle, with the service's sentences | notes/OrganizationScreen.tsx:482-521 | orgs/ui/organization_screen.dart:1053-1110 | match | |
| Invite by link: how long it lasts, how many can join, Copy the link, Turn the link off | settings/InviteLinks.tsx:58-163; core/orgs/joinLinks.ts:47-89 | settings/invite_links.dart:96-262; orgs/join_links.dart:46-87 | match | |
| Send the link (the phone's share sheet) | settings/InviteLinks.tsx:67-68; share/ShareRows.tsx:98,168-174 | settings/invite_links.dart:221-224; share/ui/share_rows.dart:221 | n/a | Drawn only where `navigator.share` is, which Android's WebView has not. Never given in the port, so missing on the Mac and iPhone if their WebViews have it. |
| Accept and Decline: the bell's row, home's card, Settings' row | notes/NotificationsDrawer.tsx:209-213; notes/Notices.tsx:146-167 | notes/notifications_drawer.dart:650-780; root/update_wiring.dart:107-134 | match | |
| "Join X?" for a link that opened the app, kept a week across signing in | notes/JoinSheet.tsx:68-178; core/orgs/joinLinks.ts:93-118 | orgs/ui/join_sheet.dart:128-283; root/ghost_root.dart:2124-2130 | match | |
| Its settings: General (name, colour), Members, Workspace, Notifications (mute), Leave or Delete | settings/OrganizationSheet.tsx:126-558 | settings/organization_sheet.dart:245-806 | match | |
| Roles: Make admin / Make member, Hand over, Remove, Withdraw | settings/OrganizationSheet.tsx:193-202 | settings/organization_sheet.dart:626-634 | match | |
| Report a member or a note (an email) | settings/OrganizationSheet.tsx:76-80,534-539 | settings/organization_sheet.dart:30-35,323-329 | unwired | The row is drawn and cannot be pressed: `onOpenLink` is never given (root/ghost_root.dart:2096-2108), though the root holds the way to open one. |
| Edit on an organization's workspace, from home's filters, opens its sections | App.tsx:1233-1237 (no `from`) | root/ghost_root.dart:1835 | differs | Opens on Members under "← Organizations". |
| Left or deleted from the cog: home | App.tsx:1238-1248 | root/ghost_root.dart:2102 | differs | The sheet closes onto "This organization is not in your list any more." |
| The team's key turned when someone leaves | core/sync/engine.ts:321-378; core/orgs/orgKeys.ts:109-181 | sync/engine.dart:504-565; orgs/org_keys.dart:78-150 | match | |
| The workspace made on every device, with its mark; taking a note out asks twice | core/orgs/orgs.ts:328-343; editor/WorkspacePicker.tsx:24-78 | orgs/orgs.dart:311-335; note/workspace_picker.dart:59-118 | match | |
| A team's note: live with no switch, the others' carets with their handles, their selections washed | editor/useTeamNote.ts:41-148; editor/liveBinding.ts | live/open.dart:141-213; live/editor_binding.dart:93-210 | match | |
| The audit log: the filter, Everything / Notes / Team, a change opened, Open the note, Only this note | notes/OrganizationLog.tsx:50-346 | orgs/ui/organization_log.dart:256-844; root/ghost_root.dart:1553 | match | |
| The audit log: whose change it was | core/versions/record.ts:63-65 | core/versions_record.dart:92 | differs | Every version is "me" (see Account), so the log says "You" for other members' changes. |
| The audit log: days and times; Back from an opened change | editor/versionWords.ts; notes/OrganizationLog.tsx:96 | orgs/ui/organization_log.dart:70-88; shell/app_shell.dart:523-527 | differs | English days in the phone's order; Back goes straight to the dashboard. |
| Home's cards and "Recent in X" | home/HomeOrganizations.tsx:17-66; home/HomeOrgEvents.tsx:22-80 | home/home_organizations.dart:156-180; home/home_org_events.dart:60-170 | match | A news line wears a dot of its hue where the original draws the kind's mark. |

## 30. Shared links and the reader

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Share a read-only link; "The link is copied."; Copy the link, Stop sharing; the signed-out sentence | share/ShareRows.tsx:84-184 | share/ui/share_rows.dart:146-229; root/note_desk.dart:1256 | match | |
| What the link carries, in a sentence; Share where it was written; Share the places in it | share/ShareRows.tsx:14-25,150-163; share/share.ts:354-378 | share/ui/share_rows.dart:39-49,202-220; share/share.dart:430-451 | match | |
| The bar's Share and its sheet | editor/NoteScreen.tsx:1212,1486-1489 | note/note_screen.dart:1137; share/ui/share_rows.dart:257-279 | match | |
| **Your edits follow**: a share sealed again a few seconds after a save | share/share.ts:424-442; src/main.tsx:30 | share/share.dart:518-530 (`follow` has no caller) | unwired | Only a tick changed re-sends a share. Settings still says "Your edits follow it." A picture that was lacking is never sent later either. |
| A notebook's share: the index and every written page; a journal an entry at a time | share/share.ts:210-223; share/ShareRows.tsx:104-110 | share/share.dart:301-320; share/ui/share_rows.dart:175-176 | match | |
| Pictures packed in, about 4.4 MB; the refusal's sentence | share/share.ts:98-185 | share/share.dart:134-274 | match | |
| Pictures redrawn at 1024 px when they will not fit | share/share.ts:149-152; core/images.ts:214-217 | sync/device.dart:56-96 | differs | PNGs only: a phone's JPEGs are left out where the original draws them smaller. |
| The link: `ghostmarkdown.com/read.html#id.key` | share/share.ts:65-66,190-192 | share/share.dart:105-109,279 | match | A share made against a local service still names the real page. |
| Settings › Shared links: Copy, Stop, "A note not on this device", "A link no device lists", Take down | settings/SharedLinks.tsx:9-119 | settings/shared_links.dart:13-196 | match | |
| From a shared link: a copy saved as "Title (shared)", its pictures kept, a notebook's index repointed | share/share.ts:469-503; App.tsx:409-419 | share/share.dart:582-624; root/ghost_root.dart:956-966 | match | |
| The reading page in a browser: the banner, Save a copy, .md / .zip, Open in the Ghost.md app | src/read/Reader.tsx:70-265; src/read/JoinPage.tsx | — | n/a | A web page, served as before. Its "Open in the Ghost.md app" reaches whichever app Android hands `ghostmd://` to. |

## 31. Notifications

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| The bell's card: its rows by kind, sixteen sentences, the detail under a row | core/notifications/kinds.ts:20-234; notes/NotificationsDrawer.tsx:104-213 | core/notifications.dart:25-306; notes/notifications_drawer.dart:233-780; root/ghost_root.dart:1919-1945 | match | Every kind and sentence the same. |
| Read on a tap, Mark all read, Clear, Clear all | core/notifications/feed.ts:249-275 | sync/feed.dart:319-342 | match | |
| A row opens its note (a Claude edit at its first changed line) or its organization | notes/NotificationsDrawer.tsx:94-104; App.tsx:1613-1618 | notes/notifications_drawer.dart:126-136; root/ghost_root.dart:1920-1925 | match | |
| The empty state's words; signed-out and Local-only words | notes/NotificationsDrawer.tsx:144-165 | notes/notifications_drawer.dart:173-196 | match | |
| The empty state's ghost | notes/NotificationsDrawer.tsx:163 | notes/notifications_drawer.dart:193 (`emptyArt` never given) | unwired | |
| The four switches and the mutes decide what is drawn and counted; an invitation always shows | core/notifications/feed.ts:200-207 | core/notifications.dart:329-340 | match | |
| A note kept twice makes a row | core/sync/engine.ts:466; core/notifications/record.ts:27-47 | sync/engine.dart:660; sync/record.dart:38-65 | match | |
| The bell's rows as the phone's own notifications: posted as they arrive in the background, and by a worker about every fifteen minutes with the app closed | core/notifications/phone.ts:30-125; src-tauri/gen/android/…/notices/NoticeAlerts.kt:46-197, NoticeWorker.kt:27-186 | — | missing | No `notices` Kotlin, no channel, no Settings card. |
| A meeting's own "Written up" notification | recordings/RecordingAlerts.kt | android/…/glyph/recordings/RecordingAlerts.kt | match | |

The bell's dot is a row of the top bar's table, and the feed's row for a meeting written up is a row of Meetings':
both are unwired.

## 32. The command palette

Every command's id, label, group and keywords were compared line by line (commands/palette.ts:140-269 against
commands/palette.dart:266-378): they are the same. What differs is which doings the root hands it
(commands/app_commands.dart:108-163; root/ghost_root.dart:1990-2023).

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Opened by the dock's Search, the sidebar's Search and commands, Ctrl/⌘K | commands/CommandBar.tsx:25 | commands/command_bar.dart:40; root/ghost_root.dart:1414,1990 | match | |
| This note: Talk into this note / Speak an entry | commands/palette.ts:150-154 | commands/palette.dart:278-281; root/ghost_root.dart:2004 | match | |
| This note: Show it formatted / Show the marks | commands/palette.ts:156-159 | commands/palette.dart:282-286 | unwired | `setView` is never passed to `paletteDoingFor`, so the command is not offered. |
| This note: Fix spelling, Make a list, Continue | commands/palette.ts:161-165; App.tsx:1450-1452 | commands/palette.dart:288-292 | unwired | `noteAi` is never passed. |
| This note: Fill the blanks | commands/palette.ts:166; App.tsx:1368,1382 | commands/palette.dart:293 | unwired | Neither `noteAi` nor the open note's count of blanks is passed. |
| This note: Pin it to the top / Unpin it from the top | commands/palette.ts:168 | commands/palette.dart:295; commands/app_commands.dart:155 | differs | Asks the library directly, so no "pinned" haptic; the original goes through its note actions. |
| This note: Archive this note | commands/palette.ts:169; App.tsx:1444-1447 | commands/palette.dart:296; root/ghost_root.dart:2010-2015 | differs | The port also closes the note's tab; the original leaves it open. |
| This note: Delete this note; Close the {name} tab | commands/palette.ts:170-171 | commands/palette.dart:297-298 | match | |
| This note: File it in {workspace}; Take it out of its workspace | commands/palette.ts:172-178 | commands/palette.dart:299-305 | match | |
| This note: Put this tab in a new group / in {group}; Take this tab out of its group | commands/palette.ts:180-195 | commands/palette.dart:306-322 | match | |
| Notes: New note (⌘N shown), New notebook, New journal, New entry in {journal} (three at most) | commands/palette.ts:199-211 | commands/palette.dart:326-337; root/ghost_root.dart:1997-2000 | match | |
| Notes: Speak a new note, Home, All notes | commands/palette.ts:213-215 | commands/palette.dart:338-341 | match | |
| Open tabs: Go to {tab}, Close {tab}, Back, Forward | commands/palette.ts:218-227 | commands/palette.dart:344-353 | match | |
| Workspaces: Show all notes, Show {workspace} | commands/palette.ts:230-236 | commands/palette.dart:356-362 | match | |
| Notes by name: Open {note}, forty at most, a journal's entries only when typed for | commands/palette.ts:126-137,239-243 | commands/palette.dart:240-252,365-369 | match | |
| Look: Theme: Follow the phone, Light, Dark, Dawn, Boreal, Ember | commands/palette.ts:246-258 | commands/palette.dart:255-263,372-375 | match | |
| Ghost.md: Settings, Notifications, Organizations, Cheat sheet, Ghost.md Academy, The welcome walkthrough | commands/palette.ts:261-266 | commands/palette.dart:378-390; commands/app_commands.dart:145-150 | match | |

## 33. Settings

Every label and title of every page was looked for on both sides (286 of them; five are not in the port, listed
below), and every hint and footnote by the whole-tree check. The section list, its order, its search words and its
one-line readings are the same (settings/SettingsSheet.tsx:166-422; settings/settings_sections.dart:192-413).

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| The list of sections with their readings; a page of its own on a phone, a split view on a wide window | settings/SettingsScreen.tsx; settings/SettingsSheet.tsx:166 | settings/settings_screen.dart; settings/settings_sheet.dart:180-233 | match | |
| Search settings: every word must start a word; a result lights its setting; Enter opens the first | settings/settingsSearch.ts; settings/SettingsScreen.tsx:394 | settings/settings_search.dart; settings/settings_screen.dart:1217 | match | |
| Swipe right to step out of a page, left to go back in | settings/sectionSteps.ts | settings/section_steps.dart | match | |
| Sub-pages step back to their parent ("← Account", "← Plugins", "← About") | settings/SettingsSheet.tsx:323-398 | settings/settings_sections.dart:173-190,347-388 | match | |
| "Get a model" opens AI with the Model card lit | settings/SettingsSheet.tsx:136-138 | root/ghost_root.dart:683-686 | differs | Opens AI; no `setting` is named, so nothing is lit. |
| **Account**, signed out: I have an account, Create an account, Lost the password | settings/AccountPane.tsx:206-208 | settings/panes/account_pane.dart:64-66 | match | In a build with no service a press says so. |
| Account, signed in: the hero (handle, End-to-end encrypted, how sync stands) | settings/AccountPane.tsx:340-380 | settings/panes/account_pane.dart:380-410 | match | |
| Account › Sync: Sync now, Sync meeting recordings, Live typing (trial), Password and recovery codes, Sign out | settings/AccountPane.tsx:383-399 | settings/panes/account_pane.dart:51-55 | match | |
| Account: Your colour | settings/ColourCard.tsx:31 | settings/colour_card.dart:43 | match | |
| Account: Shared links (Copy, Stop, Take down) | settings/SharedLinks.tsx:84 | settings/shared_links.dart:175 | match | |
| Account › Privacy: Local only, Link previews, Look up blanks online, Privacy policy, and the footer | settings/PrivacyCard.tsx:38-69 | settings/privacy_card.dart:20-58 | match | |
| Account › Location: Map on a tagged note, Place names, Tag new notes with my location, and the refusal's line with Open settings | settings/LocationCard.tsx:62-85 | settings/panes/account_pane.dart:38-41,766 | match | |
| Account: Delete account | settings/AccountPane.tsx:292-297 | settings/panes/account_pane.dart:60 | match | |
| **Organizations**: Your organizations, Invitations with Accept and Decline, New organization | settings/OrganizationsPane.tsx:55-113 | settings/panes/organizations_pane.dart:23-136 | match | |
| **Workspaces**: Your workspaces, New workspace, Organizations' workspaces | settings/WorkspacesPane.tsx:32-41 | settings/panes/workspaces_pane.dart:14-103 | match | |
| **Notifications**: Team, Claude, Summaries, Conflicts, with their hints and footnotes | settings/NotificationsPane.tsx:32-77 | settings/panes/notifications_pane.dart:14-16,114 | match | |
| Notifications: Mute an organization | settings/NotificationsPane.tsx:79-89 | settings/panes/notifications_pane.dart:17 | match | |
| Notifications › On this phone: Phone notifications, and Allow notifications when Android blocks them | settings/NotificationsPane.tsx:90-108; core/notifications/phone.ts | — | missing | With the worker and the alerts behind it (see Notifications). |
| **Library folder**: Where your notes are, Choose a folder…, Use this folder, Use Ghost.md's own folder, Bring a copy back / Start empty / Stay in the folder, Good to know | settings/LibraryFolderPane.tsx:109-168 | settings/panes/library_folder_pane.dart:15-264; root/ghost_root.dart:796-798 | match | |
| **Backup**: Plug in a drive, Back up to …, Backing up, the tree of what a drive holds, Eject | settings/BackupPane.tsx:173-231; settings/BackupTree.tsx | settings/panes/backup_pane.dart:214-294; settings/panes/backup_tree.dart; root/ghost_root.dart:799 | match | Not walked to its end on any device (README). |
| **Export**: Export everything, its progress and Stop | settings/ExportCard.tsx:66-79 | settings/panes/export_pane.dart:15,142; root/ghost_root.dart:800 | match | |
| **Appearance** › Page: System, Light, Dark, Dawn, Boreal, Ember | settings/ThemeCards.tsx:68; settings/words.ts:45 | settings/theme_cards.dart; settings/words.dart:47 | match | |
| Appearance › Home page: Spotlight, Cards, Timeline, List, each a picture of itself | settings/LayoutCards.tsx:82 | settings/layout_cards.dart:76-88 | match | |
| Appearance › Top bar: Classic, Ledger, Masthead, Islands | settings/TopBarCards.tsx:102 | settings/top_bar_cards.dart | match | |
| Appearance › Accent: Ink, Graphite, Red, Amber, Green, Teal, Purple | settings/AccentSwatch.tsx:18; settings/words.ts:35 | settings/accent_swatch.dart; settings/words.dart:34-42 | match | |
| Appearance › Type: Note font (Maple Mono, Fira Code, Inter, Noto, Plex), Interface font (Inter, Noto, Plex), Text size (Large, Larger, Largest), Scale (85%, 93%, Default, 110%, 125%) | settings/AppearancePane.tsx:78-116; settings/TypefaceCards.tsx; settings/ScaleCards.tsx:23 | settings/appearance_pane.dart:29-32; settings/typeface_cards.dart; settings/scale_cards.dart:31 | match | |
| Appearance › Spacing: Tightest, Tight, Comfortable, Roomy, Roomiest | settings/AppearancePane.tsx:122-125 | settings/appearance_pane.dart:33; settings/words.dart:17-23 | match | |
| Appearance › Corners: Square, Soft, Round, Roundest | settings/AppearancePane.tsx:128-135 | settings/appearance_pane.dart:34,198 | match | |
| Appearance › Code: on the light page (Pastel, Ink, GitHub, Solarized), on the dark page (Pastel, Ink, One Dark, Dracula, Nord) | settings/AppearancePane.tsx:145-165 | settings/appearance_pane.dart:210-217 | match | |
| Appearance › Sidebar: Popover, Docked (a wide window only) | settings/AppearancePane.tsx:176-183 | settings/appearance_pane.dart:36; settings/words.dart:56 | match | |
| Appearance › Motion: Animation speed (Relaxed, Normal, Brisk) | settings/AppearancePane.tsx:196-203 | settings/appearance_pane.dart:38; app/ghost_app.dart | match | |
| Appearance › Motion: Ghostly typing | settings/AppearancePane.tsx:213 | settings/appearance_pane.dart:39 | differs | Followed by what the AI and the recorder write; not by a hand's deletions in a note (see the marks). |
| Appearance › Motion: Smoke at the edges | settings/AppearancePane.tsx:218 | settings/appearance_pane.dart:40; root/ghost_root.dart:1430 | match | |
| Appearance › Motion: Ripples while recording | settings/AppearancePane.tsx:223; capture/LivePage.tsx:58,131 | settings/appearance_pane.dart:41; capture/ui/capture_screen.dart:255,1609 | differs | The switch does nothing: the recorder always hands its page the ripples, and nothing but the switch reads `prefs.ripples`. |
| Appearance › Touch: Haptics | settings/AppearancePane.tsx:229-230 | settings/appearance_pane.dart:42,264; core/preferences.dart:1030 | match | |
| **Recording** › While recording: Stop when I go quiet, Review after recording | settings/RecordingPane.tsx:72-83 | settings/panes/recording_pane.dart:16-17,119 | match | |
| Recording › After recording: Better words | settings/RecordingPane.tsx:88-92 | settings/panes/recording_pane.dart:18,138-143 | match | |
| Recording › Summaries: Meetings, Meetings and long voice notes, Off | settings/RecordingPane.tsx:58-61,95 | settings/panes/recording_pane.dart:154 | match | |
| Recording › Meetings: Include sound from other apps, Tell me when a meeting is written up (Allow / On), Write up straight away | settings/RecordingPane.tsx:155-161,203 | settings/panes/recording_pane.dart:22-23,170-196 | match | |
| Recording › Tapes: Remove audio older than a month (Remove, Tap again), and how much the tapes take | settings/RecordingPane.tsx:273-288 | settings/panes/recording_pane.dart:28,201-222; settings/tapes_here.dart | differs | No "Your tapes are being counted." while the files are asked. |
| Recording › The side key (where the rings rise) | removed 2026-10-02 (settings/RecordingPane.findable.ts:11) | — | n/a | Gone from the original. |
| **AI** › Model: each model with Get, its progress, choose, In use, Remove then Tap again, the stand-in, how much they take | settings/ModelCard.tsx:73-108 | settings/panes/ai_pane.dart:17-180; root/ghost_root.dart:857-872 | match | See AI. |
| AI: Fill blanks on their own | settings/ModelCard.tsx:109 | settings/panes/ai_pane.dart:17 | match | |
| **Plugins**: a card and a switch each, "What it may reach" with Why, "Off while Local only is on" | plugins/PluginsPane.tsx:50-79 | settings/panes/plugins_pane.dart:59-190 | match | |
| **About**: the version, large, and the line under it | settings/AboutPane.tsx:57-59; settings/updateLines.ts | settings/panes/about_pane.dart:57-62,145 | differs | With no updater the version stands alone: no build line. |
| About › Updates: where it stands, Reload, Install {version}, Check for updates | settings/AboutUpdates.tsx:42-51 | settings/panes/about_pane.dart:169-189; root/ghost_root.dart:1968 | differs | Not drawn in any build: `widget.updates` is null. Reload can never apply. |
| About › Alerts: Update alerts | settings/AboutUpdates.tsx:52-66; settings/useUpdateAlerts.ts | settings/panes/about_pane.dart:190-204 (`alerts` never given) | missing | With the worker behind it. |
| About › Help: Ghost.md Academy, The welcome walkthrough, Cheat sheet, Specification, Ghost.md: The Guide, Examples | settings/AboutPane.tsx:61-88 | settings/panes/about_pane.dart:149-158 | match | |
| About › What's new: every release, "you're on this one" | settings/AboutUpdates.tsx:75-114; core/changelog.ts | settings/panes/about_pane.dart:210-239 (`releases` never given) | missing | Not drawn without an updater; with one it would say "No updates to show yet." |
| Seven taps on the version turn on developer settings, counting down from the third | settings/AboutPane.tsx:41-54; settings/developerMode.ts | settings/panes/about_pane.dart:68-134 | match | |
| **Examples**: Add the sample note, the example board, the example canvas, the "How Ghost.md works" canvas | settings/ExamplesPane.tsx:24-27 | settings/panes/examples_pane.dart:10-13; root/ghost_root.dart:1985-1988 | match | The sample note and the example canvas come without their picture. |
| **Developer** › Window: Top inset, Page, Screen, Engine | settings/DeveloperPane.tsx:110-114; diag/windowFacts.ts | settings/panes/developer_pane.dart:30-88 | match | Engine reads "Flutter on android". |
| Developer › Smoke bench | settings/DeveloperPane.tsx:45-52; diag/WispBench.tsx | settings/panes/developer_pane.dart:92-101; diag/wisp_bench.dart; root/ghost_root.dart:821 | match | |
| Developer › The phone at work: Readings (Heat, No heat, None), Play the scene | settings/DeveloperPane.tsx:54-78; diag/SceneBench.tsx | settings/panes/developer_pane.dart:105-127; diag/scene_bench.dart; root/ghost_root.dart:822 | differs | Not held off while a real run is on ("The model is on a note. Try again when it is done."). |
| Developer › Developer settings (the switch that hides the page) | settings/DeveloperPane.tsx:80-86 | settings/panes/developer_pane.dart:131-141 | match | |
| Developer › Reset local data, Reset everything (two taps, five seconds armed) | settings/DeveloperPane.tsx:88-95,124-158; core/reset.ts | settings/panes/developer_pane.dart:145-192; core/reset.dart; root/reset_wiring.dart | match | |
| **Test results**: the report this release's tests wrote, its verdict, where it came from, Search tests, Only failures | settings/TestResultsPane.tsx:103-181; diag/testReport.ts | settings/panes/test_results_pane.dart:239-393 | differs | The page is ported and no report is built in: `testReport` is never given (root/ghost_root.dart:838,848), so it says "No test report in this build." |

Not in the port, of the 286 labels: "You're on the web version" (a browser's), "On this phone" and "Phone
notifications" (above), "Notion works in the app." and "Slack works in the app." (a browser's).

## 34. Plugins

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Five ship: Marks, Notion, GitHub, Slack, Claude; all on to begin with | plugins/registry.ts; plugins/*/index.tsx | plugins/built_in.dart; root/plugin_ground.dart:67-78; main.dart:73 | match | The guidebook counts four; the code has Slack. |
| A plugin off offers nothing anywhere; what it kept stays | plugins/registry.ts | plugins/registry.dart | match | |
| Local only holds off the ones that use the internet | plugins/reach.ts | plugins/reach.dart; root/ghost_root.dart:1476 | match | |
| A plugin's requests are held to the hosts its manifest names | plugins/host.ts | plugins/host.dart; root/plugin_ground.dart:36-64 | match | A build that is not a release refuses ghostmarkdown.com, which Notion's sign-in goes through. |
| Marks: the seven marks and five effects as formattings, their spoken cues | plugins/marks/index.tsx | plugins/marks.dart; root/note_desk.dart:167 | match | |
| Notion page: Sign in with Notion (through the service), Account, Boards | plugins/notion/NotionPane.tsx:73-105; plugins/notion/client.ts | plugins/notion/notion_pane.dart:151; plugins/notion/client.dart:193 | match | |
| Notion in a note: Notion board (pick, "Don't send this note to Notion"), Send list to Notion, the swipe, the quiet word, the pill and its drawer | plugins/notion/index.tsx:64-99; plugins/notion/BoardPicker.tsx:46-70; plugins/notion/details.ts | plugins/notion/notion.dart:34-99; plugins/notion/board_picker.dart:94-119; plugins/notion/details.dart | match | The band's own Notion row is unwired (section 14). |
| GitHub page: Repos (with Forget), Token ("A token is kept", GitHub token) | plugins/github/GitHubPane.tsx:21-79 | plugins/github/github_pane.dart:85-124 | match | |
| GitHub in a note: GitHub repo (Read and link, Private repo?, "Don't link a project"), Send list to GitHub, the briefing for the model | plugins/github/index.tsx:76-114; plugins/github/ProjectPicker.tsx:66-113; plugins/github/repos.ts | plugins/github/github.dart:84-109; plugins/github/project_picker.dart:31-170; plugins/github/repos.dart | match | |
| Slack page: Channels, Add a channel (a name and its webhook), Organizations' news to a channel | plugins/slack/SlackPane.tsx:134-229 | plugins/slack/slack_pane.dart:99-278 | match | Each webhook is in the phone's secure store. |
| Slack in a note: Post to Slack, Post the summary to Slack | plugins/slack/index.tsx:70-84 | plugins/slack/slack.dart:58-106 | match | |
| Claude page: How to connect, Server address with Copy, On your own computer, What Claude can do, Your key | plugins/claude/ClaudePane.tsx:24-56; plugins/claude/ClaudeGuide.tsx:76-83 | plugins/claude/claude_pane.dart:54-108; plugins/claude/claude_guide.dart:144-258 | match | |
| What a note is linked to, at its top | plugins/LinkMarks.tsx | plugins/link_marks.dart; root/note_desk.dart:1317 | match | |

## 35. The Academy, the Guide, the cheat sheet, the specification

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Ghost.md Academy: seven chapters, 61 lessons | academy/lessons.ts | academy/lessons.g.dart; academy/lessons.dart | match | Same ids, chapters and counts. |
| Chapters page: how much is learned, Start / Continue, "I know Markdown already", Start again, Cheat sheet | academy/AcademyScreen.tsx:48-320 | academy/academy_screen.dart:74; root/ghost_root.dart:1787-1796 | match | |
| A lesson: You type / Your note shows, ticked as the mark appears, Show me, Show me a hint, Skip, Next | academy/Playground.tsx:56-74; academy/AcademyScreen.tsx | academy/playground.dart:336-346; academy/academy_screen.dart | match | |
| The lessons for a formula, a diagram and coloured code draw what they teach | academy/lessons.ts; editor/mathsDrawn.ts; editor/mermaid.ts | academy/lessons.g.dart:297; academy/playground.dart | match | Each is drawn: the diagram by editor/diagrams, the formula by editor/maths, the code's colours by editor/code. |
| The Academy's card on the home page | App.tsx:716 (kept, never drawn) | academy/banner.dart (not imported) | n/a | Gone from the original's page. |
| Ghost.md: The Guide, 44 chapters and its index, added once and opened | guidebook/guidebook.ts:84 | guide/guidebook.dart; assets/guidebook/; root/ghost_root.dart:908-919 | match | The 44 chapters and the index are byte for byte the original's. |
| The Guide waits five seconds for a sync first, so a copy added elsewhere is found | App.tsx:1709-1712 | root/ghost_root.dart:908-913 | differs | No sync before the look. |
| Cheat sheet: every mark in its groups, Find a mark, each drawn by the note's own editor | guide/CheatSheet.tsx:22-116; guide/marks.ts | settings/panes/cheat_sheet.dart:57-545; settings/panes/marks.g.dart | match | |
| Specification: the base, every extension and fill defined | settings/SpecPane.tsx:13; settings/specification.ts | settings/panes/spec_pane.dart:33; settings/panes/specification.g.dart | match | |

## 36. Updates

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| A new page downloaded over the air, applied on the next launch or by Reload; a build that fails to start set aside | core/ota.ts; src-tauri/src/ota.rs | — | n/a | A Flutter app has no page to swap. Every change is a new APK. |
| A new app found, downloaded, checked against its signed description, handed to Android's installer | core/ota.ts:285; src-tauri/gen/android/…/MainActivity.kt:985 | core/updates.dart; native/src/kept/updates.rs; android/…/ghost_md/UpdateInstaller.kt | differs | Built and walked on an emulator, and on in no build: no key (core/update_keys.dart:14), no release address. |
| Looked for four seconds after launch, on a return after a minute, every two minutes in front | core/ota.ts | core/updates.dart | differs | As above. |
| Update alerts with the app closed (a check about every six hours) | src-tauri/gen/android/…/updates/UpdateCheckWorker.kt, UpdateAlerts.kt; src-tauri/src/update_alerts.rs | — | missing | README says what it would take. |
| What's new, once, in a sheet after an update | notes/WhatsNewSheet.tsx:32; App.tsx:1654 | — | missing | |
| The list of releases in About | core/changelog.ts | — | missing | |

## 37. The Mac and the iPhone

Neither was audited row by row: the target was Android. What turned up on the way, gathered here and counted where
its row is, not again:

- **The Mac.** A note's menu on a right-click of a sidebar row is unwired (`onNoteMenu` is never given). The
  aside's History tab is unwired (nothing gives `history`). Dropping a note or a picture file onto a canvas is
  missing. A picture pasted with ⌘V is unwired (`pasteImages`), which is felt most here. "Send the link" on an
  invite link and on a share is never given: missing here if the Mac's WebView offers `navigator.share`, which the
  original draws it by.
  The review's "No language model on this phone to think it through" says "this Mac" in the port alone. ⌘N and ⌘R
  are there, and the port adds ⌘F for a note's find bar and ⌘, for Settings. Browse files is not offered on a Mac
  in either. Films are Android's only in both (main.dart:126-131).
- **The iPhone.** It records nothing and runs no model in either app (`recordsVoice`, core/iphone_app.dart;
  main.dart:105-113): no Speak, no recorder, no meetings, no tapes made there. The More sheet's AI rows are drawn
  and a press says "The AI is not on iOS yet."; blanks are drawn with no Fill (root/iphone_wiring.dart:49-71).
  "Send the link" is missing as on the Mac.

## 38. Links into the app, and what Android is told

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| `ghostmd://note/<id>` opens the note | share/appLinks.ts:20-63; App.tsx:420-426 | share/app_links.dart:28-36,87; root/ghost_root.dart:968-978 | match | |
| `ghostmd://notifications` opens the bell's card; `ghostmd://org/<id>` an organization's page | share/appLinks.ts; shell/useAppLinks.ts:59-66 | share/app_links.dart:61-70; root/ghost_root.dart:947-954 | match | |
| `ghostmd://join/<code>` asks "Join X?" | core/orgs/joinLinks.ts:93-118 | share/app_links.dart:81,109; orgs/join_links.dart:91-115 | match | |
| `ghostmd://fork#<id>.<key>` saves a copy | App.tsx:409-419 | share/app_links.dart:99; root/ghost_root.dart:956-966 | match | |
| A link is followed once the notes are read, whether it started the app or found it open | shell/useAppLinks.ts:59-66 | core/phone_links.dart:44-75; root/ghost_root.dart:1586-1592,2160-2185 | match | |
| A phone with both apps | — | android/app/src/main/AndroidManifest.xml:96-101 | differs | Both claim `ghostmd://`, so Android asks which opens a link. |
| The app's name on the phone | src-tauri/gen/android/…/AndroidManifest.xml:93 ("Ghost.md") | android/app/src/main/AndroidManifest.xml:60 | differs | "Ghost Flutter": the launcher, the assistant's picker, the Files app's place. |
| How the one window is kept | src-tauri/gen/android/…/AndroidManifest.xml:101 (`singleTask`) | android/app/src/main/AndroidManifest.xml:70-71 (`singleTop`, `taskAffinity=""`) | differs | What it changes for a link or the side key arriving over another task was not tried. |
| What a backup leaves out | src-tauri/gen/android/…/res/xml/glyph_backup_rules.xml:9 (films) | android/app/src/main/res/xml/ghost_backup_rules.xml:13-17 | match | The port leaves the search index out as well. |
| A Chromebook's own way of opening a link | src-tauri/gen/android/…/AndroidManifest.xml:134 | — | n/a | Not a phone's. Missing on a Chromebook. |
| `#fork=` and `#join=` in a browser's address | share/appLinks.ts | — | n/a | The web page's. |
| Sharing into the app from another, a widget, a quick-settings tile | — | — | n/a | Neither has one. |

## 39. A hardware keyboard

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Ctrl/⌘K opens the palette | the kit's CommandPalette | packages/glacier/lib/src/components/command_palette.dart | match | |
| Escape steps back as the back gesture does | core/back.ts:95-98 | core/back.dart:158 | match | |
| Ctrl/⌘F in Settings goes to the search field | settings/SettingsScreen.tsx:305 | settings/settings_screen.dart:380 | match | |
| ⌘N new note, ⌘R sync with its toast | App.tsx:651-667 (the Mac app only) | shell/desktop/desktop_commands.dart:96-112; root/ghost_root.dart:1492-1511 | n/a | Not on a phone in either. The port gives them to every desktop, and adds ⌘F for a note's find bar and ⌘, for Settings. |
| The editor's keys, `/` on an empty line, the + list's arrows | editor/Editor.tsx:324; editor/insertPlus.ts:519 | editor/commands/commands.dart:1590-1645; editor/plus/insert_plus.dart:517-555 | match | See section 14. |
| A canvas's keys | canvas/CanvasView.tsx:379-452 | canvas/canvas_view.dart:688-728 | match | The canvas must have the focus; the original listens on the window. |
| The arrow keys in the home filters' radios, a board's height line | home/HomeFilters.tsx:273-281; editor/boards/divider.ts:45-52 | home/home_filters.dart; editor/boards/divider.dart:14-16 | differs | The height line has no keys. |

## 40. Accessibility and languages

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Every control named for a screen reader | `aria-label` throughout | `Semantics` / `semanticLabel` throughout (about 650 in lib/) | match | Sampled with the labels: the names are the original's. |
| The note's own words read by a screen reader | the WebView's contenteditable | — (editor/editor_widget.dart:27,482) | missing | The editor draws its text with no semantics. |
| Reduce motion on the phone stills the smoke, the effects, the scene | core/motion.ts:21; editor/textEffects.ts:161 | packages/glacier tokens `reducedMotion`; editor/marks/text_effects.dart:414-431 | match | |
| The phone's text size | the page's own px and rem (WebView text zoom) | app/ghost_app.dart | n/a | Not compared: neither follows the phone's font scale by rule. |
| The app's words are English | — | — | match | |
| The palette's own words in eight languages | the kit's LocaleProvider | packages/glacier/lib/src/components/command_palette.dart:27-40 | match | |
| Dates in the phone's language and order | core/stamp.ts; core/template.ts:89; book/journalMonths.ts:66; editor/fieldChips.ts:79; core/query/calendar.ts:77 (`Intl`) | core/locale_dates.dart; core/template.dart:32-37; book/journal_months.dart:15-18; editor/items/field_chips.dart:89-104; core/query/calendar.dart:87-92 | differs | The phone's order (day first or month first) is followed; the names of months and days are always English. |

## 41. A wide window and the Fold

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| Two panes from 660 by 600 | core/useWideScreen.ts:39-42 | shell/wide_screen.dart:6-22 | match | |
| Settings as a split view | settings/SettingsScreen.tsx | settings/settings_sheet.dart:180 | match | |
| The sidebar as a card, or docked as a column; on a folding phone the docked one starts hidden | core/useWideScreen.ts:96-107; App.tsx:988-989 | shell/wide_screen.dart; root/ghost_root.dart:1904-1910 | match | |
| The aside as a card at the right, or a column beside a docked sidebar | aside/Aside.tsx:166; App.tsx:1598-1628 | aside/aside_panel.dart:27; root/ghost_root.dart:1913-1918 | match | |
| The aside's History tab, and the bar's History button opening it | aside/AsideHistory.tsx; App.tsx:995-1005 | aside/aside_panel.dart:102-105 | n/a | Not on a phone (`!isMobile`), a Fold included. Unwired on the Mac. |
| Home's cards two, three or four across | home/HomeLayouts.module.css | home/home_screen.dart | match | |
| The note unfolds with the hinge, from about thirty degrees, never folding back | core/unfold.ts:122; MainActivity.kt (hinge) | core/unfold.dart:50; android/…/ghost_md/Hinge.kt; note/note_screen.dart:1433-1449 | match | Never seen move: an emulator has no hinge. |
| Folding or unfolding with a note open | core/useWideScreen.ts (the note is made again) | shell/app_shell.dart | differs | The port keeps the note's screen, its scroll and its caret. Kinder than the page. |
| A mouse on a phone: hover grounds | app.css (`@media (hover: hover)`) | packages/glacier pressable; shell/wide_screen.dart:38-48 | differs | Decided by the platform, not the pointer. |

## 42. Touch, smoke and motion

| Feature | Original (file:line) | Port (file:line or —) | Status | Note |
| --- | --- | --- | --- | --- |
| A tick on a tap, on the finger's lift | core/haptics.ts:121-136 (`installTapHaptics`) | packages/glacier/lib/src/haptics/ | match | |
| Haptics for a swipe's detents, a card landing on a dot, a style applied, a box ticked, a counter | core/detentFeel.ts; canvas/Selection.tsx:50; editor/StyleItems.tsx; editor/taskToggle.ts | core/detent_feel.dart; canvas/canvas_view.dart:277; editor/band/style_items.dart; editor/items/task_toggle.dart | match | |
| A warning tick as a note goes to the Trash, a success tick on pin, archive, restore | notes/useNoteActions.ts:161-257 | notes/note_actions.dart:177-277 (`haptic` never passed, root/ghost_root.dart:1373) | unwired | |
| No sounds | — | — | n/a | Neither app plays a sound of its own. |
| Smoke where a page passes under the header and at its foot | art/wispEdge.ts; art/WispEdgeFilter.tsx; art/wispFoot.ts | art/wisp_edge.dart; art/wisp_strips.dart; art/wisp_foot.dart | match | On the same screens: home, All notes, a note, Settings, the guide, the recorder's page, an organization's. |
| The dock's halo torn into smoke | art/dockSmoke.ts | art/dock_smoke.dart; root/ghost_root.dart:1838 | match | |
| The dotwork ghost in its scenes (no notes, empty workspace, nothing found, listening, working, …) | art/Ghost.tsx; art/ghosts.ts | art/ghost.dart:9-21; assets/art/ghosts/ | match | |
| The launch screen's eyes | launch/eyes.ts | launch/eyes.dart | match | |
| Letters arriving out of smoke and leaving into it | editor/wispArrivals.ts; editor/wispMotion.ts; art/WispText.tsx | editor/ai/wisp_arrivals.dart; editor/marks/wisp_motion.dart; art/wisp_text.dart | match | See the Ghostly typing row for the switch. |
| Ripples through the newest words as you talk | editor/wispRipples.ts | editor/ai/wisp_ripples.dart; capture/ui/live_page.dart | match | Always on: see the switch in Settings. |
| The cassette's reels, the working gears, the icon wash | tapes/TapeArt.tsx; art/WorkingGears.tsx; art/iconWash.ts | tapes/tape_art.dart; art/working_gears.dart; art/icon_wash.dart | match | |
| Cards arriving one after another; a tab's outline sliding | home/HomeScreen.tsx:149; notes/useTabOutline.ts | home/home_screen.dart:329; notes/tabs/tab_row.dart | match | |
| Animation speed (Relaxed, Normal, Brisk) paces all of it | core/preferences.ts (`motionScale`) | app/ghost_app.dart; core/preferences.dart | match | |

## What could not be told from the source

Each of these is a row above, marked by what the code says. A phone would settle them:

- Whether a finger landing on a link, a box or a choice acts before a scroll can begin (the editor's taps).
- Whether leaving the app in the middle of a take loses the rest of it (the microphone is closed at `onStop`).
- Anything of a build with `GHOST_ASSISTANT=1`: the side key, the lock screen, a cold start by the key. None was
  ever made.
- Whether a note's desk is ever made before the engine is up, leaving that note with no AI until it is reopened.
- The other-apps' sound consent in a meeting, and the write-up worker with the app closed.
- Everything drawn or timed: heat, frost, the smoke, the reader robot, the hot phone, the strip's breathing.
- Composing and autocorrect with Samsung Keyboard.
- Whether any of the six lookup addresses answers with a redirect, which the port reads as nothing found.

---

# The three lists

Each gap once, however many tables it is a row of, in the order a daily user of the Android app would feel it.
Size is the work in the port: **small** is a seam handed over or a few lines, **medium** a screen or a bridge,
**large** a renderer, a service or a subsystem.

## Missing

1. **Code coloured by its language**, and HTML's tags with it. Done (`lib/editor/code`): the web's own grammars'
   tables run by a port of Lezer's parser, and the language pack's older line modes, a dozen ported and the rest
   run from their own JavaScript. What is left of it is Differs 40.
2. **Maths drawn as a formula**, in a line and as a `$$` block. Done (`lib/editor/maths`), by the copy of
   `flutter_math_fork` in packages/. What is left of it is Differs 41.
3. ~~**A `mermaid` block drawn as its diagram**: in a note, on a canvas's chart card, in the Academy's lesson.~~
   Drawn since 2026-10-10 (`lib/editor/diagrams`, and what it left open in the README). The number is kept so the
   others keep theirs.
4. **The bell's rows as the phone's own notifications**, with the app closed, and Settings › Notifications › On
   this phone (Phone notifications, Allow notifications). Large. The original's `notices/NoticeAlerts.kt` and
   `NoticeWorker.kt`, a channel, the session handed to a worker; only in a build with `GHOST_API`.
5. **More › Journal** and its page: keep a notebook as a journal, what an entry starts with, the place switch, make
   it a notebook again. Medium. `withJournal` / `withoutJournal` (lib/book/journal.dart:139,142) and the template
   picker exist; the page in lib/note/note_settings.dart does not.
6. **More › Ticket key.** Small. `keyProblem` (lib/book/tickets.dart:43) exists. Until it is there a notebook made
   in the port gets a key only by typing `key:`, and New ticket stays out of reach.
7. **More › AI › Fill the blanks**, with its count and who is asked, and the dot on the run that is on. Small.
   `fillPlanOf` (lib/editor/ai/blanks.dart:276) and `NoteAi.runningKind` (lib/ai/note_ai.dart:198) exist.
8. **Pull down in a note to refresh.** Small. With the pull to refresh that syncs (Differs 4).
9. **An address pasted over a selection makes a link.** Small. The editor's paste.
10. **The Undo of a voice command, offered again after the app was stopped.** Small to medium. The core already
    answers `latest_command_mutation` (native/src/dispatch.rs:379); nothing in Dart asks at launch.
11. **Spell-check underlines.** Medium to large. The port's own text client has no bridge to Android's checker.
12. **A screen reader reads the note's words.** Large. The editor draws its text with no semantics.
13. **Update alerts with the app closed; What's new**, in About and once after an update. Medium. Blocked on there
    being an updater at all (Differs 3); then a worker and the list of releases.
14. **A model mirror moved by a signed update.** Small. With the updater.
15. **A board's and a query board's height line by the arrow keys, Home and End.** Small. A keyboard's only.

## Unwired

1. **A renamed page keeps its place in its notebooks and journals**: `followRename` (lib/book/follow_rename.dart:26)
   has no caller, so a renamed page drops out of its notebook's index. Small. Call it where a note's title changes.
2. **A shared link follows your edits**: `Shares.follow` (lib/share/share.dart:518) has no caller. Small. One call
   from the root with the library's saved listenable. Settings says "Your edits follow it." all the while, and a
   picture that was lacking is never sent later. Needs `GHOST_API`.
3. **The dot on the bell**: `AppShell.unread` is never given; `unreadNotifications`
   (lib/orgs/ui/fed_notifications.dart:70) has no caller. Small.
4. **Who kept a version**: `VersionsRecord` is made without `keeper` (lib/root/ghost_root.dart:282). Small. Every
   version is "me", so version history and an organization's audit log say "You" for everyone.
5. **The palette's This note commands**: Show it formatted / Show the marks, Fix spelling, Make a list, Continue,
   Fill the blanks. Small. Give `paletteDoingFor` its `setView`, `noteAi` and `blanks`
   (lib/root/ghost_root.dart:1990-2023).
6. **The +'s "A blank for the AI" and "Blanks in the empty cells"**: `AddConfig.blanks` is never set
   (lib/root/note_desk.dart:944-959). Small.
7. **What the tape says of its summary**: Summarizing, "Needs a model.", "The summary didn't come.", "The summary
   comes after the better words.", "Summary is from before the last take." Small. Give `NoteTape` its `queue`
   (lib/root/note_desk.dart:1298-1316) and `behind` from `summaryBehind` (lib/ai/summary_keep.dart:83). Until then
   Summarize stays pressable in the middle of a run.
8. **The open note takes a write-up the moment it lands**: `onRecordingChanged` (lib/ai/summaries.dart:637) has no
   caller. Small. Today it is taken only as a note opens.
9. **A trashed meeting's write-up is cancelled, a restored one asked for again, a note deleted for good
   forgotten** (its line, runs, marks, kept summary, job). Small to medium. Give `NoteActions` its `onTrashed`,
   `onRestored` and the forgetting (lib/root/ghost_root.dart:1373-1380); `cancelWriteUp`
   (lib/capture/meeting_host.dart:192) is there.
10. **"A meeting was written up" in the bell**: `Voice.make` is not given `record`
    (lib/root/ghost_root.dart:445-453). Small.
11. **Looking again when you come back to the app**: the voice model's failed download and the better-words queue.
    Small. Give `VoiceModel` and `Refining` the `onVisible` the summaries already have
    (lib/root/voice_wiring.dart:375).
12. **A blank "Waiting for a connection" goes on when one is back**: `startFills` is given no `onLine` or
    `onOnline` (lib/root/ghost_root.dart:635-656). Small to medium. Needs something that knows the connection.
13. **An organization's workspace opens the organization**: the sidebar's "…", All notes' pill and its sheet's row.
    Small. Give `NoteTree`, `NotesDrawer`, `AllNotesScreen` and `WorkspaceManageSheet` their `onOrganization`.
14. **Report a member or a note**: `OrganizationSheet` is never given `onOpenLink`
    (lib/root/ghost_root.dart:2096-2108), so the row cannot be pressed. Small. The root has the way at line 1972.
15. **Jump to cursor on a canvas**: `_jumpTo` (lib/root/ghost_root.dart:338-344) hands on the caret and never the
    pointer. Small.
16. **The band's send row for a plugin** (Notion, GitHub) on a list item: `BandSend` is built nowhere. Small. The
    swipe and the quiet word still send.
17. **A card's AI corner**: the dot for marked changes and the spinner while its line is written. Small. Give
    `NoteCard` `marked` from `hasMarks` (lib/ai/marks.dart:51) and `working` from `activeGist`
    (lib/format/gist.dart:168).
18. **An answer's panel closes when the note scrolls**: `NoteAi.closePanels` (lib/ai/note_ai.dart:377) has no
    caller. Small. The same call would close a mark's note and a footnote, which nothing closes either.
19. **A reading note's lead line**: `leadLine()` (lib/editor/items/open_heading.dart:183) has no caller. Small.
20. **Share the versions file**: `NoteSeams.shareVersionsFile` is never given. Small to medium. On Android the
    original copies the file's text and says so.
21. **A picture pasted with Ctrl-V**: `pasteImages` (lib/editor/media/images.dart:344) has no caller. Small to
    medium. Needs the clipboard's picture from the phone.
22. **The ticks under the finger**: a warning as a note goes to the Trash, a success on pin, archive and restore.
    Small. `NoteActions.haptic` (lib/root/ghost_root.dart:1373).
23. **The AI card's Battery**: `useBatterySource` (lib/format/battery.dart:56) has no caller. Small. Needs the
    phone's battery read.
24. **The ghost on the bell's empty card**: `emptyArt` is never given to the notifications drawer
    (lib/root/ghost_root.dart:1919-1945). Small.
25. **A note's menu on a right-click of a sidebar row**: `onNoteMenu` is not given to the tree. Small. A mouse's,
    so the Mac's; with it the aside's History tab (`history`), the Mac's too.

## Differs

1. **The side key, the digital assistant and "Record note" on the icon are absent** unless the app is built with
   `GHOST_ASSISTANT=1`; the original's `main` has them always. Small to turn on (android/app/build.gradle.kts),
   large to stand behind: no such build was ever made or walked. With it come three smaller ones: the lock is read
   once as a take starts, the way into an account is drawn over a recorder and not held back for a launch by the
   key, and the window is `singleTop` where the original's is `singleTask`.
2. **Account, sync, organizations, team notes and shared links exist only in a build given `GHOST_API`.** Small. A
   release's configuration; nothing to write.
3. **Updates are on in no build**: `trustedUpdateKeys` is empty (lib/core/update_keys.dart:14). Medium. A signing
   key and a release address; then home's card, the launch line, About's build line and Updates rows are drawn.
4. **Pull to refresh reads the library again and does not sync**, on home and All notes. Small.
   `SyncEngine.syncWithin` (lib/sync/engine.dart:450) has no caller; `onRefresh` at lib/root/ghost_root.dart:1771
   and 1829. The Guide's look for a copy added elsewhere goes without its sync for the same reason.
5. **A finger landing on a link, a box or a choice acts at once**, where the original acts on a finished tap.
   Medium. The editor's gestures; try it on the Fold first.
6. **Leaving the app in the middle of a take closes the microphone**
   (android/app/src/main/kotlin/com/mattssoftware/ghost_md/MainActivity.kt:172-177), and nothing hears that it closed. Medium. Try
   it first.
7. **A note opened before the engine is up has no AI until it is reopened**, and no note has it in a run where
   voice did not attach within three seconds (lib/root/note_desk.dart:478-490; lib/main.dart:107-113). Small to
   medium. The desk's AI is `late final`.
8. **While a tape plays the transcript does not take the page**: the port lists the phrases under the note all the
   time. Medium. The note's screen.
9. **The names of months and days are always English**: due chips, the names under line 1, a journal's months,
   templates, the calendar, the +'s date row, a meeting's title, the audit log, version history, "Synced" after an
   hour, a blank's "Asked on" and its worked-out dates. Medium. One place (lib/core/locale_dates.dart), and it
   needs the names for each language.
10. **Two Motion switches do less than they say.** Ghostly typing is not followed by a hand's deletions in a note
    (lib/root/note_desk.dart:549), and Ripples while recording does nothing. Small.
11. **A note's mic stays when the note has a tape, and the tape's Add does not save what is typed first.** Small.
12. **A line is written under every note in the library**, not home's first 16 cards and All notes' first 24
    (lib/root/ghost_root.dart:631-633). Small. The phone's cores and battery pay for it.
13. ~~**Formulas, diagrams and a canvas's chart card are written and never drawn, and the words still say
    drawn.**~~ Each is drawn since 2026-10-10 (Missing 2 and 3); what differs is in their rows and in 41 below.
14. ~~**Code themes change only a block's ground and ink.**~~ Done with Missing 1: each kind of token takes the
    theme's colour.
15. **"Summarized"** has no title and no ten seconds (lib/root/ghost_root.dart:525-531). Small.
16. **Asking for notifications**: the meeting screen's Allow is marked asked before the phone has answered, and
    Settings can never say "Notifications are off for Ghost.md in the phone's settings."
    (lib/root/ghost_root.dart:763-770,875-883). Small to medium. Needs the phone's real answer.
17. **The tape and its voice memos share one player**: after a memo, Play goes on from where the memo stopped.
    Small to medium.
18. **A chip's tap opens a menu, not the band's page; a ticket's Status, Due, Estimate and Labels go through a
    sheet.** Medium, or a decision to keep the port's way. `openFields` (lib/editor/band/context_band.dart:209) is
    never called.
19. **No band over a drawn table or any drawn block; a board's fence is not reached by a tap between its cards.**
    Medium.
20. **The bookmark**: with no caret it marks line 1, not the top line in view (`caretPlace`,
    lib/note/note_place.dart:143, is never called); its button is not re-read after an undo; no line down the
    edge for one kept on the device. Small.
21. **A notebook read straight through**: the way back and the rail scroll away with the first page; a
    `[[link]]` in the notebook's own words does not open. Small to medium.
22. **Names for this note** are a strip under the editor, not a block after line 1. Small to medium.
23. **A query's timeline is the port's own drawing**: weeks tick on Monday, names beside the bars. Medium.
24. **An organization's small ends.** The profile's button always says "Open the note" and a canvas is "an
    untitled note"; Edit from home's filters lands on Members under "← Organizations"; leaving or deleting from
    the cog leaves "This organization is not in your list any more." on screen; Back from an opened change in the
    audit log skips the list. Small each.
25. **A share's pictures are drawn smaller only if they are PNGs**: a phone's JPEGs are left out of the link
    (lib/sync/device.dart:56-96). Medium. Needs a JPEG read and written.
26. **Undo in a live note is the editor's own history**: after another member wrote at the same place it can take
    out the wrong letters. Large. An undo that knows whose change it was.
27. **Blanks**: the time in a city is said against "here", not your city (`BlankHooks.zone` is never given); zone
    offsets come from a table good to 2040; a lookup follows no redirect and gives up after ten seconds; one being
    filled does not breathe. Small to medium.
28. **The AI's changes**: words taken out inside a line are one unbroken box; the + is not held back while the AI
    writes. Small.
29. **Heat and Frost are drawn another way.** Medium to large. Shaders; judge them side by side, not by counting.
30. **A note's menu opens on a long press**, which the original leaves to the swipe; the palette's Archive also
    closes the tab and its Pin gives no tick. Small, or a decision.
31. **Typing**: the handles, the loupe and composing are the app's own and were never run with Samsung Keyboard;
    Ctrl-C or Ctrl-X with nothing selected does nothing. Medium.
32. **Settings' small ends.** "Get a model" opens AI with nothing lit; Play the scene is not held off while a real
    run is on; no "Your tapes are being counted."; Test results says "No test report in this build." because none
    is built in. Small each; the report is medium, a build's tooling.
33. **Words that read otherwise**: a picture that did not come in is a toast, not a line under the header; a
    refused microphone says "Ghost.md needs the microphone to record."; a save refused for good and an account key
    that will not open have sentences only the port has. Small, or leave them.
34. **The landing's Undo** does not take off a lone where-written tag when it empties the note. Small.
35. **The starter sample note has no picture and the example canvas no picture card**; the minimap draws a picture
    card plain. Small. The pictures bundled.
36. **The name**: "Ghost Flutter" on the launcher, in the Files app and to the service; both apps claim
    `ghostmd://`, so Android asks which. Small. At the cut-over.
37. **A build that is not a release fetches models only from where `GHOST_MODELS` says.** By design.
38. **Kinder in the port, and worth keeping**: a fold or unfold keeps the note, its scroll and its caret; a newer
    build's settings this one cannot read are carried back to the account, not dropped; a live note's socket is
    let go while the app is behind another.
39. **A mouse**: hover grounds are decided by the platform, not the pointer. Small.
40. **Code is coloured by the port's own readers of the web's grammars and modes**, 142 of the language pack's
    143 (`languageNamed` in lib/editor/code/languages.dart; Angular Template is the one, and no fence can name
    it). Where the two can still part: a mode that throws, or will not move along its line, on something typed
    ends the web's colouring of the whole note, and here that line goes uncoloured and the next is read (and a
    mode is stopped after two million turns of a loop on one token); Pug's mode asks JavaScript itself whether
    an attribute's value has ended, and here the grammar JavaScript is coloured by is asked; Stylus's mode sorts
    its words with a comparison that V8 (Android, Windows) and WebKit (the Mac) take differently, and V8's is
    followed. A long block being read is coloured down to where the reading has got, as on the web, and never
    one frame in the original's own in-between states.
41. **A formula is drawn by `flutter_math_fork`, not KaTeX 0.16.** The copy in packages/flutter_math_fork is
    held to KaTeX's heights and depths (test/editor/maths/katex_test.dart: all 145 agree). What is left: seven
    families of KaTeX's commands it does not read (the test's list; such a formula is shown as its source), and
    widths and glyphs, which no test here can compare. And one difference kept on purpose: **an equation's
    number is its place in the note.** KaTeX numbers the rows of `align`, `gather`, `equation` and `alignat`
    with a counter of the page's stylesheet, which counts the numbered rows that are in the page; the web
    editor keeps only the lines near the screen in the page, so by those two a number there depends on what is
    drawn above it (read from the stylesheet and the editor's way of drawing, not watched in the web app). Here they are counted through the
    note from its top, drawn or not (test/editor/maths/numbers_test.dart), so a number never depends on what
    happens to be drawn. A formula that cannot be read
    says why in a panel on a long press, where a browser shows a tooltip; the dots under it sit where Flutter
    puts an underline; a screen reader is told the formula's TeX, where the web gives it MathML. Small each.
