import { describe, expect, it } from 'vitest';
import { enumeration, renderNote, setSpokenFormats, spokenInlineMarkup, toParagraphs, type Segment } from './markdown.ts';

/**
 * What a spoken note becomes.
 *
 * The cases fall into two groups and both matter. The first proves the rules
 * catch what they are for. The second - "does NOT become a list", "is NOT a
 * title" - proves the precision the module's header promises, because a false
 * list mangles prose that would otherwise have read fine, and that failure is
 * invisible until it happens to a real note.
 */

/** Segments one second long with a short breath between each. */
function spoken(...texts: string[]): Segment[] {
  let at = 0;
  return texts.map((text) => {
    const segment = { text, startMs: at, endMs: at + 1000 };
    at += 1300;
    return segment;
  });
}

describe('toParagraphs', () => {
  it('joins segments separated by a breath into one paragraph', () => {
    expect(toParagraphs(spoken('The first thought.', 'And more of it.'))).toEqual(['The first thought. And more of it.']);
  });

  it('starts a new paragraph after a long pause', () => {
    const segments: Segment[] = [
      { text: 'One idea.', startMs: 0, endMs: 1000 },
      { text: 'A different one.', startMs: 4000, endMs: 5000 },
    ];
    expect(toParagraphs(segments)).toEqual(['One idea.', 'A different one.']);
  });

  it('breaks on a spoken "new paragraph" and removes the cue', () => {
    expect(toParagraphs(spoken('That covers it. New paragraph. the next part.'))).toEqual([
      'That covers it.',
      'The next part.',
    ]);
  });
});

describe('enumeration', () => {
  it('finds a list after a word that introduces one', () => {
    expect(enumeration('I need eggs, milk, bread and coffee.')).toEqual({
      intro: 'I need',
      items: ['eggs', 'milk', 'bread', 'coffee'],
    });
  });

  it('keeps a determiner with the first item', () => {
    expect(enumeration('We should pick up some eggs, milk and bread.')?.items[0]).toBe('some eggs');
  });

  it('accepts an Oxford comma', () => {
    expect(enumeration('The team is Sarah, Tom, and Priya.')?.items).toEqual(['Sarah', 'Tom', 'Priya']);
  });

  /*
   * The reason the rule demands an introducing word. These commas are clauses,
   * and without the demand this sentence became "We went to:" over three
   * bullets.
   */
  it('does NOT treat a sequence of clauses as a list', () => {
    expect(enumeration('We went to the store, bought food, and came home.')).toBeNull();
  });

  it('does NOT make a list of long items', () => {
    expect(enumeration('I need the report from last quarter, the slides we used in March, and the budget.')).toBeNull();
  });

  it('does NOT make a list of two items', () => {
    expect(enumeration('I need eggs and milk.')).toBeNull();
  });
});

