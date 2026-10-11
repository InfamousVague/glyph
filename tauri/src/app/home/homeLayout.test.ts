import { describe, expect, it } from 'vitest';
import { bookNoteBody } from '../book/book.ts';
import { makeNote } from '../../test/notes.ts';
import { HOME_LAYOUT_IDS } from '../core/preferences.ts';
import type { Note } from '../core/store.ts';
import { cardsIn, firstLine, HOME_LAYOUTS, homeCounts, homeLists, homePlan, kindOf, spanOf, spotlight, timeline, type HomePlan, type PlanWays } from './homeLayout.ts';

/** The home page's rules (home/homeLayout.ts; docs/DESIGN.md §147, §148): what it lists, in what order, and how each layout groups them. */

const trip = makeNote('b', bookNoteBody('Trip', ['Packing']), { updatedAt: 5 });
const packing = makeNote('p', '# Packing\n\n- [ ] Tent', { starred: true, updatedAt: 1 });
const route = makeNote('r', '# Route\n\nNorth along the coast.', { updatedAt: 4 });
const board = makeNote('c', '{"nodes":[],"edges":[]}', { updatedAt: 3 });
const gone = makeNote('g', '# Gone', { updatedAt: 9, archivedAt: 10 });
const all = [packing, trip, route, board, gone];
const ids = (notes: { id: string }[]) => notes.map((n) => n.id);

describe('what the home page lists', () => {
  it('offers the four layouts, Spotlight, the default, first, then Cards, Timeline and List (docs/DESIGN.md §178)', () => {
    expect(HOME_LAYOUTS.map((l) => l.id)).toEqual(['spotlight', 'cards', 'timeline', 'list']);
    expect([...HOME_LAYOUTS.map((l) => l.id)].sort()).toEqual([...HOME_LAYOUT_IDS].sort());
  });

  it('knows a notebook, a canvas, a voice recording and a note of words', () => {
    const spoken = makeNote('v', '# Standup', { source: 'capture', recordingMs: 40_000 });
    const removed = makeNote('x', '# Its tape removed', { source: 'capture', recordingMs: null });
    expect([trip, board, spoken, removed, route].map(kindOf)).toEqual(['book', 'canvas', 'tape', 'note', 'note']);
  });

  it('lists a voice recording as a note, in every filter a note is in', () => {
    const spoken = makeNote('v', '# Standup', { source: 'capture', recordingMs: 40_000, updatedAt: 6 });
    expect(ids(homeLists([spoken, ...all], '', 'notes').notes)).toEqual(['p', 'v', 'r', 'c']);
    expect(homeCounts([spoken, ...all])).toMatchObject({ all: 5, notes: 4 });
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
  const ways: PlanWays = { now };
  /** A plan as its sections' keys, each with how it draws and what, by id. */
  const shape = (plan: HomePlan) => plan.sections.map((s) => `${s.key} ${s.draw}: ${s.notes.map((n: Note) => n.id).join(' ')}`);

  it('lays out Cards and List as the notebooks then the notes', () => {
    expect(shape(homePlan('cards', lists, ways))).toEqual(['books cards: b', 'notes cards: s p r']);
    expect(shape(homePlan('list', lists, ways))).toEqual(['books rows: b', 'notes rows: s p r']);
  });

  it('lays out the Timeline by when, notebooks and notes together', () => {
    expect(shape(homePlan('timeline', lists, ways))).toEqual(['today rows: b s', 'yesterday rows: p', 'earlier rows: r']);
  });

  it('leads Spotlight with the four touched last, by when alone, and the rest by when', () => {
    const plan = homePlan('spotlight', homeLists([book, ...pages, shop, makeNote('x', '# Extra', { updatedAt: at(90) })], '', 'all'), ways);
    expect(shape(plan)).toEqual(['recent cards: b s p r', 'earlier rows: x']);
    expect(plan.sections[0]).toMatchObject({ heading: 'Recent', mark: 'recent', count: null });
    // A pin does not put a note in the lead: the lead is where the person was.
    const pinned = makeNote('old', '# Pinned long ago', { starred: true, updatedAt: at(300) });
    expect(spotlight(homeLists([pinned, book, ...pages, shop], '', 'all'), 4, now).lead.map((n) => n.id)).toEqual(['b', 's', 'p', 'r']);
  });

  it('heads Spotlight with the pinned notes as lines, newest first, and draws them nowhere else on it', () => {
    const pinnedBook = makeNote('pb', bookNoteBody('Recipes', []), { starred: true, updatedAt: at(5) });
    const pinnedNote = makeNote('pn', '# Passwords to change', { starred: true, updatedAt: at(0) });
    const plan = homePlan('spotlight', homeLists([book, ...pages, shop, pinnedBook, pinnedNote], '', 'all'), ways);
    expect(shape(plan)).toEqual(['pinned lines: pn pb', 'recent cards: b s p r']);
    expect(plan.sections[0]).toMatchObject({ heading: 'Pinned', mark: 'pinned', count: 2 });
    // Nothing pinned, no Pinned; only pinned (the Pinned filter), only Pinned.
    expect(shape(homePlan('spotlight', lists, ways))[0]).toBe('recent cards: b s p r');
    expect(shape(homePlan('spotlight', homeLists([book, pinnedBook, pinnedNote], '', 'pinned'), ways))).toEqual(['pinned lines: pn pb']);
    // Lines are not cards: no line under a title is written for them.
    expect(cardsIn(plan).map((n) => n.id)).toEqual(['b', 's', 'p', 'r']);
  });

  it('stops Cards at the most it may draw, and counts what it left for All notes', () => {
    const tight = { ...ways, most: 2 };
    expect(homePlan('cards', lists, tight)).toMatchObject({ cut: 1 });
    expect(shape(homePlan('cards', lists, tight))).toEqual(['books cards: b', 'notes cards: s p']);
    // Rows are cheap, and never stop.
    expect(homePlan('timeline', lists, tight).cut).toBe(0);
    expect(homePlan('list', lists, tight).cut).toBe(0);
  });

  it('draws no empty section, and names every card in the page’s order', () => {
    const books = homeLists([book, ...pages, shop], '', 'books');
    expect(shape(homePlan('cards', books, ways))).toEqual(['books cards: b']);
    expect(cardsIn(homePlan('cards', lists, ways)).map((n) => n.id)).toEqual(['b', 's', 'p', 'r']);
    expect(cardsIn(homePlan('spotlight', lists, ways)).map((n) => n.id)).toEqual(['b', 's', 'p', 'r']);
    expect(cardsIn(homePlan('list', lists, ways))).toEqual([]);
  });
});
