import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { aiChanges, landingField } from '../editor/aiChanges.ts';
import type { RunRequest } from './runs.ts';

const requests: RunRequest[] = [];
vi.mock('./runs.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('./runs.ts')>();
  return {
    ...real,
    startRun: (request: RunRequest) => {
      requests.push(request);
      return { id: 'r', done: Promise.resolve(), cancel: () => undefined };
    },
  };
});

const { placementOf, startNoteRun, wholeLines } = await import('./start.ts');

let view: EditorView | null = null;
function open(doc: string): EditorView {
  view = new EditorView({ state: EditorState.create({ doc, extensions: [aiChanges()] }) });
  return view;
}
afterEach(() => {
  view?.destroy();
  view = null;
  requests.length = 0;
});

const ready = { ok: true as const, model: 'qwen3.5-2b', chosen: 'qwen3.5-4b' };

describe('starting a run on the note', () => {
  it('places each kind: a rewrite over the words, a summary above, a continuation under', () => {
    expect(placementOf('format')).toBe('replace');
    expect(placementOf('ask')).toBe('replace');
    expect(placementOf('summarize')).toBe('prepend');
    expect(placementOf('continue')).toBe('append');
  });

  it('gives the model the note after its front matter, and lands the rewrite there', () => {
    const v = open('---\ntitle: "A"\n---\n# A\nwords\n');
    const started = startNoteRun(v, 'n', 'format', ready);
    expect(started.ok).toBe(true);
    expect(requests[0]).toMatchObject({ noteId: 'n', kind: 'format', model: 'qwen3.5-2b', prompt: '# A\nwords\n', scope: { from: 19, to: 29 } });
    expect(v.state.field(landingField)).toMatchObject({ start: 19, cursor: 19, oldEnd: 29 });
  });

  it('lands a summary above the note and a continuation under it', () => {
    const v = open('# A\nwords\n');
    startNoteRun(v, 'n', 'summarize', ready);
    expect(v.state.field(landingField)).toMatchObject({ start: 0, cursor: 0, oldEnd: 0 });
    startNoteRun(v, 'n', 'continue', ready);
    expect(v.state.field(landingField)).toMatchObject({ start: 10, cursor: 10, oldEnd: 10 });
    expect(requests[1]?.maxTokens).toBeLessThanOrEqual(512);
  });

  it('works on a part, widened to whole lines, with the rest of the note for context', () => {
    const v = open('# A\nfirst line here\nsecond line\nthird\n');
    expect(wholeLines(v, { from: 6, to: 22 })).toEqual({ from: 4, to: 31 });
    startNoteRun(v, 'n', 'fix', ready, { scope: { from: 6, to: 22 } });
    expect(requests[0]).toMatchObject({ kind: 'fix', prompt: 'first line here\nsecond line', scope: { from: 4, to: 31 } });
    expect(requests[0]?.system).toContain('ONE PART of a longer note');
    expect(requests[0]?.context).toContain('The rest of the note:\n# A\nfirst line here');
    expect(v.state.field(landingField)).toMatchObject({ start: 4, cursor: 4, oldEnd: 31 });
  });

  it('puts an ask’s instruction in with the note, and refuses an ask with none', () => {
    const v = open('# A\nwords\n');
    expect(startNoteRun(v, 'n', 'ask', ready)).toEqual({ ok: false, reason: 'Say what to do with the note.' });
    startNoteRun(v, 'n', 'ask', ready, { instruction: ' add a title ' });
    expect(requests[0]).toMatchObject({ kind: 'ask', instruction: 'add a title', prompt: 'Instruction: add a title\n\nThe note:\n# A\nwords\n' });
  });

  it('says why it cannot start', () => {
    const v = open('');
    expect(startNoteRun(v, 'n', 'format', ready)).toEqual({ ok: false, reason: 'Nothing in the note yet.' });
    expect(startNoteRun(v, 'n', 'format', { ok: false, reason: 'Not here.', get: null, waiting: false })).toEqual({ ok: false, reason: 'Not here.' });
    expect(requests).toEqual([]);
  });
});
