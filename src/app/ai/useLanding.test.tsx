import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import type { Output, Progress, RunOptions } from '../core/ai.ts';

/** A model that answers when the test says so: `generate` is the seam, as in runs.test.ts. */
interface Fake {
  options: RunOptions;
  write: (partial: string) => void;
  finish: (text: string) => void;
  fail: (message: string) => void;
}
const fakes: Fake[] = [];

vi.mock('../core/ai.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/ai.ts')>();
  return {
    ...real,
    generate: (options: RunOptions) => {
      let resolve: (output: Output) => void = () => undefined;
      let reject: (failure: Error) => void = () => undefined;
      const done = new Promise<Output>((res, rej) => {
        resolve = res;
        reject = rej;
      });
      const report = (partial: string): Progress => ({ id: 'x', phase: 'generating', promptTokens: 10, promptTokensDone: 10, outputTokens: 5, tokensPerSecond: 9, elapsedMs: 500, partial });
      fakes.push({
        options,
        write: (partial) => options.onProgress(report(partial)),
        finish: (text) => resolve({ text, promptTokens: 10, outputTokens: 12, ms: 900, cachedTokens: 0, prefillMs: 10, loadMs: 10, tokensPerSecond: 9, truncated: false }),
        fail: (message) => reject(new Error(message)),
      });
      return { done, cancel: () => reject(new Error('cancelled')) };
    },
  };
});

const { show } = await import('../../test/render.tsx');
const { aiChanges, aiChangesField, landingField } = await import('../editor/aiChanges.ts');
const { authorsOf } = await import('../core/authors.ts');
const { forgetAllRuns, startRun } = await import('./runs.ts');
const { runsOf } = await import('./log.ts');
const { startNoteRun } = await import('./start.ts');
const { useLanding } = await import('./useLanding.ts');

const ready = { ok: true as const, model: 'qwen3.5-4b', chosen: 'qwen3.5-4b' };
/** Lets a run's promises settle, and React draw what they published. */
const settle = () => act(() => new Promise<void>((r) => setTimeout(r, 0)));

let view: EditorView | null = null;
function open(doc: string): EditorView {
  const host = document.createElement('div');
  document.body.appendChild(host);
  view = new EditorView({ state: EditorState.create({ doc, extensions: [aiChanges()] }), parent: host });
  return view;
}

function Note({ noteId, editor, onDropped }: { noteId: string; editor: EditorView; onDropped?: (count: number) => void }) {
  useLanding(noteId, editor, { wisp: false, haptic: false, owner: 'matt', onDropped });
  return null;
}

beforeEach(() => {
  localStorage.clear();
  fakes.length = 0;
});
afterEach(() => {
  forgetAllRuns();
  view?.destroy();
  view?.dom.parentElement?.remove();
  view = null;
});

