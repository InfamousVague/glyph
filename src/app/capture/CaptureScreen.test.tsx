import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createNote, getNote, listNotes, noteTitle, setNoteRecording, updateNote } from '../core/store.ts';
import { stubResizeObserver } from '../../test/stubs.ts';
import { bookNoteBody } from '../book/book.ts';
import { canvasNoteBody } from '../canvas/jsonCanvas.ts';
import type { StopOptions } from './engine.ts';
import type { RefineJob } from './refine.ts';
import { CaptureScreen } from './CaptureScreen.tsx';

const capture = vi.hoisted(() => ({
  handlers: null as { onPartial: (text: string) => void; onSegment: (segment: { text: string; startMs: number; endMs: number }) => void } | null,
  session: null as {
    kind: 'whisper';
    wantsSamples: false;
    keepsAudio: boolean;
    push: () => void;
    positionMs: () => number;
    stop: (options?: StopOptions) => Promise<{ recordedMs: number | null; transcript: string | null }>;
    cancel: () => void;
  } | null,
  /** The sound of a take nobody kept, by the note id it was recorded under (engine.ts `discardRecording`). */
  discarded: [] as string[],
  /** A take's sound moved to the note a command went to: from, to, and whether it went on the end (engine.ts `reassignRecording`). */
  reassigned: [] as [string, string, boolean][],
  /** The better words' jobs asked for at Done (refine.ts `enqueueRefine`). */
  refines: [] as Omit<RefineJob, 'tries'>[],
}));

vi.mock('./engine.ts', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./engine.ts')>();
  return {
    ...actual,
    startCapture: vi.fn(async (handlers) => {
      capture.handlers = handlers;
      if (!capture.session) throw new Error('test capture session was not configured');
      return capture.session;
    }),
    discardRecording: vi.fn(async (id: string) => void capture.discarded.push(id)),
    reassignRecording: vi.fn(async (from: string, to: string, append: boolean) => {
      capture.reassigned.push([from, to, append]);
      return 3000;
    }),
  };
});

vi.mock('./refine.ts', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./refine.ts')>();
  return { ...actual, enqueueRefine: (job: Omit<RefineJob, 'tries'>) => void capture.refines.push(job) };
});

beforeEach(() => {
  localStorage.clear();
  capture.discarded = [];
  capture.reassigned = [];
  capture.refines = [];
  HTMLElement.prototype.scrollTo = () => undefined;
  capture.handlers = null;
  capture.session = {
    kind: 'whisper',
    wantsSamples: false,
    keepsAudio: false,
    push: () => undefined,
    positionMs: () => 2600,
    // Native stop drains the final decode after the page has stopped receiving
    // capture://segment events. This is intentionally longer than the event.
    stop: async () => ({ recordedMs: null, transcript: 'add to the note labeled Go pack sunscreen' }),
    cancel: () => undefined,
  };
  stubResizeObserver();
});

afterEach(() => cleanup());

describe('native stop transcript handoff', () => {
  it('offers the full stop-time append to Go and never creates a note from a truncated phrase event', async () => {
    await createNote('go', 'Go');
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);

    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await act(async () => {
      // The terminal words never arrive as a committed event.
      capture.handlers!.onSegment({ text: 'add to the note labeled Go pack', startMs: 0, endMs: 1800 });
    });

    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));

    // The full native stop result, not Take's event-only segments, reaches the
    // classifier. A confirmation is offered before any mutation happens.
    await screen.findByRole('region', { name: 'Add to Go' });
    let notes = await listNotes();
    expect(notes).toHaveLength(1);
    expect(notes[0]?.body).toBe('Go');

    fireEvent.click(screen.getByRole('button', { name: 'Add' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));

    notes = await listNotes();
    expect(notes).toHaveLength(1);
    expect(noteTitle(notes[0]!.body)).toBe('Go');
    expect(notes[0]?.body).toContain('Pack sunscreen');
    expect(notes[0]?.body).not.toMatch(/add to the note labeled/i);
  });

  it('keeps a native-only terminal suffix when the stopped recording is an ordinary note', async () => {
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Weekend plans include packing sunscreen' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);

    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await act(async () => {
      capture.handlers!.onSegment({ text: 'Weekend plans include packing', startMs: 0, endMs: 1500 });
    });
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));

    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    const notes = await listNotes();
    expect(notes).toHaveLength(1);
    expect(notes[0]?.body).toContain('sunscreen');
  });
});

