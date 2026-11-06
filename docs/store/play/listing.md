# The Play listing, 2.4.25

Paste each fenced block into the Play Console field it is named for (Grow users › Store presence › Main store
listing), without the heading. Written 2026-11-05 against the Flutter app at 2.4.25, the Play build
(tool/cutover-build.sh --play). It replaces tauri/docs/store/play/copy/ (September, the Tauri app, voice first; its
full description was 4,059 characters, over the limit).

The rules the copy keeps: no third party's name or mark (no Claude, Anthropic, Notion, Slack, GitHub, Google, Figma,
Lovart, PostHog, OpenAI, Gemini, MCP, nor a calendar's, a watch's or a typeface's name), no em or en dashes, no
exclamation marks, nothing the Play build does not do (it has no updater, and no watch app: that is not uploaded), and
plain words. British spelling, as the Console's default language is English (United Kingdom). `node
docs/store/play/check.mjs` counts the blocks and looks for the banned words.

## App name (30)

```
Ghost.md: Notes in Markdown
```

What the Console has held since 2026-10-05. The name under the icon is Ghost.md.

## Short description (80)

```
Notes you say or type, kept as plain Markdown files on your phone.
```

## Full description (4,000)

```
Ghost.md is a notes app where every note is a plain Markdown file on your phone. Say a note or type it. Either way it lands with its headings, lists and to-dos in place.

SAY IT
Tap the microphone and talk. Your voice is turned into words on the phone, by a model it downloads once. Say "heading, before we go" and a heading appears. "Remember to book the cabin" becomes a to-do with its box, and "scratch that" takes back the last thing you said. Say "Hey Ghost, add this to House jobs" and the words go into that note instead. Hey Ghost is only heard inside a recording you started.

MEETINGS AND TAPES
Record a meeting and let the screen go off. When it ends, the phone transcribes it and writes a summary under the title: what was decided, and the to-dos as boxes. Every spoken note keeps its recording, to play back or add to.

AN AI ASSISTANT, IF YOU WANT ONE
Bring a key from the AI provider you prefer. It stays on this phone. Ask from any page and watch the assistant search your notes, write into them and plan with them. Give it a photo of a schedule or a whiteboard and it writes what is in it into a note, with appointments as dated to-dos. Without a key, everything else works.

TO-DOS, REMINDERS AND YOUR CALENDAR
To-dos from every note gather on one page under Overdue, Today, Later and Someday. Give one a time and it rings on the minute. Add your calendar and today's events sit above your to-dos.

THE MARKDOWN
Headings, lists, tables, code, footnotes and links between notes are drawn as you type with the marks dimmed, so a note reads the same in any other app. Seven marks of Ghost.md's own, from highlight to spoiler, which sits in smoke until you tap it. Diagrams and timelines are drawn from text in the note.

BOARDS, QUERIES, NOTEBOOKS AND CANVASES
A list can be a board with cards you drag between columns. A query gathers notes, to-dos or tickets from across your library and shows them as a board, a table, a calendar or a timeline. Notes gather into a notebook with an index, and a journal keeps an entry each time you write. A canvas puts cards on a page with lines between them.

PLUGINS
Connect the tools you already use, each switched on or off on one page that says what it reaches: your calendar, code repositories, team wikis and chat, webhooks, and an address that turns email into notes. Wrapped looks back over your year in notes and helps you clear out what went stale.

ON YOUR HOME SCREEN
Widgets for today, your to-dos, your calendar, a pinned note and a quick voice note, a tile in quick settings for a new note, and shortcuts on the icon.

SIMPLE OR ADVANCED
Choose how much of the app you see. Simple keeps it to your notes, a search and your to-dos, and everything else waits until you want it.

SYNC, TEAMS AND PRIVACY
No account is needed, and without one none of your notes is on any server. Sign in and your notes are the same on your phone, your computer and in a browser, encrypted on the phone before they leave, so the server cannot read them. Make an organization and invite people, and the notes you file there are shared with them, encrypted the same way. The assistant sees only what you ask and the notes it reads to answer, sent to the provider you chose with your own key. Delete your account in Settings and everything it kept goes with it.

No ads and no tracking. Ghost.md sends anonymous usage stats, counts of which features are used, never your notes or who you are. Turn them off in Settings › Privacy.
```

What it leaves out for room, all true on the Play build: the review after Done, the effects that move, tickets,
folding phones, live typing, shared links, the Academy and the Guide, Notion import.

## Release notes, 2.4.25 (500)

The en-GB box of the release. The first version on Play, so it says what came in the last few releases.

```
Wrapped, a new plugin: your year in notes as a story to swipe through, then a tidy-up of old to-dos and stale notes, each with Undo. Plugins can now add a button to the dock.
Give the AI assistant a photo of a schedule, a receipt or a whiteboard and it writes what is in it into your notes.
Maps in notes are drawn in full colour, and header images keep their own colours in dark mode.
```
