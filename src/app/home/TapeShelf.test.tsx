import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Note } from '../core/store.ts';
import { makeNote } from '../../test/notes.ts';
import { button, show, unmount } from '../../test/render.tsx';

/**
 * The shelf of tapes (docs/DESIGN.md §127 section 1): a cassette a note, its words under it, and the caption in its
 * order (home/tapeCaption.ts) - the first true thing wins. The queues the caption reads are stood in for here, since
 * none of them can run in a test, and the sets are the same objects the shelf reads, so a test fills one and draws.
 */

const sources = vi.hoisted(() => ({
  recording: null as string | null,
  refining: new Set<string>(),
  pending: new Set<string>(),
  native: new Set<string>(),
  failed: new Set<string>(),
  needsModel: new Set<string>(),
  lines: new Map<string, string>(),
  retried: [] as string[],
}));
vi.mock('./useMeetingLive.ts', () => ({ useMeetingLive: () => sources.recording }));
vi.mock('../capture/refine.ts', () => ({ useRefining: () => ({ pending: sources.refining, download: null }) }));
vi.mock('../ai/summaries.ts', () => ({
  useSummaries: () => ({ pending: sources.pending, native: sources.native, failed: sources.failed, needsModel: sources.needsModel }),
  retrySummary: (id: string) => sources.retried.push(id),
}));
vi.mock('../ai/summaryText.ts', () => ({ summaryLine: (body: string) => sources.lines.get(body) ?? null }));
const { TapeShelf } = await import('./TapeShelf.tsx');
const { captionOf } = await import('./tapeCaption.ts');

afterEach(() => {
  unmount();
  sources.recording = null;
  for (const set of [sources.refining, sources.pending, sources.native, sources.failed, sources.needsModel]) set.clear();
  sources.lines.clear();
  sources.retried.length = 0;
});

const tape = (id: string, recordingMs: number, over: Partial<Note> = {}) =>
  makeNote(id, `# ${id}`, { source: 'capture', recordingMs, createdAt: Date.UTC(2026, 8, 26, 12), updatedAt: Date.UTC(2026, 8, 26, 12), ...over });
const shelf = (notes: Note[], over: { more?: number; gists?: Record<string, string>; onOpen?: (id: string) => void; onMore?: () => void; onGetModel?: () => void } = {}) =>
  show(<TapeShelf notes={notes} more={over.more ?? 0} gists={over.gists ?? {}} onOpen={over.onOpen ?? (() => undefined)} onMore={over.onMore ?? (() => undefined)} onGetModel={over.onGetModel ?? (() => undefined)} />);
const captions = (host: HTMLElement) => [...host.querySelectorAll('li > p')].map((p) => p.textContent);
const cassettes = (host: HTMLElement) => [...host.querySelectorAll<HTMLButtonElement>('li > button')];

describe('the shelf', () => {
  it('draws a bare cassette a tape, its title, counter and date under it, and opens the note from it', () => {
    const onOpen = vi.fn();
    const host = shelf([tape('Trip', 760_000), tape('blank', 40_000, { body: '' })], { onOpen });
    const [trip, blank] = cassettes(host);
    // The words are under the cassette in real type, not printed on its label.
    expect([...trip!.querySelectorAll('svg text')].map((t) => t.textContent)).toEqual(['A']);
    expect(trip!.querySelector('[class*=title]')?.textContent).toBe('Trip');
    expect(trip!.querySelector('[class*=meta]')?.textContent).toMatch(/^12:40 · /);
    expect(trip!.getAttribute('aria-label')).toMatch(/^Trip, 12:40, /);
    expect(trip!.getAttribute('aria-label')).not.toContain('summarized');
    expect(blank!.querySelector('[class*=title]')?.textContent).toBe('Untitled');
    act(() => trip!.click());
    expect(onOpen).toHaveBeenCalledWith('Trip');
    // Each takes its beat from its place in the row, as the cards do.
    expect([...host.querySelectorAll('li')].map((li) => li.style.getPropertyValue('--i'))).toEqual(['0', '1']);
  });

  it('draws every cassette against the longest tape on the shelf, at least five minutes', () => {
    const takeup = (host: HTMLElement) => [...host.querySelectorAll('li > button')].map((b) => Number(b.querySelectorAll('circle')[1]!.getAttribute('r')));
    // Alone, a three-minute note is over half wound on the five-minute tape.
    const [alone] = takeup(shelf([tape('short', 180_000)]));
    unmount();
    // Beside an hour, it is a thin ring and the hour is a full reel.
    const [beside, hour] = takeup(shelf([tape('short', 180_000), tape('long', 3_600_000)]));
    expect(beside).toBeLessThan(alone!);
    expect(hour).toBeGreaterThan(beside!);
  });

  it('says how many more there are at the row’s end, and that word opens All notes', () => {
    const onMore = vi.fn();
    const host = shelf([tape('a', 1000)], { more: 3, onMore });
    act(() => button('and 3 more in All notes', host).click());
    expect(onMore).toHaveBeenCalledTimes(1);
    unmount();
    expect(shelf([tape('a', 1000)]).textContent).not.toContain('more in All notes');
  });

  it('says the note is summarized to a screen reader once it has a summary', () => {
    const note = tape('Planning', 900_000, { body: '# Planning\n## Summary\nWhat the call settled.' });
    sources.lines.set(note.body, 'What the call settled.');
    const host = shelf([note]);
    expect(cassettes(host)[0]!.getAttribute('aria-label')).toMatch(/, summarized$/);
    expect(captions(host)).toEqual(['What the call settled.']);
  });
});

