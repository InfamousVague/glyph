import { afterEach, describe, expect, it } from 'vitest';
import { press, show } from '../../../test/render.tsx';
import { preferences, reloadPreferences } from '../../core/preferences.ts';
import { Theme } from './Theme.tsx';

/** The theme page's rows, by the words on them. */
const rows = (el: HTMLElement) => [...el.querySelectorAll<HTMLButtonElement>('[role="radiogroup"] [role="radio"]')];
const row = (el: HTMLElement, label: string) => rows(el).find((b) => b.textContent?.startsWith(label));
const checked = (el: HTMLElement) => rows(el).filter((b) => b.getAttribute('aria-checked') === 'true').map((b) => b.textContent);

afterEach(() => {
  localStorage.clear();
  reloadPreferences();
  document.documentElement.removeAttribute('data-theme');
});

describe('the guide’s theme page', () => {
  it('offers Dark, Light and the phone’s own, each saying what it looks like', () => {
    const el = show(<Theme />);
    expect(rows(el).map((b) => b.textContent)).toEqual([
      'AaDarkLight words on black. Easier on the eyes at night.',
      'AaLightDark words on white, like paper.',
      'AaMatch the phoneFollows your phone’s dark mode.',
    ]);
  });

  it('applies a row the moment it is tapped, and marks it as the one chosen', () => {
    const el = show(<Theme />);
    expect(checked(el)).toEqual(['AaDarkLight words on black. Easier on the eyes at night.']);
    press(row(el, 'AaLight'));
    expect(preferences().theme).toBe('light');
    expect(document.documentElement.getAttribute('data-theme')).toBe('light');
    expect(checked(el)).toEqual(['AaLightDark words on white, like paper.']);
    expect(row(el, 'AaLight')!.className).toContain('app-inverse');
    expect(row(el, 'AaDark')!.className).not.toContain('app-inverse');
    // Another tap is another choice, kept at once: there is nothing to confirm and nothing puts the last one back.
    press(row(el, 'AaDark'));
    expect(preferences().theme).toBe('dark');
    expect(checked(el)).toEqual(['AaDarkLight words on black. Easier on the eyes at night.']);
    // And it is the preference from now on, read back as the app starts.
    press(row(el, 'AaMatch the phone'));
    reloadPreferences();
    expect(preferences().theme).toBe('system');
  });
});
