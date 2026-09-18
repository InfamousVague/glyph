import { describe, expect, it } from 'vitest';
import { askWords, chooseNote, guessNote, opensLikeCommand, parseChoice, parseTrigger, saysFinished, saysNeverMind } from './memoFlow.ts';

const notes = [
  { id: 'g', title: 'Groceries' },
  { id: 'w', title: 'Work' },
  { id: 't', title: 'Weekend trip' },
  { id: 'p', title: 'Weekend plans' },
  { id: 'a', title: 'AttackFM bug bash' },
];
const options = notes.slice(0, 3);
const choose = (text: string) => {
  const choice = parseChoice(text);
  return choice ? chooseNote(choice, options, notes) : null;
};

describe('which note', () => {
  it('takes a name after a word that says it is one', () => {
    expect(parseChoice('Use note groceries.')).toEqual({ kind: 'name', name: 'groceries', explicit: true });
    expect(parseChoice('Select the work note')).toEqual({ kind: 'name', name: 'work', explicit: true });
    expect(parseChoice('Open weekend trip.')).toEqual({ kind: 'name', name: 'weekend trip', explicit: true });
    expect(parseChoice('Okay, go to my groceries list.')).toEqual({ kind: 'name', name: 'groceries', explicit: true });
    expect(parseChoice('Select the note called AttackFM bug bash.')).toEqual({ kind: 'name', name: 'AttackFM bug bash', explicit: true });
  });

  it('takes a bare name too, and a place in the list', () => {
    expect(parseChoice('Weekend trip.')).toEqual({ kind: 'name', name: 'Weekend trip', explicit: false });
    expect(parseChoice('The first one.')).toEqual({ kind: 'ordinal', index: 0 });
    expect(parseChoice('Number two')).toEqual({ kind: 'ordinal', index: 1 });
    expect(parseChoice('the third')).toEqual({ kind: 'ordinal', index: 2 });
  });

  it('takes "new note", with or without a title', () => {
    expect(parseChoice('New note.')).toEqual({ kind: 'new', title: '' });
    expect(parseChoice('Start a new note called camping.')).toEqual({ kind: 'new', title: 'camping' });
    expect(parseChoice('new note for the trip')).toEqual({ kind: 'new', title: 'trip' });
  });

  it('is still asking after "use note" with nothing after it', () => {
    expect(parseChoice('Use note.')).toBeNull();
    expect(parseChoice('Select a note')).toBeNull();
    expect(parseChoice('')).toBeNull();
  });

  it('finds the note a name means, more leniently after "use note"', () => {
    expect(choose('Use note grocery.')).toEqual({ kind: 'note', note: notes[0] });
    expect(choose('Select note attack bug bash')).toEqual({ kind: 'note', note: notes[4] });
    expect(choose('Work.')).toEqual({ kind: 'note', note: notes[1] });
    expect(choose('The second one.')).toEqual({ kind: 'note', note: notes[1] });
    expect(choose('New note called camping.')).toEqual({ kind: 'new', title: 'camping' });
  });

  it('says so when a name fits nothing, or fits two', () => {
    expect(choose('Use note camping.')).toEqual({ kind: 'none', said: 'camping' });
    expect(choose('Number five.')).toEqual({ kind: 'none', said: 'number 5' });
    // A bare phrase that only half fits a title is talk, not a choice.
    expect(choose('I think the grocery run is tomorrow.')).toEqual({ kind: 'none', said: 'I think the grocery run is tomorrow' });
    const unsure = choose('Use note weekend.');
    expect(unsure?.kind).toBe('unsure');
    if (unsure?.kind === 'unsure') expect(unsure.between.map((n) => n.id).sort()).toEqual(['p', 't']);
  });

  it('guesses the note while the name is still being said', () => {
    expect(guessNote('use note groc', options, notes)?.id).toBe('g');
    expect(guessNote('select attack', options, notes)?.id).toBe('a');
    expect(guessNote('use note weekend', options, notes)).toBeNull();
    expect(guessNote('the second', options, notes)?.id).toBe('w');
    expect(guessNote('so um', options, notes)).toBeNull();
  });
});

