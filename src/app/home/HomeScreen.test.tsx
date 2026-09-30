import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import { bookNoteBody } from '../book/book.ts';
import type { Updates } from '../core/ota.ts';
import { reloadPreferences, setPreferences, type HomeLayout } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace, fileNote, reloadWorkspaces } from '../core/workspaces.ts';
import type { Note } from '../core/store.ts';
import { makeNote } from '../../test/notes.ts';
import { goBack } from '../core/back.ts';
import { button, rerender, show, typeInto, unmount } from '../../test/render.tsx';
import { stubMatchMedia, stubResizeObserver } from '../../test/stubs.ts';

/**
 * The home page as a person reads it (docs/DESIGN.md §147, §148): the search and the filters beside it, the chips that
 * say what is on, the layouts Settings offers, the empty page, the way to All notes, and the dock. What the page lists
 * and in what order is home/homeLayout.ts's, tested there.
 */

// A card's small drawing is the editor (notes/NotePeek.tsx), which is nothing the page decides.
vi.mock('../notes/NotePeek.tsx', () => ({ NotePeek: () => null }));
// The meeting being recorded now, which the phone's service knows (capture/meetingLive.ts) and a test says.
const meeting = vi.hoisted(() => ({ live: null as string | null }));
vi.mock('../capture/meetingLive.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../capture/meetingLive.ts')>()),
  useMeetingState: () => (meeting.live ? { recording: true, noteId: meeting.live, title: null, startedAt: 0, elapsedMs: 0, silenced: false, writingUp: null, discarded: [] } : null),
}));
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
  const section = [...document.querySelectorAll('section')].find((s) => s.querySelector('h2 span')?.textContent === heading || s.getAttribute('aria-label') === heading);
  return [...(section?.querySelectorAll(':scope > :is(ol, ul) > li') ?? [])].map((li) => li.querySelector('[class*=title], [class*=Title]')?.textContent);
};
const search = (words: string) => typeInto(document.querySelector<HTMLInputElement>('input[type="search"]')!, words);
const laidOut = (layout: HomeLayout) => act(() => setPreferences({ homeLayout: layout }));

/** The filters' button beside the search, whatever it says is on. */
const filterButton = () => document.querySelector<HTMLButtonElement>('button[aria-haspopup="dialog"][aria-label^="Filters"]');
const openFilters = () => act(() => filterButton()!.click());
const panel = () => document.querySelector<HTMLElement>('[role="dialog"][aria-label="Filters"]');
/** A group of the panel's choices by its heading, each as its words and "(on)" for the chosen. */
const choices = (heading: string) => {
  const group = [...(panel()?.querySelectorAll('[role="radiogroup"]') ?? [])].find((g) => document.getElementById(g.getAttribute('aria-labelledby') ?? '')?.textContent === heading);
  return [...(group?.querySelectorAll<HTMLButtonElement>('[role="radio"]') ?? [])];
};
const said = (radios: HTMLButtonElement[]) => radios.map((r) => `${r.textContent}${r.getAttribute('aria-checked') === 'true' ? ' (on)' : ''}`);
const choose = (heading: string, words: string) => act(() => choices(heading).find((r) => r.textContent?.startsWith(words))!.click());
/** The chips under the search, one for each filter on. */
const chips = () => [...document.querySelectorAll('[aria-label="Filters on"] button')].map((b) => b.textContent);

/** The page's clock, held at a Wednesday afternoon, so a note touched a minute ago is today whenever the tests run. */
const now = new Date(2026, 8, 30, 15, 0).getTime();
const day = 24 * 60 * 60 * 1000;
const trip = makeNote('b', bookNoteBody('Trip', ['Packing', 'Route']), { updatedAt: 5 });
const packing = makeNote('p', '# Packing\n\n- [ ] Tent and stove', { starred: true, updatedAt: 3 });
const route = makeNote('r', '# Route\n\nNorth along the coast road.', { updatedAt: 4 });
const loose = makeNote('l', '# Shopping\n\nMilk, bread.', { updatedAt: 2 });
const shelf = [trip, packing, route, loose];
/** Notes touched at known moments: two today, one yesterday, one three months ago. */
const dated = [
  makeNote('t1', '# Fresh', { updatedAt: now - 60_000 }),
  makeNote('t2', '# Morning', { updatedAt: now - 120_000 }),
  makeNote('y', '# Last night', { updatedAt: now - day - 60_000 }),
  makeNote('o', '# Stale', { updatedAt: now - 90 * day }),
];

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(now);
  localStorage.clear();
  reloadPreferences();
  reloadWorkspaces();
  // Most of these read the Cards layout's two sections, Notebooks then Notes; the default has a test of its own.
  setPreferences({ homeLayout: 'cards', homeLayoutChosen: true });
});
afterEach(() => {
  unmount();
  vi.useRealTimers();
  meeting.live = null;
});