describe('renderNote with local rules', () => {
  it('turns a short opening into the title', () => {
    const { markdown } = renderNote(spoken('Grocery run.', 'It has to happen before Saturday.'));
    expect(markdown).toBe('# Grocery run\n\nIt has to happen before Saturday.');
  });

  it('does NOT title a long opening', () => {
    const { markdown } = renderNote(spoken('So I was thinking about how the launch went last week.'));
    expect(markdown.startsWith('#')).toBe(false);
  });

  it('does NOT title an opening to-do', () => {
    const { markdown } = renderNote(spoken('I need to call the bank.'));
    expect(markdown).toBe('- [ ] Call the bank');
  });

  it('honours a spoken title cue', () => {
    expect(renderNote(spoken('Title: launch retro.', 'It went well.')).markdown).toBe('# Launch retro\n\nIt went well.');
  });

  it('gives a recording added to a note no title of its own', () => {
    const untitled = { titled: false };
    expect(renderNote(spoken('Grocery run.', 'It has to happen before Saturday.'), '', untitled).markdown).toBe(
      'Grocery run. It has to happen before Saturday.',
    );
    // A spoken title there is a section, not a second title mid-note.
    expect(renderNote(spoken('Title: launch retro.', 'It went well.'), '', untitled).markdown).toBe(
      '## Launch retro\n\nIt went well.',
    );
    expect(renderNote(spoken('Title.', 'Launch retro.', 'It went well.'), '', untitled).markdown.startsWith('## ')).toBe(true);
  });

  it('makes to-dos out of "need to" and "remember to"', () => {
    const { markdown } = renderNote(
      spoken('Weekend plans.', 'I need to call the plumber.', "Don't forget to pay the rent."),
    );
    expect(markdown).toBe('# Weekend plans\n\n- [ ] Call the plumber\n- [ ] Pay the rent');
  });

  it('renders a spoken list under its intro', () => {
    const { markdown } = renderNote(spoken('Shopping.', 'I need eggs, milk, bread and coffee.'));
    expect(markdown).toBe('# Shopping\n\nI need:\n- eggs\n- milk\n- bread\n- coffee');
  });

  it('separates a list intro from a to-do directly above it', () => {
    const { markdown } = renderNote(spoken('Trip prep.', 'I need to renew my passport.', 'I need socks, shirts and a charger.'));
    expect(markdown).toBe('# Trip prep\n\n- [ ] Renew my passport\n\nI need:\n- socks\n- shirts\n- a charger');
  });

  it('closes a spoken list before a to-do that follows it', () => {
    const { markdown } = renderNote(spoken('Road trip.', 'For the drive we want snacks, water and a charger.', 'Remember to ask Sam about the dog.'));
    expect(markdown).toBe('# Road trip\n\nFor the drive we want:\n- snacks\n- water\n- a charger\n\n- [ ] Ask Sam about the dog');
  });

  it('numbers an ordinal run once "first" has started it', () => {
    const { markdown } = renderNote(
      spoken('Deploy steps.', 'First, build the app.', 'Then run the tests.', 'Finally, ship it.'),
    );
    expect(markdown).toBe('# Deploy steps\n\n1. Build the app\n2. Run the tests\n3. Ship it');
  });

  it('does NOT number "then" without a "first"', () => {
    const { markdown } = renderNote(spoken('It rained all morning and then it cleared up.', 'Then we went out.'));
    expect(markdown).not.toMatch(/^\d\./m);
  });

  it('honours spoken heading and bullet cues', () => {
    const { markdown } = renderNote(
      spoken('This is a longer opening sentence about the week.', 'Heading: next steps.', 'Bullet point: book flights.'),
    );
    expect(markdown).toBe('This is a longer opening sentence about the week.\n\n## Next steps\n\n- Book flights');
  });

  it('emboldens a spoken "important"', () => {
    const { markdown } = renderNote(spoken('This is a longer opening about the deadline itself.', 'Important: it moved to Friday.'));
    expect(markdown).toContain('**Important:** it moved to Friday.');
  });

  // The paragraph survives rendering, not just toParagraphs: sentences of one
  // paragraph are joined back into a line, and that join must stop at a break.
  it('keeps a "new paragraph" said as its own segment', () => {
    const { markdown } = renderNote(
      spoken('The kitchen needs work before we list it.', 'New paragraph.', 'The garden is fine as it is.'),
    );
    expect(markdown).toBe('The kitchen needs work before we list it.\n\nThe garden is fine as it is.');
  });

  it('keeps a "new paragraph" said mid-segment', () => {
    const { markdown } = renderNote(
      spoken('The kitchen needs work before we list it. New paragraph. The garden is fine as it is.'),
    );
    expect(markdown).toBe('The kitchen needs work before we list it.\n\nThe garden is fine as it is.');
  });

  it('keeps a paragraph broken by a long pause', () => {
    const { markdown } = renderNote([
      { text: 'The kitchen needs work before we list it.', startMs: 0, endMs: 2000 },
      { text: 'The garden is fine as it is.', startMs: 5000, endMs: 7000 },
    ]);
    expect(markdown).toBe('The kitchen needs work before we list it.\n\nThe garden is fine as it is.');
  });

  it('still joins the sentences inside one paragraph', () => {
    const { markdown } = renderNote(
      spoken('The kitchen needs work before we list it.', 'The cupboards are the worst of it.'),
    );
    expect(markdown).toBe('The kitchen needs work before we list it. The cupboards are the worst of it.');
  });
});

