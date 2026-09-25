import { useRef, type ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { show, unmount } from '../../test/render.tsx';
import { installBack, onBack } from './back.ts';
import { useSwipeNav } from './swipe.ts';

/*
 * A swipe across Settings or the guide (swipe.ts): right for back, left for forward, and only a quick, mostly
 * sideways drag that did not start on something that moves sideways itself. And the one swipe that is also Android's
 * back gesture steps back once, not twice (core/back.ts). The clock is the test's.
 */

let now = 0;
const went: string[] = [];

function Surface({ active = true, children }: { active?: boolean; children?: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useSwipeNav(ref, { onBack: () => went.push('back'), onForward: () => went.push('forward') }, active);
  return <div ref={ref}>{children}</div>;
}

beforeEach(() => {
  now = 0;
  went.length = 0;
  vi.spyOn(performance, 'now').mockImplementation(() => now);
});

afterEach(() => {
  unmount();
  vi.restoreAllMocks();
});

/** A pointer event on `on`, bubbling to the surface. */
function pointer(type: string, on: Element, x: number, y = 0, { id = 1, primary = true, button = 0 } = {}): void {
  const event = new Event(type, { bubbles: true });
  Object.defineProperties(event, {
    clientX: { value: x },
    clientY: { value: y },
    pointerId: { value: id },
    isPrimary: { value: primary },
    button: { value: button },
  });
  on.dispatchEvent(event);
}

/** A drag from 0,0 on `on` to `dx`,`dy`, taking `ms`. */
function drag(on: Element, dx: number, dy = 0, ms = 200, options = {}): void {
  pointer('pointerdown', on, 0, 0, options);
  now += ms;
  pointer('pointerup', on, dx, dy, options);
}

describe('a swipe across the page', () => {
  it('goes back to the right and forward to the left', () => {
    const surface = show(<Surface />).firstElementChild!;
    drag(surface, 80);
    drag(surface, -80);
    expect(went).toEqual(['back', 'forward']);
  });

  it('is only a quick drag, far enough, and mostly sideways', () => {
    const surface = show(<Surface />).firstElementChild!;
    drag(surface, 63);
    drag(surface, 80, 41);
    drag(surface, 80, 0, 1_501);
    expect(went).toEqual([]);
    drag(surface, 64, 31, 1_500);
    expect(went).toEqual(['back']);
  });

  it('leaves alone a drag that began on a field, a slider, a segmented control or anything marked data-noswipe', () => {
    const surface = show(
      <Surface>
        <input />
        <div role="slider" />
        <div role="radiogroup">
          <input type="radio" />
        </div>
        <div data-noswipe="" />
        <div role="radiogroup" className="choices">
          <button type="button">A choice</button>
        </div>
      </Surface>,
    ).firstElementChild!;
    for (const owner of surface.querySelectorAll('input, [role="slider"], [data-noswipe]')) drag(owner, 80);
    expect(went).toEqual([]);
    // A radiogroup of buttons, the guide's choice rows, does not slide: it swipes like the page.
    drag(surface.querySelector('button')!, 80);
    expect(went).toEqual(['back']);
  });

  it('counts only the primary pointer’s main button, and forgets a cancelled drag', () => {
    const surface = show(<Surface />).firstElementChild!;
    drag(surface, 80, 0, 200, { primary: false });
    drag(surface, 80, 0, 200, { button: 2 });
    pointer('pointerdown', surface, 0);
    pointer('pointercancel', surface, 0);
    pointer('pointerup', surface, 80);
    expect(went).toEqual([]);
  });

  it('does nothing while the surface is not on screen', () => {
    const surface = show(<Surface active={false} />).firstElementChild!;
    drag(surface, 80);
    expect(went).toEqual([]);
  });

  it('is the same gesture as Android’s back a moment later, so the page steps back once', () => {
    const stop = installBack();
    let stepped = 0;
    const off = onBack(() => {
      stepped += 1;
      return true;
    });
    const surface = show(<Surface />).firstElementChild!;
    drag(surface, 80);
    expect(went).toEqual(['back']);
    // Android's own back arrives from the same thumb: answered, and not stepped on again.
    now += 100;
    expect(window.__glyph?.back?.()).toBe(true);
    expect(stepped).toBe(0);
    now += 500;
    window.__glyph?.back?.();
    expect(stepped).toBe(1);
    off();
    stop();
  });
});
