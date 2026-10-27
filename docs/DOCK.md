# The dock, the same on every page

Matt, 2026-10-17: "I want the right side dock standardized across all pages but include icons relevant to what you can
do on that page like settings and ask claude."

Until then only the home page had a dock (Claude, Search, +, Speak). Now every page has the same one, made once in
lib/shell/page_dock.dart: the home page's look, place, size, smoke and motion, with what that page can do in it. The
Flutter app only; the web app and the Tauri app have the home page's dock alone (docs/PARITY.md, "Home").

## What is the same everywhere

- **Where it stands.** The bottom end corner of the page it is on, in from the edge by the safe area and
  `--glacier-space-4`, over the bottom safe area by the same step. On a wide window (a tablet, the Fold open, a
  desktop) it is the content pane's corner, never over the docked sidebar or the aside, which stand beside the pane.
  While the chat with Claude is a panel down the right of a wide window (lib/claude/claude_chat.dart, 420 wide from
  720), the dock moves out to the panel's start, so it stays on the page and in reach (`windowEndCover`).
- **How it looks.** A column of rings in a pill of glass (blurred 14, the page's ground at 82%, a hairline), each ring
  `--app-ring` across, `--glacier-space-2` between them. The halo of smoke round it (lib/art/dock_smoke.dart
  `DockSmoke`) wherever the app draws one, as on the home page.
- **The order.** Claude at the head, always: the orange ring (lib/claude/claude_dock.dart), turning while Claude works,
  with its dot while an AI is online. Under it, where the build can hear, Talk to Claude: the plain ring with its rim and mic
  in Claude's orange (docs/CLAUDE_APP.md, "Talking to Claude"), on every page whose dock has Claude. One microphone only
  (GHST-104; Matt, 2026-10-18: "When Claude mode is enabled there should only be one microphone icon still it should
  just use Claude instead of the local models"): where Talk to Claude is on a dock, the ink-filled Speak is not, on home,
  on a page of notes and on a note; what is said goes to Claude, not to the recorder and the phone's own models. With
  the Claude plugin off, or where the build cannot hear, Speak is the dock's microphone as it always was, and the
  recorder is still reached by the sidebar's Speak pill, the palette's "Speak a new note" and the More sheet's row. What the page is for in the middle. A settings-type ring at the foot, always,
  where the page has one: Settings on a page of notes, the ⋯ on a note, the cog on an organization's page.
- **How it moves.** Search's magnifier leans in when pressed, a + gives a quarter turn, Speak's ink pill dips, the rest
  are still. Under reduced motion nothing turns and the dock comes and goes at once.
- **While the page scrolls.** Matt, 2026-10-17: "when we scroll make the dock bar animate to be 33% smaller", then
  "the navbar should only get 20% smaller 33% is too small, also it should stay small until scrolling back to the top
  of the page". Once the person scrolls the page down (a thumb, a trackpad, a wheel) the whole dock, its rings, their
  gaps, the pill and the halo round it, grows smaller to four fifths of itself (`dockScrolledScale`), held to its
  bottom end corner, in `--glacier-duration-fast`. It stays so however long the page is still, and grows back in
  `--glacier-duration-normal` when the page is at its top again (within `dockTopSlack`), whoever took it there: the
  thumb, or the app gliding it back for another filter. Both `--glacier-ease-out`, at once under reduced motion. Only
  the page's own scroll: a carousel across the page, a code block's or a table's own scroller and a search's field
  leave it as it is, and so does the page moved by the app away from its top (a jump to where it was left). It is a
  transform, so a ring is pressed where it is drawn, small or not, and Claude's turning and the rings' own motions go
  on inside it; the room each page keeps at its foot is the room for the dock at rest, and the keyboard's step aside
  and ride are as they were (`DockShrink`).
- **The keyboard.** On a note (any kind: words, a canvas, a notebook, a journal) the dock steps aside while the
  keyboard is up, so it never stands over the caret: it fades out, takes no presses and is not read, and the halo goes
  with it; it comes back as the keyboard goes. On the other pages it rides over the keyboard, as the home page's
  always has, so a search being typed still has it.
- **Room at the foot.** Each page keeps room at its end for the dock's column, as the home page does, so the last
  rows and the last lines scroll clear of it. A canvas's map stands to the dock's start rather than under it
  (`PageDockRoom`).
- **Said and shown.** Every ring is a button with its words said to a screen reader; on a desktop (a mouse) the words
  come up beside the ring while the pointer rests on it (`DockTip`). The dock as a whole is named for its page
  ("Note actions", "Canvas actions"; the home page's keeps "New note").

## Each page's rings

| Page | Rings, head to foot | Each one is |
| --- | --- | --- |
| Home | Claude, Talk to Claude, Search, + (Write a note), Speak (only without Talk to Claude), Settings | Ask Claude; the ask said aloud; the command palette; the + sheet; the recorder; the app's Settings |
| All notes | Claude, Talk to Claude, Search, +, Speak (only without Talk to Claude), Settings | the same, from the root (lib/root/root_parts.dart `_notesDock`) |
| Tags, a tag's notes, a smart notebook | Claude, Talk to Claude, Search, +, Speak (only without Talk to Claude), Settings | the same |
| A note's words | Claude, Talk to Claude, Find in note, Speak (only without Talk to Claude), Add, Note options | the chat with `[[Title]] ` in its field; the note's find bar; the note's own mic (Talk into this note, not on a spoken note, which has its tape's Add); the +'s list for the caret's line, placed at the caret; the More sheet (the header's ⋯) |
| A canvas | Claude, Add a card, Fit to screen, Canvas options | the canvas's own Add (its sheet of kinds) and Fit (Shift+1), offered by its view; the More sheet |
| A notebook's index | Claude, Add a page, Read straight through, Notebook options | the index's own Add a page (the form, its field focused) and Read straight through; while reading, Back to the index in its place; the More sheet |
| A journal | Claude, New entry, Journal options | the journal's own New entry, its templates opened and brought into view; the More sheet |
| An organization's dashboard | Claude, New note in this organization, Invite, Organization settings | the hero's New (the + sheet filed in its workspace) and Invite (to the invite field, an owner or an admin only); the bar's cog |
| Settings | Claude | the chat, over Settings |

A canvas's JSON and a notebook's Markdown, when the view switch shows them, are words: their dock is a note's, less
Add, which a note of words alone has.

### Simple mode (GHST-103, 2026-10-18)

Matt, 2026-10-17: "allow selecting between simple and advanced mode where simple mode has a much more approachable UI
with fancy features hidden behind more." With Simple chosen (Settings, the walkthrough, home's one-time card) the
pages of notes keep their dock less Claude: Claude and Talk to Claude are advanced. Everything else about the dock is
as above. The root decides (lib/root/root_parts.dart `_homePage`, `_notesDock`, reading `preferences.value.simple`);
the home page's own dock is handed no Claude, and a page of notes' seam has none.

| Page, in simple mode | Rings, head to foot |
| --- | --- |
| Home | Search, + (Write a note), Speak where the build records, Settings |
| All notes | Search, +, Speak, Settings |
| Tags, a tag's notes, a smart notebook | Search, +, Speak, Settings (reached only by a saved link or a tab: simple mode's sidebar and palette do not offer them) |
| A note's words, a canvas, a notebook, a journal, an organization's dashboard, Settings | As advanced: these docks are the note's, the organization's and Settings' own slices, and are not trimmed here |

The + in simple mode opens on Note and one row, "More…", that opens in place to Today, an entry, Canvas, Notebook,
Meeting and a shared link (lib/notes/new_sheet.dart `NewSheet.simple`).

Nothing is taken out of the top bars: the dock is another place for what is already there.

## The dock editor (2026-10-27)

Matt, 2026-10-27: "build the dock editor", from docs/ideas/CUSTOMIZATION_AND_SOUNDS.md idea 9: "Choose and order the
floating dock's buttons (Claude, search, +, mic, Market, Settings), and which sit on the phone versus the Fold. The dock
is now fixed."

Settings, Appearance, **Dock** (the last card, in Simple too): the app's buttons as a list, dragged into order by their
grips (lib/book/row_drag.dart, the notebook's own drag; Move up and Move down for a screen reader), each with a switch,
beside the dock drawn as it will be, and Reset to default. "Its own dock when wide" gives the Fold opened, a tablet or a
desktop window a dock of its own, copied from the phone's to start, and Phone or Wide chooses which is edited. In Simple
the list is Simple's four buttons (Search, Write a note, Speak, Settings) and the wide dock is behind More, opened in
place. Settings' search finds the card by "dock", "buttons", "reorder", "mic" and the buttons' names.

- **Kept as** `Preferences.dock` (lib/core/dock_layout.dart `DockPrefs`, `DockLayout`): `{"order": [...], "hidden":
  [...], "wide": {...}}`, synced with the rest of the settings. An empty order is the default one, and nothing chosen
  is the dock as the tables above have it.
- **Settings is never hidden** (`dockKeptIds`): on a phone the dock's cog is the way into Settings that is always in
  reach. Its switch is held on and its row says why; a store that hid it shows it anyway.
- **Every dock reads it** (`PageDock`, through `dockPrefs` for the window's width): home, All notes, the collections,
  the Market, a note, an organization and Settings. The app's buttons among a page's rings are ordered and hidden;
  a page's own rings (a note's Find and Add, a canvas's Fit, an organization's Invite, a note's ⋯) keep their places.
  A dock with every ring hidden (Settings' own, Claude alone) draws no pill.
- **One microphone is the dock's rule now** (`DockLayout.arrange`): the pages hand it Speak whether or not Talk to
  Claude is there, and where Talk is drawn, Speak and a note's own mic are not. So hiding Talk in the editor brings
  Speak back, as it would be with the Claude plugin off.
- The room a page keeps at its foot is still for every ring it was handed: a hidden ring leaves a little more air.

Tests: test/core/dock_layout_test.dart (the default, the JSON, the sync, the order, the one microphone, Settings kept),
test/settings/dock_editor_test.dart (dragged, switched, reset, the wide dock, Simple's list and More, a page's dock
following each), and pictures in build/feature-shots/dock-editor/ (test/settings/dock_editor_shots_test.dart).

## Claude's subject

The chat with Claude holds no subject of its own. A note's dock (a canvas, a notebook and a journal are notes) opens
it with the note's `[[Title]] ` in the field, ready to ask about; another note's dock pressed while the chat is open
down the right puts that note's title in the field, where nothing has been written. The other pages open the chat as
the home page does, with the field empty: an organization and Settings have no `[[link]]` to give it.

## How it is built

| Part | Where |
| --- | --- |
| A ring, the pill, the room it takes, the tip, the frame that places it, the offers, `windowEndCover` | lib/shell/page_dock.dart |
| The home page's dock, now the pill with Settings at its foot | lib/home/home_screen.dart (`HomeScreen.onSettings`) |
| All notes, the collections, an organization, Settings | lib/notes/all_notes_screen.dart, lib/notes/collection_screen.dart, lib/orgs/ui/organization_screen.dart, lib/settings/settings_screen.dart (each `dock:`) |
| A note's dock, its rings for what is up, its room at the foot | lib/note/note_screen.dart (`NoteScreen.dock`, `_dockRings`) |
| Add at the caret's line | lib/root/note_desk.dart (`_openAdd`, `NoteSeams.onAdd`) |
| What a canvas, a notebook and a journal offer | lib/canvas/canvas_view.dart, lib/book/book_view.dart, lib/book/journal_view.dart (`DockOffer`) |
| The halo while the dock is aside | lib/art/dock_smoke.dart (`DockSmoke.shown`) |
| The dock smaller while the page scrolls, and its halo with it | lib/shell/page_dock.dart (`DockShrink`, `dockHearsScroll`), lib/art/dock_smoke.dart (`DockSmoke.scale`, `DockHalo.reach`), lib/home/home_screen.dart (`_screen`) |
| The root's seams: Claude about a page, the halo, a page of notes' rings | lib/root/root_parts.dart (`_notesDock`, `_pageDock`), lib/root/root_claude.dart (`_claudeDockAbout`) |
| The chat's field and its cover of the window's end | lib/claude/claude_chat.dart (`initial`, `windowEndCover`) |
| Tests | test/shell/page_dock_test.dart (the pill, the tip, the offers, home, All notes, the collections, Settings), test/note/note_dock_test.dart (a note's words, a canvas, a notebook, a journal, the keyboard), test/orgs_ui/organization_dock_test.dart, test/root/wiring_test.dart ("puts the dock on every page"), test/shell/dock_scroll_test.dart (smaller while the page scrolls), test/root/simple_test.dart (no Claude on home's and All notes' docks in simple mode) |

A page is handed a `PageDockSeam` (Claude, the halo, and for a page of notes its rings and Settings) and draws its dock
with a `PageDockFrame` round what scrolls. A view inside a note offers its rings with a `DockOffer`, which the note's
screen hears (`DockOffers`), so the canvas's own Add and Fit, and the index's own buttons, are what the dock presses.

## Not done

- The recorder, a meeting, the Academy and an organization's audit log have no dock: each takes the whole window for
  one thing, and has its way out at its top.

### Simple shell (GHST-105, 2026-10-18)

Matt, 2026-10-18: "The simple mode in the app is not quite right, it still is a bit complex with the tabs and such,
spend a significant amount of time looking into simple apps like todoist and others to build out a clean simple UI."
Since then simple mode's places have no bar over them at all: the shell draws them plain (lib/shell/app_shell.dart
`_plain`): no control row, no tab row, no drawer, no docked sidebar, no aside, and the row of open notes is only ever
the note on screen (`OpenTabsController.trimTo`). The home page in simple mode is lib/simple/simple_home.dart
(`SimpleHome`) in place of HomeScreen, and it has **no dock of rings**: its two controls are drawn as themselves
(lib/simple/simple_bar.dart), a filled round + (a note straight away; held, the + sheet) and a plain round microphone
(Talk to Claude where Claude can hear, the recorder otherwise, one microphone only as GHST-104 has it), over a bar
along the foot with two destinations, Notes and To-dos. The gear is in the page's header. A note opened from it on a
phone draws its own Back at the start of its header (`NoteScreen.back`), since there is no bar with Home; its dock
is the note's as above. On a wide window the shell draws the list as a column beside the note, the switch under the
title and the + and the microphone at the column's foot, and the note's Format pill measures its room by the pane,
not the window. All notes, the collections, an organization's page and Settings keep the docks the table above
gives them.

| Page, in simple mode (GHST-105) | Controls |
| --- | --- |
| Home | The gear in the header; the + and the microphone over the bar's end; Notes and To-dos along the foot (lib/simple/simple_bar.dart `SimpleActions`, `SimpleBar`) |
| A note | Its own Back at the header's start on a phone; the dock as above |

Tests: test/simple/simple_home_test.dart (the page), test/shell/simple_shell_test.dart (the plain shell, the one
tab, the wide window; in place of simple_bar_test.dart, which held simple mode to a trimmed bar), test/root/simple_test.dart
and test/root/simple_wide_test.dart (the root wiring on a phone and on the Fold opened out).
