import { describe, expect, it } from 'vitest';
import { knownHeight, origin, spotOnScreen } from './sideKey.ts';

describe('where the side key is', () => {
  it('knows the Fold line from its model code', () => {
    expect(knownHeight('SM-F976U', 'samsung')).toBe(0.47);
    expect(knownHeight('sm-f966b', 'samsung')).toBe(0.47);
    expect(knownHeight(null, 'Google')).toBe(0.3);
    expect(knownHeight(undefined, undefined)).toBe(0.4);
  });

  it('follows the key round the screen as the phone turns', () => {
    expect(spotOnScreen(0.47, 0)).toEqual({ edge: 'right', along: 0.47 });
    expect(spotOnScreen(0.47, 90)).toEqual({ edge: 'top', along: 0.47 });
    expect(spotOnScreen(0.25, 180)).toEqual({ edge: 'left', along: 0.75 });
    expect(spotOnScreen(0.25, 270)).toEqual({ edge: 'bottom', along: 0.75 });
    expect(spotOnScreen(0.25, -90)).toEqual({ edge: 'bottom', along: 0.75 });
  });

  it('puts the rings just outside the edge beside the key', () => {
    expect(origin({ edge: 'right', along: 0.5 }, 400, 800)).toEqual({ x: 412, y: 400 });
    expect(origin({ edge: 'top', along: 0.25 }, 800, 400, 4)).toEqual({ x: 200, y: -4 });
  });
});
