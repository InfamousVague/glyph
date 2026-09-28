import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import type { Output, RunOptions } from '../core/ai.ts';
import type { Segment } from '../capture/markdown.ts';
import { aiChanges } from '../editor/aiChanges.ts';
import type { SummaryJob } from './summaries.ts';

/**
 * The summary queue (ai/summaries.ts): what it writes and where, the holds it waits behind, what the recorder does to
 * a run in flight and what a person's Stop does, how a job fails and is tried again, the pieces of a long recording,
 * and the hand-off to an open note's editor - including a note opened while the model wrote. The model is a fake
 * that answers when the test says so, the bridge a stand-in for the note store, the better-words queue a pair of
 * flags, and the clock a fake one.
 */

let native = true;
const notes = new Map<string, { id: string; body: string; revision: number; recordingMs: number; segments: Segment[] }>();
const invoked: { command: string; args: Record<string, unknown> }[] = [];
const invoke = vi.fn(async (command: string, args: Record<string, unknown> = {}) => {
  invoked.push({ command, args });
  switch (command) {
    case 'get_note':
      return notes.get(args.id as string) ?? null;
    case 'update_note': {
      const was = notes.get(args.id as string);
      if (!was || was.revision !== args.expectedRevision) throw new Error('the note was deleted or changed');
      const note = { ...was, body: args.body as string, revision: was.revision + 1 };
      notes.set(note.id, note);
      return note;
    }
    default:
      throw new Error(`no answer for ${command}`);
  }
});
vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke }));

/** The model: each generation asked for, answered by the test. */
const fakes: { options: RunOptions; finish: (text: string) => void; fail: (message: string) => void; cancelled: boolean }[] = [];
let present: string[] = ['qwen3.5-4b'];
vi.mock('../core/ai.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/ai.ts')>();
  return {
    ...real,
    listModels: async () => real.MODELS.map((m) => ({ id: m.id, file: '', bytes: m.bytes, present: present.includes(m.id), path: '' })),
    generate: (options: RunOptions) => {
      let resolve: (output: Output) => void = () => undefined;
      let reject: (failure: Error) => void = () => undefined;
      const done = new Promise<Output>((res, rej) => {
        resolve = res;
        reject = rej;
      });
      const fake = {
        options,
        cancelled: false,
        finish: (text: string) => resolve({ text, promptTokens: 10, outputTokens: 10, ms: 100, cachedTokens: 0, prefillMs: 1, loadMs: 1, tokensPerSecond: 10, truncated: false }),
        fail: (message: string) => reject(new Error(message)),
      };
      fakes.push(fake);
      return {
        done,
        cancel: () => {
          fake.cancelled = true;
          reject(new Error('cancelled'));
        },
      };
    },
  };
});

/** The better-words queue: whether the recorder is up, which notes still wait for their words, and who follows the hold. */
const refine = vi.hoisted(() => ({ held: false, pending: new Set<string>(), listeners: new Set<(on: boolean) => void>() }));
vi.mock('../capture/refine.ts', () => ({
  refineHeld: () => refine.held,
  refinePending: (id: string) => refine.pending.has(id),
  onRefineHold: (listener: (on: boolean) => void) => {
    refine.listeners.add(listener);
    return () => refine.listeners.delete(listener);
  },
}));
const hold = (on: boolean) => {
  refine.held = on;
  refine.listeners.forEach((l) => l(on));
};
const synced = vi.hoisted(() => ({ now: vi.fn(async () => undefined), settled: vi.fn(async () => undefined) }));
vi.mock('../core/sync/engine.ts', () => ({ syncNow: synced.now, syncSettled: () => synced.settled() }));

/** The phone's own write-ups (core/recordings.ts): the result each left, the state each is in, and whether the phone may notify. */
const phone = vi.hoisted(() => ({ results: new Map<string, unknown>(), states: [] as unknown[], taken: [] as string[], canNotify: true }));
vi.mock('../core/recordings.ts', () => ({
  takeRecordingResult: async (id: string) => {
    phone.taken.push(id);
    const result = phone.results.get(id) ?? null;
    phone.results.delete(id);
    return result;
  },
  recordingJobState: async () => phone.states,
}));
vi.mock('../capture/meetingLive.ts', () => ({ canNotifyNow: () => phone.canNotify }));

const { setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const { dropSummary, enqueueSummary, landNativeResult, openForSummaries, pauseSummaries, retrySummary, startSummaries, summariesNow, summaryPending, writeUpNow } = await import('./summaries.ts');
const { readSummary, keepSummary, summaryUnchanged } = await import('./summaryKeep.ts');
const { allLines, cancelRun, forgetAllRuns, runFor, startRun } = await import('./runs.ts');
const { startNoteRun } = await import('./start.ts');
const { Lander } = await import('./land.ts');
const { renderNote } = await import('../capture/markdown.ts');
const { fill, NOTES_CONTEXT, PIECE_CONTEXT, RECORDING_NOTES_PROMPT, RECORDING_SUMMARY_PROMPT } = await import('../format/prompt.ts');
const { ONE_PASS_CHARS, summarySection } = await import('./summaryText.ts');

const QUEUE_KEY = 'glyph-summary-queue';
const queued = (): SummaryJob[] => JSON.parse(localStorage.getItem(QUEUE_KEY) ?? '[]') as SummaryJob[];

const phrases: Segment[] = [
  { text: 'That is the March launch settled.', startMs: 0, endMs: 2000 },
  { text: 'Sam owns the press list.', startMs: 2100, endMs: 4000 },
];
const ANSWER = '# March launch settled\nWhat the call settled.\n\n- Launch is in March.\n- Sam: the press list.\n\n- [ ] Book the venue before the tenth.';
const SECTION = '## Summary\nWhat the call settled.\n\n- Launch is in March.\n- Sam: the press list.\n\n- [ ] Book the venue before the tenth.';

let stop: (() => void) | null = null;
let changed = vi.fn();
let summarized = vi.fn();
const visible = (state: 'visible' | 'hidden') => Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => state });
const tick = (ms = 0) => vi.advanceTimersByTimeAsync(ms);

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
  native = true;
  present = ['qwen3.5-4b'];
  notes.clear();
  invoked.length = 0;
  fakes.length = 0;
  refine.held = false;
  refine.pending.clear();
  synced.now.mockClear();
  synced.settled.mockClear();
  phone.results.clear();
  phone.states = [];
  phone.taken = [];
  phone.canNotify = true;
  delete window.GlyphHost;
  visible('visible');
  notes.set('n1', { id: 'n1', body: '# March launch\n\nThat is the March launch settled. Sam owns the press list.', revision: 1, recordingMs: 4000, segments: phrases });
  changed = vi.fn();
  summarized = vi.fn();
  stop = startSummaries(changed, summarized);
});

afterEach(async () => {
  stop?.();
  pauseSummaries(false);
  openForSummaries('n1', null);
  for (const fake of fakes) fake.fail('over');
  forgetAllRuns();
  await tick(0);
  vi.clearAllTimers();
  vi.useRealTimers();
  Reflect.deleteProperty(document, 'visibilityState');
  setPreferences(DEFAULT_PREFERENCES);
});

