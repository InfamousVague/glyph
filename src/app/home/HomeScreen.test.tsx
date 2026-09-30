import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import { bookNoteBody } from '../book/book.ts';
import type { Updates } from '../core/ota.ts';
import { reloadPreferences, setPreferences, type HomeLayout } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace, fileNote } from '../core/workspaces.ts';
import type { Note } from '../core/store.ts';
import { makeNote } from '../../test/notes.ts';
import { button, rerender, show, typeInto, unmount } from '../../test/render.tsx';
import { stubMatchMedia, stubResizeObserver } from '../../test/stubs.ts';

/**
 * The home page as a person reads it (docs/DESIGN.md §147): the search and the filter over the notebooks and the notes,
 * the five layouts Settings offers, the empty page, the way to All notes, and the dock. What the page lists and in what
 * order is home/homeLayout.ts's, tested there.
 */

// A card's small drawing is the editor (notes/NotePeek.tsx), which is nothing the page decides.
vi.mock('../notes/NotePeek.tsx', () => ({ NotePeek: () => null }));
// The glide back to the top asks whether motion is reduced; jsdom has no matchMedia.
stubMatchMedia();
const { HomeScreen } = await import('./HomeScreen.tsx');

// The page's wisp watches the bar's size; jsdom lays nothing out, so nothing ever resizes.
stubResizeObserver();

const updates = { ready: null, apk: { kind: 'none' }, checking: false, lastError: null, lastChecked: null, status: null, build: 'b', version: 'v', check: () => undefined, reload: () => undefined, installApk: () => undefined } as Updates;
type Props = ComponentProps<typeof HomeScreen>;
const page = (notes: Note[], over: Partial<Props> = {}) => (
  <HomeScreen
    notes={notes}
    loading={false}
    onOpen={() => undefined}
    onNew={() => undefined}
    onCapture={() => undefined}
    onSettings={() => undefined}
    onAllNotes={() => undefined}
    voiceModel={{ kind: 'ready' }}
    onRetryVoiceModel={() => undefined}
    updates={updates}
    {...over}
  />
);

/** The section headings, by their words without the count. */
const headings = () => [...document.querySelectorAll('h2')].map((h) => h.querySelector('span')?.textContent);
/** What a section lists, by each note's title: a card's, a row's or a cover's, never a notebook card's own list of pages. */
const listed = (heading: string) => {
  const section = [...document.querySelectorAll('section')].find((s) => s.querySelector('h2 span')?.textContent === heading);
  return [...(section?.querySelectorAll(':scope > :is(ol, ul) > li') ?? [])].map((li) => li.querySelector('[class*=title], [class*=Title]')?.textContent);
};
const filters = () => [...document.querySelectorAll('[aria-label="Show"] [role="radio"]')].map((r) => `${r.textContent}${r.getAttribute('aria-checked') === 'true' ? ' (on)' : ''}`);
const search = (words: string) => typeInto(document.querySelector<HTMLInputElement>('input[type="search"]')!, words);
const laidOut = (layout: HomeLayout) => act(() => setPreferences({ homeLayout: layout }));

const trip = makeNote('b', bookNoteBody('Trip', ['Packing', 'Route']), { updatedAt: 5 });
const packing = makeNote('p', '# Packing\n\n- [ ] Tent and stove', { starred: true, updatedAt: 3 });
const route = makeNote('r', '# Route\n\nNorth along the coast road.', { updatedAt: 4 });
const loose = makeNote('l', '# Shopping\n\nMilk, bread.', { updatedAt: 2 });
const shelf = [trip, packing, route, loose];

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
});
afterEach(() => unmount());

