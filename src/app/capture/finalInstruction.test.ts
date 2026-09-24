import { describe, expect, it, vi } from 'vitest';
import { classifyFinalTranscript } from './finalInstruction.ts';
import type { InferenceRun } from './instructionIntent.ts';
import { placeWords } from './listAppend.ts';

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

  describe('“add to my note labeled Go a list with…”', () => {
    const go = [{ id: 'go', title: 'Go', note: { body: '# Go\n' } }, ...notes.slice(1)];
    const places = ['Parkersburg, West Virginia', 'Marietta, Ohio', 'Balitmore, Maryland', 'Detroit, Michigan'];
    const never = vi.fn(() => inferred({ status: 'unavailable', reason: 'not called' }));

    it.each([
      'add to my note labeled go a list with parkersburg west virginia marietta ohio balitmore maryland and detroit michigan',
      'Add to my note labeled Go, a list with Parkersburg, West Virginia, Marietta, Ohio, Balitmore, Maryland and Detroit, Michigan.',
      'Hey Ghost, add to my note labeled Go a list with Parkersburg West Virginia, Marietta Ohio, Balitmore Maryland and Detroit Michigan.',
      'Okay, um, add to my note called “Go” a list of Parkersburg West Virginia Marietta Ohio Balitmore Maryland and Detroit Michigan',
    ])('offers the list for Go, one item per place: %s', async (words) => {
      const decision = await classifyFinalTranscript(words, go, never);
      expect(decision).toMatchObject({ kind: 'offer', plan: { kind: 'place', note: { id: 'go' }, how: 'item', many: true, items: places } });
      expect(never).not.toHaveBeenCalled();
      if (decision.kind !== 'offer' || decision.plan.kind !== 'place') throw new Error('no offer');
      expect(placeWords('# Go\n', decision.plan.text, decision.plan).body).toBe(`# Go\n\n${places.map((place) => `- ${place}`).join('\n')}\n`);
    });

    it('reads a to-do list as tasks', async () => {
      await expect(classifyFinalTranscript('add to my note labeled Go a to-do list with pack sunscreen, book hotel and fill the tank', go, never)).resolves.toMatchObject({
        kind: 'offer',
        plan: { how: 'item', task: true, items: ['pack sunscreen', 'book hotel', 'fill the tank'] },
      });
    });

    it('asks the on-device model before rejecting a name the rules could not match', async () => {
      const run = vi.fn(() => inferred({ status: 'intent', model: 'local', intent: { action: 'append', target: 'Go', content: 'Parkersburg, West Virginia; Detroit, Michigan', placement: 'list' } }));
      await expect(classifyFinalTranscript('add to that one I call go the places Parkersburg and Detroit', go, run)).resolves.toMatchObject({
        kind: 'offer',
        plan: { note: { id: 'go' }, how: 'item', items: ['Parkersburg, West Virginia', 'Detroit, Michigan'] },
      });
      expect(run).toHaveBeenCalledOnce();
    });

    it('still fails closed when neither the rules nor the model find the note', async () => {
      const unavailable = vi.fn(() => inferred({ status: 'unavailable', reason: 'no model' }));
      await expect(classifyFinalTranscript('add to my note labeled Nowhere a list with milk', go, unavailable)).resolves.toMatchObject({ kind: 'rejected' });
      const wrong = vi.fn(() => inferred({ status: 'intent', model: 'local', intent: { action: 'append', target: 'Nowhere', content: 'milk', placement: 'list' } }));
      await expect(classifyFinalTranscript('add to my note labeled Nowhere a list with milk', go, wrong)).resolves.toMatchObject({ kind: 'rejected' });
    });

    it('keeps a command said inside a sentence as words', async () => {
      await expect(classifyFinalTranscript('Okay so I told Sam to add to my note labeled Go a list', go, never)).resolves.toEqual({ kind: 'ordinary', notice: null });
    });
  });
});
