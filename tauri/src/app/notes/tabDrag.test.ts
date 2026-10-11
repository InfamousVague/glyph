import { describe, expect, it } from 'vitest';
import { coasted, groupAt, placeAt } from './tabDrag.ts';

/** Three tabs a hundred pixels wide from the left edge; the dragged one is never among them. */
const three = [
  { left: 0, width: 100, tabs: 1 },
  { left: 100, width: 100, tabs: 1 },
  { left: 200, width: 100, tabs: 1 },
];

describe('where a dragged tab has reached', () => {
  it('is how many middles it has passed', () => {
    expect(placeAt(three, 10)).toBe(0);
    expect(placeAt(three, 50)).toBe(0);
    expect(placeAt(three, 51)).toBe(1);
    expect(placeAt(three, 260)).toBe(3);
  });

  it('passes every tab of a folded group at once, and none of a chip that is not counting any', () => {
    const folded = [three[0]!, { left: 100, width: 40, tabs: 3 }, { left: 140, width: 100, tabs: 1 }];
    expect(placeAt(folded, 125)).toBe(4);
    expect(placeAt([{ left: 0, width: 40, tabs: 0 }], 30)).toBe(0);
  });
});

describe('the group a dragged tab is over', () => {
  const row = [
    { left: 0, right: 100, group: null },
    { left: 110, right: 150, group: 'g' },
    { left: 150, right: 250, group: 'g' },
    { left: 260, right: 290, group: null },
  ];

  it('is the group of the tab or chip under it, and none over a loose tab or the +', () => {
    expect(groupAt(row, 50)).toBeNull();
    expect(groupAt(row, 120)).toBe('g');
    expect(groupAt(row, 200)).toBe('g');
    expect(groupAt(row, 270)).toBeNull();
  });

  it('is none past either end of the row', () => {
    expect(groupAt(row, -5)).toBeNull();
    expect(groupAt(row, 300)).toBeNull();
  });

  it('is as it was in the gap between two things, and in a row with nothing else in it', () => {
    expect(groupAt(row, 105)).toBeUndefined();
    expect(groupAt([], 10)).toBeUndefined();
  });
});

describe('a flick carrying on', () => {
  it('goes on at the speed it left at, a fifteenth slower each frame', () => {
    const one = coasted(100, 1, 16.67, 1000);
    expect(one.left).toBeCloseTo(116.67);
    expect(one.pace).toBeCloseTo(14 / 15);
    expect(one.done).toBe(false);
  });

  it('counts a stalled frame as four at most', () => {
    expect(coasted(100, 1, 1000, 10_000).left).toBeCloseTo(100 + 16.67 * 4);
  });

  it('stops when it is too slow to see, and at either end of the row', () => {
    expect(coasted(100, 0.02, 16.67, 1000).done).toBe(true);
    expect(coasted(990, 1, 16.67, 1000).done).toBe(true);
    expect(coasted(10, -1, 16.67, 1000).done).toBe(true);
  });
});
