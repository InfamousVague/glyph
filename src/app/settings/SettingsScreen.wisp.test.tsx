import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, unmount } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

/**
 * Settings' split view with the wisp edge's real hook (SettingsScreen.test.tsx stands it in): the left column smokes
 * under the search field as a page does under its header (Matt: "on the settings page when scrolling on the left
 * sidebar we should see the wisp fade effect under the search bar covering the overflowing content like we see with
 * the header on the main page"), on a band of its own beside the section's page; the phone's list stays as it was; and
 * the column goes without with "Smoke at the edges" switched off and holds still under reduced motion.
 *
 * jsdom lays nothing out, so the field's height and the views' sizes are set by hand; how the smoke looks is the
 * renders' to show (docs/DESIGN.md §54).
 */

// The split view is the sidebar's line; each test says which side of it the window is.
let wide = true;
vi.mock('../core/useWideScreen.ts', () => ({ useSidebar: () => wide }));

const { SettingsScreen } = await import('./SettingsScreen.tsx');
const { WispEdgeFilter } = await import('../art/WispEdgeFilter.tsx');
const edge = await import('../art/wispEdge.ts');
const { setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
import type { SettingsSection } from './SettingsScreen.tsx';

const sections: SettingsSection[] = [
  { id: 'type', label: 'Type', icon: null, group: 0, content: <div className="setk-row">Text size</div> },
  { id: 'animations', label: 'Animations', icon: null, group: 1, content: <div className="setk-row">Smoke at the edges</div> },
];

/** The search field's height, as the hook would measure it. */
const FIELD = 58;

/** What the screen answers for each media query: a desktop's pointer, and reduced motion. */
function screen({ desktop = false, still = false } = {}) {
  window.matchMedia = (query: string) =>
    ({
      matches: (query.includes('pointer: fine') && desktop) || (query.includes('reduced-motion') && still),
      media: query,
      onchange: null,
      addListener: () => undefined,
      removeListener: () => undefined,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
      dispatchEvent: () => false,
    }) as MediaQueryList;
}

beforeEach(() => {
  wide = true;
  screen();
  stubResizeObserver();
  localStorage.clear();
  const sized = (name: 'clientHeight' | 'scrollHeight' | 'offsetHeight' | 'offsetWidth', value: (el: HTMLElement) => number) =>
    vi.spyOn(HTMLElement.prototype, name, 'get').mockImplementation(function (this: HTMLElement) {
      return value(this);
    });
  // Every view 400 tall with 600 more to scroll, the field its own height.
  sized('clientHeight', () => 400);
  sized('scrollHeight', () => 1000);
  sized('offsetHeight', (el) => (el.classList.contains('settingsScreen__find') ? FIELD : 400));
  sized('offsetWidth', () => 320);
});

afterEach(() => {
  unmount();
  setPreferences(DEFAULT_PREFERENCES);
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function render() {
  return show(
    <>
      <WispEdgeFilter />
      <SettingsScreen open onClose={() => {}} sections={sections} />
    </>,
  );
}

function scroll(el: HTMLElement, top: number) {
  el.scrollTop = top;
  act(() => {
    el.dispatchEvent(new Event('scroll'));
  });
}

const attr = (id: string, name: string) => document.getElementById(id)?.getAttribute(name);
const columnOf = (host: HTMLElement) => host.querySelector<HTMLElement>('.settingsScreen__side > .settingsScreen__list')!;
const paneOf = (host: HTMLElement) => host.querySelector<HTMLElement>('.settingsScreen__pane')!;

describe('the split view’s left column', () => {
  it('smokes under the search field on a band of its own, apart from the page’s', () => {
    const host = render();
    const column = columnOf(host);
    const pane = paneOf(host);
    expect(column.hasAttribute('data-wisp-edge')).toBe(false);
    // The sections start under the field, and the column's scrollbar with them (app.css `[data-under-header]`).
    expect(column.style.getPropertyValue('--wisp-under')).toBe(`${FIELD}px`);
    expect(column.hasAttribute('data-under-header')).toBe(true);
    scroll(column, 120);
    expect(column.getAttribute('data-wisp-edge')).toBe('column');
    expect(pane.hasAttribute('data-wisp-edge')).toBe(false);
    // The column's band is under the field; the page's, placed by the pane, is at the pane's own top.
    expect(Number(attr(edge.WISP_EDGE_COLUMN_STRIP_ID, 'height'))).toBeGreaterThan(edge.WISP_EDGE_ABOVE + FIELD + edge.WISP_EDGE_BAND);
    scroll(pane, 120);
    expect(pane.getAttribute('data-wisp-edge')).toBe('');
    expect(attr(edge.WISP_EDGE_STRIP_ID, 'height')).toBe(String(edge.WISP_EDGE_ABOVE + edge.WISP_EDGE_BAND));
    expect(column.getAttribute('data-wisp-edge')).toBe('column');
    scroll(column, 0);
    expect(column.hasAttribute('data-wisp-edge')).toBe(false);
    expect(pane.getAttribute('data-wisp-edge')).toBe('');
  });

  it('hangs the blur strip under the field on a desktop, inside the column, as the home page does under its bar', () => {
    screen({ desktop: true });
    const host = render();
    const column = columnOf(host);
    const strip = host.querySelector<HTMLElement>('.settingsScreen__side > .settingsScreen__find + .app-headerBlur');
    expect(strip).not.toBeNull();
    expect(strip!.style.top).toBe(`${FIELD}px`);
    expect(strip!.hasAttribute('data-on')).toBe(false);
    scroll(column, 120);
    expect(strip!.hasAttribute('data-on')).toBe(true);
    expect(column.dataset.wispDraw).toBe('fade');
  });

  it('leaves the phone’s list as it was: the page’s band, under no header, and nothing else wearing one', () => {
    wide = false;
    const host = render();
    const list = host.querySelector<HTMLElement>('.settingsScreen__list')!;
    scroll(list, 120);
    expect(list.getAttribute('data-wisp-edge')).toBe('');
    expect(list.hasAttribute('data-under-header')).toBe(false);
    expect(host.querySelectorAll('[data-wisp-draw]')).toHaveLength(1);
    expect(host.querySelector('.app-headerBlur')).toBeNull();
  });

  it('goes without with "Smoke at the edges" switched off', () => {
    setPreferences({ wispEdge: false });
    const host = render();
    const column = columnOf(host);
    scroll(column, 120);
    expect(column.dataset.wispDraw).toBeUndefined();
    expect(column.hasAttribute('data-wisp-edge')).toBe(false);
    expect(column.style.getPropertyValue('--wisp-under')).toBe('');
  });

  it('holds still under reduced motion, and the stylesheet takes its filter off', () => {
    const frames = vi.fn(() => 1);
    vi.stubGlobal('requestAnimationFrame', frames);
    vi.stubGlobal('cancelAnimationFrame', () => undefined);
    // Moving, the scroll starts the drift on the animation clock: the reading below is one that can fail.
    let host = render();
    scroll(columnOf(host), 120);
    expect(frames).toHaveBeenCalled();
    unmount();
    frames.mockClear();
    screen({ still: true });
    host = render();
    scroll(columnOf(host), 120);
    expect(columnOf(host).getAttribute('data-wisp-edge')).toBe('column');
    expect(frames).not.toHaveBeenCalled();
    // The column's filter is set at the weight of the page's, so the reduced-motion rule, later, still wins over it.
    const css = readFileSync(join(import.meta.dirname, '../art/wisp.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    const own = css.indexOf("[data-wisp-edge='column'] {");
    const still = css.indexOf('@media (prefers-reduced-motion: reduce)');
    expect(own).toBeGreaterThan(-1);
    expect(still).toBeGreaterThan(own);
    expect(css.slice(still, css.indexOf('}', css.indexOf('}', still) + 1))).toMatch(/\[data-wisp-edge\],[\s\S]*filter: none/);
  });
});
