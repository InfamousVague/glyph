import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { chapterParts, chaptersOf } from '../app/book/book.ts';
import { drawnBody } from '../read/drawn.ts';
import { docsHeadings, docsPages, docsPath, docsSearchIndex, docsShared, docsSlugAt, docsSummary, docsTitle, pageSections, plainLine } from './book.ts';
import { fold, matchRanges, prepare, queryTerms, searchDocs, snippetOf, type Part } from './search.ts';

/**
 * Ghost.md Docs put together from docs/book/ (book.ts): the index first, then each chapter it links to that has a
 * page, in the index's order and found by its title; a page at `/docs/<slug>`; and what each page's own HTML says.
 */

const index = [
  '---',
  'title: "Ghost.md Docs"',
  'book: true',
  '---',
  '# Ghost.md Docs',
  '',
  'Everything Ghost.md does, a page at a time.',
  '',
  '## Part I: Getting started',
  '',
  '1. [[Welcome to Ghost.md]]',
  '2. [[Install Ghost.md]]',
  '',
  '## Part II: Writing',
  '',
  '3. [[Markdown and Ghost.md\'s marks]]',
  '4. [[Canvases]]',
  '',
].join('\n');

describe('the docs book', () => {
  it('is the index, then the chapters it links to that are written, in its order, a page no link names left out', () => {
    const shared = docsShared(index, ['# Canvases\n\nCards.', '# Not in the index\n\nStray.', '# Welcome to Ghost.md\n\nHello.']);
    expect(shared.kind).toBe('book');
    expect(shared.title).toBe('Ghost.md Docs');
    expect(shared.pages.map((p) => p.title)).toEqual(['Ghost.md Docs', 'Welcome to Ghost.md', 'Canvases']);
    expect(shared.pages[0]!.body).toBe(index);
  });

  it('names each part over the chapters it opens', () => {
    expect(chapterParts(index)).toEqual(['Part I: Getting started', null, 'Part II: Writing', null]);
  });

  it('reads a page from its address, with or without the slash a directory gets, and writes the address back', () => {
    expect(docsSlugAt('/docs')).toBeNull();
    expect(docsSlugAt('/docs/')).toBeNull();
    expect(docsSlugAt('/docs/the-market')).toBe('the-market');
    expect(docsSlugAt('/docs/the-market/')).toBe('the-market');
    expect(docsPath('')).toBe('/docs/');
    expect(docsPath('the-market')).toBe('/docs/the-market');
  });

  it('gives each page its own title and description, and the index its own', () => {
    const shared = docsShared(index, ['# Welcome to Ghost.md\n\nGhost.md is **Markdown** notes, see [[Install Ghost.md]].\n\nMore.']);
    expect(docsTitle(shared, null)).toBe('Ghost.md Docs');
    expect(docsPages(shared)).toEqual([
      { slug: '', title: 'Ghost.md Docs', description: 'Everything Ghost.md does, a page at a time.' },
      { slug: 'welcome-to-ghost-md', title: 'Welcome to Ghost.md · Ghost.md Docs', description: 'Ghost.md is Markdown notes, see Install Ghost.md.' },
    ]);
    expect(docsSummary(`# Long\n\n${'word '.repeat(60)}`).length).toBeLessThanOrEqual(160);
  });
});

/** The book as the build reads it (vite.docs.config.ts), from docs/book/ at the repository's root. */
function realBook() {
  const dir = join(import.meta.dirname, '..', '..', '..', 'docs', 'book');
  const chapters = readdirSync(join(dir, 'chapters'))
    .filter((name) => name.endsWith('.md'))
    .sort()
    .map((name) => readFileSync(join(dir, 'chapters', name), 'utf8'));
  return docsShared(readFileSync(join(dir, 'index.md'), 'utf8'), chapters);
}

const words = (parts: Part[]) => parts.map((p) => p.text).join('');
const hits = (parts: Part[]) => parts.filter((p) => p.hit).map((p) => p.text);

