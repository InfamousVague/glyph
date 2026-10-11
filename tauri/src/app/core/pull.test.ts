import { describe, expect, it } from 'vitest';
import { armed, INTENT_MS, PULL_DETENT_PX, PULL_MOST_PX, pullIntent, pullOffset } from './pull.ts';

/** Pulling a page down to refresh it (core/pull.ts; docs/DESIGN.md §152). */

describe('how far the page follows the finger', () => {
  it('follows at half the travel to the detent, then as a rubber band, and never past the most', () => {
    expect(pullOffset(-20)).toBe(0);
    expect(pullOffset(40)).toBe(20);
    expect(pullOffset(PULL_DETENT_PX * 2)).toBe(PULL_DETENT_PX);
    const past = pullOffset(PULL_DETENT_PX * 2 + 60);
    expect(past).toBeGreaterThan(PULL_DETENT_PX);
    expect(past).toBeLessThan(PULL_DETENT_PX + 30);
    expect(pullOffset(5000)).toBe(PULL_MOST_PX);
  });

  it('refreshes on a let-go at the detent or past it', () => {
    expect(armed(PULL_DETENT_PX - 1)).toBe(false);
    expect(armed(PULL_DETENT_PX)).toBe(true);
  });
});

describe('which touches are a pull', () => {
  it('is a quick drag down, more than across, from a page at its top', () => {
    expect(pullIntent(0, 4, true, 20)).toBe('undecided');
    expect(pullIntent(2, 14, true, 60)).toBe('pull');
  });

  it('leaves the page anything else: scrolled down, going up, going across, or a finger that rested first', () => {
    expect(pullIntent(2, 14, false, 60)).toBe('other');
    expect(pullIntent(2, -14, true, 60)).toBe('other');
    expect(pullIntent(14, 12, true, 60)).toBe('other');
    expect(pullIntent(2, 14, true, INTENT_MS + 50)).toBe('other');
    expect(pullIntent(0, 3, true, INTENT_MS + 50)).toBe('other');
  });
});