describe('renderNote with the in-progress phrase', () => {
  it('appends the partial to the last paragraph and reports where it starts', () => {
    const { markdown, pendingFrom } = renderNote(
      spoken('This is a longer opening sentence to avoid a title.'),
      'and this is still',
    );
    expect(markdown).toBe('This is a longer opening sentence to avoid a title. and this is still');
    expect(markdown.slice(pendingFrom ?? 0)).toBe('and this is still');
  });

  it('puts the partial on its own line after a list', () => {
    const { markdown, pendingFrom } = renderNote(spoken('I need to call the bank.'), 'and then');
    expect(markdown).toBe('- [ ] Call the bank\n\nand then');
    expect(markdown.slice(pendingFrom ?? 0)).toBe('and then');
  });

  it('keeps the partial out of the committed transcript', () => {
    expect(renderNote(spoken('Committed words.'), 'not yet').plain).toBe('Committed words.');
  });
});

/*
 * The cues the "how to talk to Glyph" guide teaches. The guide renders its own
 * examples through renderNote, so these tests are the contract it relies on:
 * each cue does what the guide says, and each one leaves ordinary speech alone.
 */
describe('guide cues', () => {
  const opening = 'This opening sentence is long enough not to become a title.';

  it('quotes', () => {
    expect(renderNote(spoken(opening, 'Quote, the best way out is always through.')).markdown).toBe(
      `${opening}\n\n> The best way out is always through.`,
    );
  });

  it('keeps consecutive quotes in one block', () => {
    const { markdown } = renderNote(spoken(opening, 'Quote, first line.', 'Quote, second line.'));
    expect(markdown).toBe(`${opening}\n\n> First line.\n> Second line.`);
  });

  it('numbers spoken "number one, number two"', () => {
    const { markdown } = renderNote(spoken(opening, 'Number one, book flights.', 'Number 2, pack bags.'));
    expect(markdown).toBe(`${opening}\n\n1. Book flights\n2. Pack bags`);
  });

  it('does NOT number "number one" said as prose', () => {
    expect(renderNote(spoken(opening, 'Number one priority is sleep.')).markdown).not.toMatch(/^\d\./m);
  });

  it('makes a check box', () => {
    expect(renderNote(spoken(opening, 'Check box, call the dentist.')).markdown).toBe(`${opening}\n\n- [ ] Call the dentist`);
    expect(renderNote(spoken(opening, 'Checklist item, renew passport.')).markdown).toBe(
      `${opening}\n\n- [ ] Renew passport`,
    );
  });

  it('does NOT make a check box of a sentence about a checklist', () => {
    expect(renderNote(spoken(opening, 'Checklist for the trip is done.')).markdown).not.toContain('- [ ]');
  });

  it('draws a divider behind a blank line', () => {
    // Straight under text, `---` would turn that text into a heading.
    expect(renderNote(spoken(opening, 'Divider.', 'After the break.')).markdown).toBe(`${opening}\n\n---\n\nAfter the break.`);
  });

  it('bolds between "bold" and "end bold", even across the pauses Whisper writes as full stops', () => {
    expect(renderNote(spoken(`${opening} The deadline is bold Friday end bold.`)).markdown).toContain('The deadline is **Friday**.');
    expect(renderNote(spoken(opening, 'The deadline is bold.', 'Friday.', 'End bold.')).markdown).toContain(
      'The deadline is **Friday**.',
    );
  });

  it('italicises between "italic" and "end italic"', () => {
    expect(renderNote(spoken(`${opening} Read italic Klara and the Sun end italic next.`)).markdown).toContain(
      '_Klara and the Sun_ next',
    );
  });

  // What base.en writes for "end" on most voices: it sounds the same as "and".
  it('closes on "and bold" when Whisper marked a pause after the opening cue', () => {
    expect(renderNote(spoken(opening, 'Italics, maybe, and italics.')).markdown).toContain('_maybe_.');
    expect(renderNote(spoken(opening, 'Bold. This really matters and bold.')).markdown).toContain('**This really matters**.');
  });

  it('closes on "and bold" that ends the sentence, the way Whisper writes "end bold" said plainly', () => {
    expect(renderNote(spoken(`${opening} The deadline is bold Friday at noon and bold.`)).markdown).toContain('The deadline is **Friday at noon**.');
    expect(renderNote(spoken(opening, 'The deadline is italics next Friday and italics.')).markdown).toContain('The deadline is _next Friday_.');
  });

  it('does NOT close on "and bold" with no pause after the opening word', () => {
    expect(renderNote(spoken(`${opening} It was bold thinking and bold action.`)).markdown).not.toContain('**');
    expect(renderNote(spoken(`${opening} It was bold, brash thinking.`)).markdown).not.toContain('**');
  });

  it('does NOT bold "bold" without "end bold"', () => {
    expect(renderNote(spoken(`${opening} That was a bold move.`)).markdown).not.toContain('**');
  });

  it('keeps a sentence that starts with bolded words separate from the one before', () => {
    const { markdown } = renderNote(spoken(opening, 'Heading, plan.', 'Bold Friday end bold is the day.'));
    expect(markdown).toContain('**Friday** is the day.');
  });
});

