import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useRef } from 'react';
import { show, unmount } from '../../test/render.tsx';
import { stubMatchMedia } from '../../test/stubs.ts';
import * as edge from './wispEdge.ts';
import { WispEdgeFilter } from './WispEdgeFilter.tsx';

/**
 * The wisp edge's hook on a view, with the page's one filter mounted as the app mounts it: when a view wears the
 * smoke, where the bands are placed in the filter, the budget that keeps a view too large for the filter on its
 * plain fade, and the header watched by its border box. jsdom lays nothing out, so each view's sizes and scroll are
 * set by hand; the look of the smoke is nothing a test here can see (docs/DESIGN.md §54).
 */

/** Every ResizeObserver the hook made, and what each was told to watch. */
const watched: { target: Element; options?: ResizeObserverOptions }[] = [];

beforeEach(() => {
  stubMatchMedia(false);
  watched.length = 0;
  globalThis.ResizeObserver = class {
    observe(target: Element, options?: ResizeObserverOptions) {
      watched.push({ target, options });
    }
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
  localStorage.clear();
});

afterEach(() => {
  unmount();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

/** A view that can scroll `more` px past its height, wearing the hook, under a header `header` px tall when asked. */
function view({ more = 600, header = 0, foot = false }: { more?: number; header?: number; foot?: boolean } = {}) {
  function Page() {
    const scroller = useRef<HTMLDivElement>(null);
    const under = useRef<HTMLElement>(null);
    edge.useWispEdge(scroller, 'page', header ? under : undefined, { foot });
    return (
      <>
        <WispEdgeFilter />
        {header ? <header ref={under} data-testid="header" /> : null}
        <div ref={scroller} data-testid="view" />
      </>
    );
  }
  sizeViews({ more, header });
  const host = show(<Page />);
  const el = host.querySelector<HTMLElement>('[data-testid="view"]')!;
  return { host, el, scrollTo: (top: number) => scroll(el, top) };
}

/** Sizes every view, on the prototype since the hook reads them in its first effect: a header `header` px tall. */
function sizeViews({ more = 600, header = 0 }: { more?: number; header?: number }) {
  const sized = (name: 'clientHeight' | 'scrollHeight' | 'offsetHeight' | 'offsetWidth', value: (el: HTMLElement) => number) =>
    vi.spyOn(HTMLElement.prototype, name, 'get').mockImplementation(function (this: HTMLElement) {
      return value(this);
    });
  sized('clientHeight', () => 800);
  sized('offsetHeight', (el) => (el.tagName === 'HEADER' ? header : 800));
  sized('offsetWidth', () => 400);
  sized('scrollHeight', () => 800 + more);
}

function scroll(el: HTMLElement, top: number) {
  el.scrollTop = top;
  act(() => {
    el.dispatchEvent(new Event('scroll'));
  });
}

/**
 * A page and a column beside it, as Settings' split view has them: the page under no header, the column under a
 * header `header` px tall (the search field) and wearing the column's band; asking for a foot as well when `foot`.
 */
function pageAndColumn(header = 54, { foot = false }: { foot?: boolean } = {}) {
  function Split() {
    const page = useRef<HTMLDivElement>(null);
    const column = useRef<HTMLElement>(null);
    const field = useRef<HTMLElement>(null);
    edge.useWispEdge(page, 'page');
    edge.useWispEdge(column, 'column', field, { band: 'column', foot });
    return (
      <>
        <WispEdgeFilter />
        <header ref={field} />
        <nav ref={column} data-testid="column" />
        <div ref={page} data-testid="page" />
      </>
    );
  }
  sizeViews({ header });
  const host = show(<Split />);
  return {
    page: host.querySelector<HTMLElement>('[data-testid="page"]')!,
    column: host.querySelector<HTMLElement>('[data-testid="column"]')!,
  };
}

const attr = (id: string, name: string) => document.getElementById(id)?.getAttribute(name);

/**
 * The animation clock by hand, and the wait for the scrolling to stop on a fake clock: `run` plays `count` frames.
 * The frames' time only ever goes forward, across tests too - the drift keeps the last step's time, and a step
 * stamped before it is no step at all.
 */
let clockAt = 1e9;
function animationClock() {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  const frames = new Map<number, FrameRequestCallback>();
  let id = 0;
  vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback) => {
    frames.set(++id, callback);
    return id;
  });
  vi.stubGlobal('cancelAnimationFrame', (which: number) => frames.delete(which));
  vi.spyOn(Document.prototype, 'visibilityState', 'get').mockReturnValue('visible');
  return (count = 6) => {
    for (let i = 0; i < count; i += 1) {
      clockAt += 40;
      const due = [...frames.values()];
      frames.clear();
      for (const frame of due) frame(clockAt);
    }
  };
}

describe('the page’s filter', () => {
  it('carries an element for every id the hook writes to', () => {
    show(<WispEdgeFilter />);
    const ids = Object.entries(edge).filter(([name]) => name.endsWith('_ID'));
    expect(ids.length).toBeGreaterThan(10);
    for (const [name, id] of ids) expect(document.getElementById(id as string), name).not.toBeNull();
  });
});

describe('the budget', () => {
  it('holds a region to 2^24 of the screen’s own pixels', () => {
    vi.stubGlobal('devicePixelRatio', 1);
    expect(edge.withinWispBudget(4096, 4096)).toBe(true);
    expect(edge.withinWispBudget(4200, 4000)).toBe(false);
    // At two device pixels to the CSS pixel, the boundary moves to 2048 exactly.
    vi.stubGlobal('devicePixelRatio', 2);
    expect(edge.withinWispBudget(2048, 2048)).toBe(true);
    expect(edge.withinWispBudget(2049, 2048)).toBe(false);
  });
});

describe('useWispEdge', () => {
  it('wears the smoke once the view is scrolled off its top, and puts it away at the top again', () => {
    const { el, scrollTo } = view();
    expect(el.dataset.wispDraw).toBe('filter');
    expect(el.hasAttribute('data-wisp-edge')).toBe(false);
    scrollTo(120);
    expect(el.hasAttribute('data-wisp-edge')).toBe(true);
    // The strip over the view's top, from above it down to the lip: no header, and a phone with no status bar.
    expect(attr(edge.WISP_EDGE_STRIP_ID, 'height')).toBe(String(edge.WISP_EDGE_ABOVE + edge.WISP_EDGE_BAND));
    expect(attr(edge.WISP_EDGE_NOISE_ID, 'height')).toBe(String(40 + edge.WISP_EDGE_REACH));
    scrollTo(0);
    expect(el.hasAttribute('data-wisp-edge')).toBe(false);
    expect(attr(edge.WISP_EDGE_STRIP_ID, 'height')).toBe('0');
  });

  it('never smokes a view that cannot scroll, whatever its scrollTop says', () => {
    const { el, scrollTo } = view({ more: 0 });
    scrollTo(120);
    expect(el.hasAttribute('data-wisp-edge')).toBe(false);
  });

  it('moves the band under a header, and watches the header by its border box', () => {
    const { host, el, scrollTo } = view({ header: 60 });
    scrollTo(120);
    // Above the view, the header, the drop under its edge, and the lip.
    expect(Number(attr(edge.WISP_EDGE_STRIP_ID, 'height'))).toBeGreaterThan(edge.WISP_EDGE_ABOVE + 60 + edge.WISP_EDGE_BAND);
    expect(el.style.getPropertyValue('--wisp-under')).toBe('60px');
    expect(el.hasAttribute('data-under-header')).toBe(true);
    const header = host.querySelector('[data-testid="header"]');
    expect(watched.find((w) => w.target === header)?.options).toEqual({ box: 'border-box' });
  });

  it('smokes the foot while there is more below, and not at the end', () => {
    const { el, scrollTo } = view({ foot: true });
    expect(el.hasAttribute('data-wisp-foot')).toBe(true);
    // The foot's strip at the view's bottom edge, lifted to where the words still are.
    expect(attr(edge.WISP_EDGE_FOOT_STRIP_ID, 'y')).toBe(String(800 - edge.WISP_EDGE_FOOT_LIFT - edge.WISP_EDGE_FOOT_BAND));
    scrollTo(600);
    expect(el.hasAttribute('data-wisp-foot')).toBe(false);
    expect(attr(edge.WISP_EDGE_FOOT_STRIP_ID, 'y')).toBe(String(1e6));
  });

  it('keeps a window too large for the filter’s budget on its plain fade', () => {
    vi.stubGlobal('innerWidth', 5000);
    vi.stubGlobal('innerHeight', 5000);
    const { el, scrollTo } = view({ foot: true });
    scrollTo(120);
    expect(el.hasAttribute('data-wisp-edge')).toBe(false);
    expect(el.hasAttribute('data-wisp-foot')).toBe(false);
  });

  it('draws nothing at all with the smoke switched off in Settings', async () => {
    const { setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
    setPreferences({ wispEdge: false });
    try {
      const { el, scrollTo } = view();
      scrollTo(120);
      expect(el.dataset.wispDraw).toBeUndefined();
      expect(el.hasAttribute('data-wisp-edge')).toBe(false);
    } finally {
      setPreferences(DEFAULT_PREFERENCES);
    }
  });

  it('takes everything it put on the view away when it goes', () => {
    const { el, scrollTo } = view({ foot: true, header: 40 });
    scrollTo(120);
    unmount();
    expect(el.hasAttribute('data-wisp-edge')).toBe(false);
    expect(el.hasAttribute('data-wisp-foot')).toBe(false);
    expect(el.hasAttribute('data-under-header')).toBe(false);
    expect(el.dataset.wispDraw).toBeUndefined();
  });
});

/*
 * Settings' split view scrolls a column beside a page, both smoking at their tops at once under headers of different
 * heights. On the one filter the second view placed moved the first one's band too (every attribute on a filter is
 * global) and the drift moved both while one scrolled; the column has a band of its own.
 */
describe('a column’s band beside the page’s', () => {
  it('places each under its own header, and takes only its own away at the top', () => {
    const { page, column } = pageAndColumn(54);
    scroll(page, 120);
    scroll(column, 120);
    expect(page.getAttribute('data-wisp-edge')).toBe('');
    expect(column.getAttribute('data-wisp-edge')).toBe('column');
    // The page's strip at its own top, as if the column were not there; the column's under its 54px header.
    expect(attr(edge.WISP_EDGE_STRIP_ID, 'height')).toBe(String(edge.WISP_EDGE_ABOVE + edge.WISP_EDGE_BAND));
    expect(Number(attr(edge.WISP_EDGE_COLUMN_STRIP_ID, 'height'))).toBeGreaterThan(edge.WISP_EDGE_ABOVE + 54 + edge.WISP_EDGE_BAND);
    expect(column.style.getPropertyValue('--wisp-under')).toBe('54px');
    expect(page.style.getPropertyValue('--wisp-under')).toBe('0px');
    // The page's region is the window's; the column's is the column's own width, and the window's height.
    expect(attr(edge.WISP_EDGE_FILTER_ID, 'width')).toBe(String(innerWidth + edge.WISP_EDGE_SIDE * 2));
    expect(attr(edge.WISP_EDGE_COLUMN_FILTER_ID, 'width')).toBe(String(400 + edge.WISP_EDGE_SIDE * 2));
    expect(attr(edge.WISP_EDGE_COLUMN_FILTER_ID, 'height')).toBe(attr(edge.WISP_EDGE_FILTER_ID, 'height'));
    // And the foot's is still the page's: the column's, cut to its width, would have clipped a page smoking at its foot.
    expect(attr(edge.WISP_EDGE_FOOT_FILTER_ID, 'width')).toBe(attr(edge.WISP_EDGE_FILTER_ID, 'width'));
    scroll(column, 0);
    expect(column.hasAttribute('data-wisp-edge')).toBe(false);
    expect(attr(edge.WISP_EDGE_COLUMN_STRIP_ID, 'height')).toBe('0');
    expect(attr(edge.WISP_EDGE_STRIP_ID, 'height')).toBe(String(edge.WISP_EDGE_ABOVE + edge.WISP_EDGE_BAND));
  });

  it('cuts the column’s region to the column, out to its right-hand edge in the window', () => {
    // WebKit counts the region from the document's corner: a column standing 100px in reaches 500px across.
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue(new DOMRect(100, 0, 400, 800));
    const { column } = pageAndColumn(54);
    scroll(column, 120);
    expect(attr(edge.WISP_EDGE_COLUMN_FILTER_ID, 'width')).toBe(String(500 + edge.WISP_EDGE_SIDE * 2));
  });

  it('holds the column to the budget together with the page beside it', () => {
    // Two device pixels to the CSS pixel, as on the Mac. At 1800 x 1100 the pair fits, and both smoke.
    vi.stubGlobal('devicePixelRatio', 2);
    vi.stubGlobal('innerWidth', 1800);
    vi.stubGlobal('innerHeight', 1100);
    let views = pageAndColumn(54);
    scroll(views.page, 120);
    scroll(views.column, 120);
    expect(views.page.getAttribute('data-wisp-edge')).toBe('');
    expect(views.column.getAttribute('data-wisp-edge')).toBe('column');
    unmount();
    // At 2200 x 1300 the page's region fits on its own (0.86 of the budget) and the pair does not (1.04): WebKit
    // drew nothing at all past the budget together, so the column keeps its plain edge and the page smokes.
    vi.stubGlobal('innerWidth', 2200);
    vi.stubGlobal('innerHeight', 1300);
    views = pageAndColumn(54);
    scroll(views.page, 120);
    scroll(views.column, 120);
    expect(views.page.getAttribute('data-wisp-edge')).toBe('');
    expect(views.column.hasAttribute('data-wisp-edge')).toBe(false);
  });

  it('eases the column’s lip down over the first px of its scroll, and leaves the page’s where it is', () => {
    const { page, column } = pageAndColumn(54);
    const strip = () => Number(attr(edge.WISP_EDGE_COLUMN_STRIP_ID, 'height'));
    scroll(column, 10);
    const early = strip();
    scroll(column, 20);
    expect(strip()).toBe(early + 10);
    scroll(column, 120);
    // Settled a band's depth below where it began, and there it stays.
    expect(strip()).toBe(early + edge.WISP_EDGE_EASE - 10);
    scroll(column, 400);
    expect(strip()).toBe(early + edge.WISP_EDGE_EASE - 10);
    // Under no header, at its own top, and never eased: the page's first lines are not at an edge.
    scroll(page, 10);
    expect(attr(edge.WISP_EDGE_STRIP_ID, 'height')).toBe(String(edge.WISP_EDGE_ABOVE + edge.WISP_EDGE_BAND));
  });

  it('never smokes a column at its foot, asked or not: the two-ended rule would have worn the page’s band', () => {
    const { column } = pageAndColumn(54, { foot: true });
    scroll(column, 120);
    expect(column.hasAttribute('data-wisp-foot')).toBe(false);
    expect(column.getAttribute('data-wisp-edge')).toBe('column');
  });

  it('drifts a masked column’s smoke on the column, not on the page', () => {
    localStorage.setItem('glyph-wisp-draw', 'mask');
    const run = animationClock();
    try {
      const { page, column } = pageAndColumn(54);
      expect(column.dataset.wispDraw).toBe('mask');
      const lip = () => parseFloat(column.style.getPropertyValue('--wisp-lip'));
      const atRest = lip();
      scroll(column, 120);
      run();
      expect(column.style.getPropertyValue('--wisp-noise-y')).not.toBe('');
      expect(column.style.getPropertyValue('--wisp-noise-y')).not.toBe('0px');
      expect(page.style.getPropertyValue('--wisp-noise-y')).toBe('');
      // And the mask's lip eases as the filter's strip does: a band's depth further down once the scroll is under way.
      expect(lip() - atRest).toBe(edge.WISP_EDGE_EASE);
    } finally {
      unmount();
      vi.useRealTimers();
    }
  });

  it('puts the column’s band back to rest at its top, and leaves the page’s drifted', () => {
    const run = animationClock();
    try {
      const { page, column } = pageAndColumn(54);
      scroll(page, 120);
      scroll(column, 120);
      run();
      expect(attr(edge.WISP_EDGE_COLUMN_DRIFT_ID, 'dy')).not.toBe('0');
      const pageDrift = attr(edge.WISP_EDGE_DRIFT_ID, 'dy');
      expect(pageDrift).not.toBe('0');
      scroll(column, 0);
      expect(attr(edge.WISP_EDGE_COLUMN_DRIFT_ID, 'dy')).toBe('0');
      expect(attr(edge.WISP_EDGE_COLUMN_DRIFT_ID, 'dx')).toBe('0');
      expect(attr(edge.WISP_EDGE_COLUMN_NOISE_ID, 'baseFrequency')).toBe('0.018 0.06');
      expect(attr(edge.WISP_EDGE_DRIFT_ID, 'dy')).toBe(pageDrift);
    } finally {
      unmount();
      vi.useRealTimers();
    }
  });

  it('drifts only the band being scrolled: the column’s smoke holds while the page beside it scrolls', () => {
    const run = animationClock();
    try {
      const { page, column } = pageAndColumn(54);
      scroll(column, 120);
      run();
      const held = attr(edge.WISP_EDGE_COLUMN_DRIFT_ID, 'dy');
      expect(held).not.toBe('0');
      expect(attr(edge.WISP_EDGE_DRIFT_ID, 'dy')).toBe('0');
      // The column's scrolling stops; the page's starts, and goes on for a while.
      act(() => vi.advanceTimersByTime(200));
      scroll(page, 120);
      run();
      scroll(page, 160);
      run();
      expect(attr(edge.WISP_EDGE_DRIFT_ID, 'dy')).not.toBe('0');
      expect(attr(edge.WISP_EDGE_COLUMN_DRIFT_ID, 'dy')).toBe(held);
      // And the column picks up again when it is scrolled.
      scroll(column, 160);
      run();
      expect(attr(edge.WISP_EDGE_COLUMN_DRIFT_ID, 'dy')).not.toBe(held);
    } finally {
      unmount();
      vi.useRealTimers();
    }
  });
});

describe('whether the foot smokes, for a note to keep its caret clear of it', () => {
  it('smokes where it is drawn as smoke, and not with the preference off', () => {
    expect(edge.footSmokes(true)).toBe(true);
    expect(edge.footSmokes(false)).toBe(false);
  });

  it('does not on a desktop, whose foot is a plain fade', () => {
    localStorage.setItem('glyph-wisp-head', 'blur');
    expect(edge.wispModeFor()).toBe('fade');
    expect(edge.footSmokes(true)).toBe(false);
  });

  it('does not with reduced motion, which takes the filter away, but the mask stays', () => {
    localStorage.setItem('glyph-wisp-head', 'smoke');
    stubMatchMedia(true);
    expect(edge.footSmokes(true)).toBe(false);
    localStorage.setItem('glyph-wisp-draw', 'mask');
    expect(edge.footSmokes(true)).toBe(true);
  });
});
