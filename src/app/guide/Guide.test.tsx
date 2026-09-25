import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';

await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

import { button, press, rerender, show } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';
import { goBack } from '../core/back.ts';
import { Guide } from './Guide.tsx';
import { GUIDE_PAGES } from './pages.ts';
import { NUDGE_AFTER_MS, NUDGES } from './useBottomNudge.ts';

/**
 * jsdom lays nothing out, so every scroller is as tall as its window here unless a test says the page is long: then
 * it is 2000 pixels of words in a 400-pixel window, and scrolled wherever the test puts it.
 */
let long = false;
const layout = {
  scrollHeight: Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'scrollHeight'),
  clientHeight: Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'clientHeight'),
};
const watcher = globalThis.IntersectionObserver;
beforeAll(() => {
  stubResizeObserver();
  // A screen watcher that never reports, so the marks page's examples keep their placeholder words
  // (guide/MarkExample.tsx): without one, every row builds its editor at once, fifty of them.
  globalThis.IntersectionObserver = class StillWatcher {
    observe(): void {}
    unobserve(): void {}
    disconnect(): void {}
    takeRecords(): IntersectionObserverEntry[] {
      return [];
    }
  } as unknown as typeof IntersectionObserver;
  Object.defineProperty(HTMLElement.prototype, 'scrollHeight', { configurable: true, get: () => (long ? 2000 : 400) });
  Object.defineProperty(HTMLElement.prototype, 'clientHeight', { configurable: true, get: () => 400 });
  // The side-key page's rings: no canvas in this document, and the layer mounts empty.
  HTMLCanvasElement.prototype.getContext = (() => null) as unknown as HTMLCanvasElement['getContext'];
});
afterAll(() => {
  for (const [name, was] of Object.entries(layout)) if (was) Object.defineProperty(HTMLElement.prototype, name, was);
  globalThis.IntersectionObserver = watcher;
});
beforeEach(() => {
  long = false;
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});
afterEach(() => {
  vi.useRealTimers();
});

const at = (page: (typeof GUIDE_PAGES)[number]) => GUIDE_PAGES.indexOf(page);

function guide(index: number, extra: { tooSoon?: boolean } = {}) {
  const calls = { onIndex: vi.fn(), onClose: vi.fn(), onTry: vi.fn() };
  const el = show(<Guide index={index} {...calls} {...extra} />);
  return { el, ...calls, again: (next: number) => rerender(<Guide index={next} {...calls} {...extra} />) };
}

/** The scrolling page: the one div among the dialog's own children. */
const pageOf = (el: HTMLElement) => el.querySelector<HTMLElement>('[role="dialog"] > div')!;
const next = (el: HTMLElement) => button('Next', el);
const nudge = (el: HTMLElement) => [...el.querySelectorAll('button')].find((b) => NUDGES.some((words) => b.textContent?.includes(words)))!;
const shown = (b: HTMLElement) => b.dataset.shown !== undefined;