describe('a summary of a closed note', () => {
  it('reads the tape, writes the section under the title, keeps what it wrote, refreshes the list and says so', async () => {
    enqueueSummary('n1', 'recording');
    expect(summaryPending('n1')).toBe(true);
    await tick(0);
    expect(fakes).toHaveLength(1);
    expect(fakes[0]!.options.system).toBe(RECORDING_SUMMARY_PROMPT);
    // The tape's words, not the note's.
    expect(fakes[0]!.options.prompt).toBe('That is the March launch settled. Sam owns the press list.');
    expect(fakes[0]!.options.model).toBe('qwen3.5-4b');
    fakes[0]!.finish(ANSWER);
    await tick(0);
    expect(notes.get('n1')?.body).toBe(`# March launch\n\n${SECTION}\n\nThat is the March launch settled. Sam owns the press list.`);
    expect(readSummary('n1')).toMatchObject({ text: SECTION, model: 'qwen3.5-4b', forMs: 4000 });
    expect(queued()).toEqual([]);
    expect(changed).toHaveBeenCalledOnce();
    expect(summarized).toHaveBeenCalledWith({ id: 'n1', title: 'March launch' });
    // Sync before the read and after the write.
    expect(synced.now).toHaveBeenCalledTimes(2);
  });

  it('is asked for only in the app, and never for a note with no words on its tape', async () => {
    native = false;
    enqueueSummary('n1', 'recording');
    expect(queued()).toEqual([]);
    native = true;
    notes.set('n2', { id: 'n2', body: '# Quiet', revision: 1, recordingMs: 900, segments: [] });
    enqueueSummary('n2', 'recording');
    await tick(0);
    expect(fakes).toEqual([]);
    expect(queued()).toEqual([]);
  });

  it('waits behind the note’s better words, and runs once they have come', async () => {
    refine.pending.add('n1');
    enqueueSummary('n1', 'recording');
    await tick(30_000);
    expect(fakes).toEqual([]);
    expect(queued()).toHaveLength(1);
    refine.pending.delete('n1');
    await tick(20_000);
    expect(fakes).toHaveLength(1);
  });

  it('waits three seconds behind a note’s own run', async () => {
    const handle = startRun({ noteId: 'other', kind: 'format', model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 10 });
    enqueueSummary('n1', 'recording');
    await tick(0);
    // The note's own generation was asked for first; the summary's is not.
    expect(fakes).toHaveLength(1);
    fakes[0]!.finish('done');
    await handle.done;
    await tick(3000);
    expect(fakes).toHaveLength(2);
    expect(fakes[1]!.options.system).toBe(RECORDING_SUMMARY_PROMPT);
  });

  it('is cancelled by the recorder and left queued, uncounted, then runs again once the recorder has gone', async () => {
    enqueueSummary('n1', 'recording');
    await tick(0);
    expect(fakes).toHaveLength(1);
    hold(true);
    await tick(0);
    expect(fakes[0]!.cancelled).toBe(true);
    expect(queued()).toEqual([expect.objectContaining({ id: 'n1', tries: 0, started: false })]);
    await tick(60_000);
    expect(fakes).toHaveLength(1);
    hold(false);
    await tick(1500);
    expect(fakes).toHaveLength(2);
  });

  it('counts a job found started at launch as one try, and fails one on its third', async () => {
    stop?.();
    localStorage.setItem(QUEUE_KEY, JSON.stringify([{ id: 'n1', kind: 'recording', tries: 1, started: true }, { id: 'n2', kind: 'recording', tries: 2, started: true }]));
    stop = startSummaries(changed, summarized);
    expect(queued()).toEqual([
      { id: 'n1', kind: 'recording', tries: 2, started: false },
      { id: 'n2', kind: 'recording', tries: 3, started: false, failed: true },
    ]);
  });

  it('waits a minute for a model that is not on the phone, saying so, and runs once one is', async () => {
    present = [];
    enqueueSummary('n1', 'recording');
    await tick(0);
    expect(fakes).toEqual([]);
    expect(summariesNow().needsModel.has('n1')).toBe(true);
    present = ['qwen3.5-2b'];
    await tick(59_999);
    expect(fakes).toEqual([]);
    await tick(1);
    expect(fakes).toHaveLength(1);
    expect(fakes[0]!.options.model).toBe('qwen3.5-2b');
    expect(summariesNow().needsModel.has('n1')).toBe(false);
  });

  it('publishes what the shelf and the strip read: pending while queued and running, failed after three tries, cleared on finish and drop', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    enqueueSummary('n1', 'recording');
    expect(summariesNow().pending.has('n1')).toBe(true);
    await tick(0);
    expect(summariesNow().pending.has('n1')).toBe(true);
    for (let n = 1; n <= 3; n += 1) {
      await tick(n === 1 ? 0 : 20_000);
      fakes[n - 1]!.fail('the model fell over');
      await tick(0);
    }
    expect(summariesNow().failed.has('n1')).toBe(true);
    expect(summariesNow().pending.has('n1')).toBe(false);
    retrySummary('n1');
    expect(summariesNow().failed.has('n1')).toBe(false);
    expect(summariesNow().pending.has('n1')).toBe(true);
    await tick(0);
    fakes[3]!.finish(ANSWER);
    await tick(0);
    expect(summariesNow()).toEqual({ pending: new Set(), native: new Set(), waiting: new Set(), failed: new Set(), needsModel: new Set() });
    enqueueSummary('n1', 'recording', { native: true });
    expect(summariesNow().native.has('n1')).toBe(true);
    dropSummary('n1');
    expect(summariesNow().native.has('n1')).toBe(false);
    warn.mockRestore();
  });

  it('starts nothing once the recorder has come up during the sync wait', async () => {
    let release: () => void = () => undefined;
    synced.settled.mockImplementationOnce(() => new Promise<undefined>((resolve) => (release = () => resolve(undefined))));
    enqueueSummary('n1', 'recording');
    await tick(0);
    expect(fakes).toEqual([]);
    hold(true);
    release();
    await tick(0);
    expect(fakes).toEqual([]);
    expect(queued()).toEqual([expect.objectContaining({ id: 'n1', tries: 0, started: false })]);
    hold(false);
    await tick(1500);
    expect(fakes).toHaveLength(1);
  });

  it('takes the model’s heading as the title of a note still wearing a meeting’s date title', async () => {
    notes.set('n1', { ...notes.get('n1')!, body: '# Meeting, 26 Sep 14:05\n\nWords.' });
    enqueueSummary('n1', 'recording');
    await tick(0);
    fakes[0]!.finish(ANSWER);
    await tick(0);
    expect(notes.get('n1')?.body).toBe(`# March launch settled\n\n${SECTION}\n\nWords.`);
    expect(summarized).toHaveBeenCalledWith({ id: 'n1', title: 'March launch settled' });
  });

  it('holds the write, with the answer kept, when the better words came to be owed between the run and the write', async () => {
    enqueueSummary('n1', 'recording');
    await tick(0);
    refine.pending.add('n1');
    fakes[0]!.finish(ANSWER);
    await tick(0);
    expect(invoked.filter((c) => c.command === 'update_note')).toEqual([]);
    expect(queued()[0]).toMatchObject({ id: 'n1', text: ANSWER, tries: 0 });
    refine.pending.delete('n1');
    await tick(20_000);
    expect(fakes).toHaveLength(1);
    expect(notes.get('n1')?.body).toContain(SECTION);
  });

  it('counts a write that failed for any reason but a conflict as a try, without asking the model again', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const real = invoke.getMockImplementation()!;
    invoke.mockImplementation(async (command, args) => {
      if (command === 'update_note') throw new Error('the disk is full');
      return real(command, args);
    });
    try {
      enqueueSummary('n1', 'recording');
      await tick(0);
      fakes[0]!.finish(ANSWER);
      await tick(0);
      expect(queued()[0]).toMatchObject({ tries: 1, text: ANSWER });
      await tick(20_000);
      await tick(20_000);
      expect(queued()[0]).toMatchObject({ tries: 3, failed: true });
      expect(fakes).toHaveLength(1);
    } finally {
      invoke.mockImplementation(real);
      warn.mockRestore();
    }
  });

  it('gives up after three failures twenty seconds apart, and Try again puts the job back', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    enqueueSummary('n1', 'recording');
    for (let n = 1; n <= 3; n += 1) {
      await tick(n === 1 ? 0 : 20_000);
      expect(fakes).toHaveLength(n);
      fakes[n - 1]!.fail('the model fell over');
      await tick(0);
      expect(queued()[0]?.tries).toBe(n);
    }
    expect(queued()[0]?.failed).toBe(true);
    await tick(120_000);
    expect(fakes).toHaveLength(3);
    retrySummary('n1');
    expect(queued()[0]).toMatchObject({ tries: 0, failed: false });
    await tick(0);
    expect(fakes).toHaveLength(4);
    warn.mockRestore();
  });

  it('waits while the note is in the trash, and drops the job when the note is deleted for good', async () => {
    setPreferences({ trash: { n1: 1 } });
    enqueueSummary('n1', 'recording');
    await tick(60_000);
    expect(fakes).toEqual([]);
    expect(queued()).toHaveLength(1);
    dropSummary('n1');
    expect(queued()).toEqual([]);
    setPreferences({ trash: {} });
    await tick(60_000);
    expect(fakes).toEqual([]);
  });

  it('leaves a native job waiting for its result, and never runs the model for it', async () => {
    enqueueSummary('n1', 'meeting', { native: true });
    await tick(60_000);
    expect(fakes).toEqual([]);
    expect(queued()).toEqual([{ id: 'n1', kind: 'meeting', tries: 0, native: true }]);
  });

  it('starts only while the page is visible, and looks again when it is', async () => {
    visible('hidden');
    enqueueSummary('n1', 'recording');
    await tick(10_000);
    expect(fakes).toEqual([]);
    visible('visible');
    document.dispatchEvent(new Event('visibilitychange'));
    await tick(2000);
    expect(fakes).toHaveLength(1);
  });
});

