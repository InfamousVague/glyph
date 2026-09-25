import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';

/**
 * The boot handshake with the OTA loader (index.html): with no loader the page mounts at once; with one, each copy of
 * main.tsx registers its mount under its own URL and mounts only when the loader has chosen it - never on its own
 * say, and never twice. And mounting does NOT claim the boot succeeded: that is App's first effect, after a real
 * commit (core/ota.ts `settleBoot`), so it is not asked here.
 */

// The app itself is its own tests' business: here it is a line that says it mounted.
vi.mock('./app/App.tsx', () => ({ App: () => <p data-app>mounted</p> }));
const shares = vi.hoisted(() => ({ followed: 0 }));
vi.mock('./app/share/share.ts', () => ({ followShares: () => void (shares.followed += 1) }));

// React checks this before it will let `act` flush without warning.
(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: HTMLDivElement;
beforeEach(() => {
  vi.resetModules();
  shares.followed = 0;
  root = document.createElement('div');
  root.id = 'root';
  // Left behind by a frontend the loader started and abandoned.
  root.innerHTML = '<p>stale</p>';
  document.body.appendChild(root);
});
afterEach(() => {
  delete window.__glyphBoot;
  root.remove();
});

/** Loads main.tsx afresh, as a page load does, and lets whatever it rendered commit. */
async function load(): Promise<void> {
  await act(async () => {
    await import('./main.tsx');
  });
}

describe('the page’s mount', () => {
  it('mounts at once where there is no loader, into an emptied root, and starts following shares', async () => {
    await load();
    expect(root.querySelector('[data-app]')).not.toBeNull();
    expect(root.textContent).toBe('mounted');
    expect(shares.followed).toBe(1);
  });

  it('with a loader still deciding, registers its mount and waits', async () => {
    const boot: GlyphBoot = { waiting: [], mounters: {}, build: null };
    window.__glyphBoot = boot;
    await load();
    expect(root.textContent).toBe('stale');
    const [self] = Object.keys(boot.mounters);
    expect(self).toBeDefined();
    expect(boot.waiting).toHaveLength(1);
    // Another copy chosen: this one stays out of it.
    boot.chosen = 'https://attack.fm/glyph/ota/other/main.js';
    act(() => boot.waiting.forEach((consider) => consider()));
    expect(root.textContent).toBe('stale');
    // This one chosen: it mounts, once, however many times it is asked.
    boot.chosen = self;
    act(() => boot.waiting.forEach((consider) => consider()));
    act(() => boot.mounters[self!]!());
    expect(root.querySelectorAll('[data-app]')).toHaveLength(1);
    expect(boot.mounted).toBeUndefined();
  });

  it('mounts at once when the loader had already chosen it, and not when it chose another', async () => {
    window.__glyphBoot = { waiting: [], mounters: {}, build: null, chosen: 'https://attack.fm/glyph/ota/other/main.js' };
    await load();
    expect(root.textContent).toBe('stale');
    const self = Object.keys(window.__glyphBoot.mounters)[0]!;
    delete window.__glyphBoot;
    vi.resetModules();
    window.__glyphBoot = { waiting: [], mounters: {}, build: null, chosen: self };
    await load();
    expect(root.textContent).toBe('mounted');
    expect(window.__glyphBoot.waiting).toHaveLength(0);
  });
});
