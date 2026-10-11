import { afterEach, describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { archivedCount, browseNotes, hasTape, matches, readSort, tapeCount, writeSort } from './allNotes.ts';

afterEach(() => localStorage.clear());

describe('what the search finds', () => {
  it('finds every word typed, anywhere in the note, whatever the case', () => {
    const packing = makeNote('a', '# Trip\n\nPacking: tent, stove');
    expect(matches(packing, 'trip packing')).toBe(true);
    expect(matches(packing, 'TENT')).toBe(true);
    expect(matches(packing, 'tent kettle')).toBe(false);
  });

  it('finds a filled answer by its words and a blank by its question, never by the hidden bracket (docs/DESIGN.md §145)', () => {
    const filled = makeNote('a', '# Tokyo trip\n\nFlights are cheapest on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)\n\nWeather: {?weather today}');
    expect(matches(filled, 'midweek')).toBe(true);
    expect(matches(filled, 'weather today')).toBe(true);
    expect(matches(filled, 'memory')).toBe(false);
    expect(matches(filled, 'asked')).toBe(false);
    expect(matches(filled, 'qwen3.5')).toBe(false);
    expect(matches(makeNote('b', 'A ??doubt??(check with Sam)'), 'sam')).toBe(true);
  });

  it('finds a to-do’s priority by its name, and its person and day as written (docs/DESIGN.md §158)', () => {
    const sprint = makeNote('a', '# Sprint\n\n- [ ] Fix the login loop @sam ⏫ 📅 2026-10-03\n- [ ] Tidy up 🔽');
    expect(matches(sprint, 'high priority')).toBe(true);
    expect(matches(sprint, 'login high')).toBe(true);
    expect(matches(sprint, 'low')).toBe(true);
    expect(matches(sprint, 'lowest')).toBe(false);
    expect(matches(sprint, 'sam 2026-10-03')).toBe(true);
    expect(matches(makeNote('b', 'Inline code `⏫` is not a priority'), 'high')).toBe(false);
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
    expect(browseNotes(notes, { query: '', sort: 'newest', archived: false, tapes: false }).map((n) => n.id)).toEqual(['new', 'blank', 'old']);
    expect(browseNotes(notes, { query: '', sort: 'newest', archived: true, tapes: false }).map((n) => n.id)).toEqual(['gone', 'new', 'blank', 'old']);
  });

  it('orders by name whatever the case, with a nameless note after every name', () => {
    expect(browseNotes(notes, { query: '', sort: 'title', archived: true, tapes: false }).map((n) => n.id)).toEqual(['new', 'gone', 'old', 'blank']);
  });

  it('narrows to the search first', () => {
    expect(browseNotes(notes, { query: 'mango', sort: 'newest', archived: false, tapes: false })).toEqual([]);
    expect(browseNotes(notes, { query: 'mango', sort: 'newest', archived: true, tapes: false }).map((n) => n.id)).toEqual(['gone']);
  });

  it('does not reorder the notes it was given', () => {
    const ids = notes.map((n) => n.id);
    browseNotes(notes, { query: '', sort: 'title', archived: true, tapes: false });
    expect(notes.map((n) => n.id)).toEqual(ids);
  });

  it('counts the archive', () => {
    expect(archivedCount(notes)).toBe(1);
    expect(archivedCount([])).toBe(0);
  });
});

describe('the tapes', () => {
  const notes = [
    makeNote('spoken', '# Spoken', { source: 'capture', recordingMs: 40_000, updatedAt: 4 }),
    makeNote('typed', '# Typed then spoken', { source: 'editor', recordingMs: 12_000, updatedAt: 3 }),
    makeNote('plain', '# Plain', { updatedAt: 2 }),
    makeNote('removed', '# Removed', { source: 'capture', recordingMs: null, updatedAt: 1 }),
    makeNote('gone', '# Gone', { source: 'capture', recordingMs: 9_000, updatedAt: 5, archivedAt: 6 }),
  ];

  it('shows only the notes with a recording when asked, typed ones included, and the archive still only when asked', () => {
    expect(browseNotes(notes, { query: '', sort: 'newest', archived: false, tapes: true }).map((n) => n.id)).toEqual(['spoken', 'typed']);
    expect(browseNotes(notes, { query: '', sort: 'newest', archived: true, tapes: true }).map((n) => n.id)).toEqual(['gone', 'spoken', 'typed']);
    expect(browseNotes(notes, { query: 'typed', sort: 'newest', archived: false, tapes: true }).map((n) => n.id)).toEqual(['typed']);
  });

  it('knows a tape by its recording, and counts them', () => {
    expect(notes.map(hasTape)).toEqual([true, true, false, false, true]);
    expect(tapeCount(notes)).toBe(3);
    expect(tapeCount(notes.filter((n) => !n.archivedAt))).toBe(2);
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
