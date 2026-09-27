import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import { bookNoteBody } from '../book/book.ts';
import type { Updates } from '../core/ota.ts';
import { reloadPreferences } from '../core/preferences.ts';
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
vi.mock('../ai/summaries.ts', () => ({ useSummaries: () => queues, retrySummary: () => undefined, enqueueSummary: () => undefined }));
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
    // is a 1em box now, sized by the heading it sits in.
    for (const [mark] of marks) {
      expect(mark!.style.inlineSize).toBe('1em');
      expect(mark!.hasAttribute('width')).toBe(false);
    }
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

  it('opens to forty at most, and counts the rest inside the card', () => {
    const many = Array.from({ length: 45 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
    show(page([makeNote('a', `# List\n\n${many}`)]));
    act(() => button('Show all 45').click());
    expect(tasks()).toHaveLength(40);
    expect(document.querySelector('section[aria-labelledby="home-tasks"] [class*=todo] p')?.textContent).toBe('and 5 more in your notes');
  });

  it('has no Show all under five to-dos', () => {
    show(page([makeNote('a', '# List\n\n- [ ] One\n- [ ] Two')]));
    expect(document.querySelector('section[aria-labelledby="home-tasks"] [class*=groupWord]')).toBeNull();
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

  it('glides to a phrase’s group when it is tapped, and opens Settings at Formatting for a missing model', () => {
    const glided: Element[] = [];
    const scrollIntoView = Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView = function (this: Element) {
      glided.push(this);
    };
    try {
      const onGetModel = vi.fn();
      queues.needsModel.add('t');
      show(page([makeNote('a', '# Shop\n\n- [ ] Milk\n- [ ] Eggs', { updatedAt: Date.now() }), recorded('t', 'Take', 2)], { onGetModel }));
      act(() => button('2 to-dos open').click());
      expect(glided).toEqual([document.querySelector('section[aria-labelledby="home-tasks"]')]);
      act(() => button('1 note touched today').click());
      expect(glided[1]).toBe(document.querySelector('section[aria-labelledby="home-recent"]'));
      act(() => button('1 tape needs a model').click());
      expect(onGetModel).toHaveBeenCalledTimes(1);
      expect(glided).toHaveLength(2);
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