describe("the docs' headings and sections", () => {
  const page = [
    '# Meetings',
    'Ghost can sit in on your **meetings**.',
    '',
    '## Inviting Ghost to a `Zoom` call',
    'Paste a [link](https://zoom.us) into **Invite Ghost**.',
    '',
    '```markdown',
    '## Not a heading',
    '```',
    '',
    '### Recurring',
    '- [ ] Every weekday',
    '',
    '| Kind | Where |',
    '|---|---|',
    '| Zoom | [[The Market]] |',
    '',
    '## Recurring',
    'Twice, and still a place of its own.',
  ].join('\n');

  it('gives every heading an anchor of its words, unique on the page, and passes over code', () => {
    expect(docsHeadings(page).map((h) => [h.level, h.text, h.anchor])).toEqual([
      [2, 'Inviting Ghost to a Zoom call', 'inviting-ghost-to-a-zoom-call'],
      [3, 'Recurring', 'recurring'],
      [2, 'Recurring', 'recurring-2'],
    ]);
  });

  it('cuts a page at its headings, the opening words first, as plain words', () => {
    expect(pageSections(page)).toEqual([
      { heading: null, anchor: '', text: 'Ghost can sit in on your meetings.' },
      { heading: 'Inviting Ghost to a Zoom call', anchor: 'inviting-ghost-to-a-zoom-call', text: 'Paste a link into Invite Ghost. Not a heading' },
      { heading: 'Recurring', anchor: 'recurring', text: 'Every weekday Kind Where Zoom The Market' },
      { heading: 'Recurring', anchor: 'recurring-2', text: 'Twice, and still a place of its own.' },
    ]);
    expect(plainLine('> A **bold** ==find== in [[Settings|the settings]], ~~not~~ `code` and snake_case')).toBe('A bold find in the settings, not code and snake_case');
  });

  it('indexes every section of every chapter of the real book, each at an anchor its page draws', () => {
    const book = realBook();
    const index = docsSearchIndex(book);
    // Every chapter the index names and has written, and not the index page itself.
    expect(index.pages.map((p) => p.title)).toEqual(book.pages.slice(1).map((p) => p.title));
    expect(index.pages.length).toBe(chaptersOf(book.pages[0]!.body).length);
    book.pages.slice(1).forEach((chapter, p) => {
      const headings = docsHeadings(chapter.body);
      const sections = index.sections.filter((s) => s[0] === p);
      expect(sections.filter((s) => s[1] !== null).map((s) => s[2])).toEqual(headings.map((h) => h.anchor));
      expect(new Set(headings.map((h) => h.anchor)).size).toBe(headings.length);
      // The page finds its headings again in the text it draws (reveal.ts reads its editor's), at the same anchors.
      expect(docsHeadings(drawnBody(chapter.body)).map((h) => h.anchor)).toEqual(headings.map((h) => h.anchor));
      for (const [, heading, anchor, text] of sections) {
        expect(heading === null ? anchor === '' : anchor.length > 0).toBe(true);
        expect(text).not.toMatch(/\*\*|\[\[|\]\]/);
      }
    });
    // Small: the book's words, once, and little else: less than the Markdown it was made from.
    expect(JSON.stringify(index).length).toBeLessThan(book.pages.reduce((sum, p) => sum + p.body.length, 0));
  });
});

describe("the docs' search", () => {
  it('folds case and accents one character for one, and reads a query as its words', () => {
    expect(fold('Café ÉTÉ’s')).toBe("cafe ete's");
    expect(fold('Settings › Recording').length).toBe('Settings › Recording'.length);
    expect(queryTerms('  Simple MODE, simple ')).toEqual(['simple', 'mode']);
  });

  it('finds a word only where a word starts, so "zoo" is Zoom and not kazoo', () => {
    expect(matchRanges(fold('Zoom, a kazoo and zoom again'), ['zoo'])).toEqual([
      [0, 3],
      [18, 21],
    ]);
  });

  it('cuts a snippet round what was found, marked, with … where words were cut', () => {
    const text = `${'Before the words. '.repeat(20)}Ghost joins a Zoom call as a guest. ${'After the words. '.repeat(20)}`;
    const snippet = snippetOf(text, ['zoom'], 120);
    expect(snippet[0]).toEqual({ text: '…', hit: false });
    expect(snippet.at(-1)).toEqual({ text: '…', hit: false });
    expect(hits(snippet)).toEqual(['Zoom']);
    expect(words(snippet).length).toBeLessThanOrEqual(122);
    expect(words(snippetOf('Short words, all shown.', ['short']))).toBe('Short words, all shown.');
    // Found by its heading alone: the section's first words.
    expect(words(snippetOf(text, ['nothing'], 60)).startsWith('Before the words.')).toBe(true);
  });

  const index = prepare({
    v: 1,
    pages: [
      { slug: 'zebras', title: 'Zebras' },
      { slug: 'animals', title: 'Animals' },
      { slug: 'other', title: 'Other' },
    ],
    sections: [
      [2, 'Elsewhere', 'elsewhere', 'A zebra, a zebra, a zebra and a zebra, said many times over.'],
      [1, 'Zebra crossings', 'zebra-crossings', 'Stripes on the road.'],
      [0, null, '', 'Striped horses.'],
      [2, 'Simple mode', 'simple-mode', 'What Simple shows.'],
      [2, 'Advanced', 'advanced', 'Simple is one switch, and the mode is kept.'],
    ],
  });

  it('ranks a chapter whose title has the word over a heading that has it, over words that have it', () => {
    expect(searchDocs(index, 'zebra').map((h) => h.anchor || h.slug)).toEqual(['zebras', 'zebra-crossings', 'elsewhere']);
  });

  it('needs every word, ranks them met together in a heading first, and marks them', () => {
    const found = searchDocs(index, 'simple mode');
    expect(found.map((h) => h.anchor)).toEqual(['simple-mode', 'advanced']);
    expect(hits(found[0]!.headingParts)).toEqual(['Simple', 'mode']);
    expect(searchDocs(index, 'simple zebra')).toEqual([]);
    expect(searchDocs(index, '   ')).toEqual([]);
  });

  it('finds what a reader would look for in the real book', () => {
    const real = prepare(docsSearchIndex(realBook()));
    for (const query of ['zoom', 'discord', 'simple mode', 'export', 'keyboard', 'lovart']) {
      const found = searchDocs(real, query);
      expect(found.length, query).toBeGreaterThan(0);
    }
    expect(searchDocs(real, 'lovart')[0]!.pageTitle).toBe('Lovart');
    expect(searchDocs(real, 'zoom').some((h) => /zoom/i.test(h.heading ?? ''))).toBe(true);
    expect(searchDocs(real, 'qqqzzzxxy')).toEqual([]);
  });
});
