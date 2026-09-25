import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';

vi.mock('../core/haptics.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/haptics.ts')>()), fireNativeHaptic: vi.fn() }));

import { rerender, show } from '../../test/render.tsx';
import { createNote } from '../core/store.ts';
import { aiChanges, aiChangesField } from '../editor/aiChanges.ts';
import { runsOf } from './log.ts';
import { forgetAllRuns } from './runs.ts';
import { useNoteReview, type ReviewStage } from './useNoteReview.ts';
import type { ReviewHandoff } from './review.ts';

/**
 * The review after a recording, run in the note, end to end in a browser the way it is developed: `?review` plays
 * the slower speech model and the thinking model with a script (ai/reviewSimulation.ts), so the stages, the run and
 * the landing are the real ones and only the models are not.
 */

let view: EditorView | null = null;
const stages: (ReviewStage | null)[] = [];
const said: string[] = [];

function Note({ review, editor }: { review: ReviewHandoff & { key: number }; editor: EditorView }) {
  stages.push(useNoteReview(review, editor, { wisp: false, say: (message) => said.push(message) }));
  return null;
}

beforeEach(() => {
  vi.useFakeTimers();
  localStorage.clear();
  stages.length = 0;
  said.length = 0;
  window.history.replaceState(null, '', '/?review');
});
afterEach(() => {
  forgetAllRuns();
  view?.destroy();
  view = null;
  window.history.replaceState(null, '', '/');
  vi.useRealTimers();
});

describe('the review after a recording, in the note', () => {
  it('listens again, thinks, and lands what the slower model heard as a tracked change', async () => {
    const body = '# Player\n- [ ] Fix the seat bar.\n';
    await createNote('n1', body, 'capture');
    view = new EditorView({ state: EditorState.create({ doc: body, extensions: [aiChanges()] }) });
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
    view = new EditorView({ state: EditorState.create({ doc: body, extensions: [aiChanges()] }) });
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
