import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { DOCS_BASE, docsPages, docsSearchIndex, docsShared } from './src/docs/book.ts';

/**
 * Ghost.md Docs, the public book at ghostmarkdown.com/docs (src/docs; Matt, 2026-10-26: "build an entire docs book
 * build it using ghost markdown but host it publicly from the website so that people can read the docs"): docs.html,
 * the reader's site layout fed the Markdown in docs/book/, built on its own into landing/docs/, which the website's
 * deploy ships with the rest of the site (scripts/deploy-landing.mjs runs this first). `npm run build:docs`.
 *
 * Its own config, not a third input in vite.config.ts, so the app's build and what a release ships are as they were.
 * Under `/docs/`, so its scripts and styles are at /docs/assets/ and not the release's /assets/ (the Caddy block).
 *
 * Every page gets a copy of the HTML at its own address, `/docs/<slug>/index.html`, with its own title, description and
 * canonical address in it: a search engine reads what the page is without running it, and a page's address opens even
 * where the web server sends a missing path nowhere (the Caddy block's try_files sends it to the index instead).
 *
 * And the search's index beside them, `/docs/search.json` (book.ts `docsSearchIndex`; Matt, 2026-10-26: "add the
 * ability to search the book"): every chapter's sections as plain words, which the search box fetches the first time
 * it is used (src/docs/DocsSearch.tsx).
 */

const root = import.meta.dirname;
// docs/book/ and landing/ are at the repository's root, one above this app's (tauri/).
const BOOK = join(root, '..', 'docs', 'book');
const OUT = join(root, '..', 'landing', 'docs');
const SITE = 'https://ghostmarkdown.com';

const build = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')) as { version: string };

/** The book as the page draws it, read here the same way (src/docs/content.ts): for each page's own HTML. */
function readBook() {
  const read = (path: string) => readFileSync(path, 'utf8');
  const index = existsSync(join(BOOK, 'index.md')) ? read(join(BOOK, 'index.md')) : '---\ntitle: "Ghost.md Docs"\nbook: true\n---\n# Ghost.md Docs\n';
  const dir = join(BOOK, 'chapters');
  const chapters = existsSync(dir)
    ? readdirSync(dir)
        .filter((name) => name.endsWith('.md'))
        .sort()
        .map((name) => read(join(dir, name)))
    : [];
  return docsShared(index, chapters);
}

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function docsPagesHtml(): Plugin {
  return {
    name: 'glyph-docs-pages',
    apply: 'build',
    closeBundle() {
      const built = join(OUT, 'docs.html');
      const html = readFileSync(built, 'utf8');
      rmSync(built);
      const book = readBook();
      writeFileSync(join(OUT, 'search.json'), JSON.stringify(docsSearchIndex(book)));
      for (const page of docsPages(book)) {
        const address = `${SITE}${DOCS_BASE}${page.slug ? encodeURIComponent(page.slug) : ''}`;
        const head = [
          `<title>${escape(page.title)}</title>`,
          ...(page.description ? [`<meta name="description" content="${escape(page.description)}" />`] : []),
          `<link rel="canonical" href="${address}" />`,
          `<meta property="og:title" content="${escape(page.title)}" />`,
          ...(page.description ? [`<meta property="og:description" content="${escape(page.description)}" />`] : []),
          `<meta property="og:url" content="${address}" />`,
          `<meta property="og:image" content="${SITE}/icon.png" />`,
        ].join('\n    ');
        const own = html.replace(/<title>[^<]*<\/title>\s*(<meta name="description"[^>]*>)?/, head);
        const dir = page.slug ? join(OUT, page.slug) : OUT;
        mkdirSync(dir, { recursive: true });
        writeFileSync(join(dir, 'index.html'), own);
      }
    },
  };
}

export default defineConfig({
  plugins: [react(), docsPagesHtml()],
  base: DOCS_BASE,
  // The release's icons are the website's (landing/), so the page names them from the root.
  publicDir: false,
  define: {
    __GLYPH_BUILD__: JSON.stringify(build),
    __GLYPH_VERSION__: JSON.stringify(pkg.version),
    __GLYPH_SOURCE__: JSON.stringify(''),
    __GLYPH_STAGING__: JSON.stringify(false),
  },
  // The book is read from outside this app's folder.
  server: { fs: { allow: ['..'] } },
  build: {
    outDir: OUT,
    emptyOutDir: true,
    sourcemap: false,
    rollupOptions: { input: { docs: join(root, 'docs.html') } },
  },
  clearScreen: false,
});
