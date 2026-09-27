import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { packRadii } from '../capture/tape.ts';
import type { Note } from '../core/store.ts';
import { makeNote } from '../../test/notes.ts';
import { button, show, unmount } from '../../test/render.tsx';

/**
 * The shelf of tapes (docs/DESIGN.md §127 section 1): a cassette a note, its words under it, and the caption in its
 * order (home/tapeCaption.ts) - the first true thing wins. The queues the caption reads are stood in for here, since
 * none of them can run in a test, and the sets are the same objects the shelf reads, so a test fills one and draws.
 * The shelf is drawn as on a phone, where a long tape's caption asks for the app to be kept open.
 */

const sources = vi.hoisted(() => ({
  recording: null as string | null,
  refining: new Set<string>(),
  pending: new Set<string>(),
  native: new Set<string>(),
  waiting: new Set<string>(),
  failed: new Set<string>(),
  needsModel: new Set<string>(),
  lines: new Map<string, string>(),
  retried: [] as string[],
  writtenUp: [] as string[],
}));
vi.mock('./useMeetingLive.ts', () => ({ useMeetingLive: () => sources.recording }));
vi.mock('../capture/refine.ts', () => ({ useRefining: () => ({ pending: sources.refining, download: null }) }));
vi.mock('../ai/summaries.ts', () => ({
  useSummaries: () => ({ pending: sources.pending, native: sources.native, waiting: sources.waiting, failed: sources.failed, needsModel: sources.needsModel }),
  retrySummary: (id: string) => sources.retried.push(id),
  writeUpNow: (id: string) => sources.writtenUp.push(id),
}));
vi.mock('../ai/summaryText.ts', () => ({ summaryLine: (body: string) => sources.lines.get(body) ?? null }));
vi.mock('../core/platform.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/platform.ts')>()), isMobile: true }));
const { TapeShelf } = await import('./TapeShelf.tsx');
const { canOfferSummary, captionOf } = await import('./tapeCaption.ts');

afterEach(() => {
  unmount();
  vi.restoreAllMocks();
  sources.recording = null;
  for (const set of [sources.refining, sources.pending, sources.native, sources.waiting, sources.failed, sources.needsModel]) set.clear();
  sources.lines.clear();
  sources.retried.length = 0;
  sources.writtenUp.length = 0;
});

const tape = (id: string, recordingMs: number, over: Partial<Note> = {}) =>
  makeNote(id, `# ${id}`, { source: 'capture', recordingMs, createdAt: Date.UTC(2026, 8, 26, 12), updatedAt: Date.UTC(2026, 8, 26, 12), ...over });
const shelf = (notes: Note[], over: { gists?: Record<string, string>; onOpen?: (id: string) => void; onGetModel?: () => void; onSummarize?: (note: Note) => void; canSummarize?: boolean } = {}) =>
  show(
    <TapeShelf
      notes={notes}
      gists={over.gists ?? {}}
      onOpen={over.onOpen ?? (() => undefined)}
      onGetModel={over.onGetModel ?? (() => undefined)}
      onSummarize={over.onSummarize ?? (() => undefined)}
      canSummarize={over.canSummarize ?? false}
    />,
  );
const captions = (host: HTMLElement) => [...host.querySelectorAll('li > p')].map((p) => p.textContent);
const cassettes = (host: HTMLElement) => [...host.querySelectorAll<HTMLButtonElement>('li > button')];
/** The frames, run by hand on a clock of the test's own, which the cassettes read as well (as tapes/tapes.test.tsx runs them). */
const frames = () => {
  const queued: FrameRequestCallback[] = [];
  let clock = performance.now();
  vi.spyOn(performance, 'now').mockImplementation(() => clock);
  vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => queued.push(cb));
  vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => undefined);
  return (count: number) => {
    for (let i = 0; i < count; i += 1) act(() => queued.shift()?.((clock += 16)));
  };
};
/** Each cassette's reels' transforms: null while a reel has never turned. */
const reels = (host: HTMLElement) => cassettes(host).map((b) => [...b.querySelectorAll('svg > g:not([mask])')].map((g) => g.getAttribute('transform')));