describe('the section already there', () => {
  const body = (section: string) => `# March launch\n\n${section}\n\nThat is the March launch settled. Sam owns the press list.`;
  const NEXT = '# Launch\nA newer line.\n\n- [ ] Book the venue.';

  it('is replaced whole when it still reads as the app wrote it, its ticked to-dos carried', async () => {
    const old = '## Summary\nThe old line.\n\n- [x] Send Sam the list.\n- [ ] Book the venue.';
    keepSummary('n1', { text: old, model: 'm', at: 1, forMs: 2000 });
    notes.set('n1', { ...notes.get('n1')!, body: body(old) });
    enqueueSummary('n1', 'recording');
    await tick(0);
    fakes[0]!.finish(NEXT);
    await tick(0);
    expect(notes.get('n1')?.body).toBe(body('## Summary\nA newer line.\n\n- [ ] Book the venue.\n- [x] Send Sam the list.'));
  });

  it('is left alone by a job of the queue’s own when the person edited it, and replaced when they asked for that', async () => {
    const edited = '## Summary\nMy own words.\n\n- [ ] Book the venue.';
    keepSummary('n1', { text: '## Summary\nThe old line.\n\n- [ ] Book the venue.', model: 'm', at: 1, forMs: 2000 });
    notes.set('n1', { ...notes.get('n1')!, body: body(edited) });
    enqueueSummary('n1', 'recording');
    await tick(0);
    fakes[0]!.finish(NEXT);
    await tick(0);
    expect(notes.get('n1')?.body).toBe(body(edited));
    expect(queued()).toEqual([]);
    expect(summarized).not.toHaveBeenCalled();

    enqueueSummary('n1', 'recording', { replace: true });
    await tick(500);
    fakes[1]!.finish(NEXT);
    await tick(0);
    expect(notes.get('n1')?.body).toBe(body('## Summary\nA newer line.\n\n- [ ] Book the venue.'));
  });

  it('reads the note again after a conflict and writes once more, then keeps the text for the next pass', async () => {
    let conflicts = 3;
    const real = invoke.getMockImplementation()!;
    invoke.mockImplementation(async (command, args) => {
      if (command === 'update_note' && conflicts > 0) {
        conflicts -= 1;
        throw new Error('the note was changed');
      }
      return real(command, args);
    });
    try {
      enqueueSummary('n1', 'recording');
      await tick(0);
      fakes[0]!.finish(ANSWER);
      await tick(0);
      // Two writes tried this pass, the answer kept on the job, and no model asked again next time.
      expect(conflicts).toBe(1);
      expect(queued()[0]).toMatchObject({ id: 'n1', text: ANSWER, tries: 0 });
      await tick(20_000);
      expect(fakes).toHaveLength(1);
      expect(notes.get('n1')?.body).toContain(SECTION);
      expect(queued()).toEqual([]);
    } finally {
      invoke.mockImplementation(real);
    }
  });
});

