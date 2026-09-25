import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { button, show } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
// The side key's rings watch their box; jsdom has no observer.
stubResizeObserver();

// In the app, where there is a side key to place, or in a browser, where there is none.
let native = true;
vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke: () => Promise.reject(new Error('no binary in a test')) }));

const { RecordingPane } = await import('./RecordingPane.tsx');
const { savedHeight, saveHeight } = await import('../capture/sideKey.ts');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');

/**
 * Recording's page: its switches write the preferences the recorder reads, and in the app the side key can be moved
 * from Ghost.md's guess to where the key really is, and put back.
 */

beforeEach(() => {
  native = true;
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
});

describe('the Recording page', () => {
  it('writes each switch to the preference the recorder reads', () => {
    const host = show(<RecordingPane />);
    const quiet = preferences().quietStop;
    act(() => host.querySelector<HTMLElement>('[aria-label="Stop when I go quiet"]')!.click());
    expect(preferences().quietStop).toBe(!quiet);
    const refine = preferences().refine;
    act(() => host.querySelector<HTMLElement>('[aria-label="Better words after recording"]')!.click());
    expect(preferences().refine).toBe(!refine);
  });

  it('offers Ghost.md’s guess back only once the side key has been moved, and forgets the move', () => {
    let host = show(<RecordingPane />);
    expect(host.textContent).toContain('Where the side key is');
    expect(host.textContent).not.toContain('Use Ghost.md’s guess');
    saveHeight(0.62);
    host = show(<RecordingPane />);
    // The slider stands where the key was moved to, as a percentage of the edge.
    const slider = host.querySelector<HTMLElement>('[aria-label="Side key height"]')!;
    expect(slider.getAttribute('aria-valuenow') ?? (slider as HTMLInputElement).value).toBe('62');
    act(() => button('Reset', host).click());
    expect(savedHeight()).toBeNull();
    expect(host.textContent).not.toContain('Use Ghost.md’s guess');
  });

  it('has no side key to place in a browser', () => {
    native = false;
    expect(show(<RecordingPane />).textContent).not.toContain('Where the side key is');
  });
});
