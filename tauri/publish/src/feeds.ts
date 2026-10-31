import type { Library, Page } from './library.ts';
import { summaryOf } from './page.tsx';

/** `sitemap.xml` and `feed.xml` (Atom, the most recently changed pages), both wanting the site's address to be of use. */

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function address(baseUrl: string | null, href: string): string {
  return `${baseUrl ?? ''}/${href}`;
}

export function sitemap(library: Library, baseUrl: string | null): string {
  const urls = [
    `  <url><loc>${escape(address(baseUrl, 'index.html'))}</loc></url>`,
    ...library.pages.map((page) => `  <url><loc>${escape(address(baseUrl, page.href))}</loc><lastmod>${new Date(page.updatedAt).toISOString().slice(0, 10)}</lastmod></url>`),
  ];
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join('\n')}\n</urlset>\n`;
}

export function feed(library: Library, title: string, baseUrl: string | null, count = 20): string {
  const recent: Page[] = [...library.pages].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, count);
  const updated = recent[0] ? new Date(recent[0].updatedAt).toISOString() : new Date(0).toISOString();
  const entries = recent.map((page) =>
    [
      '  <entry>',
      `    <title>${escape(page.title)}</title>`,
      `    <link href="${escape(address(baseUrl, page.href))}"/>`,
      `    <id>${escape(address(baseUrl, page.href))}</id>`,
      `    <updated>${new Date(page.updatedAt).toISOString()}</updated>`,
      `    <summary>${escape(summaryOf(page))}</summary>`,
      '  </entry>',
    ].join('\n'),
  );
  return [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<feed xmlns="http://www.w3.org/2005/Atom">',
    `  <title>${escape(title)}</title>`,
    `  <link href="${escape(address(baseUrl, 'index.html'))}"/>`,
    `  <link rel="self" href="${escape(address(baseUrl, 'feed.xml'))}"/>`,
    `  <id>${escape(address(baseUrl, ''))}</id>`,
    `  <updated>${updated}</updated>`,
    ...entries,
    '</feed>',
    '',
  ].join('\n');
}
