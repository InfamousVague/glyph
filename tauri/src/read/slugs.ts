import type { Shared } from '../app/share/share.ts';

/*
 * A page's name in a site's address (site.ts, docs/SITES.md), on its own and pure: the public docs at /docs/
 * (src/docs, vite.docs.config.ts) name their pages the same way, and their build reads these in Node.
 */

/**
 * A title as a page's name: lower case, accents off, letters and digits of any script kept, everything else one `-`
 * between them, at most sixty characters. "Café plans, 2026" is `cafe-plans-2026`.
 */
export function slugOf(title: string): string {
  const plain = title
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '');
  return [...plain].slice(0, 60).join('').replace(/-+$/, '');
}

/**
 * Each page's name, in the site's order: the first page has none (it is the site's own address), and every other its
 * title's slug, made unique with `-2`, `-3` where two titles slug alike, or `page-<n>` where a title has nothing a
 * slug can keep.
 */
export function siteSlugs(shared: Pick<Shared, 'pages'>): string[] {
  const taken = new Set<string>(['']);
  return shared.pages.map((page, i) => {
    if (i === 0) return '';
    const base = slugOf(page.title) || `page-${i + 1}`;
    let slug = base;
    for (let n = 2; taken.has(slug); n += 1) slug = `${base}-${n}`;
    taken.add(slug);
    return slug;
  });
}