describe('the walkthrough', () => {
  it('keeps Next at the bottom of a long page, and after a moment nudges the reader down to it', () => {
    long = true;
    const { el } = guide(at('welcome'));
    expect(shown(next(el))).toBe(false);
    expect(next(el).getAttribute('aria-hidden')).toBe('true');
    expect(shown(nudge(el))).toBe(false);
    act(() => vi.advanceTimersByTime(NUDGE_AFTER_MS - 1));
    expect(shown(nudge(el))).toBe(false);
    act(() => vi.advanceTimersByTime(1));
    expect(shown(nudge(el))).toBe(true);
    // Read to the end: Next is there, and the nudge has done its job.
    const page = pageOf(el);
    Object.defineProperty(page, 'scrollTop', { configurable: true, value: 1590 });
    act(() => page.dispatchEvent(new Event('scroll')));
    expect(shown(next(el))).toBe(true);
    expect(next(el).tabIndex).toBe(0);
    expect(shown(nudge(el))).toBe(false);
  });

  it('shows Next at once on a page that fits the screen', () => {
    const { el } = guide(at('theme'));
    expect(shown(next(el))).toBe(true);
    act(() => vi.advanceTimersByTime(NUDGE_AFTER_MS));
    expect(shown(nudge(el))).toBe(false);
  });

  it('steps with Next and Back, and the back gesture steps back until the first page, where it closes the guide', () => {
    const { el, onIndex, onClose, again } = guide(at('model'));
    press(next(el));
    expect(onIndex).toHaveBeenLastCalledWith(at('model') + 1);
    press(button('Back', el));
    expect(onIndex).toHaveBeenLastCalledWith(at('model') - 1);
    act(() => void goBack());
    expect(onIndex).toHaveBeenLastCalledWith(at('model') - 1);
    expect(onClose).not.toHaveBeenCalled();
    again(0);
    expect(button('Back', el).disabled).toBe(true);
    act(() => void goBack());
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('says where the reader is, and offers Skip until the last page, which offers Close and Try it', () => {
    const { el, onClose, onTry, again } = guide(at('theme'));
    expect(el.querySelector('[role="img"]')?.getAttribute('aria-label')).toBe(`Page ${at('theme') + 1} of ${GUIDE_PAGES.length}`);
    press(button('Skip', el));
    expect(onClose).toHaveBeenCalledTimes(1);
    again(GUIDE_PAGES.length - 1);
    expect(el.textContent).toContain('A few habits.');
    press(button('Try it', el));
    expect(onClose).toHaveBeenCalledTimes(2);
    expect(onTry).toHaveBeenCalledTimes(1);
    expect(button('Close', el)).toBeTruthy();
  });

  it('opens with one line for a reader who held the side key too soon', () => {
    const { el } = guide(0, { tooSoon: true });
    expect(el.querySelector('[role="status"]')?.textContent).toContain('Not yet, finish reading.');
    const calm = guide(0);
    expect(calm.el.textContent).not.toContain('Not yet, finish reading.');
  });

  it('draws the side key’s rings only on the side-key page, outside the page that scrolls', () => {
    const { el, again } = guide(at('sidekey'));
    const rings = el.querySelector('[data-testid="side-key-waves"]');
    expect(rings).not.toBeNull();
    expect(pageOf(el).contains(rings)).toBe(false);
    // Off Android, the page says how to start a voice note instead of which rows to tap.
    expect(el.textContent).toContain('Start a voice note with Speak.');
    // Not before it (Matt: "remove the animation … until we get to that step"), and not after.
    for (const page of GUIDE_PAGES.filter((name) => name !== 'sidekey')) {
      again(at(page));
      expect(el.querySelector('[data-testid="side-key-waves"]'), page).toBeNull();
    }
  });
});

describe('swiping through the walkthrough', () => {
  /** A quick sideways drag across the guide, `dx` pixels: left is forward, right is back. */
  function swipe(el: HTMLElement, dx: number) {
    const target = pageOf(el);
    const at = (type: string, clientX: number) =>
      Object.assign(new MouseEvent(type, { bubbles: true, clientX, clientY: 300, button: 0 }), { pointerId: 1, isPrimary: true });
    act(() => {
      target.dispatchEvent(at('pointerdown', 200));
      target.dispatchEvent(at('pointerup', 200 + dx));
    });
  }

  it('goes forward on a swipe left only once the page is read to the bottom, as Next does', () => {
    long = true;
    const { el, onIndex } = guide(at('welcome'));
    swipe(el, -120);
    expect(onIndex).not.toHaveBeenCalled();
    const page = pageOf(el);
    Object.defineProperty(page, 'scrollTop', { configurable: true, value: 1590 });
    act(() => page.dispatchEvent(new Event('scroll')));
    swipe(el, -120);
    expect(onIndex).toHaveBeenCalledWith(at('welcome') + 1);
  });

  it('goes back on a swipe right, and never forward from the last page', () => {
    const { el, onIndex, onClose } = guide(GUIDE_PAGES.length - 1);
    swipe(el, -120);
    expect(onIndex).not.toHaveBeenCalled();
    expect(onClose).not.toHaveBeenCalled();
    swipe(el, 120);
    expect(onIndex).toHaveBeenCalledWith(GUIDE_PAGES.length - 2);
  });
});