describe('a run landing in the note on screen', () => {
  it('puts each line in as the model finishes it, then the tidied answer, signed by the AI and kept for Undo', async () => {
    const before = 'call sam\nbuy eggs\n';
    const v = open(before);
    show(<Note noteId="n1" editor={v} />);
    const started = startNoteRun(v, 'n1', 'format', ready);
    if (!started.ok) throw new Error(started.reason);
    await settle();
    // A line lands only once its newline has come; the one under the pen waits.
    act(() => fakes[0]!.write('# Call Sam\n- Buy'));
    expect(v.state.doc.toString()).toBe('# Call Sam\nbuy eggs\n');
    expect(v.state.field(aiChangesField).length).toBeGreaterThan(0);
    act(() => fakes[0]!.finish('# Call Sam\n- Buy eggs\n'));
    await settle();
    const after = v.state.doc.toString();
    expect(after.endsWith('# Call Sam\n- Buy eggs\n')).toBe(true);
    // The person owns the note and the app's model co-wrote it.
    expect(authorsOf(after)).toEqual(['matt', 'Ghost']);
    // The bookmark is put away, and the log has the words before and after.
    expect(v.state.field(landingField)).toBeNull();
    expect(runsOf('n1')[0]).toMatchObject({ id: started.handle.id, outcome: 'done', before, after });
  });

  it('keeps what landed when the run is stopped, and signs nothing', async () => {
    const v = open('call sam\nbuy eggs\n');
    show(<Note noteId="n2" editor={v} />);
    const started = startNoteRun(v, 'n2', 'format', ready);
    if (!started.ok) throw new Error(started.reason);
    await settle();
    act(() => fakes[0]!.write('# Call Sam\n'));
    act(() => started.handle.cancel());
    await settle();
    expect(v.state.doc.toString()).toBe('# Call Sam\nbuy eggs\n');
    expect(authorsOf(v.state.doc.toString())).toEqual([]);
    expect(v.state.field(landingField)).toBeNull();
    expect(runsOf('n2')[0]).toMatchObject({ outcome: 'stopped', before: 'call sam\nbuy eggs\n', after: '# Call Sam\nbuy eggs\n' });
  });

  it('leaves the review’s run alone: its findings land by their own road', async () => {
    const v = open('fix the seat bar\n');
    show(<Note noteId="n3" editor={v} />);
    const handle = startRun({ noteId: 'n3', kind: 'review', model: 'qwen3.5-4b', system: '', prompt: 'x', maxTokens: 100 });
    await settle();
    act(() => fakes[0]!.write('[{"check":"words"}]\n'));
    act(() => fakes[0]!.finish('[]\n'));
    await handle.done;
    await settle();
    expect(v.state.doc.toString()).toBe('fix the seat bar\n');
  });

  it('keeps a line the person rewrote while the model was on it, and says the model’s was dropped', async () => {
    const dropped = vi.fn();
    const v = open('call sam\nbuy eggs\n');
    show(<Note noteId="n4" editor={v} onDropped={dropped} />);
    const started = startNoteRun(v, 'n4', 'format', ready);
    if (!started.ok) throw new Error(started.reason);
    await settle();
    act(() => fakes[0]!.write('# Call Sam\n'));
    // The person rewrites the next line while the model is still on it.
    const second = v.state.doc.line(2);
    act(() => v.dispatch({ changes: { from: second.from, to: second.to, insert: 'buy eggs and milk' }, userEvent: 'input.type' }));
    act(() => fakes[0]!.write('# Call Sam\n- Buy eggs\n'));
    expect(v.state.doc.toString()).toBe('# Call Sam\nbuy eggs and milk\n');
    act(() => fakes[0]!.finish('# Call Sam\n- Buy eggs\n'));
    await settle();
    expect(v.state.doc.toString()).toContain('# Call Sam\nbuy eggs and milk\n');
    expect(v.state.doc.toString()).not.toContain('- Buy eggs');
    // How many is told once, when the run is done, and the note's toast says it. One line was dropped, but it says 2:
    // a known fault in ai/land.ts Lander.finish, which counts the line as it lands and again as it reads the finished
    // answer over what landed. Pinned so a change to the count shows here; once finish() is fixed this reads [[1]].
    expect(dropped.mock.calls).toEqual([[2]]);
  });

  it('puts the model’s version above a rewritten line when it comes only with the finished answer (a known fault)', async () => {
    const dropped = vi.fn();
    const v = open('call sam\nbuy eggs\n');
    show(<Note noteId="n5" editor={v} onDropped={dropped} />);
    const started = startNoteRun(v, 'n5', 'format', ready);
    if (!started.ok) throw new Error(started.reason);
    await settle();
    act(() => fakes[0]!.write('# Call Sam\n'));
    const second = v.state.doc.line(2);
    act(() => v.dispatch({ changes: { from: second.from, to: second.to, insert: 'buy eggs and milk' }, userEvent: 'input.type' }));
    // The last line has no newline, so the model's version of it arrives only with the finished answer.
    act(() => fakes[0]!.finish('# Call Sam\n- Buy eggs'));
    await settle();
    // The person's line stays, but the model's is put in above it rather than dropped, and nothing says so: finish()
    // strikes up to the cursor without moving past the line the person touched, so it finds nothing ahead to match.
    // Pinned so a fix shows here; fixed, the note under its signature reads '# Call Sam\nbuy eggs and milk\n' and
    // onDropped says 1.
    expect(v.state.doc.toString()).toBe('---\nauthors: matt, Ghost\n---\n# Call Sam\n- Buy eggs\nbuy eggs and milk\n');
    expect(dropped).not.toHaveBeenCalled();
  });
});
