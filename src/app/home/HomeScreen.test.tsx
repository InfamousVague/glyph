import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import { bookNoteBody } from '../book/book.ts';
import type { Updates } from '../core/ota.ts';
import { reloadPreferences } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace } from '../core/workspaces.ts';
import type { Note } from '../core/store.ts';
import { makeNote } from '../../test/notes.ts';
import { button, rerender, show, unmount } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

/**
 * The home page as a person reads it: the groups in their order, the empty page, the to-dos ticked off in place and
 * the ghost when the last one goes, and the dock. What each group holds is home/dashboard.ts's, tested there.
 */

// A card's small drawing is the editor (notes/NotePeek.tsx), which is nothing the page decides.
vi.mock('../notes/NotePeek.tsx', () => ({ NotePeek: () => null }));
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
const headings = () => [...document.querySelectorAll('h2')].map((h) => h.textContent?.replace(/\d+$/, '').trim());
const tasks = () => [...document.querySelectorAll('button[aria-label^="Tick off "]')].map((b) => b.getAttribute('aria-label')!.slice('Tick off '.length));

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
});
afterEach(() => unmount());

describe('the home page', () => {
  it('lays its groups out in their order: Pinned, Library, Recent, To do', () => {
    show(
      page([
        makeNote('p', '# Packing\n\n- [ ] Tent', { starred: true, updatedAt: 3 }),
        makeNote('b', bookNoteBody('Trip', ['Packing']), { updatedAt: 2 }),
        makeNote('r', '# Route', { updatedAt: 1 }),
      ]),
    );
    expect(headings()).toEqual(['Pinned', 'Library', 'Recent', 'To do']);
    // A page of a book says which on its card.
    expect(document.querySelector('[title="Page 1 of Trip"]')?.textContent).toBe('Trip');
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

  it('ticks a to-do off at once, before its note has been written, and names the note it is in', () => {
    const onTick = vi.fn();
    const notes = [makeNote('a', '# Shop\n\n- [ ] Milk\n- [ ] Eggs', { updatedAt: 2 })];
    show(page(notes, { onTick }));
    expect(tasks()).toEqual(['Milk', 'Eggs']);
    expect(document.querySelector('[class*=taskNote]')?.textContent).toBe('Shop');
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

  it('shows eight to-dos and counts the rest', () => {
    const many = Array.from({ length: 11 }, (_, i) => `- [ ] Thing ${i + 1}`).join('\n');
    show(page([makeNote('a', `# List\n\n${many}`)]));
    expect(tasks()).toHaveLength(8);
    expect(document.body.textContent).toContain('and 3 more in your notes');
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
