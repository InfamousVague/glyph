import { describe, expect, it } from 'vitest';
import * as Y from 'yjs';
import { applyTextDiff } from './textDiff.ts';

/**
 * Words reconciled into a shared text (core/team/textDiff.ts) by whole characters: a character outside the basic
 * plane is two code units, and a change that kept the first of them and swapped the second would have Yjs cut the
 * pair and write U+FFFD into the document for every member.
 */

/** `from` held by one member, changed to `to` there, and the change carried to another who held the same. */
function carried(from: string, to: string): { here: string; there: string } {
  const here = new Y.Doc();
  const text = here.getText('words');
  text.insert(0, from);
  const there = new Y.Doc();
  Y.applyUpdate(there, Y.encodeStateAsUpdate(here));
  const before = Y.encodeStateVector(here);
  applyTextDiff(text, from, to);
  Y.applyUpdate(there, Y.encodeStateAsUpdate(here, before));
  return { here: text.toString(), there: there.getText('words').toString() };
}

function expectWhole(from: string, to: string): void {
  const { here, there } = carried(from, to);
  expect(here).toBe(to);
  expect(here).not.toContain('�');
  expect(there).toBe(to);
}

describe('a change between two characters that share half their code units', () => {
  it('swaps one for the other in the middle of a sentence', () => {
    expectWhole('It went 😀 on the day.', 'It went 😁 on the day.');
    expectWhole('The light is 🔴 now.', 'The light is 🟢 now.');
  });

  it('swaps one for the other at the start', () => {
    expectWhole('😀 it went well', '😁 it went well');
  });

  it('swaps one for the other at the end', () => {
    expectWhole('it went well 😀', 'it went well 😁');
    expectWhole('😀', '😁');
  });

  it('swaps one whose second half is the same', () => {
    // U+1F600 and U+1FA00: D83D DE00 and D83E DE00, the foot's side of the same cut.
    expectWhole('a \u{1F600} b', 'a \u{1FA00} b');
    expectWhole('\u{1F600}', '\u{1FA00}');
  });

  it('changes one member of a joined sequence', () => {
    expectWhole('The family 👨‍👩‍👧 came.', 'The family 👨‍👩‍👦 came.');
    expectWhole('👩‍🚀', '👩‍🚒');
  });

  it('adds and removes one beside another like it', () => {
    expectWhole('😀', '😀😁');
    expectWhole('😀😁', '😀');
    expectWhole('😁😀', '😀');
    expectWhole('a😀b', 'ab');
  });

  it('still keeps the common head and foot of plain words', () => {
    const doc = new Y.Doc();
    const text = doc.getText('words');
    text.insert(0, 'one two three');
    const deltas: unknown[] = [];
    text.observe((event) => deltas.push(event.delta));
    applyTextDiff(text, 'one two three', 'one 2 three');
    expect(text.toString()).toBe('one 2 three');
    expect(deltas).toEqual([[{ retain: 4 }, { delete: 3 }, { insert: '2' }]]);
  });

  it('merges with a change made elsewhere at the same moment', () => {
    const a = new Y.Doc();
    const b = new Y.Doc();
    a.getText('words').insert(0, 'mood 😀 today');
    Y.applyUpdate(b, Y.encodeStateAsUpdate(a));
    applyTextDiff(a.getText('words'), 'mood 😀 today', 'mood 😁 today');
    applyTextDiff(b.getText('words'), 'mood 😀 today', 'mood 😀 today, and tomorrow');
    const fromA = Y.encodeStateAsUpdate(a);
    const fromB = Y.encodeStateAsUpdate(b);
    Y.applyUpdate(a, fromB);
    Y.applyUpdate(b, fromA);
    expect(a.getText('words').toString()).toBe('mood 😁 today, and tomorrow');
    expect(b.getText('words').toString()).toBe(a.getText('words').toString());
    expect(a.getText('words').toString()).not.toContain('�');
  });
});
