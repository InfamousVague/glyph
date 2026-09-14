import { describe, expect, it } from 'vitest';
import { armedAt, followFinger, startsInGestureEdge, type SwipeAction } from './swipe.ts';

const left: SwipeAction[] = [
  { id: 'archive', label: 'Archive', icon: 'archive', tone: 'neutral', detent: 0.22, removes: true },
  { id: 'delete', label: 'Delete', icon: 'delete', tone: 'danger', detent: 0.55, removes: true },
];

describe('swipe detents', () => {
  it('arms nothing short of the first detent, then the furthest one passed', () => {
    expect(armedAt(left, 0.1)).toBeNull();
    expect(armedAt(left, 0.22)?.id).toBe('archive');
    expect(armedAt(left, 0.5)?.id).toBe('archive');
    expect(armedAt(left, 0.7)?.id).toBe('delete');
  });

  it('leaves the screen edges to the back gesture', () => {
    expect(startsInGestureEdge(10, 400)).toBe(true);
    expect(startsInGestureEdge(395, 400)).toBe(true);
    expect(startsInGestureEdge(200, 400)).toBe(false);
  });

  it('follows the finger, then resists past the last detent', () => {
    expect(followFinger(-100, 0.55, 400)).toBe(-100);
    const far = followFinger(-400, 0.55, 400);
    expect(far).toBeLessThan(0);
    expect(Math.abs(far)).toBeLessThan(400);
    expect(Math.abs(far)).toBeGreaterThan((0.55 + 0.18) * 400);
  });
});
