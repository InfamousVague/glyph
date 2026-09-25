import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, StrictMode } from 'react';
import { ToastProvider } from '@glacier/react';
import { NOTE_SAVED, type Note } from '../core/store.ts';
import { isTrashed } from '../core/trash.ts';
import { reloadPreferences } from '../core/preferences.ts';
import { makeNote } from '../../test/notes.ts';
import { button, rerender, show } from '../../test/render.tsx';

/**
 * The Shell's background duties that a person would notice going wrong: the sample note arriving in a fresh library
 * and never in a full one, the sidebar reading the notes again after a save, the memo sweep, and a voice command's
 * Undo offered again after the app was stopped before it could be used.
 */

// The Glacier kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

const seed = vi.hoisted(() => ({ seedSampleNote: vi.fn(async (_count: number): Promise<Note | null> => null) }));
vi.mock('../core/seed.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/seed.ts')>()),
  sampleNoteSeeded: () => false,
  seedSampleNote: seed.seedSampleNote,
}));
const commands = vi.hoisted(() => ({
  latest: vi.fn(async (): Promise<{ mutationId: string; noteId: string; kind: 'create' | 'update'; createdAt: number } | null> => null),
  undo: vi.fn(async (_id: string) => ({ kind: 'undone' })),
}));
vi.mock('../core/store.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/store.ts')>()),
  latestCommandMutation: commands.latest,
  undoCommandMutation: commands.undo,
}));

const { useHousekeeping } = await import('./useHousekeeping.ts');

function Probe({ notes = [], loading = false, refresh, sidebar = false }: { notes?: Note[]; loading?: boolean; refresh: () => Promise<void>; sidebar?: boolean }) {
  useHousekeeping({ notes, loading, refresh, sidebar });
  return null;
}
const tree = (props: Parameters<typeof Probe>[0]) => (
  <ToastProvider>
    <Probe {...props} />
  </ToastProvider>
);
const keep = (props: Parameters<typeof Probe>[0]) => show(tree(props));

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  seed.seedSampleNote.mockClear();
  commands.latest.mockReset().mockResolvedValue(null);
  commands.undo.mockClear();
});
afterEach(() => vi.useRealTimers());

describe('the sample note', () => {
  it('is asked for four seconds after the first read, with how many notes there were, and the notes read again', async () => {
    vi.useFakeTimers();
    seed.seedSampleNote.mockResolvedValueOnce(makeNote('sample'));
    const refresh = vi.fn(async () => undefined);
    keep({ refresh, loading: true });
    // Not while the first read is still out: a slow phone is not an empty library.
    await act(async () => void vi.advanceTimersByTime(5000));
    expect(seed.seedSampleNote).not.toHaveBeenCalled();
    rerender(tree({ refresh }));
    await act(async () => void vi.advanceTimersByTime(3999));
    expect(seed.seedSampleNote).not.toHaveBeenCalled();
    await act(async () => void vi.advanceTimersByTime(1));
    expect(seed.seedSampleNote).toHaveBeenCalledWith(0);
    expect(refresh).toHaveBeenCalled();
  });
});

describe('the sidebar beside a note', () => {
  it('reads the notes again a moment after the last of a run of saves, only when it is there to show them', () => {
    vi.useFakeTimers();
    const refresh = vi.fn(async () => undefined);
    keep({ refresh, sidebar: false });
    act(() => {
      window.dispatchEvent(new Event(NOTE_SAVED));
      vi.advanceTimersByTime(1000);
    });
    expect(refresh).not.toHaveBeenCalled();
    rerender(tree({ refresh, sidebar: true }));
    act(() => {
      window.dispatchEvent(new Event(NOTE_SAVED));
      vi.advanceTimersByTime(200);
      window.dispatchEvent(new Event(NOTE_SAVED));
      vi.advanceTimersByTime(299);
    });
    expect(refresh).not.toHaveBeenCalled();
    act(() => void vi.advanceTimersByTime(1));
    expect(refresh).toHaveBeenCalledTimes(1);
  });
});

describe('the memos', () => {
  it('go to the trash on the first read, and the notes are read again', async () => {
    const refresh = vi.fn(async () => undefined);
    keep({ refresh, notes: [makeNote('m', '---\nkind: memo\n---\nMilk'), makeNote('n', '# A note')] });
    await act(async () => {
      // The sweep runs as the first read lands.
    });
    expect(isTrashed('m')).toBe(true);
    expect(isTrashed('n')).toBe(false);
    expect(refresh).toHaveBeenCalled();
  });
});

describe('a voice command left undoable', () => {
  it('is offered its Undo again once, which undoes it and reads the notes again', async () => {
    commands.latest.mockResolvedValue({ mutationId: 'm1', noteId: 'n', kind: 'update', createdAt: 0 });
    const refresh = vi.fn(async () => undefined);
    // Under StrictMode, as main.tsx mounts the app: its effects are run, cleaned up and run again.
    show(<StrictMode>{tree({ refresh })}</StrictMode>);
    await act(async () => {
      // The pending record is asked for once, as the app starts.
    });
    expect(document.body.textContent!.split('Voice command changed a note.')).toHaveLength(2);
    await act(async () => button('Undo').click());
    expect(commands.undo).toHaveBeenCalledWith('m1');
    expect(refresh).toHaveBeenCalled();
    expect(commands.latest).toHaveBeenCalledTimes(1);
  });
});
