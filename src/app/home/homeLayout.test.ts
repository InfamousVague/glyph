import { describe, expect, it } from 'vitest';
import { bookNoteBody } from '../book/book.ts';
import { makeNote } from '../../test/notes.ts';
import { HOME_LAYOUT_IDS } from '../core/preferences.ts';
import type { Note } from '../core/store.ts';
import { cardsIn, firstLine, HOME_LAYOUTS, homeCounts, homeLists, homePlan, isBookSection, kindOf, spanOf, spotlight, timeline, type HomePlan, type PlanWays } from './homeLayout.ts';

/** The home page's rules (home/homeLayout.ts; docs/DESIGN.md §147, §148): what it lists, in what order, and how each layout groups them. */

const trip = makeNote('b', bookNoteBody('Trip', ['Packing']), { updatedAt: 5 });
const packing = makeNote('p', '# Packing\n\n- [ ] Tent', { starred: true, updatedAt: 1 });
const route = makeNote('r', '# Route\n\nNorth along the coast.', { updatedAt: 4 });
const board = makeNote('c', '{"nodes":[],"edges":[]}', { updatedAt: 3 });
const gone = makeNote('g', '# Gone', { updatedAt: 9, archivedAt: 10 });
const all = [packing, trip, route, board, gone];
const ids = (notes: { id: string }[]) => notes.map((n) => n.id);

