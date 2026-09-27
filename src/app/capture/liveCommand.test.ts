import { describe, expect, it } from 'vitest';
import { bareEvidence, bareShape, commandWords, hearKeyword, isOpener, misheardShape, nameable, onlyFillerPhrase, onlyLead, payloadOf, readNameFirst, readRoute, silenceLine } from './liveCommand.ts';

/** The first reading of each shape, as the grammar gives them: name, payload, and the flags a test is about. */
const read = (text: string) => readRoute(commandWords(text)).map((r) => ({ shape: r.shape, name: r.name, payload: r.payload, stopped: r.stopped, split: r.split }));
const named = (text: string) => read(text).filter((r) => !r.split).map((r) => [r.name, r.payload]);

describe('hearing the keyword in a phrase', () => {
  const always = () => true;
  const never = () => false;

  it('hears it anywhere, with the words before it kept apart', () => {
    expect(hearKeyword('Hey Ghost, add a note to house to do’s.', never)).toEqual({ before: '', after: 'add a note to house to do’s.', misheard: false });
    expect(hearKeyword('Kevin owns the release, hey Ghost, add call Sam to work.', never)).toMatchObject({ before: 'Kevin owns the release', after: 'add call Sam to work.' });
  });

  it('hears its mishearings at the start only when a command follows, with or without a comma', () => {
    expect(hearKeyword('Hey, like, add a note to house to do’s, the note is call Sam.', always)).toMatchObject({ misheard: true, after: 'add a note to house to do’s, the note is call Sam.' });
    expect(hearKeyword('Hey goes add a note to house to-dos. Call an electrician.', always)).toMatchObject({ misheard: true });
    expect(hearKeyword('Hey, like, the weather is lovely.', never)).toBeNull();
    expect(hearKeyword('Okay, like, add a note to house to-dos.', always)).toBeNull();
    expect(hearKeyword('Hey, go add a note to house to-dos.', always)).toBeNull();
  });

  it('counts a mishearing only before a command for a note, by its shape, and a note named clearly', () => {
    const clear = () => true;
    for (const words of ['add a note to house to-dos, call Sam', 'add call Sam to house to-dos', 'add this to weekend trip: book the ferry', 'move this to daily life', 'new item for groceries, eggs']) {
      expect(misheardShape(commandWords(words), clear), words).toBe(true);
    }
    for (const words of ['I need to call my mum', 'I have to get this finished by Friday', 'new note', 'remind me to book the MOT', 'go to work', 'for groceries, eggs']) {
      expect(misheardShape(commandWords(words), clear), words).toBe(false);
    }
    expect(misheardShape('add a note to house to-dos, call Sam', () => false)).toBe(false);
  });
});

/**
 * The gate a phrase passes with no keyword (docs/DESIGN.md §136), by its words alone and then by the note it names.
 * Each sentence that stays out was a mis-fire the review of the design found.
 */
