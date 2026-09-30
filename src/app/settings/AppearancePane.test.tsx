import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// On a phone, where there is a motor, or in a browser or on the Mac, where there is none.
let phone = true;
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isNativeMobile() {
    return phone;
  },
}));
// A window wide enough for the sidebar, or a phone's.
let wide = false;
vi.mock('../core/useWideScreen.ts', () => ({ useSidebar: () => wide }));

const { AppearancePane } = await import('./AppearancePane.tsx');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const { hapticsPref } = await import('../core/haptics.ts');

/**
 * Appearance's page (docs/DESIGN.md §138): how it looks, moves and feels, with Type, Motion (Feel's Speed and
 * Movement, which were Animations) and Touch as cards where they were pages, each switch writing what the app reads.
 */

beforeEach(() => {
  phone = true;
  wide = false;
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
});

const titles = (host: HTMLElement) => [...host.querySelectorAll('.setk__title')].map((title) => title.textContent);
const labels = (host: HTMLElement, card: string) =>
  [...[...host.querySelectorAll('section')].find((s) => s.querySelector('.setk__title')?.textContent === card)!.querySelectorAll('.setk-row__label')].map((l) => l.textContent);

describe('the Appearance page', () => {
  it('holds the look, the type, the motion and, on a phone, the touch, in that order', () => {
    expect(titles(show(<AppearancePane />))).toEqual(['Page', 'Home page', 'Accent', 'Type', 'Spacing', 'Corners', 'Code', 'Motion', 'Touch']);
  });

  it('keeps the two size dials together in Type, beside the two faces', () => {
    const host = show(<AppearancePane />);
    expect(labels(host, 'Type')).toEqual(['Note font', 'Interface font', 'Text size', 'Scale']);
    expect(labels(host, 'Motion')).toEqual(['Animation speed', 'Ghostly typing', 'Smoke at the edges', 'Ripples while recording']);
    // The sample in the card's head, where the paragraph that told the two sizes apart was.
    expect(host.querySelector('section .setk__desc .settingsScreen__sample')?.textContent).toBe('Aa');
    expect(host.textContent).not.toContain('Text size, under Type');
  });

  it('has no Touch where there is no motor, and no Sidebar on a phone, where it changes nothing', () => {
    phone = false;
    const host = show(<AppearancePane />);
    expect(titles(host)).toEqual(['Page', 'Home page', 'Accent', 'Type', 'Spacing', 'Corners', 'Code', 'Motion']);
    expect(host.querySelector('[aria-label="Haptics"]')).toBeNull();
    expect(host.querySelector('[aria-label="Sidebar"]')).toBeNull();
  });

  it('offers the home page’s layouts, Cards chosen at first, and writes the one picked (docs/DESIGN.md §147, §148)', () => {
    const host = show(<AppearancePane />);
    expect(labels(host, 'Home page')).toEqual(['Cards', 'Timeline', 'Card timeline', 'Spotlight', 'Shelf and timeline', 'Notebook cards', 'List', 'Shelf', 'Library']);
    const picked = () => [...host.querySelectorAll('.setk-pick[aria-checked="true"]')].map((pick) => pick.getAttribute('aria-label'));
    expect(picked()).toEqual(['Cards']);
    act(() => host.querySelector<HTMLElement>('.setk-pick[aria-label="Spotlight"]')!.click());
    expect(preferences().homeLayout).toBe('spotlight');
    expect(picked()).toEqual(['Spotlight']);
  });

  it('offers the sidebar’s choice on a window wide enough for the sidebar, and writes it', () => {
    wide = true;
    const host = show(<AppearancePane />);
    expect(titles(host)).toContain('Sidebar');
    act(() => host.querySelector<HTMLInputElement>('input[type="radio"][value="docked"]')!.click());
    expect(preferences().sidebarStyle).toBe('docked');
  });

  it('writes each switch to what the app reads', () => {
    const host = show(<AppearancePane />);
    const wisp = preferences().wisp;
    act(() => host.querySelector<HTMLElement>('[aria-label="Ghostly typing"]')!.click());
    expect(preferences().wisp).toBe(!wisp);
    const haptics = hapticsPref();
    act(() => host.querySelector<HTMLElement>('[aria-label="Haptics"]')!.click());
    expect(hapticsPref()).toBe(!haptics);
  });

  it('writes the text size and the scale, each its own preference', () => {
    const host = show(<AppearancePane />);
    act(() => host.querySelector<HTMLInputElement>('input[type="radio"][value="largest"]')!.click());
    expect(preferences().textSize).toBe('largest');
    act(() => host.querySelector<HTMLInputElement>('input[name="ui-scale"][value="1.1"]')!.click());
    expect(preferences().uiScale).toBe(1.1);
    expect(preferences().textSize).toBe('largest');
  });

  it('has no Link previews: that is Account’s Privacy card now', () => {
    expect(show(<AppearancePane />).querySelector('[aria-label="Link previews"]')).toBeNull();
  });
});
