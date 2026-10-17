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
  with its dot while an AI is online. What the page is for in the middle. A settings-type ring at the foot, always,
  where the page has one: Settings on a page of notes, the ⋯ on a note, the cog on an organization's page.
- **How it moves.** Search's magnifier leans in when pressed, a + gives a quarter turn, Speak's ink pill dips, the rest
  are still. Under reduced motion nothing turns and the dock comes and goes at once.
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
| Home | Claude, Search, + (Write a note), Speak, Settings | Ask Claude; the command palette; the + sheet; the recorder; the app's Settings |
| All notes | Claude, Search, +, Speak, Settings | the same, from the root (lib/root/root_parts.dart `_notesDock`) |
| Tags, a tag's notes, a smart notebook | Claude, Search, +, Speak, Settings | the same |
| A note's words | Claude, Find in note, Speak, Add, Note options | the chat with `[[Title]] ` in its field; the note's find bar; the note's own mic (Talk into this note, not on a spoken note, which has its tape's Add); the +'s list for the caret's line, placed at the caret; the More sheet (the header's ⋯) |
| A canvas | Claude, Add a card, Fit to screen, Canvas options | the canvas's own Add (its sheet of kinds) and Fit (Shift+1), offered by its view; the More sheet |
| A notebook's index | Claude, Add a page, Read straight through, Notebook options | the index's own Add a page (the form, its field focused) and Read straight through; while reading, Back to the index in its place; the More sheet |
| A journal | Claude, New entry, Journal options | the journal's own New entry, its templates opened and brought into view; the More sheet |
| An organization's dashboard | Claude, New note in this organization, Invite, Organization settings | the hero's New (the + sheet filed in its workspace) and Invite (to the invite field, an owner or an admin only); the bar's cog |
| Settings | Claude | the chat, over Settings |

A canvas's JSON and a notebook's Markdown, when the view switch shows them, are words: their dock is a note's, less
Add, which a note of words alone has.

Nothing is taken out of the top bars: the dock is another place for what is already there.

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
| The root's seams: Claude about a page, the halo, a page of notes' rings | lib/root/root_parts.dart (`_notesDock`, `_pageDock`), lib/root/root_claude.dart (`_claudeDockAbout`) |
| The chat's field and its cover of the window's end | lib/claude/claude_chat.dart (`initial`, `windowEndCover`) |
| Tests | test/shell/page_dock_test.dart (the pill, the tip, the offers, home, All notes, the collections, Settings), test/note/note_dock_test.dart (a note's words, a canvas, a notebook, a journal, the keyboard), test/orgs_ui/organization_dock_test.dart, test/root/wiring_test.dart ("puts the dock on every page") |

A page is handed a `PageDockSeam` (Claude, the halo, and for a page of notes its rings and Settings) and draws its dock
with a `PageDockFrame` round what scrolls. A view inside a note offers its rings with a `DockOffer`, which the note's
screen hears (`DockOffers`), so the canvas's own Add and Fit, and the index's own buttons, are what the dock presses.

## Not done

- The recorder, a meeting, the Academy and an organization's audit log have no dock: each takes the whole window for
  one thing, and has its way out at its top.
