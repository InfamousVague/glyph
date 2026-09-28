import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, waitUntil } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

/** Where the device is, as the pane asks it (core/location.ts): whether it may be asked, and what a fix does. */
const device = vi.hoisted(() => ({ can: { ok: true } as { ok: true } | { ok: false; why: string }, asked: 0, answer: 'fix' as 'fix' | 'refused' | 'blocked' | 'timeout', forgot: 0 }));
vi.mock('../core/location.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/location.ts')>();
  return {
    ...real,
    canLocate: () => device.can,
    locate: async () => {
      device.asked += 1;
      if (device.answer === 'fix') return { lat: 51.5074, lon: -0.1278, accuracy: 12, at: 0 };
      throw new real.LocateError(device.answer);
    },
    forgetRefusal: () => {
      device.forgot += 1;
    },
  };
});

const { LocationCard } = await import('./LocationCard.tsx');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');

/**
 * The Location card on Account (docs/DESIGN.md §138; it was the Location page): the three switches, all off under
 * Local only, and the ask that turning tagging on makes here so the prompt never comes over the recorder; a refusal
 * leaves the switch on and says why notes are not tagged.
 */

const flip = (host: HTMLElement, label: string) => act(() => host.querySelector<HTMLElement>(`[aria-label="${label}"]`)!.click());

beforeEach(() => {
  localStorage.clear();
  setPreferences({ ...DEFAULT_PREFERENCES });
  device.can = { ok: true };
  device.asked = 0;
  device.answer = 'fix';
  device.forgot = 0;
  delete window.GlyphHost;
});
afterEach(() => vi.clearAllMocks());

describe('the Location card', () => {
  it('has the three switches, on by default, and each writes its preference', () => {
    const host = show(<LocationCard />);
    expect(preferences()).toMatchObject({ mapTiles: true, placeNames: true, tagNewNotes: true });
    flip(host, 'Map on a tagged note');
    flip(host, 'Place names');
    expect(preferences()).toMatchObject({ mapTiles: false, placeNames: false, tagNewNotes: true });
    flip(host, 'Tag new notes with my location');
    expect(preferences().tagNewNotes).toBe(false);
    // Turning tagging off asks nothing.
    expect(device.asked).toBe(0);
  });

  it('greys all three under Local only, and says a tagged note still shows where it was written', () => {
    setPreferences({ localOnly: true });
    const host = show(<LocationCard />);
    expect(host.querySelectorAll('[data-disabled]')).toHaveLength(3);
    expect([...host.querySelectorAll('.setk-row__why')].map((el) => el.textContent)).toEqual(['Local only is on.', 'Local only is on.', 'Local only is on.']);
    // A named tag keeps its name under Local only; only the coordinates would be wrong to promise.
    expect(host.textContent).toContain('A tagged note shows where it was written and a pin while Local only is on, and no new location is taken.');
  });

  it('asks for a fix once when tagging is turned on, so the prompt happens here and not over the recorder', async () => {
    setPreferences({ tagNewNotes: false });
    const host = show(<LocationCard />);
    flip(host, 'Tag new notes with my location');
    expect(preferences().tagNewNotes).toBe(true);
    await waitUntil(() => expect(device.forgot).toBe(1));
    expect(device.asked).toBe(1);
    expect(host.textContent).not.toContain('not tagged');
  });

  it('leaves the switch on after a refusal, and says why notes are not tagged, with the way to settings where the phone is blocked', async () => {
    setPreferences({ tagNewNotes: false });
    device.answer = 'refused';
    const host = show(<LocationCard />);
    flip(host, 'Tag new notes with my location');
    await waitUntil(() => expect(host.textContent).toContain('Ghost.md wasn’t allowed to know where you are, so new notes are not tagged.'));
    expect(preferences().tagNewNotes).toBe(true);
    expect(host.querySelector('.setk-action')).toBeNull();
    // In a browser the way back is the browser's own settings for the site, not a phone's.
    expect(host.textContent).toContain('Allow location for this site in the browser’s settings and they will be.');
    // Blocked, on a phone that can open its own settings page.
    const opened = vi.fn(() => true);
    window.GlyphHost = { takeLaunch: () => '', isLocked: () => false, endCapture: () => undefined, openLocationSettings: opened };
    device.answer = 'blocked';
    flip(host, 'Tag new notes with my location');
    flip(host, 'Tag new notes with my location');
    await waitUntil(() => expect(host.textContent).toContain('Location is off for Ghost.md, so new notes are not tagged.'));
    act(() => host.querySelector<HTMLElement>('.setk-action')!.click());
    expect(opened).toHaveBeenCalledTimes(1);
  });

  it('says so when a new note’s own ask was refused, and forgets it once the switch is turned off', () => {
    localStorage.setItem('glyph-geotag-refused', JSON.stringify({ why: 'refused', at: Date.now() }));
    const host = show(<LocationCard />);
    expect(host.textContent).toContain('Ghost.md wasn’t allowed to know where you are, so new notes are not tagged.');
    expect(preferences().tagNewNotes).toBe(true);
    flip(host, 'Tag new notes with my location');
    expect(host.textContent).not.toContain('not tagged');
  });

  it('greys tagging where no fix can be asked for, and says why', () => {
    for (const [why, words] of [
      ['mac', 'This Mac can’t say where it is yet.'],
      ['none', 'This browser can’t say where you are.'],
      ['unavailable', 'Update Ghost.md to tag notes.'],
    ] as const) {
      device.can = { ok: false, why };
      const host = show(<LocationCard />);
      const rows = host.querySelectorAll('[data-disabled]');
      expect(rows).toHaveLength(1);
      expect(rows[0]?.textContent).toContain(words);
      host.remove();
    }
  });
});
