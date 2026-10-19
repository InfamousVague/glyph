# The App Store listing

What App Store Connect holds for the iPhone app (Ghost Markdown, app 6818598896, `com.mattssoftware.glyph`). Since
2026-10-18 it is version 2.2.1's (renumbered 2.3.1 with a new build on 2026-10-19, below) (Matt: "redo the website and the app store listing to highlight more important
features that set us apart like the claude integrations and calendar integrations as well as notion etc"), written
there through the App Store Connect API (`ghost-md-app-store-pack/tools/asc.mjs`), and since 2026-10-19 without a
third party's name (below). The pictures are not in the repository: they are in
`~/Development/Apps/ghost-md-app-store-pack/screenshots/`. American spelling, for the en-US listing. No em or en
dashes, no exclamation marks, nothing the app does not do on an iPhone (guideline 2.3).

## No third party's name or mark in the listing (4.1(a), 2026-10-19)

**Apple refused iOS 2.2.1** (submission cf04e1e6-870a-4c90-a672-a5784f358b04, `UNRESOLVED_ISSUES`) under 4.1(a)
Copycats: "The metadata appears to contain potentially misleading references to third-party content. Specifically,
the metadata includes content that resembles Claude without the necessary authorization." The build (2002001) was not
flagged and is kept. Matt (2026-10-19): "Mention AI and stuff but don't include specific brands, for the claude
integrations show a generic AI icon for the submission".

**The rule, for every listing from now on (iPhone and Mac, words and pictures):** no third party's name or mark in
any metadata a customer sees: the subtitle, promotional text, keywords, description, What's New, screenshots and their
captions, the header and search pictures. Not Claude, Anthropic, Notion, Slack, GitHub, Google, Todoist, Things, MCP,
iCloud, Outlook, Zapier, Mermaid, JSON Canvas, Qwen, YouTube, Spotify, Figma or a typeface's name; not Anthropic's
spark, and not Claude's orange as a brand cue. Say what a thing does: "an AI assistant", "your AI assistant's own
app", "Ghost.md's connector", "your calendar", "code repositories", "plugins for the tools you use". The review notes
are not public and may name Claude plainly.

