import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import { bookNoteBody } from '../book/book.ts';
import type { Updates } from '../core/ota.ts';
import { reloadPreferences, setPreferences } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace, fileNote } from '../core/workspaces.ts';
import type { Note } from '../core/store.ts';
import { bodyHash } from '../format/bodyHash.ts';
import { keepGist } from '../format/results.ts';
import { makeNote } from '../../test/notes.ts';
import { button, rerender, show, unmount } from '../../test/render.tsx';
import { stubMatchMedia, stubResizeObserver } from '../../test/stubs.ts';

/**
 * The home page as a person reads it: the groups in their order, the empty page, the shelf of tapes and its way to
 * the rest of them, the to-dos ticked off in place and the ghost when the last one goes, and the dock. What each
 * group holds is home/dashboard.ts's, tested there; the shelf's own words are home/TapeShelf.test.tsx's.
 */

// A card's small drawing is the editor (notes/NotePeek.tsx), which is nothing the page decides.
vi.mock('../notes/NotePeek.tsx', () => ({ NotePeek: () => null }));
// The summary queue's sets, which the digest and the shelf's captions read: a test fills one and draws.
const queues = vi.hoisted(() => ({ pending: new Set<string>(), native: new Set<string>(), failed: new Set<string>(), needsModel: new Set<string>() }));
// What the queue is asked for from a tape's Summarize, and whether this is Tauri, where a summariser can run: off by default, as jsdom is.
const summarize = vi.hoisted(() => ({ enqueue: vi.fn(), tauri: false }));
vi.mock('../ai/summaries.ts', () => ({ useSummaries: () => queues, retrySummary: () => undefined, enqueueSummary: summarize.enqueue }));
vi.mock('../core/tauri.ts', () => ({ isTauri: () => summarize.tauri, invoke: () => Promise.reject(new Error('no Tauri in this test')) }));
// The digest's glide asks whether motion is reduced; jsdom has no matchMedia.
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
    onTick={() => undefined}
    voiceModel={{ kind: 'ready' }}
    onRetryVoiceModel={() => undefined}
    updates={updates}
    {...over}
  />
);
/** The groups on the page, by the word on each heading, in the page's order: the count after a word is not the word. */
const headings = () => [...document.querySelectorAll('h2 [class*=groupName]')].map((h) => h.textContent);
const tasks = () => [...document.querySelectorAll('button[aria-label^="Tick off "]')].map((b) => b.getAttribute('aria-label')!.slice('Tick off '.length));
/** The cassettes on the shelf, by the title each says to a screen reader, in the row's order. */
const shelved = () => [...document.querySelectorAll('ol[aria-label="Tapes"] li > button[aria-label]')].map((b) => b.getAttribute('aria-label')?.split(',')[0]);
/** The cards under one heading, by title. */
const cards = (group: string) => [...document.querySelectorAll(`section[aria-labelledby="${group}"] ol li [class*=title]`)].map((el) => el.textContent);
const recorded = (id: string, title: string, createdAt: number, over: Partial<Note> = {}) =>
  makeNote(id, `# ${title}`, { source: 'capture', recordingMs: 40_000, createdAt, updatedAt: createdAt, ...over });

/** The digest's phrases, in their order. */
const digestLine = () => [...document.querySelectorAll('ul[aria-label="Today"] li')].map((li) => li.textContent);

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
});
afterEach(() => {
  unmount();
  for (const set of Object.values(queues)) set.clear();
  summarize.enqueue.mockClear();
  summarize.tauri = false;
});

