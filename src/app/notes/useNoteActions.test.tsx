import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { ToastProvider } from '@glacier/react';
import { createNote, getNote } from '../core/store.ts';
import { reloadPreferences } from '../core/preferences.ts';
import { isTrashed, trashNote } from '../core/trash.ts';
import { addWorkspace, fileNote, workspaceOf } from '../core/workspaces.ts';
import { makeNote } from '../../test/notes.ts';
import { button, show, unmount } from '../../test/render.tsx';
import type { NoteActions } from './useNoteActions.ts';

/**
 * Pin, archive, the trash and the delete for good, each with its words and its Undo - and the delete that is deferred
 * rather than done and undone: hidden at once, gone from the store when its Undo runs out, and made final the moment
 * anything could outlive the toast (the header of useNoteActions.ts says why each of those).
 */

// The Glacier kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
const { useNoteActions } = await import('./useNoteActions.ts');

let actions: NoteActions;
const refresh = vi.fn(async () => undefined);
function Probe() {
  actions = useNoteActions(refresh);
  return null;
}
const mount = () =>
  show(
    <ToastProvider>
      <Probe />
    </ToastProvider>,
  );

/** Lets a delete's awaits land: the store's writes and the refresh after them are promises, not timers. */
const settle = () =>
  act(async () => {
    for (let i = 0; i < 10; i += 1) await Promise.resolve();
  });
const said = () => document.body.textContent ?? '';
const apples = makeNote('a', '# Apples');
const bread = makeNote('b', '# Bread');
const cheese = makeNote('c', '# Cheese');

beforeEach(async () => {
  localStorage.clear();
  reloadPreferences();
  refresh.mockClear();
  await createNote('a', '# Apples');
  await createNote('b', '# Bread');
});
afterEach(() => vi.useRealTimers());

describe('deleting for good', () => {
  it('hides the note at once, and removes it, its filing and its place in the trash only when the Undo runs out', async () => {
    vi.useFakeTimers();
    const space = addWorkspace('Kitchen')!;
    fileNote('a', space.id);
    trashNote('a');
    mount();
    act(() => actions.destroy((apples)));
    expect(actions.hidden.has('a')).toBe(true);
    expect(said()).toContain('Deleted “Apples” for good.');
    await act(async () => void vi.advanceTimersByTime(4999));
    await settle();
    expect(await getNote('a')).not.toBeNull();
    await act(async () => void vi.advanceTimersByTime(1));
    await settle();
    expect(await getNote('a')).toBeNull();
    expect(workspaceOf('a')).toBeNull();
    expect(isTrashed('a')).toBe(false);
    expect(actions.hidden.has('a')).toBe(false);
    expect(refresh).toHaveBeenCalled();
  });

  it('keeps the note when Undo is pressed in time', async () => {
    vi.useFakeTimers();
    mount();
    act(() => actions.destroy(apples));
    act(() => button('Undo').click());
    expect(actions.hidden.has('a')).toBe(false);
    await act(async () => void vi.advanceTimersByTime(10_000));
    await settle();
    expect(await getNote('a')).not.toBeNull();
  });

  it('makes the first final when a second is deleted, since only one Undo is on screen', async () => {
    mount();
    act(() => actions.destroy(apples));
    act(() => actions.destroy(bread));
    await settle();
    expect(await getNote('a')).toBeNull();
    expect(await getNote('b')).not.toBeNull();
    expect(actions.hidden.has('b')).toBe(true);
  });

  it('is made final when the app goes to the background, is put away, or the list asks for it', async () => {
    mount();
    act(() => actions.destroy(apples));
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
    act(() => void document.dispatchEvent(new Event('visibilitychange')));
    delete (document as { visibilityState?: unknown }).visibilityState;
    await settle();
    expect(await getNote('a')).toBeNull();

    act(() => actions.destroy(bread));
    act(() => void window.dispatchEvent(new Event('pagehide')));
    await settle();
    expect(await getNote('b')).toBeNull();

    await createNote('c', '# Cheese');
    act(() => actions.destroy(cheese));
    await act(async () => actions.flushDeletes());
    expect(await getNote('c')).toBeNull();
  });

  it('is made final when the screen that asked for it goes', async () => {
    mount();
    act(() => actions.destroy(apples));
    unmount();
    await settle();
    expect(await getNote('a')).toBeNull();
  });
});

describe('the trash', () => {
  it('takes a note with an Undo that brings it back, and gives it back with words of its own', () => {
    mount();
    act(() => actions.remove(apples));
    expect(isTrashed('a')).toBe(true);
    expect(said()).toContain('Moved “Apples” to the Trash.');
    act(() => button('Undo').click());
    expect(isTrashed('a')).toBe(false);
    trashNote('b');
    act(() => actions.restore(bread));
    expect(isTrashed('b')).toBe(false);
    expect(said()).toContain('“Bread” is back in your notes.');
  });

  it('empties at once, and says how many went', async () => {
    trashNote('a');
    trashNote('b');
    mount();
    await act(async () => actions.emptyTrash([apples, bread]));
    expect(await getNote('a')).toBeNull();
    expect(await getNote('b')).toBeNull();
    expect(isTrashed('a')).toBe(false);
    expect(said()).toContain('Deleted 2 notes for good.');
  });

  it('names a note by its title only while the title is short enough to read in a line', async () => {
    await createNote('long', '# A title far too long to fit in the one line a toast has');
    mount();
    act(() => actions.remove(makeNote('long', '# A title far too long to fit in the one line a toast has')));
    expect(said()).toContain('Moved the note to the Trash.');
  });
});

describe('pin and archive', () => {
  it('pin at once, and archive with an Undo that brings it back', async () => {
    mount();
    await act(async () => actions.pin(apples));
    await settle();
    expect((await getNote('a'))?.starred).toBe(true);
    await act(async () => actions.archive(bread, true));
    await settle();
    expect((await getNote('b'))?.archivedAt).toBeTruthy();
    expect(said()).toContain('Archived “Bread”.');
    await act(async () => button('Undo').click());
    await settle();
    expect((await getNote('b'))?.archivedAt ?? null).toBeNull();
  });
});