describe('the shelf', () => {
  it('draws a bare cassette a tape as a card, its title under it and the counter and date in its foot, and opens the note from it', () => {
    const onOpen = vi.fn();
    const host = shelf([tape('Trip', 760_000), tape('blank', 40_000, { body: '' })], { onOpen });
    const [trip, blank] = cassettes(host);
    // The words are under the cassette in real type, not printed on its label.
    expect([...trip!.querySelectorAll('svg text')].map((t) => t.textContent)).toEqual(['A']);
    expect(trip!.querySelector('[class*=title]')?.textContent).toBe('Trip');
    // The counter, then the day and the month in the device's own order, in the card's foot, outside the button.
    expect(host.querySelector('li [class*=foot]')?.textContent).toMatch(/^12:40 · (\d{1,2} [A-Z][a-z]{2}|[A-Z][a-z]{2} \d{1,2})$/);
    expect(trip!.querySelector('[class*=foot]')).toBeNull();
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
    // Alone, a three-minute note is over half wound on the five-minute tape: the floor, not its own three minutes.
    const [alone] = takeup(shelf([tape('short', 180_000)]));
    expect(alone).toBe(packRadii(180_000).takeup);
    unmount();
    // Beside an hour, it is a thin ring and the hour is a full reel.
    const [beside, hour] = takeup(shelf([tape('short', 180_000), tape('long', 3_600_000)]));
    expect(beside).toBeLessThan(alone!);
    expect(hour).toBeGreaterThan(beside!);
  });

  it('offers Summarize under a tape of three minutes or more with no summary, where a summariser can run, and asks for that note', () => {
    const onSummarize = vi.fn();
    const long = tape('long', 200_000);
    const host = shelf([long, tape('short', 40_000)], { onSummarize, canSummarize: true });
    expect([...host.querySelectorAll('li')].map((li) => li.querySelector('[class*=offer]')?.textContent ?? null)).toEqual(['Summarize', null]);
    act(() => button('Summarize', host).click());
    expect(onSummarize).toHaveBeenCalledWith(long);
    unmount();
    // Off Tauri the queue is a no-op and the page shows what synced: no offer.
    expect(shelf([tape('long', 200_000)]).querySelector('[class*=offer]')).toBeNull();
  });

  it('offers no Summarize once the tape has a summary, or while anything is happening to it', () => {
    const note = tape('n', 200_000, { body: '# n\n## Summary\nDone.' });
    sources.lines.set(note.body, 'Done.');
    expect(shelf([note], { canSummarize: true }).querySelector('[class*=offer]')).toBeNull();
    unmount();
    for (const set of [sources.refining, sources.pending, sources.native, sources.waiting, sources.failed, sources.needsModel]) {
      set.add('n');
      expect(shelf([tape('n', 200_000)], { canSummarize: true }).querySelector('[class*=offer]')).toBeNull();
      unmount();
      set.clear();
    }
    sources.recording = 'n';
    expect(shelf([tape('n', 200_000)], { canSummarize: true }).querySelector('[class*=offer]')).toBeNull();
  });

  it('says the note is summarized to a screen reader once it has a summary', () => {
    const note = tape('Planning', 900_000, { body: '# Planning\n## Summary\nWhat the call settled.' });
    sources.lines.set(note.body, 'What the call settled.');
    const host = shelf([note]);
    expect(cassettes(host)[0]!.getAttribute('aria-label')).toMatch(/, summarized$/);
    expect(captions(host)).toEqual(['What the call settled.']);
    // In the gist's style, since it fades in as a gist does.
    expect(host.querySelector('li > p')?.className).toMatch(/gist/);
  });
});

