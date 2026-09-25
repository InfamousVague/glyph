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

  describe('“make a new list called … and add …”', () => {
    const never = vi.fn(() => inferred({ status: 'unavailable', reason: 'not called' }));
    const heroes = ['Spider-Man', 'Batman', 'Superman', 'the Fantastic Four', 'the Green Lantern'];

    it.each([
      'make a new list called comic books and add to the list Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.',
      'Make a new list called comic books, and add Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern to it.',
      'Create a new list called comic books with Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.',
      'Okay, make a new list called comic books. Add these: Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.',
    ])('offers one new list titled Comic books with its items: %s', async (words) => {
      await expect(classifyFinalTranscript(words, notes, never)).resolves.toEqual({ kind: 'offer', conversational: false, plan: { kind: 'create-list', title: 'comic books', items: heroes } });
      expect(never).not.toHaveBeenCalled();
    });

    it('keeps a title that only contains “with”, and a list said with no items', async () => {
      await expect(classifyFinalTranscript('make a new list called books with pictures', notes, never)).resolves.toEqual({ kind: 'offer', conversational: false, plan: { kind: 'create-list', title: 'books with pictures' } });
      await expect(classifyFinalTranscript('make a new list called comic books', notes, never)).resolves.toEqual({ kind: 'offer', conversational: false, plan: { kind: 'create-list', title: 'comic books' } });
    });
  });

  describe('lists the model or the rules left as plain words', () => {
    const movies = [{ id: 'movies', title: 'Movies', note: { body: 'Movies\n\n- Jaws\n- Alien\n' } }];
    const films = ['The Matrix', 'Heat', 'Back to the Future'];

    it('keeps a list when the model returns no placement', async () => {
      const run = vi.fn(() => inferred({ status: 'intent', model: 'local', intent: { action: 'append', target: 'Movies', content: 'The Matrix, Heat and Back to the Future', placement: null } }));
      const decision = await classifyFinalTranscript('add to that one I call movies the Matrix, Heat and Back to the Future', movies, run);
      expect(decision).toMatchObject({ kind: 'offer', plan: { how: 'item', many: true, items: films } });
      if (decision.kind !== 'offer' || decision.plan.kind !== 'place') throw new Error('no offer');
      expect(placeWords(movies[0]!.note.body, decision.plan.text, decision.plan).body).toBe('Movies\n\n- Jaws\n- Alien\n- The Matrix\n- Heat\n- Back to the Future\n');
    });

    it('keeps a list when the command says “list” even if the model says paragraph-less null and the note is empty', async () => {
      const empty = [{ id: 'movies', title: 'Movies', note: { body: 'Movies' } }];
      const run = vi.fn(() => inferred({ status: 'intent', model: 'local', intent: { action: 'append', target: 'Movies', content: 'The Matrix; Heat; Back to the Future', placement: null } }));
      await expect(classifyFinalTranscript('add these to that movie list thing: the Matrix, Heat, Back to the Future', empty, run)).resolves.toMatchObject({ kind: 'offer', plan: { how: 'item', items: films } });
    });

    it('splits several short things added to a list note by the rules', async () => {
      await expect(classifyFinalTranscript('add to Movies the Matrix, Heat and Back to the Future', movies, never())).resolves.toMatchObject({ kind: 'offer', plan: { how: 'item', items: ['the Matrix', 'Heat', 'Back to the Future'] } });
    });

    it('leaves a sentence a sentence', async () => {
      const decision = await classifyFinalTranscript('add to Movies we should watch these on Friday, after dinner, with Sam and the kids if everyone is free', movies, never());
      expect(decision).toMatchObject({ kind: 'offer', plan: { how: 'leave' } });
    });
  });

  describe('a request anywhere in the recording', () => {
    const lists = [
      { id: 'movies', title: 'Movies', note: { body: 'Movies\n\n- Jaws\n' } },
      { id: 'groceries', title: 'Groceries', note: { body: 'Groceries\n\n- Eggs\n' } },
    ];

    it.each([
      ['Let’s add oat milk and bread to my groceries list.', 'groceries', ['oat milk', 'bread']],
      ['So I was at the store earlier and it was packed. Anyway, can you put oat milk and bread on the groceries list?', 'groceries', ['oat milk', 'bread']],
      ['I watched a bunch of stuff this weekend. Go ahead and add Heat, Alien and the Matrix to Movies.', 'movies', ['Heat', 'Alien', 'the Matrix']],
    ])('reads the request inside the talk: %s', async (words, id, items) => {
      const decision = await classifyFinalTranscript(words, lists, never());
      expect(decision).toMatchObject({ kind: 'offer', conversational: true, plan: { kind: 'place', note: { id }, items } });
    });

    it('lets the model reason over the whole recording, with the note titles, and make the list it asked for', async () => {
      const run = vi.fn((_words: string, _titles: readonly string[]) =>
        inferred({ status: 'intent', model: 'local', intent: { action: 'create', target: 'comic books', content: 'Spider-Man; Batman; The Fantastic Four' } }),
      );
      const words = 'Okay so I was reading last night and I really need a list of comic books, like Spider-Man, Batman and the Fantastic Four.';
      await expect(classifyFinalTranscript(words, lists, run)).resolves.toMatchObject({
        kind: 'offer',
        conversational: true,
        plan: { kind: 'create-list', title: 'Comic Books', items: ['Spider\\-Man', 'Batman', 'The Fantastic Four'] },
      });
      expect(run).toHaveBeenCalledWith(words, ['Movies', 'Groceries']);
    });

    it.each([
      'I need to make dinner and then add some photos to the album.',
      'I want to add more to this idea tomorrow when I have time.',
      'I told Sam to add oat milk to the groceries list.',
      'She said, “put it on the list”, and then left.',
      'We added the groceries list to the fridge door last week.',
    ])('leaves dictation as a note: %s', async (words) => {
      await expect(classifyFinalTranscript(words, lists, never())).resolves.toEqual({ kind: 'ordinary', notice: null });
    });

    it('keeps the recording as a note when a request found in it cannot be carried out', async () => {
      const unclear = vi.fn(() => inferred({ status: 'intent', model: 'local', intent: { action: 'none', reason: 'unclear' } }));
      await expect(classifyFinalTranscript('Honestly the note from yesterday was fine, I might make it a list someday.', lists, unclear)).resolves.toEqual({ kind: 'ordinary', notice: null });
      const missing = vi.fn(() => inferred({ status: 'intent', model: 'local', intent: { action: 'append', target: 'Camping', content: 'tent', placement: 'list' } }));
      await expect(classifyFinalTranscript('Before I forget, can you add a tent to the camping list?', lists, missing)).resolves.toMatchObject({ kind: 'ordinary', notice: expect.stringMatching(/Saved this recording as a note/) });
    });
  });
});

function never() {
  return vi.fn(() => inferred({ status: 'unavailable', reason: 'not called' }));
}