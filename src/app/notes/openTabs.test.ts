import { describe, expect, it } from 'vitest';
import { addOpen, afterClose, closeOpen, moveOpen, openOnly } from './openTabs.ts';

describe('the open notes', () => {
  it('adds a note once, at the end, and drops the oldest past the limit', () => {
    expect(addOpen([], 'a')).toEqual(['a']);
    expect(addOpen(['a', 'b'], 'c')).toEqual(['a', 'b', 'c']);
    expect(addOpen(['a', 'b'], 'a')).toEqual(['a', 'b']);
    expect(addOpen(['a', 'b', 'c'], 'd', 3)).toEqual(['b', 'c', 'd']);
  });

  it('closes one, and lands on the next, then the one before, then nowhere', () => {
    expect(closeOpen(['a', 'b', 'c'], 'b')).toEqual(['a', 'c']);
    expect(afterClose(['a', 'b', 'c'], 'b')).toBe('c');
    expect(afterClose(['a', 'b'], 'b')).toBe('a');
    expect(afterClose(['a'], 'a')).toBeNull();
    // A note already gone: the last one open, or nowhere.
    expect(afterClose(['a', 'b'], 'gone')).toBe('b');
    expect(afterClose([], 'gone')).toBeNull();
  });

  it('keeps only the ids that are still notes, in order', () => {
    expect(openOnly(['a', 'b', 'c'], new Set(['c', 'a']))).toEqual(['a', 'c']);
    expect(openOnly(['a'], new Set())).toEqual([]);
  });
});

describe('dragging a tab', () => {
  const shown = ['a', 'b', 'c', 'd'];

  it('moves one along the row', () => {
    expect(moveOpen(shown, shown, 'a', 2)).toEqual(['b', 'c', 'a', 'd']);
  });

  it('moves one back down the row', () => {
    expect(moveOpen(shown, shown, 'd', 0)).toEqual(['d', 'a', 'b', 'c']);
  });

  it('changes nothing when it lands where it started', () => {
    expect(moveOpen(shown, shown, 'b', 1)).toEqual(shown);
  });

  it('holds a drop past either end at the end', () => {
    expect(moveOpen(shown, shown, 'b', 99)).toEqual(['a', 'c', 'd', 'b']);
    expect(moveOpen(shown, shown, 'c', -4)).toEqual(['c', 'a', 'b', 'd']);
  });

  it('keeps ids that are no longer notes, after the row', () => {
    const open = ['a', 'ghost', 'b', 'c'];
    expect(moveOpen(open, ['a', 'b', 'c'], 'c', 0)).toEqual(['c', 'a', 'b', 'ghost']);
  });

  it('ignores a tab that is not in the row', () => {
    expect(moveOpen(shown, shown, 'nope', 0)).toEqual(shown);
  });
});
