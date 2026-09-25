import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import type { ModelInfo, Output, RunOptions } from '../core/ai.ts';

/**
 * The review after a recording, run in the note, two ways: in a browser with `?review`, where a script plays both
 * models, and as a phone runs it, where each model answers when the test says so.
 *
 * The phone: the models it has, and a thinking run that answers on cue (`generate` is the seam, as in
 * runs.test.ts). Listening again and the queue it hands the take back to are the recorder's (capture/refine.ts),
 * stood in for here, so a test can say what the slower speech model heard, or that it failed, or leave it listening.
 */
const phone = vi.hoisted(() => ({
  models: [] as ModelInfo[],
  runs: [] as { options: RunOptions; finish: (text: string) => void; fail: (message: string) => void }[],
}));

vi.mock('../core/haptics.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/haptics.ts')>()), fireNativeHaptic: vi.fn() }));
vi.mock('../core/ai.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/ai.ts')>()),
  listModels: async () => phone.models,
  generate: (options: RunOptions) => {
    let resolve: (output: Output) => void = () => undefined;
    let reject: (failure: Error) => void = () => undefined;
    const done = new Promise<Output>((res, rej) => {
      resolve = res;
      reject = rej;
    });
    phone.runs.push({
      options,
      finish: (text) => resolve({ text, promptTokens: 10, outputTokens: 12, ms: 900, cachedTokens: 0, prefillMs: 10, loadMs: 10, tokensPerSecond: 9, truncated: false }),
      fail: (message) => reject(new Error(message)),
    });
    return { done, cancel: () => reject(new Error('cancelled')) };
  },
}));
vi.mock('../capture/refine.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../capture/refine.ts')>()),
  listenAgain: vi.fn(),
  enqueueRefine: vi.fn(),
  keepBetterPhrases: vi.fn(async () => undefined),
  holdRefining: vi.fn(),
}));

import { rerender, show, unmount, waitUntil } from '../../test/render.tsx';
import { enqueueRefine, holdRefining, keepBetterPhrases, listenAgain } from '../capture/refine.ts';
import type { Segment } from '../capture/markdown.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { createNote, getNote, updateNote } from '../core/store.ts';
import { aiChanges, aiChangesField } from '../editor/aiChanges.ts';
import { runsOf } from './log.ts';
import { cancelRun, forgetAllRuns } from './runs.ts';
import { useNoteReview, type ReviewStage } from './useNoteReview.ts';
import type { ReviewHandoff } from './review.ts';

let view: EditorView | null = null;
const stages: (ReviewStage | null)[] = [];
const said: string[] = [];

function Note({ review, editor }: { review: ReviewHandoff & { key: number }; editor: EditorView }) {
  stages.push(useNoteReview(review, editor, { wisp: false, say: (message) => said.push(message) }));
  return null;
}

function editor(doc: string): EditorView {
  view = new EditorView({ state: EditorState.create({ doc, extensions: [aiChanges()] }) });
  return view;
}

beforeEach(() => {
  localStorage.clear();
  stages.length = 0;
  said.length = 0;
  phone.models = [];
  phone.runs.length = 0;
  vi.clearAllMocks();
});
afterEach(() => {
  forgetAllRuns();
  view?.destroy();
  view = null;
  window.history.replaceState(null, '', '/');
  vi.useRealTimers();
});

