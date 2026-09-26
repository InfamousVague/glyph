import { describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { bareWords, readInstruction, runOf } from './instruction.ts';

const notes = [
  { id: 'g', title: 'Groceries', note: makeNote('g', '# Groceries\n- milk\n') },
  { id: 'w', title: 'Work', note: makeNote('w', '# Work\nplain words\n') },
];

describe('the words themselves', () => {
  it('drops the keyword at the start and the lead-ins, and says whether the keyword was said', () => {
    expect(bareWords('Hey Ghost, please fix the spelling.')).toEqual({ words: 'fix the spelling', keyed: true, misheard: false });
    expect(bareWords('okay um, summarise it')).toEqual({ words: 'summarise it', keyed: false, misheard: false });
    expect(bareWords('I told Sam, hey Ghost, add eggs')).toBeNull();
  });
});

describe('a run said in words', () => {
  it('reads the phrasings that mean one kind', () => {
    expect(runOf('fix the spelling')).toBe('fix');
    expect(runOf('check my grammar')).toBe('fix');
    expect(runOf('summarise this')).toBe('summarize');
    expect(runOf('tidy it up')).toBe('format');
    expect(runOf('expand on this')).toBe('enhance');
    expect(runOf('carry on')).toBe('continue');
    expect(runOf('make this a list')).toBe('shape');
    expect(runOf('turn it into a table')).toBe('shape');
  });

  it('leaves a new list by name, and anything else, to the other readers', () => {
    expect(runOf('make a list called comic books')).toBeNull();
    expect(runOf('add eggs to groceries')).toBeNull();
    expect(runOf('add a heading about the budget')).toBeNull();
  });
});

describe('reading an instruction', () => {
  it('is a run for a run’s words, with the keyword or without', async () => {
    expect(await readInstruction('hey ghost fix the spelling', notes)).toEqual({ kind: 'run', run: 'fix' });
    expect(await readInstruction('Make this a list', notes)).toEqual({ kind: 'run', run: 'shape' });
  });

  it('is a command, to be confirmed, when a note is named', async () => {
    const read = await readInstruction('add eggs to groceries', notes);
    expect(read.kind).toBe('command');
    if (read.kind === 'command' && read.plan.kind === 'place') {
      expect(read.plan.note.id).toBe('g');
      expect(read.plan.text).toBe('eggs');
    }
    const made = await readInstruction('make a new list called comic books and add Batman and Superman', notes);
    expect(made).toMatchObject({ kind: 'command', plan: { kind: 'create-list', title: 'comic books', items: ['Batman', 'Superman'] } });
  });

  it('refuses a command that named a note there is no note for, with its reason', async () => {
    const read = await readInstruction('add to the camping list eggs and milk', notes);
    expect(read.kind).toBe('reject');
    // A name the rules cannot read at all is an ask after the keyword, not a refusal.
    expect(await readInstruction('hey ghost, add eggs to the camping list', notes)).toEqual({ kind: 'ask', instruction: 'add eggs to the camping list' });
  });

  it('is an ask about the note only after the keyword; without it, the words are the note’s', async () => {
    expect(await readInstruction('hey ghost, add a heading about the budget', notes)).toEqual({ kind: 'ask', instruction: 'add a heading about the budget' });
    expect(await readInstruction('hey ghost, shorten the second paragraph', notes)).toEqual({ kind: 'ask', instruction: 'shorten the second paragraph' });
    expect(await readInstruction('shorten the second paragraph', notes)).toMatchObject({ kind: 'words' });
    expect(await readInstruction('we should shorten the second paragraph', notes)).toEqual({ kind: 'words' });
  });
});

describe('the keyword as Whisper hears it', () => {
  const house = [...notes, { id: 'h', title: 'House TODOs', note: makeNote('h', '# House TODOs\n\n- [ ] Fix the gutter\n') }];

  it('takes filler before the keyword, and the mishearings of it when a command follows', () => {
    expect(bareWords('Um, hey Ghost, add call Sam to house to-dos.')).toEqual({ words: 'add call Sam to house to-dos', keyed: true, misheard: false });
    expect(bareWords("Hey, like add a note to house to do's")).toEqual({ words: "add a note to house to do's", keyed: false, misheard: true });
    expect(bareWords('Hey goes add a note to house to-dos')).toEqual({ words: 'add a note to house to-dos', keyed: false, misheard: true });
    // Not followed by a command, they are words: "Hey, like, the weather" is a note.
    expect(bareWords('Hey, like, the weather is lovely')).toMatchObject({ keyed: false, misheard: false });
    expect(bareWords('Hey goes the dog')).toMatchObject({ keyed: false, misheard: false });
    // Without the keyword, what a sentence starts with is its own: "And carry on tomorrow" is no run.
    expect(bareWords('And continue the story tomorrow.')).toEqual({ words: 'And continue the story tomorrow', keyed: false, misheard: false });
  });

  it.each([
    'Okay, like, make sure the door is locked.',
    'Hey, go add some colour to the living room walls, it would look nice.',
    'Hey, like, make sure the door is locked.',
    'Hey, like, fix the spelling on the sign.',
    'Hey goes, add a bit more salt next time.',
  ])('keeps how people talk as words, never an ask or a run: %s', async (said) => {
    expect(await readInstruction(said, house)).toMatchObject({ kind: 'words' });
  });

  it.each([
    "Hey, like add a note to house to do's, the note is call an electrician to fix the light sockets.",
    'Hey goes add a note to house to-dos. Call an electrician to fix the light sockets.',
    'Okay, hey Ghost, I want to add call an electrician to fix the light sockets to house to-dos.',
    'Hey Ghost, like, add a note to house chores. The note is call an electrician to fix the light sockets.',
  ])('is Matt’s command on House TODOs, however it opened: %s', async (said) => {
    const read = await readInstruction(said, house);
    expect(read).toMatchObject({ kind: 'command', plan: { kind: 'place', note: { id: 'h' } } });
    if (read.kind === 'command' && read.plan.kind === 'place') expect(read.plan.text).toMatch(/^call an electrician to fix the light sockets$/i);
  });
});
