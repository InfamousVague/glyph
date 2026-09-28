# What Ghost.md does, as shipped

The map the listing was written from: each feature as the app really has it, with its own words, read from the Guide
(`src/app/guidebook/`, chapters 1 to 26), docs/MARKDOWN.md, BOARDS.md, BOOKS.md, CANVAS.md, SYNC.md, SHARING.md, the
landing page and DESIGN §113 to §128, at 1.8.0-20. Meetings are from the 1.9.0 spec (§127 sections 3 to 5), which is
the build going to Play.

## The flagship six

The listing leads with these. Each is something a person would install the app for, each is true today or in the
Play build, and each has a screenshot.

| | Feature | Why it leads |
|---|---|---|
| 1 | Speaking a note, with the cues | It is the app. Nothing else on the phone turns "bullet point" into a bullet as you say it. |
| 2 | Hey Ghost, into a note you name | The words land in another note's list while you talk, with Undo. The thing people show each other. |
| 3 | The AI on the phone: the review, and the runs | A second listen and a read-through after every recording, every change marked to keep or revert, and no cloud. |
| 4 | Meetings, tapes and summaries | Record with the screen off, written up afterwards with a summary under the title. New in the Play build. |
| 5 | Plain Markdown, and the marks | One .md file per note, the seven marks and five effects, boards, notebooks, journals and canvases. |
| 6 | Private by design | No account needed; sync and shares sealed on the device; nothing listens in the background. |

Supporting, mentioned in a line each: the side key, the Fold, the Mac app, Notion and GitHub, the Claude connector,
the Academy and the Guide.

## 1. Speaking a note

Four ways in: Speak in the dock, the microphone in a note's bar (Talk into this note; Add on its tape once it has one),
the side key held (Android, once Ghost.md is the digital assistant), and the launcher shortcut Record a voice note.
Every way opens the same recorder.

