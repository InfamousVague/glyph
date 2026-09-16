# The markdown Glyph speaks

What the editor parses and draws today, measured rather than assumed, and what is worth adding next. The rule behind
all of it: **a note is a markdown file**. Anything Glyph draws must read the same in GitHub, Obsidian or a plain text
editor, and anything it cannot draw must still be readable as words.

## What is supported

Measured by parsing each sample with the app's own language (`editor/language.ts`) and reading the syntax tree.

| Syntax                    | Parsed | Drawn | Notes                                                       |
| ------------------------- | ------ | ----- | ----------------------------------------------------------- |
| Headings `#`–`######`      | yes    | yes   | Setext (`---` under a line) is deliberately off: on a phone it promoted a paragraph every time a list was started below it |
| Bold, italic, both         | yes    | yes   |                                                             |
| Strikethrough `~~`         | yes    | yes   | GFM                                                         |
| Inline code, fenced code   | yes    | yes   | A fence with a language is highlighted in it; the block is drawn as one card |
| Lists, ordered lists       | yes    | yes   | Wrapped lines hang off the marker, measured in the real face |
| Task lists `- [ ]`         | yes    | yes   | GFM. Ticking one syncs to a linked task (`editor/doneSync.ts`) |
| Blockquotes, nested        | yes    | yes   |                                                             |
| Tables                     | yes    | yes   | GFM. Drawn as a table, the fence still editable             |
| Links, reference links      | yes    | yes   | A long URL is shown short (`editor/links.ts`)               |
| Autolinks (bare and `< >`) | yes    | yes   | GFM                                                         |
| Images `![]()`             | yes    | yes   | Drawn under their line                                      |
| Hard line breaks            | yes    | yes   | Two spaces at the end of a line                             |
| HTML blocks and tags       | yes    | as text | Never executed; a note is words                            |
| Comments `<!-- -->`        | yes    | as text |                                                            |
| Horizontal rules `---`     | yes    | yes   |                                                             |
| Superscript `^x^`          | yes    | yes   | Added 2026-09-16; was parsed and drawn as plain words        |
| Subscript `~x~`            | yes    | yes   | Added 2026-09-16                                            |
| Callouts `> [!NOTE]`       | as a quote | yes | Added 2026-09-16. NOTE, TIP, IMPORTANT, WARNING, CAUTION    |
| Emoji `:tada:`             | yes    | as text | Parsed as an `Emoji` node; left as the words that were typed |
| Footnotes `[^1]`           | no     | as a link | Reads as a link label, which is wrong. See below           |
| Definition lists           | no     | as text |                                                            |
| Front matter               | no     | as a rule | The opening `---` becomes a horizontal rule                |
| Math `$x$`, `$$x$$`        | no     | as text |                                                            |
| Wiki links `[[Note]]`      | no     | as text |                                                            |

Glyph's own marks are on top of that, each from the Marks plugin and switched off with it: `||spoiler||`,
`==highlight==`, `%%aside%%`, `??unsure??`, `^^shout^^`, `++added++`, and a note on any of them in brackets —
`??four hundred??(Sam said 400)`. They were checked against the extended syntax above: `^^shout^^` and `^x^`,
`~~struck~~` and `~x~`, `++added++` and a list's `+` marker all parse as themselves.

## What is worth adding, and why

Ordered by what a voice-first notes app actually gains. Each one has to answer three questions: does it read as words
without Glyph, can it be said out loud, and does it earn its place on a phone screen.

### 1. Wiki links between notes — `[[Another note]]`

The biggest one, and not really formatting: it is the feature Glyph is missing. A note that can point at another note
makes a pile of notes into something you can navigate, and the syntax is already what Obsidian and every other notes
app writes. Said: “link to *the cabin trip*”. Tapping it opens that note; a name with no note offers to make it.

Cost: resolving a title to a note, a way to show an unresolved link, and navigation. Worth doing properly rather than
cheaply.

### 2. Footnotes — `[^1]` and `[^1]: the source`

Already common in extended markdown, and today they read as links, which is actively wrong. A phone screen is the
place where a reference belongs at the bottom rather than inline. Drawn: the marker raised and quiet, tapping it
showing the note the way a mark's own note does (`editor/markNotes.ts` already has the panel).

Small, correct, and it removes a wrong reading. This is the one I would do next.

### 3. Definition lists — `Term` / `: the meaning`

For a glossary note, which is exactly the note people keep. Cheap to parse, easy to draw as a hanging indent, and it
degrades to two readable lines. Said: “define *deposit* as …”.

### 4. Emoji shortcodes drawn as emoji — `:tada:` → 🎉

Parsed already. Drawing it means replacing the words, which Glyph only does where the thing drawn is unmistakably the
same thing (a table, a picture, a board). An emoji qualifies. Wants a name table, which is weight; a short list of the
hundred people actually type would cover it.

### 5. Front matter

Obsidian and every static site write YAML at the top of a note, and Glyph turns the opening `---` into a horizontal
rule, which looks like a mistake. Drawing it as a quiet block of keys, or at least not as a rule, would make notes
from other tools open cleanly. No voice cue; nobody dictates front matter.

### 6. Math — `$x^2$`

Only with a renderer (KaTeX is ~280 KB), and the app is on-device and small. Parse it so it does not read as
punctuation, draw it as code, and leave rendering until someone asks.

### Deliberately not

- **Setext headings.** Taken out on purpose: `-` under a line promoted it every time a list was started.
- **Raw HTML rendering.** A note is words. HTML is kept as text and never executed.
- **Abbreviations (`*[HTML]: …`).** The mark-note in brackets already covers “what does this mean”, said out loud and
  shown on a tap, without a second syntax for the same idea.

## Where the code is

- `editor/language.ts` — the parser: GFM, minus setext, plus the plugins' own delimiters.
- `editor/glyphHighlight.ts` — inline looks by tag; `editor/glyphLines.ts` — everything that belongs to a line.
- `editor/extended.ts` — superscript, subscript and callouts.
- `editor/markNotes.ts` — a note in brackets after a mark, and the panel a tap opens.
- `guide/marks.ts` — the cheat sheet's rows, read from the same place the editor reads its marks.
