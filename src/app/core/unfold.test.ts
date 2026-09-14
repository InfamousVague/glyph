import { describe, expect, it } from 'vitest';
import { FLAT, HANDOVER, LONGEST_MS, SETTLE_MS, STALL_MS, Unfold, progressAt } from './unfold.ts';

describe('the unfold', () => {
  it('starts as the hinge opens through the hand-over and follows it to flat', () => {
    const unfold = new Unfold();
    expect(unfold.reading(0, 0)).toBe(1);
    expect(unfold.reading(20, 10)).toBe(1);
    expect(unfold.active).toBe(false);
    const first = unfold.reading(40, 20);
    expect(unfold.active).toBe(true);
    expect(first).toBeGreaterThan(0);
    expect(first).toBeLessThan(0.2);
    const mid = unfold.reading(75, 30);
    expect(mid).toBeGreaterThan(first);
    expect(mid).toBeLessThan(1);
    expect(unfold.reading(FLAT + 5, 40)).toBe(1);
    expect(unfold.active).toBe(false);
  });

  it('never folds back up on a wobble, and closing ends it flat', () => {
    const unfold = new Unfold();
    unfold.reading(10, 0);
    unfold.reading(70, 10);
    const at70 = unfold.reading(70, 20);
    expect(unfold.reading(62, 30)).toBe(at70);
    expect(unfold.reading(HANDOVER - 1, 40)).toBe(1);
    expect(unfold.active).toBe(false);
  });

  it('settles flat on its own when the hinge stops partway', () => {
    const unfold = new Unfold();
    unfold.reading(0, 0);
    const held = unfold.reading(80, 10);
    expect(unfold.tick(10 + STALL_MS - 1)).toBe(held);
    expect(unfold.tick(10 + STALL_MS)).toBe(held);
    const later = unfold.tick(10 + STALL_MS + SETTLE_MS / 2);
    expect(later).toBeGreaterThan(held);
    expect(later).toBeLessThan(1);
    expect(unfold.tick(10 + STALL_MS + SETTLE_MS)).toBe(1);
    expect(unfold.active).toBe(false);
  });

  it('ignores the hinge once it has begun to settle', () => {
    const unfold = new Unfold();
    unfold.reading(0, 0);
    unfold.reading(60, 10);
    const settling = unfold.tick(10 + STALL_MS + 40);
    const next = unfold.reading(100, 10 + STALL_MS + 41);
    expect(next).toBeGreaterThanOrEqual(settling);
    expect(next).toBeLessThan(progressAt(100));
  });

  it('gives up on an unfold that drags on', () => {
    const unfold = new Unfold();
    unfold.reading(0, 0);
    let now = 0;
    for (let angle = 35; angle < 60; angle += 1) {
      now += 100;
      unfold.reading(angle, now);
    }
    expect(now).toBeGreaterThan(LONGEST_MS);
    expect(unfold.tick(now + SETTLE_MS)).toBe(1);
    expect(unfold.active).toBe(false);
  });

  it('joins an unfold already under way when the page wakes mid-hinge, and nothing else', () => {
    const woke = new Unfold();
    expect(woke.reading(70, 0)).toBeLessThan(1);
    expect(woke.active).toBe(true);
    const closed = new Unfold();
    expect(closed.reading(0, 0)).toBe(1);
    expect(closed.active).toBe(false);
    const flat = new Unfold();
    expect(flat.reading(180, 0)).toBe(1);
    expect(flat.active).toBe(false);
  });

  it('eases from hand-over to flat', () => {
    expect(progressAt(HANDOVER)).toBe(0);
    expect(progressAt(FLAT)).toBe(1);
    expect(progressAt((HANDOVER + FLAT) / 2)).toBeCloseTo(0.5, 5);
    expect(progressAt(-10)).toBe(0);
    expect(progressAt(180)).toBe(1);
  });
});
