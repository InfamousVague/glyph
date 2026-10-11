import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Release } from '../core/changelog.ts';
import { button, rerender, show } from '../../test/render.tsx';

/**
 * What's new, once, after an update: shown only when this build is newer than the one that last ran here, with the
 * releases between the two, and the build remembered whether or not the sheet is read. The test build is
 * 20260101000000 (vitest.config.ts).
 */

const releases: Release[] = [
  { version: '1.9.0-2', build: '20260101000000', at: '2026-01-01T00:00:00Z', notes: 'The newest.' },
  { version: '1.9.0-1', build: '20251215000000', at: '2025-12-15T00:00:00Z', notes: 'The one before.' },
  { version: '1.8.9', build: '20251101000000', at: '2025-11-01T00:00:00Z', notes: 'Already seen.' },
];
const changelog = vi.hoisted(() => ({ fetchReleases: vi.fn(async (): Promise<Release[]> => []) }));
vi.mock('../core/changelog.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/changelog.ts')>()),
  fetchReleases: changelog.fetchReleases,
}));

const { WhatsNewSheet } = await import('./WhatsNewSheet.tsx');

const NOW = '20260101000000';
const seen = () => localStorage.getItem('glyph-seen-build');
const sheet = () => document.querySelector('[role="dialog"][aria-label="What\'s new"]');

beforeEach(() => {
  localStorage.clear();
  changelog.fetchReleases.mockReset().mockResolvedValue(releases);
  vi.useFakeTimers();
});
afterEach(() => vi.useRealTimers());

/** Past the pause the sheet waits after launch, and the fetch's answer. */
const later = () => act(async () => void vi.advanceTimersByTime(1500));

describe('what’s new', () => {
  it('shows nothing on a first launch, and remembers the build it was', async () => {
    show(<WhatsNewSheet sources={undefined} hold={false} />);
    await later();
    expect(sheet()).toBeNull();
    expect(seen()).toBe(NOW);
    expect(changelog.fetchReleases).not.toHaveBeenCalled();
  });

  it('after an update shows the releases since the last build that ran here, newest first, once', async () => {
    localStorage.setItem('glyph-seen-build', '20251201000000');
    show(<WhatsNewSheet sources={['https://example.test/changelog.json']} hold={false} />);
    expect(sheet()).toBeNull();
    await later();
    expect(changelog.fetchReleases).toHaveBeenCalledWith(['https://example.test/changelog.json'], expect.any(AbortSignal));
    expect(sheet()?.textContent).toContain('What\'s new in 1.9.0-2');
    expect(sheet()?.textContent).toContain('Ghost.md just updated, 2 releases at once.');
    expect(sheet()?.textContent).toContain('The one before.');
    expect(sheet()?.textContent).not.toContain('Already seen.');
    expect(seen()).toBe(NOW);
    act(() => button('Done').click());
    expect(sheet()).toBeNull();
  });

  it('waits while it is held back - the guide or a recording is up - and comes when it is let go', async () => {
    localStorage.setItem('glyph-seen-build', '20251201000000');
    show(<WhatsNewSheet sources={undefined} hold />);
    await later();
    expect(changelog.fetchReleases).not.toHaveBeenCalled();
    expect(seen()).toBe('20251201000000');
    rerender(<WhatsNewSheet sources={undefined} hold={false} />);
    await later();
    expect(sheet()).not.toBeNull();
  });

  it('starts again, showing nothing, from a build it cannot read or one newer than this', async () => {
    for (const odd of ['junk', '20270101000000']) {
      localStorage.setItem('glyph-seen-build', odd);
      show(<WhatsNewSheet sources={undefined} hold={false} />);
      await later();
      expect(sheet()).toBeNull();
      expect(seen()).toBe(NOW);
    }
    expect(changelog.fetchReleases).not.toHaveBeenCalled();
  });

  it('says nothing when the build has not changed', async () => {
    localStorage.setItem('glyph-seen-build', NOW);
    show(<WhatsNewSheet sources={undefined} hold={false} />);
    await later();
    expect(changelog.fetchReleases).not.toHaveBeenCalled();
    expect(sheet()).toBeNull();
  });
});
