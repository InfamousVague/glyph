import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createNote, setNoteRecording, type Note } from '../core/store.ts';
import type { Segment } from '../capture/markdown.ts';
import { PACK_MAX_R, packRadii } from '../capture/tape.ts';
import { makeNote } from '../../test/notes.ts';
import { stubMatchMedia } from '../../test/stubs.ts';
import { button, show } from '../../test/render.tsx';
import { NoteTape, TranscriptWords, type TapeSummary } from './NoteTape.tsx';
import { TapeArt } from './TapeArt.tsx';
import { useTape, type Tape } from './useTape.ts';

/** The summary queue as the strip reads it: which notes have one on the way, or waiting for a model, or given up. */
const queue = vi.hoisted(() => ({ pending: new Set<string>(), needsModel: new Set<string>(), failed: new Set<string>() }));
vi.mock('../ai/summaries.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../ai/summaries.ts')>()),
  useSummaries: () => ({ pending: queue.pending, native: new Set<string>(), failed: queue.failed, needsModel: queue.needsModel }),
}));

/**
 * A spoken note's tape: the playhead the page follows (in a browser a clock stands in for the audio, which is what
 * lets this run at all), the phrases lit as they are heard, and the strip's Remove, which asks first on a note whose
 * voice memos play from the recording.
 */

const phrases: Segment[] = [
  { text: 'Pack the tent.', startMs: 0, endMs: 1000 },
  { text: 'And the stove.', startMs: 1000, endMs: 2000 },
  { text: 'Leave at six.', startMs: 2000, endMs: 3000 },
];

let tape: Tape;
function Probe({ note }: { note: Note }) {
  tape = useTape(note);
  return <TranscriptWords tape={tape} />;
}

beforeEach(() => {
  localStorage.clear();
  // A phrase heard is scrolled into view, which jsdom has nothing to do with.
  Element.prototype.scrollIntoView = () => undefined;
});
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  stubMatchMedia(false);
  for (const set of [queue.pending, queue.needsModel, queue.failed]) set.clear();
});

describe('the tape, playing', () => {
  it('fetches the phrases of a note the list loaded without them, and says so while it waits', async () => {
    await createNote('t', '# Trip');
    await setNoteRecording('t', 3000, phrases);
    const host = show(<Probe note={makeNote('t', '# Trip', { recordingMs: 3000 })} />);
    expect(host.querySelector('[aria-busy="true"]')).not.toBeNull();
    await act(async () => {
      // The note is read again by id for its phrases.
    });
    expect(tape.segments?.map((s) => s.text)).toEqual(['Pack the tent.', 'And the stove.', 'Leave at six.']);
    expect(host.querySelector('[aria-busy="true"]')).toBeNull();
  });

  it('runs on a clock in a browser, lights the phrase under the playhead, and stops at the end', () => {
    vi.useFakeTimers();
    const host = show(<Probe note={makeNote('t', '# Trip', { recordingMs: 3000, segments: phrases })} />);
    expect(tape.web).toBe(true);
    expect(tape.length).toBe(3000);
    expect(tape.current).toBe(0);
    act(() => tape.toggle());
    expect(tape.playing).toBe(true);
    act(() => void vi.advanceTimersByTime(1500));
    expect(tape.current).toBe(1);
    const lit = [...host.querySelectorAll('button')].map((b) => [b.textContent, b.hasAttribute('data-current'), b.hasAttribute('data-past')]);
    expect(lit).toEqual([
      ['Pack the tent.', false, true],
      ['And the stove.', true, false],
      ['Leave at six.', false, false],
    ]);
    act(() => void vi.advanceTimersByTime(2000));
    expect(tape.playing).toBe(false);
    expect(tape.at).toBe(0);
  });

  it('goes to a phrase that is tapped', () => {
    const host = show(<Probe note={makeNote('t', '# Trip', { recordingMs: 3000, segments: phrases })} />);
    act(() => button('Leave at six.', host).click());
    expect(tape.at).toBe(2000);
    expect(tape.current).toBe(2);
  });

  it('says when a recording kept no words', () => {
    const host = show(<Probe note={makeNote('t', '# Trip', { recordingMs: 3000, segments: [] })} />);
    expect(host.textContent).toBe('No words were kept with this recording.');
  });
});

