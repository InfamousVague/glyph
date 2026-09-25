import { imageMarkdown } from './images.ts';
import smokeUrl from '../assets/sample-smoke.jpg';

/**
 * The sample note: a short tutorial for formatting everything, one mark at a
 * time - how to type it, how to say it, and one example (Matt: "replace the
 * 'everything a note can hold' as a short tutorial for formatting
 * everything"). It took over from the guide's Markdown step, which was taken
 * out. It began as a note with every kind of mark in it ("add a default note
 * with every kind of markdown formatting and table and image and everything
 * we support"), and it still has one of each: the tests hold it to that, the
 * five effects and every row of the cheat sheet (guide/marks.ts) included. A
 * fresh library gets it once (seed.ts), and Settings > About makes another
 * whenever wanted.
 *
 * The words are the note's own explanation of itself, in the app's voice.
 * The cues it teaches are the cheat sheet's `say` words, so the two never
 * teach different things. The marks that would change how the note behaves
 * rather than how it reads - the bookmark, which would open the note half
 * way down, and a canvas in a frame, which needs a canvas - are written in
 * backticks, as words about the mark rather than the mark itself.
 *
 * The picture is a photograph of smoke by Jocelyn Morales, from Unsplash
 * under the Unsplash License (docs/THIRD_PARTY.md), bundled with the app
 * and copied into the library's pictures the way a pasted picture is
 * (core/images.ts), so the note holds a real `![…](image/…)` line and not a
 * special case. (An ink cassette drawn in SVG came first; Matt: "quite ugly".)
 * Where the picture can't be fetched (a test) the note has no picture and
 * says nothing of one.
 */

export const SAMPLE_TITLE = 'How to format a note';

