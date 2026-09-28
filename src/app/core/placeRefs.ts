import { coordsText, type GeoTag } from './geotag.ts';
import { lineWords } from './itemSyntax.ts';

/**
 * A place written into a note's words: a plain Markdown link to a `geo:` address (RFC 5870), alone on its line.
 *
 *   [Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
 *
 * The + beside the line writes one where the caret is (editor/AddList.tsx, Matt: "add a menu to add things like
 * geotag cards images videos and more"), the editor draws the map card under it (editor/placeCards.ts), and any other
 * reader shows a link. A note may hold as many as it likes. Where the note itself was written is another thing, the
 * tag in its front matter (core/geotag.ts), with its own card at the top and its own share switch.
 *
 * The coordinates are the tag's: four decimals, or two for a rough fix, and the roughness is read back from the
 * decimals, as the tag's is. The words are the place's name, or the coordinates as a person reads them when no name
 * came.
 *
 * A share leaves every `geo:` address out unless "Share the places in it" is ticked (share/share.ts), so
 * `withoutPlaces` takes every form one can be written in, not only the line the + writes: a place line goes whole,
 * a link inside other words keeps its words, an autolink and a reference definition go. In fenced and inline code
 * too, since the switch promises that none leaves; and whatever form is left, a link over two lines, a picture's
 * source, raw HTML, loses its address last of all.
 *
 * Only the words, and nothing that reaches a device, as core/imageRefs.ts is: its two imports are pure as well, so
 * the MCP server's Node bundle can read a body's places with the same code.
 */

/** A link's destination when it is a `geo:` address: bare or in angle brackets, with an optional title. */
const DESTINATION = String.raw`\(\s*<?geo:[^)\s>]*>?(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)`;
/** Any Markdown link to a `geo:` address, never a picture's: its words as group 1. Global, so read with `matchAll`. */
export const GEO_LINK = new RegExp(String.raw`(?<!!)\[((?:[^\[\]\n]|\[[^\]\n]*\])*)\]${DESTINATION}`, 'gi');
/** A `geo:` address written as an autolink, `<geo:38.7,-9.1>`. */
export const GEO_AUTOLINK = /<geo:[^>\s]*>/gi;
/** A reference definition whose address is a `geo:` one, `[c]: geo:38.7,-9.1`: its label as group 1. */
export const GEO_DEFINITION = /^ {0,3}\[([^\]\n]+)\]:\s*<?geo:\S*>?.*$/gim;
/** A picture whose source is a `geo:` address, `![map](geo:38.7,-9.1)`: its words as group 1. Global. */
const GEO_PICTURE = new RegExp(String.raw`!\[((?:[^\[\]\n]|\[[^\]\n]*\])*)\]${DESTINATION}`, 'gi');
/**
 * A link or a picture to a `geo:` address written over more than one line: its words broken across two, `[Cais
 * do Sodré](geo:…)`, or its address with a break inside the brackets. Never across a blank line, which no link spans.
 * A picture's mark and the words as groups 1 and 2. Global.
 */
