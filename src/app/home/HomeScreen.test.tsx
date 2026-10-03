import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import { bookNoteBody } from '../book/book.ts';
import type { Updates } from '../core/ota.ts';
import { reloadPreferences, setPreferences, type HomeLayout } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace, fileNote, reloadWorkspaces } from '../core/workspaces.ts';
import type { Note } from '../core/store.ts';
import { makeNote } from '../../test/notes.ts';
import { goBack } from '../core/back.ts';
import { button, buttonSaying, rerender, show, typeInto, unmount } from '../../test/render.tsx';
import { stubMatchMedia, stubResizeObserver } from '../../test/stubs.ts';

/**
 * The home page as a person reads it (docs/DESIGN.md §147, §148): the search and the filters beside it, the chips that
 * say what is on, the layouts Settings offers, the empty page, the way to All notes, and the dock. What the page lists
 * and in what order is home/homeLayout.ts's, tested there.
 */

// A card's small drawing is the editor (notes/NotePeek.tsx), which is nothing the page decides.
vi.mock('../notes/NotePeek.tsx', () => ({ NotePeek: () => null }));
// The motor, for what a swipe makes it do at each detent.
const felt = vi.hoisted(() => ({ kinds: [] as string[], ticks: 0 }));
vi.mock('../core/haptics.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/haptics.ts')>()),
  fireNativeHaptic: (kind = 'light') => void felt.kinds.push(kind),
  fireMicroTick: () => void (felt.ticks += 1),
}));
// The meeting being recorded now, which the phone's service knows (capture/meetingLive.ts) and a test says.
const meeting = vi.hoisted(() => ({ live: null as string | null }));
vi.mock('../capture/meetingLive.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../capture/meetingLive.ts')>()),
  useMeetingState: () => (meeting.live ? { recording: true, noteId: meeting.live, title: null, startedAt: 0, elapsedMs: 0, silenced: false, writingUp: null, discarded: [] } : null),
}));
// Signed out, unless a test about organizations signs matt in (docs/TEAMS.md).
const who = vi.hoisted(() => ({ session: null as { token: string; handle: string; accountId: number } | null }));
vi.mock('../core/account/account.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/account/account.ts')>()),
  accountState: () => ({ session: who.session, unlocked: who.session !== null }),
  useAccount: () => ({ session: who.session, unlocked: who.session !== null }),
  accountKey: async () => null,
}));
// The pass an answered invitation asks for: it confirms the answer, as the service would, and takes the list of
// organizations again, where one accepted is now one the account is in - which takes the home page's card away. A
// test can hold the pass there, as the network holds a real one, so the page is drawn again before it ends.
const pass = vi.hoisted(() => ({ held: false, end: null as (() => void) | null }));
vi.mock('../core/sync/engine.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/sync/engine.ts')>()),
  syncNotificationsNow: async () => {
    const { feedState, updateFeed } = await import('../core/notifications/feed.ts');
    const { orgsState, saveOrgs } = await import('../core/orgs/orgs.ts');
    const accepted = feedState(7).marks.flatMap((mark) => ('org' in mark && mark.answer ? [mark.org] : []));
    updateFeed(7, (state) => ({ ...state, marks: [] }));
    const kept = orgsState();
    saveOrgs(7, { ...kept, list: kept.list.map((row) => (accepted.includes(row.id) ? { ...row, state: 'member' as const } : row)) });
    if (pass.held) await new Promise<void>((resolve) => (pass.end = resolve));
  },
}));
// The glide back to the top asks whether motion is reduced; jsdom has no matchMedia.
stubMatchMedia();
const { HomeScreen } = await import('./HomeScreen.tsx');
const { forgetNotifications, updateFeed, withFed } = await import('../core/notifications/feed.ts');
const { forgetOrgs, saveOrgs } = await import('../core/orgs/orgs.ts');
const { ensureOrgWorkspace } = await import('../core/workspaces.ts');

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
  felt.kinds = [];
  felt.ticks = 0;
  who.session = null;
  forgetNotifications(7);
  forgetOrgs(7);
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
    // Each with its mark at its left, the one its things wear on the page.
    expect(choices('Show').map((choice) => choice.firstElementChild?.tagName.toLowerCase())).toEqual(['svg', 'svg', 'svg', 'svg']);
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
    // Every workspace wears the folder; each workspace its colour.
    expect(choices('Workspace')[0]!.firstElementChild?.tagName.toLowerCase()).toBe('svg');
    expect(choices('Workspace')[1]!.firstElementChild?.getAttribute('class')).toContain('hueDot');
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

  it('says how many cards a canvas has on its row, never the first line of its JSON', () => {
    const board = makeNote('c', '---\ntitle: "Plan"\n---\n{"nodes":[{"id":"a","type":"text","text":"One","x":0,"y":0,"width":100,"height":60},{"id":"b","type":"text","text":"Two","x":0,"y":90,"width":100,"height":60}],"edges":[]}', { updatedAt: 9 });
    show(page([board, makeNote('e', '---\ntitle: "Empty"\n---\n{"nodes":[],"edges":[]}', { updatedAt: 8 })]));
    laidOut('list');
    const rows = [...document.querySelectorAll('section li button')].map((b) => b.querySelector('[class*=rowLead]')?.textContent);
    expect(rows).toEqual(['2 cards', 'No cards yet']);
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

  it('draws Spotlight as the four touched last as cards, then the rest by when, as rows', () => {
    show(page([...dated, makeNote('m', '# Last month', { updatedAt: now - 20 * day }), makeNote('a', '# Ancient', { updatedAt: now - 400 * day })]));
    laidOut('spotlight');
    expect(headings()).toEqual(['Recent', 'Earlier']);
    expect(listed('Recent')).toEqual(['Fresh', 'Morning', 'Last night', 'Last month']);
    expect(listed('Earlier')).toEqual(['Stale', 'Ancient']);
    // "Recent" has no count: it is always the four.
    expect(document.querySelector('#home-recent')?.textContent).toBe('Recent');
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

  it('says a ticket’s key and status on its card, its row and its line, the status in its notebook’s workflow (docs/DESIGN.md §157)', () => {
    const book = makeNote('book', '---\ntitle: "Ghost.md"\nbook: true\nkey: GHO\nstatuses: [Ideas, Building, Live]\n---\n# Ghost.md\n\n- [[Fix the login loop]]\n', { updatedAt: now - 5000 });
    const ticket = makeNote('t', '---\ntype: ticket\nid: GHO-12\nstatus: Live\n---\n# Fix the login loop\n', { updatedAt: now, starred: true });
    const plain = makeNote('p', '# Groceries\n\n- milk', { updatedAt: now - 1000 });
    const marks = () => [...document.querySelectorAll<HTMLElement>('section li [data-category]')].map((mark) => [mark.textContent, mark.dataset.category]);
    show(page([book, ticket, plain]));
    expect(marks()).toContainEqual(['GHO-12Live', 'done']);
    laidOut('list');
    expect(marks()).toContainEqual(['GHO-12Live', 'done']);
    expect(marks().filter(([words]) => words?.includes('Groceries'))).toEqual([]);
  });

  it('draws forty-eight cards at most, and sends the rest to All notes', () => {
    const many = Array.from({ length: 50 }, (_, i) => makeNote(`n${i}`, `# Note ${i}`, { updatedAt: now - i * 1000 }));
    show(page(many));
    expect(listed('Notes')).toHaveLength(48);
    expect(button('2 more in All notes')).toBeTruthy();
    // Rows are cheap: the Timeline draws every one.
    laidOut('timeline');
    expect(listed('Today')).toHaveLength(50);
    expect(button('All notes · 50')).toBeTruthy();
  });
});

describe('swiping a note', () => {
  // jsdom lays nothing out: a row is as wide as a phone's, and the finger is held as a real one would be.
  const WIDTH = 400;
  beforeEach(() => {
    Object.defineProperty(HTMLElement.prototype, 'offsetWidth', { configurable: true, get: () => WIDTH });
    Element.prototype.setPointerCapture = () => undefined;
  });
  afterEach(() => {
    Reflect.deleteProperty(HTMLElement.prototype, 'offsetWidth');
    Reflect.deleteProperty(Element.prototype, 'setPointerCapture');
  });

  /** A finger on a note's row, moved across by `by` of the row's width, in steps, and let go. */
  const swipe = (button: Element, by: number) => {
    const row = button.parentElement!;
    const at = (type: string, x: number) => row.dispatchEvent(new PointerEvent(type, { bubbles: true, pointerId: 1, pointerType: 'touch', clientX: x, clientY: 300 }));
    act(() => at('pointerdown', 200));
    for (let step = 1; step <= 10; step += 1) act(() => at('pointermove', 200 + (by * WIDTH * step) / 10));
    act(() => at('pointerup', 200 + by * WIDTH));
  };
  const rowOf = (title: string) => [...document.querySelectorAll('section li button')].find((b) => b.textContent?.includes(title))!;
  /** Long enough for a row that leaves to slide away first. */
  const away = () => act(async () => await new Promise((done) => setTimeout(done, 220)));

  it('pins a note swiped right past its detent, with the firm click of arriving', () => {
    const onSwipe = vi.fn();
    laidOut('list');
    show(page(shelf, { onSwipe }));
    swipe(rowOf('Shopping'), 0.3);
    expect(onSwipe).toHaveBeenCalledWith(loose, 'pin');
    expect(felt.kinds).toEqual(['medium']);
  });

  it('archives a note swiped left, and deletes it pulled further, each detent felt, the delete heavier', async () => {
    const onSwipe = vi.fn();
    laidOut('list');
    show(page(shelf, { onSwipe }));
    swipe(rowOf('Shopping'), -0.3);
    await away();
    expect(onSwipe).toHaveBeenLastCalledWith(loose, 'archive');
    expect(felt.kinds).toEqual(['medium']);
    felt.kinds = [];
    swipe(rowOf('Route'), -0.62);
    await away();
    expect(onSwipe).toHaveBeenLastCalledWith(route, 'delete');
    expect(felt.kinds).toEqual(['medium', 'heavy']);
    // The detents are felt coming, too: light ticks on the way to each.
    expect(felt.ticks).toBeGreaterThan(0);
  });

  it('springs back short of a detent, does nothing, and never opens the note the finger let go of', async () => {
    const onSwipe = vi.fn();
    const onOpen = vi.fn();
    laidOut('list');
    show(page(shelf, { onSwipe, onOpen }));
    swipe(rowOf('Shopping'), -0.1);
    act(() => (rowOf('Shopping') as HTMLButtonElement).click());
    await away();
    expect(onSwipe).not.toHaveBeenCalled();
    expect(onOpen).not.toHaveBeenCalled();
    // The next tap opens it, as ever.
    act(() => (rowOf('Shopping') as HTMLButtonElement).click());
    expect(onOpen).toHaveBeenCalledWith('l');
  });

  it('swipes the cards, and the pinned lines, which unpin', () => {
    const onSwipe = vi.fn();
    show(page(shelf, { onSwipe }));
    swipe(document.querySelector('section[data-section="notes"] ol > li button')!, 0.3);
    expect(onSwipe).toHaveBeenLastCalledWith(packing, 'pin');
    unmount();
    laidOut('spotlight');
    show(page(shelf, { onSwipe }));
    const line = document.querySelector('section[data-section="pinned"] li button')!;
    swipe(line, 0.3);
    expect(onSwipe).toHaveBeenLastCalledWith(packing, 'pin');
  });

  it('does not swipe where the page has nothing to do with one', () => {
    laidOut('list');
    show(page(shelf));
    expect(rowOf('Shopping').parentElement?.getAttribute('style') ?? '').not.toContain('translate');
    expect(document.querySelector('[data-swiping]')).toBeNull();
    expect(rowOf('Shopping').parentElement?.tagName).toBe('LI');
  });
});

/** Organizations (docs/TEAMS.md): an invitation's card, New organization beside New workspace, and an organization's workspace. */
describe('organizations', () => {
  const signIn = () => {
    who.session = { token: 't', handle: 'matt', accountId: 7 };
  };
  const invite = (id: string, orgId: string, name: string, at: number) =>
    updateFeed(7, (state) => withFed(state, { id, rev: at, at, readAt: null, hidden: false, kind: 'invite', from: 'sam', org: { id: orgId, name }, body: { name }, state: 'pending' }, at));

  it('shows a card for the newest invitation still waiting whose organization is in the list, with Accept opening it', async () => {
    signIn();
    saveOrgs(7, {
      list: [
        { id: 'o1', name: 'Ghost', hue: null, role: 'member', state: 'invited', members: 1, invitedBy: 'sam', createdAt: 1 },
        { id: 'o3', name: 'Old', hue: null, role: 'member', state: 'invited', members: 1, invitedBy: 'sam', createdAt: 1 },
      ],
      at: 1,
    });
    invite('n1', 'o3', 'Old', now - 3 * day);
    invite('n2', 'o1', 'Ghost', now - day);
    // Newer still, but its organization is not in the list any more: deleted under it, or answered elsewhere.
    invite('n3', 'o2', 'Gone', now - 60_000);
    const onOrganization = vi.fn();
    show(page(shelf, { onOrganization }));
    const card = document.querySelector<HTMLElement>('[data-notice="invite"]')!;
    expect(card.textContent).toContain('sam invited you to Ghost');
    expect(card.textContent).not.toContain('Gone');
    await act(async () => button('Accept', card).click());
    expect(onOrganization).toHaveBeenCalledWith('o1');
  });

  it('opens the organization an only invitation was accepted to, though the accepting takes its card away', async () => {
    signIn();
    saveOrgs(7, { list: [{ id: 'o1', name: 'Ghost', hue: null, role: 'member', state: 'invited', members: 1, invitedBy: 'sam', createdAt: 1 }], at: 1 });
    invite('n1', 'o1', 'Ghost', now - day);
    const onOrganization = vi.fn();
    show(page(shelf, { onOrganization }));
    pass.held = true;
    await act(async () => button('Accept', document.querySelector<HTMLElement>('[data-notice="invite"]')!).click());
    pass.held = false;
    // The pass made matt a member, and the page was drawn again before it ended: the card has gone.
    expect(document.querySelector('[data-notice="invite"]')).toBeNull();
    expect(onOrganization).not.toHaveBeenCalled();
    // The page is told all the same when the pass ends, and opens the organization.
    await act(async () => pass.end?.());
    expect(onOrganization).toHaveBeenCalledWith('o1');
  });

  it('shows no card signed out, or with nothing waiting', () => {
    invite('n1', 'o1', 'Ghost', now - day);
    show(page(shelf));
    expect(document.querySelector('[data-notice="invite"]')).toBeNull();
    unmount();
    signIn();
    show(page(shelf));
    expect(document.querySelector('[data-notice="invite"]')).toBeNull();
  });

  it('offers New organization in the filters’ panel signed in, which opens its sheet, and not signed out', async () => {
    show(page(shelf, { onOrganization: () => undefined }));
    openFilters();
    expect(() => button('New organization')).toThrow();
    unmount();
    signIn();
    show(page(shelf, { onOrganization: () => undefined }));
    openFilters();
    act(() => button('New organization').click());
    expect(filterButton()?.getAttribute('aria-expanded')).toBe('false');
    expect(document.querySelector('[role="dialog"][aria-label="New organization"]')).not.toBeNull();
    expect(buttonSaying(document.body, 'Create')!.disabled).toBe(true);
  });

  it('marks an organization’s workspace in the panel and on its chip, and Edit on it opens the organization', () => {
    signIn();
    ensureOrgWorkspace({ id: 'o1', name: 'Ghost', hue: 'sea' });
    addWorkspace('Kitchen');
    reloadWorkspaces();
    chooseWorkspace('org-o1');
    const onOrganization = vi.fn();
    show(page(shelf, { onOrganization }));
    openFilters();
    const ghost = choices('Workspace').find((r) => r.textContent?.startsWith('Ghost'))!;
    expect(ghost.getAttribute('data-org')).toBe('o1');
    expect(ghost.querySelector('[role="img"][aria-label="Organization"]')).not.toBeNull();
    expect(choices('Workspace').find((r) => r.textContent?.startsWith('Kitchen'))?.hasAttribute('data-org')).toBe(false);
    act(() => button('Edit Ghost').click());
    expect(onOrganization).toHaveBeenCalledWith('o1');
    expect(filterButton()?.getAttribute('aria-expanded')).toBe('false');
    const chip = document.querySelector<HTMLElement>('[aria-label="Filters on"] [data-org="o1"]')!;
    expect(chip.querySelector('[role="img"][aria-label="Organization"]')).not.toBeNull();
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

  // The iPhone app records nothing yet (core/platform.ts `recordsVoice`): App hands the page no Speak.
  it('leaves Speak out of the dock, and out of the empty page’s hint, where nothing records', () => {
    show(page([], { onCapture: undefined }));
    expect(document.querySelector('button[aria-label="Speak a voice note"]')).toBeNull();
    expect(button('Write a note')).toBeTruthy();
    expect(document.querySelector('[class*="emptyHint"]')?.textContent).toBe('Tap + to write it.');
  });
});
