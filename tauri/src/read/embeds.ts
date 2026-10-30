import { frontMatterOffset } from '../app/core/frontMatter.ts';
import { titleKey } from '../app/core/titleKey.ts';

/**
 * Section embeds on the shared page (Matt, 2026-10-30, "add all 12"; the app's lib/editor/media/note_embeds.dart):
 * `![[Note]]`, `![[Note#Heading]]` and `![[Note#^line]]` on a line of their own. Rendered.tsx draws the section in place
 * when the note it names is a page of the same share, and a "from [[Note]]" placeholder when it is not: a share carries
 * only its own pages, and nothing is fetched for a page the reader was never given. The Markdown is not changed.
 */

/** An embed as written: the note's title, and what followed a `#`. */
export interface Embed {
  title: string;
  anchor: string | null;
}

const EMBED = /^\s*!\[\[([^[\]\n]{1,200})\]\]\s*$/;
const PICTURE = /\.(png|jpe?g|gif|webp|bmp|heic|avif)$/i;
const HEADING = /^(#{1,6})\s+(.*?)\s*#*\s*$/;
const FENCE = /^\s*(```|~~~)/;
const LIST = /^(\s*)(?:[-*+]|\d+[.)])\s/;

/** The embed a paragraph is, when it is only an embed of a note: not a picture's, and not one with no name. */
export function embedOf(text: string): Embed | null {
  const match = EMBED.exec(text);
  if (!match) return null;
  const whole = match[1]!.trim();
  const bar = whole.indexOf('|');
  const inside = (bar >= 0 ? whole.slice(0, bar) : whole).trim();
  if (PICTURE.test(inside)) return null;
  const hash = inside.indexOf('#');
  const title = (hash >= 0 ? inside.slice(0, hash) : inside).trim();
  if (!title) return null;
  const anchor = hash >= 0 ? inside.slice(hash + 1).trim() : '';
  return { title, anchor: anchor || null };
}

/** [body]'s lines that are words, each with whether it is fenced code. */
function linesOf(body: string): { text: string; fenced: boolean }[] {
  const out: { text: string; fenced: boolean }[] = [];
  let fence: string | null = null;
  for (const text of body.slice(frontMatterOffset(body)).split('\n')) {
    const marker = FENCE.exec(text);
    if (marker) {
      out.push({ text, fenced: true });
      fence = fence === null ? marker[1]! : fence === marker[1] ? null : fence;
      continue;
    }
    out.push({ text, fenced: fence !== null });
  }
  return out;
}

/**
 * What an embed draws of [body]: the whole note without its front matter and its title's heading; under a heading,
 * the heading and what follows it up to the next heading as high or higher; a named line, the line, and a list item's
 * own items under it. Null where the anchor names nothing in the note, as the app's `sectionOf` (lib/core/block_ids.dart).
 */
export function sectionOf(body: string, anchor: string | null): string | null {
  const lines = linesOf(body);
  if (anchor === null) {
    const first = lines.findIndex((line) => line.text.trim() !== '');
    const heading = first >= 0 && !lines[first]!.fenced ? HEADING.exec(lines[first]!.text) : null;
    return (heading ? lines.slice(first + 1) : lines)
      .map((line) => line.text)
      .join('\n')
      .trim();
  }
  if (anchor.startsWith('^')) {
    const name = anchor.slice(1).toLowerCase();
    const at = lines.findIndex((line) => !line.fenced && new RegExp(`(?:^|\\s)\\^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`).test(line.text));
    if (at < 0) return null;
    const lead = LIST.exec(lines[at]!.text);
    const kept = [lines[at]!.text];
    if (lead) {
      for (let i = at + 1; i < lines.length; i += 1) {
        const text = lines[i]!.text;
        if (text.trim() === '' || /^\s*/.exec(text)![0].length <= lead[1]!.length) break;
        kept.push(text);
      }
    }
    return kept.join('\n');
  }
  const key = titleKey(anchor);
  const at = lines.findIndex((line) => {
    const heading = line.fenced ? null : HEADING.exec(line.text);
    return heading !== null && titleKey(heading[2]!) === key;
  });
  if (at < 0) return null;
  const level = HEADING.exec(lines[at]!.text)![1]!.length;
  let end = lines.length;
  for (let i = at + 1; i < lines.length; i += 1) {
    const heading = lines[i]!.fenced ? null : HEADING.exec(lines[i]!.text);
    if (heading && heading[1]!.length <= level) {
      end = i;
      break;
    }
  }
  return lines
    .slice(at, end)
    .map((line) => line.text)
    .join('\n')
    .trim();
}

/** How deep embeds draw on the page, as in the app: a page in this one, and a page in that. */
export const MOST_EMBED_DEPTH = 2;
