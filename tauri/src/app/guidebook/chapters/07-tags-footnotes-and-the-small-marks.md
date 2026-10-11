# Tags, footnotes and the small marks

_The extras Ghost.md does more with, each written in plain characters that read sensibly in any other app._

Apart from the hidden line, which belongs to the Marks plugin, none of these needs a plugin, and none of them hides anything from another app. Opened anywhere else, a counter is still `[3/8]` and a sum is still a sum. Ghost.md just draws more of them.

## All of them at once

| Mark | Type | Say while recording |
|---|---|---|
| A tag | `#web`, or `#work/clients` | "hashtag web" |
| A footnote | `four hundred[^sam]`, and a line `[^sam]: Sam said so.` | "footnote Sam said so end footnote" |
| A comment | `the ==venue==[^c1]`, and its thread in a ` ```comments ` block at the end | Nothing |
| A definition | `Deposit`, then on the next line `: what you pay up front` | "define deposit as what you pay up front" |
| A counter | `- Water [3/8]` | "counter three of eight" |
| A sum | `= $450 + 120 * 2` | "calculate: four hundred plus one hundred twenty" |
| A choice | `- ( ) Tent`, and `- (x) Cabin` for the one picked | "option: tent", "picked option: cabin" |
| A hidden line | `>\| The answer is forty-two.` | "hidden line: the answer is forty-two" |
| The bookmark | `§§` at the end of a line's words | "… bookmark this" |
| Progress | Nothing | Nothing |

## Tags

A `#` straight against a letter, then letters, digits, `_`, `-` or `/`: `#web`, `#launch`, `#work/clients`. A tag is drawn as a small quiet chip with its `#` kept, and it can sit anywhere in a line, a list item included: `- [ ] Ship the pricing page #web #launch`.

Not a tag: `# ` with a space after it, which is a heading; `#42`, which starts with a digit; and a `#` inside a word, a link, code or maths. On a list item linked to Notion or GitHub, the tags go with the words, before the item's mark and its name.

Searching All notes for `#web` finds every note that carries it, and any with those letters in a longer word, such as `#website`.

## Footnotes

A marker where the small print belongs, and a line anywhere below saying what it is:

```
The deposit is four hundred[^sam], not four fifty.

[^sam]: Sam said so on the phone. The email disagrees.
```

The marker is raised and quiet, the way print sets one, and a tap on it shows what the footnote says, so you never have to scroll to the foot of the note. The line itself is set as small print. A marker with no line to go with it stays plain, because it is a typo, and drawing it as a footnote would hide that.

Said while recording, "footnote Sam said so end footnote" leaves a numbered marker where you said it and writes its words under the note.

## Comments

A comment is kept in the note's own words, so it travels wherever the note does. Select some words, or put the caret on a line, and press **Comment**: on the menu a press and hold (or a right-click) opens over the words, in the bar beside Version history, or in More. A note's right-click menu in a list has **Add a comment** too, which opens the note with a comment started on its first line.

What it writes is a mark after the words, `[^c1]`, or round the words you selected, `==the venue==[^c1]`, and one block at the end of the note that holds every thread:

````
The ==venue==[^c1] is booked.

```comments
c1 matt 2026-10-04T19:00:12Z
The venue needs confirming - the hall or the barn?
  sam 2026-10-04T19:05:40Z
  The hall. Confirmed this morning.
  resolved sam 2026-10-04T19:06:02Z
```
````

Each comment is its id, who wrote it and when, then its words, which may run over several lines; a reply is the same, indented two spaces under it; `resolved` with a name and a time closes the thread. In the note the mark is a small round in the writer's colour, the selected words are washed in it, and the block is drawn as the list of threads. A tap on the round, or on a thread in the list, opens its card, to reply, resolve or reopen it, or delete it. A resolved thread keeps its words and loses its wash, and its round becomes a ring.

In an organization's workspace each person's colour is the one they chose there; anywhere else comments are in ink. Opened in another app, the mark reads as a footnote's and the block as lines of text. A line in the block that starts with a backslash had one put there so it would not read as a new comment.

## Definitions

For the glossary note everybody keeps: the term on one line, and the meaning on the next after a colon and a space.

```
Deposit
: what you pay up front
```

The term is set apart, the meaning hangs under it, and anywhere else it is two readable lines. Said: "define deposit as what you pay up front", with a term of up to three words.

## Counters

A count and a goal in square brackets, anywhere in a line: `- Water [3/8]`, `- Push-ups [0/50]`. It is drawn as a small chip that fills as the count rises. A tap adds one, and a press and hold takes one away. It never goes below nothing, and a full counter stays full. Each change is an ordinary edit, with its own undo. A board and a Notion task leave the counter out of an item's words.

## Sums

A line that starts with `=` and a space works itself out:

```
= 450 + 120 * 2
- = $1,200 / 3
```

The answer, `→ 690` and `→ $400`, is drawn after the line in quiet ink, and it is never written into the note, so a changed number is answered at once. A list item or a quote can be a sum too. It is arithmetic only: numbers, `+`, `-`, `*` and `/`, `^` for a power, `%` after a number for a percent, and brackets. A currency sign, the dollar, euro, pound, yen or rupee, and thousands commas come back on the answer. Anything else, a word or a sum that cannot be done, draws nothing.

Said: "calculate", "sum" or "add up", then the numbers, with plus, minus, times or divided by.

## Choices

Round boxes on list items, of which one is picked:

```
Where do we stay?
- ( ) Tent
- (x) Cabin
- ( ) Hotel
```

A tap on a round box picks that item and clears the others in its group, which is the choice lines side by side at the same indent. Tap the picked one again and it is cleared, so nothing has to stay picked. Said: "option: tent" for each, and "picked option: cabin" for the one you chose.

## Hidden lines

A quote whose first character is a bar, `>| The answer is forty-two.`, goes to smoke like a spoiler until you put the caret in it. A run of such lines clears together. It belongs with the spoiler, so with the Marks plugin off it is an ordinary quote. Said: "hidden line", then the words.

## The bookmark

Two section signs at the end of a line's words, `the deposit is four hundred §§`, mark where the note opens. A note has one: putting it on a line takes it off every other. It is drawn as a small ribbon, with a line down the edge of the bookmarked line so you can see it as you scroll past. On a list item it goes before the item's mark, counters and name.

You rarely type it. The bookmark button in the note's tools puts it on the line you are reading or writing, which is the caret's line, or else the line at the top of the page. Pressed on the line that already has it, it takes it off. Said: "bookmark this", or "bookmark here", at the end of a line; the last one said wins.

## Progress under a heading

Nothing to type. A heading with to-dos under it says how far they have got, after its words: "3 of 7", or "All 7 done" when every box is ticked. It counts down to the next heading of the same size or larger, so a `##` counts the `###` sections inside it too. A heading with no to-dos under it says nothing.

## Read next

- [[Lists and to-dos]]
- [[Saying the marks]]
- [[Boards made of list items]]
