import { describe, expect, it } from 'vitest';
import type { RunState } from '../ai/runs.ts';
import { runSentence } from '../ai/words.ts';
import { glowOf, glowStepOf, litPinsOf, liveWords, NOTHING_TO_COMPARE, pinsOf, sceneDetail, sceneTitle, stepsOf, titlePieces, warmthOf, workingStep, type SceneInput } from './steps.ts';

/**
 * The scene's words and heat, from what the review is doing: the steps in order, which is working, what the title
 * says (word for word the strip's own where they are shared), and the die's warmth and glow.
 */

function run(over: Partial<RunState> = {}): RunState {
  return {
    id: 'run-1',
    noteId: 'n',
    kind: 'review',
    instruction: null,
    model: 'qwen3.5-4b',
    scope: null,
    phase: 'loading',
    lines: [],
    partial: '',
    thought: '',
    text: null,
    promptTokens: 0,
    promptTokensDone: 0,
    outputTokens: 0,
    maxTokens: 1900,
    tokensPerSecond: 0,
    elapsedMs: 0,
    hardware: null,
    truncated: false,
    message: null,
    startedAt: 0,
    endedAt: null,
    hash: null,
    ...over,
  };
}

function input(over: Partial<SceneInput> = {}): SceneInput {
  return { stage: null, download: null, run: null, hasJob: true, compared: null, ended: false, ...over };
}

const listening = (percent: number | null) => ({ what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent });
const comparing = (detail: string) => ({ what: 'Comparing', detail, percent: null });
const ids = (steps: ReturnType<typeof stepsOf>) => steps.map((s) => s.id);
const states = (steps: ReturnType<typeof stepsOf>) => steps.map((s) => `${s.id}:${s.state}`);

describe('the steps', () => {
  it('draws six in the order things happen with a job, and five without', () => {
    expect(ids(stepsOf(input()))).toEqual(['listen', 'load', 'read', 'think', 'write', 'done']);
    expect(ids(stepsOf(input({ hasJob: false })))).toEqual(['load', 'read', 'think', 'write', 'done']);
    // At the opening the first step is the one working, and the rest wait.
    expect(states(stepsOf(input()))).toEqual(['listen:working', 'load:waiting', 'read:waiting', 'think:waiting', 'write:waiting', 'done:waiting']);
  });

  it('ticks the listen step when Comparing arrives, with its detail kept after the stage clears', () => {
    const detail = '3 places where the two models heard different words.';
    const compared = stepsOf(input({ stage: comparing(detail), compared: detail }));
    expect(compared[0]).toEqual({ id: 'listen', words: 'Listening again', state: 'done', detail });
    expect(compared[1]?.state).toBe('working');
    const later = stepsOf(input({ compared: detail, run: run({ phase: 'prefill' }) }));
    expect(later[0]).toMatchObject({ state: 'done', detail });
  });

  it('skips the listen step when there was nothing to compare against, with the reason as its detail', () => {
    const steps = stepsOf(input({ stage: comparing(NOTHING_TO_COMPARE), compared: NOTHING_TO_COMPARE }));
    expect(steps[0]).toEqual({ id: 'listen', words: 'Listening again', state: 'skipped', detail: NOTHING_TO_COMPARE });
    expect(steps[1]?.state).toBe('working');
  });

  it('puts the download’s words in the listen step while it downloads', () => {
    const steps = stepsOf(input({ stage: listening(0), download: { received: 12e6, total: 190e6 } }));
    expect(steps[0]?.detail).toBe('Getting the better voice model, 12 of 190 MB.');
  });

  it('lets a stage win over a live run', () => {
    const steps = stepsOf(input({ stage: listening(40), run: run({ phase: 'generating', kind: 'ask' }) }));
    expect(steps[0]?.state).toBe('working');
    expect(workingStep(input({ stage: listening(40), run: run({ phase: 'generating' }) }))).toBe('listen');
    expect(sceneTitle(input({ stage: listening(40), run: run({ phase: 'generating' }) }))).toBe('Listening again, 40%.');
  });

  it('advances the working step with each phase of the run', () => {
    const compared = 'Both models heard the same words.';
    const at = (over: Partial<RunState>) => workingStep(input({ compared, run: run(over) }));
    expect(at({ phase: 'queued' })).toBe('load');
    expect(at({ phase: 'loading' })).toBe('load');
    expect(at({ phase: 'prefill' })).toBe('read');
    expect(at({ phase: 'generating' })).toBe('think');
    expect(at({ phase: 'generating', thought: 'Is seat right?' })).toBe('think');
    expect(at({ phase: 'generating', thought: 'Is seat right?', partial: '[{"what": "' })).toBe('write');
    expect(at({ phase: 'done', text: '[]', lines: ['[]'] })).toBeNull();
    expect(states(stepsOf(input({ compared, run: run({ phase: 'done', text: '[]', lines: ['[]'] }) })))).toEqual(['listen:done', 'load:done', 'read:done', 'think:done', 'write:done', 'done:done']);
  });

  it('shows the load step working while the run is queued', () => {
    expect(stepsOf(input({ run: run({ phase: 'queued' }) }))[1]).toMatchObject({ id: 'load', state: 'working' });
  });

  it('ticks nothing more once the run stopped or failed', () => {
    const stopped = stepsOf(input({ compared: 'x', run: run({ phase: 'stopped', thought: 'Was thinking', endedAt: 1 }) }));
    expect(states(stopped)).toEqual(['listen:done', 'load:done', 'read:done', 'think:waiting', 'write:waiting', 'done:waiting']);
    expect(workingStep(input({ compared: 'x', run: run({ phase: 'failed', message: 'Out of memory.' }) }))).toBeNull();
  });

  it('uses a summary’s words for a run of that kind, with no listen and no thinking', () => {
    const steps = stepsOf(input({ run: run({ kind: 'summarize', phase: 'prefill' }) }));
    expect(steps.map((s) => s.words)).toEqual(['Loading the model', 'Reading the recording', 'Writing the summary', 'Done']);
  });

  it('ticks every step when the review is over with no run', () => {
    expect(states(stepsOf(input({ ended: true })))).toEqual(['listen:done', 'load:done', 'read:done', 'think:done', 'write:done', 'done:done']);
  });
});

