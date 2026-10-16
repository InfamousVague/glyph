import { destination, escapeText } from './escape.ts';
import { PICTURE_SCHEME, type ClipMode } from './kinds.ts';
import type { PictureRef } from './markdown.ts';

/**
 * A clip as the note it becomes: plain Markdown the app already draws, with what the clip is in front matter.
 *
 *   ---
 *   source: https://example.com/the-article
 *   clipped: 2026-10-16
 *   tags: [reading, garden]
 *   ---
 *   # The page's title
 *
 *   The person's comment, when they wrote one.
 *
 *   ---
 *
 *   The page's words.
 *
 * `source:` and `clipped:` are keys like any other: the app folds the block to one quiet line, a query can read
 * them (`where: source contains example.com`), and any other Markdown app shows them as the page's front matter.
 * `tags:` is written as a list in brackets, the one form the app's front matter rule and its queries both read
 * (core/frontMatter.ts, core/query/records.ts): a list item per line would end the block at its first item. The title
 * is the first heading, which is what names a note in the app (core/noteTitle.ts).
 */

/** What the person chose in the popup, with what the page answered. */
export interface Draft {
  mode: ClipMode;
  url: string;
  title: string;
  /** The page's words, its pictures written as `ghost-clip:picture/<n>` (core/markdown.ts). */
  markdown: string;
  pictures: PictureRef[];
  description?: string;
  tags: string[];
  comment: string;
  /** A workspace's id, from the account's settings; null for none. */
  workspace: string | null;
  /** A notebook's note id; null for none. */
  notebook: string | null;
}

/** The longest title kept: a page's `<title>` can be a paragraph of keywords. */
const TITLE_MOST = 160;

/** A title on one line, at most so long, never empty: the page's address names it where nothing else does. */
export function cleanTitle(title: string, url: string): string {
  let words = title.replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim();
  // A heading of its own words: no leading marks that would make it something else.
  words = words.replace(/^[#>\-+*\s]+/, '').trim();
  if (words.length > TITLE_MOST) words = `${words.slice(0, TITLE_MOST - 1).trimEnd()}…`;
  if (words) return words;
  try {
    return new URL(url).hostname || 'Clipped page';
  } catch {
    return 'Clipped page';
  }
}

/**
 * Tags as the person typed them, separated by commas or spaces, each as the app's tag grammar has it (core/tags.ts):
 * a letter, then letters, digits, `_`, `-` or `/`. A leading `#` is dropped; anything else that is not part of a tag
 * name is taken out. Repeats, ignoring case, are kept once.
 */
export function parseTags(text: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of text.split(/[,\s]+/)) {
    const name = raw.replace(/^#+/, '').replace(/[^\p{L}\p{N}_/-]/gu, '').replace(/^[^\p{L}]+/u, '').replace(/[-/]+$/, '');
    if (!name || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    out.push(name);
  }
  return out;
}

/** The date on this computer's calendar, as `clipped:` writes it: 2026-10-16. */
export function localDate(at: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())}`;
}

/** A value on a front matter line: as it is where it reads back the same, else in double quotes. */
function yamlValue(value: string): string {
  return /^[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\s"'\\]+$/.test(value) && !/\s#/.test(value) ? value : JSON.stringify(value);
}

export function frontMatter({ url, clipped, tags }: { url: string; clipped: Date; tags: readonly string[] }): string {
  const lines = ['---', `source: ${yamlValue(url)}`, `clipped: ${localDate(clipped)}`];
  if (tags.length) lines.push(`tags: [${tags.join(', ')}]`);
  lines.push('---');
  return lines.join('\n');
}

/** A link to a page that reads as where it is: `example.com/the-article`. */
export function linkLine(url: string): string {
  let shown = url;
  try {
    const at = new URL(url);
    shown = `${at.hostname.replace(/^www\./, '')}${at.pathname === '/' ? '' : at.pathname}`;
  } catch {
    shown = url;
  }
  return `[${escapeText(shown)}](${destination(url)})`;
}

/** The words a mode clips, before its pictures are placed: a bookmark and a screenshot are made here, the rest came from the page. */
export function contentOf(draft: Pick<Draft, 'mode' | 'url' | 'title' | 'markdown' | 'pictures' | 'description'>): string {
  if (draft.mode === 'bookmark') {
    const parts = [linkLine(draft.url)];
    if (draft.description?.trim()) parts.push(escapeText(draft.description.trim().replace(/\s+/g, ' ')));
    if (draft.pictures.length) parts.push(`![${draft.pictures[0]!.alt.replace(/[[\]]/g, '')}](${PICTURE_SCHEME}0)`);
    return `${parts.join('\n\n')}\n`;
  }
  if (draft.mode === 'screenshot') return draft.pictures.length ? `![${draft.pictures[0]!.alt.replace(/[[\]]/g, '')}](${PICTURE_SCHEME}0)\n` : '';
  return draft.markdown;
}

/** The whole note: its front matter, its title as the first heading, the person's comment, and the clip's words. */
export function noteBody({ title, url, clipped, tags, comment, content }: { title: string; url: string; clipped: Date; tags: readonly string[]; comment: string; content: string }): string {
  const parts = [`# ${title}`];
  const said = comment.replace(/\r\n?/g, '\n').trim();
  const words = content.trim();
  if (said) parts.push(said);
  // A rule between the person's words and the page's, with a blank line above it so it is never read as a heading.
  if (said && words) parts.push('---');
  if (words) parts.push(words);
  return `${frontMatter({ url, clipped, tags })}\n${parts.join('\n\n')}\n`;
}