Before the first word: the ghost listening, "Start talking.", the counter, how the recording ends ("Tap Done to
stop."), and the Things to say card with To shape it, To send it somewhere, To ask the AI.

While you talk, words appear as they are heard, laid out as they will read. The cues, as the app reads them:

- "Title: weekend trip" (or "Call this note …"), or a short first sentence, becomes `# Weekend trip`.
- "Heading: the budget" (or "New section") is `## The budget`; "Subheading" is `###`.
- "Bullet point: the heating", "Next point: …", "The next item is …" make bullets. A list said in one breath ("we
  need snacks, water, a charger and the good playlist") becomes a lead line and bullets.
- "Number one: passports", or "First … Then … Finally …", numbers a list.
- "Check box: call the plumber", "Remember to book the cabin" (also "I need to", "Don't forget to", "Remind me to")
  make `- [ ]`; "Done task: pay the deposit" makes `- [x]`.
- "Bold … end bold", "italic … end italic", "strike … end strike"; "Important: …" writes `**Important:**`.
- "Quote: …", "Info box: …", "Warning callout: …", "Hidden line: …".
- "New paragraph", or two seconds of quiet; "new line"; "Divider".
- "hashtag travel", "note link weekend trip end link", "footnote … end footnote", "bookmark this", "define X as Y",
  "emoji party popper", "code … end code", "Code block in bash … End code block", "maths … end maths",
  "Calculate: four hundred plus one hundred twenty", "counter three of eight", "option: tent", "picked option: cabin".
- The marks: "highlight … end highlight", "aside", "unsure", "redact", "shout", "added", "spoiler"; the effects:
  "heated", "frosted", "wavy", "shimmering", "haunted", each closed with "end …" (or "and …", since Whisper hears
  one for the other).
- Taking it back: "Scratch that" (also strike that, take that back, forget that, delete that, never mind, cancel
  that); "Actually, …" replaces the last sentence with the corrected one; "No wait, four" changes one number, day,
  month or name; "Scratch that, add it to Groceries instead" moves it. Each shows Took back "…" with Undo.

Done writes the note once, from the whole recording. Discard keeps nothing. The phone's back gesture, the side key
and the screen going off all save as Done does. The recording is kept as the note's tape. Better words (on by
default) runs the larger speech model over the recording afterwards. Every engine listens for English.

No cue exists for a table, a picture, a diagram or a board; the recorder says so and keeps the words.

## 2. Hey Ghost

"Hey Ghost, add a note to House TODOs." Then "Call an electrician to fix the light sockets." The top line reads
Adding to "House TODOs", the page shows that note, and each sentence is written into its list as it is said: under
the heading that shares its words (Electrical, not Kitchen), as a to-do in a to-do list, in the list's own style.
Nothing is stored until Done; then the note opens with Added to House TODOs and Undo. Not this note sends the
recording back to its own note.

"Hi Ghost", "OK Ghost", "So Ghost" and the old word "Glyph" work; "Ghost" alone does not. A name is found by its
words, so "house list", "house chores" and "house" all find House TODOs. A name that could be two notes shows a
card, Add to which note?; a name that matches none keeps the words where you are and says so.

In the middle of a recording, "Hey Ghost, add call Sam to House TODOs" sends just those words. "Hey Ghost, move this
to Groceries" moves the recording. "Hey Ghost, make a new list called Packing with toothbrush, socks and charger"
shows Create Packing at Done. A notebook is never written into by voice.

No microphone is left listening for the name. It is heard inside a recording you started, and nowhere else.

## 3. The AI on the phone

Two kinds of model, both on the device, downloaded once, checked byte for byte: Whisper base.en (about 60 MB, live)
and small.en (about 190 MB, afterwards); and one language model chosen in Settings › Recording › Model: Qwen3.5 2B,
4B (the default, 2.7 GB), 9B, or Gemma 4 E4B. The app never fetches a language model without being asked.

From a note's More sheet, under AI: Format ("Tidy and organise, keeping every word that matters"), Summarize ("The
point of the note and its tasks, in far fewer words", above the note), Enhance ("Every thought finished and the note
made fuller, without inventing"). Spoken into a note: "Hey Ghost, fix the spelling", "summarise this", "make this a
list", "tidy this up", "flesh it out", "carry on", or any free ask.

Lines land as they finish. Added words are tinted, removed words struck through, and each group of changes has Keep
and Revert; Keep all in the strip; typing on a changed line keeps it. Undo puts the whole note back. A finished run
adds Ghost to the note's authors ("By yourname and Ghost").

The review after recording (on by default): the note opens, the larger speech model listens again, the two
transcripts are compared, the language model thinks it through out loud and each thing it finds lands as a marked
change. The phone at work scene covers the screen while it runs: the step list (Listening again, Loading the model,
Reading the note, Thinking it through, Writing what it found, Done), Heat, CPU, Pace, Since Done, and the line "It
carries on behind the note. Nothing leaves the phone."

The gist: one quiet line under a note's card, written by the smallest model on the phone. Local only (Settings ›
Formatting) stops every download, update check, sync and internet plugin.

## 4. Meetings, tapes and summaries

Tapes: every spoken note keeps its recording; a cassette at the top of the note with Play, Add and Remove, the reels
turning as it plays. The Tapes shelf on the home page shows the last eight as cards, with the summary's first line or
the gist under each, and the counter and date ("47:12 · 25 Sept").

Summaries (§127 section 2): a `## Summary` section under the title, one prose line then items, kept as words in the
body, so it syncs, shares and feeds To do. Settings › Recording › Summaries: Meetings (default), Long recordings (over
three minutes), Off. The setting's own line: "The language model on the phone writes a summary under the title. What
was said, what was decided, and your to-dos."

Meetings (1.9.0, §127 sections 3 to 5): + › Meeting, "Record a meeting. The screen can go off. It is written up
afterwards." A foreground service holds the microphone; the notification reads "Recording · 12:40" with Stop and
Discard; "Muted by another app" when a call takes the microphone; after two hours "Still recording?" and a hard stop
at four. The dictation features are off during a meeting: no live reader, no Hey Ghost, no review. Afterwards the
write-up runs on the phone with the app closed ("Listening to the recording, 40%", "Summarizing"), when charging or
above half by default, and a notification says "Written up: Meeting, 26 Sep 14:05" with the summary's first sentence,
private on the lock screen. Meeting audio does not sync unless Sync meeting recordings is switched on.

## 5. Plain Markdown, and the marks

A note is one `.md` file named after its first line, in Inbox/ or a workspace's folder, readable in any editor and
in Obsidian. Browse files opens the folder in Android's Files app (read-only there) or Finder. Front matter is kept
as found.

