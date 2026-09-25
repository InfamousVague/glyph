import type { WheelEvent } from 'react';
import { describe, expect, it } from 'vitest';
import { scrollSideways } from './scrollSideways.ts';

/*
 * A mouse wheel over a row that only scrolls sideways (scrollSideways.ts): the tabs and the workspace pills. jsdom
 * lays nothing out, so each row's widths are set by hand.
 */

/** A row `scrollWidth` wide in `clientWidth` of room, and the wheel turned over it. */
function wheel(scrollWidth: number, clientWidth: number, deltaY: number, deltaX = 0): HTMLElement {
  const row = document.createElement('div');
  Object.defineProperties(row, { scrollWidth: { value: scrollWidth }, clientWidth: { value: clientWidth } });
  scrollSideways({ currentTarget: row, deltaX, deltaY } as unknown as WheelEvent<HTMLElement>);
  return row;
}

describe('a mouse wheel over a sideways row', () => {
  it('scrolls it sideways by the wheel’s turn', () => {
    expect(wheel(800, 300, 120).scrollLeft).toBe(120);
  });

  it('follows a trackpad’s own sideways swipe when that is the larger', () => {
    expect(wheel(800, 300, 10, 80).scrollLeft).toBe(80);
  });

  it('leaves the wheel to the page under a row that fits', () => {
    expect(wheel(300, 300, 120).scrollLeft).toBe(0);
  });
});
