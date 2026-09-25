import { describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { bareWords, readInstruction, runOf } from './instruction.ts';

const notes = [
  { id: 'g', title: 'Groceries', note: makeNote('g', '# Groceries\n- milk\n') },
  { id: 'w', title: 'Work', note: makeNote('w', '# Work\nplain words\n') },
];

describe('the words themselves', () => {
  it('drops the keyword at the start and the lead-ins, and says whether the keyword was said', () => {
    expect(bareWords('Hey Ghost, please fix the spelling.', true)).toEqual({ words: 'fix the spelling', keyed: true });
    expect(bareWords('okay um, summarise it', false)).toEqual({ words: 'summarise it', keyed: false });
    expect(bareWords('I told Sam, hey Ghost, add eggs', true)).toBeNull();
  });
});

describe('a chip said in words', () => {
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
  it('is a run for a chip’s words, spoken or typed', async () => {
    expect(await readInstruction('hey ghost fix the spelling', notes, true)).toEqual({ kind: 'run', run: 'fix' });
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
    // A name the rules cannot read at all is an ask, never a wait on the command model.
    expect(await readInstruction('add eggs to the camping list', notes)).toEqual({ kind: 'ask', instruction: 'add eggs to the camping list' });
  });

  it('is an ask about the note for anything else typed, and spoken only after the keyword', async () => {
    expect(await readInstruction('add a heading about the budget', notes)).toEqual({ kind: 'ask', instruction: 'add a heading about the budget' });
    expect(await readInstruction('shorten the second paragraph', notes)).toEqual({ kind: 'ask', instruction: 'shorten the second paragraph' });
    expect(await readInstruction('hey ghost, shorten the second paragraph', notes, true)).toEqual({ kind: 'ask', instruction: 'shorten the second paragraph' });
    expect(await readInstruction('we should shorten the second paragraph', notes, true)).toEqual({ kind: 'words' });
  });
});