describe('the tape at the top of a note', () => {
  const strip = (over: { hasMemos?: boolean; onRemove?: () => void; recordingMs?: number; summary?: TapeSummary | null } = {}) => {
    function Strip() {
      const t = useTape(makeNote('t', '# Trip', { recordingMs: over.recordingMs ?? 65_000, segments: phrases }));
      return <NoteTape note={makeNote('t', '# Trip')} title="Trip" tape={t} onSpeak={() => undefined} onRemove={over.onRemove ?? (() => undefined)} hasMemos={over.hasMemos ?? false} summary={over.summary ?? null} />;
    }
    return show(<Strip />);
  };
  const summary = (over: Partial<TapeSummary> = {}): TapeSummary => ({ ask: () => undefined, edited: () => false, behind: false, ...over });

  it('is not there for a note with nothing recorded', () => {
    expect(strip({ recordingMs: 0 }).innerHTML).toBe('');
  });

  it('winds an hour-long tape over its whole length in playback, rather than sitting full from the fifth minute', () => {
    function Strip() {
      tape = useTape(makeNote('t', '# Trip', { recordingMs: 3_600_000, segments: phrases }));
      return <NoteTape note={makeNote('t', '# Trip')} title="Trip" tape={tape} onSpeak={() => undefined} onRemove={() => undefined} hasMemos={false} />;
    }
    const host = show(<Strip />);
    const takeup = () => Number(host.querySelectorAll('circle')[1]!.getAttribute('r'));
    // Still, the whole recording is on the right reel.
    expect(takeup()).toBeCloseTo(PACK_MAX_R);
    // Five minutes in, a five-minute tape would be full; an hour's is a twelfth wound.
    act(() => tape.seek(300_000));
    expect(takeup()).toBeCloseTo(packRadii(300_000, 3_600_000).takeup);
    expect(takeup()).toBeLessThan(PACK_MAX_R / 2);
  });

  it('says how long the recording is, and plays and pauses it', () => {
    const host = strip();
    expect(host.textContent).toContain('0:00 / 1:05');
    act(() => button('Play', host).click());
    expect(button('Pause', host)).toBeTruthy();
  });

  it('removes a recording at once where no voice memo plays from it', () => {
    const onRemove = vi.fn();
    const host = strip({ onRemove });
    act(() => button("Remove this note's recording", host).click());
    expect(onRemove).toHaveBeenCalledTimes(1);
  });

  it('has a Summarize word only where there is a model, which asks the queue for the recording’s summary', () => {
    expect(strip().querySelector('[aria-label="Summarize the recording"]')).toBeNull();
    const ask = vi.fn();
    const host = strip({ summary: summary({ ask }) });
    const word = button('Summarize the recording', host);
    expect(word.textContent).toBe('Summarize');
    expect(word.title).toBe('The recording, summarized under the title.');
    act(() => word.click());
    expect(ask).toHaveBeenCalledWith(false);
    expect(host.textContent).not.toContain('Summary is from before the last take.');
  });

  it('asks before replacing a summary that was edited, replaces on Replace, and leaves it on Keep mine', () => {
    vi.useFakeTimers();
    const ask = vi.fn();
    const host = strip({ summary: summary({ ask, edited: () => true }) });
    act(() => button('Summarize the recording', host).click());
    expect(ask).not.toHaveBeenCalled();
    expect(host.textContent).toContain('You edited the summary. Replace it?');
    act(() => button('Keep the summary as you edited it', host).click());
    expect(ask).not.toHaveBeenCalled();
    expect(host.textContent).not.toContain('You edited the summary. Replace it?');
    act(() => button('Summarize the recording', host).click());
    act(() => void vi.advanceTimersByTime(8000));
    expect(host.textContent).not.toContain('You edited the summary. Replace it?');
    act(() => button('Summarize the recording', host).click());
    act(() => button('Replace the summary you edited', host).click());
    expect(ask).toHaveBeenCalledWith(true);
  });

  it('says when the summary is from before the last take, when one is on its way, when a model is missing, and when it did not come', () => {
    expect(strip({ summary: summary({ behind: true }) }).textContent).toContain('Summary is from before the last take.');
    queue.pending.add('t');
    let host = strip({ summary: summary({ behind: true }) });
    const word = button('Summarize the recording', host);
    expect(word.textContent).toBe('Summarizing');
    expect(word.disabled).toBe(true);
    expect(host.textContent).not.toContain('Summary is from before the last take.');
    queue.pending.clear();
    queue.needsModel.add('t');
    host = strip({ summary: summary() });
    expect(host.textContent).toContain('Needs a model.');
    queue.needsModel.clear();
    queue.failed.add('t');
    host = strip({ summary: summary() });
    expect(host.textContent).toContain('The summary didn’t come.');
  });

  it('asks first where voice memos play from it, keeps it on Keep, and stops asking after a while', () => {
    vi.useFakeTimers();
    const onRemove = vi.fn();
    const host = strip({ onRemove, hasMemos: true });
    act(() => button("Remove this note's recording", host).click());
    expect(onRemove).not.toHaveBeenCalled();
    expect(host.textContent).toContain('The voice memos in this note play from this recording.');
    act(() => button("Keep this note's recording", host).click());
    expect(host.textContent).not.toContain('The voice memos in this note play from this recording.');
    act(() => button("Remove this note's recording", host).click());
    act(() => void vi.advanceTimersByTime(5000));
    expect(button("Remove this note's recording", host)).toBeTruthy();
    act(() => button("Remove this note's recording", host).click());
    act(() => button('Remove the recording and stop its voice memos', host).click());
    expect(onRemove).toHaveBeenCalledTimes(1);
  });
});

