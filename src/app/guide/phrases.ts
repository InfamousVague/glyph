import { renderNote, type Segment } from '../capture/markdown.ts';

/**
 * What to SAY to get markdown, as the guide teaches it.
 *
 * Every example is rendered by the real speech-to-markdown rules at runtime
 * (`renderNote`), never typed out by hand: the guide shows exactly what the
 * capture screen would write, so a rule that changes cannot leave the guide
 * promising the old behaviour. guide.test.ts pins what each example must still
 * produce, so a rule that REGRESSES fails a test instead of quietly teaching
 * something that no longer works.
 *
 * Only cues src/app/capture/markdown.ts implements belong here: the note is
 * shaped by what was said and nothing else.
 */

export interface Example {
  /** What to say, one phrase per pause - the way Whisper commits it. */
  say: string[];
  /** A marker the rendered markdown must contain; checked by guide.test.ts. */
  expect: string;
}

export interface PhraseGroup {
  title: string;
  /** One line on when to use it. */
  lead: string;
  /** The words that trigger it, as a person would read them. */
  cues: string[];
  example: Example;
}

export const PHRASES: PhraseGroup[] = [
  {
    title: 'Name the note',
    lead: 'Say it first. A short first sentence becomes the title anyway.',
    cues: ['“Title”', '“Call this note”'],
    example: { say: ['Title: weekend trip.', 'We leave on Friday after work.'], expect: '# Weekend trip' },
  },
  {
    title: 'Start a section',
    lead: 'Say it at the start of a sentence, then pause.',
    cues: ['“Heading”', '“New section”'],
    example: { say: ['Notes from the call with Sam about the house.', 'Heading: the budget.', 'We agreed on four thousand.'], expect: '## The budget' },
  },
  {
    title: 'New paragraph',
    lead: 'Or just stop talking for two seconds.',
    cues: ['“New paragraph”'],
    example: { say: ['The kitchen needs work before we list it.', 'New paragraph.', 'The garden is fine as it is.'], expect: 'list it.\n\nThe garden' },
  },
  {
    title: 'Bullet points',
    lead: 'One point per sentence.',
    cues: ['“Bullet point”', '“Next point”'],
    example: { say: ['Things to check at the cabin.', 'Bullet point: the heating.', 'Next point: the water pressure.'], expect: '- The heating' },
  },
  {
    title: 'A list in one breath',
    lead: 'Three or more short things after a word like need, buy or bring.',
    cues: ['“I need eggs, milk and bread”'],
    example: { say: ['For the drive we need snacks, water, a charger and the good playlist.'], expect: 'For the drive we need:\n- snacks' },
  },
  {
    title: 'Numbers, out loud',
    lead: 'Use it when the order matters.',
    cues: ['“Number one”', '“Number two”'],
    example: { say: ['Packing order.', 'Number one: passports.', 'Number two: chargers.'], expect: '2. Chargers' },
  },
  {
    title: 'Steps in order',
    lead: 'Start with “first”. Then say second, then, or finally.',
    cues: ['“First”', '“Second”', '“Finally”'],
    example: { say: ['How to reset the router.', 'First, unplug it.', 'Second, wait thirty seconds.', 'Finally, plug it back in.'], expect: '3. Plug it back in' },
  },
  {
    title: 'To-dos',
    lead: 'Say it like you’d say it to yourself.',
    cues: ['“Remember to”', '“I need to”', '“Check box”'],
    example: { say: ['Before Saturday.', 'Remember to book the cabin.', 'Check box: call the plumber.'], expect: '- [ ] Call the plumber' },
  },
  {
    title: 'Quote someone',
    lead: 'Keeps their words apart from yours.',
    cues: ['“Quote”'],
    example: { say: ['What the landlord said at the end.', 'Quote: the deposit comes back in full.'], expect: '> The deposit comes back in full.' },
  },
  {
    title: 'Make it stand out',
    lead: 'Pause after the word so it gets a colon.',
    cues: ['“Important”', '“Key point”'],
    example: { say: ['Thoughts on the offer.', 'Important: they need an answer by Monday.'], expect: '**Important:**' },
  },
  {
    title: 'Bold and italic, anywhere',
    lead: 'Say where it starts and where it ends, mid-sentence if you like.',
    cues: ['“Bold” then “end bold”', '“Italic” then “end italic”'],
    example: { say: ['The deadline is bold Friday at noon end bold, not Monday.'], expect: '**Friday at noon**' },
  },
  {
    title: 'A dividing line',
    lead: 'Say it on its own, between two parts of a note.',
    cues: ['“Divider”', '“Horizontal line”'],
    example: { say: ['That covers the morning.', 'Divider.', 'The afternoon is free.'], expect: '\n---\n' },
  },
];

/**
 * A cue said on its own - "Bullet point." then a pause - applies to what comes
 * next. The guide says so once rather than per cue; this example is what
 * guide.test.ts checks that promise against.
 */
export const CUE_ALONE: Example = { say: ['Shopping.', 'Bullet point.', 'Oat milk.'], expect: '- Oat milk' };

/** The same shape the capture tests use: a second per phrase with a breath between. */
export function toSegments(say: readonly string[]): Segment[] {
  let at = 0;
  return say.map((text) => {
    const segment = { text, startMs: at, endMs: at + 1000 };
    at += 1300;
    return segment;
  });
}

/** An example as the capture screen would write it. */
export function renderExample(example: Example): string {
  return renderNote(toSegments(example.say)).markdown;
}