/** A tick of the real clock, for what the panel does once the kit has opened it. */
const tick = () => act(async () => await new Promise((done) => setTimeout(done, 0)));

describe('the home page', () => {
  it('opens on Spotlight on a device where no layout was picked', () => {
    setPreferences({ homeLayout: 'cards', homeLayoutChosen: false });
    reloadPreferences();
    show(page(dated));
    expect(document.querySelector('[data-layout="spotlight"]')).not.toBeNull();
    expect(headings()).toEqual(['Recent']);
  });

  it('lists the pinned notes above Recent on Spotlight, a line each, and not again below', () => {
    const onOpen = vi.fn();
    laidOut('spotlight');
    show(page([...dated, makeNote('pin', '# Wifi password', { starred: true, updatedAt: now - 5 * day }), trip, packing], { onOpen }));
    expect(headings()).toEqual(['Pinned', 'Recent', 'Earlier']);
    const lines = [...document.querySelectorAll<HTMLButtonElement>('section[data-section="pinned"] li button')];
    expect(lines.map((b) => b.querySelector('[class*=lineTitle]')?.textContent)).toEqual(['Wifi password', 'Packing']);
    // Its notebook after its name, and no pin on a line: the list is the pinned ones.
    expect(lines[1]?.textContent).toContain('Trip');
    expect(document.querySelector('section[data-section="pinned"] ul [class*=rowPin]')).toBeNull();
    expect(document.querySelector('#home-pinned')?.textContent).toBe('Pinned2');
    // Not in Recent, nor further down.
    expect(listed('Recent')).toEqual(['Fresh', 'Morning', 'Last night', 'Stale']);
    expect(document.body.textContent?.match(/Wifi password/g)).toHaveLength(1);
    act(() => lines[0]!.click());
    expect(onOpen).toHaveBeenLastCalledWith('pin');
  });

  it('is the search with its filters beside it, and the notebooks then the notes, pinned first, as cards', () => {
    show(page(shelf));
    expect(document.querySelector('input[type="search"]')?.getAttribute('placeholder')).toBe('Search notebooks and notes');
    expect(filterButton()?.getAttribute('aria-label')).toBe('Filters');
    // No rows of pills: the filters and the workspaces are in the button's panel, and nothing is on.
    expect(document.querySelector('[role="group"][aria-label="Workspaces"]')).toBeNull();
    expect(chips()).toEqual([]);
    expect(headings()).toEqual(['Notebooks', 'Notes']);
    expect(listed('Notebooks')).toEqual(['Trip']);
    expect(listed('Notes')).toEqual(['Packing', 'Route', 'Shopping']);
    expect(document.querySelector('[title="Page 1 of Trip"]')?.textContent).toBe('Trip');
    expect(document.querySelector('button[aria-label^="Tick off "]')).toBeNull();
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
});

describe('the filters beside the search', () => {
  it('offer what to show, with how many of each, and keep the choice under the search as a chip until its cross', () => {
    show(page(shelf));
    expect(panel()).toBeNull();
    openFilters();
    expect(said(choices('Show'))).toEqual(['All4 (on)', 'Notebooks1', 'Notes3', 'Pinned1']);
    choose('Show', 'Notebooks');
    expect(headings()).toEqual(['Notebooks']);
    expect(said(choices('Show'))).toContain('Notebooks1 (on)');
    // The button is inked and says what is on; a chip says it under the search.
    expect(filterButton()?.getAttribute('aria-label')).toBe('Filters: Notebooks');
    expect(filterButton()?.hasAttribute('data-on')).toBe(true);
    expect(chips()).toEqual(['Notebooks']);
    choose('Show', 'Pinned');
    expect(listed('Notes')).toEqual(['Packing']);
    expect(chips()).toEqual(['Pinned']);
    act(() => button('Pinned: show everything').click());
    expect(chips()).toEqual([]);
    expect(headings()).toEqual(['Notebooks', 'Notes']);
    expect(filterButton()?.getAttribute('aria-label')).toBe('Filters');
  });

  it('open on the chosen Show, and move each group’s choice with the arrow keys, round both ends', async () => {
    addWorkspace('Kitchen');
    addWorkspace('Work');
    show(page(shelf));
    openFilters();
    await tick();
    expect(document.activeElement).toBe(choices('Show')[0]);
    const keyed = (group: string, key: string) =>
      act(() => choices(group).find((r) => r.getAttribute('aria-checked') === 'true')!.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true })));
    keyed('Show', 'ArrowDown');
    expect(said(choices('Show'))[1]).toBe('Notebooks1 (on)');
    expect(document.activeElement?.textContent).toBe('Notebooks1');
    keyed('Show', 'ArrowUp');
    keyed('Show', 'ArrowUp');
    expect(said(choices('Show'))[3]).toBe('Pinned1 (on)');
    keyed('Show', 'ArrowDown');
    expect(said(choices('Show'))[0]).toBe('All4 (on)');
    keyed('Workspace', 'ArrowDown');
    expect(said(choices('Workspace'))).toEqual(['Every workspace', 'Kitchen (on)', 'Work']);
    expect(document.activeElement?.textContent).toBe('Kitchen');
    keyed('Workspace', 'ArrowUp');
    keyed('Workspace', 'ArrowUp');
    expect(said(choices('Workspace'))[2]).toBe('Work (on)');
  });

  it('close on the phone’s back, and when the keyboard leaves them for the page', () => {
    show(page(shelf));
    openFilters();
    expect(filterButton()?.getAttribute('aria-expanded')).toBe('true');
    act(() => goBack());
    expect(filterButton()?.getAttribute('aria-expanded')).toBe('false');
    openFilters();
    // Shift+Tab from the first choice lands on the page's last button, the dock's.
    const away = button('Settings');
    act(() => choices('Show')[0]!.dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: away })));
    expect(filterButton()?.getAttribute('aria-expanded')).toBe('false');
    // Moving between its own choices keeps it open.
    openFilters();
    act(() => choices('Show')[0]!.dispatchEvent(new FocusEvent('focusout', { bubbles: true, relatedTarget: choices('Show')[1]! })));
    expect(filterButton()?.getAttribute('aria-expanded')).toBe('true');
  });

  it('say every filter on in the button’s name and a chip each, and hand the keyboard on as each chip goes', () => {
    const kitchen = addWorkspace('Kitchen')!;
    fileNote('l', kitchen.id);
    show(page(shelf));
    openFilters();
    choose('Show', 'Notes');
    choose('Workspace', 'Kitchen');
    expect(filterButton()?.getAttribute('aria-label')).toBe('Filters: Notes, Kitchen');
    expect(chips()).toEqual(['Notes', 'Kitchen']);
    act(() => button('Notes: show everything').click());
    expect(document.activeElement?.getAttribute('aria-label')).toBe('Kitchen: every workspace');
    act(() => button('Kitchen: every workspace').click());
    expect(chips()).toEqual([]);
    expect(document.activeElement).toBe(filterButton());
  });

  it('choose the workspace, name it in a chip in its colour, and take it off from the chip', () => {
    const kitchen = addWorkspace('Kitchen', 'moss')!;
    addWorkspace('Work');
    fileNote('l', kitchen.id);
    show(page(shelf));
    openFilters();
    expect(said(choices('Workspace'))).toEqual(['Every workspace (on)', 'Kitchen', 'Work']);
    // The pills are gone from the page: the workspaces and the Show choices are only in the panel.
    expect(document.querySelector('[role="group"][aria-label="Workspaces"]')).toBeNull();
    expect([...document.querySelectorAll('[role="radiogroup"]')].every((group) => group.closest('[role="dialog"]'))).toBe(true);
    choose('Workspace', 'Kitchen');
    expect(listed('Notes')).toEqual(['Shopping']);
    expect(said(choices('Show'))[0]).toBe('All1 (on)');
    expect(chips()).toEqual(['Kitchen']);
    expect(document.querySelector('[aria-label="Filters on"] [data-hue="moss"]')).not.toBeNull();
    expect(filterButton()?.getAttribute('aria-label')).toBe('Filters: Kitchen');
    act(() => button('Kitchen: every workspace').click());
    expect(chips()).toEqual([]);
    expect(listed('Notes')).toEqual(['Packing', 'Route', 'Shopping']);
  });

  it('make a workspace, and change the chosen one, from the panel', () => {
    show(page(shelf));
    openFilters();
    // None yet: a line on what one is, and the way to make one.
    expect(choices('Workspace')).toEqual([]);
    expect(panel()?.textContent).toContain('Notes filed in a workspace show together.');
    act(() => button('New workspace').click());
    // The panel closes for the sheet (its fade out is the kit's, which jsdom never finishes).
    expect(filterButton()?.getAttribute('aria-expanded')).toBe('false');
    expect(document.querySelector('[role="dialog"][aria-label="New workspace"]')).not.toBeNull();
    unmount();
    const kitchen = addWorkspace('Kitchen')!;
    chooseWorkspace(kitchen.id);
    show(page(shelf));
    openFilters();
    act(() => button('Edit Kitchen').click());
    expect(document.querySelector('[role="dialog"][aria-label="Kitchen"]')).not.toBeNull();
    // The sheet closed, the keyboard is back on the button that opened the panel.
    act(() => goBack());
    expect(document.activeElement).toBe(filterButton());
  });

  it('stay on a workspace with nothing in it, so it can be left', () => {
    const kitchen = addWorkspace('Kitchen')!;
    chooseWorkspace(kitchen.id);
    show(page(shelf));
    expect(document.body.textContent).toContain('Nothing in Kitchen yet.');
    expect(chips()).toEqual(['Kitchen']);
    act(() => button('Kitchen: every workspace').click());
    expect(headings()).toEqual(['Notebooks', 'Notes']);
  });
});

