import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { press, show } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// In the app or in a browser, as each test says.
let native = true;
vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke: () => Promise.reject(new Error('no binary in a test')) }));
const opened = vi.hoisted(() => [] as string[]);
vi.mock('../core/linkPreview.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/linkPreview.ts')>()),
  openLink: async (url: string) => {
    opened.push(url);
  },
}));

const { PrivacyCard } = await import('./PrivacyCard.tsx');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');

/**
 * The Privacy card on Account (docs/DESIGN.md §138): Local only, which was on Formatting, Link previews, which was on
 * Type, and the policy with its two lines, which were About's foot.
 */

beforeEach(() => {
  native = true;
  opened.length = 0;
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
});

const hint = (host: HTMLElement, label: string) =>
  [...host.querySelectorAll('.setk-row')].find((row) => row.querySelector('.setk-row__label')?.textContent === label)?.querySelector('.setk-row__hint')?.textContent;

describe('the Privacy card', () => {
  // Changed on purpose: it listed the Location card's three as well, five lines at 412, and they say it under their own rows.
  it('switches Local only, with one hint whatever the state, saying the sync stops too', () => {
    const host = show(<PrivacyCard />);
    const before = hint(host, 'Local only');
    expect(before).toBe('No sync, updates, downloads or link titles, and plugins that use the internet are held off. Ghost.md runs from what is on this device.');
    act(() => host.querySelector<HTMLElement>('[aria-label="Local only"]')!.click());
    expect(preferences().localOnly).toBe(true);
    expect(hint(host, 'Local only')).toBe(before);
  });

  it('says in a browser only what a browser does', () => {
    native = false;
    const host = show(<PrivacyCard />);
    expect(hint(host, 'Local only')).toBe('No sync, and plugins that use the internet are held off.');
    expect(host.querySelector('.setk__footer')?.textContent).toContain('Your notes stay in this browser.');
  });

  it('switches link previews, under Local only too, since the switch also says whether a link’s card is drawn at all', () => {
    const host = show(<PrivacyCard />);
    expect(preferences().linkPreviews).toBe(true);
    act(() => host.querySelector<HTMLElement>('[aria-label="Link previews"]')!.click());
    expect(preferences().linkPreviews).toBe(false);
    act(() => setPreferences({ localOnly: true }));
    const row = [...host.querySelectorAll('.setk-row')].find((r) => r.querySelector('.setk-row__label')?.textContent === 'Link previews');
    expect(row?.hasAttribute('data-disabled')).toBe(false);
  });

  it('opens the policy, and says what it comes to in its footer', () => {
    const host = show(<PrivacyCard />);
    press([...host.querySelectorAll('button')].find((b) => b.textContent?.includes('Privacy policy')));
    expect(opened).toEqual(['https://ghostmarkdown.com/privacy.html']);
    expect(host.querySelector('.setk__footer')?.textContent).toBe(
      'Your notes, recordings and pictures stay on this device, and your voice is turned into text here. Signed in, they sync encrypted on the device first, so only your own devices can read them. No ads, no analytics, no tracking.',
    );
  });
});

describe('looking up blanks online (docs/DESIGN.md §145)', () => {
  it('is on by default in the app, says what goes where, and switches off', () => {
    const host = show(<PrivacyCard />);
    expect(hint(host, 'Look up blanks online')).toBe(
      'When you press Fill on a blank that needs something live, like today’s weather or an exchange rate, this device asks Open-Meteo, the European Central Bank’s rates or Wikipedia. Only the question goes, and the model here writes the answer.',
    );
    const toggle = host.querySelector<HTMLInputElement>('[aria-label="Look up blanks online"]')!;
    expect(toggle.checked).toBe(true);
    act(() => toggle.click());
    expect(preferences().lookUpBlanks).toBe(false);
  });

  it('is off and held under Local only, which keeps such blanks waiting', () => {
    setPreferences({ localOnly: true });
    const host = show(<PrivacyCard />);
    expect(host.querySelector<HTMLInputElement>('[aria-label="Look up blanks online"]')?.checked).toBe(false);
    expect(host.textContent).toContain('Local only is on, so such blanks wait.');
  });

  it('is not in a browser, which runs no model', () => {
    native = false;
    expect(show(<PrivacyCard />).querySelector('[aria-label="Look up blanks online"]')).toBeNull();
  });
});

