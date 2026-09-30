import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, useRef } from 'react';
import { show, unmount } from '../../test/render.tsx';
import { PULL_DETENT_PX, PULL_REST_PX } from '../core/pull.ts';

/**
 * Pulling a page down to refresh it (notes/PullToRefresh.tsx; docs/DESIGN.md §152): a pull past the detent refreshes,
 * with the motor's click there and a tap when it is done; short of it, or from a page scrolled down, or a finger that
 * rested first, nothing happens.
 */

const felt = vi.hoisted(() => ({ kinds: [] as string[], ticks: 0 }));
vi.mock('../core/haptics.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/haptics.ts')>()),
  fireNativeHaptic: (kind = 'light') => void felt.kinds.push(kind),
  fireMicroTick: () => void (felt.ticks += 1),
}));

const { PullToRefresh } = await import('./PullToRefresh.tsx');

afterEach(() => {
  unmount();
  felt.kinds = [];
  felt.ticks = 0;
});

function Page({ onRefresh, enabled = true }: { onRefresh: () => Promise<unknown>; enabled?: boolean }) {
  const scroller = useRef<HTMLDivElement>(null);
  return (
    <>
      <div ref={scroller} data-testid="page">
        <p>The page</p>
      </div>
      <PullToRefresh scroller={scroller} onRefresh={onRefresh} enabled={enabled} />
    </>
  );
}

const page = () => document.querySelector<HTMLElement>('[data-testid="page"]')!;
/** A touch event on the page, where the finger is at `y`, `at` ms into the touch. */
const touch = (type: string, y: number, at: number) => {
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.defineProperty(event, 'touches', { value: type === 'touchend' ? [] : [{ clientX: 100, clientY: y }] });
  Object.defineProperty(event, 'timeStamp', { value: at });
  act(() => page().dispatchEvent(event));
  return event;
};
/** A finger down at the top, drawn down `by` px in ten steps over `ms`, starting to move after `rest` ms, and let go. */
const pull = (by: number, { ms = 160, rest = 0 } = {}) => {
  touch('touchstart', 100, 0);
  let last: Event | null = null;
  for (let step = 1; step <= 10; step += 1) last = touch('touchmove', 100 + (by * step) / 10, rest + (ms * step) / 10);
  touch('touchend', 100 + by, rest + ms + 10);
  return last!;
};
const wait = (ms: number) => act(async () => await new Promise((done) => setTimeout(done, ms)));
const status = () => document.querySelector<HTMLElement>('[role="status"]')!;

describe('pulling a page down to refresh it', () => {
  it('refreshes past the detent: the page comes down, the motor clicks there, the ring spins, and a tap says it is done', async () => {
    let finish = () => undefined as void;
    const onRefresh = vi.fn(() => new Promise<void>((done) => (finish = done)));
    show(<Page onRefresh={onRefresh} />);
    const moved = pull(PULL_DETENT_PX * 2 + 40);
    // The browser's own overscroll was stopped, and the page followed the finger.
    expect(moved.defaultPrevented).toBe(true);
    expect(felt.kinds).toEqual(['medium']);
    expect(felt.ticks).toBeGreaterThan(0);
    await wait(0);
    expect(onRefresh).toHaveBeenCalledTimes(1);
    expect(status().dataset.phase).toBe('refreshing');
    expect(status().textContent).toBe('Refreshing');
    expect(page().querySelector('p')!.style.translate).toBe(`0 ${PULL_REST_PX}px`);
    finish();
    await wait(560);
    expect(felt.kinds).toEqual(['medium', 'light']);
    expect(status().textContent).toBe('Up to date');
    await wait(400);
    expect(status().hidden).toBe(true);
    expect(page().querySelector('p')!.style.translate).toBe('');
  });

  it('goes back up short of the detent, and a pull that backs out of it says so, both without refreshing', async () => {
    const onRefresh = vi.fn(async () => undefined);
    show(<Page onRefresh={onRefresh} />);
    pull(PULL_DETENT_PX);
    await wait(20);
    expect(onRefresh).not.toHaveBeenCalled();
    expect(felt.kinds).toEqual([]);
    expect(page().querySelector('p')!.style.translate).toBe('');
    // Out through the detent and back: a click, then the lightest tick.
    touch('touchstart', 100, 0);
    touch('touchmove', 115, 20);
    touch('touchmove', 100 + PULL_DETENT_PX * 2 + 20, 60);
    touch('touchmove', 140, 100);
    touch('touchend', 140, 120);
    await wait(20);
    expect(felt.kinds).toEqual(['medium', 'selection']);
    expect(onRefresh).not.toHaveBeenCalled();
  });

  it('leaves the page alone when it is scrolled down, when the finger rested first, or where it is off', async () => {
    const onRefresh = vi.fn(async () => undefined);
    show(<Page onRefresh={onRefresh} />);
    page().scrollTop = 40;
    Object.defineProperty(page(), 'scrollTop', { configurable: true, value: 40 });
    expect(pull(PULL_DETENT_PX * 3).defaultPrevented).toBe(false);
    Reflect.deleteProperty(page(), 'scrollTop');
    // A long press, then a drag: choosing words, not a pull.
    expect(pull(PULL_DETENT_PX * 3, { rest: 600 }).defaultPrevented).toBe(false);
    unmount();
    show(<Page onRefresh={onRefresh} enabled={false} />);
    expect(pull(PULL_DETENT_PX * 3).defaultPrevented).toBe(false);
    await wait(20);
    expect(onRefresh).not.toHaveBeenCalled();
    expect(felt.kinds).toEqual([]);
  });
});
