import { describe, expect, it } from 'vitest';
import { bookNoteBody } from '../book/book.ts';
import { LiveTake, type LiveTakeOptions, type MemoryNote } from './liveTake.ts';
import { LIVE_TIMING } from './liveRoute.ts';

const HOUSE = '# House TODOs\n\n- [ ] Fix the gutter\n';
const library = (): MemoryNote[] => [
  { id: 'house', body: HOUSE },
  { id: 'todo', body: '# Todo\n' },
  { id: 'tasks', body: '# Task Management\n' },
  { id: 'daily', body: '# Daily Life\n\nWent for a walk.\n' },
  { id: 'jobs', body: '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n' },
  { id: 's1', body: '# Signing in, and signing\n' },
  { id: 's2', body: '# Signing the order\n' },
  { id: 'groceries', body: '# Groceries\n\n- Eggs\n' },
  { id: 'book', body: bookNoteBody('Field guide', ['Trees']) },
  { id: 'call', body: '# Call log\n' },
];

/** A recording: phrases said one after another, each a second apart unless told otherwise, on a clock of its own. */
function record(options: LiveTakeOptions & { notes?: MemoryNote[] } = {}) {
  const take = new LiveTake(options.notes ?? library(), options);
  let now = 0;
  let at = 0;
  const say = (text: string, gap = 1000) => {
    take.phrase({ text, startMs: at, endMs: at + 900 }, now);
    at += gap;
    now += gap;
    take.tick(now);
  };
  const wait = (ms: number) => {
    for (let t = 0; t < ms; t += 250) {
      now += 250;
      take.tick(now);
    }
    at += ms;
  };
  const done = () => take.close(now);
  return { take, say, wait, done, now: () => now };
}

const lastChip = (take: LiveTake) => take.chips.at(-1);

describe('Matt’s sentence, as Whisper commits it', () => {
  it('switches to House TODOs and writes the to-do into its list, in two phrases', () => {
    const { take, say, done } = record();
    say("Hey Ghost, add a note to house to do's.");
    expect(take.aim?.id).toBe('house');
    expect(lastChip(take)).toEqual({ phase: 'waiting', title: 'House TODOs', many: false, leave: true });
    expect(take.live.awaitingPayload).toBe(true);
    // What is being said now is for the chip, until it is committed.
    expect(take.live.hearingCommand).toBe(true);
    say('The note is call an electrician to fix the light sockets.');
    expect(take.live.hearingCommand).toBe(false);
    // The page shows it arriving in the list as it is said; nothing is a new note.
    expect(take.page()).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n');
    done();
    expect(take.result()).toMatchObject({ made: [] });
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n');
  });

  it.each([
    "Hey Ghost, add a note to house to do's. The note is call an electrician to fix the light sockets.",
    "Hey Ghost, add a note to house to do's, the note is call an electrician to fix the light sockets.",
    'Hey Ghost, add a note to house chores, the note is call an electrician to fix the light sockets.',
    "Hey, like, add a note to house to do's, the note is call an electrician to fix the light sockets.",
    'Hey goes add a note to house to-dos. Call an electrician to fix the light sockets.',
    "Hey Ghost add a note to house to do's the note is call an electrician to fix the light sockets",
    'Hey Ghost, add call an electrician to fix the light sockets to house to-dos.',
    'Hey Ghost, add a note to the house list items: call an electrician to fix the light sockets.',
    'Um, hey Ghost, like, add a note to house chores. Call an electrician to fix the light sockets.',
  ])('does the same in one phrase: %s', (said) => {
    const { take, say, done } = record();
    say(said);
    done();
    expect(take.aim?.id).toBe('house');
    expect(take.result().made).toEqual([]);
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n');
  });

  it('keeps writing what is said next into the same list', () => {
    const { take, say, done } = record();
    say("Hey Ghost, add a note to house to do's.");
    say('The note is call an electrician to fix the light sockets.');
    say('Ask about the porch light too.');
    done();
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n- [ ] Ask about the porch light too\n');
  });
});