describe('the title', () => {
  it('says every line in the app’s voice, word for word the strip’s where they share one', () => {
    expect(sceneTitle(input())).toBe('Checking what was heard.');
    expect(sceneTitle(input({ stage: listening(0), download: { received: 12e6, total: 190e6 } }))).toBe('Getting the better voice model, 12 of 190 MB.');
    expect(sceneTitle(input({ stage: listening(0) }))).toBe('Listening again.');
    expect(sceneTitle(input({ stage: listening(40) }))).toBe('Listening again, 40%.');
    expect(sceneTitle(input({ stage: comparing('x') }))).toBe('Comparing.');
    const queued = run({ phase: 'queued' });
    expect(sceneTitle(input({ run: queued }))).toBe('Waiting for the model, which is on another note.');
    expect(sceneTitle(input({ run: queued }))).toBe(runSentence(queued));
    const loading = run({ phase: 'loading' });
    expect(sceneTitle(input({ run: loading }))).toBe('Loading Qwen3.5 4B.');
    expect(sceneTitle(input({ run: loading }))).toBe(runSentence(loading));
    const reading = run({ phase: 'prefill', promptTokens: 1040, promptTokensDone: 312 });
    expect(sceneTitle(input({ run: reading }))).toBe('Reading the note, 312 of 1040.');
    expect(sceneTitle(input({ run: reading }))).toBe(runSentence(reading));
    expect(sceneTitle(input({ run: run({ phase: 'prefill' }) }))).toBe('Reading the note.');
    expect(sceneTitle(input({ run: run({ phase: 'generating', thought: 'Hmm' }) }))).toBe('Qwen3.5 4B is thinking it through.');
    expect(sceneTitle(input({ run: run({ phase: 'generating', thought: 'Hmm', partial: '[' }) }))).toBe('Qwen3.5 4B is writing what it found.');
    expect(sceneTitle(input({ run: run({ kind: 'summarize', phase: 'generating' }) }))).toBe('Summarizing with Qwen3.5 4B.');
    const done = run({ phase: 'done', elapsedMs: 72_000, text: '[]', lines: ['[]'] });
    expect(sceneTitle(input({ run: done }))).toBe('Reviewed by Qwen3.5 4B in 1:12.');
    expect(sceneTitle(input({ run: done }))).toBe(runSentence(done));
    const cut = run({ phase: 'done', elapsedMs: 72_000, text: '[]', lines: ['[]'], truncated: true });
    expect(sceneTitle(input({ run: cut }))).toBe(runSentence(cut));
    expect(sceneTitle(input({ run: run({ phase: 'stopped' }) }))).toBe('Stopped.');
    expect(sceneTitle(input({ run: run({ phase: 'failed', message: 'The model stopped.' }) }))).toBe('The model stopped.');
    expect(sceneTitle(input({ ended: true }))).toBe('Done.');
  });

  it('has a detail for each moment', () => {
    expect(sceneDetail(input())).toBe('The recording is saved.');
    expect(sceneDetail(input({ stage: listening(0), download: { received: 0, total: 1 } }))).toBe('Once, then it stays on the phone.');
    expect(sceneDetail(input({ stage: listening(10) }))).toBe('The slower speech model is listening to the recording again.');
    expect(sceneDetail(input({ run: run({ phase: 'queued' }) }))).toBe('');
    expect(sceneDetail(input({ run: run({ phase: 'loading' }) }))).toBe('2.7 GB on this phone.');
    expect(sceneDetail(input({ run: run({ phase: 'prefill' }) }))).toBe('The note and everything that was heard.');
    expect(sceneDetail(input({ run: run({ phase: 'generating' }) }))).toBe('Thinking it through out loud.');
    expect(sceneDetail(input({ run: run({ phase: 'generating', partial: '[' }) }))).toBe('What it finds is checked against the note, then marked.');
    expect(sceneDetail(input({ run: run({ phase: 'done' }) }))).toBe('');
    expect(sceneDetail(input({ ended: true }))).toBe('');
  });

  it('parts the progress numbers from the words, and leaves a model’s name whole', () => {
    expect(titlePieces('Reading the note, 312 of 1040.')).toEqual([
      { text: 'Reading the note', number: false },
      { text: ', 312 of 1040', number: true },
      { text: '.', number: false },
    ]);
    expect(titlePieces('Listening again, 40%.')).toEqual([
      { text: 'Listening again', number: false },
      { text: ', 40%', number: true },
      { text: '.', number: false },
    ]);
    expect(titlePieces('Reviewed by Qwen3.5 4B in 1:12.')).toEqual([
      { text: 'Reviewed by Qwen3.5 4B', number: false },
      { text: ' in 1:12', number: true },
      { text: '.', number: false },
    ]);
    expect(titlePieces('Qwen3.5 4B is thinking it through.')).toEqual([{ text: 'Qwen3.5 4B is thinking it through.', number: false }]);
  });

  it('changes the live line only with the step, never with a number', () => {
    expect(liveWords(input({ stage: listening(10) }))).toBe('Listening again.');
    expect(liveWords(input({ stage: listening(40) }))).toBe('Listening again.');
    expect(liveWords(input({ run: run({ phase: 'prefill', promptTokens: 100, promptTokensDone: 10 }) }))).toBe('Reading the note.');
    expect(liveWords(input({ run: run({ phase: 'prefill', promptTokens: 100, promptTokensDone: 90 }) }))).toBe('Reading the note.');
    expect(liveWords(input({ run: run({ phase: 'generating' }) }))).toBe('Thinking it through.');
    expect(liveWords(input({ run: run({ phase: 'done', elapsedMs: 3000 }) }))).toBe('Reviewed by Qwen3.5 4B in 0:03.');
    expect(liveWords(input({ ended: true }))).toBe('Done.');
  });
});

