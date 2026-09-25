import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { onMarkDetails, type MarkDetails } from '../core/markDetails.ts';
import { detailsCache, type DetailsCacheOptions } from './detailsCache.ts';
import { createHost } from './host.ts';
import type { PluginManifest } from './types.ts';

/**
 * The cache behind Notion's and GitHub's pills (detailsCache.ts), with the service stood in for by a `read` whose
 * answers each test holds and lets go of: how many are read at once, when an answer is fresh enough not to read
 * again, when a failure is tried again, and what is kept across a reload and how much.
 */

const manifest: PluginManifest = {
  id: 'test',
  name: 'Test',
  description: '',
  version: '1.0.0',
  author: 'test',
  standard: false,
  permissions: [],
  storage: ['glyph-test-details'],
};
const host = createHost(manifest, () => Promise.reject(new Error('no native commands here')));

const details = (title: string, readAt = Date.now()): MarkDetails => ({ url: `https://x/${title}`, title, status: null, brief: [], fields: [], editedAt: null, readAt });

/** A read per call, each answered when the test says: `answer(i, …)` or `fail(i, …)`. */
function service() {
  const calls: { key: string; resolve: (d: MarkDetails) => void; reject: (e: Error) => void }[] = [];
  const read = vi.fn(
    (key: string) =>
      new Promise<MarkDetails>((resolve, reject) => {
        calls.push({ key, resolve, reject });
      }),
  );
  return { read, calls };
}

/** Lets the answered reads land, and the queue move on. */
const settle = async () => {
  for (let i = 0; i < 5; i += 1) await Promise.resolve();
};

function cache(over: Partial<DetailsCacheOptions> = {}) {
  const { read, calls } = service();
  return { cache: detailsCache({ host, storageKey: 'glyph-test-details', read, ...over }), read, calls };
}

beforeEach(() => {
  localStorage.clear();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(Date.parse('2026-09-25T12:00:00Z'));
});

afterEach(() => vi.useRealTimers());

describe('the details cache', () => {
  it('reads two at a time and queues the rest, in the order they were wanted', async () => {
    const { cache: c, calls } = cache();
    for (const key of ['a', 'b', 'c', 'd']) c.want(key, `https://x/${key}`);
    expect(calls.map((call) => call.key)).toEqual(['a', 'b']);
    expect(c.peek('c')).toEqual({ state: 'loading' });
    calls[0]!.resolve(details('a'));
    await settle();
    expect(calls.map((call) => call.key)).toEqual(['a', 'b', 'c']);
    expect(c.peek('a')).toEqual({ state: 'ready', details: details('a'), loading: false });
  });

  it('does not read again while an answer is fresh, and does once it is 45 seconds old or asked by hand', async () => {
    const { cache: c, calls, read } = cache();
    c.want('a', 'https://x/a');
    calls[0]!.resolve(details('a'));
    await settle();
    c.want('a', 'https://x/a');
    expect(read).toHaveBeenCalledOnce();
    // A Refresh by hand reads whatever is kept, and the pill keeps its answer while it does.
    c.want('a', 'https://x/a', true);
    expect(read).toHaveBeenCalledTimes(2);
    expect(c.peek('a')).toMatchObject({ state: 'ready', loading: true });
    calls[1]!.resolve(details('a'));
    await settle();
    vi.setSystemTime(Date.now() + 46_000);
    c.want('a', 'https://x/a');
    expect(read).toHaveBeenCalledTimes(3);
  });

  it('says what a failed read said, and tries again only once the failure is as old as a stale answer', async () => {
    const { cache: c, calls, read } = cache();
    c.want('a', 'https://x/a');
    calls[0]!.reject(new Error('The network is not back yet.'));
    await settle();
    expect(c.peek('a')).toEqual({ state: 'failed', message: 'The network is not back yet.' });
    c.want('a', 'https://x/a');
    expect(read).toHaveBeenCalledOnce();
    vi.setSystemTime(Date.now() + 46_000);
    c.want('a', 'https://x/a');
    expect(read).toHaveBeenCalledTimes(2);
  });

  it('keeps the answer it had over a read that fails', async () => {
    const { cache: c, calls } = cache();
    c.want('a', 'https://x/a');
    calls[0]!.resolve(details('a'));
    await settle();
    c.want('a', 'https://x/a', true);
    calls[1]!.reject(new Error('Rate limited.'));
    await settle();
    expect(c.peek('a')).toEqual({ state: 'ready', details: details('a'), loading: false });
  });

  it('keeps the newest answers across a reload, and leaves out what another build kept in another shape', async () => {
    const first = cache({ keep: 2 });
    first.cache.keep('old', details('old', Date.now() - 3000));
    first.cache.keep('mid', details('mid', Date.now() - 2000));
    first.cache.keep('new', details('new', Date.now() - 1000));
    const kept = JSON.parse(localStorage.getItem('glyph-test-details')!) as Record<string, MarkDetails>;
    expect(Object.keys(kept)).toEqual(['new', 'mid']);
    localStorage.setItem('glyph-test-details', JSON.stringify({ ...kept, odd: { title: 7 }, gone: null }));
    const second = cache();
    expect(second.cache.peek('mid')).toMatchObject({ state: 'ready', details: { title: 'mid' } });
    expect(second.cache.peek('odd')).toBeNull();
    expect(second.cache.peek('old')).toBeNull();
  });

  it('asks nothing before it is ready, and tells the pills every time something changes', async () => {
    let ready = false;
    const heard = vi.fn();
    const stop = onMarkDetails(heard);
    try {
      const { cache: c, calls } = cache({ ready: () => ready });
      c.want('a', 'https://x/a');
      expect(calls).toHaveLength(0);
      ready = true;
      c.want('a', 'https://x/a');
      calls[0]!.resolve(details('a'));
      await settle();
      expect(heard).toHaveBeenCalledOnce();
      c.forget();
      expect(heard).toHaveBeenCalledTimes(2);
      expect(c.peek('a')).toBeNull();
      expect(localStorage.getItem('glyph-test-details')).toBeNull();
    } finally {
      stop();
    }
  });
});