describe('where the words go in the note found', () => {
  it('goes under the heading it fits, and says so', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add call an electrician to home jobs.');
    done();
    expect(take.body('jobs')).toBe('# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call an electrician\n');
  });

  it('adds several short things said as a list as several items', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add milk, eggs and bread to groceries.');
    done();
    expect(take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Milk\n- Eggs\n- Bread\n');
  });

  it('takes the words after a name and “and” as more of the thing', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add milk to groceries and bread.');
    done();
    expect(take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Milk\n- Bread\n');
  });
});

describe('the start of a fresh take, and the middle of one', () => {
  it('writes a one-shot mid-take, and the take carries on where it was', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add call the electrician to House TODOs.');
    say('The budget review is Friday.');
    done();
    expect(take.aim).toBeNull();
    const { made } = take.result();
    expect(made).toEqual(['# Kevin owns the release\n\nThe budget review is Friday.']);
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call the electrician\n');
    expect(take.log).toContain('Added to House TODOs, in its to-do list');
  });

  it('ends a one-shot’s payload at a full stop inside the phrase', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add call Sam to House TODOs. Next, the budget review is Friday.');
    done();
    expect(take.result().made).toEqual(['# Kevin owns the release\n\nNext, the budget review is Friday.']);
    expect(take.body('house')).toContain('- [ ] Call Sam\n');
  });

  it('takes the phrases after a one-shot named with nothing, until a pause, then carries on', () => {
    const { take, say, wait, done } = record();
    say('Notes from the call.');
    say('Hey Ghost, add a note to house to-dos.');
    say('Call Sam.');
    wait(LIVE_TIMING.itemsQuietMs + 500);
    say('Back to the meeting.');
    done();
    expect(take.body('house')).toContain('- [ ] Call Sam\n');
    expect(take.result().made).toEqual(['# Notes from the call\n\nBack to the meeting.']);
  });

  it('stops a one-shot after three phrases', () => {
    const { take, say, done } = record();
    say('Notes.');
    say('Hey Ghost, add a note to house to-dos.');
    say('One.');
    say('Two.');
    say('Three.');
    say('Four is mine.');
    done();
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] One\n- [ ] Two\n- [ ] Three\n');
    expect(take.result().made[0]).toContain('Four is mine.');
  });

  it('on a note’s own Speak, sends the words to the note named and keeps the take on its note', () => {
    const daily = library().find((n) => n.id === 'daily')!;
    const { take, say, done } = record({ own: daily });
    say('Went for a run.');
    say('Hey Ghost, add call Sam to House TODOs.');
    say('Then I made lunch.');
    done();
    expect(take.aim?.id).toBe('daily');
    expect(take.body('daily')).toBe('# Daily Life\n\nWent for a walk.\n\nWent for a run. Then I made lunch.');
    expect(take.body('house')).toContain('- [ ] Call Sam\n');
  });

  it('moves the take, words so far and all, for “move this to …”', () => {
    const { take, say, done } = record();
    say('Our budget for the trip is four hundred.');
    say('Hey Ghost, move this to Daily Life.');
    say('The cabin has two bedrooms.');
    done();
    expect(take.aim?.id).toBe('daily');
    expect(take.result().made).toEqual([]);
    expect(take.body('daily')).toBe('# Daily Life\n\nWent for a walk.\n\nOur budget for the trip is four hundred. The cabin has two bedrooms.');
  });
});

describe('a name heard in pieces', () => {
  it('grows a name into the next phrase when that adds a word of the title', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add a note to house.');
    expect(take.aim?.id).toBe('house');
    say('To-dos. Call an electrician.');
    done();
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician\n');
  });

  it('does not grow it with words the title only shares a stem with', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add a note to house.');
    say('Household bills are due Friday.');
    done();
    expect(take.body('house')).toContain('- [ ] Household bills are due Friday\n');
  });

  it('joins the keyword’s lead to the phrase Whisper cut it from', () => {
    const { take, say, done } = record();
    say('Hey.');
    say('Ghost, add a note to house to-dos.');
    say('Call Sam.');
    done();
    expect(take.body('house')).toContain('- [ ] Call Sam\n');
    expect(take.result().made).toEqual([]);
  });

  it('holds a command for its name, and gives the words back when none comes', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add a note to');
    expect(take.live.holding).toBe(true);
    say('house to-dos.');
    say('Call Sam.');
    done();
    expect(take.body('house')).toContain('- [ ] Call Sam\n');

    const again = record();
    again.say('Hey Ghost, add eggs to');
    again.wait(LIVE_TIMING.holdMs + 500);
    expect(again.take.live.holding).toBe(false);
    again.done();
    expect(again.take.result().made).toEqual(['# Add eggs to']);
  });
});

