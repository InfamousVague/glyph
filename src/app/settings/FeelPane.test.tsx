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

const { FeelPane } = await import('./FeelPane.tsx');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const { hapticsPref } = await import('../core/haptics.ts');

/**
 * Feel's page (docs/DESIGN.md §136): Animations' Speed and Movement, and Touch where there is a motor to switch,
 * each switch writing what the app reads.
 */

beforeEach(() => {
  phone = true;
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
});

const titles = (host: HTMLElement) => [...host.querySelectorAll('.setk__title')].map((title) => title.textContent);

describe('the Feel page', () => {
  it('holds Speed, Movement and, on a phone, Touch', () => {
    expect(titles(show(<FeelPane />))).toEqual(['Speed', 'Movement', 'Touch']);
  });

  it('has no Touch where there is no motor to switch', () => {
    phone = false;
    const host = show(<FeelPane />);
    expect(titles(host)).toEqual(['Speed', 'Movement']);
    expect(host.querySelector('[aria-label="Haptics"]')).toBeNull();
  });

  it('writes each switch to what the app reads', () => {
    const host = show(<FeelPane />);
    const wisp = preferences().wisp;
    act(() => host.querySelector<HTMLElement>('[aria-label="Ghostly typing"]')!.click());
    expect(preferences().wisp).toBe(!wisp);
    const haptics = hapticsPref();
    act(() => host.querySelector<HTMLElement>('[aria-label="Haptics"]')!.click());
    expect(hapticsPref()).toBe(!haptics);
  });
});