describe('the layouts', () => {
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
    expect(listed('Trip')).toEqual(['Packing', 'Route']);
    // Under its own notebook a page does not name it again.
    expect(document.querySelector('section[aria-label="Trip"] li')?.textContent).not.toContain('Trip');
    expect(headings()).toEqual(['In no notebook']);
    expect(listed('In no notebook')).toEqual(['Shopping']);
    act(() => document.querySelector<HTMLButtonElement>('section[aria-label="Trip"] button')!.click());
    expect(onOpen).toHaveBeenLastCalledWith('b');
  });

  it('draws a page the search found under Notes when its notebook was not found, in the Library and Notebook cards', () => {
    for (const layout of ['library', 'notebook-cards'] as const) {
      show(page(shelf));
      laidOut(layout);
      search('coast');
      expect(headings()).toEqual(['Notes']);
      expect(listed('Notes')).toEqual(['Route']);
      search('zebra');
      expect(document.body.textContent).toContain('Nothing has “zebra”.');
      unmount();
    }
  });

  it('draws the Timeline by when each was last touched, as rows', () => {
    show(page(dated));
    laidOut('timeline');
    expect(headings()).toEqual(['Today', 'Yesterday', 'Earlier']);
    expect(listed('Today')).toEqual(['Fresh', 'Morning']);
    expect(document.querySelector('section[data-section="today"] ul')).not.toBeNull();
  });

  it('draws a voice recording in the Timeline as one, with its cassette and its length, and the one being recorded as that', () => {
    const spoken = makeNote('v', '# Standup\n\nWe agreed to ship on Friday.', { source: 'capture', recordingMs: 40_000, updatedAt: now - 30_000 });
    const live = makeNote('m', '# Planning', { source: 'capture', updatedAt: now - 10_000 });
    meeting.live = 'm';
    show(page([...dated, spoken, live]));
    laidOut('timeline');
    expect(listed('Today')).toEqual(['Planning', 'Standup', 'Fresh', 'Morning']);
    const rows = [...document.querySelectorAll<HTMLButtonElement>('section[data-section="today"] li button')];
    expect(rows[1]?.querySelector('[class*=rowLead]')?.textContent).toBe('0:40We agreed to ship on Friday.');
    expect(rows[1]?.querySelector('[class*=rowMarkTape]')).not.toBeNull();
    expect(rows[0]?.querySelector('[class*=rowLive]')?.textContent).toBe('Recording now');
    expect(rows[0]?.querySelector('[class*=rowMarkTape]')).not.toBeNull();
    // A note of words has neither.
    expect(rows[2]?.querySelector('[class*=rowMarkTape], [class*=rowTape], [class*=rowLive]')).toBeNull();
    // In Spotlight the four touched last are its cards, the recording and the meeting among them.
    laidOut('spotlight');
    expect(listed('Recent')).toEqual(['Planning', 'Standup', 'Fresh', 'Morning']);
  });

  it('draws the Card timeline as the Timeline’s spans with a card for each', () => {
    show(page(dated));
    laidOut('card-timeline');
    expect(headings()).toEqual(['Today', 'Yesterday', 'Earlier']);
    expect(listed('Today')).toEqual(['Fresh', 'Morning']);
    expect(document.querySelector('section[data-section="today"] ul')).toBeNull();
    expect(document.querySelectorAll('section[data-section="today"] ol > li')).toHaveLength(2);
  });

  it('draws Spotlight as the four touched last as cards, then the rest by when, as rows', () => {
    show(page([...dated, makeNote('m', '# Last month', { updatedAt: now - 20 * day }), makeNote('a', '# Ancient', { updatedAt: now - 400 * day })]));
    laidOut('spotlight');
    expect(headings()).toEqual(['Recent', 'Earlier']);
    expect(listed('Recent')).toEqual(['Fresh', 'Morning', 'Last night', 'Last month']);
    expect(listed('Earlier')).toEqual(['Stale', 'Ancient']);
    // "Recent" has no count: it is always the four.
    expect(document.querySelector('#home-recent')?.textContent).toBe('Recent');
  });

  it('draws the Shelf and timeline as the notebooks’ covers, then the notes by when', () => {
    show(page([makeNote('b', bookNoteBody('Trip', []), { updatedAt: now }), ...dated]));
    laidOut('shelf-timeline');
    expect(headings()).toEqual(['Notebooks', 'Today', 'Yesterday', 'Earlier']);
    expect([...document.querySelectorAll('ol[aria-label="Notebooks"] button')].map((b) => b.textContent?.includes('Trip'))).toEqual([true]);
    expect(listed('Today')).toEqual(['Fresh', 'Morning']);
  });

  it('draws Notebook cards as each notebook with a few of its pages as cards, the rest a tap away in the notebook', () => {
    const titles = Array.from({ length: 8 }, (_, i) => `Day ${i + 1}`);
    const book = makeNote('big', bookNoteBody('Road trip', titles), { updatedAt: 9 });
    const onOpen = vi.fn();
    show(page([book, ...titles.map((title, i) => makeNote(`d${i}`, `# ${title}`, { updatedAt: i + 1 })), loose], { onOpen }));
    laidOut('notebook-cards');
    expect(listed('Road trip')).toEqual(titles.slice(0, 6));
    // Under its own notebook a page's card does not name it again; on the Cards layout it does.
    expect(document.querySelector('section[aria-label="Road trip"] [title^="Page "]')).toBeNull();
    expect(listed('In no notebook')).toEqual(['Shopping']);
    act(() => button('2 more in Road trip').click());
    expect(onOpen).toHaveBeenLastCalledWith('big');
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

  it('draws forty-eight cards at most, and sends the rest to All notes', () => {
    const many = Array.from({ length: 50 }, (_, i) => makeNote(`n${i}`, `# Note ${i}`, { updatedAt: now - i * 1000 }));
    show(page(many));
    expect(listed('Notes')).toHaveLength(48);
    expect(button('2 more in All notes')).toBeTruthy();
    laidOut('card-timeline');
    expect(listed('Today')).toHaveLength(48);
    expect(button('2 more in All notes')).toBeTruthy();
    // Rows are cheap: the Timeline draws every one.
    laidOut('timeline');
    expect(listed('Today')).toHaveLength(50);
    expect(button('All notes · 50')).toBeTruthy();
  });
});

describe('the rest of the page', () => {
  it('is a blank page with nothing written, and says which workspace is empty when one is chosen', () => {
    show(page([]));
    expect(document.body.textContent).toContain('A blank page.');
    expect(document.body.textContent).toContain('Write it, or tap Speak and say it.');
    expect(document.querySelector('input[type="search"]')).toBeNull();
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