describe('the shapes a bare command may have', () => {
  const shapes = (text: string) => readRoute(commandWords(text)).filter(bareShape);
  const names = (text: string) => shapes(text).map((r) => r.name);

  it('takes a note or an item said for a note, a stopped “put this in”, “add X to Y”, a heading, and “move this”', () => {
    expect(names('add a note to house to-dos, call Sam')).toEqual(['house to-dos']);
    expect(names('new item for groceries, eggs')).toEqual(['groceries']);
    expect(names('put this in the house list, call Sam')).toEqual(['house list']);
    expect(names('add call Sam to house to-dos')).toContain('house to-dos');
    expect(names('add fix the tap under kitchen in home jobs')).toContain('home jobs');
    expect(names('move this to the garage')).toEqual(['garage']);
    expect(names('switch everything to work')).toEqual(['work']);
  });

  it('never takes a name from a split the grammar chose, a to-do for here, a name said first, or an unstopped “put this in”', () => {
    // "Another item on the agenda is the budget": the only name is the whole tail, never "agenda" with "is the budget" after it.
    const agenda = readRoute(commandWords('another item on the agenda is the budget'));
    expect(agenda.find((r) => r.name === 'agenda')).toMatchObject({ shape: 2, split: true, payload: 'is the budget' });
    expect(names('another item on the agenda is the budget')).toEqual(['agenda is the budget']);
    expect(names('add a note to house to-dos call Sam')).toEqual(['house to-dos call Sam']);
    for (const words of ['remind me to book the MOT', 'make a note to call the electrician', 'new note', 'for groceries, eggs', 'put this in weekend trip', 'add a note to call log', 'go to work', 'continue in the garage', 'move it to the garage', 'carry on in work']) {
      expect(names(words), words).toEqual([]);
    }
  });

  it('marks a move said plainly: “move this” or “switch this”, never “go to” or “move it”', () => {
    const plain = (text: string) => readRoute(text).find((r) => r.shape === 5)?.plainMove;
    expect(plain('go to work')).toBe(false);
    expect(plain('move this to work')).toBe(true);
    expect(plain('move it to work')).toBe(false);
    expect(plain('switch everything to work')).toBe(true);
    expect(plain('switch to weekend trip')).toBe(false);
    expect(plain('carry on in the garage')).toBe(false);
  });

  it('wants the name or the title to say what kind of list it is for “put this in”, “add X to Y” and a heading, and the heading to exist', () => {
    const one = (text: string) => shapes(text)[0]!;
    const sam = { title: 'Sam', body: '# Sam\n\n- Owes me a tenner\n' };
    const groceries = { title: 'Groceries', body: '# Groceries\n\n- Eggs\n' };
    const work = { title: 'Work', body: '# Work\n\nNotes.\n' };
    const jobs = { title: 'Home jobs', body: '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n' };
    expect(bareEvidence(one('send this to Sam, the deposit is due'), sam)).toBe(false);
    expect(bareEvidence(one('put this in the house list, call Sam'), work)).toBe(true);
    expect(bareEvidence(one('add oat milk to groceries'), groceries)).toBe(true);
    expect(bareEvidence(one('add call the plumber to work'), work)).toBe(false);
    expect(bareEvidence(one('add call the plumber to the work list'), work)).toBe(true);
    expect(bareEvidence(one('add fix the tap under kitchen in home jobs'), jobs)).toBe(true);
    expect(bareEvidence(one('add the key under the mat in home jobs'), jobs)).toBe(false);
    // "A note" said is its own evidence, whatever the title.
    expect(bareEvidence(one('add a note to work, call Sam'), work)).toBe(true);
    expect(bareEvidence(one('move this to work'), work)).toBe(true);
  });

  it('knows a phrase that is only the keyword’s lead, only filler, or Whisper’s line for a silence', () => {
    expect(onlyLead('Hey.')).toBe(true);
    expect(onlyLead('Hey Sam.')).toBe(false);
    expect(onlyFillerPhrase('Okay.')).toBe(true);
    expect(onlyFillerPhrase('Okay, the budget.')).toBe(false);
    expect(silenceLine('Thank you.')).toBe(true);
    expect(silenceLine('Thank you for coming.')).toBe(false);
  });

  it('takes the lead-ins off the command, never the words', () => {
    expect(commandWords('like, add a note to house to-dos')).toBe('add a note to house to-dos');
    expect(commandWords('can you add call Sam to work')).toBe('add call Sam to work');
    expect(commandWords('I want to add call Sam to work')).toBe('add call Sam to work');
    expect(commandWords('I want to go home')).toBe('I want to go home');
    expect(payloadOf('The note is call an electrician.')).toBe('call an electrician.');
  });
});

