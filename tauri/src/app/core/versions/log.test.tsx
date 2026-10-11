import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { show, unmount, waitUntil } from '../../../test/render.tsx';
import { changesIn, changesOf, newestFirst, useChangesAcross, type ChangesRead } from './log.ts';
import { readFile, writeFile } from './file.ts';
import { keepVersion } from './record.ts';
import { writeVersionsFile } from './store.ts';

/**
 * The changes across many notes (core/versions/log.ts), for an organization's audit log: each note's versions as a
 * line each, every note's together newest first, read a few at a time and read again as a note's file changes.
 */

const DAY = 86_400_000;

beforeEach(() => {
  localStorage.clear();
});

afterEach(() => {
  unmount();
  localStorage.clear();
});

describe('a note’s changes', () => {
  it('are its versions, each with its counts, the first line it changed, and whether it began the note', () => {
    const file = writeFile('n1', [
      { at: 1_000, by: 'matt', text: '# Plan\n- book the venue' },
      { at: 2_000, by: 'sam', text: '# Plan\n- book the venue (done)\n- send invites', label: 'Before the review' },
      { at: 3_000, by: 'sam', text: '# Plan\n- book the venue (done)\n- send invites', label: 'Named only' },
    ]);
    const changes = changesIn('n1', readFile(file)!.versions);
    expect(changes).toEqual([
      { noteId: 'n1', n: 1, at: 1_000, by: 'matt', added: 2, removed: 0, peek: { kind: 'add', text: '# Plan' }, first: true },
      { noteId: 'n1', n: 2, at: 2_000, by: 'sam', label: 'Before the review', added: 2, removed: 1, peek: { kind: 'del', text: '- book the venue' }, first: false },
      { noteId: 'n1', n: 3, at: 3_000, by: 'sam', label: 'Named only', added: 0, removed: 0, peek: null, first: false },
    ]);
  });

  it('are read from the note’s file, with how many versions could not be', async () => {
    await keepVersion('n2', 'Milk', { now: 1_000 });
    await keepVersion('n2', 'Milk\nEggs', { now: 2_000 });
    const read = await changesOf('n2');
    expect(read.damaged).toBe(0);
    expect(read.changes.map((c) => [c.n, c.by, c.added, c.peek?.text])).toEqual([
      [1, 'me', 1, 'Milk'],
      [2, 'me', 1, 'Eggs'],
    ]);
    expect(await changesOf('nobody')).toEqual({ changes: [], damaged: 0 });
  });

  it('order newest first, and the same moment by note and then the later version', () => {
    const at = (noteId: string, n: number, when: number) => ({ noteId, n, at: when, by: 'me', added: 0, removed: 0, peek: null, first: n === 1 });
    const sorted = [at('b', 1, 5), at('a', 2, 5), at('a', 1, 5), at('c', 1, 9), at('a', 3, 1)].sort(newestFirst);
    expect(sorted.map((c) => `${c.noteId}${c.n}`)).toEqual(['c1', 'a2', 'a1', 'b1', 'a3']);
  });
});

describe('the changes across notes', () => {
  let seen: ChangesRead | null = null;
  function Across({ ids }: { ids: readonly string[] }) {
    seen = useChangesAcross(ids);
    return null;
  }

  it('come in as the files are read, every note’s together newest first, and a note that leaves the set goes with them', async () => {
    const now = Date.now();
    await keepVersion('a', '# Roadmap', { now: now - 2 * DAY });
    await keepVersion('a', '# Roadmap\n- ship', { now: now - 60_000 });
    await keepVersion('b', '# Standup', { now: now - DAY });
    seen = null;
    show(<Across ids={['a', 'b', 'c']} />);
    await waitUntil(() => expect(seen?.read).toBe(3));
    expect(seen!.total).toBe(3);
    expect(seen!.damaged).toBe(0);
    expect(seen!.changes.map((c) => `${c.noteId}${c.n}`)).toEqual(['a2', 'b1', 'a1']);
    // A note unfiled from the workspace: its changes go, and the count with them.
    show(<Across ids={['b', 'c']} />);
    await waitUntil(() => expect(seen?.changes.map((c) => `${c.noteId}${c.n}`)).toEqual(['b1']));
    expect(seen!.read).toBe(2);
    expect(seen!.total).toBe(2);
  });

  it('read a note again when its file changes here, and only that note', async () => {
    await keepVersion('a', '# Roadmap', { now: 1_000 });
    seen = null;
    show(<Across ids={['a', 'b']} />);
    await waitUntil(() => expect(seen?.read).toBe(2));
    expect(seen!.changes).toHaveLength(1);
    await act(async () => {
      await keepVersion('b', '# Standup', { now: 2_000 });
    });
    await waitUntil(() => expect(seen?.changes.map((c) => `${c.noteId}${c.n}`)).toEqual(['b1', 'a1']));
    // A file of someone else's changing is nothing to the log.
    await act(async () => {
      await writeVersionsFile('elsewhere', writeFile('elsewhere', [{ at: 3_000, by: 'me', text: 'x' }]));
    });
    expect(seen!.changes).toHaveLength(2);
  });

  it('is nothing for no notes, and does not wait', () => {
    seen = null;
    show(<Across ids={[]} />);
    expect(seen).toEqual({ changes: [], damaged: 0, read: 0, total: 0 });
  });
});
