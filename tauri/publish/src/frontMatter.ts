import { frontMatterEnd, unquoted } from '../../src/app/core/frontMatter.ts';

/**
 * A note's front matter as it is on disk (docs/MARKDOWN_FIRST.md §2 and §11 decision 1): today TWO blocks, the
 * library's (`id`, `created`, `pinned`, `archived`, `source`, soon `updated`) and then the page's (`type: ticket`,
 * `status:`, `title:`, `tags:`…), which the Dart side writes at the top of the body; tomorrow ONE merged block, the
 * ticket's key written as `issue:` so it cannot be mistaken for the library's `id:`. The publisher reads both shapes
 * and answers the same thing for each: the keys the library manages, the keys the page has, and the words.
 *
 * Where each block ends is the app's own rule (core/frontMatter.ts `frontMatterEnd`), never a second one.
 */

export interface FrontMatter {
  /** The library's keys: hidden on a page. */
  managed: Record<string, string>;
  /** The page's keys, in the order written: what the properties block shows. */
  page: Record<string, string>;
  /** The words after every block of front matter. */
  body: string;
  /** Whether the file held two blocks (the layout on disk today) or one. */
  blocks: 0 | 1 | 2;
}

/** The keys the library writes into a note's first block, and what a page never shows. */
export const MANAGED_KEYS = new Set(['id', 'created', 'updated', 'pinned', 'archived', 'source']);

const KEY = /^([\w.-]+)[ \t]*:(.*)$/;
/** A library id: the Rust side writes a UUID, the web app a 20-odd character random id. Never a ticket key like GHO-12. */
const LIBRARY_ID = /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_-]{16,})$/;

function keysOf(lines: readonly string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of lines) {
    const said = KEY.exec(line);
    if (said && !(said[1]! in out)) out[said[1]!] = unquoted((said[2] ?? '').trim());
  }
  return out;
}

/** The front matter of a note's text on disk, both shapes (the header). */
export function readFrontMatter(text: string): FrontMatter {
  const lines = text.split('\n');
  const first = frontMatterEnd(lines);
  if (!first) return { managed: {}, page: {}, body: text, blocks: 0 };
  const firstKeys = keysOf(lines.slice(1, first - 1));
  const rest = lines.slice(first);
  const second = frontMatterEnd(rest);
  if (second) {
    // Two blocks: the first is the library's whole, the second the page's whole.
    return { managed: firstKeys, page: keysOf(rest.slice(1, second - 1)), body: rest.slice(second).join('\n'), blocks: 2 };
  }
  // One block: the library's names are the library's; `id` is the page's when it is a ticket key and nothing says `issue:`.
  const managed: Record<string, string> = {};
  const page: Record<string, string> = {};
  for (const [key, value] of Object.entries(firstKeys)) {
    const libraryId = key === 'id' && (LIBRARY_ID.test(value) || 'issue' in firstKeys);
    if ((MANAGED_KEYS.has(key) && key !== 'id') || libraryId) managed[key] = value;
    else page[key] = value;
  }
  return { managed, page, body: rest.join('\n'), blocks: 1 };
}

/** The note's text with the library's block taken off: what the app's own readers (titles, embeds, queries) are given. */
export function pageText(text: string): string {
  const front = readFrontMatter(text);
  if (front.blocks !== 2) return text;
  const lines = text.split('\n');
  return lines.slice(frontMatterEnd(lines)).join('\n');
}

/** `true`, `yes` or `on`, however it is cased. */
export function isOn(value: string | undefined): boolean {
  return value !== undefined && /^(true|yes|on)$/i.test(value.trim());
}

/** A `tags:` or `aliases:` value's items: written across in brackets or with commas (core/properties.ts `propertyList`). */
export function listOf(value: string | undefined): string[] {
  if (!value) return [];
  const inner = value.trim().replace(/^\[|\]$/g, '');
  return inner
    .split(',')
    .map((item) => unquoted(item.trim()))
    .filter((item) => item !== '');
}