describe('the caption', () => {
  const none = { pending: new Set<string>(), native: new Set<string>(), waiting: new Set<string>(), failed: new Set<string>(), needsModel: new Set<string>() };
  const quiet = { recording: null, refining: new Set<string>(), summaries: none, phone: false, canSummarize: false };
  const note = tape('n', 60_000);
  const long = tape('n', 1_200_000);
  const set = (...ids: string[]) => new Set(ids);

  it('is the first true thing in its order: recording, listening again, writing up, summarizing, waiting to charge, needs a model, didn’t come, the summary, the gist', () => {
    const everything = { recording: 'n', refining: set('n'), summaries: { pending: set('n'), native: set('n'), waiting: set('n'), failed: set('n'), needsModel: set('n') }, phone: false, canSummarize: false };
    sources.lines.set(note.body, 'The first line.');
    expect(captionOf(note, everything, 'a gist')).toEqual({ kind: 'recording' });
    expect(captionOf(note, { ...everything, recording: null }, 'a gist')).toEqual({ kind: 'working', word: 'Listening again', keepOpen: false });
    expect(captionOf(note, { ...everything, recording: null, refining: set() }, 'a gist')).toEqual({ kind: 'working', word: 'Writing up', keepOpen: false });
    const noNative = { ...everything.summaries, native: set() };
    expect(captionOf(note, { ...quiet, summaries: noNative }, 'a gist')).toEqual({ kind: 'working', word: 'Summarizing', keepOpen: false });
    expect(captionOf(note, { ...quiet, summaries: { ...noNative, pending: set() } }, 'a gist')).toEqual({ kind: 'waiting' });
    expect(captionOf(note, { ...quiet, summaries: { ...noNative, pending: set(), waiting: set() } }, 'a gist')).toEqual({ kind: 'needsModel' });
    expect(captionOf(note, { ...quiet, summaries: { ...noNative, pending: set(), waiting: set(), needsModel: set() } }, 'a gist')).toEqual({ kind: 'failed' });
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
    // Over ten minutes, not at them.
    expect(captionOf(tape('n', 600_000), { ...phone, refining: set('n') }, undefined)).toEqual({ kind: 'working', word: 'Listening again', keepOpen: false });
    expect(captionOf(tape('n', 600_001), { ...phone, refining: set('n') }, undefined)).toEqual({ kind: 'working', word: 'Listening again', keepOpen: true });
  });

  it('says to keep Ghost.md open, in those words, under a long tape the page is working on', () => {
    sources.refining.add('a');
    sources.pending.add('b');
    const host = shelf([tape('a', 1_200_000), tape('b', 1_200_000), tape('c', 1_200_000)]);
    expect(captions(host)).toEqual(['Listening again. Keep Ghost.md open.', 'Summarizing. Keep Ghost.md open.', '']);
  });

  it('is drawn with the spinner while something is on its way, and the reels turn only while a meeting is recorded', () => {
    const run = frames();
    sources.refining.add('a');
    sources.pending.add('b');
    sources.recording = 'c';
    const host = shelf([tape('a', 1000), tape('b', 1000), tape('c', 1000)]);
    expect(captions(host)).toEqual(['Listening again', 'Summarizing', 'Recording']);
    expect([...host.querySelectorAll('li')].map((li) => li.querySelector('[class*=working]') !== null)).toEqual([true, true, false]);
    // The tape is the player and lives in the note: only a meeting being recorded turns its reels here.
    run(5);
    const [a, b, c] = reels(host);
    expect(a).toEqual([null, null]);
    expect(b).toEqual([null, null]);
    expect(c!.every((t) => t?.startsWith('rotate('))).toBe(true);
  });

  it('offers Try again after the summary did not come, which puts the job back in the queue', () => {
    sources.failed.add('a');
    const host = shelf([tape('a', 1000)]);
    expect(captions(host)).toEqual(['The summary didn’t come Try again']);
    act(() => button('Try again', host).click());
    expect(sources.retried).toEqual(['a']);
  });

  it('says the write-up is waiting to charge, with Write up now, which asks the phone to run it from the front', () => {
    sources.waiting.add('a');
    const host = shelf([tape('a', 1000)]);
    expect(captions(host)).toEqual(['Waiting to charge Write up now']);
    // No spinner: nothing is happening to it until the phone charges, or the word is tapped.
    expect(host.querySelector('[class*=working]')).toBeNull();
    act(() => button('Write up now', host).click());
    expect(sources.writtenUp).toEqual(['a']);
  });

  it('offers Get a model while the job waits for one, which opens Settings', () => {
    sources.needsModel.add('a');
    const onGetModel = vi.fn();
    const host = shelf([tape('a', 1000)], { onGetModel });
    expect(captions(host)).toEqual(['Needs a model Get a model']);
    act(() => button('Get a model', host).click());
    expect(onGetModel).toHaveBeenCalledTimes(1);
  });

  it('is the gist when there is nothing else to say, and an empty line when there is not even that', () => {
    const host = shelf([tape('a', 1000), tape('b', 1000)], { gists: { a: 'Packing for the trip' } });
    expect(captions(host)).toEqual(['Packing for the trip', '']);
  });
});

describe('the offer', () => {
  const none = { pending: new Set<string>(), native: new Set<string>(), waiting: new Set<string>(), failed: new Set<string>(), needsModel: new Set<string>() };
  const can = { recording: null, refining: new Set<string>(), summaries: none, phone: false, canSummarize: true };
  const set = (...ids: string[]) => new Set(ids);

  it('stands for a tape of three minutes or more, with no summary, where a summariser can run and nothing is happening to the note', () => {
    expect(canOfferSummary(tape('n', 180_000), can)).toBe(true);
    expect(canOfferSummary(tape('n', 179_999), can)).toBe(false);
    expect(canOfferSummary(tape('n', 180_000), { ...can, canSummarize: false })).toBe(false);
    expect(canOfferSummary(tape('n', 180_000, { recordingMs: null }), can)).toBe(false);
    const summarized = tape('n', 180_000, { body: '# n\n## Summary\nDone.' });
    sources.lines.set(summarized.body, 'Done.');
    expect(canOfferSummary(summarized, can)).toBe(false);
    // Each state with a caption of its own: no offer beside it.
    expect(canOfferSummary(tape('n', 180_000), { ...can, recording: 'n' })).toBe(false);
    expect(canOfferSummary(tape('n', 180_000), { ...can, refining: set('n') })).toBe(false);
    for (const key of ['pending', 'native', 'waiting', 'failed', 'needsModel'] as const) {
      expect(canOfferSummary(tape('n', 180_000), { ...can, summaries: { ...none, [key]: set('n') } })).toBe(false);
    }
  });
});
