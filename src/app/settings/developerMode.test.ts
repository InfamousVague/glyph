import { describe, expect, it } from 'vitest';
import { countKnock, KNOCKS_WANTED } from './developerMode.ts';

/**
 * The seven presses on About's version: a run counts down and completes at the seventh, a pause starts it again, and
 * a completed run starts from nothing. The clock is passed in, so none of this waits.
 */

/** Presses `n` times from `start`, `gap` ms apart, and answers what the last press said and when it was. */
function knocks(n: number, start: number, gap = 150): { left: number; at: number } {
  let left = -1;
  let at = start;
  for (let i = 0; i < n; i += 1) {
    at = start + i * gap;
    left = countKnock(at);
  }
  return { left, at };
}

describe('countKnock', () => {
  it('answers how many presses are left, and 0 on the seventh', () => {
    // Far from any other test's presses, so the run starts at one.
    const start = 1_000_000;
    expect(countKnock(start)).toBe(KNOCKS_WANTED - 1);
    expect(countKnock(start + 100)).toBe(KNOCKS_WANTED - 2);
    expect(knocks(KNOCKS_WANTED - 2, start + 200).left).toBe(0);
  });

  it('starts again after a pause longer than the gap between presses', () => {
    const { at } = knocks(5, 2_000_000);
    expect(countKnock(at + 800)).toBe(1);
    // Past the gap: the run begins again at this press.
    expect(countKnock(at + 800 + 901)).toBe(KNOCKS_WANTED - 1);
  });

  it('starts from nothing after a completed run, however quickly the next press comes', () => {
    const { left, at } = knocks(KNOCKS_WANTED, 3_000_000);
    expect(left).toBe(0);
    expect(countKnock(at + 50)).toBe(KNOCKS_WANTED - 1);
  });
});
