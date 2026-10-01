import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, unmount, waitUntil } from '../../test/render.tsx';
import { titleKey } from '../core/titleKey.ts';

/**
 * The templates on a new note's blank page (TemplateCards.tsx): a card for each, a button named by it and described by
 * its sentence, with nothing to press inside what it draws; A map at the top dimmed with its reason where no note made
 * here keeps a place, and not there at all where the device can never say where it is; A day saying so when today's
 * name is taken. The device is core/platform.ts and a stood-in geolocation.
 */

await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
const device = vi.hoisted(() => ({ mac: false }));
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isMacApp() {
    return device.mac;
  },
}));
const haptics = vi.hoisted(() => [] as string[]);
vi.mock('../core/haptics.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/haptics.ts')>()),
  fireNativeHaptic: (kind: string) => void haptics.push(kind),
}));

const { TemplateCards } = await import('./TemplateCards.tsx');
const { setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const { rememberRefusal, forgetRefusal } = await import('../core/location.ts');

const AT = new Date(2026, 8, 28, 14, 5);
const cards = () => [...document.querySelectorAll<HTMLElement>('[data-template]')];
const card = (id: string) => document.querySelector<HTMLElement>(`[data-template="${id}"]`)!;
const said = (id: string) => document.getElementById(card(id).getAttribute('aria-describedby')!)?.textContent;

beforeEach(() => {
  device.mac = false;
  haptics.length = 0;
  Object.defineProperty(navigator, 'geolocation', { configurable: true, value: { getCurrentPosition: () => undefined } });
});

afterEach(() => {
  unmount();
  setPreferences({ localOnly: DEFAULT_PREFERENCES.localOnly });
  forgetRefusal();
  Reflect.deleteProperty(navigator, 'geolocation');
  Reflect.deleteProperty(navigator, 'permissions');
});

describe('the template cards', () => {
  it('are eight buttons, each named by its template and described by its sentence, and a press chooses it', () => {
    const chosen: string[] = [];
    show(<TemplateCards at={AT} taken={new Set()} onChoose={(template) => chosen.push(template.id)} />);
    expect(cards().map((one) => one.dataset.template)).toEqual(['day', 'meeting', 'checklist', 'book', 'map', 'reading', 'bug', 'feature']);
    expect(cards().every((one) => one.tagName === 'BUTTON')).toBe(true);
    expect(card('meeting').getAttribute('aria-label')).toBe('A meeting');
    expect(said('meeting')).toBe('Named for this minute, with who was there, notes and to-dos.');
    act(() => card('reading').click());
    expect(chosen).toEqual(['reading']);
  });

  it('keep the editor’s focus: a pointer or mouse press has its default taken', () => {
    show(<TemplateCards at={AT} taken={new Set()} onChoose={() => undefined} />);
    for (const kind of ['pointerdown', 'mousedown']) {
      const press = new (kind === 'pointerdown' ? PointerEvent : MouseEvent)(kind, { bubbles: true, cancelable: true });
      card('day').dispatchEvent(press);
      expect([kind, press.defaultPrevented]).toEqual([kind, true]);
    }
  });

  it('draw the note’s top in a picture with nothing to press and nothing read out, and each map as a picture', async () => {
    show(<TemplateCards at={AT} taken={new Set()} onChoose={() => undefined} />);
    for (const one of cards()) {
      const drawn = one.querySelector('[inert]')!;
      expect(drawn.getAttribute('aria-hidden')).toBe('true');
      expect(drawn.querySelector('button')).toBeNull();
    }
    // A map at the top draws its header, and it is the only card with a map.
    expect(card('map').querySelector('[data-size="header"]')).not.toBeNull();
    expect(cards().filter((one) => one.querySelector('[data-size]')).map((one) => one.dataset.template)).toEqual(['map']);
    await waitUntil(() => expect(card('day').querySelector('.cm-content')?.textContent).toContain('2026-09-28'));
    expect(card('checklist').querySelector('.cm-openHint')?.textContent).toBe('A name');
  });

  it('say when today’s name is taken, and draw the heading A day will write', async () => {
    show(<TemplateCards at={AT} taken={new Set([titleKey('2026-09-28')])} onChoose={() => undefined} />);
    expect(said('day')).toBe('Today has a note by this name. This makes a second.');
    await waitUntil(() => expect(card('day').querySelector('.cm-content')?.textContent).toContain('2026-09-28 (2)'));
    unmount();
    // Only A day says so: a second meeting in the same minute is still named for it, and says what it is.
    show(<TemplateCards at={AT} taken={new Set([titleKey('Meeting 2026-09-28 14.05')])} onChoose={() => undefined} />);
    expect(said('meeting')).toBe('Named for this minute, with who was there, notes and to-dos.');
    expect(said('day')).toBe('Named for today, with a to-do to start.');
    await waitUntil(() => expect(card('meeting').querySelector('.cm-content')?.textContent).toContain('14.05 (2)'));
  });

  it('dim A map at the top under Local only, as no button, and buzz at a press that makes nothing', () => {
    setPreferences({ localOnly: true });
    const chosen: string[] = [];
    show(<TemplateCards at={AT} taken={new Set()} onChoose={(template) => chosen.push(template.id)} />);
    expect(card('map').tagName).toBe('DIV');
    expect(card('map').hasAttribute('data-dimmed')).toBe(true);
    expect(said('map')).toBe('Local only is on, so a note made here keeps no place.');
    act(() => card('map').click());
    expect(chosen).toEqual([]);
    expect(haptics).toEqual(['warning']);
  });

  it('dim it with where to allow location after a refusal that still stands', async () => {
    rememberRefusal('refused');
    Object.defineProperty(navigator, 'permissions', { configurable: true, value: { query: async () => ({ state: 'denied' }) } });
    show(<TemplateCards at={AT} taken={new Set()} onChoose={() => undefined} />);
    await waitUntil(() => expect(card('map').hasAttribute('data-dimmed')).toBe(true));
    expect(said('map')).toBe('Allow location for this site in the browser’s settings for a note to keep its place.');
  });

  it('are your own templates once you have them, in their order, and end with the way to them', async () => {
    const { templateOf, newTemplatePageBody, templatePageBody } = await import('./ownTemplates.ts');
    const { BUILT_INS } = await import('./noteTemplates.ts');
    const { makeNote } = await import('../../test/notes.ts');
    const walk = templateOf(makeNote('walk', newTemplatePageBody('A walk')));
    const day = templateOf(makeNote('d', templatePageBody(BUILT_INS[0]!)));
    const yours = vi.fn();
    const chosen: string[] = [];
    show(<TemplateCards at={AT} taken={new Set([titleKey('2026-09-28')])} onChoose={(template) => chosen.push(template.id)} templates={[walk, day]} onYours={yours} />);
    expect(cards().map((one) => one.dataset.template)).toEqual(['walk', 'd', 'yours']);
    expect(said('walk')).toBe('One of your own.');
    // Still A day word for word: its rules, a taken name included.
    expect(said('d')).toBe('Today has a note by this name. This makes a second.');
    expect(card('yours').textContent).toBe('Your templatesChange these or write your own. They are notes in a notebook.');
    act(() => card('walk').click());
    act(() => card('yours').click());
    expect(chosen).toEqual(['walk']);
    expect(yours).toHaveBeenCalledTimes(1);
  });

  it('leave it out where the device can never say where it is: the Mac, or a browser with no geolocation', () => {
    device.mac = true;
    show(<TemplateCards at={AT} taken={new Set()} onChoose={() => undefined} />);
    expect(cards().map((one) => one.dataset.template)).toEqual(['day', 'meeting', 'checklist', 'book', 'reading', 'bug', 'feature']);
    unmount();
    device.mac = false;
    Reflect.deleteProperty(navigator, 'geolocation');
    show(<TemplateCards at={AT} taken={new Set()} onChoose={() => undefined} />);
    expect(cards()).toHaveLength(7);
  });
});