describe('the home page', () => {
  it('lays its groups out in their order: Pinned, To do, Tapes, Library, Recent', () => {
    show(
      page([
        makeNote('p', '# Packing\n\n- [ ] Tent', { starred: true, updatedAt: 3 }),
        recorded('t', 'Directions', 4),
        makeNote('b', bookNoteBody('Trip', ['Packing']), { updatedAt: 2 }),
        makeNote('r', '# Route', { updatedAt: 1 }),
      ]),
    );
    expect(headings()).toEqual(['Pinned', 'To do', 'Tapes', 'Library', 'Recent']);
    // The cassette mark on Tapes, the way the pin sits on Pinned.
    expect(document.querySelector('#home-tapes svg')).not.toBeNull();
    // A page of a book says which on its card.
    expect(document.querySelector('[title="Page 1 of Trip"]')?.textContent).toBe('Trip');
  });

  it('draws one mark on every heading, each at the heading’s own size and none at a width of its own', () => {
    show(
      page([
        makeNote('p', '# Packing\n\n- [ ] Tent', { starred: true, updatedAt: 3 }),
        recorded('t', 'Directions', 4),
        makeNote('b', bookNoteBody('Trip', ['Packing']), { updatedAt: 2 }),
        makeNote('r', '# Route', { updatedAt: 1 }),
      ]),
    );
    const marks = [...document.querySelectorAll('h2')].map((h) => h.querySelectorAll('svg'));
    expect(marks.map((m) => m.length)).toEqual([1, 1, 1, 1, 1]);
    // The mismatch, as a test (docs/DESIGN.md §132): the kit's Book wrote width=24 beside the 1em strokes. Every mark
    // is a 1em box now, sized by the heading it sits in, and the foot's grid is the same line, not the kit's LayoutGrid.
    const foot = document.querySelector<SVGElement>('[class*=allNotes] svg')!;
    for (const mark of [...marks.map(([m]) => m!), foot]) {
      expect(mark.style.inlineSize).toBe('1em');
      expect(mark.hasAttribute('width')).toBe(false);
      expect(mark.style.fontSize).toBe('');
    }
    // One family: every heading's mark wears the one class that sizes and inks it.
    for (const [mark] of marks) expect(mark!.getAttribute('class')).toContain('groupMark');
  });

  it('shows four of the notes touched last, and the rest wait in All notes', () => {
    show(page(Array.from({ length: 6 }, (_, i) => makeNote(`n${i}`, `# Note ${i}`, { updatedAt: i + 1 }))));
    expect(cards('home-recent')).toEqual(['Note 5', 'Note 4', 'Note 3', 'Note 2']);
    expect(button('All notes · 6')).toBeTruthy();
  });

  it('shelves what the recorder made, last recorded first, nothing twice, and leaves a typed note spoken into in Recent with its counter', () => {
    show(
      page([
        recorded('old', 'Old take', 1, { updatedAt: 9 }),
        recorded('new', 'New take', 3),
        recorded('pinned', 'Pinned take', 2, { starred: true }),
        makeNote('typed', '# Typed then spoken', { recordingMs: 760_000, createdAt: 4, updatedAt: 4 }),
        recorded('gone', 'Archived take', 5, { archivedAt: 6 }),
      ]),
    );
    expect(headings()).toEqual(['Pinned', 'Tapes', 'Recent']);
    // By when each was recorded, not when it was last touched.
    expect(shelved()).toEqual(['New take', 'Pinned take', 'Old take']);
    // Pinned keeps its card and the cassette is drawn as well, since pinning is a deliberate act.
    expect(cards('home-pinned')).toEqual(['Pinned take']);
    expect(cards('home-recent')).toEqual(['Typed then spoken']);
    expect(document.querySelector('section[aria-labelledby="home-recent"] [class*=tapeLength]')?.textContent).toBe('12:40');
    expect(document.body.textContent).not.toContain('more in All notes');
  });

  it('shelves only the chosen workspace’s tapes, as every group shows only its notes', () => {
    const kitchen = addWorkspace('Kitchen')!;
    fileNote('in', kitchen.id);
    chooseWorkspace(kitchen.id);
    show(page([recorded('in', 'Kitchen take', 2), recorded('out', 'Elsewhere', 3)]));
    expect(shelved()).toEqual(['Kitchen take']);
  });

  it('shows eight tapes, counts every tape in the heading, and its See all opens All notes with its Tapes toggle on', () => {
    const onAllNotes = vi.fn();
    show(page(Array.from({ length: 11 }, (_, i) => recorded(`t${i}`, `Take ${i}`, i + 1)), { onAllNotes }));
    expect(shelved()).toHaveLength(8);
    expect(document.querySelector('#home-tapes')?.textContent).toContain('· 11');
    act(() => button('See all', document.querySelector('section[aria-labelledby="home-tapes"]')!).click());
    expect(onAllNotes).toHaveBeenCalledWith({ tapes: true });
    expect(document.body.textContent).not.toContain('more in All notes');
    unmount();
    // Eight or fewer: no count and no See all, since the shelf is all of them.
    show(page(Array.from({ length: 8 }, (_, i) => recorded(`t${i}`, `Take ${i}`, i + 1)), { onAllNotes }));
    expect(document.querySelector('#home-tapes')?.textContent).toBe('Tapes');
    expect(document.querySelector('section[aria-labelledby="home-tapes"] [class*=groupWord]')).toBeNull();
  });

  it('offers Summarize under a long idle tape on Tauri alone, and asks the queue for the tape’s own kind', () => {
    // A meeting by the preference, whatever made it, and a plain recording: each three minutes and more, with no summary.
    setPreferences({ meetings: { m: 2 } });
    const notes = [makeNote('m', '# Standup', { source: 'editor', recordingMs: 200_000, createdAt: 2, updatedAt: 2 }), recorded('r', 'Walk', 1, { recordingMs: 200_000 })];
    show(page(notes));
    expect(shelved()).toEqual(['Standup', 'Walk']);
    // Off Tauri the queue is a no-op, and the web shows what synced: no offer.
    expect(document.querySelector('ol[aria-label="Tapes"] [class*=offer]')).toBeNull();
    unmount();
    summarize.tauri = true;
    show(page(notes));
    const offers = [...document.querySelectorAll<HTMLButtonElement>('ol[aria-label="Tapes"] li [class*=offer]')];
    expect(offers.map((b) => b.textContent)).toEqual(['Summarize', 'Summarize']);
    act(() => offers[0]!.click());
    act(() => offers[1]!.click());
    expect(summarize.enqueue.mock.calls).toEqual([
      ['m', 'meeting'],
      ['r', 'recording'],
    ]);
  });

  it('gives the shelf’s notes their gists, so a voice note gets its line under the cassette', () => {
    const note = recorded('t', 'Beach', 1);
    keepGist('t', { text: 'A walk along the shore at dusk', for: bodyHash(note.body), model: 'm', len: note.body.length, head: '# Beach' });
    show(page([note]));
    expect(document.querySelector('ol[aria-label="Tapes"] li > p')?.textContent).toBe('A walk along the shore at dusk');
  });

  it('has no shelf while nothing has been recorded', () => {
    show(page([makeNote('a', '# Plain'), makeNote('t', '# Typed then spoken', { recordingMs: 5_000 })]));
    expect(headings()).toEqual(['Recent']);
  });

  it('is a blank page with nothing written, and says which workspace is empty when one is chosen', () => {
    show(page([]));
    expect(document.body.textContent).toContain('A blank page.');
    expect(document.body.textContent).toContain('Write it, or tap Speak and say it.');
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

  it('ticks a to-do off at once, before its note has been written, and names the note it is in and when that was touched', () => {
    const onTick = vi.fn();
    const notes = [makeNote('a', '# Shop\n\n- [ ] Milk\n- [ ] Eggs', { updatedAt: Date.now() })];
    show(page(notes, { onTick }));
    expect(tasks()).toEqual(['Milk', 'Eggs']);
    expect(document.querySelector('[class*=taskNote]')?.textContent).toBe('Shop · Just now');
    act(() => button('Tick off Milk').click());
    expect(onTick).toHaveBeenCalledWith(expect.objectContaining({ noteId: 'a', line: 2, text: 'Milk' }));
    expect(tasks()).toEqual(['Eggs']);
    // The notes read again say it themselves.
    rerender(page([makeNote('a', '# Shop\n\n- [x] Milk\n- [ ] Eggs', { updatedAt: 3 })], { onTick }));
    expect(tasks()).toEqual(['Eggs']);
  });

  it('says every to-do is done once the last is ticked, and says nothing on a page that never had one', () => {
    show(page([makeNote('a', '# Shop\n\n- [ ] Milk')]));
    act(() => button('Tick off Milk').click());
    expect(document.body.textContent).toContain('Every to-do is done.');
    unmount();
    show(page([makeNote('a', '# Shop\n\nNo boxes here.')]));
    expect(document.body.textContent).not.toContain('Every to-do is done.');
    expect(headings()).not.toContain('To do');
  });

  it('shows five to-dos, opens to all of them on Show all, and folds them on Show fewer', () => {
    const many = Array.from({ length: 8 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
    show(page([makeNote('a', `# List\n\n${many}`)]));
    expect(tasks()).toHaveLength(5);
    expect(document.querySelector('#home-tasks')?.textContent).toContain('· 8');
    expect(document.body.textContent).not.toContain('more in your notes');
    act(() => button('Show all 8').click());
    expect(tasks()).toHaveLength(8);
    act(() => button('Show fewer').click());
    expect(tasks()).toHaveLength(5);
  });

  it('opens to forty at most, and counts the rest inside the card only once opened', () => {
    const many = Array.from({ length: 45 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
    show(page([makeNote('a', `# List\n\n${many}`)]));
    expect(document.body.textContent).not.toContain('more in your notes');
    act(() => button('Show all 45').click());
    expect(tasks()).toHaveLength(40);
    expect(document.querySelector('section[aria-labelledby="home-tasks"] [class*=todo] p')?.textContent).toBe('and 5 more in your notes');
  });

  it('has no Show all at five to-dos, which the card holds, and one from the sixth', () => {
    const five = Array.from({ length: 5 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
    show(page([makeNote('a', `# List\n\n${five}`)]));
    expect(tasks()).toHaveLength(5);
    expect(document.querySelector('section[aria-labelledby="home-tasks"] [class*=groupWord]')).toBeNull();
    unmount();
    show(page([makeNote('a', `# List\n\n${five}\n- [ ] Thing 6`)]));
    expect(tasks()).toHaveLength(5);
    expect(button('Show all 6')).toBeTruthy();
  });

  it('names each group for its place on the wider screens, in the page’s order', () => {
    show(
      page([
        makeNote('p', '# Packing\n\n- [ ] Tent', { starred: true, updatedAt: 3 }),
        recorded('t', 'Directions', 4),
        makeNote('b', bookNoteBody('Trip', ['Packing']), { updatedAt: 2 }),
        makeNote('r', '# Route', { updatedAt: 1 }),
      ]),
    );
    expect([...document.querySelectorAll('section[data-group]')].map((s) => s.getAttribute('data-group'))).toEqual(['pinned', 'tasks', 'tapes', 'library', 'recent']);
    // The ids the digest's glide and these tests find the groups by are where they were.
    expect([...document.querySelectorAll('section[data-group]')].map((s) => s.getAttribute('aria-labelledby'))).toEqual(['home-pinned', 'home-tasks', 'home-tapes', 'home-library', 'home-recent']);
  });

  it('lays the page out as a head, its groups and the foot, the notices in the head', () => {
    show(page([makeNote('p', '# Packing\n\n- [ ] Tent', { starred: true, updatedAt: 3 }), recorded('t', 'Directions', 4), makeNote('r', '# Route', { updatedAt: 1 })]));
    // The grid's own children are what the wide screens place (HomeScreen.module.css, "The page laid out wide").
    const grid = document.querySelector('[class*=grid]')!;
    const children = [...grid.children];
    expect(children[0]!.className).toMatch(/head/);
    expect(children.slice(1, -1).map((child) => child.getAttribute('data-group'))).toEqual(['pinned', 'tasks', 'tapes', 'recent']);
    expect(children.at(-1)!.textContent).toMatch(/^All notes · /);
    // The date, the digest and the notices in the head, where the wide screens hold them to the first unit.
    const head = children[0]!;
    expect(head.querySelector('[class*=today]')).not.toBeNull();
    expect(head.querySelector('ul[aria-label="Today"]')).not.toBeNull();
    expect(head.querySelector(':scope > [class*=notices]')).not.toBeNull();
  });

  it('pairs one pinned card with To do only while To do is not opened out', () => {
    const six = Array.from({ length: 6 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
    const paired = () => document.querySelector('[class*=grid]')!.hasAttribute('data-paired');
    const lisbon = makeNote('p', '# Lisbon', { starred: true });
    show(page([lisbon, makeNote('a', `# List\n\n${six}`)]));
    expect(paired()).toBe(true);
    act(() => button('Show all 6').click());
    expect(paired()).toBe(false);
    // Ticked down to the five the card holds, it is a pair again, though Show all was never folded.
    act(() => button('Tick off Thing 1').click());
    expect(tasks()).toHaveLength(5);
    expect(paired()).toBe(true);
    unmount();
    show(page([lisbon, makeNote('a', `# List\n\n${six}`)]));
    act(() => button('Show all 6').click());
    act(() => button('Show fewer').click());
    expect(paired()).toBe(true);
    unmount();
    // Every to-do ticked keeps the card, with its ghost, and the pair with it.
    show(page([lisbon, makeNote('a', '# List\n\n- [x] Done')]));
    expect(paired()).toBe(true);
    unmount();
    // Two pinned cards are a row of their own; no To do, or no pin, is nothing to pair.
    show(page([lisbon, makeNote('q', '# Porto', { starred: true }), makeNote('a', `# List\n\n${six}`)]));
    expect(paired()).toBe(false);
    unmount();
    show(page([lisbon, makeNote('a', '# List')]));
    expect(paired()).toBe(false);
    unmount();
    show(page([makeNote('a', `# List\n\n${six}`)]));
    expect(paired()).toBe(false);
  });

  /**
   * jsdom lays nothing out, so the layout is told: out of the pair, the card spans the page under the pinned card, and
   * its heading is 220px lower than beside it, as on two columns (HomeScreen.module.css).
   */
  const twoColumns = () =>
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: HTMLElement) {
      const top = this.querySelector(':scope > h2#home-tasks') ? (this.closest('[data-paired]') ? 300 : 520) : 0;
      return { x: 0, y: top, top, left: 0, right: 0, bottom: top, width: 0, height: 0, toJSON: () => ({}) } as DOMRect;
    });

  it('keeps To do’s heading where it was on the screen when Show all moves it, and Show fewer moves it back', () => {
    const rect = twoColumns();
    try {
      const many = Array.from({ length: 8 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
      show(page([makeNote('p', '# Lisbon', { starred: true }), makeNote('a', `# List\n\n${many}`)]));
      const scroller = document.querySelector<HTMLElement>('[class*=scroll]')!;
      scroller.scrollTop = 40;
      act(() => button('Show all 8').click());
      expect(scroller.scrollTop).toBe(260);
      act(() => button('Show fewer').click());
      expect(scroller.scrollTop).toBe(40);
      // Where the heading does not move, the page does not either.
      rect.mockImplementation(() => ({ x: 0, y: 300, top: 300, left: 0, right: 0, bottom: 300, width: 0, height: 0, toJSON: () => ({}) }) as DOMRect);
      act(() => button('Show all 8').click());
      expect(scroller.scrollTop).toBe(40);
    } finally {
      rect.mockRestore();
    }
  });

  it('keeps To do’s heading where it was when the tick that brings it down to what the card holds puts it back beside the pinned card', () => {
    const rect = twoColumns();
    try {
      const six = Array.from({ length: 6 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
      show(page([makeNote('p', '# Lisbon', { starred: true }), makeNote('a', `# List\n\n${six}`)]));
      const scroller = document.querySelector<HTMLElement>('[class*=scroll]')!;
      scroller.scrollTop = 40;
      act(() => button('Show all 6').click());
      expect(scroller.scrollTop).toBe(260);
      // Ticking the list off from the top: six to five puts the card back in the pair, 220px up, and the page with it.
      act(() => button('Tick off Thing 1').click());
      expect(scroller.scrollTop).toBe(40);
      // A tick that moves nothing moves nothing.
      act(() => button('Tick off Thing 2').click());
      expect(scroller.scrollTop).toBe(40);
    } finally {
      rect.mockRestore();
    }
  });

  it('folds the To do card and counts the digest afresh when another workspace is chosen', () => {
    const work = addWorkspace('Work')!;
    fileNote('a', work.id);
    const many = Array.from({ length: 8 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
    show(page([makeNote('a', `# List\n\n${many}`, { updatedAt: Date.now() }), makeNote('b', '# Elsewhere\n\n- [ ] Out\n- [ ] Side', { updatedAt: Date.now() })]));
    expect(digestLine()).toEqual(['10 to-dos open', '2 notes touched today']);
    act(() => button('Show all 10').click());
    expect(tasks()).toHaveLength(10);
    // The workspace's own to-dos, folded again, and the digest counts only its notes.
    act(() => chooseWorkspace(work.id));
    expect(tasks()).toHaveLength(5);
    expect(button('Show all 8')).toBeTruthy();
    expect(digestLine()).toEqual(['8 to-dos open', '1 note touched today']);
  });

  it('opens a card and a to-do’s note, and counts every note left out of the archive for All notes', () => {
    const onOpen = vi.fn();
    const onAllNotes = vi.fn();
    show(page([makeNote('a', '# Shop\n\n- [ ] Milk ^milk'), makeNote('z', '# Old', { archivedAt: 1 })], { onOpen, onAllNotes }));
    act(() => [...document.querySelectorAll<HTMLButtonElement>('ol li button')].find((b) => b.textContent?.includes('Shop'))!.click());
    expect(onOpen).toHaveBeenLastCalledWith('a');
    act(() => [...document.querySelectorAll<HTMLButtonElement>('button')].find((b) => b.textContent?.includes('Milk') && !b.getAttribute('aria-label'))!.click());
    expect(onOpen).toHaveBeenLastCalledWith('a', 'milk');
    act(() => button('All notes · 1').click());
    expect(onAllNotes).toHaveBeenCalledTimes(1);
  });

  it('says under the date what is waiting, each phrase that is true in its order', () => {
    queues.pending.add('p');
    queues.failed.add('f');
    show(page([makeNote('a', '# Shop\n\n- [ ] Milk\n- [ ] Eggs', { updatedAt: Date.now() }), recorded('p', 'Pending take', 2), recorded('f', 'Failed take', 1)]));
    expect(digestLine()).toEqual(['2 to-dos open', 'Working on 1 tape', '1 summary didn’t come', '1 note touched today']);
    unmount();
    show(page([makeNote('a', '# Plain', { updatedAt: 1 })]));
    expect(digestLine()).toEqual(['Nothing waiting on you']);
    // The ghost speaks on an empty page, and nothing is said while the notes are still being read.
    unmount();
    show(page([]));
    expect(document.querySelector('ul[aria-label="Today"]')).toBeNull();
    unmount();
    show(page([makeNote('a', '# Plain')], { loading: true }));
    expect(document.querySelector('ul[aria-label="Today"]')).toBeNull();
  });

  it('glides to a phrase’s group when it is tapped, opens Settings at Formatting for a missing model, and only says the day’s count', () => {
    const glided: Element[] = [];
    const scrollIntoView = Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView = function (this: Element) {
      glided.push(this);
    };
    try {
      const onGetModel = vi.fn();
      queues.needsModel.add('t');
      queues.pending.add('p');
      show(page([makeNote('a', '# Shop\n\n- [ ] Milk\n- [ ] Eggs', { updatedAt: Date.now() }), recorded('t', 'Take', 2), recorded('p', 'Pending take', 3)], { onGetModel }));
      expect(digestLine()).toEqual(['2 to-dos open', 'Working on 1 tape', '1 tape needs a model', '1 note touched today']);
      act(() => button('2 to-dos open').click());
      expect(glided).toEqual([document.querySelector('section[aria-labelledby="home-tasks"]')]);
      act(() => button('Working on 1 tape').click());
      expect(glided[1]).toBe(document.querySelector('section[aria-labelledby="home-tapes"]'));
      act(() => button('1 tape needs a model').click());
      expect(onGetModel).toHaveBeenCalledTimes(1);
      expect(glided).toHaveLength(2);
      // The day's count is said, not a word: the notes it counts are all over the page, not in one group.
      expect(() => button('1 note touched today')).toThrow();
      expect(document.querySelector('ul[aria-label="Today"] li:last-child > span')?.textContent).toBe('1 note touched today');
    } finally {
      Element.prototype.scrollIntoView = scrollIntoView;
    }
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

/**
 * How many the page holds, by its own column's width (home/tiers.ts): the phone's four notes and five to-dos, and a
 * desk's six and eight. The shelf holds eight at every width.
 */
describe('the home page on a wide screen', () => {
  /** Eight typed notes, eleven to-dos in the first of them, and nine tapes. */
  const library = () => [
    makeNote('n0', `# Note 0\n\n${Array.from({ length: 11 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n')}`, { updatedAt: 100 }),
    ...Array.from({ length: 7 }, (_, i) => makeNote(`n${i + 1}`, `# Note ${i + 1}`, { updatedAt: 99 - i })),
    ...Array.from({ length: 9 }, (_, i) => recorded(`t${i}`, `Take ${i}`, i + 1)),
  ];
  const held = () => ({ recent: cards('home-recent').length, tasks: tasks().length, shelf: shelved().length });

  it('holds a desk’s six notes and eight to-dos when the column is read on mount, before any report, and the shelf’s eight', () => {
    // The column read on mount, as a desk's 1100px: the size observer here never reports. (That the read is a layout
    // effect, in before the first paint, is the hook's and the browser pass's to show: jsdom paints nothing.)
    const rect = vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({ x: 0, y: 0, top: 0, left: 0, right: 1100, bottom: 0, width: 1100, height: 0, toJSON: () => ({}) } as DOMRect);
    try {
      show(page(library()));
      expect(held()).toEqual({ recent: 6, tasks: 8, shelf: 8 });
      expect(cards('home-recent')).toEqual(['Note 0', 'Note 1', 'Note 2', 'Note 3', 'Note 4', 'Note 5']);
      expect(button('Show all 11')).toBeTruthy();
      expect(document.querySelector('#home-tapes')?.textContent).toContain('· 9');
      expect(button('See all', document.querySelector('section[aria-labelledby="home-tapes"]')!)).toBeTruthy();
    } finally {
      rect.mockRestore();
    }
  });

  it('shows a desk every to-do up to the eight its card holds, with no Show all', () => {
    const rect = vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({ x: 0, y: 0, top: 0, left: 0, right: 1100, bottom: 0, width: 1100, height: 0, toJSON: () => ({}) } as DOMRect);
    try {
      show(page([makeNote('a', `# List\n\n${Array.from({ length: 7 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n')}`)]));
      expect(tasks()).toHaveLength(7);
      expect(document.querySelector('section[aria-labelledby="home-tasks"] [class*=groupWord]')).toBeNull();
    } finally {
      rect.mockRestore();
    }
  });

  describe('as the column changes width', () => {
    /** What each observer watches, and how to tell it: a ResizeObserver whose reports the test sends. */
    let watching: { target: Element; report: ResizeObserverCallback; observer: ResizeObserver }[] = [];
    class ReportingObserver {
      readonly report: ResizeObserverCallback;
      constructor(report: ResizeObserverCallback) {
        this.report = report;
      }
      observe(target: Element): void {
        watching.push({ target, report: this.report, observer: this as unknown as ResizeObserver });
      }
      unobserve(): void {}
      disconnect(): void {
        watching = watching.filter((one) => one.observer !== (this as unknown as ResizeObserver));
      }
    }
    const still = globalThis.ResizeObserver;
    // Outright, not with stubs.ts's `??=`, which would keep the observer that never reports.
    beforeEach(() => {
      globalThis.ResizeObserver = ReportingObserver as unknown as typeof ResizeObserver;
    });
    afterEach(() => {
      globalThis.ResizeObserver = still;
      watching = [];
    });
    /** The page's column is now `width` wide: told to whatever watches it, and only to that. */
    const resizeTo = (width: number) => {
      const column = document.querySelector('[class*=grid]')!.parentElement!;
      const told = watching.filter((one) => one.target === column);
      expect(told).toHaveLength(1);
      act(() => {
        for (const { report, observer } of told) report([{ target: column, contentRect: { width } } as unknown as ResizeObserverEntry], observer);
      });
    };

    it('holds the phone’s counts on two columns, a desk’s past 60rem, and the phone’s again when it narrows', () => {
      show(page(library()));
      expect(held()).toEqual({ recent: 4, tasks: 5, shelf: 8 });
      resizeTo(800);
      expect(held()).toEqual({ recent: 4, tasks: 5, shelf: 8 });
      resizeTo(1100);
      expect(held()).toEqual({ recent: 6, tasks: 8, shelf: 8 });
      expect(button('Show all 11')).toBeTruthy();
      resizeTo(800);
      expect(held()).toEqual({ recent: 4, tasks: 5, shelf: 8 });
    });

    it('draws its lines at the root’s rem, which Settings’ interface size moves', () => {
      // At 125% a rem is 20px: 1100px of column is 55rem, two across, and the desk's line is 1320px.
      setPreferences({ uiScale: 1.25 });
      const rect = vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({ x: 0, y: 0, top: 0, left: 0, right: 1100, bottom: 0, width: 1100, height: 0, toJSON: () => ({}) } as DOMRect);
      try {
        expect(getComputedStyle(document.documentElement).fontSize).toBe('20px');
        show(page(library()));
        expect(held()).toEqual({ recent: 4, tasks: 5, shelf: 8 });
        resizeTo(1300);
        expect(held()).toEqual({ recent: 4, tasks: 5, shelf: 8 });
        resizeTo(1400);
        expect(held()).toEqual({ recent: 6, tasks: 8, shelf: 8 });
      } finally {
        rect.mockRestore();
        setPreferences({ uiScale: 1 });
      }
    });

    it('stops watching the column when the page goes', () => {
      show(page(library()));
      const column = document.querySelector('[class*=grid]')!.parentElement;
      expect(watching.filter(({ target }) => target === column)).toHaveLength(1);
      unmount();
      expect(watching.filter(({ target }) => target === column)).toEqual([]);
    });
  });
});
