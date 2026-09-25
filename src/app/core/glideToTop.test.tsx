import { useRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { rerender, show, unmount } from '../../test/render.tsx';
import { stubMatchMedia } from '../../test/stubs.ts';
import { useGlideToTop } from './glideToTop.ts';

/*
 * The home page gliding back to its top when a workspace is chosen (glideToTop.ts), rather than the browser snapping
 * it up because the new list is shorter. jsdom lays nothing out, so the scroller's heights are set by hand and its
 * scrolling is a stand-in that says where it was asked to go; the clock is the test's.
 */

let scroller: HTMLDivElement;
const asked: ScrollToOptions[] = [];

function Home({ workspace }: { workspace: string | null }) {
  const ref = useRef<HTMLDivElement>(null);
  useGlideToTop(ref, workspace);
  return <div ref={ref} />;
}

/** The page up on `workspace`, its list `listHeight` tall in a window 500 tall, scrolled to `top`. */
function mount(workspace: string | null, listHeight: number, top: number): void {
  scroller = show(<Home workspace={workspace} />).firstElementChild as HTMLDivElement;
  Object.defineProperty(scroller, 'clientHeight', { configurable: true, value: 500 });
  height(listHeight);
  scroller.scrollTop = top;
  scroller.dispatchEvent(new Event('scroll'));
  scroller.scrollTo = ((options: ScrollToOptions) => asked.push(options)) as typeof scroller.scrollTo;
}

function height(px: number): void {
  Object.defineProperty(scroller, 'scrollHeight', { configurable: true, value: px });
}

/** Another workspace chosen, whose list is `listHeight` tall. */
function choose(workspace: string | null, listHeight: number): void {
  height(listHeight);
  rerender(<Home workspace={workspace} />);
}

beforeEach(() => {
  asked.length = 0;
  vi.useFakeTimers();
  delete (window as { matchMedia?: unknown }).matchMedia;
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
});

describe('choosing another workspace', () => {
  it('holds the page where it was over the shorter list, and glides it to the top', () => {
    mount('home', 3_000, 1_200);
    choose('work', 800);
    // 1,200 down in a 500 window needs 1,700 of page; the list is 800, so 900 is borrowed at its foot.
    expect(scroller.style.paddingBlockEnd).toBe('900px');
    expect(scroller.scrollTop).toBe(1_200);
    expect(asked).toEqual([{ top: 0, behavior: 'smooth' }]);
  });

  it('gives the borrowed room back when the glide reaches the top, and not at the scrollend of being put back', () => {
    mount('home', 3_000, 1_200);
    choose('work', 800);
    scroller.dispatchEvent(new Event('scrollend'));
    expect(scroller.style.paddingBlockEnd).toBe('900px');
    scroller.scrollTop = 0;
    scroller.dispatchEvent(new Event('scrollend'));
    expect(scroller.style.paddingBlockEnd).toBe('');
  });

  it('gives it back without scrollend too: at the top, or after three seconds whatever happened', () => {
    mount('home', 3_000, 1_200);
    choose('work', 800);
    vi.advanceTimersByTime(2_900);
    expect(scroller.style.paddingBlockEnd).toBe('900px');
    vi.advanceTimersByTime(400);
    expect(scroller.style.paddingBlockEnd).toBe('');

    choose('home', 800);
    scroller.scrollTop = 0;
    vi.advanceTimersByTime(700);
    expect(scroller.style.paddingBlockEnd).toBe('');
  });

  it('borrows nothing when the new list is long enough, and does nothing from the top or for no workspace', () => {
    mount('home', 3_000, 1_200);
    choose('work', 3_000);
    expect(scroller.style.paddingBlockEnd).toBe('');
    expect(asked).toHaveLength(1);
    unmount();
    asked.length = 0;
    mount('home', 3_000, 0);
    choose('work', 800);
    choose(null, 800);
    expect(asked).toEqual([]);
  });

  it('goes straight to the top where less motion is asked for', () => {
    stubMatchMedia(true);
    mount('home', 3_000, 1_200);
    choose('work', 800);
    expect(asked).toEqual([{ top: 0, behavior: 'auto' }]);
    expect(scroller.style.paddingBlockEnd).toBe('');
  });

  it('gives the room back when the page goes mid-glide', () => {
    mount('home', 3_000, 1_200);
    choose('work', 800);
    const was = scroller;
    unmount();
    expect(was.style.paddingBlockEnd).toBe('');
  });
});
