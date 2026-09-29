import { beforeEach, describe, expect, it } from 'vitest';
import { createNote, getNote } from '../core/store.ts';
import { withChapterRenamed } from './book.ts';
import { followRename } from './followRename.ts';

const BOOK = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n1. [[Introduction]]\n2. [[Trees#Oaks]] the long one\n3. [[Birds|the birds]]\n\nMore in [[Trees]] as it grows.\n';

describe('a chapter renamed in its index', () => {
  it('names the new title on its line, its heading, alias and words kept, and leaves links in passing alone', () => {
    const renamed = withChapterRenamed(BOOK, 'Trees', 'Woodland');
    expect(renamed).toContain('2. [[Woodland#Oaks]] the long one');
    expect(renamed).toContain('More in [[Trees]] as it grows.');
    expect(withChapterRenamed(BOOK, 'birds', 'Garden birds')).toContain('3. [[Garden birds|the birds]]');
    expect(withChapterRenamed(BOOK, 'Trees', '  ')).toBe(BOOK);
  });
});

describe('a page renamed keeps its place', () => {
  beforeEach(() => localStorage.clear());

  it('in every notebook and journal that lists it', async () => {
    await createNote('book', BOOK);
    await createNote('journal', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[Introduction]]\n');
    await createNote('page', '# Introduction\n\nWhy this guide.');
    expect(await followRename('page', 'Introduction', 'Before you start')).toBe(2);
    expect((await getNote('book'))!.body).toContain('1. [[Before you start]]');
    expect((await getNote('journal'))!.body).toContain('- [[Before you start]]');
  });

  it('never while another note still has the old title: the line means that one', async () => {
    await createNote('book', BOOK);
    await createNote('page', '# Introduction\n\nMine.');
    await createNote('other', '# Introduction\n\nTheirs.');
    expect(await followRename('page', 'Introduction', 'Before you start')).toBe(0);
    expect((await getNote('book'))!.body).toContain('1. [[Introduction]]');
  });
});
