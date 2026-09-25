import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { changelogUrl, fetchReleases, keptReleases, readReleases, releaseWhen } from './changelog.ts';

const one = { version: '1.4.1-4', build: '20260916003621', at: '2026-09-16T00:36:21.000Z', notes: 'Smoke at the edges.' };
const two = { version: '1.4.1-3', build: '20260916002336', at: '2026-09-16T00:23:36.000Z' };

describe('the changelog', () => {
  beforeEach(() => localStorage.clear());

  it('reads releases newest first, and drops what is not one', () => {
    const releases = readReleases([two, one, { version: '', build: '20260916003621' }, { version: '1.0.0', build: 'nope' }, 'x', null]);
    expect(releases.map((r) => r.version)).toEqual(['1.4.1-4', '1.4.1-3']);
    expect(releases[0]?.notes).toBe('Smoke at the edges.');
    expect(releases[1]).not.toHaveProperty('notes');
  });

  it('keeps one entry per build', () => {
    expect(readReleases([one, { ...one, notes: 'again' }, two])).toHaveLength(2);
  });

  it('carries the APK version when one went out with it', () => {
    expect(readReleases([{ ...one, apk: '1.4.1' }])[0]?.apk).toBe('1.4.1');
    expect(readReleases([{ ...one, apk: '   ' }])[0]).not.toHaveProperty('apk');
  });

  it('is read from wherever the app takes its updates', () => {
    expect(changelogUrl(undefined, true)).toBe('https://attack.fm/glyph/changelog.json');
    expect(changelogUrl(['https://glyph.example/x/'], true)).toBe('https://glyph.example/x/changelog.json');
    expect(changelogUrl(['not a url', 'https://elsewhere.test/g'], true)).toBe('https://elsewhere.test/g/changelog.json');
  });

  it('is the file next door on the web, where the page and the changelog are served together', () => {
    expect(changelogUrl(undefined, false)).toBe('./changelog.json');
    expect(changelogUrl(['https://elsewhere.test/g'], false)).toBe('./changelog.json');
  });

  it('answers with nothing when nothing was ever read', () => {
    expect(keptReleases()).toEqual([]);
    localStorage.setItem('glyph-changelog', 'not json');
    expect(keptReleases()).toEqual([]);
  });

  it('says when a release went out, falling back to its build', () => {
    expect(releaseWhen(one)).toMatch(/\d/);
    expect(releaseWhen({ version: '1.0.0', build: '20260916003621', at: '' })).toMatch(/Sep/);
  });
});

describe('the changelog read from the update source', () => {
  beforeEach(() => localStorage.clear());
  afterEach(() => vi.unstubAllGlobals());

  /** A source that answers `body` with `status`, or cannot be reached at all. */
  function source(answer: { status?: number; body?: unknown } | 'offline'): string[] {
    const asked: string[] = [];
    vi.stubGlobal('fetch', async (url: string) => {
      asked.push(url);
      if (answer === 'offline') throw new TypeError('Failed to fetch');
      return new Response(JSON.stringify(answer.body ?? []), { status: answer.status ?? 200 });
    });
    return asked;
  }

  it('is fetched, read, and kept for a page opened with no signal', async () => {
    const asked = source({ body: [two, one] });
    expect((await fetchReleases(undefined)).map((r) => r.build)).toEqual([one.build, two.build]);
    expect(asked).toEqual(['./changelog.json']);
    source('offline');
    expect((await fetchReleases(undefined)).map((r) => r.build)).toEqual([one.build, two.build]);
  });

  it('answers what was kept when the source refuses, or answers nothing that is a release', async () => {
    source({ body: [one] });
    await fetchReleases(undefined);
    source({ status: 503 });
    expect(await fetchReleases(undefined)).toHaveLength(1);
    // An empty list is not kept over the one that was.
    source({ body: [] });
    expect(await fetchReleases(undefined)).toEqual([]);
    expect(keptReleases()).toHaveLength(1);
  });

  it('keeps the newest sixty', async () => {
    const many = Array.from({ length: 70 }, (_, i) => ({ version: `1.0.${i}`, build: String(20260901000000 + i), at: '' }));
    source({ body: many });
    expect(await fetchReleases(undefined)).toHaveLength(70);
    const kept = keptReleases();
    expect(kept).toHaveLength(60);
    expect(kept[0]?.version).toBe('1.0.69');
  });
});
