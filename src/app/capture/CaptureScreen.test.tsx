import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createNote, getNote, listNotes, noteTitle, setNoteRecording, updateNote } from '../core/store.ts';
import { setTapeId, tapeId } from '../core/clips.ts';
import { setPreferences } from '../core/preferences.ts';
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
  /** Held, the notes a command can name are not read until it is let go (core/store.ts `listNotes`). */
  notesHeld: null as Promise<void> | null,
}));

vi.mock('../core/store.ts', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../core/store.ts')>();
  return {
    ...actual,
    listNotes: vi.fn(async (...args: Parameters<typeof actual.listNotes>) => {
      if (capture.notesHeld) await capture.notesHeld;
      return actual.listNotes(...args);
    }),
  };
});

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
/** The summaries asked for at Done (ai/summaries.ts `enqueueSummary`). */
const summaries = vi.hoisted(() => ({ asked: [] as [string, string][] }));
vi.mock('../ai/summaries.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../ai/summaries.ts')>()),
  enqueueSummary: (id: string, kind: string) => void summaries.asked.push([id, kind]),
}));

beforeEach(() => {
  localStorage.clear();
  capture.discarded = [];
  capture.reassigned = [];
  capture.refines = [];
  summaries.asked = [];
  capture.notesHeld = null;
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

    // A minute on, well past the twenty seconds a spoken question was once given, and ticked through.
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

  it('keeps each place the card showed as one item when it is confirmed', async () => {
    await createNote('go', '# Go\n');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Add to my note labeled Go a list with Parkersburg West Virginia and Marietta Ohio.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    const card = await screen.findByRole('region', { name: 'Add to Go' });
    fireEvent.click(within(card).getByRole('button', { name: 'Add' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('go'))?.body).toBe('# Go\n\n- Parkersburg, West Virginia\n- Marietta, Ohio\n');
  });

  it('makes the new list a confirmed card offered, with its items, and opens it', async () => {
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Make a new list called comic books with Batman and Superman.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    const card = await screen.findByRole('region', { name: 'Create Comic Books' });
    expect(await listNotes()).toEqual([]);
    fireEvent.click(within(card).getByRole('button', { name: 'Create' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    const notes = await listNotes();
    expect(notes.map((note) => note.body)).toEqual(['Comic Books\n\n- Batman\n- Superman\n']);
    const [saved, locked, , , landing] = onFinish.mock.calls[0]!;
    expect(saved).toMatchObject({ id: notes[0]!.id });
    expect(locked).toBe(false);
    expect(landing).toMatchObject({ noteId: notes[0]!.id, title: 'Comic Books', blocks: [], made: [notes[0]!.id] });
  });
});

describe('things to say', () => {
  it('shows the card until the first words, naming one of their notes and no ask on a new recording, then tips one at a time', async () => {
    await createNote('groceries', 'Groceries');
    render(<CaptureScreen fromAssistant={false} onFinish={vi.fn()} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    const card = await screen.findByLabelText('Things to say');
    // The command said bare (docs/DESIGN.md §136): no "Hey Ghost" before it.
    await waitFor(() => expect(card.textContent).toContain('Add … to Groceries'));
    expect(card.textContent).not.toMatch(/Hey Ghost/);
    expect(card.textContent).toContain('Bullet point');
    // A new recording is not a note yet: an ask said into it would not run, so none is offered.
    expect(card.textContent).not.toContain('Fix the spelling');
    act(() => capture.handlers!.onSegment({ text: 'Milk and eggs', startMs: 0, endMs: 900 }));
    await waitFor(() => expect(screen.queryByLabelText('Things to say')).toBeNull());
  });

  it('offers the asks on a note’s own Speak, and never names that note as somewhere to send the take', async () => {
    await createNote('groceries', 'Groceries');
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={vi.fn()} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    const card = await screen.findByLabelText('Things to say');
    await waitFor(() => expect(card.textContent).toContain('Fix the spelling'));
    expect(card.textContent).not.toContain('to Groceries');
    expect(card.textContent).toContain('Make a list called');
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

  // Without the keyword a run is the whole phrase and nothing more (docs/DESIGN.md §136): a sentence that opens with
  // one is the note's words, where it let the recording go and rewrote the note.
  it('appends a sentence that opens with a run’s words, said without the keyword, and runs nothing', async () => {
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: null });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="daily" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Fix the spelling of Kowalski on the sign.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(onFinish.mock.calls[0]?.[3]).toBeUndefined();
    expect((await getNote('daily'))?.body).toBe('# Daily Life\n\nWent for a walk.\n\nFix the spelling of Kowalski on the sign.');
  });

  // What the live reader's gate kept as words is words at Done too (docs/DESIGN.md §136): no card offers to send them
  // to a note called Work, whose Cancel would let the recording go.
  it('appends a sentence the live reader kept as words, said without the keyword, and offers no card at Done', async () => {
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    await createNote('work', '# Work\n\nNotes.');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: null });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="daily" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Add call the plumber to work.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(screen.queryByRole('region', { name: 'Add to Work' })).toBeNull();
    expect((await getNote('daily'))?.body).toBe('# Daily Life\n\nWent for a walk.\n\nAdd call the plumber to work.');
    expect((await getNote('work'))?.body).toBe('# Work\n\nNotes.');
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

  it('lays out a switched-on plugin’s formatting when it is said, as bold is', async () => {
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'The gate code is spoiler four four one seven end spoiler.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('The gate code is spoiler four four one seven end spoiler.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body)).toEqual([expect.stringContaining('||four four one seven||')]);
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

  it('saves an ask a new recording cannot carry out as a note of its words, without the keyword, and says why', async () => {
    capture.session!.stop = async () => ({ recordedMs: null, transcript: null });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('Hey Ghost, make a book called trips.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body)).toEqual(['# Make a book called trips']);
    expect(screen.getByText(/isn't something a recording can do, so the words are saved as a note/)).toBeInTheDocument();
  });

  // Changed on purpose (docs/DESIGN.md §136): a person who did not say the keyword did not say it was a command, so
  // the words are saved as the note, the reason set on the recorder's line, where nothing was saved. (After the keyword
  // the live reader keeps the words with its own chip, "No note called “shopping”, so the words stay here", as it did.)
  // The line is set as the recorder saves and closes, so it is not held long enough to read yet: §136's question 8.
  it('saves a bare command that names no note as its words, with the reason', async () => {
    await createNote('work', 'Work');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Add to shopping, oat milk.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('Add to shopping, oat milk.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(onFinish.mock.calls[0]?.[0]).toMatchObject({ body: '# Add to shopping, oat milk' });
    expect((await listNotes()).map((note) => note.body).sort()).toEqual(['# Add to shopping, oat milk', 'Work']);
    expect(screen.getByText('No note called “shopping”, so the words are saved as a note.')).toBeInTheDocument();
  });

  // A sentence the live reader's gate kept as words opens a fresh recording: at Done it is the note, never a card for a
  // note called Bowl whose Cancel would let the recording go (docs/DESIGN.md §136).
  it('saves a fresh recording that opens with a sentence the gate kept as words, with no card', async () => {
    await createNote('bowl', '# Bowl\n\nBlue.');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Add the flour to the bowl. Then stir it for a minute.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('Add the flour to the bowl.', 0);
    await say('Then stir it for a minute.', 1000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(screen.queryByRole('region', { name: 'Add to Bowl' })).toBeNull();
    expect((await getNote('bowl'))?.body).toBe('# Bowl\n\nBlue.');
    expect((await listNotes()).map((note) => note.body).sort()).toEqual(['# Add the flour to the bowl\n\nThen stir it for a minute.', '# Bowl\n\nBlue.']);
  });

  // After the keyword it was said to be a command: the live reader keeps its words here with its own chip, as it did.
  it('keeps a keyworded command that names no note as its words, with the live reader’s chip', async () => {
    await createNote('work', 'Work');
    capture.session!.stop = async () => ({ recordedMs: null, transcript: 'Hey Ghost, add to shopping, oat milk.' });
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say('Hey Ghost, add to shopping, oat milk.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body).sort()).toEqual(['# Oat milk', 'Work']);
    expect(screen.getByText('No note called “shopping”, so the words stay here.')).toBeInTheDocument();
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
    setTapeId('groceries', 'earlier');
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
      keywordAt: [],
    });
    // The same tape, so the voice memos already in the note play against it still (core/clips.ts).
    expect(tapeId('groceries')).toBe('earlier');
  });

  it('marks a phrase of words and then the keyword for the better words, on the tape’s timeline', async () => {
    await taped();
    await createNote('work', '# Work\n\n- Email Jo');
    keeping(33_000, null);
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('The heating is fixed, hey Ghost, add call Sam to Work.', 1000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));

    expect((await getNote('work'))?.body).toContain('- Call Sam');
    expect(capture.refines).toHaveLength(1);
    expect(capture.refines[0]).toMatchObject({ id: 'groceries', fromMs: 30_000, keywordAt: [{ startMs: 31_000, endMs: 31_900 }] });
  });

  it('runs no review for a take over three minutes, says why at Done, and asks for its summary only when Settings says so', async () => {
    window.history.replaceState({}, '', '/?review');
    try {
      keeping(200_000, null);
      let onFinish = vi.fn();
      render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
      await waitFor(() => expect(capture.handlers).not.toBeNull());
      await say('A long meeting about the launch.', 1000);
      fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
      await screen.findByText('Long recording. The better words come later.');
      expect(onFinish).not.toHaveBeenCalled();
      await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1), { timeout: 4000 });
      // No review, and the better words from the queue instead.
      expect(onFinish.mock.calls[0]?.[2]).toBeUndefined();
      expect(capture.refines).toHaveLength(1);
      expect(summaries.asked).toEqual([]);
      cleanup();

      setPreferences({ summaries: 'long' });
      keeping(200_000, null);
      onFinish = vi.fn();
      render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
      await waitFor(() => expect(capture.handlers).not.toBeNull());
      await say('A long meeting about the launch.', 1000);
      fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
      await screen.findByText('Long recording. The better words come later. The summary comes later.');
      await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1), { timeout: 4000 });
      expect(summaries.asked).toEqual([[onFinish.mock.calls[0]?.[0].id, 'recording']]);
      cleanup();

      // A short take keeps its review, and is never summarized on its own.
      keeping(20_000, null);
      onFinish = vi.fn();
      render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
      await waitFor(() => expect(capture.handlers).not.toBeNull());
      await say('A short note.', 1000);
      fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
      await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
      expect(onFinish.mock.calls[0]?.[2]).toMatchObject({ noteId: onFinish.mock.calls[0]?.[0].id });
      expect(summaries.asked).toHaveLength(1);
    } finally {
      setPreferences({ summaries: 'meetings' });
      window.history.replaceState({}, '', '/');
    }
  });

  it('starts the file afresh on a note whose recording was removed, rather than playing after the removed sound', async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    await setNoteRecording('groceries', 0, []);
    setTapeId('groceries', 'removed');
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
    // A new tape, so a voice memo left from the removed one does not play against this sound.
    expect(tapeId('groceries')).not.toBe('removed');
    expect(tapeId('groceries')).not.toBeNull();
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

  // A table for a note there is none of: the one command the live reader leaves alone that the reader at Done
  // refuses (a bare "add to the camping list eggs and milk" is the note's words now, §136).
  it('stays on a continued note’s tape when what was said into it is a command that is refused', async () => {
    const { onFinish } = await intoGroceries('Hey Ghost, add a table to the camping list.');
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

  it('keeps a phrase taken back out of the tape’s words and marks its stretch for the better words, the sound kept', async () => {
    await taped();
    keeping(36_000, null);
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} noteId="groceries" onFinish={onFinish} />);
    await screen.findByRole('button', { name: 'Adding to “Groceries”' });
    await say('For the soup.', 1000);
    await say('Oat milk too.', 2500);
    await say('Scratch that.', 4000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));

    const stored = await getNote('groceries');
    expect(stored?.body).toBe('# Groceries\n\n- Eggs\n- For the soup');
    expect(stored?.recordingMs).toBe(36_000);
    expect(stored?.segments).toEqual([eggs, { text: 'For the soup.', startMs: 31_000, endMs: 31_900 }]);
    expect(capture.refines).toHaveLength(1);
    expect(capture.refines[0]).toMatchObject({
      id: 'groceries',
      fromMs: 30_000,
      // The phrase that went, and the take-back itself: replaced by the live phrases inside them, which is none.
      skip: [
        { startMs: 32_500, endMs: 33_400 },
        { startMs: 34_000, endMs: 34_900 },
      ],
      live: [{ text: 'For the soup.', startMs: 31_000, endMs: 31_900 }],
    });
  });

  it('reads a take-back only the stop heard, and names it in the note’s toast', async () => {
    await createNote('house', '# House TODOs\n\n- [ ] Fix the gutter\n');
    keeping(4000, "Hey Ghost, add a note to house to do's. Call Sam. Buy fuses. Scratch that.");
    const onFinish = vi.fn();
    render(<CaptureScreen fromAssistant={false} onFinish={onFinish} />);
    await waitFor(() => expect(capture.handlers).not.toBeNull());
    await say("Hey Ghost, add a note to house to do's.", 0);
    await say('Call Sam.', 1000);
    await say('Buy fuses.', 2000);
    fireEvent.click(screen.getByRole('button', { name: 'Stop and save' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
    const [saved, , , , landing] = onFinish.mock.calls[0]!;
    expect(saved).toMatchObject({ id: 'house', segments: [{ text: 'Call Sam.', startMs: 1000, endMs: 1900 }] });
    expect(landing).toMatchObject({ noteId: 'house', blocks: ['- [ ] Call Sam'], tookBack: ['Buy fuses'] });
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
    // What is being said for it shows in the chip, not on the page, until it is committed.
    act(() => capture.handlers!.onPartial('The note is call'));
    expect(document.body.textContent).toContain('House TODOs: The note is call');
    expect(page()).not.toContain('The note is call');
    await say('The note is call an electrician to fix the light sockets.', 1500);
    await waitFor(() => expect(page()).toContain('Call an electrician to fix the light sockets'));
    expect(page()).not.toContain('The note is');
    // Drawn into the list, the line under the gutter, not on the note's end.
    const lines = [...document.querySelectorAll('.cm-line')].map((line) => line.textContent ?? '');
    const gutter = lines.findIndex((line) => line.includes('Fix the gutter'));
    expect(lines[gutter + 1]).toContain('Call an electrician to fix the light sockets');
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
    cleanup();

    await createNote('house', HOUSE);
    const routed = await recording();
    await say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
    await say('Hey Ghost, fix the spelling.', 1000);
    await screen.findByText("That can't run in the middle of a recording, so it was left out.");
    done();
    await waitFor(() => expect(routed).toHaveBeenCalledTimes(1));
    expect(routed.mock.calls[0]?.[3]).toBeUndefined();
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
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
      // The command, and the phrase its words were read from: the better words put the live words there.
      skip: [
        { startMs: 0, endMs: 900 },
        { startMs: 1500, endMs: 2400 },
      ],
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
  it('runs no review for a take written into a note that was there, and does for a new one', async () => {
    window.history.replaceState({}, '', '/?review');
    try {
      await createNote('house', HOUSE);
      const routed = await recording();
      await say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      await screen.findByRole('button', { name: 'Adding to “House TODOs”' });
      done();
      await waitFor(() => expect(routed).toHaveBeenCalledTimes(1));
      expect(routed.mock.calls[0]?.[0]).toMatchObject({ id: 'house' });
      expect(routed.mock.calls[0]?.[2]).toBeUndefined();
      cleanup();

      const fresh = await recording();
      await say('Buy milk.', 0);
      done();
      await waitFor(() => expect(fresh).toHaveBeenCalledTimes(1));
      expect(fresh.mock.calls[0]?.[2]).toMatchObject({ noteId: fresh.mock.calls[0]?.[0].id });
    } finally {
      window.history.replaceState({}, '', '/');
    }
  });

  it('keeps words in the order they were said when a card settles after later ones', async () => {
    await createNote('s1', '# Signing in, and signing');
    await createNote('s2', '# Signing the order');
    const onFinish = await recording();
    await say('Kevin owns the release.', 0);
    await say('Hey Ghost, add call Jo to signing.', 1000);
    await screen.findByRole('region', { name: 'Add to which note?' });
    await say('The budget review is Friday.', 2000);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(onFinish.mock.calls[0]?.[0].body).toBe('# Kevin owns the release\n\nCall Jo. The budget review is Friday.');
  });

  it('sends the words said since a card mid-take to the note chosen on it, out of the take', async () => {
    await createNote('s1', '# Signing in, and signing');
    await createNote('s2', '# Signing the order');
    const onFinish = await recording();
    await say('Kevin owns the release.', 0);
    await say('Hey Ghost, add a note to signing;', 1000);
    const card = await screen.findByRole('region', { name: 'Add to which note?' });
    await say('Check the form.', 2000);
    fireEvent.click(within(card).getByRole('button', { name: 'Signing the order' }));
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('s2'))?.body).toBe('# Signing the order\n\nCheck the form.');
    expect(onFinish.mock.calls[0]?.[0].body).toBe('# Kevin owns the release');
  });

  it('takes a one-shot back into the take on its own Not this note', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say('Kevin owns the release.', 0);
    await say('Hey Ghost, add call Sam to House TODOs.', 1000);
    const landing = await screen.findByLabelText('Added to House TODOs');
    fireEvent.click(within(landing).getByRole('button', { name: 'Not this note' }));
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe(HOUSE);
    expect(onFinish.mock.calls[0]?.[0].body).toBe('# Kevin owns the release\n\nCall Sam.');
  });

  /**
   * Matt: "Id like sentences to be able to redact" (docs/DESIGN.md §130). The last thing said goes back into smoke,
   * the chip says what went with Undo, and "scratch that" never flashes onto the page while it is said.
   */
  it('takes the last sentence back into smoke, with Undo in the chip that puts it back and writes the words', async () => {
    const onFinish = await recording();
    await say('Eggs.', 0);
    await say('Call Sam.', 1000);
    await waitFor(() => expect(page()).toContain('Call Sam'));
    act(() => capture.handlers!.onPartial('Scratch'));
    expect(page()).not.toContain('Scratch');
    // Nor when the opener comes after words, which stay on the page while it is said.
    act(() => capture.handlers!.onPartial('The meeting is at three, scratch tha'));
    expect(page()).toContain('The meeting is at three');
    expect(page()).not.toContain('scratch');
    await say('Scratch that.', 2000);
    await waitFor(() => expect(page()).not.toContain('Call Sam'));
    expect(page()).not.toContain('Scratch');
    expect(screen.getByText(/Took back “Call Sam”/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Undo' }));
    await waitFor(() => expect(page()).toContain('Call Sam'));
    expect(page()).toContain('Scratch that.');
    expect(screen.queryByRole('button', { name: 'Undo' })).toBeNull();
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(onFinish.mock.calls[0]?.[0].body).toBe('# Eggs\n\nCall Sam. Scratch that.');
  });

  it('says there is nothing to take back after New note is tapped', async () => {
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    await recording({ noteId: 'daily' });
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Went for a run.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'New note' }));
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Adding to “Daily Life”' })).toBeNull());
    await say('Scratch that.', 1000);
    await screen.findByText('Nothing to take back.');
  });

  it('sends the sentence taken back to the note named, written at Done, and says what it took back at Done', async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    const onFinish = await recording();
    await say('Kevin owns the release.', 0);
    await say('Oat milk.', 1000);
    await say('Scratch that, add it to groceries instead.', 2000);
    await waitFor(() => expect(page()).not.toContain('Oat milk'));
    expect(screen.getByText(/Sent “Oat milk” to/)).toBeInTheDocument();
    expect((await getNote('groceries'))?.body).toBe('# Groceries\n\n- Eggs');
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('groceries'))?.body).toBe('# Groceries\n\n- Eggs\n- Oat milk');
    const [saved, , , , landing] = onFinish.mock.calls[0]!;
    expect(saved.body).toBe('# Kevin owns the release');
    expect(landing).toMatchObject({ noteId: saved.id, others: [expect.any(String)], into: ['Groceries'], tookBack: ['Oat milk'] });
  });

  it('empties a one-shot of the enumeration taken back, so Done leaves the note as it was', async () => {
    await createNote('groceries', '# Groceries\n\n- Eggs');
    const onFinish = await recording();
    await say('Kevin owns the release.', 0);
    await say('Hey Ghost, add milk, bread and butter to groceries.', 1000);
    await say('Scratch that.', 2000);
    expect(screen.getByText(/Took back “milk, bread, butter”/)).toBeInTheDocument();
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('groceries'))?.body).toBe('# Groceries\n\n- Eggs');
    expect(onFinish.mock.calls[0]?.[0].body).toBe('# Kevin owns the release');
  });

  it('still reads a command left for the reader at Done, over the phrases as the take kept them', async () => {
    const onFinish = await recording();
    await say('Hey Ghost, make a list called packing with sunscreen and towels.', 0);
    await say('Bin bags.', 1000);
    await say('Scratch that.', 2000);
    done();
    const card = await screen.findByRole('region', { name: 'Create Packing' });
    expect(card.textContent).toContain('sunscreen');
    expect(card.textContent).not.toContain('Bin bags');
    fireEvent.click(within(card).getByRole('button', { name: 'Create' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body)).toEqual(['Packing\n\n- Sunscreen\n- Towels\n']);
  });

  it('reads a phrase said before the notes were read once they are', async () => {
    await createNote('house', HOUSE);
    let letGo = () => undefined as void;
    capture.notesHeld = new Promise<void>((resolve) => (letGo = resolve));
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
    expect(screen.queryByRole('button', { name: 'Adding to “House TODOs”' })).toBeNull();
    await act(async () => letGo());
    await screen.findByRole('button', { name: 'Adding to “House TODOs”' });
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
  });

  it('stores nothing on Discard after New note, the part before it included', async () => {
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    const onFinish = await recording({ noteId: 'daily' });
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Went for a run.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'New note' }));
    await say('Call Sam.', 1000);
    fireEvent.click(screen.getByRole('button', { name: 'Discard' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false));
    expect((await listNotes()).map((note) => note.body)).toEqual(['# Daily Life\n\nWent for a walk.']);
  });

  it('never writes a shared note over the lock screen', async () => {
    (window as { GlyphHost?: unknown }).GlyphHost = { isLocked: () => true, endCapture: () => undefined, setCapturing: () => false };
    setPreferences({ shares: { house: { id: 'shared-house', key: 'key', sent: '' } } });
    try {
      await createNote('house', HOUSE);
      const onFinish = await recording();
      await say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      await screen.findByText('That note is shared, so the words stay here.');
      done();
      await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
      expect((await getNote('house'))?.body).toBe(HOUSE);
      expect((await listNotes()).map((note) => note.body).sort()).toEqual(['# Call Sam', HOUSE]);
    } finally {
      setPreferences({ shares: {} });
    }
  });

  it('offers no book on a card, and never writes into one', async () => {
    await createNote('b1', bookNoteBody('HelloTrade: The Book', ['Intro']));
    await createNote('b2', bookNoteBody('HelloTrade — The Book', ['From tap to fill']));
    await createNote('guide', '# HelloTrade: Frontend Developer Guide\n');
    const onFinish = await recording();
    await say('Hey Ghost, add a note to hello trade the book, check the glossary.', 0);
    await screen.findByText('“HelloTrade — The Book” is a book, so the words stay here.');
    expect(screen.queryByRole('region', { name: 'Add to which note?' })).toBeNull();
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('b1'))?.body).toBe(bookNoteBody('HelloTrade: The Book', ['Intro']));
    expect((await getNote('b2'))?.body).toBe(bookNoteBody('HelloTrade — The Book', ['From tap to fill']));
    expect(onFinish.mock.calls[0]?.[0].body).toBe('# Check the glossary');
  });

  it('carries out a second command said while the first waits for its name', async () => {
    await createNote('s1', '# Signing in, and signing');
    await createNote('s2', '# Signing the order');
    await createNote('groceries', '# Groceries\n\n- Eggs\n');
    const onFinish = await recording();
    await say('Kevin owns the release.', 0);
    await say('Hey Ghost, add to signing.', 1000);
    await say('Hey Ghost, add milk to groceries.', 2000);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('groceries'))?.body).toBe('# Groceries\n\n- Eggs\n- Milk\n');
    expect(onFinish.mock.calls[0]?.[0].body).toBe('# Kevin owns the release');
  });

  it('keeps how people talk as words, where a mishearing of the keyword starts it', async () => {
    await createNote('post', "# It's post");
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    const fresh = await recording();
    await say('Hey, like, put the parcel in the post.', 0);
    await say('Then I went home.', 1000);
    done();
    await waitFor(() => expect(fresh).toHaveBeenCalledTimes(1));
    expect((await getNote('post'))?.body).toBe("# It's post");
    expect(fresh.mock.calls[0]?.[0].body).toBe('Hey, like, put the parcel in the post. Then I went home.');
    cleanup();

    const own = await recording({ noteId: 'daily' });
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Okay, like, make sure the door is locked.', 0);
    done();
    await waitFor(() => expect(own).toHaveBeenCalledTimes(1));
    expect(own.mock.calls[0]?.[3]).toBeUndefined();
    expect((await getNote('daily'))?.body).toBe('# Daily Life\n\nWent for a walk.\n\nOkay, like, make sure the door is locked.');
  });

  it('queues a keyworded ask the take opened with once a later command is carried out, and never saves it as words', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say('Hey Ghost, fix the spelling.', 0);
    await say('Buy milk.', 1000);
    await say('Hey Ghost, add call Sam to House TODOs.', 2000);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
    const [saved, , , ask] = onFinish.mock.calls[0]!;
    expect(saved.body).toBe('# Buy milk');
    expect(ask).toEqual({ kind: 'fix' });
  });

  it('writes what is said after a second command into the note it named, not the first', async () => {
    await createNote('house', HOUSE);
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's.", 0);
    await say('Hey Ghost, add a note to daily life.', 1000);
    await say('Went for a run.', 2000);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await getNote('house'))?.body).toBe(HOUSE);
    expect((await getNote('daily'))?.body).toBe('# Daily Life\n\nWent for a walk.\n\nWent for a run.');
  });

  it('keeps every word of a name that matched nothing on Keep here', async () => {
    const onFinish = await recording();
    await say('Hey Ghost, add a note to moon base pack sunscreen and the tent.', 0);
    await screen.findByRole('region', { name: /^No note called/ });
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(onFinish.mock.calls[0]?.[0].body).toBe('Moon base pack sunscreen and the tent.');
  });

  it('hands the better words a card’s new note under its title', async () => {
    capture.session!.keepsAudio = true;
    capture.session!.stop = async () => ({ recordedMs: 3000, transcript: null });
    const onFinish = await recording();
    await say('Hey Ghost, add a note to the moon base.', 0);
    const card = await screen.findByRole('region', { name: 'No note called “moon base”' });
    fireEvent.click(within(card).getByRole('button', { name: 'New note “Moon base”' }));
    await say('Call Sam.', 1000);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(capture.refines[0]).toMatchObject({ baseBody: 'Moon base', savedBody: 'Moon base\n\nCall Sam.', titled: false });
  });

  it('keeps the better words of the take’s own note when a one-shot from it is undone', async () => {
    await createNote('house', HOUSE);
    capture.session!.keepsAudio = true;
    capture.session!.stop = async () => ({ recordedMs: 3000, transcript: null });
    const onFinish = await recording();
    await say('Kevin owns the release.', 0);
    await say('Hey Ghost, add call Sam to House TODOs.', 1000);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    const landing = onFinish.mock.calls[0]?.[4];
    expect(landing).toMatchObject({ blocks: [], others: [expect.any(String)] });
    expect(landing?.fromMs).toBeUndefined();
  });

  it('says why nothing was added to a note named with nothing said for it, long enough to be read', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say("Hey Ghost, add a note to house to do's.", 0);
    done();
    await screen.findByText('Nothing was said for House TODOs, so nothing was added.');
    expect(onFinish).not.toHaveBeenCalled();
    await waitFor(() => expect(onFinish).toHaveBeenCalledWith(null, false), { timeout: 3000 });
    expect((await getNote('house'))?.body).toBe(HOUSE);
  });
  it('reads only what was said after New note at Done, and writes what came before it first', async () => {
    await createNote('daily', '# Daily Life\n\nWent for a walk.');
    await createNote('groceries', '# Groceries\n\n- Eggs\n');
    const onFinish = await recording({ noteId: 'daily' });
    await screen.findByRole('button', { name: 'Adding to “Daily Life”' });
    await say('Kevin owns the release on Friday.', 0);
    fireEvent.click(screen.getByRole('button', { name: 'New note' }));
    // A new list by name is the reader at Done's ("add oat milk to groceries" would be carried out as it is said, §136).
    await say('Make a new list called packing with tent and stove.', 1000);
    done();
    const card = await screen.findByRole('region', { name: 'Create Packing' });
    expect(card.textContent).not.toMatch(/Kevin/);
    expect((await getNote('daily'))?.body).toBe('# Daily Life\n\nWent for a walk.\n\nKevin owns the release on Friday.');
    fireEvent.click(within(card).getByRole('button', { name: 'Create' }));
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect((await listNotes()).map((note) => note.body)).toContainEqual(expect.stringMatching(/^Packing\n\n- Tent\n- Stove/));
  });

  // A command needs no keyword (docs/DESIGN.md §136): said plainly at the start, it is carried out as it is said.
  it('switches to House TODOs for a command said without the keyword, writes the item live, and makes no note', async () => {
    await createNote('house', HOUSE);
    const onFinish = await recording();
    await say('Add call Sam to House TODOs.', 0);
    await screen.findByRole('button', { name: 'Adding to “House TODOs”' });
    await waitFor(() => expect(page()).toContain('Call Sam'));
    expect((await getNote('house'))?.body).toBe(HOUSE);
    done();
    await waitFor(() => expect(onFinish).toHaveBeenCalledTimes(1));
    expect(screen.queryByRole('region', { name: /^Add to/ })).toBeNull();
    expect((await listNotes()).map((note) => note.body)).toEqual(['# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n']);
    expect(onFinish.mock.calls[0]?.[0]).toMatchObject({ id: 'house' });
  });
});
