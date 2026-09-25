import { afterEach, describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { archivedCount, browseNotes, matches, readSort, writeSort } from './allNotes.ts';

afterEach(() => localStorage.clear());

describe('what the search finds', () => {
  it('finds every word typed, anywhere in the note, whatever the case', () => {
    const packing = makeNote('a', '# Trip\n\nPacking: tent, stove');
    expect(matches(packing, 'trip packing')).toBe(true);
    expect(matches(packing, 'TENT')).toBe(true);
    expect(matches(packing, 'tent kettle')).toBe(false);
  });

  it('shows every note for a blank search', () => {
    expect(matches(makeNote('a', '# Trip'), '')).toBe(true);
    expect(matches(makeNote('a', '# Trip'), '   ')).toBe(true);
  });
});

describe('the order and the archive', () => {
  const notes = [
    makeNote('old', '# Zebra', { updatedAt: 1 }),
    makeNote('new', '# apple', { updatedAt: 3 }),
    makeNote('blank', '', { updatedAt: 2 }),
    makeNote('gone', '# Mango', { updatedAt: 4, archivedAt: 5 }),
  ];

  it('puts the last touched first, and keeps the archive out unless asked', () => {
    expect(browseNotes(notes, { query: '', sort: 'newest', archived: false }).map((n) => n.id)).toEqual(['new', 'blank', 'old']);
    expect(browseNotes(notes, { query: '', sort: 'newest', archived: true }).map((n) => n.id)).toEqual(['gone', 'new', 'blank', 'old']);
  });

  it('orders by name whatever the case, with a nameless note after every name', () => {
    expect(browseNotes(notes, { query: '', sort: 'title', archived: true }).map((n) => n.id)).toEqual(['new', 'gone', 'old', 'blank']);
  });

  it('narrows to the search first', () => {
    expect(browseNotes(notes, { query: 'mango', sort: 'newest', archived: false })).toEqual([]);
    expect(browseNotes(notes, { query: 'mango', sort: 'newest', archived: true }).map((n) => n.id)).toEqual(['gone']);
  });

  it('does not reorder the notes it was given', () => {
    const ids = notes.map((n) => n.id);
    browseNotes(notes, { query: '', sort: 'title', archived: true });
    expect(notes.map((n) => n.id)).toEqual(ids);
  });

  it('counts the archive', () => {
    expect(archivedCount(notes)).toBe(1);
    expect(archivedCount([])).toBe(0);
  });
});

describe('the order kept on the device', () => {
  it('is newest first until another is chosen, and only ever one of the two', () => {
    expect(readSort()).toBe('newest');
    writeSort('title');
    expect(readSort()).toBe('title');
    localStorage.setItem('glyph-all-notes-sort', 'sideways');
    expect(readSort()).toBe('newest');
  });
});
