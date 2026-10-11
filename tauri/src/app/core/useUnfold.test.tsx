import { act, useRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { show, unmount } from '../../test/render.tsx';
import { stubMatchMedia } from '../../test/stubs.ts';
import { FLAT, LONGEST_MS, SETTLE_MS, useUnfold } from './unfold.ts';

/*
 * The unfold drawn on the note (unfold.ts `useUnfold`): the hinge's readings, arriving through the activity, written
 * straight onto the screen's element, and the note never left creased - not when the page goes dark mid-unfold, not
 * when frames stop coming, not when the screen goes. The machine itself is unfold.test.ts's; here the clock and the
 * animation frames are the test's.
 */

let now = 0;
/** Frames asked for and not yet run. */
let frames: FrameRequestCallback[] = [];

beforeEach(() => {
  now = 0;
  frames = [];
  vi.useFakeTimers();
  vi.spyOn(performance, 'now').mockImplementation(() => now);
  vi.spyOn(window, 'requestAnimationFrame').mockImplementation((run) => frames.push(run));
  vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => undefined);
  delete (window as { matchMedia?: unknown }).matchMedia;
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
  vi.restoreAllMocks();
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
});

function Note() {
  const ref = useRef<HTMLDivElement>(null);
  useUnfold(ref);
  return <div ref={ref} />;
}

/** The note screen's element, as the hook draws on it. */
let screen: HTMLElement | null = null;

/** Puts the note screen up. */
function mount(): void {
  screen = show(<Note />).firstElementChild as HTMLElement;
}

/** The hinge at `angle`, `after` ms from the last reading. */
function hinge(angle: number, after = 16): void {
  now += after;
  act(() => window.__glyph?.hinge?.(angle));
}

/** Runs the frames asked for, `after` ms on. */
function frame(after = 16): void {
  now += after;
  const run = frames;
  frames = [];
  act(() => {
    for (const callback of run) callback(now);
  });
}

const unfold = () => screen?.style.getPropertyValue('--unfold') ?? '';
const unfolding = () => screen?.dataset.unfolding !== undefined;

describe('the note opening with the phone', () => {
  it('follows the hinge from the hand-over to flat, and is plain paper again after', () => {
    mount();
    hinge(10);
    expect(unfolding()).toBe(false);
    hinge(40);
    expect(unfolding()).toBe(true);
    const early = Number(unfold());
    hinge(80);
    expect(Number(unfold())).toBeGreaterThan(early);
    hinge(FLAT + 1);
    expect(unfolding()).toBe(false);
    expect(unfold()).toBe('');
  });

  it('settles flat on its own frames when the hinge stops partway', () => {
    mount();
    hinge(10);
    hinge(60);
    expect(unfolding()).toBe(true);
    for (let i = 0; i < 40 && unfolding(); i += 1) frame(50);
    expect(unfolding()).toBe(false);
  });

  it('is flattened at once when the page goes dark mid-unfold, since a hidden page gets no frames', () => {
    mount();
    hinge(10);
    hinge(60);
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
    act(() => document.dispatchEvent(new Event('visibilitychange')));
    expect(unfolding()).toBe(false);
  });

  it('is flattened by a timer past the longest an unfold runs, whatever happened to the frames', () => {
    mount();
    hinge(10);
    hinge(60);
    act(() => vi.advanceTimersByTime(LONGEST_MS + SETTLE_MS + 99));
    expect(unfolding()).toBe(true);
    act(() => vi.advanceTimersByTime(1));
    expect(unfolding()).toBe(false);
  });

  it('stops listening to the hinge with the screen gone', () => {
    mount();
    expect(window.__glyph?.hinge).toBeTypeOf('function');
    unmount();
    expect(window.__glyph?.hinge).toBeUndefined();
  });

  it('draws nothing where the phone asks for less motion', () => {
    stubMatchMedia(true);
    mount();
    expect(window.__glyph?.hinge).toBeUndefined();
  });
});
