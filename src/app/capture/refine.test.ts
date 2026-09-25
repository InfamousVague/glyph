import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Segment } from './markdown.ts';
import type { RefineJob } from './refine.ts';

/**
 * The pass after a recording (capture/refine.ts): the queue it keeps on the phone, when it runs and when it waits, and
 * what it writes. The bridge is a stand-in that answers as Rust would, the note store's Tauri half included, and the
 * clock is a fake one, so "twenty seconds later" is a thing a test can say.
 */

let native = true;
let generation = 7;
const notes = new Map<string, { id: string; body: string; revision: number }>();
const answers = new Map<string, (args: Record<string, unknown>) => unknown>();
const invoked: { command: string; args: Record<string, unknown> }[] = [];
const invoke = vi.fn(async (command: string, args: Record<string, unknown> = {}) => {
  invoked.push({ command, args });
  const answer = answers.get(command);
  if (!answer) throw new Error(`no answer for ${command}`);
  return answer(args);
});
const progress = new Map<string, (payload: unknown) => void>();

vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke }));
vi.mock('../core/nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => native && generation >= wanted }));
vi.mock('../core/events.ts', () => ({
  listenTo: async (event: string, handler: (payload: unknown) => void) => {
    progress.set(event, handler);
    return () => progress.delete(event);
  },
}));

const { setPreferences } = await import('../core/preferences.ts');
const { enqueueRefine, keepBetterPhrases, listenAgain, setRecorderLive, startRefining } = await import('./refine.ts');

const QUEUE_KEY = 'glyph-refine-queue';
const queued = (): RefineJob[] => JSON.parse(localStorage.getItem(QUEUE_KEY) ?? '[]') as RefineJob[];
const calls = (command: string) => invoked.filter((call) => call.command === command);

const job = (over: Partial<Omit<RefineJob, 'tries'>> = {}): Omit<RefineJob, 'tries'> => ({
  id: 'n1',
  fromMs: 0,
  recordingMs: 2400,
  baseBody: '',
  savedBody: '# Grocery run\n\nOat milk and legs.',
  titled: true,
  priorSegments: [],
  promptTail: '',
  ...over,
});
const better: Segment[] = [
  { text: 'Grocery run.', startMs: 0, endMs: 900 },
  { text: 'Oat milk and eggs.', startMs: 1200, endMs: 2400 },
];

let stop: (() => void) | null = null;
let changed = vi.fn();

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  localStorage.clear();
  native = true;
  generation = 7;
  notes.clear();
  answers.clear();
  invoked.length = 0;
  progress.clear();
  setPreferences({ refine: true, localOnly: false });
  notes.set('n1', { id: 'n1', body: '# Grocery run\n\nOat milk and legs.', revision: 1 });
  answers.set('get_note', ({ id }) => notes.get(id as string) ?? null);
  answers.set('update_note', ({ id, body, expectedRevision }) => {
    const note = { id: id as string, body: body as string, revision: (expectedRevision as number) + 1 };
    notes.set(note.id, note);
    return note;
  });
  answers.set('set_note_recording', ({ id }) => notes.get(id as string) ?? null);
  answers.set('capture_refine_model_status', () => ({ present: true, bytes: 190_000_000 }));
  answers.set('capture_refine', () => better);
  changed = vi.fn();
  stop = startRefining(changed);
});

afterEach(() => {
  stop?.();
  setRecorderLive(false);
  vi.clearAllTimers();
  vi.useRealTimers();
  setPreferences({ refine: true, localOnly: false });
});

describe('the better words', () => {
  it('replace the words of a note that still reads as Done left it, and the phrases on its tape', async () => {
    enqueueRefine(job());
    expect(queued()).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(0);
    expect(calls('capture_refine')[0]?.args).toEqual({ id: 'n1', fromMs: 0, promptTail: '' });
    expect(notes.get('n1')?.body).toBe('# Grocery run\n\nOat milk and eggs.');
    expect(calls('set_note_recording')[0]?.args).toEqual({ id: 'n1', recordingMs: 2400, segments: better });
    expect(queued()).toEqual([]);
    expect(changed).toHaveBeenCalledOnce();
  });

  it('leave a note someone changed since Done as they left it, and still put the better phrases on its tape', async () => {
    notes.set('n1', { id: 'n1', body: '# Grocery run\n\nOat milk and legs. And bread.', revision: 2 });
    enqueueRefine(job());
    await vi.advanceTimersByTimeAsync(0);
    expect(calls('update_note')).toEqual([]);
    expect(notes.get('n1')?.body).toBe('# Grocery run\n\nOat milk and legs. And bread.');
    expect(calls('set_note_recording')).toHaveLength(1);
    expect(queued()).toEqual([]);
  });

  it('are asked for once per take: a take queued again replaces its own job, another take joins the queue', () => {
    enqueueRefine(job({ promptTail: 'first' }));
    enqueueRefine(job({ promptTail: 'second' }));
    enqueueRefine(job({ fromMs: 5000 }));
    expect(queued().map((j) => [j.fromMs, j.promptTail, j.tries])).toEqual([
      [0, 'second', 0],
      [5000, '', 0],
    ]);
  });

  it('are not asked for with better words switched off, or in a browser', () => {
    setPreferences({ refine: false });
    enqueueRefine(job());
    setPreferences({ refine: true });
    native = false;
    enqueueRefine(job());
    expect(queued()).toEqual([]);
  });

  it('wait on a binary without the larger model’s pass', async () => {
    generation = 6;
    enqueueRefine(job());
    await vi.advanceTimersByTimeAsync(60_000);
    expect(invoked).toEqual([]);
    expect(queued()).toHaveLength(1);
  });
});