describe('a long recording', () => {
  it('goes through the notes prompt in pieces, each checkpointed, and then the summary prompt over the notes', async () => {
    const long: Segment[] = [];
    let at = 0;
    while (long.reduce((n, s) => n + s.text.length + 1, 0) < ONE_PASS_CHARS + 2000) {
      long.push({ text: `Something that was said at ${at}, at some length, to fill the tape.`, startMs: at, endMs: at + 2000 });
      at += 4000;
    }
    notes.set('n1', { ...notes.get('n1')!, segments: long });
    enqueueSummary('n1', 'recording');
    await tick(0);
    expect(fakes).toHaveLength(1);
    expect(fakes[0]!.options.system).toBe(RECORDING_NOTES_PROMPT);
    expect(fakes[0]!.options.prompt.startsWith(`${fill(PIECE_CONTEXT, { n: 1, m: 2 })}\n\n`)).toBe(true);
    expect(fakes[0]!.options.prompt.startsWith('Part 1 of 2 of one recording.\n\n')).toBe(true);
    // The recorder up as the first piece ends: the next piece waits for it to go, the finished one kept.
    fakes[0]!.finish('- The first half.');
    hold(true);
    await tick(0);
    expect(queued()[0]?.pieces).toEqual(['- The first half.']);
    expect(fakes).toHaveLength(1);
    hold(false);
    await tick(1500);
    expect(fakes[1]!.options.prompt.startsWith(`${fill(PIECE_CONTEXT, { n: 2, m: 2 })}\n\n`)).toBe(true);
    fakes[1]!.finish('- The second half.\n- [ ] Book the venue.');
    await tick(0);
    expect(fakes[2]!.options.system).toBe(RECORDING_SUMMARY_PROMPT);
    const words = renderNote(long).plain.split(/\s+/).filter(Boolean).length;
    const parts = fill(NOTES_CONTEXT, { words: words.toLocaleString('en') });
    expect(fakes[2]!.options.prompt).toBe(`${parts}\n\n- The first half.\n\n- The second half.\n- [ ] Book the venue.`);
    expect(parts).toContain(`about ${words.toLocaleString('en')} words`);
    expect(parts).toContain('measured against that, not against these notes');
    fakes[2]!.finish(ANSWER);
    await tick(0);
    expect(notes.get('n1')?.body).toContain(SECTION);
    expect(queued()).toEqual([]);
  });

  it('starts at the piece after the last one checkpointed', async () => {
    const long: Segment[] = [];
    let at = 0;
    while (long.reduce((n, s) => n + s.text.length + 1, 0) < ONE_PASS_CHARS + 2000) {
      long.push({ text: `Something that was said at ${at}, at some length, to fill the tape.`, startMs: at, endMs: at + 2000 });
      at += 4000;
    }
    notes.set('n1', { ...notes.get('n1')!, segments: long });
    localStorage.setItem(QUEUE_KEY, JSON.stringify([{ id: 'n1', kind: 'recording', tries: 0, pieces: ['- The first half.'] }]));
    stop?.();
    stop = startSummaries(changed, summarized);
    await tick(4000);
    expect(fakes).toHaveLength(1);
    expect(fakes[0]!.options.prompt.startsWith(`${fill(PIECE_CONTEXT, { n: 2, m: 2 })}\n\n`)).toBe(true);
  });
});

