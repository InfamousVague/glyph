import { howCanvas, HOW_TITLE } from '../app/canvas/howCanvas.ts';
import { canvasNoteBody } from '../app/canvas/jsonCanvas.ts';
import { imageMarkdown } from '../app/core/imageRefs.ts';

/**
 * Examples as an earlier Ghost.md made them, for the tests that hold the renewers to them (core/sampleNote.ts
 * `renewedSample`, canvas/howCanvas.ts `renewedHowCanvas`): a copy of one that nobody has changed is what Ghost.md:
 * The Guide brings up to date before it teaches from it (guide/theGuide/book.ts). Only ever read by tests.
 */

/**
 * The sample note as the two versions before 2026-09-25 made it (core/sampleNote.ts at 688ee24 and b468cc0), word for
 * word: never change a word of it. The two differ in one line, the table command, said "Ghost, add a table…" and then
 * "Hey Ghost, add a table…". The body with the picture line when there is a picture, and the table command as said.
 */
export function pastSampleBody(image: string | null, said: 'Ghost' | 'Hey Ghost'): string {
  const picture = image
    ? `## Pictures

Paste one, or press and hold and choose Add image. It sits under its own line, and the line stays:

${imageMarkdown(image, 'A wisp of smoke, by Jocelyn Morales')}

`
    : '';
  return `# How to format a note

A note is plain Markdown: words with a few marks around them. Type a mark, or say its word while recording, and Ghost.md draws it. The marks stay on the page, a little dimmed. Try each one here, then delete this note.

## Headings

Type \`#\` and a space for the note's name, \`##\` for a section, and more hashes, up to six, for smaller ones. Say "heading", or "subheading".

### Three hashes

#### Four

##### Five

###### Six

## Words

Two stars for **bold**, underscores for _italic_, three stars for ***both***, two tildes to ~~strike~~, and backticks for \`code\`. Say "bold", then "end bold"; italic works the same way. A backslash makes a mark mean itself: \\*not italic\\*.

Two pipes each side keep a secret, drawn as smoke until the caret is in it: ||the key is under the third stone||.

## Ghost.md's own marks

Two of the same sign each side: ==highlight==, %%an aside%%, ??unsure?? (with a reason in brackets after it: ??the deposit??(ask Sam)), ^^shout^^, and ++added++. Say "highlight", then "end highlight"; the others work the same way.

## Lists

A dash for a point, indented for a smaller one. Say "bullet point".

- Milk
  - Oat, if they have it

A number and a dot for steps. Say "number one", "number two".

1. Wake up
2. Write it down

A dash and a box for a to-do; tap the box to tick it. Say "remember to".

- [ ] Book the cabin
- [x] Call Sam

## Quotes

A line that starts with \`>\`. Say "quote".

> The note you make on the way is the one you keep.

## Links

Words in brackets and the address after: [Ghost.md](https://attack.fm/glyph). An address on its own line gets a card with the page's title:

https://attack.fm/glyph

## Tables

Pipes between cells and a row of dashes under the first. Or say "${said}, add a table to this note" and answer its questions. Tap a drawn table to change it.

| What | Where |
| :--- | ---: |
| Tent | Garage |
| Stove | Loft |

## Code

Three backticks above and below, with the language after the first three:

\`\`\`js
const note = 'said, then written';
\`\`\`

## A line across

Three dashes on a line of their own:

---

${picture}## Without typing

Press and hold on any words and choose Style to put one of these marks on them.
`;
}

/**
 * The canvas that says how Ghost.md works, as it was made before 2026-09-25: the same canvas but for two cards, which
 * said "Tap Speak" and named list, done and table as marks to say. Made from today's canvas, so a change to any other
 * card changes this too and the test of `renewedHowCanvas` fails: an edit to the canvas makes today's a past one, whose
 * body the renewer has to know as well.
 */
export function pastHowCanvasBody(): string {
  const then: Record<string, string> = {
    speak: '# Say it\n\nTap **Speak**, or press the side key, and talk. Ghost.md writes the words as you say them.',
    marks: '# Say the marks too\n\nSay *heading*, *list*, *done* or *table*, and Ghost.md draws them. No menus.',
  };
  const canvas = howCanvas();
  return canvasNoteBody(HOW_TITLE, { ...canvas, nodes: canvas.nodes.map((node) => (node.id in then ? { ...node, text: then[node.id]! } : node)) });
}
