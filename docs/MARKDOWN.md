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
| Emoji `:tada:`             | yes    | yes   | Drawn as the emoji; the words come back while the caret is on the line. A name Glyph doesn't know stays as words |
| Footnotes `[^1]`           | yes    | yes   | The marker raised and quiet, what it says on a tap; the definition set as small print. A marker with no definition stays plain, because it is a typo |
| Definition lists           | yes    | yes   | `Term` then `: the meaning`; the term set apart, the meaning hanging under it |
| Front matter               | yes    | yes   | Drawn as quiet keys rather than a rule, and the note is named by its `title:` |
| Math `$x$`, `$$x$$`        | yes    | yes   | Set as code, delimiters and all. No renderer: KaTeX is ~280 KB the phone doesn't need |
| Wiki links `[[Note]]`      | yes    | yes   | Opens that note; a title with no note is drawn dashed, and tapping it makes the note and opens it. `[[Note#^anchor]]` splits on the first `#`; `[[#^anchor]]` is a place in this note and belongs to `editor/boards.ts` |

Glyph's own marks are on top of that, each from the Marks plugin and switched off with it: `||spoiler||`,
`==highlight==`, `%%aside%%`, `??unsure??`, `^^shout^^`, `++added++`, and a note on any of them in brackets —
`??four hundred??(Sam said 400)`. They were checked against the extended syntax above: `^^shout^^` and `^x^`,
`~~struck~~` and `~x~`, `++added++` and a list's `+` marker all parse as themselves.

## What was added, and why

All six of the gaps above were built on 2026-09-16. What each one had to answer: does it read as words without Glyph,
can it be said out loud, and does it earn its place on a phone screen.

### Wiki links — `[[Another note]]`

The one that is really a feature rather than formatting: a note that points at another note makes a pile of notes into
something you can walk through, and the syntax is what every notes app already writes. A title that matches a note
opens it. A title that matches nothing is drawn dashed and quiet — a place to go, not a mistake — and tapping it makes
that note with the title as its heading and opens it. Titles match the way a person says them, case and punctuation
aside, so `[[the cabin trip]]` finds "The cabin trip."

Nothing is stored: the link IS the title. Renaming a note is a matter of the words in it.

A `#` in the brackets points inside a note rather than at one, the way Obsidian writes a block reference.
`[[The cabin trip#^friday]]` resolves the title here and hands the anchor to whoever opens it; `[[#^friday]]`, which
has no title at all, is not a wiki link and is left to the board's own drawing (`editor/boards.ts`).

### Footnotes — `[^sam]` and `[^sam]: what it says`

They used to read as links, which is worse than not supporting them: a link is a promise. The marker is now raised and
quiet the way print sets one, and tapping it shows what the note says, because on a phone the foot of the note is a
long way down and the point of a footnote is not to have to go there. The definition line is set as small print. A
marker with no definition stays plain words — it is a typo, and drawing it as a footnote would hide that.

### Definition lists — `Term` / `: the meaning`

For the glossary note everybody keeps. The term is set apart, the meaning hangs under it, and both degrade to two
readable lines anywhere else.

### Emoji — `:tada:` → 🎉

Parsed already; now drawn. This is the one place besides tables, pictures and clips where Glyph replaces what is
written, and it earns it because the drawn thing is unmistakably the written thing. The words come back the moment the
caret is on that line. The list is the hundred-odd names people actually type (`core/emoji.ts`), GitHub's spellings;
anything else stays as the words that were typed.

### Front matter

A note from Obsidian or a static site opens with `---`, which Glyph drew as a horizontal rule — it looked like a
mistake, and worse, the note was called "---" in the list. The block is now drawn as quiet keys in the note's mono
face, and the note takes its name from `title:` where it has one, or from the first words under the fence.

### Maths — `$x^2$`, `$$ … $$`

Set as code, delimiters and all, so it reads as what it is. No renderer: KaTeX is around 280 KB for something a notes
app meets a few times a year. If someone wants it drawn, that is a plugin.

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
