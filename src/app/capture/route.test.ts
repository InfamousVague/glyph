import { describe, expect, it } from 'vitest';
import { matchNote, parseRoute, similarity } from './route.ts';

const notes = [
  { id: 'a', title: 'Weekend trip' },
  { id: 'b', title: 'Shopping list' },
  { id: 'c', title: 'Work' },
  { id: 'd', title: 'Ideas for the garden' },
  { id: 'e', title: 'Weekend trip to the lake' },
];

describe('hearing "add to <note>"', () => {
  it('finds the command at the start and keeps what follows', () => {
    expect(parseRoute('Add to shopping list, oat milk and eggs.')).toEqual({ kind: 'note', name: 'shopping', rest: 'oat milk and eggs.' });
    expect(parseRoute('Put this in my work note. Email Sam about Friday.')).toEqual({ kind: 'note', name: 'work', rest: 'Email Sam about Friday.' });
  });

  it('finds the command at the end and keeps what came before', () => {
    expect(parseRoute('Oat milk and eggs, add that to the shopping list.')).toEqual({ kind: 'note', name: 'shopping', rest: 'Oat milk and eggs' });
    expect(parseRoute('Add to weekend trip.')).toEqual({ kind: 'note', name: 'weekend trip', rest: '' });
    expect(parseRoute('Switch to ideas for the garden')).toEqual({ kind: 'note', name: 'ideas for the garden', rest: '' });
  });

  it('hears "new note" only on its own', () => {
    expect(parseRoute('New note.')).toEqual({ kind: 'new', rest: '' });
    expect(parseRoute('I need a new notebook for school.')).toBeNull();
  });

  it('leaves ordinary sentences alone', () => {
    expect(parseRoute('We should add salt to the soup.')).toBeNull();
    expect(parseRoute('I went to the shops.')).toBeNull();
    expect(parseRoute('Remember to ask Sam about the dog.')).toBeNull();
  });

  it('does not take a name of a letter or two for a note', () => {
    expect(parseRoute('add to we')).toBeNull();
  });
});

describe('hearing "new item for <note>"', () => {
  it('takes the note name and an item said in the same phrase', () => {
    expect(parseRoute('New item for AttackFM, fix the login bug.')).toEqual({ kind: 'item', name: 'AttackFM', rest: 'fix the login bug.', task: false, many: false, target: null });
    expect(parseRoute('Add a task to the backlog: dark mode.')).toEqual({ kind: 'item', name: 'backlog', rest: 'dark mode.', task: true, many: false, target: null });
  });

  it('hears the command on its own, the item to follow', () => {
    expect(parseRoute('New item for AttackFM.')).toEqual({ kind: 'item', name: 'AttackFM', rest: '', task: false, many: false, target: null });
    expect(parseRoute('New to-dos for work.')).toMatchObject({ kind: 'item', name: 'work', task: true, many: true });
  });

  it('waits for the phrase to end, or the item to follow, before the name counts', () => {
    expect(parseRoute('new item for attack')).toBeNull();
  });

  it('leaves sentences about new items alone', () => {
    expect(parseRoute('The new item for AttackFM is great.')).toBeNull();
    expect(parseRoute('I bought a new thing for the kitchen yesterday and it broke.')).toBeNull();
  });
});

describe('an item command with a plugin’s word after the name', () => {
  it('takes the word off the name and says which it was', () => {
    expect(parseRoute('New task for AttackFM in Notion, fix the login bug.', { targets: ['notion'] })).toEqual({
      kind: 'item',
      name: 'AttackFM',
      rest: 'fix the login bug.',
      task: true,
      many: false,
      target: 'notion',
    });
  });

  it('leaves the word in the name when no plugin offers it', () => {
    expect(parseRoute('New task for AttackFM in Notion, fix the login bug.')).toMatchObject({ name: 'AttackFM in Notion', target: null });
  });
});

describe('matching a spoken name to a note', () => {
  it('forgives how speech recognition spells titles', () => {
    expect(similarity('week end trip', 'Weekend trip')).toBe(1);
    expect(similarity('weekend trips', 'Weekend trip')).toBeGreaterThan(0.9);
    expect(matchNote('the shopping', notes)?.note.id).toBe('b');
    expect(matchNote('shopping list', notes)?.note.id).toBe('b');
  });

  it('prefers the exact title over a longer one it starts', () => {
    expect(matchNote('weekend trip', notes)?.note.id).toBe('a');
    expect(matchNote('weekend trip to the lake', notes)?.note.id).toBe('e');
  });

  it('refuses a name that fits nothing, or fits two notes equally', () => {
    expect(matchNote('the oven', notes)).toBeNull();
    expect(matchNote('weekend', [{ id: 'x', title: 'Weekend trip' }, { id: 'y', title: 'Weekend plans' }])).toBeNull();
  });
});

describe('hearing "leave a note for <note> that says …"', () => {
  it('takes the note’s name and what the note says', () => {
    expect(parseRoute('Leave a note on the page for AttackFM that says the login is broken on Android.')).toEqual({
      kind: 'leave',
      name: 'AttackFM',
      rest: 'the login is broken on Android',
    });
    expect(parseRoute('Add a note to shopping list saying we are out of eggs')).toEqual({ kind: 'leave', name: 'shopping', rest: 'we are out of eggs' });
    expect(parseRoute('Write a quick note in my work note: call Sam about Friday.')).toEqual({ kind: 'leave', name: 'work', rest: 'call Sam about Friday' });
    expect(parseRoute('Can you leave a note for the weekend trip, book the cabin')).toEqual({ kind: 'leave', name: 'weekend trip', rest: 'book the cabin' });
    expect(parseRoute('Leave a note on the page called ideas for the garden that we need more mulch.')).toEqual({
      kind: 'leave',
      name: 'ideas for the garden',
      rest: 'we need more mulch',
    });
  });

  it('waits for the note when the phrase stops at the name', () => {
    expect(parseRoute('Leave a note for weekend trip.')).toEqual({ kind: 'leave', name: 'weekend trip', rest: '' });
    // A finished phrase with no stop could still be growing: not yet.
    expect(parseRoute('Leave a note for weekend trip')).toBeNull();
  });

  it('leaves ordinary sentences alone', () => {
    expect(parseRoute('I left a note on the fridge.')).toBeNull();
    expect(parseRoute('We should make a note of that.')).toBeNull();
  });
});
