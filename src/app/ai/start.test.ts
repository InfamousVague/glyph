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

const { landingAt, placementOf, startNoteRun } = await import('./start.ts');
const { keepSummary } = await import('./summaryKeep.ts');

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

  it('gives the model a rule with words under it, which the editor shows as words (core/frontMatter.ts)', () => {
    const v = open('---\nSome words here\n---\n# A\n');
    startNoteRun(v, 'n', 'format', ready);
    expect(requests[0]).toMatchObject({ prompt: '---\nSome words here\n---\n# A\n', scope: { from: 0, to: 28 } });
    expect(v.state.field(landingField)).toMatchObject({ start: 0, cursor: 0, oldEnd: 28 });
  });

  it('lands a summary above the note and a continuation under it', () => {
    const v = open('# A\nwords\n');
    startNoteRun(v, 'n', 'summarize', ready);
    expect(v.state.field(landingField)).toMatchObject({ start: 0, cursor: 0, oldEnd: 0 });
    startNoteRun(v, 'n', 'continue', ready);
    expect(v.state.field(landingField)).toMatchObject({ start: 10, cursor: 10, oldEnd: 10 });
    expect(requests[1]?.maxTokens).toBeLessThanOrEqual(512);
  });

  it('puts an ask’s instruction in with the note, and refuses an ask with none', () => {
    const v = open('# A\nwords\n');
    expect(startNoteRun(v, 'n', 'ask', ready)).toEqual({ ok: false, reason: 'Say what to do with the note.' });
    startNoteRun(v, 'n', 'ask', ready, { instruction: ' add a title ' });
    expect(requests[0]).toMatchObject({ kind: 'ask', instruction: 'add a title', prompt: 'Instruction: add a title\n\nThe note:\n# A\nwords\n' });
  });

  it('lands a run placed on its own over its scope, whatever its kind would do', () => {
    expect(landingAt('summarize', { from: 8, to: 20 }, 40, 'replace')).toEqual({ start: 8, cursor: 8, oldEnd: 20 });
    expect(landingAt('summarize', { from: 8, to: 8 }, 40, 'replace')).toEqual({ start: 8, cursor: 8, oldEnd: 8 });
  });

  it('says why it cannot start', () => {
    const v = open('');
    expect(startNoteRun(v, 'n', 'format', ready)).toEqual({ ok: false, reason: 'Nothing in the note yet.' });
    expect(startNoteRun(v, 'n', 'format', { ok: false, reason: 'Not here.', get: null, waiting: false })).toEqual({ ok: false, reason: 'Not here.' });
    expect(requests).toEqual([]);
  });
});

describe('the recording’s summary as a run', () => {
  const recording = { words: 'That is the March launch settled. Sam owns the press list.', model: 'qwen3.5-4b', maxTokens: 300, replace: false };
  const ANSWER = '# March launch\nWhat the call settled.\n\n- Launch in March.\n\n- [ ] Book the venue.';
  const SECTION = '## Summary\nWhat the call settled.\n\n- Launch in March.\n\n- [ ] Book the venue.';

  it('is given the tape’s words and the recording prompt, and lands under the title with a blank line first', () => {
    const v = open('# Planning call\n\nWe started with the launch.');
    localStorage.clear();
    const started = startNoteRun(v, 'n', 'summarize', ready, { recording });
    expect(started.ok).toBe(true);
    expect(requests[0]).toMatchObject({ kind: 'summarize', model: 'qwen3.5-4b', prompt: recording.words, maxTokens: 300, scope: { from: 16, to: 16 }, placement: 'replace' });
    expect(requests[0]?.system).toContain('one recording');
    expect(v.state.field(landingField)).toMatchObject({ start: 16, cursor: 16, oldEnd: 16 });
    // The answer shaped as it streams: the model's heading never lands, and a blank line comes first.
    expect(requests[0]?.restore?.('# March launch\nWhat the call set', false)).toBe('\n## Summary\nWhat the call set');
    expect(requests[0]?.restore?.(ANSWER, true)).toBe(`\n${SECTION}`);
  });

  it('puts a blank line under a title that runs straight into its paragraph, so the section stands on its own', () => {
    const v = open('# Planning call\nWe started with the launch.');
    startNoteRun(v, 'n', 'summarize', ready, { recording });
    expect(v.state.doc.toString()).toBe('# Planning call\n\nWe started with the launch.');
    expect(requests[0]).toMatchObject({ scope: { from: 16, to: 16 } });
  });

  it('lands over the section the note has when it is still the app’s, carrying its ticked to-dos, and refuses one the person edited', () => {
    const old = '## Summary\nThe old line.\n\n- [x] Send Sam the list.\n- [ ] Book the venue.';
    const v = open(`# Planning call\n\n${old}\n\nWe started with the launch.`);
    keepSummary('n', { text: old, model: 'm', at: 1, forMs: 1000 });
    startNoteRun(v, 'n', 'summarize', ready, { recording });
    expect(requests[0]).toMatchObject({ scope: { from: 17, to: 17 + old.length }, placement: 'replace' });
    expect(v.state.field(landingField)).toMatchObject({ start: 17, cursor: 17, oldEnd: 17 + old.length });
    // No blank first over an old section, and the ticked to-do carried as it finishes.
    expect(requests[0]?.restore?.(ANSWER, false)).toBe(SECTION);
    expect(requests[0]?.restore?.(ANSWER, true)).toBe(`${SECTION}\n- [x] Send Sam the list.`);

    keepSummary('n', { text: '## Summary\nSomething else.', model: 'm', at: 1, forMs: 1000 });
    expect(startNoteRun(v, 'n', 'summarize', ready, { recording })).toEqual({ ok: false, reason: 'edited' });
    expect(startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, replace: true } }).ok).toBe(true);
    expect(startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, words: ' ' } })).toEqual({ ok: false, reason: 'nothing' });
  });
});

describe('where a run’s lines land', () => {
  it('is over the part for a rewrite, at the part’s start for a summary, and at the very end for a continuation', () => {
    const scope = { from: 12, to: 40 };
    expect(landingAt('format', scope, 60)).toEqual({ start: 12, cursor: 12, oldEnd: 40 });
    expect(landingAt('ask', scope, 60)).toEqual({ start: 12, cursor: 12, oldEnd: 40 });
    expect(landingAt('summarize', scope, 60)).toEqual({ start: 12, cursor: 12, oldEnd: 12 });
    expect(landingAt('continue', scope, 60)).toEqual({ start: 60, cursor: 60, oldEnd: 60 });
  });

  it('stays inside a note that has grown shorter since the run was asked for', () => {
    expect(landingAt('format', { from: 12, to: 40 }, 20)).toEqual({ start: 12, cursor: 12, oldEnd: 20 });
    expect(landingAt('summarize', { from: 30, to: 40 }, 20)).toEqual({ start: 20, cursor: 20, oldEnd: 20 });
  });
});
