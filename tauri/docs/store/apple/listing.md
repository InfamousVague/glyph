# The App Store listing

What App Store Connect holds for the iPhone app (Ghost Markdown, app 6818598896, `com.mattssoftware.glyph`). Since
2026-10-18 it is version 2.2.1's (Matt: "redo the website and the app store listing to highlight more important
features that set us apart like the claude integrations and calendar integrations as well as notion etc"), written
there through the App Store Connect API (`ghost-md-app-store-pack/tools/asc.mjs`). The pictures are not in the
repository: they are in `~/Development/Apps/ghost-md-app-store-pack/screenshots/`. American spelling, for the en-US
listing. No em or en dashes, no exclamation marks, nothing the app does not do on an iPhone (guideline 2.3).

**What the iPhone build does, and so what the listing may claim** (checked in the code on 2026-10-18, build 2.2.1):
the app's own Claude (own key, model and effort, live typing, thinking shown, the Ask Claude note); the connector
for Claude's own app (with an account); the Calendar plugin (iCal addresses, Google Calendar's sign-in, which
glyph-api offers, events on Today and in queries, dated to-dos on Google's); GitHub, Contacts and Webhooks; queries,
boards, tickets, notebooks, journals, canvases, Mermaid and gantt drawn in the note and full screen; pictures from
the camera and photos; sealed sync and organizations. **Not on an iPhone, so not in this listing:** Notion and Slack
(listed as plugins, but every request answers "Notion is not available on iOS yet", lib/core/iphone_app.dart
`notOnIPhone`), Talk to Claude and every other way into a recording (no microphone, `recordsVoice`), the on-phone
AI, place reminders, finding where you are, .ghostex export, and the Import page (so Todoist and Things imports).
No iPad: `TARGETED_DEVICE_FAMILY` is 1.

## Name (30)

```
Ghost Markdown
```

The name the app record was made with. The name under the icon is Ghost.md (`CFBundleDisplayName`).

## Subtitle (30)

```
Markdown notes with Claude
```

The subtitle is the app's, not the version's (`appInfoLocalizations`): it is shown for the Mac too once 2.2.1 is
released. Its words are indexed for search, which is why the keywords leave Claude out. If review objects to a
third party's name in the subtitle (2.3.7), "Markdown notes with AI" is the fallback.

## Promotional text (170)

```
Ask Claude with your own key and watch it write into your notes, its thinking shown. Your calendar on Today, dated to-dos on Google Calendar, every note plain Markdown.
```

## Keywords (100)

```
notes,ai,assistant,calendar,to-do,kanban,board,notebook,journal,canvas,tickets,mcp,github,md,sync
```

## Description (4,000)

```
Ghost.md is a notes app in plain Markdown with Claude built in. Every note is a Markdown file on your iPhone, and Claude can read it, write in it and plan with it while you watch.

CLAUDE, IN THE APP
Ask Claude from the dock at the head of any page. Bring your own Anthropic API key, kept on this iPhone, and choose the model and how much effort it puts in. Claude searches and reads your notes, then makes and changes them: the note opens and the words are typed in as Claude writes them, and the chat shows Claude's thinking as it goes. Write a request in your Ask Claude note and Claude works through it.

CLAUDE'S OWN APP, CONNECTED
With an account, connect Claude's own app to Ghost.md's MCP server. From there Claude can list, search, read, write and add to your notes, and you see it at work in Ghost.md, on the note it is writing.

YOUR CALENDAR
Connect Google Calendar, or add any calendar's iCal address, from iCloud, Outlook or Fastmail. Today's events sit on the home page above your to-dos, and a query lists them or lays them on a calendar beside your to-dos. Switch it on and every to-do with a due date goes onto your Google Calendar, moved when its date changes and taken off when it is done.

PLUGINS
Claude, Calendar, GitHub, Contacts and Webhooks are built in, each switched on or off on one page that says plainly what it reaches. Link a note to a GitHub repo and its list items become issues you can tick off from either side. Contacts puts a person's picture on the to-dos that name them, a tap away from a call, a text or an email. Webhooks tell a URL of yours when a note changes, and give you URLs that add to a note, for Zapier, Make, IFTTT or a line of curl.

THE MARKDOWN CORE
Headings, lists, to-dos, tables, code, footnotes and links between notes, drawn as you type with the marks left dimmed, so a note reads the same anywhere. Seven marks of Ghost.md's own: highlight, aside, unsure, redact, shout, added, and spoiler, which sits in smoke until you tap it. Mermaid diagrams and gantt timelines are drawn in the note and open full screen. Add pictures from your photos or the camera.

BOARDS, TICKETS AND QUERIES
A list can be a board, with cards you move between columns. A note can be a ticket, with its status, assignee, priority and due date kept at its top. A query gathers notes, to-dos, tickets or events from across your library and draws them live, as a board, a table, a list, a calendar or a timeline.

NOTEBOOKS, JOURNALS AND CANVASES
Notes gather into a notebook with an index, to read page by page or straight through. A journal keeps an entry for each time you write, named by the minute. A canvas puts cards on a page with lines between them, saved as JSON Canvas.

WORKSPACES AND TEAMS
File notes under workspaces to keep work and home apart. With an account, make an organization and invite people by their handle. It gets a workspace of its own on each member's devices.

SYNC AND PRIVACY
No account is needed. Without one, your notes stay on your iPhone and nothing of yours is on any server. Sign in and your notes are the same on your iPhone, on a Mac and in a browser, sealed on the device before they leave. The server cannot read them, and your password never leaves the device. Claude sees only what you ask it and the notes it reads to answer, sent to Anthropic with your own key. Delete the account in Settings and everything it kept goes with it. No ads, no analytics, no tracking.
```

