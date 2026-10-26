import { describe, expect, it } from 'vitest';
import { chapterParts } from '../app/book/book.ts';
import { docsPages, docsPath, docsShared, docsSlugAt, docsSummary, docsTitle } from './book.ts';

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