describe('what to add', () => {
  it('reads the trigger words, and what came with them', () => {
    expect(parseTrigger('Add task.')).toEqual({ kind: 'ask', ask: { what: 'task', many: false }, said: '' });
    expect(parseTrigger('Add a to-do.')).toEqual({ kind: 'ask', ask: { what: 'task', many: false }, said: '' });
    expect(parseTrigger('New task: buy milk.')).toEqual({ kind: 'ask', ask: { what: 'task', many: false }, said: 'buy milk' });
    expect(parseTrigger('Add task buy milk')).toEqual({ kind: 'ask', ask: { what: 'task', many: false }, said: 'buy milk' });
    expect(parseTrigger('Add tasks.')).toEqual({ kind: 'ask', ask: { what: 'task', many: true }, said: '' });
    expect(parseTrigger('Add an item saying call Sam.')).toEqual({ kind: 'ask', ask: { what: 'item', many: false }, said: 'call Sam' });
    expect(parseTrigger('Add a bullet point.')).toEqual({ kind: 'ask', ask: { what: 'item', many: false }, said: '' });
    expect(parseTrigger('Add a line.')).toEqual({ kind: 'ask', ask: { what: 'line', many: false }, said: '' });
    expect(parseTrigger('Add a note, we are out of coffee.')).toEqual({ kind: 'ask', ask: { what: 'line', many: false }, said: 'we are out of coffee' });
  });

  it('reads switching, a new note, and undo', () => {
    expect(parseTrigger('Switch note.')).toEqual({ kind: 'switch', name: null });
    expect(parseTrigger('Use a different note')).toEqual({ kind: 'switch', name: null });
    expect(parseTrigger('Switch to work.')).toEqual({ kind: 'switch', name: 'work' });
    expect(parseTrigger('Change to the note called groceries')).toEqual({ kind: 'switch', name: 'groceries' });
    expect(parseTrigger('New note called camping.')).toEqual({ kind: 'new', title: 'camping' });
    expect(parseTrigger('Undo.')).toEqual({ kind: 'undo' });
    expect(parseTrigger('Scratch that')).toEqual({ kind: 'undo' });
  });

  it('leaves talk alone', () => {
    expect(parseTrigger('We should add the numbers up before Friday.')).toBeNull();
    expect(parseTrigger('Put the kettle on.')).toBeNull();
    expect(parseTrigger('The new task list is long.')).toBeNull();
    expect(parseTrigger('I made a note of it.')).toBeNull();
    expect(opensLikeCommand('Add task.')).toBe(true);
    expect(opensLikeCommand('Put the kettle on.')).toBe(true);
    expect(opensLikeCommand('We should add the numbers up.')).toBe(false);
  });

  it('knows the end of several, and a change of mind', () => {
    expect(saysFinished('Done.')).toBe(true);
    expect(saysFinished("That's all.")).toBe(true);
    expect(saysFinished('Done with the dishes.')).toBe(false);
    expect(saysNeverMind('Never mind.')).toBe(true);
    expect(saysNeverMind('No, cancel that.')).toBe(true);
    expect(saysNeverMind('Nothing else matters.')).toBe(false);
  });

  it('asks in its own words', () => {
    expect(askWords({ what: 'task', many: false })).toEqual({ heading: 'Adding a task', question: 'What task should we add?', hint: 'Say it, or “never mind”.' });
    expect(askWords({ what: 'item', many: false }).heading).toBe('Adding an item');
    expect(askWords({ what: 'line', many: false }).question).toBe('What should it say?');
    expect(askWords({ what: 'task', many: true }).question).toBe('What tasks should we add?');
  });
});