describe('the review after a recording, in the note', () => {
  /**
   * End to end in a browser the way it is developed: `?review` plays the slower speech model and the thinking model
   * with a script (ai/reviewSimulation.ts), so the stages, the run and the landing are the real ones and only the
   * models are not.
   */
  beforeEach(() => {
    vi.useFakeTimers();
    window.history.replaceState(null, '', '/?review');
  });

  it('listens again, thinks, and lands what the slower model heard as a tracked change', async () => {
    const body = '# Player\n- [ ] Fix the seat bar.\n';
    await createNote('n1', body, 'capture');
    view = editor(body);
    show(<Note review={{ key: 1, noteId: 'n1', job: null, heard: 'Fix the seat bar.', commands: [], touched: [] }} editor={view} />);
    // A quarter of a second at a time, so each stage is drawn as the strip would draw it.
    for (let i = 0; i < 40; i += 1) await act(() => vi.advanceTimersByTimeAsync(250));
    await act(async () => {
      await vi.runAllTimersAsync();
    });
    // Listening again is a stage of its own, with its percent climbing. (Comparing takes no time with nothing to wait
    // on, so it is gone before it is drawn.)
    const listening = stages.flatMap((stage) => (stage?.what === 'Listening again' && stage.percent !== null ? [stage.percent] : []));
    expect(listening.length).toBeGreaterThan(3);
    expect(listening).toEqual([...listening].sort((a, b) => a - b));
    // The stages give way to the run, and the strip follows that like any other.
    expect(stages.at(-1)).toBeNull();
    expect(view.state.doc.toString()).toBe('# Player\n- [ ] Fix the seek bar.\n');
    expect(view.state.field(aiChangesField).map((change) => change.removed)).toEqual(['- [ ] Fix the seat bar.']);
    expect(said.at(-1)).toMatch(/found 1 thing to look at\. Each is marked in the note\.$/);
    // The log has the review, and the words before and after it, for Undo.
    expect(runsOf('n1')[0]).toMatchObject({ kind: 'review', outcome: 'done', before: body, after: '# Player\n- [ ] Fix the seek bar.\n' });
  });

  it('runs once for its handoff, however often the note draws', async () => {
    const body = '# Player\n- [ ] Fix the seat bar.\n';
    await createNote('n2', body, 'capture');
    view = editor(body);
    const review = { key: 7, noteId: 'n2', job: null, heard: 'Fix the seat bar.', commands: [], touched: [] };
    show(<Note review={review} editor={view} />);
    await act(async () => {
      await vi.runAllTimersAsync();
    });
    // The note draws again with the same handoff: the review has run, and does not run again.
    rerender(<Note review={{ ...review }} editor={view} />);
    await act(async () => {
      await vi.runAllTimersAsync();
    });
    expect(runsOf('n2').filter((run) => run.kind === 'review')).toHaveLength(1);
    expect(view.state.doc.toString()).toBe('# Player\n- [ ] Fix the seek bar.\n');
  });
});

