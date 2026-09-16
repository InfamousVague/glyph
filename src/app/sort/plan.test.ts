import { describe, expect, it } from 'vitest';
import { UNSORTED_MEMOS, leftover, memosNote, onlyMemos, readPlacements, rulePlacements } from './plan.ts';

const notes = [
  { id: 'g', title: 'Groceries' },
  { id: 'w', title: 'Work' },
];

describe('sorting a memo', () => {
  const memo = 'Add oat milk to the groceries list. Remember to call Sam about the lease. Put send the invoice on the work list.';

  it('keeps a proposal only for a real note, words really in the memo, and something to add', () => {
    const answer = JSON.stringify([
      { note: 'Groceries', add: 'oat milk', as: 'item', from: 'Add oat milk to the groceries list.' },
      { note: 'Holidays', add: 'passport', from: 'Remember to call Sam about the lease.' },
      { note: 'Work', add: 'send the invoice', from: 'words that were never said' },
      { note: 'Work', add: '', from: 'Put send the invoice on the work list.' },
    ]);
    const placed = readPlacements(`Here you go:\n${answer}`, memo, notes);
    expect(placed.map((p) => [p.noteTitle, p.text, p.how])).toEqual([['Groceries', 'oat milk', 'item']]);
  });

  it('files the commands the rules understand when there is no model', () => {
    const placed = rulePlacements(memo, notes);
    expect(placed.map((p) => [p.noteTitle, p.text])).toEqual([
      ['Groceries', 'oat milk'],
      ['Work', 'send the invoice'],
    ]);
  });

  it('leaves what was not placed for the new note, tidied', () => {
    const placed = rulePlacements(memo, notes);
    expect(leftover(memo, placed)).toBe('Remember to call Sam about the lease.');
    expect(leftover('# Memo\n\n- Add eggs to groceries\n- call the bank', rulePlacements('# Memo\n\n- Add eggs to groceries\n- call the bank', notes))).toBe('# Memo\n\n- call the bank');
    expect(leftover(memo, [])).toBe(memo);
  });
});

describe('a memo with nowhere to go', () => {
  const clip = '![voice 0:12](tape:12000-24000@k3f9x2)';

  it('is only voice memos when nothing but clips is left', () => {
    expect(onlyMemos(`- ${clip}\n\n- ${clip}\n`)).toBe(true);
    expect(onlyMemos(`${clip}`)).toBe(true);
    expect(onlyMemos(`- [ ] ${clip}`)).toBe(true);
    expect(onlyMemos(`- ${clip} ring the roofer back`)).toBe(false);
    expect(onlyMemos('- ring the roofer back')).toBe(false);
    expect(onlyMemos('')).toBe(false);
    expect(onlyMemos('   \n\n')).toBe(false);
  });

  it('becomes the Unsorted memos note, keeping a heading it already has', () => {
    expect(memosNote(`- ${clip}`)).toBe(`# ${UNSORTED_MEMOS}\n\n- ${clip}`);
    expect(memosNote(`# Roof\n\n- ${clip}`)).toBe(`# Roof\n\n- ${clip}`);
  });
});
