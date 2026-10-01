# The markdown Ghost.md speaks

What the editor parses and draws today, measured rather than assumed, and what was added to it. The rule behind all of
it: **a note is a markdown file**. Anything Ghost.md draws must read the same in GitHub, Obsidian or a plain text
editor, and anything it cannot draw must still be readable as words.

## What is supported

Measured by parsing each sample with the app's own language (`src/app/editor/language.ts`) and reading the syntax
tree.

| Syntax                    | Parsed | Drawn | Notes                                                       |
| ------------------------- | ------ | ----- | ----------------------------------------------------------- |
| Headings `#`–`######`      | yes    | yes   | Setext (`---` under a line) is deliberately off: on a phone it promoted a paragraph every time a list was started below it |
| Bold, italic, both         | yes    | yes   |                                                             |
| Strikethrough `~~`         | yes    | yes   | GFM                                                         |
| Inline code, fenced code   | yes    | yes   | A fence with a language is highlighted in it; the block is drawn as one card |
| Lists, ordered lists       | yes    | yes   | Wrapped lines hang off the marker, measured in the real face |
| Task lists `- [ ]`         | yes    | yes   | GFM. Ticking one syncs to a linked task (`src/app/editor/doneSync.ts`) |
| Blockquotes, nested        | yes    | yes   |                                                             |
| Tables                     | yes    | yes   | GFM. Drawn as a table, the fence still editable             |
| Links, reference links      | yes    | yes   | A long URL is shown short (`src/app/editor/links.ts`)               |
| Autolinks (bare and `< >`) | yes    | yes   | GFM                                                         |
| Images `![]()`             | yes    | yes   | Drawn under their line                                      |
| Places `[name](geo:lat,lon)` | as a link | yes | Added 2026-09-28: a link to a `geo:` address alone on its line draws its map card under it, and reads as its name off the caret (`src/app/editor/placeCards.ts`) |
| Films `[![video 0:12](image/…)](video/…)` | as a linked picture | yes | Added 2026-09-28: a poster picture linked to a film under `video/`, alone on its line, draws the film's card under it (`src/app/editor/videos.ts`) |
| Hard line breaks            | yes    | yes   | Two spaces at the end of a line                             |
| HTML blocks and tags       | yes    | as text | Never executed; a note is words                            |
| Comments `<!-- -->`        | yes    | as text |                                                            |
| Horizontal rules `---`     | yes    | yes   |                                                             |
| Superscript `^x^`          | yes    | yes   | Added 2026-09-16; was parsed and drawn as plain words        |
| Subscript `~x~`            | yes    | yes   | Added 2026-09-16                                            |
| Callouts `> [!NOTE]`       | as a quote | yes | Added 2026-09-16. NOTE, TIP, IMPORTANT, WARNING, CAUTION    |
| Emoji `:tada:`             | yes    | yes   | Drawn as the emoji; the words come back while the caret is on the line. A name the app doesn't know stays as words |
| Footnotes `[^1]`           | yes    | yes   | The marker raised and quiet, what it says on a tap; the definition set as small print. A marker with no definition stays plain, because it is a typo |
| Definition lists           | yes    | yes   | `Term` then `: the meaning`; the term set apart, the meaning hanging under it |
| Front matter               | yes    | yes   | Drawn as quiet keys rather than a rule, and the note is named by its `title:` |
| Math `$x$`, `$$x$$`        | yes    | yes   | Set as code, delimiters and all. No renderer: KaTeX is ~280 KB the phone doesn't need |
| Mermaid ```` ```mermaid ```` | as a code block | yes | Added 2026-09-17: drawn as the diagram it describes (`src/app/editor/mermaid.ts`), the fence tapped to edit. Mermaid itself, every diagram type, loaded the first time a note has one; a diagram that cannot be drawn stays as its text |
| Wiki links `[[Note]]`      | yes    | yes   | Opens that note; a title with no note is drawn dashed, and tapping it makes the note and opens it. `[[Note#^anchor]]` splits on the first `#`; `[[#^anchor]]` is a place in this note, drawn with the anchors (`src/app/editor/boards/anchors.ts`) |

A highlight can be given a colour by name, in the same brackets a note uses: `==the cabin key==(green)`, from the
kit's own ramps (blue, red, amber, green, teal, purple, gray). A name the build does not know stays the plain
highlight and its brackets are the note they always were.

Ghost.md's own marks are on top of that, each from the Marks plugin and switched off with it: `||spoiler||`,
`==highlight==`, `%%aside%%`, `??unsure??`, `@@redact@@`, `^^shout^^`, `++added++`, five effects, and a note on any
of them in brackets — `??four hundred??(Sam said 400)`.

A redaction is a solid bar of the page's ink over its words, and everything under it prints in that ink, an emoji
included (`app/ink.css --app-ink-flat`, a filter, since an emoji keeps its colours under `color`). It lifts while the
caret is in the words so they can be read and edited, and stays where there is no caret to lift it: in the Formatted
view, where the at signs are hidden too, on the reader page and on a note's card. It is a look only: the words stay in
the note, so the file a share or an export gives, and any other app, has them between their `@@`. (Cut once as "the
same as spoiler", and back at Matt's asking, 2026-09-26: the bar where the spoiler is smoke.)

**Effects** are moving looks on words, and each is written as its emoji twice either side. The emoji is the effect's
name, so a note read anywhere else still says what was meant.

| Written | Effect | Said while recording |
|---|---|---|
| `🔥🔥too hot to touch🔥🔥` | Heat: the words go bold and shimmer slightly, and the text on the line above them wavers in the heat coming off them, thinner on the line above that | "heated … end heated" |
| `❄️❄️frozen solid❄️❄️` | Frost: the words go cold, a grainy rime creeping over their edges and settling | "frosted … end frosted" |
| `🌊🌊out to sea🌊🌊` | Wave: the words bob along the line, a ripple passing through them | "wavy … end wavy" |
| `✨✨silver thread✨✨` | Shimmer: a glint slides across the words every few seconds | "shimmering … end shimmering" |
| `👻👻nobody there👻👻` | Haunt: the words fade almost away and back, the fading drifting along them | "haunted … end haunted" |

One emoji is a word, and three are three. Effects nest (`🔥🔥a hot ✨✨glinting✨✨ one🔥🔥`). An effect lifts while the
caret is in its words, so they edit as plain text, and holds still under reduced motion. The spoken cues are adjectives
because the nouns are everyday words: "heat the oven and heat the pan" would otherwise heat "the oven". New effects are
an entry in `src/app/editor/textEffects.ts` and a mark that names it in `src/app/plugins/marks/index.tsx`. They were
checked against the extended syntax above: `^^shout^^` and `^x^`, `~~struck~~` and `~x~`, `++added++` and a list's
`+` marker all parse as themselves.

## What was added, and why

The six gaps the table used to list - wiki links, footnotes, definition lists, emoji, front matter and maths - were
built on 2026-09-16, with superscript, subscript and callouts; embeds came later. What each one had to answer: does it
read as words without the app, can it be said out loud, and does it earn its place on a phone screen.

### Wiki links — `[[Another note]]`

The one that is really a feature rather than formatting: a note that points at another note makes a pile of notes into
something you can walk through, and the syntax is what every notes app already writes. A title that matches a note
opens it. A title that matches nothing is drawn dashed and quiet — a place to go, not a mistake — and tapping it makes
that note with the title as its heading and opens it. Titles match the way a person says them, case and punctuation
aside, so `[[the cabin trip]]` finds "The cabin trip."

Nothing is stored: the link IS the title. Renaming a note is a matter of the words in it.

A `#` in the brackets points inside a note rather than at one, the way Obsidian writes a block reference.
`[[The cabin trip#^friday]]` resolves the title here and hands the anchor to whoever opens it; `[[#^friday]]`, which
has no title at all, is not a wiki link and is left to the anchors' own drawing (`src/app/editor/boards/anchors.ts`).

### Embeds — `![[A canvas]]`

A wiki link with `!` before it, on a line of its own, draws the canvas it names in a frame inside the note, the way
Obsidian embeds one note in another (Matt: "embed a frame of a canvas within another note so we can browse the
canvas from within a frame inside the note"). The frame is the canvas note's own view with no way to change it: pan,
zoom, the minimap, every card drawn as it is on the canvas, the whole of it fitted to the frame to begin with; over
it, the canvas's name and an Open that opens the canvas note. With the caret on the line the frame steps aside and
the line shows as typed. The words are a wiki link like any other, so elsewhere the note reads as a link to the
canvas; a title that names a note of words, or no note, stays the link it is. (`src/app/editor/canvasFrames.ts`)

### Footnotes — `[^sam]` and `[^sam]: what it says`

They used to read as links, which is worse than not supporting them: a link is a promise. The marker is now raised and
quiet the way print sets one, and tapping it shows what the note says, because on a phone the foot of the note is a
long way down and the point of a footnote is not to have to go there. The definition line is set as small print. A
marker with no definition stays plain words — it is a typo, and drawing it as a footnote would hide that.

### Definition lists — `Term` / `: the meaning`

For the glossary note everybody keeps. The term is set apart, the meaning hangs under it, and both degrade to two
readable lines anywhere else.

### Emoji — `:tada:` → 🎉

Parsed already; now drawn. This is the one place besides tables, pictures and clips where the editor replaces what is
written, and it earns it because the drawn thing is unmistakably the written thing. The words come back the moment the
caret is on that line. The list is the hundred-odd names people actually type (`src/app/core/emoji.ts`), GitHub's
spellings; anything else stays as the words that were typed.

### Front matter

A note from Obsidian or a static site opens with `---`, which the editor drew as a horizontal rule — it looked like a
mistake, and worse, the note was called "---" in the list. The block is now drawn as quiet keys in the note's mono
face, and the note takes its name from `title:` where it has one, or from the first words under the fence.

### Maths — `$x^2$`, `$$ … $$`

Set as code, delimiters and all, so it reads as what it is. No renderer: KaTeX is around 280 KB for something a notes
app meets a few times a year. If someone wants it drawn, that is a plugin.

Found by Pandoc's rule (`src/app/core/maths.ts`): an opening `$` has a character that is not a space straight after
it, a closing `$` has one straight before it and no digit after it, and a `$` after a backslash is a dollar. So
`where $n$ is 3` is maths and `It costs $5, or $6 with tax.` is two prices, where the first pattern paired any two
dollars on a line and drew `$5, or $` as code.

### Ghost.md's own: tags, counters, sums, choices, hidden lines, progress

Written in plain characters that read sensibly anywhere; Ghost.md just does more with them. Matt picked the last five
from a list of ideas.

- **Tags — `#web`.** A `#` against a letter, on a list item or anywhere in a line; `#work/clients` nests. Drawn as a
  chip. Not a heading (`# ` has a space), not `#42`, not inside links or code. (`src/app/editor/tags.ts`)
- **Counters — `[3/8]`.** A count and a goal. A tap adds one, a hold takes one away, never past the goal or below
  nothing. Drawn as a chip that fills. Boards and Notion titles leave them out of an item's words.
  (`src/app/editor/counters.ts`)
- **Sums — `= $450 + 120 * 2`.** A line (or list item, or quote) starting `= ` shows its answer after it, `→ $690`,
  never written into the note. Arithmetic only: `+ - * / ^`, brackets, `%` after a number; a currency sign and
  thousands commas carry over. (`src/app/editor/sums.ts`)
- **Blanks — `{?what day / time?}`.** A question in curly brackets with a question mark after the first, where its
  answer belongs (DESIGN §145). The pattern is `/(?<![{\\$])\{\?(?!\?)([^{}|\n]{0,160})\}(?!\})/g`: not `{{?…}}` (the
  templates' family), not after a backslash or a `$` (`${?HOME}`), not `{??`, no `|` in the question, at most 160
  characters, one line. `{?}` asks about the sentence it sits in, or the question just before it. Drawn as a square
  with an icon that says which of four things happens: worked out by the app and drawn after it like a sum (a total,
  a count, days until, a weekday, a conversion, the time in a city, `src/app/core/fillFacts.ts`); Can't work out; a
  live answer looked up by the phone on Fill, or Can't know offline where no public source answers
  (`src/app/core/fillLive.ts`, `src/app/ai/fills/web.ts`); or the model, on Fill. Nothing fills unless pressed.
  A model's answer is written as an Unsure mark whose note says where it came from, which the app hides:
  `??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)`, read back by `FILLED`
  (`src/app/core/blanks.ts`): whose answer, `from memory`, `from this note` or `from` a named source such as
  `Open-Meteo`, the ISO date, what was asked, and `N of M` for one of several items. Other apps show both as the plain
  text they are. A title never holds a mark: a title blank fills as plain words, a question as the whole first line
  stays the title with its answer under it, and every reader of titles, to-dos, the item text sent to Notion and
  GitHub, and search reads a filled answer as its words (`plainFills`). (`src/app/editor/blanks.ts`)
- **Choices — `- ( )` / `- (x)`.** Round boxes on bullets, one picked per group (the choice lines side by side at
  one indent). A tap picks, and clears the rest; tapping the picked one clears it. (`src/app/editor/choices.ts`)
- **Hidden lines — `>| the answer`.** A quote whose first character is a bar goes to smoke, like `||this||`, until
  the caret is in it; a run of them clears together. Part of the spoiler, so part of the Marks plugin: with it off,
  it's a quote.
  (`src/app/editor/wispFormat.ts`)
- **Progress under a heading.** Nothing to type: a heading with to-dos under it says "3 of 7", or "All 7 done",
  counting its subsections too. (`src/app/editor/headingProgress.ts`)
- **Link cards.** A line that is only a link (bare, `<bare>`, or `[words](address)`, in a list or not) gets a card
  under it with the page's title, site and summary; a tap opens it. The title is read by the app (`link_preview`,
  native generation 17) for a card on screen, cached for a week, and never with Link previews off (Settings › Account › Privacy) or
  Local only on (the same card). Links a plugin reads keep their own rows. (`src/app/editor/linkCards.ts`)
- **The bookmark — `§§`.** Two section signs at the end of the bookmarked line's words (before a list item's mark,
  counters and anchor), one per note. The note opens there; the header's bookmark button moves it to the line being
  read, or takes it off that line. Drawn as a small ribbon. (`src/app/editor/bookmarkLine.ts`)
- **Tapping a box.** `- [ ]` and `- [x]` tick and clear on a tap of the box itself. (`src/app/editor/taskToggle.ts`)
- **Fields on a to-do — `- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03`.** Added 2026-09-30 (DESIGN §156, §159).
  Obsidian Tasks' own signs, so the line is a task with a due date there too: `📅` due, `🛫` start, `⏳` scheduled,
  `✅` done, `➕` created and `❌` cancelled, each followed by an ISO day; `🔺 ⏫ 🔼 🔽 ⏬` for highest to lowest
  priority; `🔁` and a rule in words for a repeat, kept and not yet acted on; Tasks' `🆔`, `⛔` and `🏁` read and kept.
  A person is `@sam` (an at sign after a space or an opening bracket, then a letter; not an address, `@2pm` or a
  redaction's `@@`), `@sam-ortiz` for two words. Anything else is Dataview's `[key:: value]`, and Dataview's own
  `[due:: 2026-10-03]` stands for the date where there is no `📅`. Read anywhere in a line's words but code, an
  address, a note link's title, maths, HTML, a redaction and the front matter (`src/app/core/taskFields.ts`). Off the
  caret's line each is drawn as a chip: the due day as **Today**, **Tomorrow** or **Sat 3 Oct** (the device's own
  language, the year only when it is not this one), red once it has passed and the box is not ticked, amber on the
  day, quiet once ticked; the other days quieter with their word, **Starts tomorrow**; a priority as Jira's chevrons
  with its name for a screen reader; a person with their initial in a ring; a repeat with its mark; a named field with
  its key quiet. On the caret's line the characters are there to edit (`src/app/editor/taskFields.ts`,
  `src/app/editor/fieldChips.ts`). A tap on a due, start or scheduled day opens press and hold's band on Today,
  Tomorrow, Next week (its Monday), Pick a date (the phone's own date picker) and Remove; on a priority, the five and
  None; on a person, Remove. Press and hold on any list item offers **Due date**, **Priority** and **Assign** (the
  people the note names, and Someone new) beside its other actions (`src/app/editor/FieldItems.tsx`). The app writes
  a field where Tasks reads it: Tasks' signs in a run at the end of the words in Tasks' order, a person or a named
  field before that run, all before the bookmark, the mark, a counter and the anchor. A to-do's words leave its fields
  out wherever they are its title: a task sent to Notion or an issue to GitHub, a board card (which shows the due day,
  the priority and the people as chips of its own), the home page's To do, and progress under a heading, which counts
  no box that has only fields after it. Search finds a priority by its name, "high priority". Another app shows the
  signs as written, and Obsidian with the Tasks plugin reads the dates and priorities.
- **Places — `[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)`.** A plain link to a `geo:` address (RFC 5870), alone on
  its line, with or without a list's or a quote's lead: what the + beside the line writes for A place. The map card is
  drawn under it, live on the note screen (tiles only with the map switch on and Local only off), quiet until asked on
  a shared page, and not at all on a note drawn small or a notebook read straight through. Off the caret's line the
  `[` and the `](geo:…)` fold away and the name reads alone, but in fenced code. Four decimals, or two for a rough
  fix, which reads back as rough. The words are the place's name, or the coordinates when no name came. A share leaves
  every `geo:` address out unless "Share the places in it" is ticked (docs/SHARING.md). Another app shows a link;
  Obsidian's Map View reads inline places only in a note whose own front matter has `locations:`, which a Ghost.md
  note never has, so there too it is a link. (`src/app/core/placeRefs.ts`, `src/app/editor/placeCards.ts`)
- **Films — `[![video 0:12](image/<poster>.jpg)](video/<name>.mp4)`.** A poster picture linked to its film, alone on
  its line, with or without a list's or a quote's lead: what the + beside the line writes for A video, on an Android
  phone from native generation 21. The alt is "video" and the length, as a voice memo's is. The poster is an ordinary
  picture under `image/`, so sync, a share and the reader's download carry it; the film is under `video/`, which no
  picture's pattern reads, and it stays on the phone it was added on. The card under the line is the poster with the
  length at its foot: on the note screen, on the phone that has the film, a tap plays it (a HEAD to the app's `vid`
  scheme first says whether it is there, and "This video isn’t on this phone." when it is not); on another device, a
  shared page or an older binary it is the still, with a sentence for that reader. The picture widget steps aside for
  the line, so the poster is drawn once. A film on the phone that will not play is asked about again, and its card
  says "This video can’t be played on this phone." rather than that it is missing. Off the caret's line the `[![` and
  the `](image/…)](video/…)` fold away and "video 0:12" reads alone, but in fenced code, where the line is the code's
  words. Another app shows the still as a link to a file it does not have: pictures live in the app's own storage,
  outside the library. (`src/app/core/videoRefs.ts`, `src/app/editor/videos.ts`)

### Where an insert goes

What the app puts into a note for you (the + beside the line, press and hold's Add image and Style, a pasted
picture) goes where the file still reads as meant everywhere. Checked with the app's own parser, and with plain GFM
where it is other readers the rule is for (`src/app/editor/inserts.ts`, its tests):

- **A thing drawn on a line of its own** (a picture, a film, a place, a canvas's frame) takes the caret's line when
  that line has no words: blank, or only a list's, a to-do's or a quote's lead. Otherwise it goes on a new line after
  it, and a line is never split. A line that holds a bookmark or an anchor is kept, since taking it would lose them.
  When the line above is a list item, a quote or a table row, a blank line goes first: `- [ ] ` followed by a picture
  was a to-do whose words were the picture, and a picture on the empty line under a table was a row of it. A place, a
  film and a frame, which are links, keep a blank line from a paragraph above too: `Lunch at the harbour` then a place
  is one paragraph in any other reader, "Lunch at the harbour Cais do Sodré, Lisbon". A picture under a paragraph
  stays on the next line, which every reader draws as a picture of its own.
- **A block** (a table, a rule, a fence, a callout, a board) is the same, with a blank line on either side where the
  line there has words. Without the one after, a table took the next line of words as a row. Without the one before,
  `Para` then `---` is a level 2 heading in Obsidian, GitHub and any CommonMark reader, though never in Ghost.md, whose
  parser has no setext headings.
- **Words at the caret** (the date and time, a link to a note) get a space either side where a sentence needs one.
- **A line's lead** (a to-do, a list, a heading, a sum) is written on an empty line, turns an empty item's lead into
  its own keeping the indent, and never rewrites a line of words, which is Style's job.

Each insert is one Undo.

### Deliberately not

- **Setext headings.** Taken out on purpose: `-` under a line promoted it every time a list was started.
- **Raw HTML rendering.** A note is words. HTML is kept as text and never executed.
- **Abbreviations (`*[HTML]: …`).** The mark-note in brackets already covers “what does this mean”, said out loud and
  shown on a tap, without a second syntax for the same idea.

## Saying every mark

Every mark above but tables, pictures, diagrams, HTML, comments and front matter has words for it while recording
(`src/app/capture/markdown.ts`, with its rule families in `src/app/capture/spoken/`), and the guide's marks page shows
them beside each row (`src/app/guide/MarksTable.tsx`, from each row's `say` in `src/app/guide/marks.ts`). The cheat
sheet in Settings draws the marks without them. Words that are also everyday words need both halves ("… end link") or
a pause either side ("…, new line, …"), so a sentence that only mentions them stays a sentence; the voice suite
(`voice-tests/suite.json`) holds one of those.

| Mark | Said |
| --- | --- |
| `***both***` | bold italic … end bold italic |
| `^raised^`, `~lowered~` | superscript … end superscript, subscript … end subscript |
| `$x^2 + y$` | maths x squared plus y end maths |
| `[words](https://…)`, `<https://…>` | link our site to attack dot fm end link, link attack dot fm end link |
| `[[Note]]`, `[[#^name]]` | note link … end link, item link … end link |
| ` ^name` | anchor ship page end anchor (moved to the end of its line; a repeat gets `-2`) |
| `§§` | … bookmark this (the last one said wins) |
| `[^1]` and its line | footnote Sam said so end footnote |
| `??words??(why)` | … end unsure, note Sam said so, end note |
| `- [x]` | done task: … ("checked box" is heard for "check box", so it stays an open to-do) |
| `📅`, `⏫`, `@Sam` on an item | … due Friday, … high priority (or urgent), … for Sam (or assigned to Sam), at the end of the item (`src/app/capture/spoken/fields.ts`, days in words `src/app/core/dayWords.ts`) |
| `Term` / `: meaning` | define deposit as what you pay up front |
| `:tada:` | emoji party popper (the shortcode, or a spoken name for it) |
| ```` ``` ```` block | code block in bash … end code block, a line for each sentence, kept whole across pauses |
| two spaces and a break | …, new line, … |
| `>\|`, `= sum`, `[3/8]`, `- ( )`, `#tag`, callouts, headings, lists, quotes, `---` | as the guide's marks page says |

Progress under a heading needs nothing said. A picture has no words: it needs a file, not a sentence. Nor has a place:
it needs a fix, from the + beside the line. Nor has a table:
a recording makes none (docs/DESIGN.md §127), so it is typed with pipes or added from Style › Table. A diagram, HTML,
a comment and front matter are typed.

## Where the code is

- `src/app/editor/language.ts` — the parser: GFM, minus setext, plus the plugins' own delimiters.
- `src/app/editor/glyphHighlight.ts` — inline looks by tag; `src/app/editor/glyphLines.ts` — everything that belongs
  to a line.
- `src/app/editor/extended.ts` — superscript and subscript, callouts, definition lists, front matter, maths set as
  code, and emoji shortcodes.
- `src/app/editor/canvasFrames.ts` — `![[A canvas]]` on its own line, drawn as that canvas in a browsable frame.
- `src/app/core/placeRefs.ts` — a place line read and written, and every `geo:` form taken out for a share;
  `src/app/editor/placeCards.ts` — its map card and its fold.
- `src/app/core/videoRefs.ts` — a film's line read and written; `src/app/core/videos.ts` — its pick, where it plays
  from, and whether it is on this phone; `src/app/editor/videos.ts` — its card, full screen, and its fold.
- `src/app/editor/inserts.ts` — where an insert goes, above.
- `src/app/editor/markNotes.ts` — a note in brackets after a mark, and the panel a tap opens.
- `src/app/core/taskFields.ts` — a to-do's fields read and written; `src/app/editor/taskFields.ts` and
  `src/app/editor/fieldChips.ts` — their chips; `src/app/editor/fieldMenu.ts` and `src/app/editor/FieldItems.tsx` — what a
  tap and press and hold do with them; `src/app/capture/spoken/fields.ts` — saying them.
- `src/app/guide/marks.ts` — the rows of the guide's marks page and the cheat sheet, read from the same place the
  editor reads its marks.
