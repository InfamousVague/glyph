import { titleKey } from '../../src/app/core/titleKey.ts';
import { plainLine } from '../../src/docs/book.ts';
import { slugOf } from '../../src/read/slugs.ts';
import type { Library, Page } from './library.ts';
import { namesOf } from './library.ts';

/**
 * Where a page's links go. `[[Note]]`, `[[Note|alias]]`, `[[Note#Heading]]`, `[[Note#^line]]` and `![[Note#Heading]]`
 * all name a page by its title (case and punctuation aside, core/titleKey.ts), an alias (`aliases:`) or a ticket's key
 * (`[[GHO-12]]`), across every folder; where two pages share a name the one in the linking page's own folder wins, then
 * the one whose folder is nearest, and `[[Work/Plan]]` names the page by its folder outright. A heading becomes the id
 * the page gives it (`headingId`). A name no page has is left to the words, with the name in a `title` so a reader can
 * see what was meant.
 *
 * Every address is relative to the page it is written on, so the site works at a domain's root, under GitHub Pages'
 * `/<repo>/`, or opened from a folder.
 */

export interface Resolver {
  /** A page's address, by a link's title and anchor, from the page at `from`. */
  hrefOf: (from: Page, title: string, anchor: string | null) => string | null;
  /** The page a title names, from `from`. */
  pageOf: (from: Page, title: string) => Page | null;
  /** A file's address from `from`, for `image/<name>` and the like; null for one the library has not got. */
  fileHref: (from: Page, target: string) => string | null;
  /** Every file a page asked for, by its path from the root: what the build copies. */
  used: Set<string>;
}

/** `to` from the folder `from` is in: `../work/plan.html`. */
export function relativeHref(from: string, to: string): string {
  const here = from.split('/').slice(0, -1);
  const there = to.split('/');
  let shared = 0;
  while (shared < here.length && shared < there.length - 1 && here[shared] === there[shared]) shared += 1;
  const up = here.length - shared;
  const path = [...Array<string>(up).fill('..'), ...there.slice(shared)].join('/');
  return path || './';
}

/** A heading's id: its words as read, as a slug (read/slugs.ts). `^line` keeps its name. */
export function headingId(text: string): string {
  const plain = text.trim();
  if (plain.startsWith('^')) return slugOf(plain.slice(1)) || 'line';
  return slugOf(plainLine(plain)) || 'heading';
}

/** How many folders two pages share from the root. */
function nearness(a: Page, b: Page): number {
  let n = 0;
  while (n < a.folder.length && n < b.folder.length && a.folder[n] === b.folder[n]) n += 1;
  return n;
}

export function resolver(library: Library): Resolver {
  const names = namesOf(library.pages);
  const used = new Set<string>();
  const byPath = new Map<string, Page>();
  for (const page of library.pages) byPath.set(page.file.replace(/\.md$/, '').toLowerCase(), page);

  const pageOf = (from: Page, title: string): Page | null => {
    const written = title.trim();
    if (!written) return null;
    if (written.includes('/')) {
      const path = written.replace(/^\/+/, '').replace(/\.md$/, '').toLowerCase();
      const exact = byPath.get(path);
      if (exact) return exact;
      // `[[Work/Plan]]` without the `workspaces/` in front.
      for (const [file, page] of byPath) if (file.endsWith(`/${path}`)) return page;
      return null;
    }
    const found = names.get(titleKey(written));
    if (!found?.length) return null;
    if (found.length === 1) return found[0]!;
    const same = found.filter((page) => page.folder.join('/') === from.folder.join('/'));
    if (same.length) return same[0]!;
    return [...found].sort((a, b) => nearness(b, from) - nearness(a, from) || a.file.localeCompare(b.file))[0]!;
  };

  const hrefOf = (from: Page, title: string, anchor: string | null): string | null => {
    const page = pageOf(from, title);
    if (!page) return null;
    const base = page === from ? '' : relativeHref(from.href, page.href);
    const hash = anchor ? `#${headingId(anchor)}` : '';
    return `${base}${hash}` || page.href.split('/').pop()!;
  };

  const fileHref = (from: Page, target: string): string | null => {
    const clean = target.trim().replace(/^\.\//, '').replace(/^\//, '');
    let decoded = clean;
    try {
      decoded = decodeURIComponent(clean);
    } catch {
      // A target with a stray % is tried as written.
    }
    const path = library.files.has(decoded) ? decoded : library.files.has(clean) ? clean : null;
    if (!path) return null;
    used.add(path);
    return relativeHref(from.href, path.split('/').map(encodeURIComponent).join('/'));
  };

  return { hrefOf, pageOf, fileHref, used };
}
