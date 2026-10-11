import { afterEach, describe, expect, it, vi } from 'vitest';
import { menuRoom, statusBar } from './menuRoom.ts';

/**
 * The room a menu has (editor/menuRoom.ts): from under the status bar to the keyboard's top, 8px in. The inset is set
 * inline on the root here: jsdom hands back a custom property set inline as it was set, and one from a stylesheet as
 * its raw `env(...)` text, which the browsers never do (both put the `env()` in).
 */

const root = document.documentElement;

afterEach(() => {
  root.style.removeProperty('--app-inset-top');
  vi.unstubAllGlobals();
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: 768 });
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: 1024 });
});

describe('the status bar', () => {
  it('reads the inset in px, and nothing where there is none', () => {
    root.style.setProperty('--app-inset-top', '32px');
    expect(statusBar()).toBe(32);
    root.style.removeProperty('--app-inset-top');
    expect(statusBar()).toBe(0);
  });

  it('takes an inset it cannot read for none', () => {
    root.style.setProperty('--app-inset-top', 'env(safe-area-inset-top, 0px)');
    expect(statusBar()).toBe(0);
  });
});

describe('the room', () => {
  it('starts 8px under the status bar, and 8px under the window’s top with none', () => {
    Object.defineProperty(window, 'innerHeight', { configurable: true, value: 915 });
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: 412 });
    root.style.setProperty('--app-inset-top', '32px');
    expect(menuRoom()).toEqual({ top: 40, bottom: 907, left: 8, right: 404 });
    root.style.removeProperty('--app-inset-top');
    expect(menuRoom().top).toBe(8);
  });

  it('ends 8px over the keyboard: the visual viewport’s foot', () => {
    vi.stubGlobal('visualViewport', { offsetTop: 0, height: 579 });
    expect(menuRoom().bottom).toBe(571);
  });

  it('starts under a visual viewport panned past the status bar', () => {
    root.style.setProperty('--app-inset-top', '40px');
    vi.stubGlobal('visualViewport', { offsetTop: 100, height: 400 });
    expect(menuRoom()).toMatchObject({ top: 108, bottom: 492 });
  });
});