describe('the shapes of a command for a note', () => {
  it('reads Matt’s sentence with a stop, a comma, or nothing between the name and the note', () => {
    expect(named("add a note to house to do's. The note is call an electrician to fix the light sockets.")).toEqual([["house to do's", 'The note is call an electrician to fix the light sockets']]);
    expect(named("add a note to house to do's, the note is call an electrician")).toEqual([["house to do's", 'the note is call an electrician']]);
    expect(named("add a note to house to do's.")).toEqual([["house to do's", '']]);
    const bare = read("add a note to house to do's the note is call an electrician");
    expect(bare).toContainEqual({ shape: 1, name: "house to do's", payload: 'the note is call an electrician', stopped: false, split: true });
  });

  it('reads the thing, then the note, at every “to”, “in” or “on”', () => {
    const readings = read('add call an electrician to fix the light sockets to house to-dos.');
    expect(readings).toContainEqual({ shape: 4, name: 'house to-dos', payload: 'call an electrician to fix the light sockets', stopped: false, split: false });
    // A "name" that starts with a thing to do is no name.
    expect(readRoute('add call an electrician to fix the light sockets to house to-dos').find((r) => r.name.startsWith('fix'))?.verb).toBe(true);
  });

  it('keeps what follows a stop after a shape-four name as the take’s words, and what follows a comma as more of the thing', () => {
    expect(readRoute('add call Sam to house to-dos. Next, the budget review is Friday').find((r) => r.shape === 4)).toMatchObject({ name: 'house to-dos', payload: 'call Sam', trailing: 'Next, the budget review is Friday' });
    expect(readRoute('add milk to groceries, eggs').find((r) => r.shape === 4)).toMatchObject({ name: 'groceries', payload: 'milk, eggs' });
    expect(readRoute('add milk to groceries and eggs')).toContainEqual(expect.objectContaining({ name: 'groceries', payload: 'milk, eggs', split: true }));
  });

  it('keeps what was said after the verb, for a name that finds nothing to give back', () => {
    expect(readRoute('add a note to moon base pack sunscreen').find((r) => !r.split)).toMatchObject({ name: 'moon base pack sunscreen', tail: 'moon base pack sunscreen' });
    expect(readRoute('add eggs to the moon base').find((r) => r.shape === 4)).toMatchObject({ name: 'moon base', payload: 'eggs', tail: 'eggs to the moon base' });
  });

  // A take-back's send, said in a breath of its own after "scratch that" (takeBack.ts): "instead" is not the name's.
  it('leaves “instead” off the end of a name', () => {
    expect(readRoute('add it to Groceries instead.').find((r) => r.shape === 4)).toMatchObject({ name: 'Groceries', payload: '' });
    expect(readRoute('put that in house to-dos instead').find((r) => r.shape === 4)).toMatchObject({ name: 'house to-dos', payload: '' });
    expect(readRoute('add milk to groceries instead').find((r) => r.shape === 4)).toMatchObject({ name: 'groceries', payload: 'milk' });
  });

  it('ends a thing’s name at “that says”, and reads a paragraph asked for as the kind of words, not the words', () => {
    expect(readRoute('add a paragraph to Groceries that says we are out of bread').find((r) => r.shape === 4)).toMatchObject({ name: 'Groceries', payload: 'we are out of bread', placing: 'paragraph', stopped: true });
    expect(readRoute('add milk to groceries saying it is urgent').find((r) => r.shape === 4)).toMatchObject({ name: 'groceries', payload: 'milk, it is urgent' });
  });

  it('reads the other openings', () => {
    expect(readRoute('new item for house to-dos, call Sam')[0]).toMatchObject({ shape: 2, name: 'house to-dos', payload: 'call Sam', placing: 'item', noun: true });
    expect(readRoute('add to house to-dos, call Sam')[0]).toMatchObject({ shape: 3, name: 'house to-dos', payload: 'call Sam' });
    expect(readRoute('add a to-do to house to-dos')[0]).toMatchObject({ shape: 1, placing: 'task' });
    expect(readRoute('switch to weekend trip')).toContainEqual(expect.objectContaining({ shape: 5, name: 'weekend trip', move: true }));
    expect(readRoute('move this to the weekend trip')).toContainEqual(expect.objectContaining({ shape: 5, name: 'weekend trip', move: true }));
    expect(readRoute('put this under kitchen in house to-dos')).toContainEqual(expect.objectContaining({ shape: 8, name: 'house to-dos', heading: 'kitchen', payload: '' }));
    expect(readRoute('new note.')).toEqual([expect.objectContaining({ newNote: true })]);
    expect(readNameFirst('for groceries, eggs and milk')).toEqual([expect.objectContaining({ name: 'groceries', payload: 'eggs and milk', nameFirst: true })]);
    expect(readNameFirst('House TODOs: call Sam')).toEqual([expect.objectContaining({ name: 'House TODOs', payload: 'call Sam' })]);
  });

  it('reads a to-do for the note being written to', () => {
    expect(readRoute('remind me to book the MOT')).toEqual([expect.objectContaining({ self: true, payload: 'book the MOT', placing: 'task' })]);
    expect(readRoute('make a note to call the electrician')).toContainEqual(expect.objectContaining({ self: true, payload: 'call the electrician', placing: 'task' }));
    expect(readRoute('add a to-do: call Sam')).toEqual([expect.objectContaining({ self: true, payload: 'call Sam' })]);
    expect(readRoute('add eggs here')).toEqual([expect.objectContaining({ self: true, payload: 'eggs', placing: 'item' })]);
  });

  it('reads nothing for a note where there is no note', () => {
    for (const words of [
      'put the dates in a table',
      'add a summary to the top',
      'fix the spelling',
      'make a list called packing',
      'add a table to this note',
      'add a chapter to the field guide',
      'make this a board',
      'make a book called trips',
    ]) {
      expect(readRoute(words).filter((r) => !r.verb), words).toEqual([]);
    }
    expect(nameable('a table')).toBe('not');
    expect(nameable('the bottom')).toBe('not');
    expect(nameable('call the bank')).toBe('verb');
    expect(nameable('house to-dos')).toBe('name');
  });

  it('knows a command still waiting for its name', () => {
    for (const words of ['', 'add a note to', 'add eggs to', 'new item for', 'move this to', 'for', 'add']) expect(isOpener(words), words).toBe(true);
    for (const words of ['add a note to house', 'fix the spelling', 'call Sam']) expect(isOpener(words), words).toBe(false);
  });
});