const GEO_LINK_LINES = new RegExp(String.raw`(!?)\[((?:[^\[\]]|\[[^\]]*\])*)\]${DESTINATION}`, 'gi');
/** A `geo:` address anywhere at all, as plain words, in raw HTML or in a URL: `geo:` and coordinates after it. Global. */
const GEO_ADDRESS = /\bgeo:(?=[-+.\d])[^\s<>"'()[\]`]*/gi;

/** The one form a place line takes: the words, then the latitude and the longitude as groups 2 and 3. */
const PLACE = /^\[([^[\]\n]*)\]\(geo:(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)\)$/i;
/** A line that opens or closes fenced code, as editor/lines.ts reads one. */
const FENCE = /^\s*(```|~~~)/;
/** The most a place's name may run to, as the tag's `place:` may (core/geotag.ts). */
const NAME_CHARS = 80;

/** A place read from a line: where it is, and the words it is written with. */
export interface PlaceLine {
  /** The place as a tag: `place` is its name, or null where its words are only the coordinates. */
  tag: GeoTag;
  words: string;
}

/** How many decimals a number was written with. */
function decimalsOf(text: string): number {
  const dot = text.indexOf('.');
  return dot < 0 ? 0 : text.length - dot - 1;
}

/**
 * The place a line is, or null: a line whose words, past its quote's markers and its list lead, are exactly one link
 * to `geo:lat,lon` with the latitude in -90..90 and the longitude in -180..180. That line draws a map card.
 */
export function placeOfLine(text: string): PlaceLine | null {
  const found = PLACE.exec(lineWords(text));
  if (!found) return null;
  const [, words = '', a = '', b = ''] = found;
  const lat = Number(a);
  const lon = Number(b);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  const rough = Math.max(decimalsOf(a), decimalsOf(b)) <= 2;
  const tag: GeoTag = { lat, lon, place: null, rough };
  const named = words.trim();
  return { tag: { ...tag, place: named && named !== coordsText(tag) ? named : null }, words: named };
}

/** A name made safe for a link's words: no brackets, backslashes or line breaks, one space between words, a title's length. */
export function cleanPlaceName(name: string): string {
  return name
    .replace(/[[\]\\]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, NAME_CHARS)
    .trim();
}

/** The line for a place: its name as the words, or the coordinates where there is none. The tag's own precision. */
export function placeMarkdown(tag: GeoTag, name?: string | null): string {
  const digits = tag.rough ? 2 : 4;
  const words = cleanPlaceName(name ?? '') || coordsText(tag);
  return `[${words}](geo:${tag.lat.toFixed(digits)},${tag.lon.toFixed(digits)})`;
}

/** Every place line in a body, outside fenced code, with its line number counting from 1. */
export function placeLines(body: string): (PlaceLine & { line: number })[] {
  const found: (PlaceLine & { line: number })[] = [];
  let fence: string | null = null;
  body.split('\n').forEach((text, index) => {
    const marker = FENCE.exec(text)?.[1];
    if (marker) {
      fence = fence === null ? marker : fence === marker ? null : fence;
      return;
    }
    if (fence) return;
    const place = placeOfLine(text);
    if (place) found.push({ ...place, line: index + 1 });
  });
  return found;
}

/** Whether a line's words are only links (or pictures) to `geo:` addresses: the line goes whole. */
function onlyPlaces(text: string): boolean {
  const words = lineWords(text);
  if (!words) return false;
  const links = [...words.matchAll(GEO_PICTURE)].length + [...words.matchAll(GEO_LINK)].length + [...words.matchAll(GEO_AUTOLINK)].length;
  return links > 0 && words.replace(GEO_PICTURE, '').replace(GEO_LINK, '').replace(GEO_AUTOLINK, '').trim() === '';
}

/**
 * The body with every `geo:` address taken out, wherever it is written: a line of nothing but places goes whole (one
 * blank line kept where it stood between two), a link or a picture inside other words keeps its words, one written
 * over two lines keeps its words too, an autolink goes, and a reference definition goes while its references keep
 * their words. Then any address still there, in raw HTML, a URL or plain words, goes on its own, and what is round it
 * stays. `geo:` as a word with no coordinates after it is words, and the tag in the front matter is the tag's own
 * switch (core/geotag.ts `withGeoTag`).
 */
export function withoutPlaces(body: string): string {
  const joined = body.replace(GEO_LINK_LINES, (whole, _mark: string, words: string) => (whole.includes('\n') && !/\n[ \t]*\n/.test(whole) ? words : whole));
  const lines = joined.split('\n');
  const labels = new Set<string>();
  for (const line of lines) for (const found of line.matchAll(GEO_DEFINITION)) labels.add((found[1] ?? '').toLowerCase());
  const out: string[] = [];
  lines.forEach((line, index) => {
    if (new RegExp(GEO_DEFINITION.source, 'i').test(line)) return;
    if (onlyPlaces(line)) {
      // A place between two blank lines leaves one of them, not two.
      const next = lines[index + 1];
      if (out.length && out[out.length - 1]!.trim() === '' && (next === undefined || next.trim() === '')) out.pop();
      return;
    }
    let kept = line
      .replace(GEO_PICTURE, (_whole, words: string) => words)
      .replace(GEO_LINK, (_whole, words: string) => words)
      .replace(GEO_AUTOLINK, '');
    if (labels.size) kept = kept.replace(/(?<!!)\[([^\]\n]+)\]\[([^\]\n]*)\]/g, (whole, words: string, label: string) => (labels.has((label || words).toLowerCase()) ? words : whole));
    out.push(kept);
  });
  return out.join('\n').replace(GEO_ADDRESS, '');
}

/** Whether a body holds a `geo:` address in any form a share would take out. */
export function hasPlaces(body: string): boolean {
  return withoutPlaces(body) !== body;
}
