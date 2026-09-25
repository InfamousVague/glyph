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
  // Sizes first, on the prototype, since the hook reads them in its first effect.
  const sized = (name: 'clientHeight' | 'scrollHeight' | 'offsetHeight' | 'offsetWidth', value: (el: HTMLElement) => number) =>
    vi.spyOn(HTMLElement.prototype, name, 'get').mockImplementation(function (this: HTMLElement) {
      return value(this);
    });
  sized('clientHeight', () => 800);
  sized('offsetHeight', (el) => (el.tagName === 'HEADER' ? header : 800));
  sized('offsetWidth', () => 400);
  sized('scrollHeight', () => 800 + more);
  const host = show(<Page />);
  const el = host.querySelector<HTMLElement>('[data-testid="view"]')!;
  const scrollTo = (top: number) => {
    el.scrollTop = top;
    act(() => {
      el.dispatchEvent(new Event('scroll'));
    });
  };
  return { host, el, scrollTo };
}

const attr = (id: string, name: string) => document.getElementById(id)?.getAttribute(name);

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
