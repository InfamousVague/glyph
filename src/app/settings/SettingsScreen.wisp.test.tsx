import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { rerender, show, unmount } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

/**
 * Settings' split view with the wisp edge's real hook (SettingsScreen.test.tsx stands it in): the left column smokes
 * under the search field as a page does under its header (Matt: "on the settings page when scrolling on the left
 * sidebar we should see the wisp fade effect under the search bar covering the overflowing content like we see with
 * the header on the main page"), on a band of its own beside the section's page; the phone's list stays as it was; and
 * the column goes without with "Smoke at the edges" switched off and holds still under reduced motion. And the
 * stylesheet's half, read as text: the field laid over the column only, the rows starting under it at rest and
 * brought out from under it when focused, and the column's scrollbar from the field's edge.
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

const screenOf = () => (
  <>
    <WispEdgeFilter />
    <SettingsScreen open onClose={() => {}} sections={sections} />
  </>
);

function render() {
  return show(screenOf());
}

/** A stylesheet as text, comments out. */
const sheet = (path: string) => readFileSync(join(import.meta.dirname, path), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');

/** A sheet's innermost rules, selector and body: one inside an `@media` is read without it. */
const rulesOf = (css: string) =>
  [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(([, selector = '', body = '']) => ({ selector: selector.trim().split(/\s+/).join(' '), body }));

/** The body of the rule whose whole selector is `selector`, not one of a list: `null` when there is none. */
const ruleOf = (css: string, selector: string) => rulesOf(css).find((rule) => rule.selector === selector)?.body ?? null;

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
    // A desktop's plain edges have nothing for the drift to move: scrolling starts no animation loop.
    const frames = vi.fn(() => 1);
    vi.stubGlobal('requestAnimationFrame', frames);
    vi.stubGlobal('cancelAnimationFrame', () => undefined);
    const host = render();
    const column = columnOf(host);
    const strip = host.querySelector<HTMLElement>('.settingsScreen__side > .settingsScreen__find + .app-headerBlur');
    expect(strip).not.toBeNull();
    expect(strip!.style.top).toBe(`${FIELD}px`);
    expect(strip!.hasAttribute('data-on')).toBe(false);
    scroll(column, 120);
    expect(strip!.hasAttribute('data-on')).toBe(true);
    expect(column.dataset.wispDraw).toBe('fade');
    scroll(column, 160);
    expect(frames).not.toHaveBeenCalled();
  });

  it('gives the column its edge when the window opens out with Settings open, as the Fold does unfolding', () => {
    wide = false;
    render();
    wide = true;
    rerender(screenOf());
    const column = columnOf(document.body);
    expect(column).not.toBeNull();
    scroll(column, 120);
    expect(column.getAttribute('data-wisp-edge')).toBe('column');
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
    const css = sheet('../art/wisp.css');
    // Its own selector exactly, at the start of a line: `.settingsScreen__list[data-wisp-edge='column']` would outweigh it.
    const own = css.search(/^\[data-wisp-edge='column'\] \{/m);
    const still = css.indexOf('@media (prefers-reduced-motion: reduce)');
    expect(own).toBeGreaterThan(-1);
    expect(still).toBeGreaterThan(own);
    expect(css.slice(still, css.indexOf('}', css.indexOf('}', still) + 1))).toMatch(/\[data-wisp-edge\],[\s\S]*filter: none/);
  });
});

describe('the column’s stylesheet', () => {
  const css = sheet('settings.css');

  it('lays the field over the split view’s column only: the phone’s field stands above its list', () => {
    const over = ruleOf(css, '.settingsScreen__side > .settingsScreen__find');
    expect(over).toMatch(/position: absolute/);
    // No other rule for the field takes it out of the flow.
    const lifted = rulesOf(css).filter((rule) => rule.selector.includes('settingsScreen__find') && /position:\s*(absolute|fixed)/.test(rule.body));
    expect(lifted.map((rule) => rule.selector)).toEqual(['.settingsScreen__side > .settingsScreen__find']);
  });

  it('starts the rows under the field at rest, floored at the field’s own height, and brings a focused row out from under it', () => {
    const list = ruleOf(css, '.settingsScreen__side > .settingsScreen__list');
    expect(list).not.toBeNull();
    const top = /--settings-column-top: max\(var\(--wisp-under, 0px\), calc\(([^;]+)\)\);/.exec(list!);
    expect(top).not.toBeNull();
    // The floor is the field: its padding above and below (`.settingsScreen__find`) and its pill between them.
    const field = ruleOf(css, '.settingsScreen__find');
    const [above, below] = /padding-block: (var\([^)]+\)) (var\([^)]+\));/.exec(field!)!.slice(1);
    expect(top![1]).toBe(`${above} + var(--settings-find-pill) + ${below}`);
    expect(ruleOf(css, '.settingsScreen__findPill')).toMatch(/min-block-size: var\(--settings-find-pill\);/);
    expect(list).toMatch(/padding-block-start: var\(--settings-column-top\);/);
    // Focus scrolls a row clear of the field, which the hook measures rounded down.
    expect(list).toMatch(/scroll-padding-block-start: calc\(var\(--settings-column-top\) \+ 1px\);/);
  });

  it('starts the column’s scrollbar at the field’s edge, where the rows start', () => {
    const track = ruleOf(css, '.settingsScreen__side > .settingsScreen__list::-webkit-scrollbar-track');
    expect(track).toMatch(/margin-block-start: var\(--wisp-under, 0px\);/);
    expect(track).toMatch(/margin-top: var\(--wisp-under, 0px\);/);
  });
});
