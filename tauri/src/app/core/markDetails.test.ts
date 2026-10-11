import { describe, expect, it, vi } from 'vitest';
import {
  agoText,
  hasMarkDetails,
  markActions,
  markDetailsChanged,
  markNameFor,
  onMarkDetails,
  openMarked,
  peekMarkDetails,
  provideMarkDetails,
  wantMarkDetails,
  type MarkDetailsProvider,
  type MarkEntry,
} from './markDetails.ts';

/*
 * What an item's mark links to, read back (markDetails.ts): the editor asks by the mark's name and address, and the
 * plugin that owns the name answers through the provider it registered. Nothing here knows a plugin, so a test
 * registers its own.
 */

const LOADING: MarkEntry = { state: 'loading' };

/** A provider for links under `https://tasks.test/`, and what it was asked. */
function provider(): MarkDetailsProvider & { wanted: [string, boolean | undefined][]; opened: string[] } {
  const wanted: [string, boolean | undefined][] = [];
  const opened: string[] = [];
  return {
    wanted,
    opened,
    peek: (url) => (url.includes('known') ? LOADING : null),
    want: (url, fresh) => wanted.push([url, fresh]),
    open: async (url) => {
      opened.push(url);
    },
    reads: (url) => url.startsWith('https://tasks.test/'),
    actions: (url, words) => [{ id: 'done', label: `Mark ${words} done`, icon: 'done', busyLabel: 'Marking done…', run: async () => url }],
  };
}

describe('a mark’s details', () => {
  it('are asked of the provider registered for the mark’s name, whatever its case', async () => {
    const tasks = provider();
    provideMarkDetails('Tasks', () => tasks);
    expect(hasMarkDetails('tasks')).toBe(true);
    expect(peekMarkDetails('TASKS', 'https://tasks.test/known')).toBe(LOADING);
    expect(peekMarkDetails('tasks', 'https://tasks.test/other')).toBeNull();
    wantMarkDetails('tasks', 'https://tasks.test/known');
    wantMarkDetails('tasks', 'https://tasks.test/known', true);
    expect(tasks.wanted).toEqual([
      ['https://tasks.test/known', false],
      ['https://tasks.test/known', true],
    ]);
    await openMarked('tasks', 'https://tasks.test/known');
    expect(tasks.opened).toEqual(['https://tasks.test/known']);
    expect(markActions('tasks', 'https://tasks.test/known', 'Buy milk').map((action) => action.label)).toEqual(['Mark Buy milk done']);
  });

  it('are nothing for a mark no plugin answers, or one whose plugin is off', async () => {
    provideMarkDetails('switched-off', () => null);
    for (const name of ['nobody', 'switched-off']) {
      expect(hasMarkDetails(name)).toBe(false);
      expect(peekMarkDetails(name, 'https://tasks.test/known')).toBeNull();
      expect(markActions(name, 'https://tasks.test/known', 'x')).toEqual([]);
      expect(() => wantMarkDetails(name, 'https://tasks.test/known')).not.toThrow();
      await expect(openMarked(name, 'https://tasks.test/known')).resolves.toBeUndefined();
    }
  });

  it('are found for an ordinary link a provider reads, written the old way or pasted into a sentence', () => {
    provideMarkDetails('reader', () => ({ ...provider(), reads: (url: string) => url.startsWith('https://reader.test/') }));
    provideMarkDetails('silent', () => ({ ...provider(), reads: undefined }));
    expect(markNameFor('https://reader.test/abc')).toBe('reader');
    expect(markNameFor('https://elsewhere.test/abc')).toBeNull();
  });

  it('tell every pill and card to read again when a provider has something new, until they stop listening', () => {
    const heard = vi.fn();
    const stop = onMarkDetails(heard);
    markDetailsChanged();
    markDetailsChanged();
    expect(heard).toHaveBeenCalledTimes(2);
    stop();
    markDetailsChanged();
    expect(heard).toHaveBeenCalledTimes(2);
  });
});

describe('how long ago', () => {
  it('is said as a person says it', () => {
    const now = 10 * 24 * 60 * 60_000;
    expect(agoText(now - 30_000, now)).toBe('just now');
    expect(agoText(now + 60_000, now)).toBe('just now');
    expect(agoText(now - 3 * 60_000, now)).toBe('3 min ago');
    expect(agoText(now - 5 * 60 * 60_000, now)).toBe('5 hr ago');
    expect(agoText(now - 24 * 60 * 60_000, now)).toBe('yesterday');
    expect(agoText(now - 3 * 24 * 60 * 60_000, now)).toBe('3 days ago');
  });
});
