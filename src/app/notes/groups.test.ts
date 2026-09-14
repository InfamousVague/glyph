import { describe, expect, it } from 'vitest';
import type { Note } from '../core/store.ts';
import { groupsOf } from './groups.ts';

const note = (id: string, starred = false) => ({ id, body: id, updatedAt: 0, starred }) as unknown as Note;

describe('grouping the notes list', () => {
  it('puts pinned notes in their own category above the others', () => {
    const groups = groupsOf([note('a', true), note('b'), note('c', true), note('d')], 'notes');
    expect(groups.map((g) => [g.label, g.notes.map((n) => n.id)])).toEqual([
      ['Pinned', ['a', 'c']],
      ['Others', ['b', 'd']],
    ]);
  });

  it('shows no labels when nothing is pinned, and no empty Others', () => {
    expect(groupsOf([note('a'), note('b')], 'notes')).toEqual([{ key: 'all', label: null, notes: [note('a'), note('b')] }]);
    expect(groupsOf([note('a', true)], 'notes').map((g) => g.label)).toEqual(['Pinned']);
    expect(groupsOf([], 'notes')).toEqual([]);
  });

  it('never splits the archive', () => {
    expect(groupsOf([note('a', true), note('b')], 'archive').map((g) => g.label)).toEqual([null]);
  });
});