describe('a cue said as its own sentence', () => {
  const opening = 'This opening sentence is long enough not to become a title.';

  /*
   * How people actually dictate a command: word, pause, content. Whisper writes
   * the pause as a full stop, and before this rule the note got the literal
   * word "Heading."
   */
  it('applies to the sentence after it', () => {
    expect(renderNote(spoken(opening, 'Heading.', 'Next steps.')).markdown).toBe(`${opening}\n\n## Next steps`);
    expect(renderNote(spoken(opening, 'Bullet point.', 'Book flights.')).markdown).toBe(`${opening}\n\n- Book flights`);
    expect(renderNote(spoken(opening, 'Quote.', 'Stay hungry.')).markdown).toBe(`${opening}\n\n> Stay hungry.`);
    expect(renderNote(spoken(opening, 'To do.', 'Call mom.')).markdown).toBe(`${opening}\n\n- [ ] Call mom`);
    expect(renderNote(spoken(opening, 'Number one.', 'Wake up.')).markdown).toBe(`${opening}\n\n1. Wake up`);
  });

  it('carries across a long pause into the next paragraph', () => {
    const segments: Segment[] = [
      { text: opening, startMs: 0, endMs: 1000 },
      { text: 'Heading.', startMs: 1200, endMs: 1800 },
      { text: 'After a long think.', startMs: 5000, endMs: 6000 },
    ];
    expect(renderNote(segments).markdown).toBe(`${opening}\n\n## After a long think`);
  });

  it('makes a spoken title from "Title." then the words', () => {
    expect(renderNote(spoken('Title.', 'Launch retro.', 'It went well.')).markdown).toBe('# Launch retro\n\nIt went well.');
  });

  /*
   * The guard against prompt leakage: Whisper is prompted with the cue words, and
   * a prompted model can echo one on a quiet window. With nothing after it, the
   * echo never reaches the note.
   */
  it('renders nothing for a cue with nothing after it', () => {
    expect(renderNote(spoken(opening, 'Bullet point.')).markdown).toBe(opening);
    expect(renderNote(spoken('Heading.')).markdown).toBe('');
  });
});

describe('lists said the way people say them', () => {
  // Matt's first real list on the Fold, 2026-09-13, as Whisper wrote it.
  const matt = [
    'Hey, this is me trying out the new app.',
    "I'd like you to add a list below.",
    'List item is weed.',
    "List item is Culver's onion ring.",
    "The next list item is Culver's cement mixer ice cream.",
    'And lastly, the final item that we need on our list is a gallon of black coffee.',
    'If you don’t order it in the head home and they will have a limited end.',
  ];

  it('makes a list of "list item is", "the next list item is" and "the final item … is"', () => {
    expect(renderNote(spoken(...matt)).markdown).toBe(
      [
        "Hey, this is me trying out the new app. I'd like you to add a list below.",
        '',
        '- Weed',
        "- Culver's onion ring",
        "- Culver's cement mixer ice cream",
        '- A gallon of black coffee',
        '',
        'If you don’t order it in the head home and they will have a limited end.',
      ].join('\n'),
    );
  });

  it('keeps a list numbered when it started with "number one"', () => {
    const numbered = [...matt];
    numbered[2] = 'Number one, list item is weed.';
    numbered[3] = "Number two, list item is Culver's onion ring.";
    const { markdown } = renderNote(spoken(...numbered));
    expect(markdown).toContain("1. Weed\n2. Culver's onion ring\n3. Culver's cement mixer ice cream\n4. A gallon of black coffee");
  });

  it('keeps the list whole across a long pause between items', () => {
    const segments: Segment[] = [
      { text: 'Here is my shopping list.', startMs: 0, endMs: 1500 },
      { text: 'The first item is oat milk.', startMs: 1800, endMs: 3000 },
      { text: 'Another item is eggs.', startMs: 6500, endMs: 7500 },
    ];
    expect(renderNote(segments).markdown).toContain('- Oat milk\n- Eggs');
  });

  it('takes short items after a list is announced', () => {
    const { markdown } = renderNote(spoken(opening(), 'Here is my packing list.', 'Sunscreen.', 'Two towels.', 'The good speaker.', 'We leave at noon on Saturday if the weather holds.'));
    expect(markdown).toContain('- Sunscreen\n- Two towels\n- The good speaker\n\nWe leave at noon');
  });

  it('makes a numbered list when one is asked for', () => {
    expect(renderNote(spoken(opening(), 'Make a numbered list.', 'Preheat the oven.', 'Mix the batter.')).markdown).toContain(
      '1. Preheat the oven\n2. Mix the batter',
    );
  });

  it('does NOT make list items of ordinary sentences', () => {
    const prose = renderNote(
      spoken(opening(), 'The thing is, I am tired.', 'The item is broken again.', 'Next week is busy.', 'One is enough for now.'),
    ).markdown;
    expect(prose).not.toMatch(/^- /m);
  });

  it('does NOT take a short reply after a cue as an item', () => {
    expect(renderNote(spoken(opening(), 'Bullet point, eggs.', 'Thanks.')).markdown).toBe(`${opening()}\n\n- Eggs\n\nThanks.`);
  });

  it('does NOT take long sentences as items just because a list was mentioned', () => {
    const { markdown } = renderNote(spoken(opening(), 'I made a list yesterday.', 'It had everything we talked about on the phone last night.'));
    expect(markdown).not.toMatch(/^- /m);
  });
});

