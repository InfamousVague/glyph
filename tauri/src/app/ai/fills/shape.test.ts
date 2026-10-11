import { describe, expect, it } from 'vitest';
import { blanksIn } from '../../core/blanks.ts';
import { budgetOf, checkShape, hintFor, shapeOf, type ShapeInfo } from './shape.ts';

/** The shape of the last blank in `text`. */
const shape = (text: string) => shapeOf(blanksIn(text).at(-1)!, text);
/** The check on the last blank in `text` with these answer lines. */
const check = (text: string, lines: string[], truncated = false) => {
  const blank = blanksIn(text).at(-1)!;
  return checkShape(lines, blank, shapeOf(blank, text), text, truncated);
};
const words = (text: string, lines: string[]) => {
  const checked = check(text, lines);
  return checked.ok ? checked.text : checked.why;
};

const TWENTY = 'Book the cabin for the second week of October. Ferry once Sam confirms dates with her brother. Deposit $200 by Friday.';

describe('the shape of a blank', () => {
  it('reads a title only from a whole first line that asks for one', () => {
    expect(shape(`# {?}\n\n${TWENTY}`).shape).toBe('title');
    expect(shape(`# {?a title}\n\n${TWENTY}`).shape).toBe('title');
    expect(shape('# {?}\n\nToo few words.').tooShort).toBe(true);
    expect(shape('{?how long to boil an egg}').shape).toBe('line');
    expect(shape('# {?who wrote Dune}').shape).toBe('line');
    expect(shape('# Trip to {?capital of Japan}')).toMatchObject({ shape: 'phrase', titleLine: true });
  });

  it('reads a language from the question or a cell’s header, and not from “in which year”', () => {
    expect(shape('- Good morning: {?in Japanese}')).toMatchObject({ shape: 'language', language: { name: 'Japanese' } });
    expect(shape('| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |')).toMatchObject({ shape: 'language', cell: { header: 'In Japanese', row: 'Thank you' } });
    expect(shape('It was finished {?in which year}').shape).toBe('phrase');
    expect(shape('- Two coffees, please: {?in Portuguese}').language?.script).toBeNull();
  });

  it('counts items: one for a to-do, three otherwise, or the number asked', () => {
    expect(shape('- [x] Found the leak\n- [ ] {?the next step}')).toMatchObject({ shape: 'items', count: 1 });
    expect(shape('- Passport\n- {?more}')).toMatchObject({ shape: 'items', count: 3 });
    expect(shape('- Passport\n- {?three more things}')).toMatchObject({ shape: 'items', count: 3 });
    expect(shape('- Passport\n- {?two more}')).toMatchObject({ shape: 'items', count: 2 });
    expect(shape('1. Passport\n2. {?a few}')).toMatchObject({ shape: 'items', count: 3 });
  });

  it('reads a cell, a summary, a number, a line and a phrase', () => {
    expect(shape('| Book | Author |\n| --- | --- |\n| The Remains of the Day | {?} |')).toMatchObject({ shape: 'cell', cell: { header: 'Author', row: 'The Remains of the Day' } });
    expect(shape('Notes.\n\nIn one line: {?summary}').shape).toBe('summary');
    expect(shape('Words.\n\n1 cup of plain flour is about {?grams} grams.').shape).toBe('number');
    expect(shape('Words.\n\nA trip of {?how many} days.').shape).toBe('number');
    expect(shape('Words.\n\n{?something to add}').shape).toBe('line');
    expect(shape('Words.\n\nFlights are cheapest on {?which day}').shape).toBe('phrase');
  });

  it('gives each shape its hint and its budget', () => {
    const items = shape('- Passport\n- {?three more things}');
    expect(hintFor(1, items)).toBe('Blanks 1 to 3 are whole items of the list they are in, each one new.');
    expect(hintFor(4, shape('- [ ] Found it\n- [ ] {?next}'))).toBe('Blank 4 is a whole item of the list it is in.');
    expect(budgetOf(items)).toBe(99);
    expect(hintFor(2, shape('Words here.\n\nThe capital is {?}.'))).toBeNull();
    const cell: ShapeInfo = shape('| Book | Year |\n| --- | --- |\n| The Remains of the Day | {?} |');
    expect(hintFor(3, cell)).toBe('Blank 3 is the Year of The Remains of the Day.');
  });
});

