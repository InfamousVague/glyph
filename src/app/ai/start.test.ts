import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { aiChanges, aiChangesField, landingField } from '../editor/aiChanges.ts';
import type { RunRequest, RunState } from './runs.ts';

/** Every run asked for; each answers `done` as a finished run, so what follows the end (the title) can be seen. */
const requests: RunRequest[] = [];
vi.mock('./runs.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('./runs.ts')>();
  return {
    ...real,
    startRun: (request: RunRequest) => {
      requests.push(request);
      return { id: `r${requests.length}`, done: Promise.resolve({ phase: 'done' } as RunState), cancel: () => undefined };
    },
  };
});

const { landingAt, placementOf, startNoteRun } = await import('./start.ts');
const { Lander } = await import('./land.ts');
const { allLines } = await import('./runs.ts');
const { keepSummary, readSummary } = await import('./summaryKeep.ts');
const { summarySection } = await import('./summaryText.ts');
const { runsOf } = await import('./log.ts');

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

  /** The last run's answer streamed through its restore into a lander a character at a time, then finished: the note as it reads after. */
  function stream(v: EditorView, answer: string): string {
    const request = requests[requests.length - 1]!;
    const restore = request.restore!;
    const lander = new Lander(v, `r${requests.length}`, { wisp: false, haptic: false }, v.state.doc.toString());
    for (let n = 1; n <= answer.length; n += 1) lander.land(restore(answer.slice(0, n), false).split('\n').slice(0, -1));
    lander.finish(allLines(restore(answer, true)));
    return v.state.doc.toString();
  }

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
    // The scope takes the section's newline with it, so the lander does not put another after its last line.
    expect(requests[0]).toMatchObject({ scope: { from: 17, to: 17 + old.length + 1 }, placement: 'replace' });
    expect(v.state.field(landingField)).toMatchObject({ start: 17, cursor: 17, oldEnd: 17 + old.length + 1 });
    // No blank first over an old section, and the ticked to-do carried as it finishes.
    expect(requests[0]?.restore?.(ANSWER, false)).toBe(SECTION);
    expect(requests[0]?.restore?.(ANSWER, true)).toBe(`${SECTION}\n- [x] Send Sam the list.`);

    keepSummary('n', { text: '## Summary\nSomething else.', model: 'm', at: 1, forMs: 1000 });
    expect(startNoteRun(v, 'n', 'summarize', ready, { recording })).toEqual({ ok: false, reason: 'edited' });
    expect(startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, replace: true } }).ok).toBe(true);
    expect(startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, words: ' ' } })).toEqual({ ok: false, reason: 'nothing' });
  });

  it('remakes the section in place: the same answer leaves the note as it was, a shorter one leaves one blank line under it', () => {
    const old = '## Summary\nThe old line.\n\n- Launch moves.\n\n- [ ] Book the venue.';
    const body = `# Planning call\n\n${old}\n\nWe started with the launch.`;
    const v = open(body);
    keepSummary('n', { text: old, model: 'm', at: 1, forMs: 1000 });
    startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, replace: true } });
    expect(stream(v, '# T\nThe old line.\n\n- Launch moves.\n\n- [ ] Book the venue.')).toBe(body);
    startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, replace: true } });
    expect(stream(v, '# T\nA newer line.\n\n- [ ] One thing.')).toBe('# Planning call\n\n## Summary\nA newer line.\n\n- [ ] One thing.\n\nWe started with the launch.');
  });

  it('is closed by the kept text, so a list of the person’s under it is neither the section nor edited', () => {
    const written = '## Summary\nWhat the call settled.\n\n- [ ] Book the venue.';
    const list = '- [ ] Call Sam\n- [ ] Book the room';
    const v = open(`# Planning call\n\n${written}\n\n${list}`);
    keepSummary('n', { text: written, model: 'm', at: 1, forMs: 1000 });
    const started = startNoteRun(v, 'n', 'summarize', ready, { recording });
    expect(started.ok).toBe(true);
    expect(requests[0]).toMatchObject({ scope: { from: 17, to: 17 + written.length + 1 } });
    expect(stream(v, '# T\nA newer line.\n\n- [ ] Book the venue before the 10th.')).toBe(`# Planning call\n\n## Summary\nA newer line.\n\n- [ ] Book the venue before the 10th.\n\n${list}`);
  });

  it('lands the model’s heading as the title of a note with no words, which the section would otherwise title', () => {
    expect(startNoteRun(open(''), 'n', 'summarize', ready, { recording }).ok).toBe(true);
    expect(stream(view!, ANSWER)).toBe(`# March launch\n\n${SECTION}\n`);
    expect(startNoteRun(open('![](image/a.jpg)'), 'n', 'summarize', ready, { recording }).ok).toBe(true);
    expect(stream(view!, ANSWER)).toBe(`![](image/a.jpg)\n\n# March launch\n\n${SECTION}\n`);
  });

  it('takes the model’s heading as the title once the run is done, only while the note wears a meeting’s date title', async () => {
    const v = open('# Meeting, 26 Sep 14:05\n\nWords.');
    startNoteRun(v, 'n', 'summarize', ready, { recording });
    requests[0]!.restore!(ANSWER, true);
    await Promise.resolve();
    expect(v.state.doc.toString()).toBe('# March launch\n\nWords.');
    const kept = open('# Sam’s call\n\nWords.');
    startNoteRun(kept, 'n', 'summarize', ready, { recording });
    requests[1]!.restore!(ANSWER, true);
    await Promise.resolve();
    expect(kept.state.doc.toString()).toBe('# Sam’s call\n\nWords.');
  });

  it('lands an answer the queue already has at once, as tracked changes with no run, and answers the section as landed', () => {
    const v = open('# Planning call\n\nWe started with the launch.');
    const started = startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, text: ANSWER } });
    expect(started).toEqual({ ok: true, landed: SECTION });
    expect(requests).toEqual([]);
    // Signed by the AI as a run's landing is (ai/useLanding.ts).
    expect(v.state.doc.toString()).toBe(`---\nauthors: Ghost\n---\n# Planning call\n\n${SECTION}\n\nWe started with the launch.`);
    expect(summarySection(v.state.doc.toString())?.text).toBe(SECTION);
    // Marked as the AI's lines, with the bookmark put away, and the before and after in the log for Undo.
    expect(v.state.field(aiChangesField).length).toBeGreaterThan(0);
    expect(v.state.field(landingField)).toBeNull();
    expect(runsOf('n').some((r) => r.before === '# Planning call\n\nWe started with the launch.')).toBe(true);
    // Over an old section the same way, and refused for one the person edited.
    keepSummary('n', { text: SECTION, model: 'm', at: 1, forMs: 1000 });
    const again = startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, text: '# T\nA newer line.\n\n- [ ] One thing.' } });
    expect(again).toEqual({ ok: true, landed: '## Summary\nA newer line.\n\n- [ ] One thing.' });
    expect(v.state.doc.toString()).toBe('---\nauthors: Ghost\n---\n# Planning call\n\n## Summary\nA newer line.\n\n- [ ] One thing.\n\nWe started with the launch.');
    expect(startNoteRun(v, 'n', 'summarize', ready, { recording: { ...recording, text: ANSWER } })).toEqual({ ok: false, reason: 'edited' });
    expect(readSummary('n')?.text).toBe(SECTION);
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
