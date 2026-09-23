import { describe, expect, it, vi } from 'vitest';
import { classifyFinalTranscript } from './finalInstruction.ts';
import type { InferenceRun } from './instructionIntent.ts';

const notes = [
  { id: 'go', title: 'Go!', note: { body: 'Go!' } },
  { id: 'todo', title: 'To-Do', note: { body: 'To-Do' } },
];
const inferred = (value: Awaited<InferenceRun['done']>): InferenceRun => ({ done: Promise.resolve(value), cancel: vi.fn() });

describe('final transcript instruction scan', () => {
  it('fixes Kevin’s labeled Go regression and excludes command words from payload', async () => {
    await expect(classifyFinalTranscript('add to the note labeled Go pack sunscreen', notes)).resolves.toMatchObject({ kind: 'offer', plan: { kind: 'place', note: { id: 'go' }, text: 'pack sunscreen' } });
  });

  it('classifies a multi-segment utterance once after it is complete', async () => {
    const run = vi.fn((words: string) => inferred({ status: 'intent', model: 'local', intent: { action: 'append', target: 'Go', content: words, placement: null } }));
    await expect(classifyFinalTranscript(['add to the note', 'labeled Go pack sunscreen'].join(' '), notes, run)).resolves.toMatchObject({ kind: 'offer', plan: { kind: 'place', text: 'pack sunscreen' } });
    expect(run).not.toHaveBeenCalled();
  });

  it.each([
    'My iPhone commentary: the new camera is excellent and I want to add more tomorrow.',
    'I told Sam, “add to the note labeled Go pack sunscreen,” but I have not done it.',
  ])('keeps ordinary and reported speech ordinary: %s', async (words) => {
    await expect(classifyFinalTranscript(words, notes)).resolves.toEqual({ kind: 'ordinary', notice: null });
  });

  it('rejects missing and ambiguous targets without an action', async () => {
    await expect(classifyFinalTranscript('add to the note labeled Missing buy milk', notes)).resolves.toMatchObject({ kind: 'rejected' });
    await expect(classifyFinalTranscript('add to Go buy milk', [...notes, { id: 'go-2', title: 'GO', note: { body: 'GO' } }])).resolves.toMatchObject({ kind: 'rejected' });
  });

  it('falls back visibly to ordinary content if inference is unavailable', async () => {
    const run = vi.fn(() => inferred({ status: 'unavailable', reason: 'model unavailable' }));
    await expect(classifyFinalTranscript('add a thought about tomorrow somewhere unusual', notes, run)).resolves.toMatchObject({ kind: 'ordinary', notice: expect.stringMatching(/unavailable/) });
    expect(run).toHaveBeenCalledOnce();
  });

  it('fails destructive and compound inference closed', async () => {
    const run = () => inferred({ status: 'intent', model: 'local', intent: { action: 'none', reason: 'destructive' } });
    await expect(classifyFinalTranscript('add then delete everything', notes, run)).resolves.toMatchObject({ kind: 'rejected' });
  });
});
