import { afterEach, describe, expect, it } from 'vitest';
import { defaultHeight, knownHeight, origin, savedHeight, saveHeight, spotOnScreen } from './sideKey.ts';

describe('the Developer setting', () => {
  afterEach(() => localStorage.clear());

  it('keeps a height moved in Settings, held to the edge, until it is reset', () => {
    expect(savedHeight()).toBeNull();
    saveHeight(0.62);
    expect(savedHeight()).toBe(0.62);
    saveHeight(1.4);
    expect(savedHeight()).toBe(1);
    saveHeight(-0.2);
    expect(savedHeight()).toBe(0);
    saveHeight(null);
    expect(savedHeight()).toBeNull();
  });

  it('reads anything but a number as no setting', () => {
    localStorage.setItem('glyph-side-key', 'halfway');
    expect(savedHeight()).toBeNull();
  });

  it('is not what Reset goes back to: that is the table’s height for this phone', async () => {
    saveHeight(0.9);
    // jsdom is no phone: no model code, no maker, so the table's guess.
    await expect(defaultHeight()).resolves.toBe(0.4);
  });
});

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