## What's New, 2.2.1 (4,000)

```
Claude, in the app: ask with your own Anthropic API key, choose the model and the effort, and watch Claude type into your notes with its thinking shown.
Claude's own app, connected through Ghost.md's MCP server, is seen at work on the note it is writing.
Calendars: connect Google Calendar or add an iCal address. Events show on Today and in queries, and dated to-dos can go onto your Google Calendar.
A Plugins page: Claude, Calendar, GitHub, Contacts and Webhooks, each switched on or off in one place.
Simple or advanced: choose how much of the app is shown.
```

## What's New, 2.0.5

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

Ten, 1320 x 2868 for the 6.9-inch slot (`APP_IPHONE_67`; Apple takes 1260 x 2736, 1290 x 2796 or 1320 x 2868
there), 24-bit PNG with no alpha, each under a kicker and a caption, in this order:

| # | Kicker | Caption | Raw |
| --- | --- | --- | --- |
| 1 | Claude | Ask Claude about your notes. Watch it think. | claude-chat |
| 2 | Claude, writing | Claude types into your note as you watch. | claude-typing |
| 3 | Calendar | Your meetings and your to-dos on one calendar. | calendar |
| 4 | Plugins | Claude, Calendar, GitHub and more, built in. | plugins |
| 5 | Claude, both ways | Claude's own app can work in your notes too. | claude-plugin |
| 6 | Queries | Ask across every note. Drawn live. | board |
| 7 | Timelines | Gantt charts and diagrams, drawn from text. | timeline |
| 8 | Notebooks | A notebook, read straight through. | notebook |
| 9 | The marks | Plain Markdown, with marks of its own. | marks |
| 10 | Canvas | Cards on a canvas, lines between them. | canvas |

In `ghost-md-app-store-pack/screenshots/2026-10-18-flutter-2.2.1/` (`raw/`, kept for the website too, and
`iphone-6.9/`). How they were shot:

1. `tool/cutover-build-ios.sh 2.2.1 --simulator` (the store build's code and plain look as a debug build), with
   debug-only staging hooks that are on the branch `store-pictures-2.2.1` and not on main: `invented+` (the
   invented library plus a "This week" note with a calendar of to-dos and a "Launch timeline" with a gantt), `claude`
   (a scripted Claude conversation in place of Anthropic's API, lib/shell/tour_claude.dart: no key, nothing sent;
   the tools it calls are the app's own and run over the invented notes), `plugin:<id>[,off]` and `calendar:<url>`.
   Each is read only where `kDebugMode`, so a release has none of it.
2. An iPhone 17 Pro Max simulator (440 x 956 points at 3), dark, the status bar set to 9:41, full bars, battery full.
3. `tools/shoot-ios-2.2-scene.sh '<steps>'` in the pack: a fresh install, then the tour. The calendar is a made-up
   iCal file served from the Mac (`tools/serve-ics.mjs`), added as an address, so the events are read as a real
   address's are. Notion is switched off in the plugins picture, since it does not work on an iPhone; Webhooks and
   GitHub are on. The Claude plugin's page is shown without a key ("Add your API key").
4. `tools/compose-ios-2.2.mjs` in the pack (the frame and fonts of the 2.0.5 set, scaled to 1320 across).

The 2.0.5 set (seven pictures of the same invented library, 1290 x 2796) is still in
`screenshots/2026-10-13-flutter-2.0.5/`, and still on the live 2.0.5 version.

### The iPhone Duo set (APP_IPHONE_DUO)

The same ten scenes, kickers and captions, 2007 x 2853 (the Duo's inner display, the size the 1.10.0 Duo set was
accepted at), 24-bit PNG with no alpha, in `screenshots/2026-10-18-flutter-2.2.1/iphone-duo/` (raws in `raw-duo/`).
**They are pictures of the Duo simulator's cover screen** (1398 x 2034, the app's phone layout), drawn whole inside the
2007 x 2853 frame: the simulator boots folded, and nothing in `simctl` unfolds it (`io screenConfig` can power a screen
on or off but SpringBoard stays on the cover). Unfolding is done in Xcode's Device Hub, not done here. The cover's own
status cluster (the time and Wi-Fi at its right edge) shows in each picture. Shot by
`tools/shoot-ios-2.2-duo-scene.sh` (screenshots from `--display=1`) and composed by `tools/compose-ios-2.2-duo.mjs`.

## Version 2.2.1 in App Store Connect (2026-10-18)

- Build 2.2.1 (2002001) made by `tool/cutover-build-ios.sh 2.2.1` from 37dfa47e, validated and uploaded with
  `xcrun altool` (delivery 57310627-081e-44a6-9b42-2c1686961020), processed `VALID`, `usesNonExemptEncryption` false.
- Version 2.2.1 created (`ed771246-adbf-4016-8b51-ed5fdaa0dfb7`, `PREPARE_FOR_SUBMISSION`, released after approval
  as 2.0.5 was), the build attached, the en-US fields above set and read back, the subtitle set on the app info, the
  seven inherited screenshots taken off this version's set (2.0.5's own are untouched) and the ten above uploaded,
  each `COMPLETE`. The Duo set above was made on this version (2.0.5 had none) and its ten are `COMPLETE`. Review details came across from 2.0.5. **Not submitted**: Matt reviews, then submits.
- The custom product page "Markdown, supercharged!" was not changed: its version 1 is waiting for review.