describe('what the home page lists', () => {
  it('offers every layout the preference knows, Cards and Timeline first, then their mixes, then the rest', () => {
    expect(HOME_LAYOUTS.map((l) => l.id)).toEqual(['cards', 'timeline', 'card-timeline', 'spotlight', 'shelf-timeline', 'notebook-cards', 'list', 'shelf', 'library']);
    expect([...HOME_LAYOUTS.map((l) => l.id)].sort()).toEqual([...HOME_LAYOUT_IDS].sort());
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

describe('each layout’s sections', () => {
  const now = new Date(2026, 8, 30, 15, 0).getTime();
  const at = (days: number) => now - days * 24 * 60 * 60 * 1000 - 60_000;
  const book = makeNote('b', bookNoteBody('Trip', ['Packing', 'Route']), { updatedAt: at(0) });
  const pages = [makeNote('p', '# Packing', { updatedAt: at(1) }), makeNote('r', '# Route\n\nAlong the coast.', { updatedAt: at(40) })];
  const shop = makeNote('s', '# Shopping', { updatedAt: at(0) - 60_000 });
  const lists = homeLists([book, ...pages, shop], '', 'all');
  const ways: PlanWays = {
    pagesOf: (b) => (b.id === 'b' ? pages : []),
    placeOf: (n) => (n.id === 'p' || n.id === 'r' ? { book, title: 'Trip', chapters: [], at: 0, journal: false } : null),
    now,
  };
  /** A plan as its sections' keys, each with how it draws and what, by id. */
  const shape = (plan: HomePlan) => plan.sections.map((s) => `${s.key} ${s.draw}: ${s.notes.map((n: Note) => n.id).join(' ')}`);

  it('lays out Cards and List as the notebooks then the notes, and the Shelf with covers', () => {
    expect(shape(homePlan('cards', lists, ways))).toEqual(['books cards: b', 'notes cards: s p r']);
    expect(shape(homePlan('list', lists, ways))).toEqual(['books rows: b', 'notes rows: s p r']);
    expect(shape(homePlan('shelf', lists, ways))).toEqual(['books covers: b', 'notes dense: s p r']);
  });

  it('lays out the Timeline and the Card timeline by when, notebooks and notes together', () => {
    expect(shape(homePlan('timeline', lists, ways))).toEqual(['today rows: b s', 'yesterday rows: p', 'earlier rows: r']);
    expect(shape(homePlan('card-timeline', lists, ways))).toEqual(['today cards: b s', 'yesterday cards: p', 'earlier cards: r']);
  });

  it('leads Spotlight with the four touched last, by when alone, and the rest by when', () => {
    const plan = homePlan('spotlight', homeLists([book, ...pages, shop, makeNote('x', '# Extra', { updatedAt: at(90) })], '', 'all'), ways);
    expect(shape(plan)).toEqual(['recent cards: b s p r', 'earlier rows: x']);
    expect(plan.sections[0]).toMatchObject({ heading: 'Recent', mark: 'recent', count: null });
    // A pin does not put a note in the lead: the lead is where the person was.
    const pinned = makeNote('old', '# Pinned long ago', { starred: true, updatedAt: at(300) });
    expect(spotlight(homeLists([pinned, book, ...pages, shop], '', 'all'), 4, now).lead.map((n) => n.id)).toEqual(['b', 's', 'p', 'r']);
  });

  it('puts the Shelf and timeline’s notebooks on the shelf and only the notes on the timeline', () => {
    expect(shape(homePlan('shelf-timeline', lists, ways))).toEqual(['books covers: b', 'today rows: s', 'yesterday rows: p', 'earlier rows: r']);
  });

  it('opens each notebook over its pages in the Library, as rows, and as cards in Notebook cards, then the notes in no notebook', () => {
    const library = homePlan('library', lists, ways);
    expect(shape(library)).toEqual(['book-b rows: p r', 'loose rows: s']);
    expect(library.sections.map((s) => isBookSection(s))).toEqual([true, false]);
    expect(library.sections[1]).toMatchObject({ heading: 'In no notebook' });
    expect(shape(homePlan('notebook-cards', lists, ways))).toEqual(['book-b cards: p r', 'loose cards: s']);
    // With no notebook to be in, the loose notes are just the notes.
    expect(homePlan('library', homeLists([shop], '', 'all'), ways).sections[0]).toMatchObject({ heading: 'Notes' });
  });

  it('stops the card layouts at the most they may draw, and counts what it left for All notes', () => {
    const tight = { ...ways, most: 2 };
    expect(homePlan('cards', lists, tight)).toMatchObject({ cut: 1 });
    expect(shape(homePlan('card-timeline', lists, tight))).toEqual(['today cards: b s']);
    expect(homePlan('card-timeline', lists, tight).cut).toBe(2);
    // A span cut short still says how many it holds.
    expect(homePlan('card-timeline', lists, { ...ways, most: 1 }).sections[0]).toMatchObject({ count: 2, notes: [book] });
    // Notebook cards spends the budget notebook by notebook, and says how many pages it did not draw.
    const cards = homePlan('notebook-cards', lists, { ...ways, most: 1 });
    expect(shape(cards)).toEqual(['book-b cards: p']);
    expect(cards.sections[0]).toMatchObject({ count: 2, more: 1 });
    expect(cards.cut).toBe(1);
    // Rows are cheap, and never stop.
    expect(homePlan('timeline', lists, tight).cut).toBe(0);
    // Its budget spent, a notebook draws none of its pages and offers them all in the notebook.
    const spent = homePlan('notebook-cards', lists, { ...ways, most: 0 });
    expect(spent.sections[0]).toMatchObject({ key: 'book-b', notes: [], more: 2 });
  });

  it('draws a page whose notebook the search or the filter left out among the other notes, never nowhere', () => {
    const route = pages[1]!;
    for (const layout of ['library', 'notebook-cards'] as const) {
      // Only a page matches the search (the notebook names it, but not its coast): it is drawn, under Notes.
      const found = homePlan(layout, homeLists([book, ...pages, shop], 'coast', 'all'), ways);
      expect(shape(found).map((s) => s.split(':')[1])).toEqual([' r']);
      expect(found.sections[0]).toMatchObject({ heading: 'Notes' });
      // The Notes filter: every note, the pages among them.
      expect(homePlan(layout, homeLists([book, ...pages, shop], '', 'notes'), ways).sections.flatMap((s) => s.notes.map((n) => n.id))).toEqual(['s', 'p', 'r']);
    }
    // A notebook drawn, and a page of another the search left out: the page is one of the other notes.
    const other = makeNote('b2', bookNoteBody('Other trip', ['Route']), { updatedAt: at(0) });
    const onlyRoute = { ...ways, pagesOf: (b: Note) => (b.id === 'b2' ? [route] : []), placeOf: (n: Note) => (n.id === 'p' ? { book, title: 'Trip', chapters: [], at: 0, journal: false } : null) };
    const plan = homePlan('library', { books: [other], notes: [pages[0]!] }, onlyRoute);
    expect(plan.sections.map((s) => ('heading' in s ? s.heading : s.key))).toEqual(['book-b2', 'Other notes']);
  });

  it('draws a page once however often its notebook names it, and a journal newest first', () => {
    const twice = homePlan('library', lists, { ...ways, pagesOf: () => [pages[0]!, pages[0]!, pages[1]!] });
    expect(shape(twice)[0]).toBe('book-b rows: p r');
    expect(twice.sections[0]).toMatchObject({ count: 2 });
    const diary = makeNote('d', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n', { updatedAt: at(0) });
    const entry = (id: string, date: string) => makeNote(id, `---\ntitle: "${id}"\ndate: ${date}\n---\nWords.`, { updatedAt: at(0) });
    // The index in the order they were added: the oldest first.
    const entries = [entry('e1', '2026-09-10T09:00'), entry('e2', '2026-09-20T09:00'), entry('e3', '2026-09-29T09:00')];
    const journal = homePlan('notebook-cards', { books: [diary], notes: [] }, { ...ways, pagesOf: () => entries });
    expect(shape(journal)).toEqual(['book-d cards: e3 e2 e1']);
  });

  it('draws no empty section, and names every card in the page’s order', () => {
    const books = homeLists([book, ...pages, shop], '', 'books');
    expect(shape(homePlan('cards', books, ways))).toEqual(['books cards: b']);
    expect(cardsIn(homePlan('shelf', lists, ways)).map((n) => n.id)).toEqual(['s', 'p', 'r']);
    expect(cardsIn(homePlan('spotlight', lists, ways)).map((n) => n.id)).toEqual(['b', 's', 'p', 'r']);
  });
});