**The pictures** come from a debug build made with `--dart-define=GHOST_STORE_NEUTRAL=true` on the staging branches
(`store-pictures-2.2.1`, `store-pictures-mac-2.2.1`; never main): lib/claude/store_neutral.dart turns the app's Claude
into a generic assistant (a plain four-pointed sparkle in grey for the mark and its orange, "Assistant" or "AI" for the
name in the chat, the bar over a note, the caret and the plugin's page, the settings row in graphite), and names no
maker on Rich embeds' card, the AI row's model or Appearance's typeface. It is `const` on `kDebugMode`, so a release
compiles none of it. On the plugins picture GitHub, Notion and Slack are switched off, so the cards in view are the
assistant, Calendar, Webhooks and Marks (and Rich embeds on the Mac).

**Apple refused iOS 2.3.1 too** (2026-10-19, submission d0c82f81-…, the same 4.1(a) words), while the shared subtitle
still read "Markdown notes with Claude". Matt: "also make sure the colors and everything doesn't look like Claude".
**The colour rule, for every store picture (screenshots, header, search, iPhone and Mac):** nothing in Claude's look.
No coral or terracotta orange (#D97757 and its neighbours #C6613F, #CC785C, #DA7756: hue about 8 to 32 degrees,
saturation over 0.35, value over 0.45), no radiating spark or asterisk, no ivory or cream page (#F5F4ED, #FAF9F5)
with that orange, no orange chat bubbles, avatars, send or stop buttons, pills, rings or caret labels. The assistant is
drawn in the app's own greys (a plain four-pointed sparkle in grey, grey bubbles and buttons). Check a set with
`ghost-md-app-store-pack/tools/orange-audit.py --grid <png>...`, which counts the pixels in that window and says where
they are; every final should read 0. The other hues the app draws (a red today line, a salmon-red due date, amber and
green chips, the violet "Assistant" caret label, a canvas's blue, green and violet cards) are not Claude's and stay.

**What the iPhone build does, and so what the listing may claim** (checked in the code on 2026-10-18, build 2.2.1):
the app's own AI assistant, Claude (own key, model and effort, live typing, thinking shown, the Ask Claude note); the
connector (the MCP server) for the assistant's own app (with an account); the Calendar plugin (iCal addresses, Google
Calendar's sign-in, which glyph-api offers, events on Today and in queries, dated to-dos on Google's); GitHub, Contacts
and Webhooks; queries, boards, tickets, notebooks, journals, canvases, Mermaid and gantt drawn in the note and full
screen; pictures from the camera and photos; sealed sync and organizations. **Not on an iPhone, so not in this
listing:** Notion and Slack (listed as plugins, but every request answers "Notion is not available on iOS yet",
lib/core/iphone_app.dart `notOnIPhone`), Talk to Claude and every other way into a recording (no microphone,
`recordsVoice`), the on-phone AI, place reminders, finding where you are, .ghostex export, and the Import page (so
Todoist and Things imports). No iPad: `TARGETED_DEVICE_FAMILY` is 1.

## Name (30)

```
Ghost Markdown
```

The name the app record was made with. The name under the icon is Ghost.md (`CFBundleDisplayName`).

## Subtitle (30)

```
Markdown notes with AI
```

The subtitle is the app's, not the version's (`appInfoLocalizations` 8854f86d-…), and the Mac's too. **Set on
2026-10-19 at about 20:53 UTC** and read back, once the Mac review was cancelled (while a version is in review its app
info refuses it: 409, "The field 'subtitle' can not be modified in the current state"). It read "Markdown notes with
Claude" until then, which is what both 4.1(a) refusals saw. It was set alone with a PATCH of that localization, not
with `ios-2.2.1-neutral.mjs words` (which would also write 2.2.1's What's New over 2.3.1's and could add the old
review sentence that named Claude), so 2.3.1's What's New was not touched.

## Promotional text (170)

The words below are set by `ghost-md-app-store-pack/tools/ios-2.2.1-neutral.mjs` (`check` measures them and looks
for a brand, `words` writes and reads them back).

```
Ask an AI assistant with your own key and watch it write into your notes, its thinking shown. Meetings on Today, dated to-dos on your calendar, every note plain Markdown.
```

## Keywords (100)

```
notes,ai,assistant,chat,calendar,to-do,kanban,board,notebook,journal,canvas,tickets,gantt,md,sync
```

## Description (4,000)

```
Ghost.md is a notes app in plain Markdown with an AI assistant built in. Every note is a Markdown file on your iPhone, and the assistant can read it, write in it and plan with it while you watch.

AN AI ASSISTANT, IN THE APP
Ask from the dock at the head of any page. Bring your own API key, kept on this iPhone, and choose the model and how much effort it puts in. The assistant searches and reads your notes, then makes and changes them: the note opens and the words are typed in as it writes them, and the chat shows its thinking as it goes. Write requests in a note of their own and the assistant works through them.

YOUR AI ASSISTANT'S OWN APP, CONNECTED
With an account, connect your AI assistant's own app to Ghost.md's connector. From there the assistant can list, search, read, write and add to your notes, and you see it at work in Ghost.md, on the note it is writing.

YOUR CALENDAR
Sign in to your calendar, or add any calendar's subscription address. Today's events sit on the home page above your to-dos, and a query lists them or lays them on a calendar beside your to-dos. Switch it on and every to-do with a due date goes onto the calendar you signed in to, moved when its date changes and taken off when it is done.

PLUGINS FOR THE TOOLS YOU USE
The AI assistant, Calendar, Contacts, Webhooks and code repositories are built in, each switched on or off on one page that says plainly what it reaches. Link a note to a code repository and its list items become issues you can tick off from either side. Contacts puts a person's picture on the to-dos that name them, a tap away from a call, a text or an email. Webhooks tell a URL of yours when a note changes, and give you URLs that add to a note, for the automations you already run.

THE MARKDOWN CORE
Headings, lists, to-dos, tables, code, footnotes and links between notes, drawn as you type with the marks left dimmed, so a note reads the same anywhere. Seven marks of Ghost.md's own: highlight, aside, unsure, redact, shout, added, and spoiler, which sits in smoke until you tap it. Diagrams and gantt timelines are drawn from text in the note and open full screen. Add pictures from your photos or the camera.

BOARDS, TICKETS AND QUERIES
A list can be a board, with cards you move between columns. A note can be a ticket, with its status, assignee, priority and due date kept at its top. A query gathers notes, to-dos, tickets or events from across your library and draws them live, as a board, a table, a list, a calendar or a timeline.

NOTEBOOKS, JOURNALS AND CANVASES
Notes gather into a notebook with an index, to read page by page or straight through. A journal keeps an entry for each time you write, named by the minute. A canvas puts cards on a page with lines between them, saved in an open file format.

WORKSPACES AND TEAMS
File notes under workspaces to keep work and home apart. With an account, make an organization and invite people by their handle. It gets a workspace of its own on each member's devices.

SYNC AND PRIVACY
No account is needed. Without one, your notes stay on your iPhone and nothing of yours is on any server. Sign in and your notes are the same on your iPhone, on a Mac and in a browser, sealed on the device before they leave. The server cannot read them, and your password never leaves the device. The AI assistant sees only what you ask it and the notes it reads to answer, sent to your AI provider with your own key. Delete the account in Settings and everything it kept goes with it. No ads, no analytics, no tracking.
```

## What's New, 2.3.1 (4,000)

Set by `ghost-md-app-store-pack/tools/ios-2.3.1.mjs words` (2026-10-19). The live iPhone version is 2.0.5 (2.2.1 never
shipped), so it says what is new since 2.0.5: 2.2.1's lines, then 2.3.1's. Checked in the code at 3f17f313: simple
mode's home, To-dos and note header have no platform gate (lib/simple, lib/note/note_screen.dart), and draw no
microphone on an iPhone; "Ghost in meetings" is not offered there (`publishingOffered()` is false on iOS, so
lib/root/account_wiring.dart makes no MeetIn and Settings shows no card), so it is not named.

```
An AI assistant, in the app: ask with your own API key, choose the model and the effort, and watch it type into your notes with its thinking shown. When it makes a new note, the note opens and the words are typed in as you watch.
Your AI assistant's own app, connected through Ghost.md's connector, is seen at work on the note it is writing.
Calendars: sign in to your calendar or add a calendar's subscription address. Events show on Today and in queries, and dated to-dos can go onto your calendar.
A Plugins page: the AI assistant, Calendar, Contacts, Webhooks and code repositories, each switched on or off in one place.
Simple or advanced: choose how much of the app is shown. Simple mode is a plain home page with a search and your notes grouped by when you last wrote in them, and a To-dos page with every open to-do across your notes under Overdue, Today, Later and Someday. In simple mode a note has just Notes, More and Done at its head, and the formatting bar adds a picture, a list, a table or a date.
```

## What's New, 2.2.1 (4,000)

Never shipped: replaced by 2.3.1's above.

```
An AI assistant, in the app: ask with your own API key, choose the model and the effort, and watch it type into your notes with its thinking shown.
Your AI assistant's own app, connected through Ghost.md's connector, is seen at work on the note it is writing.
Calendars: sign in to your calendar or add a calendar's subscription address. Events show on Today and in queries, and dated to-dos can go onto your calendar.
A Plugins page: the AI assistant, Calendar, Contacts, Webhooks and code repositories, each switched on or off in one place.
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
there), 24-bit PNG with no alpha, each under a kicker and a caption, in this order (the store-neutral set,
2026-10-19):

| # | Kicker | Caption | Raw |
| --- | --- | --- | --- |
| 1 | AI assistant | Ask your AI assistant. Watch it think. | claude-chat |
| 2 | AI, writing | AI types into your note as you watch. | claude-typing |
| 3 | Calendar | Your meetings and your to-dos on one calendar. | calendar |
| 4 | Plugins | Plugins for the tools you use, built in. | plugins |
| 5 | AI, both ways | Your AI assistant's own app can work in your notes too. | claude-plugin |
| 6 | Queries | Ask across every note. Drawn live. | board |
| 7 | Timelines | Gantt charts and diagrams, drawn from text. | timeline |
| 8 | Notebooks | A notebook, read straight through. | notebook |
| 9 | The marks | Plain Markdown, with marks of its own. | marks |
| 10 | Canvas | Cards on a canvas, lines between them. | canvas |

In `ghost-md-app-store-pack/screenshots/2026-10-19-flutter-2.2.1-neutral/` (`raw/` and `iphone-6.9/`). Every final was
read whole and run through tesseract for brand names before it went up. How they were shot:

1. The store-neutral simulator build: on `store-pictures-2.2.1` (37dfa47e, the build's own commit, plus the debug-only
   hooks), `flutter build ios --simulator --debug` with cutover-build-ios.sh's defines and
   `--dart-define=GHOST_STORE_NEUTRAL=true`. The hooks: `invented+` (the invented library plus a "This week" note with
   a calendar of to-dos and a "Launch timeline" with a gantt), `claude` (a scripted conversation in place of
   Anthropic's API, lib/shell/tour_claude.dart: no key, nothing sent; the tools it calls are the app's own and run over
   the invented notes), `plugin:<id>[,off]` and `calendar:<url>`. Each is read only where `kDebugMode`.
2. An iPhone 17 Pro Max simulator (440 x 956 points at 3), dark, the status bar set to 9:41, full bars, battery full.
3. `tools/shoot-ios-2.2.1-neutral-scene.sh '<steps>'` in the pack: a fresh install, then the tour. The calendar is a
   made-up iCal file served from the Mac (`tools/serve-ics.mjs`). On the plugins picture GitHub and Notion are off,
   Webhooks on. Switching Contacts on raises iOS's permission prompt, which outlives an uninstall: reboot the
   simulator to clear it.
4. `tools/compose-ios-2.2.1-neutral.mjs` (the frame and fonts of the 2.0.5 set, scaled to 1320 across), with the
   pack's root served on 127.0.0.1:54791.

The 2026-10-18 set (with Claude's name and mark) is kept in `screenshots/2026-10-18-flutter-2.2.1/` and is on no
version now.
The 2.0.5 set (seven pictures of the same invented library, 1290 x 2796) is still in
`screenshots/2026-10-13-flutter-2.0.5/`, and still on the live 2.0.5 version.

### The iPhone Duo set (APP_IPHONE_DUO)

The same ten scenes, kickers and captions, 2007 x 2853 (the Duo's inner display, the size the 1.10.0 Duo set was
accepted at), 24-bit PNG with no alpha, in `screenshots/2026-10-19-flutter-2.2.1-neutral/iphone-duo/` (raws in
`raw-duo/`).
**They are pictures of the Duo simulator's cover screen** (1398 x 2034, the app's phone layout), drawn whole inside the
2007 x 2853 frame: the simulator boots folded, and nothing in `simctl` unfolds it (`io screenConfig` can power a screen
on or off but SpringBoard stays on the cover). Unfolding is done in Xcode's Device Hub, not done here. The cover's own
status cluster (the time and Wi-Fi at its right edge) shows in each picture. Shot by
`tools/shoot-ios-2.2.1-neutral-duo-scene.sh` (screenshots from `--display=1`) and composed by
`tools/compose-ios-2.2.1-neutral-duo.mjs`.

## Version 2.2.1 in App Store Connect (2026-10-18)

- Build 2.2.1 (2002001) made by `tool/cutover-build-ios.sh 2.2.1` from 37dfa47e, validated and uploaded with
  `xcrun altool` (delivery 57310627-081e-44a6-9b42-2c1686961020), processed `VALID`, `usesNonExemptEncryption` false.
- Version 2.2.1 created (`ed771246-adbf-4016-8b51-ed5fdaa0dfb7`, `PREPARE_FOR_SUBMISSION`, released after approval
  as 2.0.5 was), the build attached, the en-US fields above set and read back, the subtitle set on the app info, the
  seven inherited screenshots taken off this version's set (2.0.5's own are untouched) and the ten above uploaded,
  each `COMPLETE`. The Duo set above was made on this version (2.0.5 had none) and its ten are `COMPLETE`. Review details came across from 2.0.5. **Not submitted**: Matt reviews, then submits.
- The custom product page "Markdown, supercharged!" was not changed: its version 1 is waiting for review.

### After the 4.1(a) refusal (2026-10-19)

- The version's en-US words above set and read back (`tools/ios-2.2.1-neutral.mjs words`); the subtitle refused while
  the Mac version is in review (above).
- Both picture sets on 2.2.1 replaced: the ten old `APP_IPHONE_67` and ten old `APP_IPHONE_DUO` deleted on this version
  only, the neutral ten of each uploaded (`tools/upload-ios-2.2.1-neutral.mjs`), all twenty `COMPLETE`.
- The header and search pictures: placements 1dc00019-… (header-f-screens) and 28c00019-… (search-d-three) deleted,
  their library images left in the library; `creative-assets/2026-10-19/header-f-screens-neutral.png` ("Ask your AI.
  Watch it type.") and `search-d-three-neutral.png` ("Your notes, connected" over AI, Calendar, Plugins), made by
  `tools/compose-store-2026-10-19.mjs` (layouts `h19-screens`, `s19-three`; the words inside Apple's art safe area),
  uploaded with `tools/upload-creative.mjs --ref-date=2026-10-19` and placed on 2.2.1: header 4c000019-66b8-8ff0-8f33-
  94c414cc10e0, search bec00019-66b8-8ff0-8f00-70bbd8d96eb4, both `ACTIVE`.
- A sentence added to the review notes: the listing names no third party; in the app the assistant is Claude, used
  only with the person's own Anthropic API key, and Ghost.md is not made by or affiliated with Anthropic.
- Build 2002001 still attached. **Not resubmitted**: Matt resubmits, after the subtitle is set.

## Version 2.3.1 in App Store Connect (2026-10-19)

Matt: "push a new version since we're at 2.3.1 now anyways", and "also remove the rejected 2.2.1 version for iOS".

- Build 2.3.1 (2003001) made by `tool/cutover-build-ios.sh 2.3.1` from 3f17f313 (the "+" in its commit is a peer's
  uncommitted tauri/ test report, nothing the iPhone app builds), validated and uploaded with `xcrun altool` (delivery
  70c98c77-7bcf-4146-b367-72e76f5fcfbe), processed `VALID`, `usesNonExemptEncryption` false.
- The refused version renumbered rather than replaced: `PATCH appStoreVersions/ed771246-…` with versionString 2.3.1
  was accepted, and the version went from `REJECTED` to `PREPARE_FOR_SUBMISSION`; build 2003001 attached in 2002001's
  place (`tools/ios-2.3.1.mjs renumber`). No version named 2.2.1 is left on iOS.
- The refused review submission cf04e1e6-870a-4c90-a672-a5784f358b04 cancelled (`canceled: true`), now `COMPLETE`, so
  nothing named 2.2.1 is pending. A new submission is made when 2.3.1 is sent.
- What's New above set; promotional text, keywords and description read back equal to the brand-free words above; the
  ten `APP_IPHONE_67` and ten `APP_IPHONE_DUO` pictures `COMPLETE`, the header (4c000019-…) and search (bec00019-…)
  placements `ACTIVE`, all carried with the version.
- **The pictures against 2.3.1** (advanced mode, which they show): the shell, home, note, plugins and settings code
  paths between 37dfa47e and 3f17f313 change nothing in advanced mode (the simple shell is `_plain`, the Format bar's
  new tail is drawn only where `prefs.simple`). One thing is visible: the assistant's chat bubbles set their words in
  white rather than near-black (bfeadba6), so picture 1 ("Ask your AI assistant. Watch it think.", 6.9" and Duo) shows
  the old dark ink on the grey bubbles. No other picture shows a bubble.
- **Refused** on 2026-10-19 (submission d0c82f81-fd11-4813-abcf-4f9ea7743c19, `UNRESOLVED_ISSUES`), 4.1(a) again:
  "the metadata includes content that resembles Claude". The subtitle still named Claude (above).

### After the second 4.1(a) refusal (2026-10-19)

- The subtitle set to "Markdown notes with AI" (above). The review notes already named no third party.
- The colour audit (the rule above) over all 29 pictures and the header and search: everything was grey but the cabin
  canvas's Ember card ("Ask Sam about the dog") and its "who brings what" line, drawn in the app's coral (#FF9782, hue
  10) in picture 10 of the iPhone and the Duo and picture 9 of the Mac (1143, 1223 and 1914 pixels in the window). The
  store-neutral build now draws those two in violet (`lib/core/sample_library.dart`, on `store-pictures-2.2.1` 6139adc7
  and `store-pictures-mac-2.2.1` 65de13be, debug only); the three canvas pictures were shot again with the same steps
  and composed by `tools/compose-ios-neutral-v2.mjs`, `compose-ios-neutral-v2-duo.mjs` and `compose-mac-neutral-v2.mjs`
  into `screenshots/2026-10-19-flutter-neutral-v2/` (the other pictures there are the neutral set's, byte for byte).
  Every final there reads 0 in the window; the header and search pictures read 0 and were not made again; the app
  icon (the dotwork ghost on paper) reads 0. The iPhone build used main's GhostCore.xcframework (the core changed only
  in its on-device AI between 37dfa47e and main, which no picture shows).
- Both sets on 2.3.1 replaced with the v2 ten of each (`tools/upload-ios-neutral-v2.mjs`), all twenty `COMPLETE`; the
  header (4c000019-…) and search (bec00019-…) placements kept, `ACTIVE`.
- Resubmitting d0c82f81 was refused (409, "Version is not ready to be submitted yet"), so it was cancelled
  (`COMPLETE`) and **2.3.1 submitted in a new review submission, ae7df6d4-ff43-44f4-8a84-e3d0f23957ff** (`IOS`, this
  version only), `WAITING_FOR_REVIEW` at 21:01 UTC. Picture 1 still shows the bubbles' older dark ink (above).


## macOS 2.2.1 (the Mac App Store)

The macOS version of the same record, 2.2.1 (`525d24c4-5a8b-4e76-b002-16d0bb433db4`), written on 2026-10-18 through
the API (`ghost-md-app-store-pack/tools/mac-2.2.1.mjs`). Its words lead as the iPhone's do but say what the Mac
does. The subtitle above is the app's and was left as iOS 2.2.1 set it.

**What the Mac App Store build does, and so what this listing may claim** (checked in the code on 2026-10-18, the
sandboxed build `tool/cutover-build-mac-store.sh` makes): the app's own Claude (own key in the Keychain, model and
effort, live typing, thinking shown, the Ask Claude note) and Talk to Claude by voice (the Mac records; Whisper in the
core, the model downloaded into the container); the connector for Claude's own app; Calendar (Google's sign-in goes
through the browser and glyph-api, no local listener; iCal addresses; dated to-dos onto Google Calendar); Notion
(same sign-in shape, `notOnIPhone` is null on a Mac) and Slack (incoming webhooks); GitHub, Webhooks and Contacts
(the address book entitlement is the store build's sixth); the Todoist import; rich embeds; voice notes written down
on the Mac; Mermaid and gantt; pictures from a file or the clipboard; tabs, sidebar, command palette. **Not claimed:**
place reminders and time reminders (Android only); the Things import from Things' own database (the sandbox's HOME is
the container, so it never finds Things; paste from Things still works); saving a .ghostex to a folder (it goes to the
share menu) and choosing one in Import (the panel defaults to .enex, every Mac build); a meeting with the Mac's own
sound (not proven sandboxed); Backup to a drive and the Guide (hidden in the store build).

### Promotional text (170)

```
Ask Claude with your own key, typed or spoken, and watch it write into your notes. Your calendar on Today, Notion and Slack built in, every note plain Markdown.
```

### Keywords (100)

```
notes,ai,calendar,notion,slack,to-do,kanban,board,notebook,journal,canvas,tickets,mcp,github,md,sync
```

### Description (4,000)

```
Ghost.md is a notes app in plain Markdown with Claude built in. Every note is a Markdown file on your Mac, and Claude can read it, write in it and plan with it while you watch.

CLAUDE, IN THE APP
Ask Claude from the dock on any page or from the command bar. Bring your own Anthropic API key, kept on this Mac, and choose the model and how much effort it puts in. Claude searches and reads your notes, then makes and changes them: the note opens and the words are typed in as Claude writes them, and the chat shows Claude's thinking as it goes. Click Talk to Claude and say what you want instead of typing it. Write a request in your Ask Claude note and Claude works through it.

CLAUDE'S OWN APP, CONNECTED
With an account, connect Claude's own app to Ghost.md's MCP server. From there Claude can list, search, read, write and add to your notes, and you see it at work in Ghost.md, on the note it is writing.

YOUR CALENDAR
Connect Google Calendar, or add any calendar's iCal address, from iCloud, Outlook or Fastmail. Today's events sit on the home page above your to-dos, and a query lists them or lays them on a calendar beside your to-dos. Switch it on and every to-do with a due date goes onto your Google Calendar, moved when its date changes and taken off when it is done.

PLUGINS
Claude, Calendar, Notion, Slack, GitHub, Contacts, Webhooks and Todoist are built in, each switched on or off on one page that says plainly what it reaches. Send a list's items to your Notion boards as tasks. Post a note to a Slack channel. Link a note to a GitHub repo and its list items become issues you can tick off from either side. Contacts puts a person's picture on the to-dos that name them. Webhooks tell a URL of yours when a note changes, and give you URLs that add to a note, for Zapier, Make, IFTTT or a line of curl. Bring your tasks over from Todoist.

SAY IT
Click the microphone and talk, and Ghost.md writes the words into the note as you say them. The speech model is downloaded once and runs on your Mac.

THE MARKDOWN CORE
Headings, lists, to-dos, tables, code, footnotes and links between notes, drawn as you type with the marks left dimmed, so a note reads the same anywhere. Seven marks of Ghost.md's own: highlight, aside, unsure, redact, shout, added, and spoiler, which sits in smoke until you click it. Mermaid diagrams and gantt timelines are drawn in the note and open full screen. Add pictures from a file or the clipboard.

BOARDS, TICKETS AND QUERIES
A list can be a board, with cards you move between columns. A note can be a ticket, with its status, assignee, priority and due date kept at its top. A query gathers notes, to-dos, tickets or events from across your library and draws them live, as a board, a table, a list, a calendar or a timeline.

NOTEBOOKS, JOURNALS AND CANVASES
Notes gather into a notebook with an index, to read page by page or straight through. A journal keeps an entry for each time you write, named by the minute. A canvas puts cards on a page with lines between them, saved as JSON Canvas.

A WINDOW OF ITS OWN
Notes open in tabs, with a sidebar for the library and a command palette on Command-K. New Note, Find, Sync Now and Settings are in the menu bar with the keys you expect.

WORKSPACES AND TEAMS
File notes under workspaces to keep work and home apart. With an account, make an organization and invite people by their handle. It gets a workspace of its own on each member's devices.

SYNC AND PRIVACY
No account is needed. Without one, your notes stay on your Mac and nothing of yours is on any server. Sign in and your notes are the same on your Mac, on an iPhone and in a browser, sealed on the device before they leave. The server cannot read them, and your password never leaves the device. Claude sees only what you ask it and the notes it reads to answer, sent to Anthropic with your own key. Delete the account in Settings and everything it kept goes with it. No ads, no analytics, no tracking.
```

### What's New, macOS 2.2.1

```
Claude, in the app: ask with your own Anthropic API key, typed or spoken, choose the model and the effort, and watch Claude type into your notes with its thinking shown.
Claude's own app, connected through Ghost.md's MCP server, is seen at work on the note it is writing.
Calendars: connect Google Calendar or add an iCal address. Events show on Today and in queries, and dated to-dos can go onto your Google Calendar.
A Plugins page: Claude, Calendar, Notion, Slack, GitHub, Contacts, Webhooks and Todoist, each switched on or off in one place.
Mermaid diagrams and gantt timelines drawn in the note, and queries shown as a calendar or a timeline.
Simple or advanced: choose how much of the app is shown.
```

### The Mac screenshots

Nine, 2880 x 1800 (`APP_DESKTOP`), 24-bit PNG with no alpha, framed as the 2.0.5 Mac set
(`tools/compose-mac-2.2.mjs`, from compose-mac-flutter.mjs), in
`ghost-md-app-store-pack/screenshots/2026-10-18-flutter-2.2.1/mac/` (raws in `mac-raw/`):

| # | Kicker | Caption | Raw |
| --- | --- | --- | --- |
| 1 | Claude | Ask Claude about your notes. Watch it think. | claude-chat |
| 2 | Claude, writing | Claude types into your note as you watch. | claude-typing |
| 3 | Calendar | Your meetings and your to-dos on one calendar. | calendar |
| 4 | Plugins | Claude, Calendar, Notion, Slack and more, built in. | plugins |
| 5 | Claude, both ways | Claude's own app can work in your notes too. | claude-plugin |
| 6 | Queries | Ask across every note. Drawn live. | board |
| 7 | Timelines | Gantt charts and diagrams, drawn from text. | timeline |
| 8 | Notebooks | A notebook, read page by page. | notebook |
| 9 | Canvas | Cards on a canvas, lines between them. | canvas |

Shot from `tool/cutover-build-mac-store.sh 2.2.1 --tour` (the store build's code as a debug build, its own bundle id
`com.mattssoftware.glyph.storeproof`, a dead service address) on the branch `store-pictures-mac-2.2.1`, which is
`store-pictures-2.2.1`'s hooks plus the same steps in lib/shell/desktop/mac_tour.dart (`invented+`, `claude`,
`plugin:<id>[,off]`, `calendar:<url>`; each read only where `kDebugMode`; not on main). The window drives itself
(`tools/shoot-mac-2.2-scene.sh '<steps>'` in the pack), 1440 x 900 at 2x, over the invented library; Claude is the
scripted conversation (no key, nothing sent); the calendar is the made-up iCal file `tools/serve-ics.mjs` serves.
On the plugins page Place reminders and Things are off.

### Version macOS 2.2.1 in App Store Connect (2026-10-18)

- Build 2.2.1 (2002001) made by `tool/cutover-build-mac-store.sh 2.2.1` from bf3f7fab (main, with 4514d0ec's fix that
  Claude's new note opens and is typed into), validated and uploaded with `xcrun altool -t macos` and the API key
  (delivery c0be322a-eaae-4513-b539-77a7782fcc6d; the one warning, 90889, is TestFlight's want of a provisioning
  profile, as for 2.0.5), processed `VALID`, `usesNonExemptEncryption` false.
- Version created `PREPARE_FOR_SUBMISSION`, released after approval, copyright 2026 Matt Wisniewski; the words above
  set and read back; the seven pictures it inherited taken off this version's set (2.0.5 keeps its own) and the nine
  above uploaded, each `COMPLETE`; review details as 2.0.5's, with a sentence each on Talk to Claude, Contacts and
  the in-app Claude's own key; the build attached.
- **Submitted for review** at 22:28:39 UTC in a review submission of its own, `ee10b934-0537-478e-a1c3-6ff6a1400383`
  (`MAC_OS`, holding only this version): `WAITING_FOR_REVIEW`. The iOS versions and submissions were not touched;
  no price, availability or age rating was changed.

### Cancelled, made brand-free and sent again (2026-10-19)

Matt: "also cancel the mac app and resubmit, both". Review submission ee10b934-… cancelled at 20:48 UTC while
`IN_REVIEW` (now `COMPLETE`, the version `DEVELOPER_REJECTED`). Then: the subtitle (above); the brand-free words below
set and read back (`tools/mac-neutral-v2.mjs words`); the nine pictures replaced on this version only with
`screenshots/2026-10-19-flutter-neutral-v2/mac/` (`tools/mac-neutral-v2.mjs shots`), all `COMPLETE`; the review notes'
"Talk to Claude" and their paragraph on Claude and Anthropic rewritten without a name ("The app's optional AI assistant
is a plugin that works only with an API key the person enters themselves (Settings, Plugins)", and the same 4.1(a)
sentence as the iPhone's). **Submitted in a new review submission, eff0e251-2f6b-4da1-9a95-de5ac1147f08** (`MAC_OS`,
this version only), `WAITING_FOR_REVIEW` at 21:00 UTC. A read of every field of both versions (description, keywords,
promotional text, What's New, subtitle, review notes) found no match for
`claude|anthropic|notion|slack|github|google|gemini|openai|qwen|mcp|youtube|spotify|figma`.

How the brand-free set was made (it was held ready before the cancel):
`ghost-md-app-store-pack/tools/mac-2.2.1-neutral.mjs` holds the words (`check` measures them; `words` would set them,
`shots` would replace the nine pictures) and the nine pictures are in
`screenshots/2026-10-19-flutter-2.2.1-neutral/mac/` (raws in `mac-raw/`), shot from the store-neutral tour
(`tool/cutover-build-mac-store.sh 2.2.1 --tour --dart-define=GHOST_STORE_NEUTRAL=true` on `store-pictures-mac-2.2.1`,
`tools/shoot-mac-2.2.1-neutral-scene.sh`, composed by `tools/compose-mac-2.2.1-neutral.mjs`) with the iPhone's
captions (8: "A notebook, read page by page."). GitHub, Notion and Slack are off on its plugins picture.

Promotional text:

```
Ask an AI assistant with your own key, typed or spoken, and watch it write into your notes. Meetings on Today, plugins for your tools, every note plain Markdown.
```

Keywords:

```
notes,ai,assistant,chat,calendar,to-do,kanban,board,notebook,journal,canvas,tickets,gantt,md,sync
```

Description:

```
Ghost.md is a notes app in plain Markdown with an AI assistant built in. Every note is a Markdown file on your Mac, and the assistant can read it, write in it and plan with it while you watch.

AN AI ASSISTANT, IN THE APP
Ask from the dock on any page or from the command bar. Bring your own API key, kept on this Mac, and choose the model and how much effort it puts in. The assistant searches and reads your notes, then makes and changes them: the note opens and the words are typed in as it writes them, and the chat shows its thinking as it goes. Or say it instead of typing it. Write requests in a note of their own and the assistant works through them.

YOUR AI ASSISTANT'S OWN APP, CONNECTED
With an account, connect your AI assistant's own app to Ghost.md's connector. From there the assistant can list, search, read, write and add to your notes, and you see it at work in Ghost.md, on the note it is writing.

YOUR CALENDAR
Sign in to your calendar, or add any calendar's subscription address. Today's events sit on the home page above your to-dos, and a query lists them or lays them on a calendar beside your to-dos. Switch it on and every to-do with a due date goes onto the calendar you signed in to, moved when its date changes and taken off when it is done.

PLUGINS FOR THE TOOLS YOU USE
The AI assistant, Calendar, Contacts, Webhooks, team boards, team chat and code repositories are built in, each switched on or off on one page that says plainly what it reaches. Send a list's items to your team's boards as tasks. Post a note to a team chat channel. Link a note to a code repository and its list items become issues you can tick off from either side. Webhooks tell a URL of yours when a note changes, and give you URLs that add to a note, for your automations. Bring your tasks over from another to-do app.

SAY IT
Click the microphone and talk, and Ghost.md writes the words into the note as you say them. The speech model is downloaded once and runs on your Mac.

THE MARKDOWN CORE
Headings, lists, to-dos, tables, code, footnotes and links between notes, drawn as you type with the marks left dimmed, so a note reads the same anywhere. Seven marks of Ghost.md's own: highlight, aside, unsure, redact, shout, added, and spoiler, which sits in smoke until you click it. Diagrams and gantt timelines are drawn from text in the note and open full screen. Add pictures from a file or the clipboard.

BOARDS, TICKETS AND QUERIES
A list can be a board, with cards you move between columns. A note can be a ticket, with its status, assignee, priority and due date kept at its top. A query gathers notes, to-dos, tickets or events from across your library and draws them live, as a board, a table, a list, a calendar or a timeline.

NOTEBOOKS, JOURNALS AND CANVASES
Notes gather into a notebook with an index, to read page by page or straight through. A journal keeps an entry for each time you write, named by the minute. A canvas puts cards on a page with lines between them, saved in an open file format.

A WINDOW OF ITS OWN
Notes open in tabs, with a sidebar for the library and a command palette on Command-K. New Note, Find, Sync Now and Settings are in the menu bar with the keys you expect.

WORKSPACES AND TEAMS
File notes under workspaces to keep work and home apart. With an account, make an organization and invite people by their handle. It gets a workspace of its own on each member's devices.

SYNC AND PRIVACY
No account is needed. Without one, your notes stay on your Mac and nothing of yours is on any server. Sign in and your notes are the same on your Mac, on an iPhone and in a browser, sealed on the device before they leave. The server cannot read them, and your password never leaves the device. The AI assistant sees only what you ask it and the notes it reads to answer, sent to your AI provider with your own key. Delete the account in Settings and everything it kept goes with it. No ads, no analytics, no tracking.
```

What's New:

```
An AI assistant, in the app: ask with your own API key, typed or spoken, choose the model and the effort, and watch it type into your notes with its thinking shown.
Your AI assistant's own app, connected through Ghost.md's connector, is seen at work on the note it is writing.
Calendars: sign in to your calendar or add a calendar's subscription address. Events show on Today and in queries, and dated to-dos can go onto your calendar.
A Plugins page: the AI assistant, Calendar, Contacts, Webhooks, team boards, team chat, code repositories and a to-do import, each switched on or off in one place.
Diagrams and gantt timelines drawn from text in the note, and queries shown as a calendar or a timeline.
Simple or advanced: choose how much of the app is shown.
```
