import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { show, unmount } from '../../test/render.tsx';
import type { Note } from './store.ts';

/*
 * The list's door (store.ts `useNotes`): the first read, which is the one that can fail on a phone, and the three
 * things that make the list ask again - a note changed elsewhere, the app coming back, and the activity's refresh.
 * A phone is core/tauri.ts mocked, answering `list_notes` with whatever each test lines up.
 */

let native = false;
/** What each `list_notes` answers, in turn: a list, or an error to reject with. The last one repeats. */
let answers: (Note[] | Error)[] = [];
let asked = 0;

vi.mock('./tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string) => {
    if (command !== 'list_notes') throw new Error(`unexpected ${command}`);
    const answer = answers[Math.min(asked, answers.length - 1)];
    asked += 1;
    if (answer instanceof Error) throw answer;
    return answer ?? [];
  },
}));

const { createNote, NOTES_CHANGED, useNotes } = await import('./store.ts');

/** The hook's latest answer, as the list screen would have it. */
let latest: ReturnType<typeof useNotes> | null = null;
function List() {
  latest = useNotes();
  return null;
}

/** Runs the clock on by `ms`, letting every read it sets off land inside act. */
async function wait(ms: number): Promise<void> {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}

beforeEach(() => {
  native = false;
  answers = [];
  asked = 0;
  latest = null;
  localStorage.clear();
  vi.useFakeTimers();
  vi.spyOn(console, 'info').mockImplementation(() => undefined);
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('the notes list in a browser', () => {
  it('reads the store, and reads it again when a note changes elsewhere, the app comes back, or the activity asks', async () => {
    await createNote('a', '# One');
    show(<List />);
    await wait(0);
    expect(latest?.loading).toBe(false);
    expect(latest?.notes.map((n) => n.id)).toEqual(['a']);

    await createNote('b', '# Two');
    window.dispatchEvent(new Event(NOTES_CHANGED));
    await wait(0);
    expect(latest?.notes.map((n) => n.id)).toEqual(['b', 'a']);

    await createNote('c', '# Three');
    document.dispatchEvent(new Event('visibilitychange'));
    await wait(0);
    expect(latest?.notes).toHaveLength(3);

    await createNote('d', '# Four');
    act(() => window.__glyph?.refresh?.());
    await wait(0);
    expect(latest?.notes).toHaveLength(4);
  });

  it('stops answering the activity once the list is gone', async () => {
    show(<List />);
    await wait(0);
    expect(window.__glyph?.refresh).toBeTypeOf('function');
    unmount();
    expect(window.__glyph?.refresh).toBeUndefined();
  });
});

describe('the notes list on a phone', () => {
  beforeEach(() => {
    native = true;
  });

  it('tries a failed first read again, so a store still opening does not leave the list blank', async () => {
    answers = [new Error('the store is still opening'), new Error('the index is busy'), [makeNote('kept', '# Kept')]];
    show(<List />);
    await wait(0);
    expect(asked).toBe(1);
    expect(latest?.loading).toBe(true);
    await wait(250);
    expect(asked).toBe(2);
    await wait(899);
    expect(asked).toBe(2);
    await wait(1);
    expect(asked).toBe(3);
    expect(latest?.loading).toBe(false);
    expect(latest?.notes.map((n) => n.id)).toEqual(['kept']);
  });

  it('gives up after the last retry rather than asking for ever', async () => {
    answers = [new Error('gone')];
    show(<List />);
    await wait(250 + 900 + 2400 + 10_000);
    expect(asked).toBe(4);
    expect(console.warn).toHaveBeenCalledTimes(1);
  });

  it('asks once more, a moment later, when the first answer is an empty library', async () => {
    answers = [[], [makeNote('back', '# Back')]];
    show(<List />);
    await wait(0);
    expect(latest?.notes).toEqual([]);
    expect(latest?.loading).toBe(false);
    await wait(1199);
    expect(asked).toBe(1);
    await wait(1);
    expect(asked).toBe(2);
    expect(latest?.notes.map((n) => n.id)).toEqual(['back']);
  });
});