describe('the caption', () => {
  const none = { pending: new Set<string>(), native: new Set<string>(), failed: new Set<string>(), needsModel: new Set<string>() };
  const quiet = { recording: null, refining: new Set<string>(), summaries: none, phone: false };
  const note = tape('n', 60_000);
  const long = tape('n', 1_200_000);
  const set = (...ids: string[]) => new Set(ids);

  it('is the first true thing in its order: recording, listening again, writing up, summarizing, needs a model, didn’t come, the summary, the gist', () => {
    const everything = { recording: 'n', refining: set('n'), summaries: { pending: set('n'), native: set('n'), failed: set('n'), needsModel: set('n') }, phone: false };
    sources.lines.set(note.body, 'The first line.');
    expect(captionOf(note, everything, 'a gist')).toEqual({ kind: 'recording' });
    expect(captionOf(note, { ...everything, recording: null }, 'a gist')).toEqual({ kind: 'working', word: 'Listening again', keepOpen: false });
    expect(captionOf(note, { ...everything, recording: null, refining: set() }, 'a gist')).toEqual({ kind: 'working', word: 'Writing up', keepOpen: false });
    const noNative = { ...everything.summaries, native: set() };
    expect(captionOf(note, { ...quiet, summaries: noNative }, 'a gist')).toEqual({ kind: 'working', word: 'Summarizing', keepOpen: false });
    expect(captionOf(note, { ...quiet, summaries: { ...noNative, pending: set() } }, 'a gist')).toEqual({ kind: 'needsModel' });
    expect(captionOf(note, { ...quiet, summaries: { ...noNative, pending: set(), needsModel: set() } }, 'a gist')).toEqual({ kind: 'failed' });
    expect(captionOf(note, quiet, 'a gist')).toEqual({ kind: 'line', text: 'The first line.' });
    sources.lines.clear();
    expect(captionOf(note, quiet, 'a gist')).toEqual({ kind: 'line', text: 'a gist' });
    expect(captionOf(note, quiet, undefined)).toBeNull();
  });

  it('asks for the app to stay open on a phone while the page works on a tape over ten minutes, and not for the service’s write-up', () => {
    const phone = { ...quiet, phone: true };
    expect(captionOf(long, { ...phone, refining: set('n') }, undefined)).toEqual({ kind: 'working', word: 'Listening again', keepOpen: true });
    expect(captionOf(long, { ...phone, summaries: { ...none, pending: set('n') } }, undefined)).toEqual({ kind: 'working', word: 'Summarizing', keepOpen: true });
    // Under ten minutes, or on a Mac, or while the service is writing it up: no ask.
    expect(captionOf(note, { ...phone, refining: set('n') }, undefined)).toEqual({ kind: 'working', word: 'Listening again', keepOpen: false });
    expect(captionOf(long, { ...quiet, refining: set('n') }, undefined)).toEqual({ kind: 'working', word: 'Listening again', keepOpen: false });
    expect(captionOf(long, { ...phone, refining: set('n'), summaries: { ...none, native: set('n') } }, undefined)).toEqual({ kind: 'working', word: 'Listening again', keepOpen: false });
  });

  it('is drawn with the spinner while something is on its way, and the reels turn only while a meeting is recorded', () => {
    sources.refining.add('a');
    sources.pending.add('b');
    sources.recording = 'c';
    const host = shelf([tape('a', 1000), tape('b', 1000), tape('c', 1000)]);
    expect(captions(host)).toEqual(['Listening again', 'Summarizing', 'Recording']);
    expect([...host.querySelectorAll('li')].map((li) => li.querySelector('[class*=working]') !== null)).toEqual([true, true, false]);
  });

  it('offers Try again after the summary did not come, which puts the job back in the queue', () => {
    sources.failed.add('a');
    const host = shelf([tape('a', 1000)]);
    expect(captions(host)).toEqual(['The summary didn’t comeTry again']);
    act(() => button('Try again', host).click());
    expect(sources.retried).toEqual(['a']);
  });

  it('offers Get a model while the job waits for one, which opens Settings', () => {
    sources.needsModel.add('a');
    const onGetModel = vi.fn();
    const host = shelf([tape('a', 1000)], { onGetModel });
    expect(captions(host)).toEqual(['Needs a modelGet a model']);
    act(() => button('Get a model', host).click());
    expect(onGetModel).toHaveBeenCalledTimes(1);
  });

  it('is the gist when there is nothing else to say, and an empty line when there is not even that', () => {
    const host = shelf([tape('a', 1000), tape('b', 1000)], { gists: { a: 'Packing for the trip' } });
    expect(captions(host)).toEqual(['Packing for the trip', '']);
  });
});
