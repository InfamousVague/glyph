import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createNote, setNoteRecording, type Note } from '../core/store.ts';
import type { Segment } from '../capture/markdown.ts';
import { makeNote } from '../../test/notes.ts';
import { button, show } from '../../test/render.tsx';
import { NoteTape, TranscriptWords } from './NoteTape.tsx';
import { useTape, type Tape } from './useTape.ts';

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
afterEach(() => vi.useRealTimers());

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
  const strip = (over: { hasMemos?: boolean; onRemove?: () => void; recordingMs?: number } = {}) => {
    function Strip() {
      const t = useTape(makeNote('t', '# Trip', { recordingMs: over.recordingMs ?? 65_000, segments: phrases }));
      return <NoteTape note={makeNote('t', '# Trip')} title="Trip" tape={t} onSpeak={() => undefined} onRemove={over.onRemove ?? (() => undefined)} hasMemos={over.hasMemos ?? false} />;
    }
    return show(<Strip />);
  };

  it('is not there for a note with nothing recorded', () => {
    expect(strip({ recordingMs: 0 }).innerHTML).toBe('');
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
