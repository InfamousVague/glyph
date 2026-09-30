import { describe, expect, it } from 'vitest';
import { bookNoteBody } from '../book/book.ts';
import { makeNote } from '../../test/notes.ts';
import { firstLine, HOME_LAYOUTS, homeCounts, homeLists, kindOf, library, spanOf, timeline } from './homeLayout.ts';

/** The home page's rules (home/homeLayout.ts; docs/DESIGN.md §147): what it lists, in what order, and how it groups them. */

const trip = makeNote('b', bookNoteBody('Trip', ['Packing']), { updatedAt: 5 });
const packing = makeNote('p', '# Packing\n\n- [ ] Tent', { starred: true, updatedAt: 1 });
const route = makeNote('r', '# Route\n\nNorth along the coast.', { updatedAt: 4 });
const board = makeNote('c', '{"nodes":[],"edges":[]}', { updatedAt: 3 });
const gone = makeNote('g', '# Gone', { updatedAt: 9, archivedAt: 10 });
const all = [packing, trip, route, board, gone];
const ids = (notes: { id: string }[]) => notes.map((n) => n.id);

describe('what the home page lists', () => {
  it('offers five layouts, Cards first', () => {
    expect(HOME_LAYOUTS.map((l) => l.id)).toEqual(['cards', 'list', 'shelf', 'library', 'timeline']);
  });

  it('knows a notebook, a canvas and a note of words', () => {
    expect([trip, board, route].map(kindOf)).toEqual(['book', 'canvas', 'note']);
  });

  it('puts the notebooks apart from the notes, pinned first and then newest, and never the archive', () => {
    const lists = homeLists(all, '', 'all');
    expect(ids(lists.books)).toEqual(['b']);
    expect(ids(lists.notes)).toEqual(['p', 'r', 'c']);
  });

  it('filters to notebooks, notes or the pinned, and narrows to the search', () => {
    expect(homeLists(all, '', 'books').notes).toEqual([]);
    expect(homeLists(all, '', 'notes').books).toEqual([]);
    expect(ids(homeLists(all, '', 'pinned').notes)).toEqual(['p']);
    expect(ids(homeLists(all, 'coast', 'all').notes)).toEqual(['r']);
    expect(homeLists(all, 'gone', 'all').notes).toEqual([]);
  });

  it('counts each filter, leaving out the archive and never the search', () => {
    expect(homeCounts(all)).toEqual({ all: 4, books: 1, notes: 3, pinned: 1 });
  });
});

describe('how a note starts, on one line', () => {
  it('is its first words under the title, the line marks taken off', () => {
    expect(firstLine('# Packing\n\n- [ ] **Tent** and `stove`')).toBe('Tent and stove');
    expect(firstLine('---\ntitle: "Trip"\n---\n# Trip\n\n> Go north')).toBe('Go north');
    expect(firstLine('# Only a title')).toBe('');
  });

  it('is cut with an ellipsis past the most it may be', () => {
    expect(firstLine(`# T\n\n${'word '.repeat(40)}`, 20)).toBe('word word word word…');
  });
});

describe('the timeline', () => {
  const now = new Date(2026, 8, 30, 15, 0).getTime();
  const at = (days: number, hour = 9) => new Date(2026, 8, 30 - days, hour, 0).getTime();

  it('says which span a moment falls in, by this device’s days', () => {
    expect([at(0), at(1, 23), at(3), at(20), at(40)].map((t) => spanOf(t, now))).toEqual(['today', 'yesterday', 'week', 'month', 'earlier']);
  });

  it('groups notebooks and notes together, newest first, and leaves out an empty span', () => {
    const lists = { books: [makeNote('b', bookNoteBody('Trip', []), { updatedAt: at(1) })], notes: [makeNote('n', '# Now', { updatedAt: at(0) }), makeNote('o', '# Old', { updatedAt: at(40) })] };
    expect(timeline(lists, now).map(({ span, notes }) => [span, ids(notes)])).toEqual([
      ['today', ['n']],
      ['yesterday', ['b']],
      ['earlier', ['o']],
    ]);
  });
});

describe('the library', () => {
  it('opens each notebook over its pages, and lists only the notes in no notebook after them', () => {
    const lists = homeLists(all, '', 'all');
    const shelves = library(
      lists,
      (book) => (book.id === 'b' ? [packing] : []),
      (note) => (note.id === 'p' ? { book: trip, title: 'Trip', chapters: [], at: 0, journal: false } : null),
    );
    expect(shelves.books.map(({ book, pages }) => [book.id, ids(pages)])).toEqual([['b', ['p']]]);
    expect(ids(shelves.loose)).toEqual(['r', 'c']);
  });
});
