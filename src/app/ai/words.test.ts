import { describe, expect, it } from 'vitest';
import type { RunState } from './runs.ts';
import { clock, progressOf, recordSentence, runSentence } from './words.ts';

const run = (patch: Partial<RunState>): RunState => ({
  id: 'r',
  noteId: 'n',
  kind: 'format',
  instruction: null,
  model: 'qwen3.5-4b',
  scope: null,
  phase: 'generating',
  lines: [],
  partial: '',
  thought: '',
  text: null,
  promptTokens: 400,
  promptTokensDone: 400,
  outputTokens: 50,
  maxTokens: 200,
  tokensPerSecond: 31.4,
  elapsedMs: 12_000,
  hardware: null,
  truncated: false,
  message: null,
  startedAt: 0,
  endedAt: null,
  hash: null,
  ...patch,
});

describe('what the strip says', () => {
  it('names the phase, the model, the pace and the time', () => {
    expect(runSentence(run({ phase: 'queued' }))).toBe('Waiting for the model, which is on another note.');
    expect(runSentence(run({ phase: 'loading' }))).toBe('Loading Qwen3.5 4B.');
    expect(runSentence(run({ phase: 'prefill', promptTokensDone: 120 }))).toBe('Reading the note, 120 of 400.');
    expect(runSentence(run({ phase: 'prefill', promptTokens: 0 }))).toBe('Reading the note.');
    expect(runSentence(run({}))).toBe('Formatting with Qwen3.5 4B, 31 tokens a second, 0:12.');
    expect(runSentence(run({ lines: ['a', 'b'], tokensPerSecond: 7.25 }))).toBe('Formatting with Qwen3.5 4B, 7.3 tokens a second, 0:12, 2 lines.');
    expect(runSentence(run({ lines: ['a'] }))).toContain(', 1 line.');
  });

  it('says what an ask was asked, since the verb alone says nothing', () => {
    expect(runSentence(run({ kind: 'ask', instruction: 'make it shorter' }))).toBe('“make it shorter” with Qwen3.5 4B, 31 tokens a second, 0:12.');
  });

  it('says how a run ended', () => {
    expect(runSentence(run({ phase: 'done', elapsedMs: 42_000 }))).toBe('Formatted by Qwen3.5 4B in 0:42.');
    expect(runSentence(run({ phase: 'done', kind: 'summarize', truncated: true }))).toBe('Summarized by Qwen3.5 4B in 0:12. It ran out of room; try a shorter note.');
    expect(runSentence(run({ phase: 'stopped' }))).toBe('Stopped.');
    expect(runSentence(run({ phase: 'failed', message: 'The model went away.' }))).toBe('The model went away.');
    expect(runSentence(run({ phase: 'failed' }))).toBe('The model stopped.');
  });

  it('measures the bar against the note while reading and the budget while writing', () => {
    expect(progressOf(run({ phase: 'prefill', promptTokensDone: 100 }))).toBe(0.25);
    expect(progressOf(run({ outputTokens: 50, maxTokens: 200 }))).toBe(0.25);
    expect(progressOf(run({ outputTokens: 500, maxTokens: 200 }))).toBe(1);
    expect(progressOf(run({ phase: 'loading' }))).toBeNull();
    expect(progressOf(run({ phase: 'queued' }))).toBeNull();
    expect(progressOf(run({ phase: 'done' }))).toBe(1);
    expect(progressOf(run({ phase: 'stopped' }))).toBeNull();
  });

  it('reads a clock as minutes and seconds', () => {
    expect(clock(0)).toBe('0:00');
    expect(clock(61_500)).toBe('1:02');
  });

  it('writes the log in one line each', () => {
    expect(recordSentence({ kind: 'format', instruction: null, model: 'qwen3.5-2b', ms: 9_000, outcome: 'done', message: null })).toBe('Format by Qwen3.5 2B in 0:09.');
    expect(recordSentence({ kind: 'ask', instruction: 'add a title', model: 'qwen3.5-2b', ms: 9_000, outcome: 'done', message: null })).toBe('“add a title” by Qwen3.5 2B in 0:09.');
    expect(recordSentence({ kind: 'enhance', instruction: null, model: 'qwen3.5-2b', ms: 3_000, outcome: 'stopped', message: null })).toBe('Enhance, stopped after 0:03.');
    expect(recordSentence({ kind: 'fix', instruction: null, model: 'qwen3.5-2b', ms: 3_000, outcome: 'failed', message: 'No room.' })).toBe('Fix spelling failed: No room.');
  });
});
