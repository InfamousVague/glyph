import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createNote, getNote, listNotes, noteTitle, setNoteRecording } from '../core/store.ts';
import { stubResizeObserver } from '../../test/stubs.ts';
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
  };
});

vi.mock('./refine.ts', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./refine.ts')>();
  return { ...actual, enqueueRefine: (job: Omit<RefineJob, 'tries'>) => void capture.refines.push(job) };
});

beforeEach(() => {
  localStorage.clear();
  capture.discarded = [];
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
    await createNote('groceries', '# Groceries\n\n- Eggs');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Oat milk too.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('Oat milk too.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(onFinish.mock.calls[0]?.[0]).toMatchObject({ id: 'groceries', body: '# Groceries\n\n- Eggs\n\nOat milk too.' });
    expect((await listNotes()).map((note) => note.body)).toEqual(['# Groceries\n\n- Eggs\n\nOat milk too.']);
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

  it('carries on in a new note from New note, leaving what was said so far where it was said', async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'For the soup. Call Sam.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('For the soup.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'New note' }));
    await screen.findByRole('button', { name: 'New note' });
    await waitFor(async () => expect((await listNotes()).find((note) => note.id === 'groceries')?.body).toBe('# Groceries\n\n- Eggs\n\nFor the soup.'));
    await say('Call Sam.', 3000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    const bodies = (await listNotes()).map((note) => note.body).sort();
    expect(bodies).toEqual(['# Call Sam', '# Groceries\n\n- Eggs\n\nFor the soup.']);
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
    await waitFor(async () => expect((await getNote('groceries'))?.body).toBe('# Groceries\n\n- Eggs\n\nFor the soup.'));
    await say('Call Sam.', 3000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));

    const made = onFinish.mock.calls[0]?.[0] as { id: string };
    expect(made.id).not.toBe('groceries');
    expect(stop).toHaveBeenCalledWith({ recordAs: made.id, append: false });
    expect((await getNote(made.id))?.segments).toEqual([{ text: 'Call Sam.', startMs: 3000, endMs: 3900 }]);
    // The stretch said for the soup went to Groceries as words: the better words over this tape must not write it again.
    expect(capture.refines[0]).toMatchObject({ id: made.id, fromMs: 0, titled: true, skip: [{ startMs: 0, endMs: 900 }] });
    // The continued note's own tape is as it was.
    expect(await getNote('groceries')).toMatchObject({ recordingMs: 30_000, segments: [eggs] });
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
});
