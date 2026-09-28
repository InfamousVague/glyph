import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { goBack } from '../core/back.ts';
import { button, buttonSaying, rerender, show, typeInto, waitUntil } from '../../test/render.tsx';
import { dragGrip, layRowsOut } from '../../test/rows.ts';
import { inLocale } from '../../test/locale.ts';

// The kit's switch asks the window's resolution as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

/** The ask a journal's place switch makes from its press (core/location.ts `askFromPress`), counted, and its answer. */
const device = vi.hoisted(() => ({ asked: 0, answer: null as string | null }));
vi.mock('../core/location.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/location.ts')>();
  return {
    ...real,
    askFromPress: async () => {
      device.asked += 1;
      return device.answer;
    },
  };
});

const { NewBookSheet } = await import('./NewBookSheet.tsx');
const { entryPlaceHint } = await import('./entryPlace.ts');
const { setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const { PRESETS } = await import('./journal.ts');

/**
 * The New notebook sheet: a name, notes picked as pages in the order they are tapped, moved and left out, and one note
 * made with exactly that index. Closed without making it, nothing is written.
 */

/** The row that makes the book: its words, then a hint that says what it will make. */
const make = () => buttonSaying(document.body, 'Make the notebook')!;
/** Words typed into the field whose label says `label`. */
const type = (label: string, value: string) => {
  const field = [...document.querySelectorAll<HTMLInputElement>('input')].find((i) => i.closest('label')?.textContent?.includes(label));
  if (!field) throw new Error(`no field ${label}`);
  typeInto(field, value);
};
const pages = () => [...document.querySelectorAll('ol[aria-label="Pages in this notebook"] li')].map((li) => li.querySelector('[class*=pageTitle]')?.textContent);

describe('the New notebook sheet', () => {
  it('is nothing while closed, and makes nothing when closed', () => {
    const onCreate = vi.fn();
    const onClose = vi.fn();
    show(<NewBookSheet open={false} onClose={onClose} titles={['A']} onCreate={onCreate} />);
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(onCreate).not.toHaveBeenCalled();
  });

  it('marks a note that is a canvas with the canvas mark, in the list and among the pages', () => {
    show(<NewBookSheet open onClose={() => {}} titles={['Packing', 'Route map']} onCreate={() => {}} isCanvas={(t) => t === 'Route map'} />);
    const marked = () => [...document.querySelectorAll('[title="A canvas"]')].map((m) => m.parentElement?.textContent?.trim());
    expect(marked()).toEqual(['Route map']);
    act(() => button('Route map').click());
    expect(marked()).toEqual(['Route map', 'Route map']);
  });

  it('needs a name before it will make the book', () => {
    const onCreate = vi.fn();
    show(<NewBookSheet open onClose={() => {}} titles={[]} onCreate={onCreate} />);
    expect(make().disabled).toBe(true);
    type('Name', 'Trip');
    expect(make().disabled).toBe(false);
    act(() => make().click());
    expect(onCreate).toHaveBeenCalledWith('Trip', []);
  });

  it('picks pages in the order tapped, finds by name, moves and leaves out, and makes the book with that index', () => {
    const onCreate = vi.fn();
    const onClose = vi.fn();
    show(<NewBookSheet open onClose={onClose} titles={['Packing', 'Days', 'Who comes', 'Food']} onCreate={onCreate} />);
    type('Name', 'Cabin trip');
    act(() => button('Days').click());
    act(() => button('Packing').click());
    act(() => button('Food').click());
    expect(pages()).toEqual(['Days', 'Packing', 'Food']);
    // A second tap takes it out; a search narrows the list.
    act(() => button('Food').click());
    expect(pages()).toEqual(['Days', 'Packing']);
    type('Find a note', 'who');
    expect([...document.querySelectorAll('ul[aria-label="Notes"] button')].map((b) => b.textContent?.trim())).toEqual(['Who comes']);
    act(() => button('Move Packing up').click());
    expect(pages()).toEqual(['Packing', 'Days']);
    act(() => button('Move Packing up').click());
    expect(pages()).toEqual(['Packing', 'Days']);
    act(() => make().click());
    expect(onCreate).toHaveBeenCalledWith('Cabin trip', ['Packing', 'Days']);
    expect(onClose).toHaveBeenCalled();
  });

  it('closes on a back gesture while open, and holds none while closed', () => {
    const onClose = vi.fn();
    show(<NewBookSheet open onClose={onClose} titles={[]} onCreate={() => {}} />);
    expect(goBack()).toBe(true);
    expect(onClose).toHaveBeenCalledTimes(1);
    rerender(<NewBookSheet open={false} onClose={onClose} titles={[]} onCreate={() => {}} />);
    expect(goBack()).toBe(false);
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('moves a page dragged by its grip, and leaves one out by its cross', () => {
    const onCreate = vi.fn();
    show(<NewBookSheet open onClose={() => {}} titles={['Packing', 'Days', 'Food']} onCreate={onCreate} />);
    type('Name', 'Trip');
    for (const title of ['Packing', 'Days', 'Food']) act(() => button(title).click());
    const rows = [...document.querySelectorAll<HTMLElement>('ol[aria-label="Pages in this notebook"] li')];
    layRowsOut(rows);
    // Food, from the bottom to above Packing's middle: the first page.
    dragGrip(rows[2]!.querySelector('[class*=grip]')!, 100, 10);
    expect(pages()).toEqual(['Food', 'Packing', 'Days']);
    act(() => button('Leave Packing out').click());
    expect(pages()).toEqual(['Food', 'Days']);
    act(() => make().click());
    expect(onCreate).toHaveBeenCalledWith('Trip', ['Food', 'Days']);
  });
});

describe('a journal from the New notebook sheet', () => {
  beforeEach(() => {
    localStorage.clear();
    setPreferences({ ...DEFAULT_PREFERENCES });
    device.asked = 0;
    device.answer = null;
  });

  /** The page an entry would start as now, as the preview's editor draws it. */
  const preview = () => document.querySelector('[aria-label="How a new entry starts"]')?.textContent ?? '';
  const journal = () => act(() => document.querySelector<HTMLElement>('[role="radio"][aria-checked="false"]')!.click());
  const makeJournal = () => buttonSaying(document.body, 'Make the journal')!;

  it('offers Notebook or Journal only where a journal can be made, and Journal swaps the pages for the template', () => {
    show(<NewBookSheet open onClose={() => {}} titles={['Packing']} onCreate={() => {}} />);
    expect(document.querySelector('[role="radiogroup"]')).toBeNull();
    rerender(<NewBookSheet open onClose={() => {}} titles={['Packing']} onCreate={() => {}} onCreateJournal={() => {}} />);
    expect([...document.querySelectorAll('[role="radio"]')].map((r) => [r.textContent, r.getAttribute('aria-checked')])).toEqual([
      ['Notebook', 'true'],
      ['Journal', 'false'],
    ]);
    journal();
    expect(document.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('New journal');
    expect(document.body.textContent).toContain('New journal');
    expect(document.querySelector<HTMLInputElement>('input[placeholder="Diary"]')).not.toBeNull();
    expect(document.querySelector('ul[aria-label="Notes"]')).toBeNull();
    expect(document.body.textContent).toContain('Each entry starts with');
    expect(buttonSaying(document.body, 'Make the notebook')).toBeUndefined();
  });

  it('opens on Journal from the palette, needs a name, and makes the journal with its template and place', () => {
    const onCreateJournal = vi.fn();
    const onClose = vi.fn();
    show(<NewBookSheet open kind="journal" onClose={onClose} titles={[]} onCreate={() => {}} onCreateJournal={onCreateJournal} />);
    expect(makeJournal().disabled).toBe(true);
    expect(makeJournal().textContent).toContain('Empty, ready for its first entry.');
    type('Name', 'Diary');
    act(() => button('A day’s to-dos').click());
    act(() => makeJournal().click());
    expect(onCreateJournal).toHaveBeenCalledWith('Diary', PRESETS[3]!.text, true);
    expect(onClose).toHaveBeenCalled();
  });

  it('shows the page an entry would start as, following the choice and your own template', async () => {
    show(<NewBookSheet open kind="journal" onClose={() => {}} titles={[]} onCreate={() => {}} onCreateJournal={() => {}} />);
    type('Name', 'Diary');
    await waitUntil(() => expect(preview()).toMatch(/Where you are, with the map, at the top\..*\d\d:\d\d/));
    act(() => button('A morning page').click());
    await waitUntil(() => expect(preview()).toContain('What is on your mind this morning?'));
    act(() => button('My own').click());
    const box = document.querySelector<HTMLTextAreaElement>('textarea[aria-label="Your own template"]')!;
    // Your own starts from what was chosen, to change.
    expect(box.value).toBe(PRESETS[2]!.text);
    typeInto(box, 'Dear {{journal}}, ');
    await waitUntil(() => expect(preview()).toContain('Dear Diary,'));
    expect(document.body.textContent).toContain('Words inside a format go in square brackets, as in {{date:D MMMM [at] HH:mm}}.');
  });

  it('puts a placeholder in at the caret', () => {
    show(<NewBookSheet open kind="journal" onClose={() => {}} titles={[]} onCreate={() => {}} onCreateJournal={() => {}} />);
    act(() => button('My own').click());
    const box = document.querySelector<HTMLTextAreaElement>('textarea[aria-label="Your own template"]')!;
    typeInto(box, 'At  today.');
    box.setSelectionRange(3, 3);
    act(() => button('{{time}}').click());
    expect(box.value).toBe('At {{time}} today.');
    expect(box.selectionStart).toBe(11);
  });

  it('starts its place switch on this device’s Tag new notes alone, and asks from the press it is turned on with', () => {
    setPreferences({ tagNewNotes: false });
    const onCreateJournal = vi.fn();
    show(<NewBookSheet open kind="journal" onClose={() => {}} titles={[]} onCreate={() => {}} onCreateJournal={onCreateJournal} />);
    const flip = () => act(() => document.querySelector<HTMLElement>('input[aria-label="With where you are"]')!.click());
    expect(document.querySelector<HTMLInputElement>('input[aria-label="With where you are"]')?.checked).toBe(false);
    expect(preview()).not.toContain('Where you are');
    flip();
    expect(device.asked).toBe(1);
    // Off asks nothing.
    flip();
    expect(device.asked).toBe(1);
    type('Name', 'Log');
    act(() => makeJournal().click());
    expect(onCreateJournal).toHaveBeenCalledWith('Log', PRESETS[0]!.text, false);
  });

  it('says under the switch what keeping a place means here, or why entries made here keep none', () => {
    const can = { ok: true } as const;
    expect(entryPlaceHint({ can, refused: null, asksName: true })).toBe('Each entry keeps where you are. Its name is asked of OpenStreetMap once.');
    expect(entryPlaceHint({ can, refused: null, asksName: false })).toBe('Each entry keeps where you are.');
    expect(entryPlaceHint({ can: { ok: false, why: 'local-only' }, refused: null, asksName: true })).toBe('Local only is on, so entries made here keep no place.');
    expect(entryPlaceHint({ can: { ok: false, why: 'mac' }, refused: 'refused', asksName: true })).toBe('This Mac can’t say where it is. Entries made on the phone keep theirs.');
    expect(entryPlaceHint({ can: { ok: false, why: 'unavailable' }, refused: null, asksName: true })).toBe('Update Ghost.md to keep where entries were written.');
    expect(entryPlaceHint({ can: { ok: false, why: 'none' }, refused: null, asksName: true })).toBe('This browser can’t say where you are.');
    expect(entryPlaceHint({ can, refused: 'blocked', asksName: true })).toBe('Ghost.md wasn’t allowed to know where you are. Allow location for this site in the browser’s settings, then turn this on again.');
    for (const hint of [entryPlaceHint({ can, refused: null, asksName: true })]) expect(hint).not.toMatch(/[;—–…]/);
  });

  it('fills the preview in the device’s language', async () => {
    await inLocale('en-GB', async () => {
      show(<NewBookSheet open kind="journal" onClose={() => {}} titles={[]} onCreate={() => {}} onCreateJournal={() => {}} />);
      await waitUntil(() => expect(preview()).toMatch(/(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) \d{1,2} [A-Z][a-z]+/));
    });
  });
});
