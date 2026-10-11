import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { rerender, show, unmount } from '../../test/render.tsx';
import { stubMatchMedia } from '../../test/stubs.ts';
import { WispText } from './WispText.tsx';

/**
 * Words from smoke, as the page sees them: the letters the engine draws for itself, which of them are waiting,
 * arriving through a filter of their own, leaving, or set, and when it says the text has settled. What the plan is -
 * which words stay, move or go, and when each letter is due - is art/wisp.test.ts; this is the DOM and the clock
 * that carry it out.
 *
 * The clock is Vitest's: animation frames, `performance.now` and the timers all fake, so a frame is sixteen
 * milliseconds of nobody's time and a run of seconds takes none. The drawn letters' classes come from the CSS module,
 * which a test does not compile, so each is found by the name the module gives it or, failing that, its own name.
 */

const LETTER = '[class*="ch"]';

/** The letters as drawn, and what each is doing. */
function letters(host: HTMLElement) {
  return [...host.querySelectorAll<HTMLElement>(`${LETTER}`)].filter((el) => el.textContent?.length === 1);
}
const hidden = (el: HTMLElement) => /(^|\s)\S*hidden\S*/.test(el.className);
// jsdom gives the address back quoted, as a browser does: url("#wisp-…").
const bending = (el: HTMLElement) => /url\("?#wisp-/.test(el.style.filter);
const drawn = (host: HTMLElement) =>
  letters(host)
    .filter((el) => !hidden(el))
    .map((el) => el.textContent)
    .join('');

/** Runs the animation clock on by `ms`, a frame at a time. */
const run = (ms: number) => act(() => vi.advanceTimersByTime(ms));

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['requestAnimationFrame', 'cancelAnimationFrame', 'performance', 'setTimeout', 'clearTimeout'] });
  stubMatchMedia(false);
});

afterEach(() => {
  // Taken down before the real clock is back, so the engine's cleanup cancels its frame on the clock that asked for it.
  unmount();
  vi.useRealTimers();
});

describe('WispText', () => {
  it('types its first text in a letter at a time, each bent by a filter of its own until it sets', () => {
    const onSettled = vi.fn();
    const host = show(<WispText text="Hello there" pace={14} onSettled={onSettled} />);
    const text = host.firstElementChild as HTMLElement;
    // The whole text is there for a screen reader from the start; the drawn letters are hidden from it.
    expect(text.textContent).toContain('Hello there');
    expect(text.hasAttribute('data-wisp-typing')).toBe(true);
    expect(letters(host)).toHaveLength(10);
    expect(drawn(host).length).toBeLessThan(3);

    run(300);
    const partway = drawn(host);
    expect(partway.length).toBeGreaterThan(1);
    expect(partway.length).toBeLessThan(10);
    expect(letters(host).some(bending)).toBe(true);
    // Two letters bending at once never share a filter: sharing one made both flicker.
    const filters = letters(host)
      .filter(bending)
      .map((el) => el.style.filter);
    expect(new Set(filters).size).toBe(filters.length);
    expect(onSettled).not.toHaveBeenCalled();

    run(5000);
    expect(drawn(host)).toBe('Hellothere');
    expect(letters(host).some(bending)).toBe(false);
    expect(onSettled).toHaveBeenCalledExactlyOnceWith('Hello there');
    expect(text.hasAttribute('data-wisp-typing')).toBe(false);
  });

  it('swaps only the words that changed', () => {
    const onSettled = vi.fn();
    const host = show(<WispText text="Hold. Talk. Done." onSettled={onSettled} />);
    run(5000);
    rerender(<WispText text="Hold. Talk. Write." onSettled={onSettled} />);
    // The word going is untyped first, while the two that stay never move.
    run(40);
    expect(letters(host).slice(0, 9).some(bending)).toBe(false);
    expect(letters(host).slice(9).some(bending)).toBe(true);
    for (let t = 0; t < 3000; t += 50) {
      run(50);
      expect(letters(host).slice(0, 9).every((el) => !hidden(el) && !bending(el))).toBe(true);
    }
    expect(drawn(host)).toBe('Hold.Talk.Write.');
    expect(onSettled).toHaveBeenLastCalledWith('Hold. Talk. Write.');
  });

  it('shows a text at rest when asked to be still, and still types the next one', () => {
    const onSettled = vi.fn();
    const host = show(<WispText text="Welcome" still onSettled={onSettled} />);
    expect(drawn(host)).toBe('Welcome');
    expect(onSettled).toHaveBeenCalledExactlyOnceWith('Welcome');
    rerender(<WispText text="Welcome back" still onSettled={onSettled} />);
    let bent = false;
    for (let t = 0; t < 1000 && !bent; t += 16) {
      run(16);
      bent = letters(host).some(bending);
    }
    expect(bent).toBe(true);
    run(5000);
    expect(drawn(host)).toBe('Welcomeback');
    expect(onSettled).toHaveBeenLastCalledWith('Welcome back');
  });

  it('lands at once with reduced motion, and fades a change in whole', () => {
    stubMatchMedia(true);
    const onSettled = vi.fn();
    const host = show(<WispText text="Not yet" onSettled={onSettled} />);
    expect(drawn(host)).toBe('Notyet');
    expect(letters(host).some(bending)).toBe(false);
    expect(onSettled).toHaveBeenCalledExactlyOnceWith('Not yet');
    rerender(<WispText text="Now" onSettled={onSettled} />);
    expect(drawn(host)).toBe('Now');
    expect((host.firstElementChild as HTMLElement).className).toMatch(/faded/);
    expect(onSettled).toHaveBeenLastCalledWith('Now');
  });

  it('keeps no more than 48 filters however fast the letters come', () => {
    const host = show(<WispText text={'smoke '.repeat(40).trim()} pace={2000} />);
    let most = 0;
    for (let t = 0; t < 1500; t += 16) {
      run(16);
      most = Math.max(most, host.querySelectorAll('filter').length);
    }
    expect(most).toBe(48);
    run(5000);
    expect(letters(host).every((el) => !hidden(el) && !bending(el))).toBe(true);
  });

  it('lands the unseen tail at once when the box clips it, rather than typing on for nobody', () => {
    // A title clamped to its box: what it holds is shorter than what it is asked to show.
    const clientHeight = vi.spyOn(HTMLElement.prototype, 'clientHeight', 'get').mockReturnValue(20);
    const scrollHeight = vi.spyOn(HTMLElement.prototype, 'scrollHeight', 'get').mockReturnValue(100);
    try {
      const onSettled = vi.fn();
      const long = 'A title that runs on well past the two lines its card has room for';
      const host = show(<WispText text={long} pace={14} onSettled={onSettled} />);
      // One letter's setting later, and nowhere near the seconds the whole title would take at this pace.
      run(600);
      expect(onSettled).toHaveBeenCalledExactlyOnceWith(long);
      expect(letters(host).every((el) => !hidden(el) && !bending(el))).toBe(true);
    } finally {
      clientHeight.mockRestore();
      scrollHeight.mockRestore();
    }
  });

  it('takes its own nodes away when it goes, and leaves nothing moving', () => {
    const host = show(<WispText text="Gone soon" />);
    run(100);
    unmount();
    expect(host.querySelector('svg')).toBeNull();
    // Nothing is left on the clock to run against a page that is gone.
    expect(vi.getTimerCount()).toBe(0);
  });
});