Standard Markdown, drawn as typed with the marks left dimmed on the page: six headings, bullets, numbered steps,
to-dos ticked with a tap, quotes, callouts (NOTE, TIP, IMPORTANT, WARNING, CAUTION), rules, tables, code blocks,
Mermaid diagrams, definitions, footnotes, links, `[[wiki links]]` between notes, tags, superscript and subscript,
maths as code, emoji names. Plus counters `[3/8]`, sums `= 450 + 120`, choices `- ( )`, hidden lines, the bookmark
`§§`, progress under a heading ("3 of 7"), and pictures. Two views: Markdown and Formatted.

Ghost.md's own seven (the Marks plugin): spoiler `||…||` in smoke, highlight `==…==` (with a colour: `(green)`),
aside `%%…%%`, unsure `??…??`, redact `@@…@@` (a bar of ink, lifted while the caret is in it), shout `^^…^^`, added
`++…++`. Any of them can carry a note in brackets. The five effects, each an emoji twice: 🔥🔥heat🔥🔥 (the line
above wavers), ❄️❄️frost❄️❄️, 🌊🌊wave🌊🌊, ✨✨shimmer✨✨, 👻👻haunt👻👻. They hold still under reduce motion.

Boards: a ```` ```board ```` fence naming columns of anchored items (`^book-cabin`). Make a board from the More
sheet, Board from list or Add to board from the press-and-hold menu. Cards tick, drag between columns, and a Done
column means done. Notebooks: `book: true` and an index of links; Read straight through, Previous and Next, the
Notebook index aside, Notebooks on the home page. Canvases: JSON Canvas 1.0 after a `title:` front matter, six card
kinds (words, a note, a link, a picture, a chart, a table), groups, lines with words, a minimap, and `![[A canvas]]`
to frame one inside a note.

## 6. Private by design

Without an account nothing of yours is on a server. With one: the password becomes two keys and only one is sent;
notes, recordings, pictures and settings are sealed with AES-256-GCM before they leave; the server sees the handle,
random ids, sizes and times, and the kind of each device, never a word. Eight recovery codes, shown once. Nobody can
reset a lost password. Delete account is in Settings › Account and on the web.

Sharing: a read-only link `ghostmarkdown.com/read.html#<id>.<key>`, the key after the # that a browser never sends.
A note or a whole notebook; edits follow; Stop sharing takes it down; Shared links lists every one.

The microphone listens only while you record. No analytics, no crash reporting, no ads, no advertising id. The web
version uses the browser's own speech recognition (Chrome sends voice to Google); the apps transcribe on the device.
Link previews ask the linked site for its title, and can be switched off.

## Supporting

- **The side key**: Ghost.md takes the phone's digital-assistant role, so a held side key starts a recording, over
  the lock screen too; a locked phone goes back behind its lock at Done without showing the note. The welcome guide
  walks the Samsung and Pixel settings rows. Or the launcher shortcut Record note.
- **The Fold**: the note unfolds with the hinge on the way open; opened out, Settings is a split view and the
  sidebar can dock beside the note.
- **The Mac app** (macOS 13.1 or later): Whisper and the models run there too; ⌘K opens the palette; Browse files
  opens Finder. **The web app** at attack.fm/glyph: the same editor, the browser's speech recognition, no models.
- **Notion and GitHub**: list items become tasks or issues (swipe left, the quiet word, press and hold, or Send
  list); a ticked box and a finished task agree both ways; a linked repo is read into a briefing for the model.
- **Claude**: an MCP connector, hosted at attack.fm/glyph/api/mcp or run on your own computer; list, read, search,
  make, rewrite, append, pin or archive, never delete; signs as Claude.
- **The Academy**: thirteen lessons, one mark at a time, with the note's own editor drawing what you type. **The
  Guide**: Settings › About › Add Ghost.md: The Guide, 44 chapters as notes in your library. **The cheat sheet**.
- **Settings**: Page (System, Light, Dark, Dawn, Boreal, Ember), two fonts, spacing, corners, code colours,
  animations (Ghostly typing, smoke at the edges, ripples), Local only.
- **Updates**: a Play copy gets new apps from the store; the web bundle still updates over the air (JavaScript in
  the WebView, which Play allows).

## Not in the app, so not in the copy

No cloud AI, no iOS app yet, no voice cue for tables, boards, pictures or diagrams, no live collaboration with
other people (Live typing is between your own devices, and a trial), no colour picker on a canvas, no moving a card
by voice, no wake word listening in the background.
