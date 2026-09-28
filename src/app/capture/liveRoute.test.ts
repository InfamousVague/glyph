import { describe, expect, it } from 'vitest';
import { bookNoteBody } from '../book/book.ts';
import { LiveTake, type LiveTakeOptions, type MemoryNote } from './liveTake.ts';
import { LIVE_TIMING } from './liveRoute.ts';
import { withoutCommands } from './refineText.ts';
import type { RouteView } from './takeHost.ts';

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
    expect(lastChip(take)).toEqual({ phase: 'waiting', title: 'House TODOs' });
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

  // "Under the sofa" is where the cleaning is, not a heading House TODOs has: the thing keeps it. Kitchen is one.
  it('keeps “under …” in the thing when the note has no such heading, and goes under the heading when it has', () => {
    const sofa = record();
    sofa.say('First words.');
    sofa.say('Hey Ghost, add clean under the sofa in house to-dos.');
    sofa.done();
    expect(sofa.take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Clean under the sofa\n');

    const tap = record();
    tap.say('First words.');
    tap.say('Hey Ghost, add fix the tap under Kitchen in home jobs.');
    tap.done();
    expect(tap.take.body('jobs')).toBe('# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n- [ ] Fix the tap\n\n## Electrical\n- [ ] Rewire porch light\n');
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

  it('does not grow it with words that add nothing of the title', () => {
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
    const [first, second] = take.card!.candidates.map((c) => c.id);
    say('The second one.');
    done();
    expect(take.card).toBeNull();
    expect(take.aim?.id).toBe(second);
    expect(take.body(second!)).toContain('Call Sam');
    expect(take.body(first!)).toBe(library().find((n) => n.id === first)!.body);
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
    expect(take.chips).toContainEqual({ phase: 'said', text: '“Field guide” is a notebook, so the words stay here.' });
    expect(take.result().made).toEqual(['# Rivers']);
  });

  it('keeps the words here when a journal is named, and says it is one: an entry is made by a tap', () => {
    const { take, say, done } = record({ notes: [...library(), { id: 'diary', body: '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n' }] });
    say('Hey Ghost, add Walked by the river to the diary.');
    done();
    expect(take.chips).toContainEqual({ phase: 'said', text: '“Diary” is a journal, so the words stay here.' });
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

/**
 * A command needs no keyword (docs/DESIGN.md §136): a phrase said without it is a command only through the bare gate
 * (liveCommand.ts `bareCommand`), and anything short of that is words, untouched. Each sentence here was a mis-fire the
 * review of the design found, or a command Matt would say, and each is the rule that answers it.
 */
describe('without the keyword', () => {
  const more = (): MemoryNote[] => [
    ...library(),
    { id: 'trip', body: '# Weekend trip\n\nCabin.\n' },
    { id: 'work', body: '# Work\n\nNotes.\n' },
    { id: 'garage', body: '# Garage\n' },
    { id: 'agenda', body: '# Agenda\n\n- Budget\n' },
    { id: 'team', body: '# Team\n' },
    { id: 'roadmap', body: '# Roadmap\n' },
    { id: 'sam', body: '# Sam\n\n- Owes me a tenner\n' },
    { id: 'porch', body: '# Porch light\n\nFlickers.\n' },
    { id: 'moon', body: '# Moon landing\n' },
  ];
  const untouched = (take: LiveTake, ids: string[]) => {
    for (const id of ids) expect(take.body(id), id).toBe(more().find((n) => n.id === id)!.body);
  };

  it('routes a note said plainly at the start, and writes what is said next into it', () => {
    const { take, say, done } = record({ notes: more() });
    say('Add a note to house to-dos, call Sam.');
    say('Also the gutter bolts.');
    done();
    expect(take.body('house')).toContain('- [ ] Call Sam\n- [ ] The gutter bolts\n');
    expect(take.result().made).toEqual([]);
  });

  it('is a one-shot mid-take, the take carrying on where it was', () => {
    const { take, say, done } = record({ notes: more() });
    say('Put the parcel in the post.');
    say('Add a note to house to-dos, call Sam.');
    say('Then the budget.');
    done();
    expect(take.live.engaged).toBe(true);
    expect(take.body('house')).toContain('- [ ] Call Sam\n');
    expect(take.result().made).toEqual(['# Put the parcel in the post\n\nThen the budget.']);
  });

  it('leaves a sentence that runs on past the name, or names nothing, or is only an opener, as words: no card, no hold', () => {
    const { take, say, done } = record({ notes: more() });
    say('Add oat milk to groceries before the weekend.');
    say('Add a note to the moon base, pack the tent.');
    say('Add a note to.');
    say('Call Sam.');
    done();
    expect(take.live.engaged).toBe(false);
    expect(take.card).toBeNull();
    expect(take.live.holding).toBe(false);
    expect(take.chips).toEqual([]);
    untouched(take, ['groceries', 'moon']);
    expect(take.result().made).toEqual(['Add oat milk to groceries before the weekend. Add a note to the moon base, pack the tent. Add a note to. Call Sam.']);
  });

  it('starts a new note on “New note” alone, and not on “Another note”', () => {
    const one = record({ notes: more() });
    one.say('Kevin owns the release.');
    one.say('New note.');
    one.say('The budget is fine.');
    one.done();
    expect(one.take.parts).toHaveLength(1);
    expect(one.take.result().made).toEqual(['# Kevin owns the release', '# The budget is fine']);

    const two = record({ notes: more() });
    two.say('Kevin owns the release.');
    two.say('Another note.');
    two.say('The budget is fine.');
    two.done();
    expect(two.take.live.engaged).toBe(false);
    expect(two.take.result().made).toEqual(['# Kevin owns the release\n\nAnother note. The budget is fine.']);
  });

  it('starts the take at a bare command said after filler, with no note of the filler', () => {
    for (const filler of ['Okay.', 'Um.']) {
      const { take, say, done } = record({ notes: more() });
      say(filler);
      say('Add a note to house to-dos, call Sam.');
      done();
      expect(take.body('house'), filler).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
      expect(take.result().made, filler).toEqual([]);
    }
    // "New note" said first is already one: the filler before it is no note's title.
    const fresh = record({ notes: more() });
    fresh.say('Okay.');
    fresh.say('New note.');
    fresh.say('Hello there.');
    fresh.done();
    expect(fresh.take.result().made).toEqual(['# Hello there']);
    // Filler before words is words, as before: "Okay." is the take's own when no command came of it.
    const words = record({ notes: more() });
    words.say('Okay.');
    words.say('The budget is fine.');
    words.done();
    expect(words.take.result().made).toEqual(['# Okay\n\nThe budget is fine.']);
  });

  it('mid-take, needs the words in the same breath; at the start, a route may wait for them', () => {
    const swallow = record({ notes: more() });
    swallow.say('Kevin owns the release.');
    swallow.say('Add a note to weekend trip.');
    swallow.say('The cabin has two bedrooms.');
    swallow.done();
    expect(swallow.take.live.engaged).toBe(false);
    untouched(swallow.take, ['trip']);
    expect(swallow.take.result().made).toEqual(['# Kevin owns the release\n\nAdd a note to weekend trip. The cabin has two bedrooms.']);

    const breath = record({ notes: more() });
    breath.say('Kevin owns the release.');
    breath.say('Add a note to weekend trip, book the ferry.');
    breath.done();
    expect(breath.take.body('trip')).toBe('# Weekend trip\n\nCabin.\n\nBook the ferry.');
    expect(breath.take.result().made).toEqual(['# Kevin owns the release']);

    const first = record({ notes: more() });
    first.say('Add a note to weekend trip.');
    expect(first.take.live.awaitingPayload).toBe(true);
    expect(lastChip(first.take)).toEqual({ phase: 'waiting', title: 'Weekend trip' });
    first.say('Book the ferry.');
    first.done();
    expect(first.take.body('trip')).toBe('# Weekend trip\n\nCabin.\n\nBook the ferry.');

    // A note's own Speak is never a fresh recording: its first phrase is in the middle of that note.
    const garage = more().find((n) => n.id === 'garage')!;
    const own = record({ notes: more(), own: garage });
    own.say('Add a note to weekend trip.');
    own.say('Book the ferry.');
    own.done();
    expect(own.take.live.engaged).toBe(false);
    untouched(own.take, ['trip']);
    expect(own.take.body('garage')).toContain('Add a note to weekend trip. Book the ferry.');
  });

  it('moves the take only for “move this” or “switch this”, never for “go to”, “continue in” or “move it to”', () => {
    const go = record({ notes: more() });
    go.say('Buy milk.');
    go.say('Go to work.');
    go.say('Ring the plumber.');
    go.done();
    expect(go.take.live.engaged).toBe(false);
    untouched(go.take, ['work']);
    expect(go.take.result().made).toEqual(['# Buy milk\n\nGo to work. Ring the plumber.']);

    for (const said of ['Continue in the garage.', 'Move it to the garage.']) {
      const words = record({ notes: more() });
      words.say('Buy milk.');
      words.say(said);
      words.done();
      expect(words.take.live.engaged, said).toBe(false);
      expect(words.take.aim, said).toBeNull();
    }

    const move = record({ notes: more() });
    move.say('Buy milk.');
    move.say('Move this to the garage.');
    move.done();
    expect(move.take.aim?.id).toBe('garage');
    expect(move.take.body('garage')).toContain('Buy milk.');

    // "Move everything to the garage" is about boxes; "move this to Tuesday" moves a meeting, even beside a Tuesday note.
    const days = [...more(), { id: 'tuesday', body: '# Tuesday\n' }];
    for (const said of ['Move everything to the garage.', 'Move these to the garage.', 'Move this to Tuesday.']) {
      const words = record({ notes: days });
      words.say('We talked about the weekend.');
      words.say(said);
      words.say('The rest of the note.');
      words.done();
      expect(words.take.live.engaged, said).toBe(false);
      expect(words.take.aim, said).toBeNull();
    }
  });

  it('never takes a name from a split the grammar chose: meeting talk stays words', () => {
    const { take, say, done } = record({ notes: more() });
    say('Another item on the agenda is the budget.');
    say('A new task for the team is to ship it.');
    say('Another point on the roadmap is billing.');
    done();
    expect(take.live.engaged).toBe(false);
    untouched(take, ['agenda', 'team', 'roadmap']);

    const item = record({ notes: more() });
    item.say('New item for groceries, eggs.');
    item.done();
    expect(item.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Eggs\n');
  });

  it('needs the name or the title to say it is a list for “put this in”: a bullet in the body is no evidence', () => {
    const sam = record({ notes: more() });
    sam.say('Send this to Sam, the deposit is due.');
    sam.done();
    expect(sam.take.live.engaged).toBe(false);
    untouched(sam.take, ['sam']);

    const list = record({ notes: more() });
    list.say('Put this in the house list, call Sam.');
    list.done();
    expect(list.take.body('house')).toContain('- [ ] Call Sam\n');

    // Nor is a title that says it is a list, when the name does not: "the house" is a place, not House TODOs.
    const place = record({ notes: more() });
    place.say('Put the washing in the house.');
    place.say('The rest of the note.');
    place.done();
    expect(place.take.live.engaged).toBe(false);
    untouched(place.take, ['house']);
    const todos = record({ notes: more() });
    todos.say('Kevin owns the release.');
    todos.say('Add call the plumber to House TODOs and book the MOT.');
    todos.done();
    expect(todos.take.body('house')).toContain('- [ ] Call the plumber\n');
  });

  it('takes a heading only when the note has it', () => {
    const porch = record({ notes: more() });
    porch.say('Put the spare key under the mat on the porch.');
    porch.done();
    expect(porch.take.live.engaged).toBe(false);
    untouched(porch.take, ['porch']);

    const jobs = record({ notes: more() });
    jobs.say('Add fix the tap under Kitchen in home jobs.');
    jobs.done();
    expect(jobs.take.body('jobs')).toBe('# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n- [ ] Fix the tap\n\n## Electrical\n- [ ] Rewire porch light\n');
  });

  it('reads “actually, add …” as the command after words in the same phrase', () => {
    const { take, say, done } = record({ notes: more() });
    say('Buy milk. Actually, add call the plumber to House TODOs.');
    done();
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call the plumber\n');
    expect(take.result().made).toEqual(['# Buy milk']);
  });

  it('reads the name-first shapes after the keyword, never without it', () => {
    for (const said of ['Hey Ghost, for groceries, eggs.', 'Hey Ghost, groceries: eggs.']) {
      const { take, say, done } = record({ notes: more() });
      say('Kevin owns the release.');
      say(said);
      done();
      expect(take.body('groceries'), said).toBe('# Groceries\n\n- Eggs\n- Eggs\n');
    }
    const bare = record({ notes: more() });
    bare.say('Kevin owns the release.');
    bare.say('Groceries: eggs.');
    bare.done();
    expect(bare.take.live.engaged).toBe(false);
    untouched(bare.take, ['groceries']);
  });

  it('never writes into a book, or a shared note over the lock screen, and says nothing of it', () => {
    const book = record({ notes: more() });
    book.say('Kevin owns the release.');
    book.say('Add a note to Field guide, call Sam.');
    book.done();
    expect(book.take.live.engaged).toBe(false);
    expect(book.take.chips).toEqual([]);
    expect(book.take.result().made).toEqual(['# Kevin owns the release\n\nAdd a note to Field guide, call Sam.']);

    const shared = record({ notes: more(), locked: true, published: (id) => id === 'house' });
    shared.say('Kevin owns the release.');
    shared.say('Add a note to house to-dos, call Sam.');
    shared.done();
    expect(shared.take.live.engaged).toBe(false);
    expect(shared.take.chips).toEqual([]);
    expect(shared.take.body('house')).toBe(HOUSE);
  });

  it('reads “actually, add …” as the command, and never as a correction of what came before', () => {
    const one = record({ notes: more() });
    one.say('Kevin owns the release.');
    one.say('Actually, add call the plumber to House TODOs.');
    one.done();
    expect(one.take.body('house')).toContain('- [ ] Call the plumber\n');
    expect(one.take.result().made).toEqual(['# Kevin owns the release']);

    const talk = record({ notes: more() });
    talk.say('Kevin owns the release.');
    talk.say('Actually I think we should go.');
    talk.done();
    expect(talk.take.live.engaged).toBe(false);
    expect(talk.take.result().made).toEqual(['# Kevin owns the release\n\nActually I think we should go.']);

    // The sentence before shares its words with the command, which `corrects` would take for the sentence said again.
    const shared = record({ notes: more() });
    shared.say('Call the plumber about the house.');
    shared.say('Actually, add call the plumber to House TODOs.');
    shared.done();
    expect(shared.take.body('house')).toContain('- [ ] Call the plumber\n');
    expect(shared.take.result().made).toEqual(['# Call the plumber about the house']);
  });

  it('never names a lane or a heading of the note being written to without the keyword', () => {
    const board = { id: 'board', body: '# Launch\n\n```board\nTo do: write-copy\nDoing: pricing-page\n```\n\n- [ ] Write the copy ^write-copy\n- [ ] Pricing page ^pricing-page\n' };
    const bare = record({ notes: [...more(), board], own: board });
    bare.say('Put this in doing, it is underway.');
    bare.done();
    expect(bare.take.live.engaged).toBe(false);
    expect(bare.take.body('board')).toContain('Put this in doing, it is underway.');
    expect(bare.take.body('board')).toContain('Doing: pricing-page\n');

    const keyed = record({ notes: [...more(), board], own: board });
    keyed.say('Hey Ghost, put this in doing, it is underway.');
    keyed.done();
    expect(keyed.take.body('board')).toMatch(/Doing: \S+, pricing-page\n/);
    expect(keyed.take.body('board')).toContain('- [ ] It is underway');
  });

  it.each([
    ['Add the flour to the bowl.', 'the flour to the bowl'],
    ['Put the kettle on.', 'the kettle on'],
    ['Move the meeting to Tuesday.', 'the meeting to Tuesday'],
    ['Move this to Tuesday.', 'this to Tuesday'],
    ['Make a list of things to pack.', 'things to pack'],
    ['Send the deposit to Sam.', 'the deposit to Sam'],
    ['Scratch that itch.', 'that itch'],
    ['Add call the plumber to work.', 'the plumber to work'],
    ['Add a note to house to-dos call Sam.', 'house to-dos call Sam'],
    ['Remind me to book the MOT.', 'ook the MOT'],
    ['For groceries, eggs.', 'groceries, eggs'],
    // A move of boxes, not of the recording.
    ['Move everything to the garage.', 'everything to the garage'],
    ['Move these to the garage.', 'these to the garage'],
    ['Continue this in Work.', 'this in Work'],
    // A place, which a list-titled note begins with: "house" is House TODOs and "garden" is Garden jobs, at 0.9.
    ['Put the washing in the house.', 'the washing in the house'],
    ['Put the new plants in the garden.', 'plants in the garden'],
    ['Put this in the garden, next to the shed.', 'next to the shed'],
    ['Put the bags in the house and lock the car.', 'lock the car'],
    // A message or a point for someone, not a note filed.
    ['Leave a note for Mum, dinner is in the oven.', 'dinner is in the oven'],
    ['Send a note to Sam, the deposit is due Friday.', 'the deposit is due Friday'],
    ['Drop a line to the team, the office is shut on Monday.', 'the office is shut on Monday'],
    ['Jot down a note for the kids, pizza is in the freezer.', 'pizza is in the freezer'],
    ['Write a note to Sam, thanks for the flowers.', 'thanks for the flowers'],
    ['Another point for the agenda, we need to hire.', 'we need to hire'],
    ['Another thing for the kitchen, we need new tiles.', 'we need new tiles'],
    ['Add a comment to the work, it needs another pass.', 'it needs another pass'],
  ])('stays words without the keyword, at the start and mid-take: %s', (said, kept) => {
    const notes = [
      ...more(),
      { id: 'bowl', body: '# Bowl\n' },
      { id: 'tuesday', body: '# Tuesday\n' },
      { id: 'kitchen', body: '# Kitchen\n\n- Tiles\n' },
      { id: 'garden', body: '# Garden jobs\n\n- Weed\n' },
      { id: 'mum', body: '# Mum\n\nBirthday in May.\n' },
      { id: 'kids', body: '# Kids\n\n- School run\n' },
    ];
    for (const before of [[], ['Kevin owns the release.']]) {
      const { take, say, done } = record({ notes });
      for (const line of before) say(line);
      say(said);
      done();
      expect(take.live.engaged, `${before.join(' ')} | ${said}`).toBe(false);
      expect(take.aim).toBeNull();
      expect(take.card).toBeNull();
      expect(take.chips).toEqual([]);
      for (const note of notes) expect(take.body(note.id), note.id).toBe(note.body);
      expect(take.result().made).toHaveLength(1);
      expect(take.result().made[0]).toContain(kept);
    }
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

describe('what a card holds', () => {
  const hello = (): MemoryNote[] => [
    ...library(),
    { id: 'b1', body: bookNoteBody('HelloTrade: The Book', ['Intro']) },
    { id: 'b2', body: bookNoteBody('HelloTrade — The Book', ['From tap to fill']) },
    { id: 'p', body: '# HelloTrade Frontend\n' },
  ];

  it('never offers a book, and a book chosen anyway keeps the words here', () => {
    const { take, say, done } = record({ notes: hello() });
    say('Hey Ghost, add a note to hello trade, chapter two needs work.');
    expect(take.card?.candidates.map((c) => c.id)).toEqual(['p']);
    take.answer({ kind: 'note', id: 'b1' });
    done();
    expect(take.body('b1')).toBe(bookNoteBody('HelloTrade: The Book', ['Intro']));
    expect(take.chips).toContainEqual({ phase: 'said', text: '“HelloTrade: The Book” is a notebook, so the words stay here.' });
    expect(take.result().made).toEqual(['# Chapter two needs work']);
  });

  it('keeps the words here when every title it could offer is a book', () => {
    const { take, say, done } = record({ notes: hello() });
    say('Hey Ghost, add a note to hello trade the book, check the glossary.');
    expect(take.card).toBeNull();
    done();
    expect(take.result().made).toEqual(['# Check the glossary']);
  });

  it('puts its words in the order they were said, after a tap or its own default', () => {
    const tapped = record();
    tapped.say('Hey Ghost, add a note to signing.');
    tapped.say('Check the form.');
    tapped.say('And the date.');
    tapped.take.answer({ kind: 'note', id: 's2' });
    tapped.done();
    expect(tapped.take.body('s2')).toBe('# Signing the order\n\nCheck the form. And the date.');

    const kept = record();
    kept.say('Kevin owns the release.');
    kept.say('Hey Ghost, add call Jo to signing.');
    kept.say('The budget review is Friday.');
    kept.done();
    expect(kept.take.result().made).toEqual(['# Kevin owns the release\n\nCall Jo. The budget review is Friday.']);
  });

  it('keeps every word of a long name that matched nothing on Keep here', () => {
    const one = record();
    one.say('Hey Ghost, add a note to moon base pack sunscreen and the tent.');
    expect(one.take.card).toMatchObject({ form: 'missing' });
    one.done();
    expect(one.take.result().made).toEqual(['Moon base pack sunscreen and the tent.']);

    const two = record();
    two.say('Hey Ghost, add a paragraph to Groceries that says we are out of bread.');
    two.done();
    expect(two.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n\nWe are out of bread.');
  });

  it('takes its default when another card comes up, so neither loses its words', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add call Jo to signing.');
    say('Hey Ghost, add a note to the moon base, pack the tent.');
    expect(take.card).toMatchObject({ form: 'missing' });
    done();
    expect(take.result().made).toEqual(['# Kevin owns the release\n\nCall Jo. Pack the tent.']);
  });
});

describe('a mishearing of the keyword', () => {
  const talk = (): MemoryNote[] => [...library(), { id: 'post', body: "# It's post\n" }, { id: 'questions', body: '# Questions\n' }, { id: 'fold', body: '# Galaxy Fold\n' }];

  it.each([
    'Hey, like, put the parcel in the post.',
    'Okay, like, add some salt to the questions.',
    'Hey, like, I need to call my mum.',
    'Okay, like, I have to get this finished by Friday.',
    'Hey, go add some colour to the living room walls, it would look nice.',
  ])('is how people talk, not a command: %s', (said) => {
    const { take, say, done } = record({ notes: talk() });
    say(said);
    say('Then I went home.');
    done();
    expect(take.live.engaged).toBe(false);
    expect(take.aim).toBeNull();
    expect(take.result().made).toHaveLength(1);
    expect(take.result().made[0]).toContain('Then I went home.');
  });

  it('is words on a note’s own Speak, never a to-do made of them', () => {
    const daily = library().find((n) => n.id === 'daily')!;
    const { take, say, done } = record({ own: daily });
    say('Okay, like, I have to say it was a great run.');
    done();
    expect(take.body('daily')).toBe('# Daily Life\n\nWent for a walk.\n\nOkay, like, I have to say it was a great run.');
  });

  it('is the keyword before a command for a note named clearly', () => {
    const { take, say, done } = record();
    say('Hey, like, add call an electrician to house to-dos.');
    done();
    expect(take.body('house')).toContain('- [ ] Call an electrician\n');
  });

  // Changed on purpose (docs/DESIGN.md §136): "move this to X" is a command with no keyword at all, so the lead-in
  // before it no longer matters, and a mishearing mid-take with nothing said for the note is words, as a bare one is.
  it('moves the take for “move this to” after any lead-in, and mid-take is words with nothing said for the note', () => {
    const move = record({ notes: talk() });
    move.say('OK like move this to the Galaxy Fold.');
    move.say('Then I went home.');
    move.done();
    expect(move.take.aim?.id).toBe('fold');
    expect(move.take.body('fold')).toContain('Then I went home.');

    const words = record({ notes: [...talk(), { id: 'trip', body: '# Weekend trip\n\nCabin.\n' }] });
    words.say('Kevin owns the release.');
    words.say('Hey, like, add a note to weekend trip.');
    words.say('The cabin has two bedrooms.');
    words.done();
    expect(words.take.live.engaged).toBe(false);
    expect(words.take.body('trip')).toBe('# Weekend trip\n\nCabin.\n');

    // "New note" needs no keyword either, so a mishearing before it is a lead-in: at the start, a new note already.
    const fresh = record({ notes: talk() });
    fresh.say('Hey, like, new note.');
    fresh.say('Then I went home.');
    fresh.done();
    expect(fresh.take.live.engaged).toBe(false);
    expect(fresh.take.chips).toContainEqual({ phase: 'said', text: 'This is a new note already.' });
    expect(fresh.take.result().made).toEqual(['# Then I went home']);
  });
});

describe('one command after another', () => {
  it('carries out a second command said while the first waits for its name', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add to signing.');
    say('Hey Ghost, add milk to groceries.');
    done();
    expect(take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Milk\n');
    expect(take.result().made).toEqual(['# Kevin owns the release']);
  });

  it('sends what is said next to the note the second command named', () => {
    const { take, say, done } = record();
    say("Hey Ghost, add a note to house to do's.");
    say('Hey Ghost, add a note to daily life.');
    say('Went for a run.');
    done();
    expect(take.body('house')).toBe(HOUSE);
    expect(take.body('daily')).toBe('# Daily Life\n\nWent for a walk.\n\nWent for a run.');
  });

  it('takes a keyworded ask the take opened with out of its words once the reader has done something', () => {
    const one = record();
    one.say('Hey Ghost, fix the spelling.');
    one.say('Buy milk.');
    one.say('Hey Ghost, add call Sam to House TODOs.');
    one.done();
    expect(one.take.asks).toEqual([{ run: 'fix', instruction: 'fix the spelling' }]);
    expect(one.take.result().made).toEqual(['# Buy milk']);
    expect(one.take.body('house')).toContain('- [ ] Call Sam\n');

    const two = record();
    two.say('Hey Ghost, make a list called packing.');
    two.say('Tent.');
    two.say('Hey Ghost, remind me to book the MOT.');
    two.done();
    expect(two.take.asks).toEqual([{ run: null, instruction: 'make a list called packing' }]);
    expect(two.take.result().made).toEqual(['# Tent\n\n- [ ] Book the MOT']);
  });
});

describe('the guards', () => {
  it('without the keyword, routes only a name that is clear, and a kind said or in the title but for “a note”', () => {
    const notes = [...library(), { id: 'hg', body: '# House and garden jobs\n\n- [ ] Mow\n' }, { id: 'trip', body: '# Weekend trip\n\nCabin.\n' }, { id: 'car', body: '# Car insurance\n' }];
    const still = (said: string) => {
      const { take, say, done } = record({ notes });
      say(said);
      done();
      expect(take.live.engaged, said).toBe(false);
      for (const note of notes) expect(take.body(note.id), `${said}: ${note.id}`).toBe(note.body);
    };
    // "garden" is the start of the title, not the whole of it; so are "the weekend" and "the car" (0.85, not clear).
    still('Add a note to garden, trim the hedge.');
    still('Add a note to the weekend, book the ferry.');
    still('Put this in the car, then drive.');
    // Weekend trip's title does not say it is a list, so "put this in" and "add X to" want the keyword; "a note" is its own evidence.
    still('Put this in the weekend trip, book the ferry.');
    still('Add book the ferry to the weekend trip.');
    const note = record({ notes });
    note.say('Add a note to weekend trip, book the ferry.');
    note.done();
    expect(note.take.body('trip')).toBe('# Weekend trip\n\nCabin.\n\nBook the ferry.');
  });

  it('never sends a name declined in this take to that note again', () => {
    const { take, say, done, now } = record();
    say("Hey Ghost, add a note to house to do's. Call Sam.");
    take.decline(now());
    say('Carry on.');
    say("Hey Ghost, add a note to house to do's. Buy fuses.");
    done();
    expect(take.body('house')).toBe(HOUSE);
  });

  it('waits one phrase for an unsure name at the end of a phrase before its card, and grows it', () => {
    const { take, say, done } = record();
    say('Hey Ghost, add a note to signing');
    expect(take.card).toBeNull();
    say('the order. Check the form.');
    done();
    expect(take.chips).toContainEqual({ phase: 'hearing', name: 'signing' });
    expect(take.aim?.id).toBe('s2');
    expect(take.body('s2')).toBe('# Signing the order\n\nCheck the form.');
  });

  it('grows a name only within its window on the recording', () => {
    const soon = record();
    soon.say('Hey Ghost, add a note to house.', 1000);
    soon.say('To-dos. Call an electrician.');
    soon.done();
    expect(soon.take.body('house')).toContain('- [ ] Call an electrician\n');

    const late = record();
    late.say('Hey Ghost, add a note to house.', 4000);
    late.say('To-dos. Call an electrician.');
    late.done();
    expect(late.take.body('house')).toContain('- [ ] To-dos\n');
  });

  it('holds a command for its name for three phrases at most', () => {
    const { take, say } = record();
    say('Hey Ghost.');
    say('Add a note to.');
    expect(take.live.holding).toBe(true);
    expect(take.card).toBeNull();
    say('The.');
    expect(take.live.holding).toBe(false);
    expect(take.segments.map((segment) => segment.text)).toEqual(['Add a note to.', 'The.']);
    expect(lastChip(take)).toEqual({ phase: 'said', text: 'No note was named, so the words stay here.' });
  });

  it('leaves out how a one-shot’s words were introduced', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add a note to House TODOs.');
    say('The note is call Sam.');
    done();
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
  });

  it('marks what a one-shot took, so the better words leave it out of the take', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add to House TODOs.');
    say('Call the electrician.');
    say('Buy fuses.');
    done();
    expect(take.commandSpans).toEqual([
      { startMs: 1000, endMs: 1900 },
      { startMs: 2000, endMs: 2900 },
      { startMs: 3000, endMs: 3900 },
    ]);
  });

  it('marks the phrase a payload was read from, as well as the command', () => {
    const { take, say, done } = record();
    say("Hey Ghost, add a note to house to do's.");
    say('The note is call Sam.');
    done();
    expect(take.commandSpans).toEqual([
      { startMs: 0, endMs: 900 },
      { startMs: 1000, endMs: 1900 },
    ]);
  });

  it('refuses a one-shot’s Not this note once the recording has ended', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add call Sam to House TODOs.');
    done();
    const [id] = [...take.inserts.keys()];
    expect(take.live.dropInsert(id!)).toEqual([]);
  });
});

/**
 * Matt: "Id like sentences to be able to redact", which is what happens "when the user says something like 'actually
 * …' or 'scratch that, add it to the <note> instead'" (docs/DESIGN.md §130). The last thing said goes back into smoke,
 * is replaced, has one word changed, or goes to a note named; the chip says what went, with Undo for a moment.
 */
describe('taking back what was just said', () => {
  const words = (take: LiveTake) => take.segments.map((segment) => segment.text);
  const tookBack = (take: LiveTake) => take.chips.filter((chip) => chip?.phase === 'tookBack').at(-1) as Extract<RouteView, { phase: 'tookBack' }> | undefined;

  it('takes the last sentence back into smoke, with a chip and Undo, and marks its stretch only once it settles', () => {
    const { take, say, wait, done } = record();
    say('Pick up the parcel.');
    say('The meeting is at three.');
    say('Scratch that.');
    expect(words(take)).toEqual(['Pick up the parcel.']);
    expect(tookBack(take)).toEqual({ phase: 'tookBack', said: 'The meeting is at three', outcome: 'gone', undo: expect.any(Number) });
    expect(take.log).toContain('Took back “The meeting is at three”');
    // Undo can still be tapped: the spans wait, and the quiet stop does too.
    expect(take.commandSpans).toEqual([]);
    expect(take.live.holding).toBe(true);
    wait(5500);
    expect(take.live.holding).toBe(false);
    expect(take.commandSpans).toEqual([
      { startMs: 1000, endMs: 1900 },
      { startMs: 2000, endMs: 2900 },
    ]);
    done();
    expect(take.result().made).toEqual(['# Pick up the parcel']);
    // Nothing engaged the reader, and the take's words are no longer the transcript's.
    expect(take.live.engaged).toBe(false);
    expect(take.live.changedWords).toBe(true);
  });

  it('takes the one before on a second scratch, and the last sentence of a phrase that held two', () => {
    const twice = record();
    twice.say('Pick up the parcel.');
    twice.say('Call the plumber.');
    twice.say('Ring the bank.');
    twice.say('Scratch that.');
    twice.say('Scratch that.');
    expect(words(twice.take)).toEqual(['Pick up the parcel.']);

    const inside = record();
    inside.say('We need eggs. Call Sam.');
    inside.say('Scratch that.');
    expect(words(inside.take)).toEqual(['We need eggs.']);
    expect(tookBack(inside.take)?.said).toBe('Call Sam');
    inside.say('Scratch that.');
    expect(words(inside.take)).toEqual([]);
  });

  it('reads the opener after the words it takes back, in one breath', () => {
    const stop = record();
    stop.say('We need eggs. Scratch that.');
    expect(words(stop.take)).toEqual([]);
    expect(tookBack(stop.take)?.said).toBe('We need eggs');

    const comma = record();
    comma.say('Pick up the parcel.');
    comma.say('The meeting is at three, scratch that.');
    expect(words(comma.take)).toEqual(['Pick up the parcel.']);

    const keyed = record();
    keyed.say('The heating is fixed, hey Ghost, scratch that.');
    expect(words(keyed.take)).toEqual([]);
    keyed.wait(5500);
    expect(keyed.take.keywordSpans).toEqual([{ startMs: 0, endMs: 900 }]);
  });

  it('takes an enumeration back as one, out of the one-shot it went to', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add milk, eggs and bread to groceries.');
    say('Scratch that.');
    expect(tookBack(take)?.said).toBe('milk, eggs, bread');
    done();
    expect(take.body('groceries')).toBe('# Groceries\n\n- Eggs\n');
    expect(take.result().made).toEqual(['# Kevin owns the release']);
  });

  it('replaces the sentence with one said again with a change, and leaves a new sentence as words', () => {
    const changed = record();
    changed.say('Pick up the parcel.');
    changed.say('The meeting is at three.');
    changed.say('Actually, the meeting is at four.');
    expect(words(changed.take)).toEqual(['Pick up the parcel.', 'The meeting is at four.']);
    expect(tookBack(changed.take)).toEqual({ phase: 'tookBack', said: 'The meeting is at three', outcome: { replaced: 'The meeting is at four' }, undo: expect.any(Number) });
    expect(changed.take.log).toContain('Replaced “The meeting is at three” with “The meeting is at four”');

    const fresh = record();
    fresh.say('The heating is fixed.');
    fresh.say('Actually, I think we should go.');
    expect(words(fresh.take)).toEqual(['The heating is fixed.', 'Actually, I think we should go.']);
    expect(fresh.take.live.changedWords).toBe(false);

    // Against the last sentence only.
    const last = record();
    last.say('We need eggs. Call Sam.');
    last.say('Actually, we need bread.');
    expect(words(last.take)).toEqual(['We need eggs. Call Sam.', 'Actually, we need bread.']);
  });

  it('takes a whole sentence after the keyword as the correction, sharing words or not', () => {
    const { take, say } = record();
    say('The heating is fixed.');
    say('Hey Ghost, actually, we should call the plumber.');
    expect(words(take)).toEqual(['We should call the plumber.']);
    expect(take.live.engaged).toBe(false);
  });

  it('changes one word: a number, a day, a name', () => {
    const number = record();
    number.say('The meeting is at three.');
    number.say('No wait, four.');
    expect(words(number.take)).toEqual(['The meeting is at four.']);
    expect(tookBack(number.take)).toEqual({ phase: 'tookBack', said: 'three', outcome: { changed: 'four' }, undo: expect.any(Number) });
    expect(number.take.log).toContain('Changed “three” to “four” in “The meeting is at three”');

    const breath = record();
    breath.say('The meeting is on Tuesday, no wait, Thursday.');
    expect(words(breath.take)).toEqual(['The meeting is on Thursday.']);

    const item = record();
    item.say('Kevin owns the release.');
    item.say('Hey Ghost, add call Sam to House TODOs.');
    item.say('Sorry, Sarah.');
    item.done();
    expect(item.take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sarah\n');
  });

  it('keeps the cue an item was written with when the item is said again', () => {
    const { take, say, done } = record();
    say("Hey Ghost, add a note to house to do's.");
    say('The note is call Sam about the invoice.');
    say('Actually, call Sarah about the invoice.');
    expect(take.page()).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sarah about the invoice\n');
    done();
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sarah about the invoice\n');

    // On a plain page too, where nothing else would make the sentence an item.
    const plain = record();
    plain.say('Check box, call Sam.');
    expect(plain.take.page()).toBe('- [ ] Call Sam');
    plain.say('Actually, call Sarah.');
    expect(plain.take.page()).toBe('- [ ] Call Sarah');
    expect(tookBack(plain.take)?.outcome).toEqual({ replaced: 'call Sarah' });
  });

  it('sends the sentence to the note named instead, in one breath or two, and shows its lines once the Undo goes', () => {
    const one = record();
    one.say('Pick up the parcel.');
    one.say('Oat milk.');
    one.say('Scratch that, add it to groceries instead.');
    expect(words(one.take)).toEqual(['Pick up the parcel.']);
    expect(tookBack(one.take)).toEqual({ phase: 'tookBack', said: 'Oat milk', outcome: { sent: 'Groceries' }, undo: expect.any(Number) });
    expect(one.take.log).toContain('Took back “Oat milk” and sent it to Groceries');
    // Its lines with Not this note only once the Undo has gone: the one-shot closes when the take-back settles.
    expect(one.take.ended).toEqual([]);
    one.wait(5500);
    expect(one.take.ended).toHaveLength(1);
    expect(one.take.chips.at(-1)).toEqual({ phase: 'tookBack', said: 'Oat milk', outcome: { sent: 'Groceries' }, undo: expect.any(Number) });
    one.done();
    expect(one.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Oat milk\n');
    expect(one.take.result().made).toEqual(['# Pick up the parcel']);

    for (const send of ['Add it to groceries instead.', 'Hey Ghost, put that in groceries.']) {
      const two = record();
      two.say('Pick up the parcel.');
      two.say('Oat milk.');
      two.say('Scratch that.', 1500);
      two.say(send);
      expect(words(two.take), send).toEqual(['Pick up the parcel.']);
      expect(tookBack(two.take)?.outcome, send).toEqual({ sent: 'Groceries' });
      two.done();
      expect(two.take.body('groceries'), send).toBe('# Groceries\n\n- Eggs\n- Oat milk\n');
      expect(two.take.result().made, send).toEqual(['# Pick up the parcel']);
      expect(two.take.commandSpans, send).toEqual([
        { startMs: 1000, endMs: 1900 },
        { startMs: 2000, endMs: 2900 },
        { startMs: 3500, endMs: 4400 },
      ]);
    }
  });

  it('leaves a sentence that names no note after a drop as words, and a book named puts the words back', () => {
    const plain = record();
    plain.say('Oat milk.');
    plain.say('Scratch that.');
    plain.say('Put it in the oven.');
    expect(words(plain.take)).toEqual(['Put it in the oven.']);

    const book = record();
    book.say('Oat milk.');
    book.say('Scratch that.');
    book.say('Add it to the field guide.');
    expect(words(book.take)).toEqual(['Oat milk.']);
    expect(lastChip(book.take)).toEqual({ phase: 'said', text: '“Field guide” is a notebook, so the words stay here.' });
  });

  it('keeps the words here when the send names no note, or a book, and says so', () => {
    const none = record();
    none.say('Oat milk.');
    none.say('Scratch that, add it to the moon base instead.');
    expect(words(none.take)).toEqual(['Oat milk.']);
    expect(lastChip(none.take)).toEqual({ phase: 'said', text: 'No note called “moon base”, so the words stay here.' });
    expect(none.take.live.changedWords).toBe(true);

    const book = record();
    book.say('Oat milk.');
    book.say('Scratch that, add it to the field guide.');
    expect(words(book.take)).toEqual(['Oat milk.']);
    expect(lastChip(book.take)).toEqual({ phase: 'said', text: '“Field guide” is a notebook, so the words stay here.' });
  });

  it('asks which note on a card for a send that is not sure, the words still on the page until it is answered', () => {
    const chosen = record();
    chosen.say('Pick up the parcel.');
    chosen.say('Check the form.');
    chosen.say('Scratch that, add it to signing.');
    expect(chosen.take.card).toMatchObject({ form: 'unsure', payload: 'Check the form' });
    expect(words(chosen.take)).toEqual(['Pick up the parcel.', 'Check the form.']);
    chosen.take.answer({ kind: 'note', id: 's2' });
    expect(words(chosen.take)).toEqual(['Pick up the parcel.']);
    chosen.done();
    expect(chosen.take.body('s2')).toBe('# Signing the order\n\nCheck the form.');

    const kept = record();
    kept.say('Pick up the parcel.');
    kept.say('Check the form.');
    kept.say('Scratch that, add it to signing.');
    kept.take.answer({ kind: 'keep' });
    expect(words(kept.take)).toEqual(['Pick up the parcel.', 'Check the form.']);
    expect(lastChip(kept.take)).toEqual({ phase: 'said', text: '“Check the form” stays here.' });
    kept.done();
    expect(kept.take.result().made).toEqual(['# Pick up the parcel\n\nCheck the form.']);
    expect(kept.take.body('s2')).toBe('# Signing the order\n');
  });

  it('puts the sentence in this note’s list when the send names it', () => {
    const house = library().find((n) => n.id === 'house')!;
    const { take, say, done } = record({ own: house });
    say('Went for a walk.');
    say('Buy fuses.');
    say('Scratch that, put that in the list.');
    expect(tookBack(take)).toEqual({ phase: 'tookBack', said: 'Buy fuses', outcome: { placed: 'in a list' }, undo: expect.any(Number) });
    done();
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Went for a walk\n- [ ] Buy fuses\n');
  });

  it('takes back and replaces in a one-shot, never on the page', () => {
    const gone = record();
    gone.say('Kevin owns the release.');
    gone.say('Hey Ghost, new item for groceries.');
    gone.say('Oat milk.');
    gone.say('Scratch that.');
    gone.done();
    expect(gone.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n');
    expect(gone.take.result().made).toEqual(['# Kevin owns the release']);

    const swapped = record();
    swapped.say('Kevin owns the release.');
    swapped.say('Hey Ghost, new item for groceries.');
    swapped.say('Oat milk.');
    swapped.say('Actually, almond milk.');
    expect(words(swapped.take)).toEqual(['Kevin owns the release.']);
    swapped.done();
    expect(swapped.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Almond milk\n');
  });

  it('cancels a command with nothing said for it yet, naming its words, and a risky opener there is its words', () => {
    const held = record();
    held.say('Hey Ghost, add a note to.');
    held.say('Scratch that.');
    expect(held.take.live.holding).toBe(false);
    expect(tookBack(held.take)).toEqual({ phase: 'tookBack', said: 'add a note to', outcome: 'gone' });
    expect(held.take.log).toContain('Took back the command “add a note to”');
    expect(words(held.take)).toEqual([]);

    const routed = record();
    routed.say("Hey Ghost, add a note to house to do's.");
    routed.say('Scratch that.');
    expect(routed.take.aim).toBeNull();
    expect(tookBack(routed.take)?.said).toBe("add a note to house to do's");
    // At its start again: the corrected command is sticky.
    routed.say('Hey Ghost, add a note to groceries.');
    expect(routed.take.aim?.id).toBe('groceries');
    routed.say('Oat milk.');
    routed.done();
    expect(routed.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Oat milk\n');
    expect(routed.take.body('house')).toBe(HOUSE);

    const payload = record();
    payload.say("Hey Ghost, add a note to house to do's.");
    payload.say('Actually, we need to call the plumber.');
    payload.done();
    expect(payload.take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Actually, we need to call the plumber\n');

    const opened = record();
    opened.say('Kevin owns the release.');
    opened.say('Hey Ghost, new item for groceries.');
    opened.say('Scratch that.');
    expect(tookBack(opened.take)?.said).toBe('new item for groceries');
    opened.say('Oat milk.');
    opened.done();
    expect(words(opened.take)).toEqual(['Kevin owns the release.', 'Oat milk.']);
    expect(opened.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n');
  });

  it('cancels a card with nothing said since it, and takes back the words said since one', () => {
    const empty = record();
    empty.say('Hey Ghost, add call Sam to signing.');
    expect(empty.take.card).not.toBeNull();
    empty.say('Scratch that.');
    expect(empty.take.card).toBeNull();
    expect(tookBack(empty.take)?.said).toBe('add call Sam to signing');
    empty.done();
    expect(empty.take.body('s1')).toBe('# Signing in, and signing\n');
    expect(empty.take.body('s2')).toBe('# Signing the order\n');
    expect(empty.take.result().made).toEqual([]);

    const after = record();
    after.say('Hey Ghost, add a note to signing;');
    after.say('Check the form.');
    after.say('Scratch that.');
    expect(after.take.card).not.toBeNull();
    expect(words(after.take)).toEqual([]);
    after.say('Check the date.');
    after.take.answer({ kind: 'note', id: 's2' });
    after.done();
    expect(after.take.body('s2')).toBe('# Signing the order\n\nCheck the date.');
  });

  it('says there is nothing to take back, and drops filler before the opener', () => {
    const nothing = record();
    nothing.say('Okay.');
    nothing.say('Scratch that.');
    expect(lastChip(nothing.take)).toEqual({ phase: 'said', text: 'Nothing to take back.' });
    expect(words(nothing.take)).toEqual([]);

    const keyed = record();
    keyed.say('Pick up the parcel.');
    keyed.say('Hey Ghost.');
    keyed.say('Scratch that.');
    expect(words(keyed.take)).toEqual([]);
    expect(tookBack(keyed.take)?.said).toBe('Pick up the parcel');

    const risky = record();
    risky.say('Actually, the meeting is at four.');
    expect(words(risky.take)).toEqual(['Actually, the meeting is at four.']);
  });

  it('reads the rest of a safe take-back as a phrase of its own', () => {
    const plain = record();
    plain.say('Call Sam.');
    plain.say('Scratch that, call the plumber.');
    expect(words(plain.take)).toEqual(['Call the plumber.']);

    const cue = record();
    cue.say('Call Sam.');
    cue.say('Scratch that, bullet point milk.');
    expect(cue.take.page()).toBe('- Milk');

    const twice = record();
    twice.say('Pick up the parcel.');
    twice.say('Call Sam.');
    twice.say('Scratch that, scratch that.');
    expect(words(twice.take)).toEqual([]);

    const sent = record();
    sent.say('Kevin owns the release.');
    sent.say('Call Sam.');
    sent.say('Scratch that, hey Ghost, add oat milk to groceries.');
    sent.done();
    expect(words(sent.take)).toEqual(['Kevin owns the release.']);
    expect(sent.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Oat milk\n');
  });

  it('puts everything back on Undo, the take-back written as the words it would have been, and pushes no spans', () => {
    const drop = record();
    drop.say('Pick up the parcel.');
    drop.say('The meeting is at three.');
    drop.say('Scratch that.');
    drop.take.undo(tookBack(drop.take)!.undo!);
    expect(words(drop.take)).toEqual(['Pick up the parcel.', 'The meeting is at three.', 'Scratch that.']);
    expect(lastChip(drop.take)).toEqual({ phase: 'done', text: 'Put back' });
    drop.wait(6000);
    expect(drop.take.commandSpans).toEqual([]);
    expect(drop.take.live.holding).toBe(false);

    const head = record();
    head.say('We need eggs. Scratch that.');
    head.take.undo(tookBack(head.take)!.undo!);
    expect(head.take.page()).toBe('# We need eggs\n\nScratch that.');

    const keyed = record();
    keyed.say('Call Sam.');
    keyed.say('Hey Ghost, no wait, Sarah.');
    expect(words(keyed.take)).toEqual(['Call Sarah.']);
    keyed.take.undo(tookBack(keyed.take)!.undo!);
    expect(words(keyed.take)).toEqual(['Call Sam.', 'No wait, Sarah.']);

    const sent = record();
    sent.say('Pick up the parcel.');
    sent.say('Oat milk.');
    sent.say('Scratch that, add it to groceries instead.');
    sent.take.undo(tookBack(sent.take)!.undo!);
    expect(words(sent.take)).toEqual(['Pick up the parcel.', 'Oat milk.', 'Scratch that, add it to groceries instead.']);
    sent.done();
    expect(sent.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n');

    const late = record();
    late.say('Call Sam.');
    late.say('Scratch that.');
    const id = tookBack(late.take)!.undo!;
    late.wait(5500);
    late.take.undo(id);
    expect(lastChip(late.take)).toEqual({ phase: 'said', text: 'Too late to put that back.' });
    expect(words(late.take)).toEqual([]);
  });

  it('takes back a phrase the reader at Done was to read, once a command reclaimed it', () => {
    const { take, say } = record();
    say('Hey Ghost, fix the spelling.');
    say('Buy milk.');
    say('Hey Ghost, add call Sam to House TODOs.');
    say('Scratch that.');
    expect(words(take)).toEqual(['Buy milk.']);
    expect(tookBack(take)?.said).toBe('Call Sam');
  });

  it('cannot reach words sealed by New note, said or tapped', () => {
    const daily = library().find((n) => n.id === 'daily')!;
    const said = record({ own: daily });
    said.say('Went for a run.');
    said.say('Hey Ghost, new note.');
    said.say('Scratch that.');
    expect(lastChip(said.take)).toEqual({ phase: 'said', text: 'Nothing to take back.' });
    said.done();
    expect(said.take.body('daily')).toBe('# Daily Life\n\nWent for a walk.\n\nWent for a run.');

    const tapped = record({ own: daily });
    tapped.say('Went for a run.');
    tapped.take.forked();
    tapped.say('Scratch that.');
    expect(lastChip(tapped.take)).toEqual({ phase: 'said', text: 'Nothing to take back.' });
    expect(tapped.take.parts).toHaveLength(1);
  });

  it('is never grown into by a name, and settles when the take moves on', () => {
    const grow = record();
    grow.say('Hey Ghost, add call Sam to house.');
    grow.say('Scratch that.');
    expect(grow.take.body('house')).toBe(HOUSE);
    expect(words(grow.take)).toEqual([]);

    const moved = record();
    moved.say('Call Sam.');
    moved.say('Scratch that.');
    moved.say('Hey Ghost, move this to groceries.');
    expect(moved.take.commandSpans.length).toBeGreaterThanOrEqual(2);
    moved.take.undo(tookBack(moved.take)!.undo!);
    expect(lastChip(moved.take)).toEqual({ phase: 'said', text: 'Too late to put that back.' });
  });

  it('over the lock screen, raises no card, names no note, and still takes back', () => {
    const { take, say, done } = record({ locked: true });
    say('Pick up the parcel.');
    say('Check the form.');
    say('Scratch that, add it to signing.');
    expect(take.card).toBeNull();
    expect(lastChip(take)).toEqual({ phase: 'said', text: 'Not sure which note, so the words stay here.' });
    say('Scratch that, add it to groceries.');
    expect(tookBack(take)?.outcome).toEqual({ sent: 'the note you named' });
    done();
    expect(take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Check the form\n');
  });

  it('names what Done settled unseen', () => {
    const { take, say, done } = record();
    say('Pick up the parcel.');
    say('Call Sam.');
    say('Scratch that.');
    done();
    expect(take.live.tookBackAtDone).toEqual(['Call Sam']);
    expect(take.commandSpans).toEqual([
      { startMs: 1000, endMs: 1900 },
      { startMs: 2000, endMs: 2900 },
    ]);
  });
  it('takes back the last thing said by time, not by when it landed, and only what the record holds', () => {
    // A card's payload that landed late is not the last thing said.
    const late = record();
    late.say('Hey Ghost, add call Sam to signing.');
    late.say('Buy milk.');
    late.take.answer({ kind: 'keep' });
    late.say('Scratch that.');
    expect(tookBack(late.take)?.said).toBe('Buy milk');
    expect(words(late.take)).toEqual(['Call Sam.']);

    // Words taken back under a mid-take card do not go with the note chosen.
    const under = record();
    under.say('Pick up the parcel.');
    under.say('Hey Ghost, add a note to signing;');
    under.say('Check the form.');
    under.say('Check the date.');
    under.say('Scratch that.');
    under.take.answer({ kind: 'note', id: 's2' });
    under.done();
    expect(under.take.body('s2')).toBe('# Signing the order\n\nCheck the form.');

    // Not this note on a one-shot brings its words home, where the next scratch finds them.
    const home = record();
    home.say('Kevin owns the release.');
    home.say('Hey Ghost, add call Sam to House TODOs.');
    const id = home.take.inserts.keys().next().value as number;
    home.take.apply(home.take.live.dropInsert(id));
    expect(words(home.take)).toEqual(['Kevin owns the release.', 'Call Sam.']);
    home.say('Scratch that.');
    expect(words(home.take)).toEqual(['Kevin owns the release.']);

    // Words a card sent to a note can be taken back out of it.
    const sent = record();
    sent.say('Pick up the parcel.');
    sent.say('Hey Ghost, add a note to signing;');
    sent.say('Check the form.');
    sent.take.answer({ kind: 'note', id: 's2' });
    sent.say('Scratch that.');
    expect(tookBack(sent.take)?.said).toBe('Check the form');
    sent.done();
    expect(sent.take.body('s2')).toBe('# Signing the order\n');
    expect(words(sent.take)).toEqual(['Pick up the parcel.']);

    // A replacement under a mid-take card goes with the note chosen.
    const replaced = record();
    replaced.say('Pick up the parcel.');
    replaced.say('Hey Ghost, add a note to signing;');
    replaced.say('The meeting is at three.');
    replaced.say('Actually, the meeting is at four.');
    replaced.take.answer({ kind: 'note', id: 's2' });
    replaced.done();
    expect(replaced.take.body('s2')).toBe('# Signing the order\n\nThe meeting is at four.');
    expect(words(replaced.take)).toEqual(['Pick up the parcel.']);
  });

  it('marks the stretches only as each take-back settles, and at once where there is no Undo', () => {
    // The next take-back settles the one before.
    const twice = record();
    twice.say('Pick up the parcel.');
    twice.say('Call the plumber.');
    twice.say('Ring the bank.');
    twice.say('Scratch that.');
    twice.say('Scratch that.');
    expect(twice.take.commandSpans).toEqual([
      { startMs: 2000, endMs: 2900 },
      { startMs: 3000, endMs: 3900 },
    ]);
    twice.wait(5500);
    expect(twice.take.commandSpans).toHaveLength(4);
    expect(twice.take.commandSpans).toEqual(expect.arrayContaining([{ startMs: 1000, endMs: 1900 }, { startMs: 4000, endMs: 4900 }]));

    // A send in the next breath restarts the window.
    const split = record();
    split.say('Oat milk.');
    split.say('Scratch that.');
    split.wait(3000);
    split.say('Add it to groceries instead.');
    split.wait(3000);
    expect(split.take.live.holding).toBe(true);
    expect(split.take.commandSpans).toEqual([]);
    split.wait(3000);
    expect(split.take.commandSpans).toHaveLength(3);

    // Nothing to take back still marks the phrase, and the filler before it, and neither is written at Done.
    const nothing = record();
    nothing.say('Okay.');
    nothing.say('Scratch that.');
    expect(nothing.take.commandSpans).toEqual([
      { startMs: 0, endMs: 900 },
      { startMs: 1000, endMs: 1900 },
    ]);
    expect(nothing.take.live.changedWords).toBe(true);
    expect(nothing.take.live.engaged).toBe(false);
    nothing.done();
    expect(nothing.take.result().made).toEqual([]);

    // A send's card, and a cancel, mark the phrase at once: the card, or the command said again, is the moment.
    const card = record();
    card.say('Check the form.');
    card.say('Scratch that, add it to signing.');
    expect(card.take.card).not.toBeNull();
    expect(card.take.commandSpans).toEqual([{ startMs: 1000, endMs: 1900 }]);
    const cancel = record();
    cancel.say('Hey Ghost, add a note to.');
    cancel.say('Scratch that.');
    expect(cancel.take.commandSpans).toEqual([
      { startMs: 0, endMs: 900 },
      { startMs: 1000, endMs: 1900 },
    ]);

    // Not this note settles an open take-back.
    const declined = record();
    declined.say("Hey Ghost, add a note to house to do's.");
    declined.say('Call Sam.');
    declined.say('Buy fuses.');
    declined.say('Scratch that.');
    expect(declined.take.commandSpans).toHaveLength(2);
    declined.take.decline(declined.now());
    expect(declined.take.commandSpans).toHaveLength(4);
    expect(declined.take.commandSpans).toEqual(expect.arrayContaining([{ startMs: 2000, endMs: 2900 }, { startMs: 3000, endMs: 3900 }]));
  });

  it('follows a bare drop only with a send in the next breath, and reads the rest after a cancel or nothing', () => {
    const after = record();
    after.say('The meeting is at three.');
    after.say('Actually, the meeting is at four.');
    after.say('Add it to groceries instead.');
    expect(words(after.take)).toEqual(['The meeting is at four.', 'Add it to groceries instead.']);
    expect(tookBack(after.take)?.outcome).toEqual({ replaced: 'The meeting is at four' });

    // A sentence between the drop and the send is what "it" means now.
    const between = record();
    between.say('Oat milk.');
    between.say('Scratch that.');
    between.say('Call the plumber.');
    between.say('Add it to groceries.');
    expect(words(between.take)).toEqual(['Call the plumber.', 'Add it to groceries.']);
    between.done();
    expect(between.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n');

    // The keyword alone between them is not: "Hey Ghost." | "Add it to groceries." is the send.
    const held = record();
    held.say('Oat milk.');
    held.say('Scratch that.');
    held.say('Hey Ghost.');
    held.say('Add it to groceries.');
    expect(tookBack(held.take)?.outcome).toEqual({ sent: 'Groceries' });
    expect(held.take.live.hearingCommand).toBe(false);
    expect(words(held.take)).toEqual([]);

    const none = record();
    none.say('Scratch that, call the plumber.');
    expect(words(none.take)).toEqual(['Call the plumber.']);
    const cancelled = record();
    cancelled.say('Hey Ghost, add a note to.');
    cancelled.say('Scratch that, call the plumber.');
    expect(words(cancelled.take)).toEqual(['Call the plumber.']);
  });

  it('restarts a one-shot’s clock and its count, and cuts the chip at forty', () => {
    const item = record();
    item.say('Kevin owns the release.');
    item.say('Hey Ghost, new item for groceries.');
    item.say('Oat milk.');
    item.wait(1000);
    item.say('Scratch that.');
    item.wait(1000);
    // Said as the first thing for the note again, an enumeration is its items.
    item.say('Milk, bread and butter.');
    item.done();
    expect(item.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Milk\n- Bread\n- Butter\n');
    expect(words(item.take)).toEqual(['Kevin owns the release.']);

    const long = record();
    long.say('This is a rather long sentence that goes on well past forty characters.');
    long.say('Scratch that.');
    expect(tookBack(long.take)?.said).toBe('This is a rather long sentence that goes…');
  });

  it('after the keyword, a whole sentence is the correction and a command is the command', () => {
    const hold = record();
    hold.say('The heating is fixed.');
    hold.say('Hey Ghost.');
    hold.say('Actually, we should call the plumber.');
    expect(words(hold.take)).toEqual(['We should call the plumber.']);
    expect(tookBack(hold.take)?.outcome).toEqual({ replaced: 'We should call the plumber' });

    // "Hey Ghost, actually, add a note to House TODOs" is that command, said as people say it: nothing is taken back.
    const command = record();
    command.say('Pick up the parcel.');
    command.say("Hey Ghost, actually, add a note to house to do's.");
    command.say('Call the plumber.');
    expect(words(command.take)).toEqual(['Pick up the parcel.']);
    expect(tookBack(command.take)).toBeUndefined();
    command.done();
    expect(command.take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call the plumber\n');

    const milk = record();
    milk.say('Pick up the parcel.');
    milk.say('Hey Ghost, actually, add milk to groceries.');
    expect(words(milk.take)).toEqual(['Pick up the parcel.']);
    milk.done();
    expect(milk.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Milk\n');

    const held = record();
    held.say('Pick up the parcel.');
    held.say('Hey Ghost.');
    held.say('Actually, add milk to groceries.');
    expect(words(held.take)).toEqual(['Pick up the parcel.']);
    held.done();
    expect(held.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Milk\n');

    // With nothing said before, a keyed risky opener is words as heard, so the page and the better words agree.
    const first = record();
    first.say('Hey Ghost, actually, the meeting is at four.');
    expect(words(first.take)).toEqual(['Hey Ghost, actually, the meeting is at four.']);
    expect(first.take.live.changedWords).toBe(false);
    expect(first.take.keywordSpans).toEqual([]);
  });

  it('keeps the keyword before a command head as the command’s: a new sentence after it is words', () => {
    const { take, say, done } = record();
    say('Kevin owns the release.');
    say('Hey Ghost, add call Sam to house. Actually, we should go for a walk.');
    expect(words(take)).toEqual(['Kevin owns the release.', 'Actually, we should go for a walk.']);
    expect(tookBack(take)).toBeUndefined();
    done();
    expect(take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
  });

  it('changes one word after a safe opener once, never twice, and never as a name after a stop', () => {
    const once = record();
    once.say('Call Sam.');
    once.say('Scratch that, Sarah.');
    expect(words(once.take)).toEqual(['Call Sarah.']);
    expect(tookBack(once.take)).toEqual({ phase: 'tookBack', said: 'Sam', outcome: { changed: 'Sarah' }, undo: expect.any(Number) });

    const shot = record();
    shot.say('Kevin owns the release.');
    shot.say('Hey Ghost, add call Sam to house.');
    shot.say('Scratch that, Sarah.');
    expect(words(shot.take)).toEqual(['Kevin owns the release.']);
    shot.done();
    expect(shot.take.body('house')).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sarah\n');

    // After a stop Whisper capitalises whatever comes next: "Tomorrow" is words, not a name to swap in.
    const stop = record();
    stop.say('Call Sam about the invoice.');
    stop.say('Scratch that. Tomorrow.');
    expect(words(stop.take)).toEqual(['Tomorrow.']);
  });

  it('puts a one-shot’s words back into it when the send’s card keeps them, or Done settles it, and sends them from it', () => {
    for (const answer of ['keep', 'done'] as const) {
      const { take, say, done } = record();
      say('Kevin owns the release.');
      say('Hey Ghost, new item for groceries.');
      say('Oat milk.');
      say('Scratch that, add it to signing.');
      expect(take.card, answer).toMatchObject({ form: 'unsure', payload: 'Oat milk' });
      expect(words(take), answer).toEqual(['Kevin owns the release.', 'Oat milk.']);
      if (answer === 'keep') take.answer({ kind: 'keep' });
      done();
      expect(lastChip(take), answer).toEqual({ phase: 'said', text: '“Oat milk” stays where it was.' });
      expect(words(take), answer).toEqual(['Kevin owns the release.']);
      expect(take.body('groceries'), answer).toBe('# Groceries\n\n- Eggs\n- Oat milk\n');
      expect(take.result().made, answer).toEqual(['# Kevin owns the release']);
    }

    const chosen = record();
    chosen.say('Kevin owns the release.');
    chosen.say('Hey Ghost, new item for groceries.');
    chosen.say('Oat milk.');
    chosen.say('Scratch that, add it to signing.');
    chosen.take.answer({ kind: 'note', id: 's2' });
    chosen.done();
    expect(chosen.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n');
    expect(chosen.take.body('s2')).toBe('# Signing the order\n\nOat milk.');
    expect(chosen.take.result().made).toEqual(['# Kevin owns the release']);
  });

  it('asks on the card for a send in the next breath that is not sure, and puts the words back for a keyworded name that finds nothing', () => {
    const unsure = record();
    unsure.say('Pick up the parcel.');
    unsure.say('Oat milk.');
    unsure.say('Scratch that.');
    unsure.say('Add it to signing.');
    expect(unsure.take.card).toMatchObject({ form: 'unsure', heading: 'Add to which note?', payload: 'Oat milk' });
    expect(words(unsure.take)).toEqual(['Pick up the parcel.', 'Oat milk.']);
    expect(unsure.take.commandSpans).toEqual(expect.arrayContaining([{ startMs: 2000, endMs: 2900 }, { startMs: 3000, endMs: 3900 }]));
    unsure.take.answer({ kind: 'note', id: 's2' });
    expect(words(unsure.take)).toEqual(['Pick up the parcel.']);
    unsure.done();
    expect(unsure.take.body('s2')).toBe('# Signing the order\n\nOat milk.');

    const keyed = record();
    keyed.say('Pick up the parcel.');
    keyed.say('Oat milk.');
    keyed.say('Scratch that.');
    keyed.say('Hey Ghost, add it to signing.');
    expect(keyed.take.card).toMatchObject({ form: 'unsure', payload: 'Oat milk' });
    expect(keyed.take.live.hearingCommand).toBe(false);
    keyed.take.answer({ kind: 'keep' });
    expect(words(keyed.take)).toEqual(['Pick up the parcel.', 'Oat milk.']);
    expect(lastChip(keyed.take)).toEqual({ phase: 'said', text: '“Oat milk” stays here.' });

    const missing = record();
    missing.say('Oat milk.');
    missing.say('Scratch that.');
    missing.say('Hey Ghost, add it to the moon base.');
    expect(missing.take.card).toBeNull();
    expect(words(missing.take)).toEqual(['Oat milk.']);
    expect(lastChip(missing.take)).toEqual({ phase: 'said', text: 'No note called “moon base”, so the words stay here.' });
    expect(missing.take.live.holding).toBe(false);
  });

  it('waits for the name Whisper cut from a send’s opener, and writes neither', () => {
    const { take, say, done } = record();
    say('Pick up the parcel.');
    say('Oat milk.');
    say('Scratch that, add it to');
    expect(words(take)).toEqual(['Pick up the parcel.']);
    expect(take.live.holding).toBe(true);
    say('Groceries instead.');
    expect(words(take)).toEqual(['Pick up the parcel.']);
    expect(tookBack(take)?.outcome).toEqual({ sent: 'Groceries' });
    done();
    expect(take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Oat milk\n');
    expect(take.result().made).toEqual(['# Pick up the parcel']);

    // No name comes: a plain drop, the opener never written.
    const plain = record();
    plain.say('Oat milk.');
    plain.say('Scratch that, add it to');
    plain.say('Call the plumber.');
    expect(words(plain.take)).toEqual(['Call the plumber.']);
    plain.done();
    expect(plain.take.result().made).toEqual(['# Call the plumber']);
  });

  it('puts the sentence in a list of a fresh take when the send names “the list”', () => {
    const { take, say, done } = record();
    say('Pick up the parcel.');
    say('Oat milk.');
    say('Scratch that, put that in the list.');
    expect(take.card).toBeNull();
    expect(tookBack(take)).toEqual({ phase: 'tookBack', said: 'Oat milk', outcome: { placed: 'in a list' }, undo: expect.any(Number) });
    expect(take.page()).toBe('# Pick up the parcel\n\n- Oat milk');
    done();
    expect(take.result().made).toEqual(['# Pick up the parcel\n\n- Oat milk']);
  });

  it('is past its start after New note is tapped, as after the spoken cue', () => {
    for (const how of ['said', 'tapped'] as const) {
      const { take, say } = record();
      say('Went for a run.');
      if (how === 'said') say('Hey Ghost, new note.');
      else take.forked();
      say("Hey Ghost, add a note to house to do's.");
      expect(take.aim, how).toBeNull();
      expect(take.routed, how).toBe(false);
      expect(take.inserts.size, how).toBe(1);
    }
  });

  it('leaves a new sentence after a risky opener as words, which a later scratch takes back alone', () => {
    const { take, say } = record();
    say('Pick up the parcel.');
    say('We need eggs. Actually, I think we should go.');
    expect(words(take)).toEqual(['Pick up the parcel.', 'We need eggs.', 'Actually, I think we should go.']);
    say('Scratch that.');
    expect(words(take)).toEqual(['Pick up the parcel.', 'We need eggs.']);
    expect(tookBack(take)?.said).toBe('Actually, I think we should go');
  });

  it('on Undo, writes a keyworded phrase without its keyword and marks its stretch, and a correction back into its one-shot', () => {
    const send = record();
    send.say('Pick up the parcel.');
    send.say('Oat milk.');
    send.say('Scratch that.');
    send.say('Hey Ghost, put that in groceries.');
    send.take.undo(tookBack(send.take)!.undo!);
    expect(words(send.take)).toEqual(['Pick up the parcel.', 'Oat milk.', 'Scratch that.', 'Put that in groceries.']);
    expect(send.take.keywordSpans).toEqual([{ startMs: 3000, endMs: 3900 }]);
    expect(send.take.commandSpans).toEqual([]);

    const keyed = record();
    keyed.say('Call Sam.');
    keyed.say('Hey Ghost, scratch that.');
    keyed.take.undo(tookBack(keyed.take)!.undo!);
    expect(words(keyed.take)).toEqual(['Call Sam.', 'Scratch that.']);
    const heard = [
      { text: 'Call Sam.', startMs: 0, endMs: 900 },
      { text: 'Hey Ghost, scratch that.', startMs: 1000, endMs: 1900 },
    ];
    expect(withoutCommands({ skip: keyed.take.commandSpans, keywordAt: keyed.take.keywordSpans, live: keyed.take.segments }, heard).map((s) => s.text)).toEqual(['Call Sam.', 'Scratch that.']);

    const head = record();
    head.say('The heating is fixed, hey Ghost, scratch that.');
    head.take.undo(tookBack(head.take)!.undo!);
    expect(words(head.take)).toEqual(['The heating is fixed.', 'Scratch that.']);
    const whole = [{ text: 'The heating is fixed, hey Ghost, scratch that.', startMs: 0, endMs: 900 }];
    expect(withoutCommands({ skip: head.take.commandSpans, keywordAt: head.take.keywordSpans, live: head.take.segments }, whole).map((s) => s.text)).toEqual(['The heating is fixed.', 'Scratch that.']);

    const shot = record();
    shot.say('Kevin owns the release.');
    shot.say('Hey Ghost, new item for groceries.');
    shot.say('Oat milk.');
    shot.say('Actually, almond milk.');
    shot.take.undo(tookBack(shot.take)!.undo!);
    expect(words(shot.take)).toEqual(['Kevin owns the release.']);
    shot.done();
    expect(shot.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n- Oat milk\n- Actually, almond milk\n');
    expect(shot.take.result().made).toEqual(['# Kevin owns the release']);
  });

  it('on Undo, puts a phrase left for the reader at Done back for it, writes a split send as words, and stays off the transcript', () => {
    const left = record();
    left.say('Hey Ghost, fix the spelling.');
    left.say('Scratch that.');
    expect(tookBack(left.take)?.said).toBe('fix the spelling');
    left.take.undo(tookBack(left.take)!.undo!);
    expect(words(left.take)).toEqual(['Hey Ghost, fix the spelling.', 'Scratch that.']);
    left.say('Hey Ghost, add call Sam to House TODOs.');
    // The reader engaged, so the phrase left for the reader at Done is reclaimed off the page.
    expect(words(left.take)).toEqual(['Scratch that.']);

    const split = record();
    split.say('Oat milk.');
    split.say('Scratch that.', 1500);
    split.say('Add it to groceries instead.');
    split.take.undo(tookBack(split.take)!.undo!);
    expect(words(split.take)).toEqual(['Oat milk.', 'Scratch that.', 'Add it to groceries instead.']);
    split.done();
    expect(split.take.body('groceries')).toBe('# Groceries\n\n- Eggs\n');

    const after = record();
    after.say('Call Sam.');
    after.say('Scratch that.');
    const id = tookBack(after.take)!.undo!;
    after.take.undo(id);
    expect(after.take.live.changedWords).toBe(true);
    after.done();
    after.take.undo(id);
    expect(lastChip(after.take)).toEqual({ phase: 'said', text: 'Too late to put that back.' });
  });
});