describe('the review after a recording, on a phone', () => {
  const body = '# Player\n- [ ] Fix the seat bar.\n';
  const seek = '# Player\n- [ ] Fix the seek bar.\n';
  /** What the slower speech model heard: the fast one's words, but "seek". */
  const better: Segment[] = [{ text: 'Fix the seek bar.', startMs: 0, endMs: 1500 }];
  const qwen: ModelInfo = { id: 'qwen3.5-4b', file: 'qwen3.5-4b.gguf', bytes: 2_740_937_888, present: true, path: '/models/qwen3.5-4b.gguf' };
  const noModel = 'No language model on this phone to think it through, so only the words the slower model heard differently are marked.';
  /** The take Stop saved, as the recorder hands it over. */
  const take = (id: string) => ({ id, fromMs: 0, recordingMs: 1500, baseBody: '', savedBody: body, titled: true, priorSegments: [], promptTail: '' });
  const handoff = (noteId: string, patch: Partial<ReviewHandoff> = {}) => ({ key: 1, noteId, job: take(noteId), heard: 'Fix the seat bar.', commands: [], touched: [], ...patch });
  /** Lets what the review is waiting on settle, and React draw it. */
  const settle = () => act(() => new Promise<void>((r) => setTimeout(r, 0)));

  it('hands the take back to the queue, once, when the note is left while it is listening again', async () => {
    await createNote('p1', body, 'capture');
    let heard: (segments: Segment[] | null) => void = () => undefined;
    vi.mocked(listenAgain).mockImplementation(() => new Promise((resolve) => (heard = resolve)));
    show(<Note review={handoff('p1')} editor={editor(body)} />);
    await waitUntil(() => expect(stages.at(-1)?.what).toBe('Listening again'));
    expect(holdRefining).toHaveBeenLastCalledWith(true);
    unmount();
    // Left mid-review: the pass the queue would have run anyway is queued, and the queue is free to run it.
    expect(enqueueRefine).toHaveBeenCalledTimes(1);
    expect(enqueueRefine).toHaveBeenCalledWith(take('p1'));
    expect(holdRefining).toHaveBeenLastCalledWith(false);
    // The slower model answers after all: the note is gone, so nothing thinks, lands or is queued again.
    heard(better);
    await settle();
    expect(enqueueRefine).toHaveBeenCalledTimes(1);
    expect(keepBetterPhrases).not.toHaveBeenCalled();
    expect(phone.runs).toHaveLength(0);
    expect(view!.state.doc.toString()).toBe(body);
  });

  it('marks only the words the slower model heard when there is no model to think, and says so', async () => {
    await createNote('p2', body, 'capture');
    vi.mocked(listenAgain).mockResolvedValue(better);
    show(<Note review={handoff('p2')} editor={editor(body)} />);
    await waitUntil(() => expect(keepBetterPhrases).toHaveBeenCalled());
    expect(view!.state.doc.toString()).toBe(seek);
    expect(said).toEqual([noModel, 'The slower model found 1 thing to look at. Each is marked in the note.']);
    expect(phone.runs).toHaveLength(0);
    // The better words are kept for the recording's transcript, instead of queueing a pass to hear them again.
    expect(keepBetterPhrases).toHaveBeenCalledWith(take('p2'), better);
    expect(enqueueRefine).not.toHaveBeenCalled();
    // Leaving the note after the review has ended hands nothing back a second time.
    unmount();
    expect(keepBetterPhrases).toHaveBeenCalledTimes(1);
    expect(vi.mocked(holdRefining).mock.calls).toEqual([[true], [false]]);
  });

  it('says why listening again failed, and hands the take back to the queue', async () => {
    await createNote('p3', body, 'capture');
    vi.mocked(listenAgain).mockRejectedValue(new Error('The slower speech model could not be loaded.'));
    show(<Note review={handoff('p3')} editor={editor(body)} />);
    await waitUntil(() => expect(enqueueRefine).toHaveBeenCalled());
    expect(said).toEqual(['The slower speech model could not be loaded.', noModel]);
    expect(view!.state.doc.toString()).toBe(body);
    expect(enqueueRefine).toHaveBeenCalledWith(take('p3'));
    expect(keepBetterPhrases).not.toHaveBeenCalled();
    unmount();
    expect(enqueueRefine).toHaveBeenCalledTimes(1);
    expect(vi.mocked(holdRefining).mock.calls).toEqual([[true], [false]]);
  });

  it.each(['stopped', 'failed'] as const)('lands only the words when the thinking run is %s, and says nothing of its own', async (outcome) => {
    const id = `p4-${outcome}`;
    await createNote(id, body, 'capture');
    phone.models = [qwen];
    vi.mocked(listenAgain).mockResolvedValue(better);
    show(<Note review={handoff(id)} editor={editor(body)} />);
    await waitUntil(() => expect(phone.runs).toHaveLength(1));
    // It thinks with the model chosen for formatting, a Qwen on the phone.
    expect(phone.runs[0]!.options.model).toBe('qwen3.5-4b');
    if (outcome === 'stopped') await act(() => cancelRun(id));
    else act(() => phone.runs[0]!.fail('out of memory'));
    await waitUntil(() => expect(keepBetterPhrases).toHaveBeenCalled());
    expect(runsOf(id)[0]).toMatchObject({ kind: 'review', outcome });
    // The words the slower speech model heard still land; the strip already says what happened to the run.
    expect(view!.state.doc.toString()).toBe(seek);
    expect(said).toEqual([]);
    expect(fireNativeHaptic).not.toHaveBeenCalled();
  });

  it('writes a finding for another note into that note as it is now, through the guarded write', async () => {
    await createNote('p5', body, 'capture');
    await createNote('p6', '# HelloTrade\n- buy milk\n');
    phone.models = [qwen];
    show(<Note review={handoff('p5', { job: null, heard: 'Fix the seat bar. Glyph, add buy milk to HelloTrade.', commands: ['Added “buy milk” to HelloTrade.'], touched: ['p6'] })} editor={editor(body)} />);
    await waitUntil(() => expect(phone.runs).toHaveLength(1));
    // While the model thinks, the other note gains a line: the finding is written over that, not over what was read
    // when the review began.
    const other = (await getNote('p6'))!;
    await updateNote('p6', `${other.body}- bread\n`, other.revision ?? 1);
    act(() => phone.runs[0]!.finish(JSON.stringify([{ check: 'commands', note: 'HelloTrade', what: 'Oat milk, not milk', why: 'It was said.', find: 'buy milk', replace: 'buy oat milk' }])));
    await waitUntil(() => expect(said).toHaveLength(1));
    expect(said[0]).toBe('Qwen3.5 4B found 1 thing to look at, 1 in another note.');
    expect(await getNote('p6')).toMatchObject({ body: '# HelloTrade\n- buy oat milk\n- bread\n', revision: 3 });
    // The note on screen had nothing to change.
    expect(view!.state.doc.toString()).toBe(body);
  });
});