describe('the cassette', () => {
  /**
   * The frames, run by hand on a clock of the test's own. The cassette reads the clock once as it mounts and then
   * from each frame, and both read this one, so a loaded machine cannot stretch or shrink a frame: with the real
   * clock, a slow mount ate the first frame's 16ms and a comparison of two cassettes' turns failed under the full suite.
   */
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
  const reels = (host: HTMLElement) => [...host.querySelectorAll('svg > g:not([mask])')].map((g) => g.getAttribute('transform'));

  it('turns its reels, frame by frame, while it plays', () => {
    const run = frames();
    const host = show(<TapeArt positionMs={30_000} playing title="Trip" />);
    run(5);
    const turned = reels(host);
    expect(turned.every((t) => t?.startsWith('rotate('))).toBe(true);
    run(5);
    expect(reels(host)).not.toEqual(turned);
  });

  it('draws its label bare, with the A mark and no words, and gives each cassette its own label mask', () => {
    const host = show(
      <>
        <TapeArt positionMs={30_000} title="Trip" side="26 SEP" counter="0:30" />
        <TapeArt positionMs={30_000} bare title="Trip" side="26 SEP" counter="0:30" />
      </>,
    );
    const [worded, bare] = [...host.querySelectorAll('svg')];
    expect([...worded!.querySelectorAll('text')].map((t) => t.textContent)).toEqual(['A', 'Trip', '26 SEP', '0:30']);
    expect([...bare!.querySelectorAll('text')].map((t) => t.textContent)).toEqual(['A']);
    // Eight cassettes on one page shared `tape-label-mask`, and every one wore the first one's.
    const masks = [...host.querySelectorAll('mask')].map((m) => m.id);
    expect(new Set(masks).size).toBe(2);
    expect(worded!.querySelector('g[mask]')?.getAttribute('mask')).toBe(`url(#${masks[0]})`);
    expect(bare!.querySelector('g[mask]')?.getAttribute('mask')).toBe(`url(#${masks[1]})`);
  });

  it('winds a longer tape over its own length, so an hour is not full from the fifth minute', () => {
    const takeup = (host: HTMLElement) => Number(host.querySelectorAll('circle')[1]!.getAttribute('r'));
    const fiveMinutes = takeup(show(<TapeArt positionMs={300_000} />));
    const anHour = takeup(show(<TapeArt positionMs={300_000} lengthMs={3_600_000} />));
    expect(anHour).toBeLessThan(fiveMinutes);
    // Left unsaid, the tape is the five-minute one, and five minutes fills it.
    expect(fiveMinutes).toBe(packRadii(300_000).takeup);
    expect(fiveMinutes).toBeCloseTo(PACK_MAX_R);
  });

  it('turns the reels over the radii its length gives: the nearly empty take-up of an hour turns faster than a full one', () => {
    /** How far the take-up reel has turned, in degrees, from its transform. */
    const turned = (host: HTMLElement) => Math.abs(Number(/rotate\((-?[\d.]+)/.exec(host.querySelectorAll('svg > g:not([mask])')[1]?.getAttribute('transform') ?? '')?.[1] ?? 0));
    const hour = frames();
    const anHour = show(<TapeArt positionMs={300_000} lengthMs={3_600_000} playing />);
    hour(10);
    const fiveMinutes = frames();
    const full = show(<TapeArt positionMs={300_000} playing />);
    fiveMinutes(10);
    expect(turned(full)).toBeGreaterThan(0);
    expect(turned(anHour)).toBeGreaterThan(turned(full) * 1.5);
  });

  it('does not turn for someone who asked for less motion', () => {
    stubMatchMedia(true);
    const run = frames();
    const host = show(<TapeArt positionMs={30_000} playing title="Trip" />);
    run(5);
    expect(reels(host)).toEqual([null, null]);
  });
});