describe('the check before anything is written', () => {
  it('reads UNKNOWN and its kin as not known, and an empty answer as none', () => {
    expect(words('Words.\n\nThe newest Pixel is the {?}', ['UNKNOWN'])).toBe('unknown');
    expect(words('Words.\n\nThe newest Pixel is the {?}', ['I don’t know'])).toBe('unknown');
    expect(words('Words.\n\nThe capital is {?which city}', ['which city'])).toBe('none');
    expect(words('Words.\n\nThe capital is {?which city}', [])).toBe('none');
  });

  it('takes an echo of the line off', () => {
    expect(words('Words.\n\nThe newest Pixel is the {?}', ['the newest Pixel is the Pixel 10'])).toBe('Pixel 10');
  });

  it('tidies quotes, bold, a list mark and a full stop the sentence already has', () => {
    expect(words('Words.\n\nThe capital of Australia is {?}.', ['"Canberra."'])).toBe('Canberra');
    expect(words('Words.\n\nThe capital of Australia is {?}.', ['**Canberra**'])).toBe('Canberra');
    expect(words('Words.\n\nFlights are cheapest on {?which day} in winter', ['- Tuesday.'])).toBe('Tuesday');
  });

  it('refuses a nine-word title and one naming what the note lacks, and passes one of its own words', () => {
    const note = `# {?}\n\n${TWENTY}`;
    expect(words(note, ['Book the cabin for the second week of October'])).toBe('didnt-fit');
    expect(words(note, ['Cabin booking'])).toBe('Cabin booking');
    expect(words(note, ['Cabin trip to Lisbon'])).toBe('didnt-fit');
    expect(words(note, ['# Cabin booking.'])).toBe('Cabin booking');
  });

  it('refuses a summary naming someone the note lacks', () => {
    const note = '# Standup\n\nPriya: export bug fixed, lands Tuesday. Tom: blocked on keys.\n\nIn one line: {?summary}';
    expect(words(note, ['Priya fixed the export bug for Tuesday and Tom is blocked on keys.'])).toMatch(/^Priya fixed/);
    expect(words(note, ['Priya and Sanjay fixed the export bug.'])).toBe('didnt-fit');
  });

  it('keeps a translation’s script, and takes a Latin one’s brackets off', () => {
    expect(words('- Thank you: {?in Japanese}', ['Arigato gozaimasu (a-ree-ga-toh go-zah-im-as)'])).toBe('didnt-fit');
    expect(words('- Thank you: {?in Japanese}', ['ありがとう (arigatō)'])).toBe('ありがとう (arigatō)');
    expect(words('- Two coffees, please: {?in Portuguese}', ['Duas cafés, por favor (duas cafés, por favor)'])).toBe('Duas cafés, por favor');
  });

  it('makes a pipe a slash in a table line', () => {
    expect(words('| Film | Director |\n| --- | --- |\n| Heat | {?} |', ['Michael Mann | director'])).toBe('Michael Mann / director');
  });

  it('holds each shape to its own caps, and a cut answer to none', () => {
    const phrase = 'Words.\n\nFlights are cheapest on {?which day}';
    expect(words(phrase, ['one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone'])).toBe('didnt-fit');
    const line = 'Words.\n\n{?something to say}';
    const thirtyFive = Array.from({ length: 35 }, (_, i) => `w${i}`).join(' ');
    expect(words(line, [thirtyFive])).toBe(thirtyFive);
    expect(check(phrase, ['Tuesday or Wed'], true)).toEqual({ ok: false, why: 'didnt-fit' });
    expect(words('Words.\n\nA cup is about {?grams} grams.', ['about a cup'])).toBe('didnt-fit');
    expect(words('Words.\n\nA cup is about {?grams} grams.', ['120 grams'])).toBe('120');
  });

  it('relets items, drops what the list has, and keeps the count', () => {
    const note = '## Japan packing\n- Passport\n- Plug adapter\n- {?three more things}';
    const checked = check(note, ['- Rail pass', 'Passport', '3. Comfortable walking shoes', 'Cash in yen', 'An umbrella']);
    expect(checked).toEqual({ ok: true, text: 'Rail pass', items: ['Rail pass', 'Comfortable walking shoes', 'Cash in yen'] });
    expect(check(note, ['Passport', 'Plug adapter'])).toEqual({ ok: false, why: 'didnt-fit' });
    expect(check(note, ['Rail pass', 'Walking sh'], true)).toEqual({ ok: true, text: 'Rail pass', items: ['Rail pass'] });
  });
});
