import { beforeEach, describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { asideContent, readAsideShown, writeAsideShown } from './aside.ts';

const BOOK = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n- [[Birds]]\n';
const notes = [makeNote('b', BOOK, { updatedAt: 5 }), makeNote('t', '# Trees\n', { updatedAt: 4 }), makeNote('x', '# Loose\n', { updatedAt: 3 }), makeNote('a', '# Archived\n', { updatedAt: 9, archivedAt: 1 })];

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
    makeNote(id, `# ${title}\n\n« [[${back}]] · next: [[09 · Something]]\n\nWords.`, { updatedAt });
  const run = [
    chapter('c10', '10 · The mount chain', 9),
    chapter('c9', '09 · In one page', 8),
    chapter('c1', '01 · Two things', 7),
    chapter('c8', '08 · The risks, and a glossary', 6),
    chapter('o1', '01 · Another book’s first', 5, 'Another book'),
    makeNote('tm', '# Task Management\n', { updatedAt: 10 }),
    makeNote('hb', '# HelloTrade — The Book\n\nThe index.', { updatedAt: 2 }),
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
    const inFolder = (id: string, title: string, path: string) => makeNote(id, `# ${title}\n\nWords.`, { updatedAt: 1, path });
    const folder = [inFolder('a', 'Arrival · Ch. 2', 'Trip/Arrival.md'), inFolder('b', 'Leaving · Ch. 1', 'Trip/Leaving.md'), inFolder('c', 'Other · Ch. 1', 'Else/Other.md')];
    const shown = asideContent(folder, folder[0]!);
    expect(shown?.kind === 'chapters' && shown.title).toBe('Trip');
    expect(shown?.kind === 'chapters' && shown.chapters.map((c) => c.id)).toEqual(['b', 'a']);
  });
});

describe('whether the aside is shown', () => {
  beforeEach(() => localStorage.clear());

  it('is hidden until it has been opened, and kept on this device', () => {
    expect(readAsideShown()).toBe(false);
    writeAsideShown(true);
    expect(readAsideShown()).toBe(true);
    writeAsideShown(false);
    expect(readAsideShown()).toBe(false);
    expect(localStorage.getItem('glyph-aside-shown')).toBe('0');
  });
});

describe('a journal’s aside', () => {
  const entry = (id: string, title: string, date: string, words: string) => makeNote(id, `---\ntitle: "${title}"\ndate: ${date}\n---\n# Day\n\n**${date.slice(11)}** ${words}`);
  const JOURNAL = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-08-30 10.00]]\n- [[2026-09-28 14.05]]\n- [[2026-09-27 21.40]]\n';
  const journalNotes = [
    makeNote('j', JOURNAL),
    entry('aug', '2026-08-30 10.00', '2026-08-30T10:00', 'August.'),
    entry('late', '2026-09-28 14.05', '2026-09-28T14:05', 'Walked.'),
    entry('early', '2026-09-27 21.40', '2026-09-27T21:40', 'Dinner.'),
  ];

  it('lists the journal’s newest month, newest first, for the journal itself', () => {
    const shown = asideContent(journalNotes, journalNotes[0]!);
    expect(shown?.kind === 'book' && shown.place.journal).toBe(true);
    if (shown?.kind !== 'book') throw new Error('no journal aside');
    expect(shown.month?.label).toBe('September 2026');
    expect(shown.month?.entries.map((e) => e.id)).toEqual(['late', 'early']);
  });

  it('lists the open entry’s own month, the entry marked', () => {
    const shown = asideContent(journalNotes, journalNotes[1]!);
    if (shown?.kind !== 'book') throw new Error('no journal aside');
    expect(shown.open).toBe('aug');
    expect(shown.month?.entries.map((e) => e.id)).toEqual(['aug']);
  });

  it('has no month for a journal with nothing written', () => {
    const empty = makeNote('e', '---\ntitle: "Log"\nbook: true\njournal: true\n---\n# Log\n\n');
    const shown = asideContent([empty], empty);
    expect(shown?.kind === 'book' && shown.month).toBeNull();
  });
});
