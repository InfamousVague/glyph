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
  it('are six buttons, each named by its template and described by its sentence, and a press chooses it', () => {
    const chosen: string[] = [];
    show(<TemplateCards at={AT} taken={new Set()} smallMap={false} onChoose={(template) => chosen.push(template.id)} />);
    expect(cards().map((one) => one.dataset.template)).toEqual(['day', 'meeting', 'checklist', 'book', 'map', 'reading']);
    expect(cards().every((one) => one.tagName === 'BUTTON')).toBe(true);
    expect(card('meeting').getAttribute('aria-label')).toBe('A meeting');
    expect(said('meeting')).toBe('Named for this minute, with who was there, notes and to-dos.');
    act(() => card('reading').click());
    expect(chosen).toEqual(['reading']);
  });

  it('keep the editor’s focus: a pointer or mouse press has its default taken', () => {
    show(<TemplateCards at={AT} taken={new Set()} smallMap={false} onChoose={() => undefined} />);
    for (const kind of ['pointerdown', 'mousedown']) {
      const press = new (kind === 'pointerdown' ? PointerEvent : MouseEvent)(kind, { bubbles: true, cancelable: true });
      card('day').dispatchEvent(press);
      expect([kind, press.defaultPrevented]).toEqual([kind, true]);
    }
  });

  it('draw the note’s top in a picture with nothing to press and nothing read out, and each map as a picture', async () => {
    show(<TemplateCards at={AT} taken={new Set()} smallMap={false} onChoose={() => undefined} />);
    for (const one of cards()) {
      const drawn = one.querySelector('[inert]')!;
      expect(drawn.getAttribute('aria-hidden')).toBe('true');
      expect(drawn.querySelector('button')).toBeNull();
    }
    // A map at the top draws its header; the rest draw no map where the note holds none.
    expect(card('map').querySelector('[data-size="header"]')).not.toBeNull();
    expect(card('day').querySelector('[data-size]')).toBeNull();
    await waitUntil(() => expect(card('day').querySelector('.cm-content')?.textContent).toContain('2026-09-28'));
    expect(card('checklist').querySelector('.cm-openHint')?.textContent).toBe('A name');
    unmount();
    // A note that holds a map's box: every card draws the small box it would get.
    show(<TemplateCards at={AT} taken={new Set()} smallMap onChoose={() => undefined} />);
    expect(card('day').querySelector('[data-size="card"]')).not.toBeNull();
    expect(card('map').querySelector('[data-size="header"]')).not.toBeNull();
  });

  it('say when today’s name is taken, and draw the heading A day will write', async () => {
    show(<TemplateCards at={AT} taken={new Set([titleKey('2026-09-28')])} smallMap={false} onChoose={() => undefined} />);
    expect(said('day')).toBe('Today has a note by this name. This makes a second.');
    await waitUntil(() => expect(card('day').querySelector('.cm-content')?.textContent).toContain('2026-09-28 (2)'));
  });

  it('dim A map at the top under Local only, as no button, and buzz at a press that makes nothing', () => {
    setPreferences({ localOnly: true });
    const chosen: string[] = [];
    show(<TemplateCards at={AT} taken={new Set()} smallMap={false} onChoose={(template) => chosen.push(template.id)} />);
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
    show(<TemplateCards at={AT} taken={new Set()} smallMap={false} onChoose={() => undefined} />);
    await waitUntil(() => expect(card('map').hasAttribute('data-dimmed')).toBe(true));
    expect(said('map')).toBe('Allow location for this site in the browser’s settings for a note to keep its place.');
  });

  it('leave it out where the device can never say where it is: the Mac, or a browser with no geolocation', () => {
    device.mac = true;
    show(<TemplateCards at={AT} taken={new Set()} smallMap={false} onChoose={() => undefined} />);
    expect(cards().map((one) => one.dataset.template)).toEqual(['day', 'meeting', 'checklist', 'book', 'reading']);
    unmount();
    device.mac = false;
    Reflect.deleteProperty(navigator, 'geolocation');
    show(<TemplateCards at={AT} taken={new Set()} smallMap={false} onChoose={() => undefined} />);
    expect(cards()).toHaveLength(5);
  });
});