describe('an open note', () => {
  it('is handed the words and lands the summary through its editor, and what landed is what is kept', async () => {
    const starter = vi.fn((ask) => {
      const handle = startRun({ noteId: 'n1', kind: 'summarize', model: ask.model, system: RECORDING_SUMMARY_PROMPT, prompt: ask.words, maxTokens: ask.maxTokens });
      return { ok: true as const, handle };
    });
    openForSummaries('n1', starter);
    enqueueSummary('n1', 'recording');
    await tick(0);
    expect(starter).toHaveBeenCalledWith({ words: 'That is the March launch settled. Sam owns the press list.', context: undefined, model: 'qwen3.5-4b', maxTokens: expect.any(Number), replace: false });
    // The run's generation is the one asked for; the queue asks for none of its own.
    expect(fakes).toHaveLength(1);
    fakes[0]!.finish(SECTION);
    await tick(0);
    expect(readSummary('n1')).toMatchObject({ text: SECTION, model: 'qwen3.5-4b' });
    expect(queued()).toEqual([]);
    expect(summarized).toHaveBeenCalledWith({ id: 'n1', title: 'March launch' });
    // Nothing written plain: the editor is the one writer of an open note.
    expect(invoked.filter((c) => c.command === 'update_note')).toEqual([]);
  });

  it('lands through the real editor run, and keeps the section as any body reads it, so a remake finds it unchanged', async () => {
    const view = new EditorView({ state: EditorState.create({ doc: '# March launch\n\nThat is the March launch settled.', extensions: [aiChanges()] }) });
    try {
      openForSummaries('n1', (ask) => startNoteRun(view, 'n1', 'summarize', { ok: true, model: 'qwen3.5-4b', chosen: 'qwen3.5-4b' }, { recording: ask }));
      enqueueSummary('n1', 'recording');
      await tick(0);
      expect(fakes).toHaveLength(1);
      // Landed as the note screen lands a run (ai/useLanding.ts): the finished lines through the lander.
      const lander = new Lander(view, runFor('n1')!.id, { wisp: false, haptic: false }, view.state.doc.toString());
      fakes[0]!.finish(ANSWER);
      await tick(0);
      lander.finish(allLines(runFor('n1')!.text!));
      const doc = view.state.doc.toString();
      expect(doc).toBe(`# March launch\n\n${SECTION}\n\nThat is the March launch settled.`);
      expect(readSummary('n1')?.text).toBe(SECTION);
      expect(summaryUnchanged('n1', summarySection(doc, SECTION)!.text)).toBe(true);
      expect(queued()).toEqual([]);
      // Asked again from the strip, the run goes over the section the note has, not beside it.
      openForSummaries('n1', (ask) => startNoteRun(view, 'n1', 'summarize', { ok: true, model: 'qwen3.5-4b', chosen: 'qwen3.5-4b' }, { recording: ask }));
      enqueueSummary('n1', 'recording');
      await tick(500);
      expect(fakes).toHaveLength(2);
      expect(runFor('n1')?.scope).toEqual({ from: 16, to: 16 + SECTION.length + 1 });
    } finally {
      view.destroy();
    }
  });

  it('hands the answer to the note’s editor when the note was opened while the model wrote, and writes nothing plain', async () => {
    enqueueSummary('n1', 'recording');
    await tick(0);
    expect(fakes).toHaveLength(1);
    const starter = vi.fn(() => ({ ok: true as const, landed: SECTION }));
    openForSummaries('n1', starter);
    fakes[0]!.finish(ANSWER);
    await tick(0);
    expect(starter).toHaveBeenCalledWith({ words: 'That is the March launch settled. Sam owns the press list.', context: undefined, model: 'qwen3.5-4b', maxTokens: expect.any(Number), replace: false, text: ANSWER });
    expect(invoked.filter((c) => c.command === 'update_note')).toEqual([]);
    expect(readSummary('n1')).toMatchObject({ text: SECTION, model: 'qwen3.5-4b', forMs: 4000 });
    expect(queued()).toEqual([]);
    expect(summarized).toHaveBeenCalledWith({ id: 'n1', title: 'March launch' });
    // An answer kept from a pass that could not write is handed over the same way at the next kick, the model not asked again.
    localStorage.setItem(QUEUE_KEY, JSON.stringify([{ id: 'n1', kind: 'recording', tries: 0, text: ANSWER }]));
    starter.mockClear();
    stop?.();
    stop = startSummaries(changed, summarized);
    await tick(4000);
    expect(fakes).toHaveLength(1);
    expect(starter).toHaveBeenCalledWith(expect.objectContaining({ text: ANSWER }));
    expect(queued()).toEqual([]);
  });

  it('drops the job when the editor says the section was edited', async () => {
    openForSummaries('n1', () => ({ ok: false, reason: 'edited' }));
    enqueueSummary('n1', 'recording');
    await tick(0);
    expect(queued()).toEqual([]);
  });

  it('leaves the job when the recorder cut the run, to land over what landed once the recorder has gone, and drops it when the person stopped it', async () => {
    const starter = vi.fn((ask: { replace: boolean }) => {
      void ask;
      return { ok: true as const, handle: startRun({ noteId: 'n1', kind: 'summarize', model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 10 }) };
    });
    openForSummaries('n1', starter);
    enqueueSummary('n1', 'recording');
    await tick(0);
    expect(starter).toHaveBeenCalledTimes(1);
    hold(true);
    await tick(0);
    expect(runFor('n1')?.phase).toBe('stopped');
    // Uncounted, and marked to replace: the half that landed is the app's own, not an edit of the person's.
    expect(queued()).toEqual([expect.objectContaining({ id: 'n1', tries: 0, started: false, replace: true })]);
    await tick(60_000);
    expect(starter).toHaveBeenCalledTimes(1);
    hold(false);
    await tick(1500);
    expect(starter).toHaveBeenCalledTimes(2);
    expect(starter).toHaveBeenLastCalledWith(expect.objectContaining({ replace: true }));
    // The person's Stop, from the strip or the scene: theirs to ask for again.
    await cancelRun('n1');
    await tick(0);
    expect(queued()).toEqual([]);
    await tick(60_000);
    expect(starter).toHaveBeenCalledTimes(2);
    expect(fakes).toHaveLength(2);
  });
});

