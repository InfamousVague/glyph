import { afterEach, describe, expect, it } from 'vitest';
import * as Y from 'yjs';
import { memoryDocs } from './docs.ts';
import { adoptTeamDoc, applyTextDiff, dropTeamDoc, forgetTeamDocs, heldTeamDocs, teamDoc } from './doc.ts';

/**
 * A team note's document on a device (core/team/doc.ts): seeded from the note's words or read from the store,
 * words from elsewhere reconciled into it as one change, updates pending until posted, and kept to the store.
 */

afterEach(() => {
  forgetTeamDocs();
});

describe('a team document', () => {
  it('is seeded from the note’s words with the whole of them pending, kept, and read back', async () => {
    const store = memoryDocs();
    expect(await teamDoc('n1', store)).toBeNull();
    const doc = (await teamDoc('n1', store, '# Roadmap\n- ship'))!;
    expect(doc.words()).toBe('# Roadmap\n- ship');
    expect(doc.pending()).toHaveLength(1);
    await doc.flush();
    forgetTeamDocs();
    const again = (await teamDoc('n1', store))!;
    expect(again.words()).toBe('# Roadmap\n- ship');
    expect(again.pending()).toHaveLength(1);
    expect(await store.read('n1')).toMatchObject({ seq: 0, snapshotSeq: 0 });
    // Posted: nothing pending, and the store says so after the flush.
    again.posted(1);
    await again.flush();
    expect((await store.read('n1'))!.pending).toEqual([]);
  });

  it('reconciles words written elsewhere as one change the team can merge with', async () => {
    const store = memoryDocs();
    const doc = (await teamDoc('n1', store, 'a\nb\nc'))!;
    doc.posted(1);
    let heard: string | null = null;
    doc.onWords((words) => (heard = words));
    expect(doc.reconcile('a\nB\nc\nd')).toBe(true);
    expect(doc.words()).toBe('a\nB\nc\nd');
    expect(heard).toBe('a\nB\nc\nd');
    expect(doc.pending()).toHaveLength(1);
    expect(doc.reconcile('a\nB\nc\nd')).toBe(false);
    // The change was one transaction in the middle: another device's edit at the end merges, nothing lost.
    const other = new Y.Doc();
    Y.applyUpdate(other, doc.snapshot());
    other.getText('body').insert(other.getText('body').length, '\ne');
    const update = Y.encodeStateAsUpdate(other, Y.encodeStateVector(doc.doc));
    expect(doc.applyRemote([update], 7)).toBe('a\nB\nc\nd\ne');
    expect(doc.seq).toBe(7);
    // A remote update is not pending.
    expect(doc.pending()).toHaveLength(1);
  });

  it('is adopted from the organization’s row over whatever the device holds, and dropped with the note', async () => {
    const store = memoryDocs();
    const theirs = new Y.Doc();
    theirs.getText('body').insert(0, 'from the team');
    const adopted = await adoptTeamDoc('n2', store, Y.encodeStateAsUpdate(theirs), 12);
    expect([adopted.seq, adopted.snapshotSeq]).toEqual([12, 12]);
    expect(adopted.words()).toBe('from the team');
    expect(adopted.pending()).toEqual([]);
    expect(heldTeamDocs()).toEqual(['n2']);
    expect(await store.read('n2')).toMatchObject({ seq: 12, snapshotSeq: 12 });
    // Adopted again, later: merged, not doubled.
    theirs.getText('body').insert(theirs.getText('body').length, ', again');
    const again = await adoptTeamDoc('n2', store, Y.encodeStateAsUpdate(theirs), 20);
    expect(again).toBe(adopted);
    expect(again.words()).toBe('from the team, again');
    expect(again.seq).toBe(20);
    await dropTeamDoc('n2', store);
    expect(heldTeamDocs()).toEqual([]);
    expect(await store.read('n2')).toBeNull();
  });

  it('applies the smallest change between two texts', () => {
    const doc = new Y.Doc();
    const text = doc.getText('body');
    text.insert(0, 'the quick brown fox');
    applyTextDiff(text, 'the quick brown fox', 'the slow brown fox');
    expect(text.toString()).toBe('the slow brown fox');
    applyTextDiff(text, 'the slow brown fox', '');
    expect(text.toString()).toBe('');
    applyTextDiff(text, '', 'new');
    expect(text.toString()).toBe('new');
  });
});
