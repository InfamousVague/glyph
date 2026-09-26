# Saying the marks

_What to say so a spoken note arrives with its headings, lists, to-dos and marks already in place._

## How a cue is heard

Whisper writes your pauses as full stops and commas, and Ghost.md listens for cues at the start of a sentence. Four habits follow from that.

- **Pause before a cue.** A short pause before “heading” or “bullet point” starts a new sentence, which is where cues are heard.
- **Or say the cue on its own.** “Bullet point.” Pause. “Oat milk.” The cue waits for the next thing you say.
- **Say both halves of a mark inside a sentence.** “Bold … end bold”. “A bold move” has no “end bold”, so it stays words.
- **Pause after a cue that is an everyday word.** “Number one, book flights” is a numbered item. “Number one priority is sleep” is a sentence. The comma Whisper writes for your pause is the whole difference, and the same goes for “quote”, “option”, “calculate” and “important”.

Your words stay as you said them: the cues are taken out, and the rest is laid out around them. A cue that is not heard is left as words, and the note is plain Markdown to fix afterwards.

## Naming and sections

| Say | You get |
|---|---|
| “Title: weekend trip.” (or “Call this note …”), said first | `# Weekend trip` |
| “Heading: the budget.” (or “New section”) | `## The budget` |
| “Subheading: the kitchen.” | `### The kitchen` |

A short first sentence, six words or fewer and not a question, becomes the title anyway: “Weekend trip. We leave on Friday.” Said into a note's own Speak, where the note has its name already, “Title: …” makes a `##` heading instead.

## Paragraphs and lines

| Say | You get |
|---|---|
| “New paragraph.”, or stop talking for a little over two seconds | A new paragraph |
| “…, new line, …”, with a pause either side | A line break |
| “Divider.” (or “Horizontal line”), on its own | `---` |

## Lists

| Say | You get |
|---|---|
| “Bullet point: the heating.” “Next point: the water pressure.” | `- The heating` and `- The water pressure` |
| “For the drive we need snacks, water, a charger and the good playlist.” | `For the drive we need:` and four bullets |
| “Number one: passports.” “Number two: chargers.” | `1. Passports` and `2. Chargers` |
| “First, unplug it.” “Then wait a minute.” “Finally, plug it back in.” | A numbered list of three |
| “The next item is oat milk.” | `- Oat milk` |
| “Here is my shopping list.” Then short sentences | Each short sentence a bullet |

A list in one breath needs three things: a word that introduces it (need, want, buy, get, grab, bring, pack, include, like, such as, pick up and a few more), three or more short things of four words at most, and an “and” or “or” before the last. Without them, commas are only commas.

The first sentence of a new note is still read as a possible title. Said first, “First, unplug it.” becomes the title, and the numbered list starts at the next step, so say a sentence or a title before it.

## To-dos, choices and counters

| Say | You get |
|---|---|
| “Check box: call the plumber.” | `- [ ] Call the plumber` |
| “Remember to book the cabin.” (or “I need to”, “Don’t forget to”, “Remind me to”) | `- [ ] Book the cabin` |
| “Done task: pay the deposit.” | `- [x] Pay the deposit` |
| “Option: tent.” “Picked option: cabin.” | `- ( ) Tent` and `- (x) Cabin` |
| “Bullet point: drink water, counter zero of eight.” | `- Drink water [0/8]` |

## Words that stand out

| Say | You get |
|---|---|
| “The deadline is bold Friday at noon end bold.” | `**Friday at noon**` |
| “italic … end italic” | `_…_` |
| “bold italic … end bold italic” | `***…***` |
| “strike … end strike” | `~~…~~` |
| “Important: they need an answer by Monday.” (or “Key point:”) | `**Important:** They need an answer by Monday.` |
| “Quote: the deposit comes back in full.” | `> The deposit comes back in full.` |
| “Info box: the gate sticks.” | A `> [!NOTE]` callout |
| “Warning callout: the step is loose.” (or tip, important, caution) | A `> [!WARNING]` callout |
| “Hidden line: it was the butler.” | A hidden line, kept in smoke until it is tapped |

A hidden line is written as `>` and a bar, then its words. Whisper often hears “end” as “and”, so “and bold” closes a mark too, where it cannot be ordinary speech.

## Inside a sentence

| Say | You get |
|---|---|
| “hashtag travel” | `#travel` |
| “note link weekend trip end link” | A link to your note Weekend trip, in double square brackets, spelled the way the note is |
| “link our site to attack dot fm end link” | `[our site](https://attack.fm)` |
| “link attack dot fm end link” | `<https://attack.fm>` |
| “footnote Sam said so end footnote” | `[^1]`, with the footnote under the note |
| “… bookmark this”, at the end of a line | The note's bookmark, `§§` |
| “define deposit as what you pay up front” | `Deposit` and `: What you pay up front` |
| “emoji party popper” | `:tada:` |
| “anchor ship page end anchor” | `^ship-page`, at the end of its line |
| “item link ship page end link” | A link to the item named `^ship-page` in this note |
| “the 2 superscript nd end superscript” | `the 2^nd^`; “subscript” lowers words the same way |

In an address, say “dot”, “slash”, “colon”, “dash” and “underscore”.

## Code, maths and sums

| Say | You get |
|---|---|
| “code npm run dev end code” | `` `npm run dev` ``, lower case, as a command is typed |
| “Code block in bash.” A sentence for each line. “End code block.” | A fenced block of bash |
| “maths x squared plus y end maths” | `$x^2 + y$` |
| “Calculate: four hundred plus one hundred twenty.” | `= 400 + 120`, with its answer beside it |

A code block can name JavaScript, TypeScript, Python, Rust, Bash, shell, JSON, HTML, CSS, SQL, Swift, Kotlin, YAML, Ruby or Go. Maths knows squared, cubed, equals, square root of, open and close bracket, plus, minus, times, over and divided by.

## Ghost.md's own marks

With the Marks plugin on, as it is unless you switched it off in Settings › Plugins, its marks are said the way bold is.

| Say | You get |
|---|---|
| “highlight … end highlight” | `==…==` |
| “aside … end aside” | `%%…%%` |
| “unsure … end unsure” | `??…??` |
| “shout … end shout” | `^^…^^` |
| “added … end added” | `++…++` |
| “heated … end heated” | `🔥🔥…🔥🔥` |
| “frosted … end frosted” | `❄️❄️…❄️❄️` |
| “wavy … end wavy” | `🌊🌊…🌊🌊` |
| “shimmering … end shimmering” | `✨✨…✨✨` |
| “haunted … end haunted” | `👻👻…👻👻` |

“Spoiler … end spoiler” puts the words between two bars either side, and they go to smoke until the caret is in them.

Straight after a mark, “note Sam said so, end note” adds what the mark means, shown on a tap: `??four hundred??(Sam said so)`. [[Effects on words]] shows what the five effects look like.

## A voice memo

The tips in a pause still offer “Voice memo … end memo”, but in this version the recorder does not act on it. The words “voice memo”, what follows and “end memo” are written down like any others, and no clip is kept. A voice memo already in a note still plays where it sits. [[Pictures and voice memos]] has the rest, and [[Where the docs and the code disagree]] lists this among the promises the recorder does not keep yet.

## What has no cue

There is no spoken cue for a table, a picture, a diagram or a board. The cheat sheet's table of marks offers “Hey Ghost, add a table to this note” and “Hey Ghost, make this a board”, but a finished recording carries out neither; [[Commands after Hey Ghost]] says what happens to them. Type those afterwards.

## Read next

- [[Commands after Hey Ghost]]
- [[The marks you can type]]
- [[Effects on words]]