describe('the heat', () => {
  it('is cold, warm or hot by state', () => {
    expect(warmthOf(input())).toBe('cold');
    expect(warmthOf(input({ stage: listening(0) }))).toBe('warm');
    expect(warmthOf(input({ stage: listening(0), download: { received: 0, total: 1 } }))).toBe('warm');
    expect(warmthOf(input({ run: run({ phase: 'queued' }) }))).toBe('cold');
    expect(warmthOf(input({ run: run({ phase: 'loading' }) }))).toBe('warm');
    expect(warmthOf(input({ run: run({ phase: 'prefill' }) }))).toBe('hot');
    expect(warmthOf(input({ run: run({ phase: 'generating' }) }))).toBe('hot');
    expect(warmthOf(input({ run: run({ phase: 'done' }) }))).toBe('cold');
    expect(warmthOf(input({ run: run({ phase: 'stopped' }) }))).toBe('cold');
    expect(warmthOf(input({ ended: true }))).toBe('cold');
  });

  it('glows only from a sample past loading, busy over the engine’s threads, blended with the heat', () => {
    const hardware = { rssBytes: 3e9, freeBytes: 4e9, totalBytes: 12e9, cpuPercent: 640, threads: 6, cores: 8 };
    expect(glowOf(null)).toBe(0);
    expect(glowOf(run({ phase: 'prefill' }))).toBe(0);
    expect(glowOf(run({ phase: 'loading', hardware }))).toBe(0);
    // Six threads at full tilt is full, whatever the eighth core is doing.
    expect(glowOf(run({ phase: 'generating', hardware }))).toBe(1);
    expect(glowOf(run({ phase: 'generating', hardware: { ...hardware, cpuPercent: 300 } }))).toBe(0.5);
    expect(glowOf(run({ phase: 'generating', hardware: { ...hardware, cpuPercent: 900 } }))).toBe(1);
    // With a temperature, half and half: 40 °C is half way from 20 to 60.
    expect(glowOf(run({ phase: 'generating', hardware: { ...hardware, tempC: 40 } }))).toBe(0.75);
    expect(glowOf(run({ phase: 'generating', hardware: { ...hardware, cpuPercent: 0, tempC: 70 } }))).toBe(0.5);
    // Cooled once it has ended.
    expect(glowOf(run({ phase: 'done', hardware }))).toBe(0);
    // No threads reported: the cores, held between two and six.
    expect(glowOf(run({ phase: 'generating', hardware: { ...hardware, threads: 0, cpuPercent: 600 } }))).toBe(1);
  });

  it('steps the glow to a ring, and lights a pin a core', () => {
    expect(glowStepOf(0)).toBe(0);
    expect(glowStepOf(0.5)).toBe(3);
    expect(glowStepOf(1)).toBe(5);
    expect(glowStepOf(1.4)).toBe(5);
    expect(litPinsOf(640, 8)).toBe(6);
    expect(litPinsOf(0, 8)).toBe(0);
    expect(litPinsOf(1200, 8)).toBe(8);
    expect(pinsOf(8)).toBe(8);
    expect(pinsOf(16)).toBe(12);
    expect(pinsOf(1)).toBe(2);
  });
});