describe('filler and silence before the command', () => {
  it('makes no note of “Okay.” said before the command', () => {
    const { take, say, done } = record();
    say('Okay.');
    say("Hey Ghost, add a note to house to do's. Call Sam.");
    done();
    expect(take.result().made).toEqual([]);
    expect(take.body('house')).toContain('- [ ] Call Sam\n');
  });

  it('gives filler back as words when no command follows it', () => {
    const { take, say, done } = record();
    say('Thank you.');
    say('Buy milk.');
    done();
    expect(take.result().made).toEqual(['# Thank you\n\nBuy milk.']);
  });
});

describe('names that are not sure', () => {
  it('raises a card between titles as close as each other, takes the phrases after it as words, and a tap moves them', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add a note to signing.');
    say('Check the order form.', 1000);
    expect(take.card).toMatchObject({ form: 'unsure', heading: 'Add to which note?' });
    expect(take.card?.candidates.map((c) => c.title).sort()).toEqual(['Signing in, and signing', 'Signing the order']);
    // A card holds the recording open, but what is said meanwhile goes to the page.
    expect(take.live.holding).toBe(true);
    expect(take.live.hearingCommand).toBe(false);
    take.answer({ kind: 'note', id: 's2' });
    done();
    expect(take.aim?.id).toBe('s2');
    expect(take.body('s2')).toBe('# Signing the order\n\nCheck the order form.');
  });

  it('takes Keep here after eight seconds, and at once when the recording ends', () => {
    const one = record();
    one.say('Hey Ghost, add call Sam to signing.');
    one.wait(LIVE_TIMING.cardMs + 500);
    expect(one.take.card).toBeNull();
    one.done();
    expect(one.take.result().made).toEqual(['# Call Sam']);

    const two = record();
    two.say('Hey Ghost, add call Sam to signing.');
    two.done();
    expect(two.take.card).toBeNull();
    expect(two.take.result().made).toEqual(['# Call Sam']);
  });

  it('takes a spoken answer from the card’s own titles', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add call Sam to signing.');
    say('The second one.');
    done();
    expect(take.card).toBeNull();
    expect(take.aim?.id).toBe(take.body('s2')?.includes('Call Sam') ? 's2' : 's1');
  });

  it('keeps a missing name’s words here, and offers a card when a note noun was said', () => {
    const one = record();
    one.say('Hey Ghost, add eggs to the moon base.');
    one.done();
    expect(one.take.result().made).toEqual(['# Eggs']);
    expect(one.take.chips).toContainEqual({ phase: 'said', text: 'No note called “moon base”, so the words stay here.' });

    const two = record();
    two.say('Hey Ghost, add a note to the moon base.');
    expect(two.take.card).toMatchObject({ form: 'missing', newTitle: 'Moon base' });
    two.take.answer({ kind: 'new' });
    two.say('Call Sam.');
    two.done();
    expect(two.take.result().made).toEqual(['Moon base\n\nCall Sam.']);
  });
});

describe('what is never switched to', () => {
  it('leaves a book’s name alone, and keeps the words here', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add Rivers to the field guide.');
    done();
    expect(take.chips).toContainEqual({ phase: 'said', text: '“Field guide” is a book, so the words stay here.' });
    expect(take.result().made).toEqual(['# Rivers']);
  });

  it('keeps the words here over the lock screen for a shared note, and never raises a card there', () => {
    const shared = record({ locked: true, published: (id) => id === 'house' });
    shared.say('Hey Ghost, add call Sam to house to-dos.');
    shared.done();
    expect(shared.take.chips).toContainEqual({ phase: 'said', text: 'That note is shared, so the words stay here.' });
    const unsure = record({ locked: true });
    unsure.say('Hey Ghost, add call Sam to signing.');
    expect(unsure.take.card).toBeNull();
  });

  it('only changes how the words go when the note named is the one being written to', () => {
    const house = library().find((n) => n.id === 'house')!;
    const { take, say, done } = record({ own: house });
    say('Hey Ghost, add call Sam to house to-dos.');
    done();
    expect(take.inserts.size).toBe(0);
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
  });

  it('is a name only when a note is plainly called that; otherwise a thing to do', () => {
    const { take, say, done } = record();
    say('Hey Ghost, make a note to call the electrician.');
    done();
    expect(take.result().made).toEqual(['- [ ] Call the electrician']);
    const log = record();
    log.say('Hey Ghost, add a note to call log. Sam rang twice.');
    log.done();
    expect(log.take.body('call')).toContain('Sam rang twice.');
  });
});

