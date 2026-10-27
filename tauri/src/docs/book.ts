import { chaptersOf } from '../app/book/book.ts';
import { frontMatterEnd } from '../app/core/frontMatter.ts';
import { noteTitle } from '../app/core/noteTitle.ts';
import { sameTitle } from '../app/core/titleKey.ts';
import type { Shared } from '../app/share/share.ts';
import { siteSlugs, slugOf } from '../read/slugs.ts';

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

/**
 * A line's words as a reader sees them, for the search's index and its snippets (search.ts): `[[links]]` as their
 * words, a link as its text, a picture as nothing, and the marks (`**`, a backtick, `==`, `~~`, a heading's `#`, a
 * list's `-`, a quote's `>`, a table's `|`) taken off.
 */
export function plainLine(line: string): string {
  return line
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, '$2')
    .replace(/\[\[([^\]]+)\]\]/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/^\s*#{1,6}\s+/, '')
    .replace(/^\s*>\s?/, '')
    .replace(/^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?/, '')
    .replace(/\*\*|__|==|~~|`/g, '')
    .replace(/(^|[^\p{L}\p{N}])[*_]+|[*_]+(?=[^\p{L}\p{N}]|$)/gu, '$1')
    .replace(/\s*\|\s*/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** A heading a reader can be sent to: its level (2 to 4), its words, its anchor on the page, and its line in the body. */
export interface DocsHeading {
  level: number;
  text: string;
  anchor: string;
  line: number;
}

/**
 * Every `## `, `### ` and `#### ` heading of a page (Matt, 2026-10-26: "add the ability to search the book"), each
 * with the anchor `/docs/<page>#<anchor>` names it by: its words as a slug (read/slugs.ts `slugOf`, as a page's own
 * name is), made unique on the page with `-2`, `-3`. Front matter and fenced code are passed over, so a `## comment`
 * in a code block is not a heading. The search's index is built with this from the book's Markdown, and the page
 * finds the heading again with it from the text its editor holds (reveal.ts), so the two always agree.
 */
export function docsHeadings(body: string): DocsHeading[] {
  const lines = body.split('\n');
  const taken = new Set<string>();
  const headings: DocsHeading[] = [];
  let fence: string | null = null;
  for (let n = frontMatterEnd(lines); n < lines.length; n += 1) {
    const line = lines[n]!;
    const opens = /^\s*(```|~~~)/.exec(line);
    if (opens) {
      if (fence === null) fence = opens[1]!;
      else if (opens[1] === fence) fence = null;
      continue;
    }
    if (fence !== null) continue;
    const heading = /^(#{2,4})\s+(.+?)\s*#*\s*$/.exec(line);
    if (!heading) continue;
    const text = plainLine(heading[2]!);
    const base = slugOf(text) || 'section';
    let anchor = base;
    for (let k = 2; taken.has(anchor); k += 1) anchor = `${base}-${k}`;
    taken.add(anchor);
    headings.push({ level: heading[1]!.length, text, anchor, line: n });
  }
  return headings;
}

/** A line the search reads no words in: the page's own `# Title` (the index has it), a fence's marks, a table's rule. */
const NO_WORDS = /^(#\s|\s*(```|~~~)|\s*\|?\s*:?-{3,}[-|:\s]*$|\s*(---|\*\*\*)\s*$)/;

/**
 * A page cut where its headings are, for the search: the words before the first heading (heading null, anchor '',
 * the page's top), then each heading with the words under it up to the next. A fence's code stays as words, and
 * every line is read as [plainLine] reads it.
 */
export function pageSections(body: string): { heading: string | null; anchor: string; text: string }[] {
  const lines = body.split('\n');
  const cuts = [
    { heading: null as string | null, anchor: '', from: frontMatterEnd(lines) - 1 },
    ...docsHeadings(body).map((h) => ({ heading: h.text as string | null, anchor: h.anchor, from: h.line })),
  ];
  return cuts.map((cut, at) => {
    const to = at + 1 < cuts.length ? cuts[at + 1]!.from : lines.length;
    const words = lines
      .slice(cut.from + 1, to)
      .filter((line) => !NO_WORDS.test(line))
      .map(plainLine)
      .filter(Boolean);
    return { heading: cut.heading, anchor: cut.anchor, text: words.join(' ') };
  });
}

/**
 * The search's index, `/docs/search.json`, which the docs build writes beside the pages (vite.docs.config.ts): every
 * chapter's sections, and not the index page, whose words are only the chapters' names. Kept small: each page's slug
 * and title once, and each section a row of four, `[page, heading, anchor, words]`, the page by its place in `pages`;
 * a page's opening words have no heading (null) and no anchor ('').
 */
export interface DocsIndex {
  v: 1;
  pages: { slug: string; title: string }[];
  sections: [page: number, heading: string | null, anchor: string, text: string][];
}

export function docsSearchIndex(shared: Shared): DocsIndex {
  const slugs = siteSlugs(shared);
  const pages: DocsIndex['pages'] = [];
  const sections: DocsIndex['sections'] = [];
  shared.pages.forEach((page, at) => {
    if (at === 0) return;
    const p = pages.push({ slug: slugs[at] ?? '', title: page.title }) - 1;
    for (const section of pageSections(page.body)) {
      if (section.heading === null && !section.text) continue;
      sections.push([p, section.heading, section.anchor, section.text]);
    }
  });
  return { v: 1, pages, sections };
}
