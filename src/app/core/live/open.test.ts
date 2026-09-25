import type { EditorView } from '@codemirror/view';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SyncHooks } from './hub.ts';
import type { SessionListener } from './session.ts';

/*
 * The note screen's door into live sync (open.ts): the editor bound once the room's document is in hand, the two
 * questions a joining note asks of the pass sync, and everything let go on the way out. The hub and the CodeMirror
 * binding are stood in for; the note store is the browser's own.
 */

/** What the hub was asked for, and the session it answers with (null for a note that will not go live). */
let opened: { noteId: string; words: string; listener: SessionListener; hooks: SyncHooks } | null = null;
let answer: { state: string } | null = { state: 'joining' };
const closed: string[] = [];
vi.mock('./hub.ts', () => ({
  openLive: async (noteId: string, words: string, listener: SessionListener, hooks: SyncHooks) => {
    opened = { noteId, words, listener, hooks };
    return answer;
  },
  closeLive: (noteId: string) => closed.push(noteId),
}));

const bound: unknown[] = [];
let unbindFails = false;
const unbound: unknown[] = [];
vi.mock('../../editor/liveBinding.ts', () => ({
  bindLive: (view: unknown, session: unknown) => bound.push([view, session]),
  unbindLive: (view: unknown) => {
    if (unbindFails) throw new Error('the view is gone');
    unbound.push(view);
  },
}));

let unsynced = true;
vi.mock('../sync/engine.ts', () => ({ hasUnsyncedChanges: () => unsynced }));

const { goLive } = await import('./open.ts');
const { createNote, listNotes, NOTES_CHANGED } = await import('../store.ts');

const view = { state: { doc: { toString: () => 'the words on screen' } } } as unknown as EditorView;

beforeEach(() => {
  opened = null;
  answer = { state: 'joining' };
  closed.length = 0;
  bound.length = 0;
  unbound.length = 0;
  unbindFails = false;
  unsynced = true;
  localStorage.clear();
});

describe('a note going live', () => {
  it('opens its room with the words on screen, and binds the editor once the document is ready, and once only', async () => {
    const peers: number[] = [];
    await goLive(view, 'a', (count) => peers.push(count));
    expect(opened).toMatchObject({ noteId: 'a', words: 'the words on screen' });
    expect(bound).toEqual([]);
    answer!.state = 'ready';
    opened!.listener.ready('the room’s words');
    opened!.listener.ready('the room’s words');
    expect(bound).toEqual([[view, answer]]);
    opened!.listener.peers(2);
    expect(peers).toEqual([2]);
  });

  it('binds at once a session that was ready before it was in hand', async () => {
    answer = { state: 'ready' };
    await goLive(view, 'a', () => undefined);
    expect(bound).toHaveLength(1);
  });

  it('asks the pass sync about the saved note, not the words on screen, and a note not saved has nothing unsent', async () => {
    await goLive(view, 'a', () => undefined);
    expect(await opened!.hooks.hasUnsynced('a')).toBe(false);
    await createNote('a', 'saved words');
    expect(await opened!.hooks.hasUnsynced('a')).toBe(true);
    unsynced = false;
    expect(await opened!.hooks.hasUnsynced('a')).toBe(false);
  });

  it('keeps this device’s words as a note of their own when they lose to the room’s, and tells the list', async () => {
    let told = 0;
    const onChanged = () => {
      told += 1;
    };
    window.addEventListener(NOTES_CHANGED, onChanged);
    await goLive(view, 'a', () => undefined);
    await opened!.hooks.keepCopy('a', 'my words');
    expect((await listNotes()).map((note) => note.body)).toEqual(['my words']);
    expect(told).toBe(1);
    window.removeEventListener(NOTES_CHANGED, onChanged);
  });
});

describe('a note leaving live sync', () => {
  it('unbinds the editor, leaves the room, and says nobody else is there', async () => {
    answer = { state: 'ready' };
    const peers: number[] = [];
    const stop = await goLive(view, 'a', (count) => peers.push(count));
    stop();
    expect(unbound).toEqual([view]);
    expect(closed).toEqual(['a']);
    expect(peers).toEqual([0]);
  });

  it('still leaves the room when the editor went first, or was never bound', async () => {
    answer = { state: 'ready' };
    unbindFails = true;
    const stop = await goLive(view, 'a', () => undefined);
    expect(() => stop()).not.toThrow();
    expect(closed).toEqual(['a']);
    unbindFails = false;
    answer = { state: 'joining' };
    (await goLive(view, 'b', () => undefined))();
    expect(unbound).toEqual([]);
    expect(closed).toEqual(['a', 'b']);
  });

  it('has nothing to let go of for a note that never went live', async () => {
    answer = null;
    const peers: number[] = [];
    (await goLive(view, 'a', (count) => peers.push(count)))();
    expect(closed).toEqual([]);
    expect(peers).toEqual([]);
  });
});
