# The App Store listing

What App Store Connect holds for the iPhone app (Ghost Markdown, app 6818598896, `com.mattssoftware.glyph`), written there
through the App Store Connect API on 2026-10-02 for version 1.10.0. The first version is notes only and iPhone only
(Matt, 2026-10-02), so nothing here mentions voice, the AI, maps, export or any other platform than the Mac and the web.
The pictures are not in the repository: they are in `~/Development/Apps/ghost-md-app-store-pack/` (`screenshots/iphone-6.9/`,
and `tools/` to shoot them again), as the Play pack's are. American spelling, for the en-US listing. No em or en dashes,
no exclamation marks, nothing the app does not do on an iPhone.

## Name (30)

```
Ghost Markdown
```

The name the app record was made with. The name under the icon is Ghost.md (`CFBundleDisplayName`).

## Subtitle (30)

```
Notes in plain Markdown
```

## Promotional text (170)

```
Notes in plain Markdown, with to-dos, boards, tickets, notebooks and a canvas. No account needed, and with one your notes are sealed on the device before they sync.
```

## Keywords (100)

```
markdown,notes,to-do,checklist,kanban,board,notebook,journal,canvas,tickets,writing,lists,sync,md
```

## Description (4,000)

```
Ghost.md is a notes app in plain Markdown. Every note is a Markdown file on your iPhone. Headings, lists and to-dos are drawn as you type, with the marks left dimmed, so a note reads the same anywhere.

THE MARKS
Headings, lists, to-dos, tables, code, footnotes and links between notes. Then seven marks of Ghost.md's own: highlight, aside, unsure, redact, shout, added, and spoiler, which sits in smoke until you tap it. And five effects that move: heat, frost, a wave, a shimmer and a haunting. Add pictures to a note from your photos or the camera.

BOARDS
A list can be a board, with cards you move between columns.

TICKETS AND QUERIES
A note can be a ticket, with its status, assignee, priority and due date kept at its top. A query in a note gathers notes from across your library and draws them live, as a board, a table or a list.

NOTEBOOKS, JOURNALS AND CANVASES
Notes gather into a notebook with an index, to read page by page or straight through. A journal keeps an entry for each time you write, named by the minute. A canvas puts cards on a page with lines between them, saved as JSON Canvas.

WORKSPACES AND TEAMS
File notes under workspaces to keep work and home apart. With an account, make an organization and invite people by their handle. It gets a workspace of its own on each member's devices.

SYNC AND PRIVACY
No account is needed. Without one, your notes stay on your iPhone and nothing of yours is on any server. Sign in and your notes are the same on your iPhone, on a Mac and in a browser, sealed on the device before they leave. The server cannot read them, and your password never leaves the device. Delete the account in Settings and everything it kept goes with it. Share a note or a notebook as a read-only link: its key rides in the link after the #, so the server cannot read what it holds. No ads, no analytics, no tracking.
```

## What's New, 2.0.5 (4,000)

Set on version 2.0.5 through the API on 2026-10-13 (en-US, the only localization).

```
Ghost.md has been rebuilt and is faster. Your notes and your sign-in carry over when you update.

Search on the home page puts the nearest note first, forgives a typo and shows the line that matched.
A note's authors show on the home list.
An organization's members list shows the AIs that read its notes.
```

## The rest of the version page

- Support URL: https://ghostmarkdown.com/privacy.html (its Contact section has the address; the home page has none).
- Privacy policy URL: https://ghostmarkdown.com/privacy.html
- Copyright: 2026 Matt Wisniewski
- Category: Productivity
- Age rating: every answer None or No (4+). No user-generated content: notes are private, a shared link is a
  read-only page in a browser, and an organization shares no notes yet.
- Price: free. Available everywhere but mainland China, which asks for an ICP filing number.
  And, since 2026-10-13, but France (Matt: no French encryption declaration for now; `../APP_STORE.md`).

## The screenshots

Seven, 1290 x 2796 for the 6.9-inch slot (`APP_IPHONE_67` in the API; Apple takes 1260 x 2736, 1290 x 2796 or
1320 x 2868 there), each under a kicker and a caption as the Play set is: Home (Your day on one page.), The marks
(Plain Markdown, with marks of its own.), Boards (A list can be a board.), Queries (Ask across every note. Drawn
live.), Tickets (A note can be a ticket.), Notebooks (A notebook, read straight through.), Canvas (Cards on a
canvas, lines between them.).

**Since 2026-10-13 they are pictures of the Flutter app** (Matt: "update the screenshots and resubmit"), the same
seven scenes in the same order over the same invented library, in `ghost-md-app-store-pack/screenshots/2026-10-13-flutter-2.0.5/`
(`raw/` and `iphone-6.9/`; the Tauri page's set is still in `screenshots/iphone-6.9/`, untouched). How they are
shot:

1. `tool/cutover-build-ios.sh 2.0.5 --simulator`: the store build's code and look (plain, the slight blur behind
   the header) as a debug build. Shot from f84d01f0, which is the uploaded build's commit (b656aca3) with two
   debug-only additions to the tour and nothing else in the app.
2. A simulator of an iPhone 16 Plus (430 x 932 points at 3, which is 1290 x 2796), dark, its status bar set with
   `xcrun simctl status_bar … override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4
   --wifiBars 3`.
3. The app's own debug tour (lib/shell/phone_tour.dart), with `invented` as the script's first step: the app
   opens no core and draws the store pictures' invented notes (`seedLibrary`, lib/core/sample_library.dart). A
   fresh install for each scene, so no tab is left from the one before; each note opened through Search and
   commands by its title. Weekend trip is scrolled 236 points; Portugal is put in Read straight through; the
   canvas is fitted, moved and pinched (`pinch:`) to the Before we go group. The two scripts are
   `tools/shoot-ios-flutter-tour.sh` and `tools/shoot-ios-flutter-scene.sh` in the pack.
4. `tools/compose-ios-flutter.mjs` in the pack: `compose-ios.mjs` reading and writing the dated folder, the same
   frame and captions.

What differs from the Tauri set: each picture has the phone's status bar (the web page had none); due dates that
have passed are drawn red, since the simulator's clock is today's and the notes' dates are September's and early
October's; the home page's times read from today. Nothing recorded is in any of them, no scene was replaced, and
the names in them are the invented library's (Sam, Ana, Ali, and "Matt" on one made-up ticket, as before).
