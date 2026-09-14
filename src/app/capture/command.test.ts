import { describe, expect, it } from 'vitest';
import { findKeyword, planCommand, reply } from './command.ts';

const notes = [
  { id: 'b', title: 'AttackFM Bugbash' },
  { id: 'h', title: 'HelloTrade' },
  { id: 'g', title: 'Glyph Notes' },
  { id: 'p', title: 'Places to Go' },
  { id: 'w', title: 'Work' },
];
const plan = (words: string, targets: string[] = []) => planCommand(words, { notes, targets });
const at = (id: string) => notes.find((n) => n.id === id)!;

describe('hearing the keyword', () => {
  it('finds "Glyph" and splits the words around it', () => {
    expect(findKeyword('Glyph, add buy milk to hello trade.')).toEqual({ before: '', after: 'add buy milk to hello trade.' });
    expect(findKeyword('Pick up the parcel. Hey Glyph add that to work')).toEqual({ before: 'Pick up the parcel.', after: 'add that to work' });
    expect(findKeyword('Okay, glyph.')).toEqual({ before: '', after: '' });
  });

  it('takes the spellings speech recognition writes for it', () => {
    expect(findKeyword('Glif, new note.')?.after).toBe('new note.');
    expect(findKeyword('Gliff add eggs to work')?.after).toBe('add eggs to work');
  });

  it('is not fooled by words that contain it or sound near it', () => {
    expect(findKeyword('The hieroglyphs were beautiful.')).toBeNull();
    expect(findKeyword('We climbed the cliff at dawn.')).toBeNull();
  });
});

describe('a yes or a no', () => {
  it('hears short replies either way', () => {
    expect(reply('Yes.')).toBe('yes');
    expect(reply('Yeah, do it')).toBe('yes');
    expect(reply('Um, okay.')).toBe('yes');
    expect(reply('No.')).toBe('no');
    expect(reply('Cancel that')).toBe('no');
    expect(reply('Never mind.')).toBe('no');
  });

  it('leaves sentences alone', () => {
    expect(reply('No problem with the invoice from last week.')).toBeNull();
    expect(reply('Buy milk.')).toBeNull();
  });
});

describe('what a command asks for', () => {
  it('adds a thing to a note named after it, the way people say it', () => {
    expect(plan('add buy milk to the hello trade.')).toEqual({ kind: 'place', note: at('h'), text: 'buy milk', how: 'leave', task: false, many: false, target: null });
    expect(plan('put call Sam on the work list')).toMatchObject({ kind: 'place', note: at('w'), text: 'call Sam' });
    expect(plan('add to work: call Sam')).toMatchObject({ kind: 'place', note: at('w'), text: 'call Sam' });
  });

  it('adds a list item when one is asked for, and waits for it when it is not said yet', () => {
    expect(plan('add a list item to the hello trade')).toEqual({ kind: 'await', note: at('h'), how: 'item', task: false, many: false, target: null });
    expect(plan('add a task buy stamps to work')).toMatchObject({ kind: 'place', note: at('w'), text: 'buy stamps', how: 'item', task: true });
    expect(plan('new item for hello trade, fix the login')).toMatchObject({ kind: 'place', note: at('h'), text: 'fix the login', how: 'item' });
  });

  it('waits for what to add when a note is named alone', () => {
    expect(plan('add a note to hello trade')).toMatchObject({ kind: 'await', note: at('h'), how: 'leave' });
    expect(plan('leave a note for places to go that says the lake by the cabin')).toMatchObject({ kind: 'place', note: at('p'), text: 'the lake by the cabin' });
  });

  it('moves the take, or starts a new note', () => {
    expect(plan('switch to work')).toEqual({ kind: 'move', note: at('w') });
    expect(plan('move this to the hello trade note')).toEqual({ kind: 'move', note: at('h') });
    expect(plan('new note')).toEqual({ kind: 'new' });
  });

  it('carries a plugin’s word after the note’s name', () => {
    expect(plan('new task for hello trade in Notion, ship it', ['notion'])).toMatchObject({ kind: 'place', note: at('h'), target: 'notion', how: 'item', task: true });
  });

  it('says so when the note named does not exist, and waits when nothing is a command yet', () => {
    expect(plan('add eggs to the shopping list')).toBeNull();
    expect(plan('new item for groceries, eggs')).toEqual({ kind: 'no-note', name: 'groceries' });
    expect(plan('add')).toBeNull();
    expect(plan('')).toBeNull();
  });
});

describe('asking for a table', () => {
  it('names the note, or means this one', () => {
    expect(plan('add a table to the attackfm bugbash note')).toEqual({ kind: 'table', note: at('b'), columns: [] });
    expect(plan('make a new table.')).toEqual({ kind: 'table', note: null, columns: [] });
  });

  it('takes column labels said up front', () => {
    expect(plan('add a table to hello trade with columns bug, owner and status')).toEqual({ kind: 'table', note: at('h'), columns: ['Bug', 'Owner', 'Status'] });
  });

  it('says so for a note that is not there, and is not fooled by other tables', () => {
    expect(plan('add a table to the groceries note')).toEqual({ kind: 'no-note', name: 'groceries' });
    expect(plan('add a table of contents')).toBeNull();
  });
});
