import { plainLine } from '../../src/docs/book.ts';
import type { Library, Page } from './library.ts';

/**
 * The search's index, `search.json` (src/docs/book.ts `docsSearchIndex` is the docs' version of the same): every page
 * as its title, its folder, its address and its words as a reader sees them, fences and front matter left out, cut to
 * a few thousand characters so a library of a thousand notes is still one small file. client/search.js fetches it the
 * first time the box is typed in and matches in the browser; nothing leaves the page.
 */

export interface SearchEntry {
  title: string;
  folder: string;
  href: string;
  kind: string;
  text: string;
}

const MOST_CHARS = 4000;

/** A page's words for the index: each line as read, no fences, no HTML. */
export function searchText(page: Page): string {
  const out: string[] = [];
  let fence: string | null = null;
  for (const line of page.body.split('\n')) {
    const marker = /^\s*(```|~~~)/.exec(line);
    if (marker) {
      fence = fence === null ? marker[1]! : fence === marker[1] ? null : fence;
      continue;
    }
    if (fence !== null) continue;
    const plain = plainLine(line).replace(/<[^>]+>/g, ' ').trim();
    if (plain) out.push(plain);
  }
  return out.join(' ').replace(/\s+/g, ' ').slice(0, MOST_CHARS);
}

export function searchIndex(library: Library): SearchEntry[] {
  return library.pages.map((page) => ({
    title: page.title,
    folder: page.folder.join(' › '),
    href: page.href,
    kind: page.kind,
    text: page.kind === 'canvas' && page.canvas ? page.canvas.nodes.map((node) => (node.type === 'text' ? node.text : node.type === 'group' ? (node.label ?? '') : '')).join(' ').slice(0, MOST_CHARS) : searchText(page),
  }));
}