describe('the card after Done', () => {
  it('waits for its tap however long it is up, so the finished take can still be answered', async () => {
    await createNote('go', 'Go');
    const ticks = vi.fn(() => 2600);
    capture.session!.positionMs = ticks;
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await screen.findByRole('region', { name: 'Add to Go' });

    // Well past the twenty seconds a spoken question is given (take.ts TAKE_TIMING.confirmMs), and ticked through.
    const clock = performance.now.bind(performance);
    const later = vi.spyOn(performance, 'now').mockImplementation(() => clock() + 60_000);
    try {
      const before = ticks.mock.calls.length;
      await waitFor(() => expect(ticks.mock.calls.length).toBeGreaterThan(before + 1));
      expect(screen.getByRole('region', { name: 'Add to Go' })).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
      await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    } finally {
      later.mockRestore();
    }
    expect((await listNotes()).map((note) => note.body)).toEqual(['Go']);
  });

  it('takes Discard as its Cancel, rather than leaving the finished take with no way out', async () => {
    await createNote('go', 'Go');
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    const card = await screen.findByRole('region', { name: 'Add to Go' });
    // The microphone is off by now: the card no longer says a spoken yes or no will do.
    expect(card.textContent).not.toMatch(/say “yes”/);
    fireEvent.click(screen.getByRole('button', { name: 'Discard' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect((await listNotes()).map((note) => note.body)).toEqual(['Go']);
  });

  it('opens the note a confirmed card wrote to, with the lines it put in', async () => {
    await createNote('go', 'Go');
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    const card = await screen.findByRole('region', { name: 'Add to Go' });
    fireEvent.click(card.querySelector('button.app-pill')!);
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    const [saved, , , , landing] = onFinish.mock.calls[0]!;
    expect(saved).toMatchObject({ id: 'go', body: expect.stringContaining('Pack sunscreen') });
    expect(landing).toMatchObject({ noteId: 'go', title: 'Go', blocks: [expect.stringContaining('Pack sunscreen')], made: [] });
  });
});

describe('things to say', () => {
  it('shows the card until the first words, naming one of their notes and no ask on a new recording, then tips one at a time', async () => {
    await createNote('groceries', 'Groceries');
    render(<CaptureScreen fromAssistant={false} onFinish={vi.fn()} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    const card = await screen.findByLabelText('Things to say');
    await waitFor(() => expect(card.textContent).toContain('add … to Groceries'));
    expect(card.textContent).toContain('Bullet point');
    // A new recording is not a note yet: an ask said into it would not run, so none is offered.
    expect(card.textContent).not.toContain('fix the spelling');
    act(() => capture.handlers!.onSegment({ text: 'Milk and eggs', startMs: 0, endMs: 900 }));
    await waitFor(() => expect(screen.queryByLabelText('Things to say')).toBeNull());
  });

  it('offers the asks on a note’s own Speak, and never names that note as somewhere to send the take', async () => {
    await createNote('groceries', 'Groceries');
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={vi.fn()} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    const card = await screen.findByLabelText('Things to say');
    await waitFor(() => expect(card.textContent).toContain('fix the spelling'));
    expect(card.textContent).not.toContain('to Groceries');
    expect(card.textContent).toContain('make a list called');
  });
});

/** A phrase committed, as Whisper's capture://segment would hand it over. */
const say = (text: string, startMs: number) => act(() => capture.handlers!.onSegment({ text, startMs, endMs: startMs + 900 }));

describe('a note’s own Speak', () => {
  it('says where the words are going, and writes them under the note’s own text at Done', async () => {
    await createNote('daily', '# Daily Life\n\n- Walked');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Oat milk too.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="daily" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Oat milk too.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(onFinish.mock.calls[0]?.[0]).toMatchObject({ id: 'daily', body: '# Daily Life\n\n- Walked\n\nOat milk too.' });
    expect((await listNotes()).map((note) => note.body)).toEqual(['# Daily Life\n\n- Walked\n\nOat milk too.']);
  });

  // Changed on purpose (docs/DESIGN.md §126): a note whose title says it is a list takes what is said as its items.
  it('writes into the list of a note whose title says it is one', async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Oat milk too.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('Oat milk too.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body)).toEqual(['# Groceries\n\n- Eggs\n- Oat milk too']);
  });

  it('opens the note with the run on it when what was said is an ask about the note', async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Hey Ghost, fix the spelling.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('Hey Ghost, fix the spelling.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(onFinish.mock.calls[0]?.slice(1)).toEqual([false, undefined, { kind: 'fix' }]);
    expect(onFinish.mock.calls[0]?.[0]).toMatchObject({ id: 'groceries' });
    expect((await listNotes()).map((note) => note.body)).toEqual(['# Groceries\n\n- Eggs']);
  });

  // Changed on purpose (docs/DESIGN.md §126): nothing is stored mid-take, so what was said before New note is written
  // at Done with the rest, and Discard would take it back too.
  it('carries on in a new note from New note, leaving what was said so far where it was said', async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'For the soup. Call Sam.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('For the soup.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'New note' }));
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Adding to “Groceries”' })).toBeNull());
    expect((await getNote('groceries'))?.body).toBe('# Groceries\n\n- Eggs');
    await say('Call Sam.', 3000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    const bodies = (await listNotes()).map((note) => note.body).sort();
    expect(bodies).toEqual(['# Call Sam', '# Groceries\n\n- Eggs\n- For the soup']);
  });
});

describe('ending a recording', () => {
  it('leaves nothing behind on Discard', async () => {
    const cancel = vi.fn();
    capture.session!.cancel = cancel;
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('Pick up the parcel.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Discard' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect(cancel).toHaveBeenCalledOnce();
    expect(await listNotes()).toEqual([]);
  });

  it('leaves nothing behind on Done when nothing was said', async () => {
    capture.session!.stop = async () => ({ recordedMs: null, transcript: null });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect(await listNotes()).toEqual([]);
  });

  it('leaves nothing behind when all that was heard is a cue said alone, as Whisper echoing its prompt makes', async () => {
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Bullet point.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('Bullet point.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect(await listNotes()).toEqual([]);
  });

  it('refuses a command that names a note there is none of, and saves none of its words', async () => {
    await createNote('work', 'Work');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Add to shopping, oat milk.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('Add to shopping, oat milk.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect((await listNotes()).map((note) => note.body)).toEqual(['Work']);
  });
});

describe('the recorder’s own lines', () => {
  it('says nothing was recorded, and why, when it could not start', async () => {
    capture.session = null;
    render(<CaptureScreen fromAssistant={false} onFinish={vi.fn()} />);
    await screen.findByText('Nothing was recorded.');
    expect(screen.getByRole('status', { name: '' }).textContent).toContain('test capture session was not configured');
    expect(screen.getByRole('button', { name: 'Stop and save' })).toBeDisabled();
  });

  it('shows what the pipeline has done when the top line is tapped', async () => {
    render(<CaptureScreen fromAssistant={false} onFinish={vi.fn()} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('Hello.', 0);
    fireEvent.click(await screen.findByRole('button', { name: 'New note' }));
    await waitFor(() => expect(screen.getByText(/^On-device Whisper · heard 0\.0 s · 0 guesses · 1 phrase$/)).toBeInTheDocument());
  });
});

/**
 * The tape. The stand-in session keeps its sound, as Whisper does on a binary that keeps recordings: `stop` is told
 * which note's id to keep it under and whether to add it to the end of that note's tape, and answers the tape's whole
 * length. What Done stores against the tape - the note's phrases, the better words' job - must be on that timeline.
 */
describe('the sound of a recording', () => {
  const eggs = { text: 'Eggs.', startMs: 0, endMs: 900 };
  /** A note with thirty seconds of tape already, from an earlier recording. */
  const taped = async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    await setNoteRecording('groceries', 30_000, [eggs]);
  };
  const keeping = (recordedMs: number, transcript: string | null) => {
    const stop = vi.fn(async (_options?: StopOptions) => ({ recordedMs, transcript }));
    capture.session!.keepsAudio = true;
    capture.session!.stop = stop;
    return stop;
  };

  it('goes on the end of a continued note’s tape, and the take’s phrases after the ones it had', async () => {
    await taped();
    const stop = keeping(33_000, 'Oat milk too.');
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('Oat milk too.', 1000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));

    expect(stop).toHaveBeenCalledWith({ recordAs: 'groceries', append: true });
    const stored = await getNote('groceries');
    expect(stored?.recordingMs).toBe(33_000);
    expect(stored?.segments).toEqual([eggs, { text: 'Oat milk too.', startMs: 31_000, endMs: 31_900 }]);
    expect(capture.refines).toHaveLength(1);
    expect(capture.refines[0]).toMatchObject({
      id: 'groceries',
      fromMs: 30_000,
      recordingMs: 33_000,
      baseBody: '# Groceries\n\n- Eggs',
      titled: false,
      priorSegments: [eggs],
      skip: [],
      clips: [],
      keywordAt: [],
    });
  });

  it('starts the file afresh on a note whose recording was removed, rather than playing after the removed sound', async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    await setNoteRecording('groceries', 0, []);
    const stop = keeping(2000, 'Oat milk too.');
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('Oat milk too.', 1000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));

    expect(stop).toHaveBeenCalledWith({ recordAs: 'groceries', append: false });
    expect((await getNote('groceries'))?.segments).toEqual([{ text: 'Oat milk too.', startMs: 1000, endMs: 1900 }]);
    expect(capture.refines[0]).toMatchObject({ fromMs: 0, recordingMs: 2000, priorSegments: [] });
  });

  it('is the new note’s after New note, with what was said before it left out of the better words', async () => {
    await taped();
    const stop = keeping(4000, 'Call Sam.');
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('For the soup.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'New note' }));
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Adding to “Groceries”' })).toBeNull());
    await say('Call Sam.', 3000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));

    const made = onFinish.mock.calls[0]?.[0] as { id: string };
    expect(made.id).not.toBe('groceries');
    expect(stop).toHaveBeenCalledWith({ recordAs: made.id, append: false });
    expect((await getNote(made.id))?.segments).toEqual([{ text: 'Call Sam.', startMs: 3000, endMs: 3900 }]);
    // The stretch said for the soup went to Groceries as words: the better words over this tape must not write it again.
    expect(capture.refines[0]).toMatchObject({ id: made.id, fromMs: 0, titled: true, skip: [{ startMs: 0, endMs: 900 }] });
    // The continued note's own tape is as it was; the words said for it are in it.
    expect(await getNote('groceries')).toMatchObject({ body: '# Groceries\n\n- Eggs\n- For the soup', recordingMs: 30_000, segments: [eggs] });
  });

  for (const [what, transcript] of [
    ['nothing was said', null],
    ['all that was heard is a cue said alone', 'Bullet point.'],
  ] as const) {
    it(`stays counted on a continued note’s tape when ${what}, so the next take lines up with its sound`, async () => {
      await taped();
      keeping(33_000, transcript);
      const onFinish = vi.fn();
      render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
      await screen.findByRole('button', { name: 'Adding to “Groceries”' });
      if (transcript) await say(transcript, 1000);
      fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
      await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));

      // The stop put three seconds on the end of the note's file; the note says so, and its words and phrases are as they were.
      expect(await getNote('groceries')).toMatchObject({ body: '# Groceries\n\n- Eggs', recordingMs: 33_000, segments: [eggs] });
      expect(capture.discarded).toEqual([]);
      expect(capture.refines).toEqual([]);
    });

    it(`goes when ${what} into a new recording, with the note that is not made`, async () => {
      const stop = keeping(3000, transcript);
      const onFinish = vi.fn();
      render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
      await waitFor(() => expect(capture.handlers).not.toBeNull());
      if (transcript) await say(transcript, 0);
      fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
      await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));

      const recordedAs = stop.mock.calls[0]?.[0]?.recordAs;
      expect(recordedAs).toEqual(expect.any(String));
      expect(capture.discarded).toEqual([recordedAs]);
      expect(await listNotes()).toEqual([]);
    });
  }
  /** Speaks `transcript` into Groceries, which has thirty seconds of tape, and presses Done. */
  const intoGroceries = async (transcript: string) => {
    await taped();
    const stop = keeping(33_000, transcript);
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say(transcript, 1000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    return { stop, onFinish };
  };

  it('stays on a continued note’s tape when what was said into it is an instruction for the AI', async () => {
    const { stop, onFinish } = await intoGroceries('Hey Ghost, fix the spelling.');
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(stop).toHaveBeenCalledWith({ recordAs: 'groceries', append: true });
    // The file is the whole of Groceries' recording, not the take's: it stays, three seconds longer, words as they were.
    expect(capture.discarded).toEqual([]);
    expect(await getNote('groceries')).toMatchObject({ body: '# Groceries\n\n- Eggs', recordingMs: 33_000, segments: [eggs] });
  });

  it('stays on a continued note’s tape when what was said into it is a command that is refused', async () => {
    const { onFinish } = await intoGroceries('add to the camping list eggs and milk');
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect(capture.discarded).toEqual([]);
    expect(await getNote('groceries')).toMatchObject({ recordingMs: 33_000, segments: [eggs] });
  });

  it('stays on a continued note’s tape when a command said into it is confirmed onto another note', async () => {
    await createNote('go', 'Go');
    const { onFinish } = await intoGroceries('add to the note labeled Go pack sunscreen');
    const card = await screen.findByRole('region', { name: 'Add to Go' });
    fireEvent.click(card.querySelector('button.app-pill')!);
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    // Moving the file would have moved the whole of Groceries' tape onto Go.
    expect(capture.reassigned).toEqual([]);
    expect(capture.discarded).toEqual([]);
    expect(await getNote('groceries')).toMatchObject({ recordingMs: 33_000, segments: [eggs] });
    expect((await getNote('go'))?.recordingMs ?? 0).toBe(0);
  });

  it('stays on a continued note’s tape when the command card after Done is cancelled', async () => {
    await createNote('go', 'Go');
    const { onFinish } = await intoGroceries('add to the note labeled Go pack sunscreen');
    await screen.findByRole('region', { name: 'Add to Go' });
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect(capture.discarded).toEqual([]);
    expect(await getNote('groceries')).toMatchObject({ recordingMs: 33_000, segments: [eggs] });
  });

  it('moves a new recording’s sound to the note a confirmed command went to, as before', async () => {
    await createNote('go', 'Go');
    const stop = keeping(3000, 'add to the note labeled Go pack sunscreen');
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('add to the note labeled Go pack sunscreen', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    const card = await screen.findByRole('region', { name: 'Add to Go' });
    fireEvent.click(card.querySelector('button.app-pill')!);
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    const recordedAs = stop.mock.calls[0]?.[0]?.recordAs;
    expect(capture.reassigned).toEqual([[recordedAs, 'go', false]]);
    expect((await getNote('go'))?.recordingMs).toBe(3000);
  });
});