/** The note's body, with the picture line when there is a picture to show. */
export function sampleNoteBody(image: string | null): string {
  const picture = image
    ? `## Pictures

Paste one, or press and hold and choose Add image. It sits under its own line, and the line stays:

${imageMarkdown(image, 'A wisp of smoke, by Jocelyn Morales')}

`
    : '';
  return `# ${SAMPLE_TITLE}

A note is plain Markdown: words with a few marks around them. Type a mark, or say its word while recording, and Ghost.md draws it. The marks stay on the page, a little dimmed. Try each one here, then delete this note.

## Headings

Type \`#\` and a space for the note's name, \`##\` for a section, and more hashes, up to six, for smaller ones. Say "heading", or "subheading".

### Three hashes

#### Four

##### Five

###### Six

## Words

Two stars for **bold**, underscores for _italic_, three stars for ***both***, two tildes to ~~strike~~, and backticks for \`code\`. Say "bold", then "end bold"; italic works the same way. A backslash makes a mark mean itself: \\*not italic\\*.

Two pipes each side keep a secret, drawn as smoke until the caret is in it: ||the key is under the third stone||. Say "spoiler", then "end spoiler".

One caret each side raises part of a word, and one tilde lowers it: the 2^nd^ of June, H~2~O. Say "superscript", then "end superscript"; "subscript" works the same way.

## Ghost.md's own marks

Two of the same sign each side: ==highlight==, %%an aside%%, ??unsure?? (with a reason in brackets after it: ??the deposit??(ask Sam)), ^^shout^^, and ++added++. A colour's name in brackets after a highlight changes its colour: ==the cabin key==(green). Say "highlight", then "end highlight"; the others work the same way.

## Effects

Words that move, each written as its emoji twice either side, so the note still says what it means in any other app. Heat bends the line above it, like air over a hot road:

- 🔥🔥Heat🔥🔥 goes bold, and the line above it wavers.
- ❄️❄️Frost❄️❄️ grows a rime over the edges of the letters.
- 🌊🌊Wave🌊🌊 bobs along the line.
- ✨✨Shimmer✨✨ catches a glint every few seconds.
- 👻👻Haunt👻👻 fades almost away, and back.

Say "heated", then "end heated"; "frosted", "wavy", "shimmering" and "haunted" work the same way. An effect lifts while the caret is in its words, so they edit as plain text, and it holds still when the phone is set to reduce motion.

## Lists

A dash for a point, indented for a smaller one. Say "bullet point".

- Milk
  - Oat, if they have it

A number and a dot for steps. Say "number one", "number two".

1. Wake up
2. Write it down

A dash and a box for a to-do; tap the box to tick it. Say "remember to", or "done task" for one that is done already. The heading above counts them.

- [ ] Book the cabin ^book-cabin
- [x] Call Sam ^call-sam

A caret and a name at the end of an item name it, so something else can point at it: [[#^book-cabin]]. Say "anchor", the name, then "end anchor".

Round brackets make a choice, and a tap picks one. Say "option", or "picked option" for the one you chose.

Where do we stay?
- ( ) Tent
- (x) Cabin

A count and a goal in square brackets is a counter: tap it to add one, hold it to take one away. Say "counter three of eight".

- Water [3/8]

A line that starts with an equals sign shows its answer after it, and never writes it into the note. Say "calculate".

= $450 + 120 * 2

A hash against a word tags the line: #cabin. Say "hashtag", then the word.

## Quotes

A line that starts with \`>\`. Say "quote".

> The note you make on the way is the one you keep.

A quote that opens with \`[!NOTE]\`, \`[!TIP]\`, \`[!IMPORTANT]\`, \`[!WARNING]\` or \`[!CAUTION]\` is a callout. Say "info box", or "warning callout".

> [!TIP]
> Say it now, and fix it after.

A bar straight after the \`>\` keeps the line in smoke until the caret is in it. Say "hidden line".

>| The answer is forty-two.

## Links

Words in brackets and the address after: [Ghost.md](https://attack.fm/glyph). An address on its own line gets a card with the page's title:

https://attack.fm/glyph

Two square brackets each side link to another note by its name: [[Weekend trip]]. A name with no note yet is drawn dashed, and a tap makes that note. Say "note link", the name, then "end link".

A caret and a name in square brackets mark a footnote, and a line starting with the same mark says what it is: the deposit is four hundred[^sam]. Tap the mark to read it. Say "footnote", what it says, then "end footnote".

[^sam]: Sam said so.

Two section signs, \`§§\`, at the end of a line are the note's bookmark, and the note opens there. The bookmark button at the top of the note moves it to the line you are on. Say "bookmark this" at the end of a line.

## Tables

Pipes between cells and a row of dashes under the first. Or press and hold, choose Style, then Table. Tap a drawn table to change it.

| What | Where |
| :--- | ---: |
| Tent | Garage |
| Stove | Loft |

## A few more

A word, and its meaning on the next line after a colon, is a definition. Say "define deposit as what you pay up front".

Deposit
: what you pay up front

Dollar signs each side set maths apart, exactly as typed: $x^2 + y$. Say "maths", the formula, then "end maths".

A name between colons is its emoji: shipped :tada:. Say "emoji", then its name.

## Code

Three backticks above and below, with the language after the first three:

\`\`\`js
const note = 'said, then written';
\`\`\`

## Boards and diagrams

A block marked board lays items out as columns, by their names. These are the to-dos from Lists; tick one there and its card moves here.

\`\`\`board
To do: book-cabin
Done: call-sam
\`\`\`

A block marked mermaid is drawn as the diagram it describes. Tap it to change the words.

\`\`\`mermaid
flowchart LR
  A[Say it] --> B[A note]
\`\`\`

A canvas can sit in a note in a frame you can look around in: its name in \`![[ ]]\`, on a line of its own.

## A line across

Three dashes on a line of their own:

---

${picture}## Without typing

Press and hold on any words and choose Style to put one of these marks on them. Every mark is in the cheat sheet as well: tap the three dots at the top of any note, then Formatting cheat sheet.
`;
}

/** The bundled photograph as a JPEG blob; null where it can't be fetched. */
export async function sampleImageBlob(): Promise<Blob | null> {
  if (typeof fetch !== 'function') return null;
  const response = await fetch(smokeUrl).catch(() => null);
  if (!response?.ok) return null;
  return response.blob();
}