describe('the keyword', () => {
  it('reads nothing said without it while the setting is on', () => {
    const { take, say, done } = record();
    say('Add a note to house to-dos, call Sam.');
    done();
    expect(take.live.engaged).toBe(false);
    expect(take.result().made).toEqual(['Add a note to house to-dos, call Sam.']);
    expect(take.body('house')).toBe(HOUSE);
  });

  it('with the setting off, routes the plainest shapes at the very start only', () => {
    const one = record({ keywordOn: false });
    one.say('Add a note to house to-dos, call Sam.');
    one.say('Also the gutter bolts.');
    one.done();
    expect(one.take.body('house')).toContain('- [ ] Call Sam\n- [ ] The gutter bolts\n');

    const words = record({ keywordOn: false });
    words.say('Put the parcel in the post.');
    words.say('Add a note to house to-dos, call Sam.');
    words.done();
    expect(words.take.live.engaged).toBe(false);
  });
});

describe('a keyworded phrase that is no route', () => {
  it('is left to the reader at Done when it is the take’s start', () => {
    const { take, say, done } = record();
    say('Hey Ghost, fix the spelling.');
    done();
    expect(take.live.engaged).toBe(false);
    expect(take.segments.map((s) => s.text)).toEqual(['Hey Ghost, fix the spelling.']);
  });

  it('is queued for after Done mid-take, and left out of a routed take', () => {
    const one = record();
    one.say('Buy milk.');
    one.say('Hey Ghost, fix the spelling.');
    one.done();
    expect(one.take.asks).toEqual([{ run: 'fix', instruction: 'fix the spelling' }]);
    expect(one.take.result().made).toEqual(['# Buy milk']);

    const two = record();
    two.say("Hey Ghost, add a note to house to do's. Call Sam.");
    two.say('Hey Ghost, fix the spelling.');
    two.done();
    expect(two.take.asks).toEqual([]);
    expect(two.take.chips).toContainEqual({ phase: 'said', text: "That can't run in the middle of a recording, so it was left out." });
  });
});

describe('Not this note, a to-do for here, and a new note', () => {
  it('goes home on Not this note, with the words said since, and offers the other notes', () => {
    const { take, say, done, now } = record();
    say("Hey Ghost, add a note to house to do's. Call Sam.");
    take.decline(now());
    expect(take.aim).toBeNull();
    expect(take.card).toMatchObject({ form: 'declined', heading: 'Not added to House TODOs' });
    say('And the gutter.');
    expect(take.card).toBeNull();
    done();
    expect(take.body('house')).toBe(HOUSE);
    expect(take.result().made).toEqual(['# Call Sam\n\nAnd the gutter.']);
  });

  it('writes a to-do for the note being written to', () => {
    const { take, say, done } = record();
    say('Buy milk.');
    say('Hey Ghost, remind me to book the MOT.');
    done();
    expect(take.result().made).toEqual(['# Buy milk\n\n- [ ] Book the MOT']);
  });

  it('starts a new note mid-take, the words so far staying where they were said', () => {
    const daily = library().find((n) => n.id === 'daily')!;
    const { take, say, done } = record({ own: daily });
    say('Went for a run.');
    say('Hey Ghost, new note.');
    say('Tax receipts go in the blue folder.');
    done();
    expect(take.body('daily')).toBe('# Daily Life\n\nWent for a walk.\n\nWent for a run.');
    expect(take.result().made).toEqual(['Tax receipts go in the blue folder.']);
  });

  it('says a fresh take is a new note already', () => {
    const { take, say } = record();
    say('Hey Ghost, new note.');
    expect(lastChip(take)).toEqual({ phase: 'said', text: 'This is a new note already.' });
  });
});
