import { DOCS_TITLE, docsShared } from './book.ts';

/**
 * The docs book's Markdown, built into the page (vite.docs.config.ts): docs/book/ at the repository's root, its index
 * and every chapter there is when the page is built, read `?raw` as the app's own Guide is (guidebook/guidebook.ts),
 * eagerly, since the whole book is the page. Nothing is fetched and nothing is opened: these docs are public.
 *
 * Globbed, the index too, so a build before the book has its index or a chapter still draws: chapters are being
 * written, and a link with no page yet is drawn as a page not written.
 */
const INDEX = import.meta.glob<string>('../../../docs/book/index.md', { query: '?raw', import: 'default', eager: true });
const CHAPTERS = import.meta.glob<string>('../../../docs/book/chapters/*.md', { query: '?raw', import: 'default', eager: true });

const index = Object.values(INDEX)[0] ?? `---\ntitle: "${DOCS_TITLE}"\nbook: true\n---\n# ${DOCS_TITLE}\n`;

export const DOCS = docsShared(
  index,
  Object.entries(CHAPTERS)
    .sort(([a], [b]) => (a < b ? -1 : 1))
    .map(([, body]) => body),
);
