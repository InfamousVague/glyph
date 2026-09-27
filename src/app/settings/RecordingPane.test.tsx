import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { button, show } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
// The side key's rings watch their box; jsdom has no observer.
stubResizeObserver();

// On Android, where there is a side key to place, on the Mac, or in a browser, where there is none.
let native = true;
let android = true;
vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke: () => Promise.reject(new Error('no binary in a test')) }));
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isAndroid() {
    return android;
  },
}));

const { RecordingPane } = await import('./RecordingPane.tsx');
const { savedHeight, saveHeight } = await import('../capture/sideKey.ts');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');

/**
 * Recording's page: its switches write the preferences the recorder reads, and in the app the side key can be moved
 * from Ghost.md's guess to where the key really is, and put back.
 */

beforeEach(() => {
  native = true;
  android = true;
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

  it('has no side key to place in a browser, nor on the Mac, where the first section is not the key’s', () => {
    native = false;
    android = false;
    expect(show(<RecordingPane />).textContent).not.toContain('Where the side key is');
    native = true;
    const mac = show(<RecordingPane />);
    expect(mac.textContent).not.toContain('Where the side key is');
    expect(mac.textContent).not.toContain('The side key');
    expect(mac.textContent).toContain('While recording');
    expect(mac.textContent).toContain('Summaries');
  });

  it('offers the summaries three ways, meetings by default, and writes the choice the queue reads', () => {
    const host = show(<RecordingPane />);
    expect(preferences().summaries).toBe('meetings');
    expect(host.textContent).toContain('A long voice note is one over three minutes.');
    // Each choice is a label round a hidden radio input, as the kit draws a segmented control.
    const choose = (value: string) => act(() => host.querySelector<HTMLInputElement>(`input[type="radio"][value="${value}"]`)!.click());
    expect(host.textContent).toContain('Meetings and long voice notes');
    choose('long');
    expect(preferences().summaries).toBe('long');
    choose('off');
    expect(preferences().summaries).toBe('off');
  });
});