describe('"the next item is" with the item in the next phrase', () => {
  it('takes the next phrase as the item when the phrase naming it stops short', () => {
    const { markdown } = renderNote(
      spoken(opening(), 'Here is my travel list.', 'The first item is the Grand Canyon.', 'The next item is.', 'Paris.', 'The next item is. Greece.'),
    );
    expect(markdown).toContain('- The Grand Canyon\n- Paris\n- Greece');
  });

  it('keeps an item phrase with no item and nothing after it as words', () => {
    expect(renderNote(spoken(opening(), 'The next item is.')).markdown).toBe(`${opening()} The next item is.`);
  });

  it('reads Whisper’s own inline numbering as a numbered list', () => {
    // Matt's Fold, 2026-09-13: Whisper wrote the spoken "the next item is" as numbers.
    const { markdown } = renderNote(spoken(opening(), '1. The Grand Canyon 2. Spain 3. The next item is', 'Paris.', 'The next item is. Greece.'));
    expect(markdown).toContain('1. The Grand Canyon\n2. Spain\n3. Paris\n4. Greece');
  });

  it('waits for the item after "number three, the next item is", keeping the count', () => {
    // As Matt's Fold rendered it before the fix: "3. The next item is" / "Paris." / "The next item is. Greece."
    const segments: Segment[] = [
      { text: opening(), startMs: 0, endMs: 2000 },
      { text: 'Number one, the Grand Canyon.', startMs: 2300, endMs: 4000 },
      { text: 'Number two, Spain.', startMs: 4300, endMs: 5500 },
      { text: 'Number three, the next item is', startMs: 5800, endMs: 7200 },
      { text: 'Paris.', startMs: 10_000, endMs: 10_800 },
      { text: 'The next item is. Greece.', startMs: 14_000, endMs: 16_000 },
    ];
    expect(renderNote(segments).markdown).toContain('1. The Grand Canyon\n2. Spain\n3. Paris\n4. Greece');
  });

  it('does NOT split ordinary numbers in a sentence', () => {
    const prose = renderNote(spoken(opening(), 'We need 2. Maybe 3 if Sam comes.', 'I was born in 1990. It was cold.')).markdown;
    expect(prose).not.toMatch(/^\d+\. /m);
  });
});

function opening(): string {
  return 'This opening sentence is long enough not to become a title.';
}

describe('a plugin formatting said aloud', () => {
  it('wraps "spoiler … end spoiler" in the plugin\'s delimiter, and leaves bold as it was', () => {
    setSpokenFormats([{ word: 'spoiler', delimiter: '||' }]);
    try {
      expect(spokenInlineMarkup('The winner is spoiler. The butler. End spoiler. And bold. Friday. End bold.')).toBe('The winner is ||The butler||. And **Friday**.');
      expect(spokenInlineMarkup('No spoilers here, spoiler alert.')).toBe('No spoilers here, spoiler alert.');
    } finally {
      setSpokenFormats([]);
    }
  });
});
