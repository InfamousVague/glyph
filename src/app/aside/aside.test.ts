import { describe, expect, it } from 'vitest';
import type { Note } from '../core/store.ts';
import { asideContent } from './aside.ts';

const note = (id: string, body: string, updatedAt = 1, extra: Partial<Note> = {}): Note => ({ id, body, createdAt: 0, updatedAt, source: 'editor', ...extra });
const BOOK = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n- [[Birds]]\n';
const notes = [note('b', BOOK, 5), note('t', '# Trees\n', 4), note('x', '# Loose\n', 3), note('a', '# Archived\n', 9, { archivedAt: 1 })];

describe('what the aside shows', () => {
  it('shows a page’s book with the page marked, and the book’s own index with none', () => {
    const page = asideContent(notes, notes[1]!);
    expect(page?.kind).toBe('book');
    if (page?.kind === 'book') {
      expect(page.place.title).toBe('Field guide');
      expect(page.place.chapters.map((c) => c.title)).toEqual(['Trees', 'Birds']);
      expect(page.open).toBe('t');
    }
    const book = asideContent(notes, notes[0]!);
    expect(book?.kind === 'book' && book.place.at).toBe(-1);
    expect(book?.kind === 'book' && book.open).toBeNull();
  });

  it('shows nothing for a note in no book and with no number, or for the home page', () => {
    expect(asideContent(notes, notes[2]!)).toBeNull();
    expect(asideContent(notes, null)).toBeNull();
  });

  // Chapters saved in whatever order, each pointing back at a book that isn't a note marked as one.
  const chapter = (id: string, title: string, updatedAt: number, back = 'HelloTrade — The Book') =>
    note(id, `# ${title}\n\n« [[${back}]] · next: [[09 · Something]]\n\nWords.`, updatedAt);
  const run = [
    chapter('c10', '10 · The mount chain', 9),
    chapter('c9', '09 · In one page', 8),
    chapter('c1', '01 · Two things', 7),
    chapter('c8', '08 · The risks, and a glossary', 6),
    chapter('o1', '01 · Another book’s first', 5, 'Another book'),
    note('tm', '# Task Management\n', 10),
    note('hb', '# HelloTrade — The Book\n\nThe index.', 2),
  ];

  it('lays out a numbered chapter’s run in number order when there is no book, the open one marked', () => {
    const shown = asideContent(run, run[3]!);
    expect(shown?.kind).toBe('chapters');
    if (shown?.kind !== 'chapters') return;
    expect(shown.title).toBe('HelloTrade — The Book');
    expect(shown.titleId).toBe('hb');
    expect(shown.chapters.map((c) => [c.number, c.name])).toEqual([
      [1, 'Two things'],
      [8, 'The risks, and a glossary'],
      [9, 'In one page'],
      [10, 'The mount chain'],
    ]);
    expect(shown.open).toBe('c8');
  });

  it('keeps a run to the chapters that point at the same note, and shows nothing for a chapter on its own', () => {
    expect(asideContent(run, run[4]!)).toBeNull();
  });

  it('groups chapters with no link by their folder, named after it', () => {
    const inFolder = (id: string, title: string, path: string) => note(id, `# ${title}\n\nWords.`, 1, { path });
    const folder = [inFolder('a', 'Arrival · Ch. 2', 'Trip/Arrival.md'), inFolder('b', 'Leaving · Ch. 1', 'Trip/Leaving.md'), inFolder('c', 'Other · Ch. 1', 'Else/Other.md')];
    const shown = asideContent(folder, folder[0]!);
    expect(shown?.kind === 'chapters' && shown.title).toBe('Trip');
    expect(shown?.kind === 'chapters' && shown.chapters.map((c) => c.id)).toEqual(['b', 'a']);
  });
});
