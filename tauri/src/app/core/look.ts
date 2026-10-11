import { FRONT_MATTER_LINES, frontMatterValue, withFrontMatterValue } from './frontMatter.ts';

/**
 * How a note looks (docs/DESIGN.md §144): one flat key in its front matter, `look:`, with two values. Matt asked for
 * templates "with cards showing how they look (map header, typography focus, etc)", and chose both:
 *
 * - `look: map`, A map at the top: where the note was written, drawn as a header across its column (editor/MapCard.tsx
 *   `size`), its box held from the first frame, and its place kept from the card's own press even with Tag new notes off.
 * - `look: reading`, A page to read: the words in the interface's face, a display title, a lead line under it, and from
 *   600px a column of 36rem. No new font: a note's faces are the two the person chose.
 *
 * One key, one value, so never both at once. Anything else in it is no look, and the key is kept as it was written, as
 * every key the app does not know is. In a file, after the file's own properties, Obsidian and any CommonMark reader
 * draw the block as a rule and then a heading holding its keys (`look: reading` with the `---` under it is one), as
 * they draw the tag's `location:` (docs/DESIGN.md §134): where the app's keys go in a file is the file's question, left
 * with §142's. The app keeps the key out of the folded front matter line (editor/extended.ts), so a new reading note
 * opens on its title. Pure, so the MCP server keeps it across a rewrite as the app reads it.
 */

export type Look = 'map' | 'reading';

/** The body's first lines, as far as front matter can reach: a look is read without splitting a long note whole. */
function head(body: string): string {
  let at = -1;
  for (let n = 0; n < FRONT_MATTER_LINES; n += 1) {
    at = body.indexOf('\n', at + 1);
    if (at < 0) return body;
  }
  return body.slice(0, at);
}

/** The note's look, or null for the usual one: `look:` read in any case, and anything but the two taken as none. */
export function lookOf(body: string): Look | null {
  if (!body.startsWith('---') && !body.startsWith('+++')) return null;
  const value = frontMatterValue(head(body), 'look')?.trim().toLowerCase();
  return value === 'map' || value === 'reading' ? value : null;
}

/** The body with its look set, or (null) taken off, and a block that held nothing else with it. Every other key is kept. */
export function withLook(body: string, look: Look | null): string {
  return withFrontMatterValue(body, 'look', look);
}
