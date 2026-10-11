import { describe, expect, it } from 'vitest';
import { barAt, DASH, easeFor, EYES, LAP_MS, LOOK_X, LOOK_Y, lookAt } from './eyes.ts';

describe('the ghost watching the bar', () => {
  it('turns an eye as far as it goes toward what it looks at, near or far', () => {
    const eye = EYES[0]!;
    expect(lookAt(eye, { x: eye.x + 50, y: eye.y })).toEqual({ x: LOOK_X, y: 0 });
    expect(lookAt(eye, { x: eye.x, y: eye.y - 3 })).toEqual({ x: 0, y: -LOOK_Y });
    const corner = lookAt(eye, { x: eye.x - 10, y: eye.y + 10 });
    expect(corner.x).toBeCloseTo(-LOOK_X / Math.SQRT2);
    expect(corner.y).toBeCloseTo(LOOK_Y / Math.SQRT2);
    // Looking at itself, it looks ahead.
    expect(lookAt(eye, eye)).toEqual({ x: 0, y: 0 });
  });

  it('puts the bar a lap round every lap, and names its middle', () => {
    expect(barAt(0)).toEqual({ middle: DASH / 200, offset: -0 });
    expect(barAt(LAP_MS / 2).offset).toBeCloseTo(-50);
    expect(barAt(LAP_MS / 2).middle).toBeCloseTo(0.5 + DASH / 200);
    expect(barAt(LAP_MS * 3 + 10)).toEqual(barAt(10));
    // Near the end of a lap the middle has come round past the start.
    expect(barAt(LAP_MS * 0.99).middle).toBeCloseTo(0.99 + DASH / 200 - 1);
  });

  it('catches up most of the way in a tenth of a second, and none of it in no time', () => {
    expect(easeFor(0)).toBe(0);
    expect(easeFor(100)).toBeGreaterThan(0.6);
    expect(easeFor(1000)).toBeGreaterThan(0.99);
  });
});