/**
 * Matt: "add a note to house to do's, the note is call an electrician to fix the light sockets" made a new note. The
 * recorder must find House TODOs, switch to it, write the to-do into its list as it is said, store nothing before
 * Done, write it once at Done with no second card, and hand House TODOs back to be opened.
 */
describe('adding to a note as it is said', () => {
  const HOUSE = '# House TODOs\n\n- [ ] Fix the gutter\n';
  const CALLED = '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n';
  /** The page the recorder draws: the editor's words as they read now. */
  const page = () => document.querySelector('.cm-content')?.textContent ?? '';
  const done = () => fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
  const recording = async (props: { noteId?: string } = {}) => {
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} {...props} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    return onFinish;
  };
  beforeEach(() => {
    capture.session!.stop = async () => ({ recordedMs: null, transcript: null });
  });
  afterEach(() => {
    delete (window as { GlyphHost?: unknown }).GlyphHost;
  });

  it('switches to House TODOs, writes the to-do into its list as it is said, and opens it at Done', async () => {
    await createNote('house', HOUSE);
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's.", 0);
    await screen.findByRole('button', { name: 'Adding to “House TODOs”' });
    expect(screen.getByText(/Say the note for/).textContent).toMatch(/Say the note for House TODOs/);
    await say('The note is call an electrician to fix the light sockets.', 1500);
    await waitFor(() => expect(page()).toContain('Call an electrician to fix the light sockets'));
    expect(page()).toContain('Fix the gutter');
    expect(page()).not.toContain('The note is');
    // Nothing is stored before Done.
    expect((await getNote('house'))?.body).toBe(HOUSE);
    expect(await listNotes()).toHaveLength(2);

    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(screen.queryByRole('region', { name: /^Add to/ })).toBeNull();
    expect((await getNote('house'))?.body).toBe(CALLED);
    expect(await listNotes()).toHaveLength(2);
    const [saved, locked, review, ask, landing] = onFinish.mock.calls[0]!;
    expect(saved).toMatchObject({ id: 'house', body: CALLED });
    expect([locked, review, ask]).toEqual([false, undefined, undefined]);
    expect(landing).toMatchObject({ noteId: 'house', title: 'House TODOs', blocks: ['- [ ] Call an electrician to fix the light sockets'], others: [], made: [] });
  });

  it.each([
    'Hey Ghost, add a note to house chores, the note is call an electrician to fix the light sockets.',
    "Hey, like, add a note to house to do's, the note is call an electrician to fix the light sockets.",
    'Hey goes add a note to house to-dos. Call an electrician to fix the light sockets.',
  ])('does the same said in one phrase: %s', async (said) => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say(said, 0);
    await screen.findByRole('button', { name: 'Adding to “House TODOs”' });
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body)).toEqual([CALLED]);
  });

  it('writes a phrase committed in the same moment as the switch into the note switched to', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    act(() => {
      capture.handlers!.onSegment({ text: "Hey Ghost, add a note to house to do's.", startMs: 0, endMs: 900 });
      capture.handlers!.onSegment({ text: 'Call Sam.', startMs: 1000, endMs: 1900 });
    });
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body)).toEqual(['# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n']);
  });

  it('keeps the item when the side key ends the recording straight after the command', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say('Hey Ghost, add call Sam to House TODOs.', 0);
    act(() => window.__glyph?.screenOff?.());
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
  });

  it('keeps the last words only the stop heard, and routes a command only the stop heard, with no card', async () => {
    await createNote('house', HOUSE);
    capture.session!.stop = async () => ({ recordedMs: null, transcript: "Hey Ghost, add a note to house to do's. Call an electrician to fix the light sockets." });
    const first = await recording();
    await say("Hey Ghost, add a note to house to do's.", 0);
    await say('Call an electrician to fix the light', 1500);
    done();
    await waitFor(() => expect(first).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe(CALLED);
    cleanup();

    localStorage.clear();
    await createNote('house', HOUSE);
    const stop = vi.fn(async (_options?: StopOptions) => ({ recordedMs: 3000, transcript: 'Hey Ghost, add call Sam to house to-dos.' }));
    capture.session!.keepsAudio = true;
    capture.session!.stop = stop;
    const second = await recording();
    done();
    await waitFor(() => expect(second).toHaveBeenCalledTimes(1));
    expect(screen.queryByRole('region', { name: /^Add to/ })).toBeNull();
    expect((await listNotes()).map((note) => note.body)).toEqual(['# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n']);
    const recordedAs = stop.mock.calls[0]?.[0]?.recordAs;
    expect(capture.reassigned).toEqual([[recordedAs, 'house', false]]);
    expect(second.mock.calls[0]?.[0]).toMatchObject({ id: 'house' });
  });

  it('sends a one-shot mid-take and carries on in the take’s own note', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say('Kevin owns the release.', 0);
    await say('Hey Ghost, add call the electrician to House TODOs.', 1000);
    await say('Next, the budget review is Friday.', 2000);
    expect(screen.getByRole('button', { name: 'New note' })).toBeInTheDocument();
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call the electrician\n');
    const [saved, , , , landing] = onFinish.mock.calls[0]!;
    expect(saved.body).toBe('# Kevin owns the release\n\nNext, the budget review is Friday.');
    expect(landing).toMatchObject({ noteId: saved.id, others: [expect.any(String)] });
  });

  it('sends a one-shot from a note’s own Speak, keeping both sentences there, and opens that note', async () => {
    await createNote('house', HOUSE);
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    const onFinish = await recording({ noteId: 'daily' });
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Went for a run.', 0);
    await say('Hey Ghost, add call Sam to House TODOs.', 1000);
    await say('Then I made lunch.', 2000);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('daily'))?.body).toBe('# Daily Life\n\nWent for a walk.\n\nWent for a run. Then I made lunch.');
    expect((await getNote('house'))?.body).toContain('- [ ] Call Sam\n');
    expect(onFinish.mock.calls[0]?.[0]).toMatchObject({ id: 'daily' });
  });

  it('asks which note on a card, takes the words said after it as words, and moves them on a tap', async () => {
    await createNote('s1', '# Signing in, and signing');
    await createNote('s2', '# Signing the order');
    const onFinish = await recording();
    await say('Hey Ghost, add a note to signing.', 0);
    await say('Check the form.', 1000);
    const card = await screen.findByRole('region', { name: 'Add to which note?' });
    fireEvent.click(within(card).getByRole('button', { name: 'Signing the order' }));
    await screen.findByRole('button', { name: 'Adding to “Signing the order”' });
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('s2'))?.body).toBe('# Signing the order\n\nCheck the form.');
    expect(await listNotes()).toHaveLength(2);
  });

  it('keeps the words here when Done comes with the card still up', async () => {
    await createNote('s1', '# Signing in, and signing');
    await createNote('s2', '# Signing the order');
    const onFinish = await recording();
    await say('Hey Ghost, add call Sam to signing.', 0);
    await screen.findByRole('region', { name: 'Add to which note?' });
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body).sort()).toEqual(['# Call Sam', '# Signing in, and signing', '# Signing the order']);
  });

  it('keeps words for a note there is none of here, and makes a named one from a card at Done', async () => {
    await createNote('house', HOUSE);
    const first = await recording();
    await say('Hey Ghost, add eggs to the moon base.', 0);
    await screen.findByText('No note called “moon base”, so the words stay here.');
    done();
    await waitFor(() => expect(first).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body).sort()).toEqual(['# Eggs', HOUSE]);
    cleanup();

    localStorage.clear();
    const second = await recording();
    await say('Hey Ghost, add a note to the moon base.', 0);
    const card = await screen.findByRole('region', { name: 'No note called “moon base”' });
    fireEvent.click(within(card).getByRole('button', { name: 'New note “Moon base”' }));
    await say('Call Sam.', 1000);
    expect(await listNotes()).toEqual([]);
    done();
    await waitFor(() => expect(second).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body)).toEqual(['Moon base\n\nCall Sam.']);
  });

  it('stores nothing on Not this note, and Done makes the take a note of its own', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
    fireEvent.click(await screen.findByRole('button', { name: 'Not this note' }));
    await screen.findByRole('button', { name: 'New note' });
    expect((await getNote('house'))?.body).toBe(HOUSE);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe(HOUSE);
    expect((await listNotes()).map((note) => note.body).sort()).toEqual(['# Call Sam', HOUSE]);
  });

  it('stores nothing on Discard after a switch', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
    await screen.findByRole('button', { name: 'Adding to “House TODOs”' });
    fireEvent.click(screen.getByRole('button', { name: 'Discard' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect((await listNotes()).map((note) => note.body)).toEqual([HOUSE]);
  });

  it('puts the item under the heading it fits, and says so', async () => {
    await createNote('jobs', '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n');
    const onFinish = await recording();
    await say('Hey Ghost, add a note to home jobs, call an electrician.', 0);
    await screen.findByText(/under Electrical/);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('jobs'))?.body).toBe('# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call an electrician\n');
  });

  it('writes onto the note as it is at Done when it changed while the take was said', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
    const now = await getNote('house');
    await updateNote('house', `${HOUSE}- [ ] Clear the drains\n`, now!.revision ?? 1);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Clear the drains\n- [ ] Call Sam\n');
  });

  it('over the lock screen, names no note, raises no card, and shows none of the note', async () => {
    (window as { GlyphHost?: unknown }).GlyphHost = { isLocked: () => true, endCapture: () => undefined, setCapturing: () => false };
    await createNote('house', HOUSE);
    await createNote('s1', '# Signing in, and signing');
    await createNote('s2', '# Signing the order');
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
    await screen.findByRole('button', { name: 'Adding to the note you named' });
    expect(page()).not.toContain('Fix the gutter');
    await say('Hey Ghost, add call Jo to signing.', 1000);
    expect(screen.queryByRole('region', { name: 'Add to which note?' })).toBeNull();
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toContain('- [ ] Call Sam\n');
  });

  it('queues an ask said mid-take on a note’s own Speak, and leaves one out of a switched take', async () => {
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    const own = await recording({ noteId: 'daily' });
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Went for a run.', 0);
    await say('Hey Ghost, fix the spelling.', 1000);
    done();
    await waitFor(() => expect(own).toHaveBeenCalledTimes(1));
    expect(own.mock.calls[0]?.[3]).toEqual({ kind: 'fix' });
    expect((await getNote('daily'))?.body).toBe('# Daily Life\n\nWent for a walk.\n\nWent for a run.');
  });

  it('keeps the sound with the note switched to, on its tape, and hands the better words where the words went', async () => {
    await createNote('house', HOUSE);
    const stop = vi.fn(async (_options?: StopOptions) => ({ recordedMs: 4000, transcript: null }));
    capture.session!.keepsAudio = true;
    capture.session!.stop = stop;
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's.", 0);
    await say('Call Sam.', 1500);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(stop).toHaveBeenCalledWith({ recordAs: 'house', append: false });
    expect(capture.reassigned).toEqual([]);
    expect(await getNote('house')).toMatchObject({ recordingMs: 4000, segments: [{ text: 'Call Sam.', startMs: 1500, endMs: 2400 }] });
    expect(capture.refines).toHaveLength(1);
    expect(capture.refines[0]).toMatchObject({
      id: 'house',
      baseBody: HOUSE,
      savedBody: '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n',
      titled: false,
      skip: [{ startMs: 0, endMs: 900 }],
      placing: { kind: 'lists', task: true },
      live: [{ text: 'Call Sam.', startMs: 1500, endMs: 2400 }],
    });
  });

  it('never names a canvas, and keeps words for a book here', async () => {
    await createNote('canvas', canvasNoteBody('House plans', { nodes: [], edges: [] }));
    await createNote('book', bookNoteBody('Field guide', ['Trees']));
    const onFinish = await recording();
    await say('Hey Ghost, add Rivers to the field guide.', 0);
    await screen.findByText('“Field guide” is a book, so the words stay here.');
    await say('Hey Ghost, add call Sam to house plans.', 1000);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('canvas'))?.body).toBe(canvasNoteBody('House plans', { nodes: [], edges: [] }));
    expect((await getNote('book'))?.body).toBe(bookNoteBody('Field guide', ['Trees']));
  });
});
