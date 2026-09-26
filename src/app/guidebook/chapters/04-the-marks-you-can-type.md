# The marks you can type

_The Markdown Ghost.md reads and draws, the six marks it adds of its own, and the two ways to look at a note._

A note is words with a few marks around them. Ghost.md draws each mark as you type it and leaves the mark on the page, dimmed, so you can always see what a line is doing. The standard marks read the same in GitHub, Obsidian or a plain text editor. Ghost.md's own read there as the plain characters they are, and anything Ghost.md does not draw still reads as words.

## Around words

Type the mark on both sides of the words it is for.

- `**Friday at noon**` is **bold**.
- `_a quiet aside_`, or `*a quiet aside*`, is _italic_.
- `***really now***` is ***both***.
- `~~the old plan~~` is ~~struck through~~, and still readable.
- `` `npm run dev` `` is `code`: the typewriter face, kept exactly as typed.
- `the 2^nd^ of June` raises "nd", and `H~2~O` lowers the 2.
- `[Ghost.md](https://attack.fm/glyph)` is a link: the words, with the address shown short ([[Links between notes]]).
- `$x^2 + y$` is maths, set as code, dollar signs and all, and so is `$$x^2 + y$$` within one line.
- `:tada:` is drawn as the party popper emoji.

A backslash makes a mark mean itself: `\*not italic\*` keeps its stars.

Ghost.md knows about a hundred and fifty emoji names, spelled the way GitHub spells them. One it knows is drawn as its emoji, and the name comes back whenever the caret is on its line. One it does not know stays as the words you typed.

Maths is set as code rather than drawn as a formula: a maths renderer is a large thing for a phone to carry for something a notes app meets rarely.

## At the start of a line

| Mark | Type | Looks like |
|---|---|---|
| Headings | `# Weekend trip`, `## The budget`, and on to six | Six sizes. The first line of a note is its name. |
| A list | `- Oat milk` | A bullet. Enter starts the next one, and Backspace takes a marker off whole. |
| Steps in order | `1. Unplug it` | Numbered |
| A to-do | `- [ ] Book the cabin`, or `- [x] Call Sam` | A box, ticked with a tap |
| A quote | `> The deposit comes back in full.` | Set apart. Two of them, `> >`, put a quote inside a quote. |
| A callout | `> [!NOTE]` on the first line of a quote | The quote set apart as a note, its kind named small at the top: NOTE, TIP, IMPORTANT, WARNING or CAUTION, the last two a shade darker |
| A dividing line | `---` on a line of its own | A rule across the page |
| A line break | Two spaces at the end of a line | Nothing changes here, since in Ghost.md every line already starts under the last. Other Markdown apps join lines into one paragraph, and the two spaces keep the break there. Saying "new line" writes them. |

To-dos have a chapter of their own: [[Lists and to-dos]].

## Blocks

| Mark | Type | Looks like |
|---|---|---|
| A table | Pipes between the cells, and a row of dashes under the first row | A real table. Tap it to edit its pipes. A colon at the left or right of a column's dashes lines that column up to that side, and one at each end centres it. |
| A block of code | Three backticks on a line above and below, with the language after the first three | Coloured as that language. With no language, the plain typewriter face. |
| A diagram | A block of code whose language is mermaid | The diagram it describes. Tap it to edit its text. |
| A definition | `Deposit`, then on the next line `: what you pay up front` | The term set apart, and the meaning hanging under it |
| Front matter | `key: value` lines between two `---` lines, at the very top | Quiet keys. A `title:` among them names the note. |

Here are the first two written out:

````
| What  | Where  |
| :---- | -----: |
| Tent  | Garage |

```js
const note = 'said, then written';
```
````

A picture is `![caption](image/…)` on a line of its own, drawn under that line: [[Pictures and voice memos]].

A diagram uses Mermaid, with every kind of diagram it knows. It is loaded the first time a note has one, and it came with the app, so it draws offline. A diagram that cannot be drawn stays as its own text, with a line saying why.

## What it leaves alone, on purpose

- **A line of dashes or equals signs under a paragraph** does not make the paragraph a heading, as it does in some Markdown. On a phone that rule turned the line above into a heading every time a list was started under it. Here `#` is the only way to a heading, a lone `-` is an empty list item, and `---` is a rule.
- **HTML** is kept as text and never runs. A note is words. A `<!-- comment -->` is words too.

## Ghost.md's own six

These come from the **Marks** plugin, which is on unless you switch it off in Settings › Plugins.

| Mark | Type | Looks like |
|---|---|---|
| Spoiler | `\|\|the key is under the third stone\|\|` | Smoke, until you put the caret in it |
| Highlight | `==the cabin key==` | A wash of blue behind the words |
| Aside | `%%a note to yourself%%` | Smaller, quieter, leaning |
| Unsure | `??four hundred??` | A dotted line under a fact to check |
| Shout | `^^the gate sticks^^` | Spaced small capitals |
| Added | `++and the dog++` | A line under what was added |

Here they are at work: ||the key is under the third stone||, ==the cabin key==, %%a note to yourself%%, ??four hundred??, ^^the gate sticks^^, and ++and the dog++.

**A highlight in a colour.** Put a colour's name in brackets straight after it: `==the cabin key==(green)`. The names are blue, red, amber, green, teal, purple and gray, spelled that way because it is the colour's name in the app's design kit. A name Ghost.md does not know leaves the plain highlight, and the brackets become a note.

**A note on a mark.** Brackets straight after any of these marks hold a note: `??four hundred??(Sam said 400)`. The brackets are hidden, so the line reads as a sentence, and tapping the words shows the note: ??four hundred??(Sam said 400). With the caret in them, they come back as plain text to edit.

Every one of these is plain characters in another app, and still says what was meant: `??four hundred??(Sam said 400)` is a doubt with its reason. With the Marks plugin off, Ghost.md shows them as plain characters too.

## Two ways to see a note

The first round button in a note's tools switches between them.

- **Markdown**, with the code icon, is the view Ghost.md starts in: the words formatted, and the marks still on the page, dimmed.
- **Formatted**, with the open book icon, hides the marks that only say how words look: stars, underscores, tildes, backticks, a heading's `#`, a quote's `>`, and Ghost.md's own. While you write, the line the caret is on shows its marks so you can edit them. A list's dash and a to-do's box always stay, since they are part of how a list looks.

The choice holds for every note. On a narrow screen, such as a folded phone, the note's More sheet has the switch as well, under Reading it › Show. In the command palette it is "Show it formatted" and "Show the marks".

## Without typing a mark

Press and hold on some words, or right-click on a Mac, and choose **Style**. The menu turns over to a band you can scroll sideways: Bold, Italic, Struck and Code; then each of Ghost.md's own marks and effects; then what a line can be, Heading, Quote, List, Numbered and To-do; then what can be put in, Link, Table and Rule. A style that applies is lit. Press it again to take it off, or press several in one go. The arrow goes back.

## And the rest

The five moving effects are [[Effects on words]]. Tags, footnotes, counters, sums, choices, hidden lines, the bookmark and progress under a heading are [[Tags, footnotes and the small marks]]. How to say every mark while recording is [[Saying the marks]]. Every mark is on the cheat sheet, in Settings › Cheat sheet.

## Read next

- [[Effects on words]]
- [[Tags, footnotes and the small marks]]
- [[Saying the marks]]
