import { withoutAnchor } from '../core/itemSyntax.ts';
import { withoutFrontMatter } from '../core/store.ts';

/**
 * The first few lines of a note, for the small preview drawn on each card in the desktop sidebar (notes/NotePeek.tsx).
 *
 * Matt: "the title is huge and it's not got a long description of what we're doing, I think it could use a list of
 * live previewed versions of the cards". The line that was meant to say what a note is about is the gist, and the gist
 * is written by a model on the phone (format/gist.ts) - on a desktop there is no model, so the card was a title and a
 * date and nothing else. This needs nothing but the note: it is the note, smaller.
 *
 * The card draws these lines with its own small editor, through the same formatter the note uses (`peekMarkdown`),
 * rather than as a hand-drawn miniature of each line's shape, which is what it began as.
 *
 * Pure, and the title is never repeated: the card already says it.
 */

/** How many lines are worth drawing. Past this the card is a note rather than a card. */
export const PEEK_LINES = 6;

/**
 * How many lines of the note the card's editor is given (notes/NotePeek.tsx): more than it shows, since a heading or
 * a wrapped line takes more than one, and few enough that a card of a long note costs a card, not a note.
 */
export const PEEK_SOURCE_LINES = 14;

/**
 * The note after its title, as markdown, for the card's own small editor to draw exactly as the note draws it
 * (Matt: "the preview for the formatting should use the same formatter that the actual note uses instead of custom
 * rolled small stuff"). Front matter and the title go, since the card says the title above; up to `most` lines
 * follow, and a block of code opened inside them is kept to its closing fence, so it is drawn as one. A board's
 * fence is left out altogether (Matt: "don't render boards in previews"): its lanes are a screen's worth, and its
 * cards are the note's own items, which follow and are drawn as the list they are. The blank lines around the cut
 * close up to one, and an item's anchor goes: it is the name a board calls the item by, never part of what it says
 * (docs/BOARDS.md), and on a card it took a line of its own.
 */
export function peekMarkdown(body: string, most: number = PEEK_SOURCE_LINES): string {
  const lines = withoutFrontMatter(body.split('\n'));
  const title = lines.findIndex((l) => l.trim() && !IMAGE_ONLY.test(l));
  const out: string[] = [];
  let fence: string | null = null;
  let board = false;
  let fenceLines = 0;
  for (let n = title + 1; n < lines.length; n += 1) {
    const line = lines[n] ?? '';
    const fenced = /^\s*(```|~~~)\s*(\w*)/.exec(line);
    if (fence) {
      if (!board) out.push(line);
      fenceLines += 1;
      if (fenced && line.trim().startsWith(fence)) {
        fence = null;
        board = false;
      }
      // A fence that never closes still ends somewhere.
      if (fenceLines >= most * 3) break;
      continue;
    }
    if (out.length >= most) break;
    // A blank line before anything is drawn, or after another, is nothing to draw.
    if (!line.trim() && (!out.length || !out[out.length - 1]!.trim())) continue;
    if (fenced) {
      fence = fenced[1]!;
      fenceLines = 0;
      board = fenced[2]?.toLowerCase() === 'board';
      if (board) continue;
    }
    // An item's anchor (core/itemSyntax.ts), with the space before it.
    out.push(withoutAnchor(line));
  }
  return out.join('\n').replace(/\s+$/, '');
}

/** A line that is a picture and nothing else: not the title, which noteTitle finds under it, and so does the card. */
const IMAGE_ONLY = /^!\[([^\]]*)\]\([^)]*\)\s*$/;