describe('the home page', () => {
  it('is the search, the filter, and the notebooks then the notes, pinned first, as cards', () => {
    show(page(shelf));
    expect(document.querySelector('input[type="search"]')?.getAttribute('placeholder')).toBe('Search notebooks and notes');
    expect(filters()).toEqual(['All4 (on)', 'Notebooks1', 'Notes3', 'Pinned1']);
    expect(headings()).toEqual(['Notebooks', 'Notes']);
    expect(listed('Notebooks')).toEqual(['Trip']);
    expect(listed('Notes')).toEqual(['Packing', 'Route', 'Shopping']);
    // No digest, no To do, no shelf of tapes.
    expect(document.querySelector('button[aria-label^="Tick off "]')).toBeNull();
    expect(document.querySelector('ol[aria-label="Tapes"]')).toBeNull();
  });

  it('narrows to what the search finds, says when it finds nothing, and clears', () => {
    show(page(shelf));
    search('coast');
    expect(headings()).toEqual(['Notes']);
    expect(listed('Notes')).toEqual(['Route']);
    search('kayak');
    expect(headings()).toEqual([]);
    expect(document.body.textContent).toContain('Nothing has “kayak”.');
    act(() => button('Clear the search').click());
    expect(headings()).toEqual(['Notebooks', 'Notes']);
  });

  it('shows only notebooks, only notes, or only what is pinned', () => {
    show(page(shelf));
    act(() => button('Notebooks1').click());
    expect(headings()).toEqual(['Notebooks']);
    act(() => button('Notes3').click());
    expect(headings()).toEqual(['Notes']);
    act(() => button('Pinned1').click());
    expect(listed('Notes')).toEqual(['Packing']);
    expect(filters()).toContain('Pinned1 (on)');
  });

  it('draws the List as one row each, with how a note starts and the notebook it is in', () => {
    show(page(shelf));
    laidOut('list');
    expect(document.querySelector('[data-layout="list"]')).not.toBeNull();
    const rows = [...document.querySelectorAll('section li button')].map((b) => b.textContent);
    expect(rows[0]).toContain('2 pages');
    expect(rows[1]).toContain('Tent and stove');
    expect(rows[1]).toContain('Trip');
    expect(rows[3]).toContain('Milk, bread.');
  });

  it('draws the Shelf as covers for the notebooks and small cards for the notes', () => {
    show(page(shelf));
    laidOut('shelf');
    const covers = [...document.querySelectorAll('ol[aria-label="Notebooks"] button')].map((b) => b.textContent);
    expect(covers).toHaveLength(1);
    expect(covers[0]).toContain('Trip');
    expect(covers[0]).toContain('2 pages');
    expect(listed('Notes')).toEqual(['Packing', 'Route', 'Shopping']);
  });

  it('draws the Library as each notebook over its pages, then the notes in no notebook', () => {
    const onOpen = vi.fn();
    show(page(shelf, { onOpen }));
    laidOut('library');
    const tripSection = document.querySelector('section[aria-label="Trip"]')!;
    expect([...tripSection.querySelectorAll('li')].map((li) => li.querySelector('[class*=rowTitle]')?.textContent)).toEqual(['Packing', 'Route']);
    expect(headings()).toEqual(['In no notebook']);
    expect(listed('In no notebook')).toEqual(['Shopping']);
    act(() => tripSection.querySelector<HTMLButtonElement>('button')!.click());
    expect(onOpen).toHaveBeenLastCalledWith('b');
  });

  it('draws the Timeline by when each was last touched', () => {
    const now = Date.now();
    const day = 24 * 60 * 60 * 1000;
    show(page([makeNote('t', '# Fresh', { updatedAt: now }), makeNote('o', '# Stale', { updatedAt: now - 90 * day })]));
    laidOut('timeline');
    expect(headings()).toEqual(['Today', 'Earlier']);
    expect(listed('Today')).toEqual(['Fresh']);
    expect(listed('Earlier')).toEqual(['Stale']);
  });

  it('counts a journal’s entries on its row, whichever workspace each was made in', () => {
    const work = addWorkspace('Work')!;
    const home = addWorkspace('Home')!;
    const journal = makeNote('diary', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-09-27 21.40]]\n- [[2026-09-28 14.05]]\n', { updatedAt: 3 });
    const entry = (title: string, date: string) => makeNote(title, `---\ntitle: "${title}"\ndate: ${date}\n---\nWords.`, { updatedAt: 1 });
    fileNote('diary', work.id);
    fileNote('2026-09-27 21.40', work.id);
    fileNote('2026-09-28 14.05', home.id);
    chooseWorkspace(work.id);
    setPreferences({ homeLayout: 'list' });
    show(page([journal, entry('2026-09-27 21.40', '2026-09-27T21:40'), entry('2026-09-28 14.05', '2026-09-28T14:05')]));
    const diary = [...document.querySelectorAll('section li button')].find((b) => b.textContent?.includes('Diary'))!;
    expect(diary.textContent).toContain('2 entries');
  });

  it('lists only the chosen workspace’s notes', () => {
    const kitchen = addWorkspace('Kitchen')!;
    fileNote('in', kitchen.id);
    chooseWorkspace(kitchen.id);
    show(page([makeNote('in', '# Kitchen list', { updatedAt: 2 }), makeNote('out', '# Elsewhere', { updatedAt: 3 })]));
    expect(listed('Notes')).toEqual(['Kitchen list']);
    expect(filters()[0]).toBe('All1 (on)');
  });

  it('is a blank page with nothing written, and says which workspace is empty when one is chosen', () => {
    show(page([]));
    expect(document.body.textContent).toContain('A blank page.');
    expect(document.body.textContent).toContain('Write it, or tap Speak and say it.');
    expect(document.querySelector('[aria-label="Show"]')).toBeNull();
    unmount();
    const kitchen = addWorkspace('Kitchen')!;
    chooseWorkspace(kitchen.id);
    show(page([makeNote('a', '# Elsewhere')]));
    expect(document.body.textContent).toContain('Nothing in Kitchen yet.');
  });

  it('draws nothing of the empty page while the notes are still being read', () => {
    show(page([], { loading: true }));
    expect(document.body.textContent).not.toContain('A blank page.');
  });

  it('opens a note, and counts every note left out of the archive for All notes', () => {
    const onOpen = vi.fn();
    const onAllNotes = vi.fn();
    show(page([makeNote('a', '# Shop'), makeNote('z', '# Old', { archivedAt: 1 })], { onOpen, onAllNotes }));
    act(() => [...document.querySelectorAll<HTMLButtonElement>('ol li button')].find((b) => b.textContent?.includes('Shop'))!.click());
    expect(onOpen).toHaveBeenLastCalledWith('a');
    act(() => button('All notes · 1').click());
    expect(onAllNotes).toHaveBeenCalledTimes(1);
  });

  it('draws forty-eight cards at most, and sends the rest to All notes', () => {
    show(page(Array.from({ length: 50 }, (_, i) => makeNote(`n${i}`, `# Note ${i}`, { updatedAt: i + 1 }))));
    expect(listed('Notes')).toHaveLength(48);
    expect(button('2 more in All notes')).toBeTruthy();
  });

  it('keeps writing, speaking and Settings in its dock, and Search only once the palette can open', () => {
    const onNew = vi.fn();
    const onCapture = vi.fn();
    const onSettings = vi.fn();
    show(page([], { onNew, onCapture, onSettings }));
    expect(document.querySelector('button[aria-label="Search and commands"]')).toBeNull();
    act(() => button('Write a note').click());
    act(() => button('Speak a voice note').click());
    act(() => button('Settings').click());
    expect([onNew, onCapture, onSettings].map((fn) => fn.mock.calls.length)).toEqual([1, 1, 1]);
    const onSearch = vi.fn();
    rerender(page([], { onNew, onCapture, onSettings, onSearch }));
    act(() => button('Search and commands').click());
    expect(onSearch).toHaveBeenCalledTimes(1);
  });
});