describe('when the pass runs', () => {
  it('never while the recorder is on screen, and soon after it goes', async () => {
    setRecorderLive(true);
    enqueueRefine(job());
    await vi.advanceTimersByTimeAsync(30_000);
    expect(calls('capture_refine')).toEqual([]);
    setRecorderLive(false);
    await vi.advanceTimersByTimeAsync(1499);
    expect(calls('capture_refine')).toEqual([]);
    await vi.advanceTimersByTimeAsync(1);
    expect(calls('capture_refine')).toHaveLength(1);
  });

  it('tries again twenty seconds after the phone was busy, not sooner, and the job keeps its tries', async () => {
    let busy = true;
    answers.set('capture_refine', () => {
      if (busy) {
        busy = false;
        throw 'the voice model is busy';
      }
      return better;
    });
    enqueueRefine(job());
    await vi.advanceTimersByTimeAsync(0);
    expect(calls('capture_refine')).toHaveLength(1);
    expect(queued()[0]?.tries).toBe(0);
    await vi.advanceTimersByTimeAsync(19_999);
    expect(calls('capture_refine')).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(calls('capture_refine')).toHaveLength(2);
    expect(queued()).toEqual([]);
  });

  it('gives a pass up after three failures, twenty seconds apart', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    answers.set('capture_refine', () => {
      throw new Error('the recording could not be read');
    });
    enqueueRefine(job());
    await vi.advanceTimersByTimeAsync(0);
    expect(queued()[0]?.tries).toBe(1);
    await vi.advanceTimersByTimeAsync(20_000);
    expect(queued()[0]?.tries).toBe(2);
    await vi.advanceTimersByTimeAsync(20_000);
    expect(queued()).toEqual([]);
    await vi.advanceTimersByTimeAsync(120_000);
    expect(calls('capture_refine')).toHaveLength(3);
    warn.mockRestore();
  });

  it('waits a minute for a larger model it cannot get, rather than asking for it again at once', async () => {
    setPreferences({ localOnly: true });
    answers.set('capture_refine_model_status', () => ({ present: false, bytes: 190_000_000 }));
    enqueueRefine(job());
    await vi.advanceTimersByTimeAsync(0);
    expect(calls('capture_refine_model_status')).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(59_999);
    expect(calls('capture_refine_model_status')).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(calls('capture_refine_model_status')).toHaveLength(2);
    expect(calls('capture_fetch_refine_model')).toEqual([]);
    expect(calls('capture_refine')).toEqual([]);
  });

  it('runs the next take’s pass half a second after one finishes', async () => {
    enqueueRefine(job());
    enqueueRefine(job({ fromMs: 5000, savedBody: 'something else' }));
    await vi.advanceTimersByTimeAsync(0);
    expect(calls('capture_refine')).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(500);
    expect(calls('capture_refine')).toHaveLength(2);
    expect(queued()).toEqual([]);
  });
});

describe('the review’s own pass', () => {
  it('listens again now, telling its progress for this note only', async () => {
    const percent = vi.fn();
    answers.set('capture_refine', () => {
      progress.get('capture://refine-progress')?.({ id: 'other', percent: 10 });
      progress.get('capture://refine-progress')?.({ id: 'n1', percent: 50 });
      return better;
    });
    await expect(listenAgain(job(), percent)).resolves.toEqual(better);
    expect(percent.mock.calls).toEqual([[50]]);
    expect(progress.has('capture://refine-progress')).toBe(false);
  });

  it('cannot listen again on a binary without the pass', async () => {
    generation = 6;
    await expect(listenAgain(job(), vi.fn())).resolves.toBeNull();
  });

  it('keeps the better phrases on the tape with the commands left out', async () => {
    const phrases = [...better, { text: 'Hey Ghost, add bread to work.', startMs: 2500, endMs: 3800 }];
    await keepBetterPhrases(job({ recordingMs: 4000, skip: [{ startMs: 2500, endMs: 3800 }] }), phrases);
    expect(calls('set_note_recording')[0]?.args).toEqual({ id: 'n1', recordingMs: 4000, segments: better });
  });
});