describe('a native write-up', () => {
  const RESULT = { summary: ANSWER, model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1 };
  const state = (phase: string, waitingFor: string | null = null) => ({ id: 'n1', title: 'Meeting, 26 Sep 14:05', phase, waitingFor, percent: 0, error: null, updatedAt: 1 });

  it('takes the result the phone left and lands it through the same write, refreshing the list and running no model, and says nothing while the phone can notify', async () => {
    enqueueSummary('n1', 'meeting', { native: true });
    phone.results.set('n1', RESULT);
    await tick(0);
    expect(fakes).toEqual([]);
    expect(notes.get('n1')?.body).toBe(`# March launch\n\n${SECTION}\n\nThat is the March launch settled. Sam owns the press list.`);
    expect(readSummary('n1')).toMatchObject({ text: SECTION, model: 'qwen3.5-2b' });
    expect(queued()).toEqual([]);
    expect(changed).toHaveBeenCalled();
    expect(summarized).not.toHaveBeenCalled();
  });

  it('says it, with Open, when the phone cannot notify: the toast is the only word then', async () => {
    phone.canNotify = false;
    enqueueSummary('n1', 'meeting', { native: true });
    phone.results.set('n1', RESULT);
    await tick(0);
    expect(summarized).toHaveBeenCalledWith({ id: 'n1', title: 'March launch' });
  });

  it('lands an answer the job already holds without asking the phone: the take happened, the page died before the write', async () => {
    localStorage.setItem(QUEUE_KEY, JSON.stringify([{ id: 'n1', kind: 'meeting', tries: 0, native: true, text: ANSWER, model: 'qwen3.5-2b' }]));
    stop?.();
    stop = startSummaries(changed, summarized);
    await tick(4000);
    expect(phone.taken).toEqual([]);
    expect(notes.get('n1')?.body).toContain(SECTION);
    expect(queued()).toEqual([]);
  });

  it('makes the job for a result that has none, and lands it', async () => {
    phone.results.set('n1', RESULT);
    await landNativeResult('n1');
    expect(phone.taken).toEqual(['n1']);
    expect(notes.get('n1')?.body).toContain(SECTION);
    expect(queued()).toEqual([]);
  });

  it('ends the job with nothing written when the result has no summary: the transcript is in the note from the phone already', async () => {
    enqueueSummary('n1', 'meeting', { native: true });
    phone.results.set('n1', { ...RESULT, summary: null });
    await tick(0);
    expect(queued()).toEqual([]);
    expect(notes.get('n1')?.body).not.toContain('## Summary');
    expect(invoked.filter((c) => c.command === 'update_note')).toEqual([]);
  });

  it('lands at once when the service says the write-up is done, and drops the job when it says cancelled', async () => {
    enqueueSummary('n1', 'meeting', { native: true });
    await tick(0);
    expect(queued()).toHaveLength(1);
    phone.results.set('n1', RESULT);
    window.__glyph!.recordingDone!(JSON.stringify({ id: 'n1', outcome: 'done' }));
    await tick(0);
    expect(notes.get('n1')?.body).toContain(SECTION);
    expect(queued()).toEqual([]);
    enqueueSummary('n1', 'meeting', { native: true });
    window.__glyph!.recordingDone!(JSON.stringify({ id: 'n1', outcome: 'cancelled' }));
    await tick(0);
    expect(queued()).toEqual([]);
    // A push this build cannot read does nothing.
    expect(() => window.__glyph!.recordingDone!('{')).not.toThrow();
  });

  it('wears the phase the phone’s progress file says: writing up, waiting to charge, needing a model, failed, and gone when cancelled', async () => {
    enqueueSummary('n1', 'meeting', { native: true });
    phone.states = [state('listening')];
    await tick(0);
    expect(summariesNow().native.has('n1')).toBe(true);
    expect(summariesNow().waiting.has('n1')).toBe(false);
    phone.states = [state('waiting', 'battery')];
    await tick(15_000);
    expect(summariesNow().waiting.has('n1')).toBe(true);
    expect(summariesNow().native.has('n1')).toBe(false);
    // Waiting for anything else - the heat, a dictation - is still writing up, as far as the shelf says.
    phone.states = [state('waiting', 'thermal')];
    await tick(15_000);
    expect(summariesNow().native.has('n1')).toBe(true);
    expect(summariesNow().waiting.has('n1')).toBe(false);
    phone.states = [state('needsModel')];
    await tick(15_000);
    expect(summariesNow().needsModel.has('n1')).toBe(true);
    expect(summariesNow().native.has('n1')).toBe(false);
    phone.states = [state('failed')];
    await tick(15_000);
    expect(summariesNow().failed.has('n1')).toBe(true);
    expect(summariesNow().native.has('n1')).toBe(false);
    phone.states = [state('cancelled')];
    await tick(15_000);
    expect(queued()).toEqual([]);
    expect(summariesNow().failed.has('n1')).toBe(false);
  });

  it('sends Try again on a failed write-up and Write up now on a waiting one to the service, to run from the front', async () => {
    const writeUp = vi.fn(() => 'queued');
    window.GlyphHost = { writeUp } as unknown as Window['GlyphHost'];
    enqueueSummary('n1', 'meeting', { native: true });
    phone.states = [state('failed')];
    await tick(0);
    expect(summariesNow().failed.has('n1')).toBe(true);
    retrySummary('n1');
    expect(writeUp).toHaveBeenCalledWith('n1', true);
    // Until the phone says otherwise it is writing up again.
    expect(summariesNow().failed.has('n1')).toBe(false);
    expect(summariesNow().native.has('n1')).toBe(true);
    phone.states = [state('waiting', 'battery')];
    await tick(15_000);
    expect(summariesNow().waiting.has('n1')).toBe(true);
    writeUpNow('n1');
    expect(writeUp).toHaveBeenLastCalledWith('n1', true);
    expect(summariesNow().waiting.has('n1')).toBe(false);
  });

  it('asks the service again, once, for a write-up that needed a model once one is on the phone', async () => {
    const writeUp = vi.fn(() => 'queued');
    window.GlyphHost = { writeUp } as unknown as Window['GlyphHost'];
    present = [];
    enqueueSummary('n1', 'meeting', { native: true });
    phone.states = [state('needsModel')];
    await tick(0);
    expect(summariesNow().needsModel.has('n1')).toBe(true);
    expect(writeUp).not.toHaveBeenCalled();
    present = ['qwen3.5-4b'];
    await tick(15_000);
    expect(writeUp).toHaveBeenCalledWith('n1', false);
    await tick(15_000);
    expect(writeUp).toHaveBeenCalledTimes(1);
  });

  it('looks for a waiting result again when the page comes back to the front, and every fifteen seconds while one waits', async () => {
    enqueueSummary('n1', 'meeting', { native: true });
    await tick(0);
    expect(phone.taken).toEqual(['n1']);
    await tick(15_000);
    expect(phone.taken).toEqual(['n1', 'n1']);
    visible('hidden');
    document.dispatchEvent(new Event('visibilitychange'));
    visible('visible');
    document.dispatchEvent(new Event('visibilitychange'));
    await tick(0);
    expect(phone.taken).toEqual(['n1', 'n1', 'n1']);
  });
});
