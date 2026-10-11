import { describe, expect, it } from 'vitest';
import { bookNoteBody } from '../book/book.ts';
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

  // The rules are anchored at the front, so without the keyword a run is the whole phrase and its object, and nothing more (docs/DESIGN.md §136).
  it('is the whole phrase, with `whole`, so a sentence that opens with a run’s words is not the run', () => {
    for (const said of ['fix the spelling', 'tidy it up', 'carry on', 'summarise it for me', 'summarize this', 'make this a list', 'tidy this up', 'flesh it out please', 'summarise that', 'summarise the note', 'summarise this note', 'tidy up everything', 'carry on now']) {
      expect(runOf(said, { whole: true }), said).not.toBeNull();
    }
    for (const said of SENTENCES) {
      expect(runOf(said, { whole: true }), said).toBeNull();
      expect(runOf(said), said).not.toBeNull();
    }
  });
});

/** Sentences that open with a run's words: each was a run on main, and rewrote the note it was said into. */
const SENTENCES = [
  'Fix the spelling of Kowalski on the sign before Friday',
  'Tidy up the garage before the weekend',
  'Organise a meeting with the team',
  'Continue the discussion with Sam tomorrow',
  'Summarise the call with Jo',
  'Keep going with the fence on Saturday',
];

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

  it('refuses a command that named a note there is no note for after the keyword, and without it saves the words with the reason', async () => {
    const keyed = await readInstruction('hey ghost, add to the camping list eggs and milk', notes);
    expect(keyed).toEqual({ kind: 'reject', reason: 'No unambiguous note matches “camping”. Nothing changed.' });
    // Without the keyword, the person never said it was a command: the words are the note's, and the chip says why.
    const bare = await readInstruction('add to the camping list eggs and milk', notes);
    expect(bare).toEqual({ kind: 'words', notice: 'No note called “camping”, so the words are saved as a note.' });
    // The name as said, up to its comma, where the rules at Done carried the words after it too.
    expect(await readInstruction('Add to shopping, oat milk.', notes)).toEqual({ kind: 'words', notice: 'No note called “shopping”, so the words are saved as a note.' });
    expect(await readInstruction('Hey Ghost, add to shopping, oat milk.', notes)).toMatchObject({ kind: 'reject' });
    // A name the rules cannot read at all is an ask after the keyword, not a refusal.
    expect(await readInstruction('hey ghost, add eggs to the camping list', notes)).toEqual({ kind: 'ask', instruction: 'add eggs to the camping list' });
  });

  it('reads a run without the keyword only as the whole phrase; with it, a sentence that opens with one is the run', async () => {
    for (const said of SENTENCES) {
      expect(await readInstruction(`${said}.`, notes), said).toEqual({ kind: 'words' });
      expect((await readInstruction(`Hey Ghost, ${said.charAt(0).toLowerCase()}${said.slice(1)}.`, notes)).kind, said).toBe('run');
    }
    for (const said of ['Fix the spelling.', 'Tidy it up.', 'Carry on.', 'Summarise it for me.']) {
      expect((await readInstruction(said, notes)).kind, said).toBe('run');
    }
  });

  it('is an ask about the note only after the keyword; without it, the words are the note’s', async () => {
    expect(await readInstruction('hey ghost, add a heading about the budget', notes)).toEqual({ kind: 'ask', instruction: 'add a heading about the budget' });
    expect(await readInstruction('hey ghost, shorten the second paragraph', notes)).toEqual({ kind: 'ask', instruction: 'shorten the second paragraph' });
    expect(await readInstruction('shorten the second paragraph', notes)).toMatchObject({ kind: 'words' });
    expect(await readInstruction('we should shorten the second paragraph', notes)).toEqual({ kind: 'words' });
  });
});

/**
 * What the live reader's gate kept as words, read again at Done from a transcript with no keyword (docs/DESIGN.md
 * §136): words here too, never a card whose Cancel lets the recording go. The keyword still makes each a card.
 */
describe('the reader at Done, without the keyword', () => {
  const library = [
    ...notes,
    { id: 'h', title: 'House TODOs', note: makeNote('h', '# House TODOs\n\n- [ ] Fix the gutter\n') },
    { id: 'b', title: 'Bowl', note: makeNote('b', '# Bowl\n\nBlue.\n') },
    { id: 'c', title: 'Car insurance', note: makeNote('c', '# Car insurance\n\n- Renew\n') },
    { id: 't', title: 'Weekend trip', note: makeNote('t', '# Weekend trip\n\nThe cabin.\n') },
    { id: 'p', title: 'Porch light', note: makeNote('p', '# Porch light\n\n- Bulb\n') },
    { id: 'o', title: 'Post', note: makeNote('o', '# Post\n\nLetters.\n') },
    { id: 'm', title: 'Team', note: makeNote('m', '# Team\n\n- Kevin\n') },
    { id: 'go', title: 'Go', note: makeNote('go', '# Go\n') },
  ];

  it.each([
    'Add call the plumber to work.',
    'Add the flour to the bowl. Then stir it for a minute.',
    'Put this in the car, then drive.',
    'Put the spare key under the mat on the porch. Then lock up.',
    'Add a note to the weekend, book the ferry.',
    'Put this in the weekend trip, book the ferry.',
    'Put the parcel in the post.',
    'Add Kevin to the team.',
    'Put the washing in the house.',
  ])('keeps what the live reader kept as words: %s', async (said) => {
    expect(await readInstruction(said, library)).toEqual({ kind: 'words' });
    expect((await readInstruction(`Hey Ghost, ${said.charAt(0).toLowerCase()}${said.slice(1)}`, library)).kind, said).toBe('command');
  });

  it('still offers what the live reader carries out, a note labelled by name, and a new list', async () => {
    expect(await readInstruction('Add oat milk to groceries.', library)).toMatchObject({ kind: 'command', plan: { kind: 'place', note: { id: 'g' } } });
    expect(await readInstruction('Add call Sam to House TODOs.', library)).toMatchObject({ kind: 'command', plan: { kind: 'place', note: { id: 'h' } } });
    // "Go" starts with a verb, so the live reader has no bare reading of it to turn down: the card is the second chance.
    expect(await readInstruction('add to the note labeled Go pack sunscreen', library)).toMatchObject({ kind: 'command', plan: { kind: 'place', note: { id: 'go' } } });
    expect(await readInstruction('Make a list called Comic books.', library)).toMatchObject({ kind: 'command', plan: { kind: 'create-list', title: 'Comic books' } });
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
    // The gate is the bare gate, shared with the live reader: a note called Sam with a bullet is no evidence.
    'Hey, like, put this in Sam, the deposit is due.',
    // A book is never written into by voice, so a mishearing before its name is words, never a card.
    'Hey, like, add a note to field guide, call Sam.',
  ])('keeps how people talk as words, never an ask or a run: %s', async (said) => {
    const sam = [...house, { id: 's', title: 'Sam', note: makeNote('s', '# Sam\n\n- Owes me a tenner\n') }, { id: 'f', title: 'Field guide', note: makeNote('f', bookNoteBody('Field guide', ['Trees'])) }];
    expect(await readInstruction(said, sam)).toMatchObject({ kind: 'words' });
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
