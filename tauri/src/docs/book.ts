import { chaptersOf } from '../app/book/book.ts';
import { frontMatterEnd } from '../app/core/frontMatter.ts';
import { noteTitle } from '../app/core/noteTitle.ts';
import { sameTitle } from '../app/core/titleKey.ts';
import type { Shared } from '../app/share/share.ts';
import { siteSlugs } from '../read/slugs.ts';

/**
 * Ghost.md Docs, the public book at ghostmarkdown.com/docs (Matt, 2026-10-26: "build an entire docs book build it using
 * ghost markdown but host it publicly from the website so that people can read the docs"): docs/book/ at the
 * repository's root, a notebook as the app keeps one, read here as a published site is (read/Site.tsx), only from
 * Markdown built into the page rather than from a sealed share.
 *
 * Pure, and it imports nothing that draws: the docs build (vite.docs.config.ts) reads it in Node to write each page's
 * own copy of the HTML, with its title and description, at the address the page itself goes to.
 *
 * The book is put together as the app shares a notebook (share/share.ts `sharedOf`): the index first, then each chapter
 * its index links to that has a page, found by its `# ` title and in the index's order. A link with no page yet stays in
 * the index, where the reader draws it as a page not written; a page no link names is not in the book.
 */

export const DOCS_TITLE = 'Ghost.md Docs';

/** Where the docs are on the website: `/docs/` is the index, `/docs/<slug>` a page ([slugOf]). */
export const DOCS_BASE = '/docs/';

/** The book: its index's body, and every chapter file's, in any order. */
export function docsShared(index: string, chapters: readonly string[]): Shared {
  const title = noteTitle(index) || DOCS_TITLE;
  const pages = [{ title, body: index }];
  for (const chapter of chaptersOf(index)) {
    const found = chapters.find((body) => sameTitle(noteTitle(body), chapter.title));
    if (found !== undefined && !pages.some((p) => sameTitle(p.title, chapter.title))) pages.push({ title: chapter.title, body: found });
  }
  return { v: 1, kind: 'book', title, pages, at: 0 };
}

/** The page an address names, as a slug: null for the index (`/docs`, `/docs/`), and a trailing `/` read as none. */
export function docsSlugAt(pathname: string): string | null {
  const at = pathname.indexOf(DOCS_BASE.slice(0, -1));
  const rest = (at >= 0 ? pathname.slice(at + DOCS_BASE.length - 1) : pathname).replace(/^\/+|\/+$/g, '');
  if (!rest) return null;
  try {
    return decodeURIComponent(rest);
  } catch {
    return rest;
  }
}

/** A page's address: the index at `/docs/`, every other page at `/docs/<slug>`. */
export function docsPath(slug: string): string {
  return slug ? `${DOCS_BASE}${encodeURIComponent(slug)}` : DOCS_BASE;
}

/** What the browser's tab says for a page: "<Page> · Ghost.md Docs", and the book's own title for its index. */
export function docsTitle(shared: Pick<Shared, 'title'>, page: string | null): string {
  return page && !sameTitle(page, shared.title) ? `${page} · ${shared.title}` : shared.title;
}

/**
 * A page in a sentence, for a search engine's line under its title (`<meta name="description">`): its first paragraph
 * of words, out of its heading, front matter, marks and links, at most 160 characters.
 */
export function docsSummary(body: string): string {
  const all = body.split('\n');
  const lines = all.slice(frontMatterEnd(all));
  const words: string[] = [];
  for (const line of lines) {
    const plain = line.trim();
    if (!plain) {
      if (words.length) break;
      continue;
    }
    // Headings, lists, tables, fences, quotes' marks and pictures are not the sentence a page opens on.
    if (/^(#|[-*+] |\d+\. |\||```|~~~|!\[|<)/.test(plain)) {
      if (words.length) break;
      continue;
    }
    words.push(plain.replace(/^>\s*/, ''));
  }
  const text = words
    .join(' ')
    .replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, '$2')
    .replace(/\[\[([^\]]+)\]\]/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/[*_`~=]+/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return text.length > 160 ? `${text.slice(0, 157).replace(/\s+\S*$/, '')}…` : text;
}

/** Each page as the build writes it: its slug (the index's is empty), the tab's title and its description. */
export function docsPages(shared: Shared): { slug: string; title: string; description: string }[] {
  const slugs = siteSlugs(shared);
  return shared.pages.map((page, at) => ({
    slug: slugs[at] ?? '',
    title: docsTitle(shared, at === 0 ? null : page.title),
    description: docsSummary(page.body),
  }));
}
