import { describe, expect, it } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { blanksIn } from './blanks.ts';
import { workOut, type Worked } from './fillFacts.ts';
import { longDate } from './stamp.ts';

/** Monday 28 September 2026, 14:05 in London: 13:05 UTC. */
const NOW = new Date(Date.UTC(2026, 8, 28, 13, 5));
const CLOCK = { now: NOW, zone: 'Europe/London' };

/** What the app works out for the last blank of `text`, in British English. */
function worked(text: string, clock = CLOCK): Worked | null {
  const blank = blanksIn(text).at(-1)!;
  return inLocale('en-GB', () => workOut(blank, text, clock));
}
const answer = (text: string) => {
  const found = worked(text);
  return found?.kind === 'answer' ? found.answer : null;
};
const refusal = (text: string) => {
  const found = worked(text);
  return found?.kind === 'cannot' ? found.words : null;
};

describe('totals and averages of the note’s own amounts', () => {
  const cabin = '## Cabin weekend\n- Cabin deposit $200\n- Ferry $45\n- Food $80\n\nTotal so far: {?total}';

  it('adds the list above, and follows a changed number', () => {
    expect(answer(cabin)).toBe('$325');
    expect(answer(cabin.replace('$80', '$95'))).toBe('$340');
    const found = worked(cabin);
    expect(found).toMatchObject({ kind: 'answer', icon: 'calculator', working: '$200 + $45 + $80 = $325.' });
  });

  it('reads a date among the costs as a date, and says so', () => {
    const found = worked('- Cabin deposit $200\n- Ferry $45\n- Dinner on 3 Oct\n\nTotal: {?}');
    expect(found).toMatchObject({ kind: 'answer', answer: '$245', working: '$200 + $45 = $245. Dinner on 3 Oct has no amount.' });
  });

  it('is no sum without a total word in the right place, or without two amounts', () => {
    expect(worked('- Japan 2019\n- Peru 2022\n\nCountries so far: {?}')).toBeNull();
    expect(worked('- Japan $200\n- Peru $300\n\nThe total came as a surprise. Countries so far: {?}')).toBeNull();
    expect(worked('What’s the average lifespan of a cat? {?}')).toBeNull();
  });

  it('refuses two kinds of amount and a line with two', () => {
    expect(refusal('- Cabin $200\n- Ferry £45\n\nTotal: {?}')).toBe('The app adds these up itself, and $200 and £45 are different money.');
    expect(refusal('- Cabin 200\n- Ferry $45\n\nTotal: {?}')).toBe('The app adds these up itself, and 200 and $45 are not the same kind of number.');
    expect(refusal('- Cabin $200\n- Ferry $45, $30 back\n\nTotal: {?}')).toBe('The app adds these up itself, and one line has two amounts: Ferry $45, $30 back. Keep one to a line.');
  });

  it('averages, keeps a unit or a code, and passes a numbered list’s own numbers', () => {
    expect(answer('- $200\n- $45\n- $80\n\nThe average: {?}')).toBe('$108.33');
    expect(answer('1. Flour 2 kg\n2. Sugar 1.5 kg\n\nTotal: {?}')).toBe('3.5 kg');
    expect(answer('- Hotel 200 EUR\n- Train 45 EUR\n\nIn all: {?}')).toBe('245 EUR');
  });

  it('adds the column above a Total row', () => {
    expect(answer('| Item | Cost |\n| --- | --- |\n| Cabin | $200 |\n| Ferry | $45 |\n| Total | {?} |')).toBe('$245');
  });
});

describe('counts', () => {
  it('counts the note’s to-dos, and the list above', () => {
    const note = '- [x] Found the leak\n- [ ] Buy a washer\n- [ ] Fit it\n- [ ] Test\n\nTo-dos left: {?}';
    expect(answer(note)).toBe('3 left');
    expect(answer(note.replace('To-dos left', 'Tasks done'))).toBe('1 done');
    expect(answer('- Passport\n- Plug adapter\n- Rail pass\nItems on this list: {?}')).toBe('3 items');
  });

  it('leaves a question about items that is not a count', () => {
    expect(worked('How many items can I take in hand luggage? {?}')).toBeNull();
  });
});

describe('days and dates, on Monday 28 September 2026', () => {
  it('counts days until and since, today counting as nought', () => {
    expect(answer('Days until Christmas: {?}')).toBe('88 days');
    expect(answer('Days since Christmas: {?}')).toBe('277 days');
    expect(answer('How many days until Christmas? {?}')).toBe('88 days');
    expect(answer('Days until 28 September: {?}')).toBe('0 days');
    expect(answer('Weeks until Christmas: {?}')).toBe('12 weeks and 4 days');
  });

  it('shows its working in the person’s own form, and changes each day', () => {
    const found = worked('Days until Christmas: {?}');
    expect(found).toMatchObject({ icon: 'calendar', changes: 'day' });
    const today = inLocale('en-GB', () => longDate(new Date(2026, 8, 28)));
    const christmas = inLocale('en-GB', () => longDate(new Date(2026, 11, 25)));
    expect(found?.kind === 'answer' && found.working).toBe(`From today, ${today}, to ${christmas}. It changes each day.`);
  });

  it('names a weekday, and a date some weeks on', () => {
    expect(answer('Sam’s birthday, 14 November, is a {?weekday}.')).toBe('Saturday');
    expect(answer('3 weeks from today: {?}')).toBe(inLocale('en-GB', () => longDate(new Date(2026, 9, 19))));
  });

  it('refuses a slashed date, a day that moves, and days with no date', () => {
    expect(refusal('Days until 05/11: {?}')).toBe('05/11 is a different day in London and in New York. Write it as 11 May or 5 November.');
    expect(refusal('Days until Easter: {?}')).toBe('Easter moves each year, and the app does not know when it falls.');
    expect(refusal('How many days until we fly? {?}')).toBe('The app counts days itself, and there is no date here to count to.');
    expect(worked('Days until Easter: {?}')).toMatchObject({ kind: 'cannot', icon: 'calendar' });
  });

  it('leaves a question with no day word and no date, and a count that is stated', () => {
    expect(worked('How long until the bread is proven? {?}')).toBeNull();
    expect(worked('I have 3 days until my exam, so revise {?what}')).toBeNull();
    expect(worked('I fly out in two days, so pack {?what}')).toBeNull();
  });
});

describe('what the app leaves to the model', () => {
  it('works none of the model’s scenarios out, Matt’s Tokyo first', () => {
    for (const text of [
      '# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}',
      'The capital of Australia is {?}.',
      'Sam said she would bring the charger and the dog food. I am booking the ferry.\n\nWho brings the charger? {?}',
      'Priya: export bug fixed, in review, lands Tuesday.\n\nIn one line: {?summary}',
      '# Kitchen tap\n- [x] Found the leak under the sink\n- [ ] {?the next step}',
      '## Japan packing\n- Passport\n- Plug adapter\n- {?three more things}',
      '| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |',
      '| Book | Author | Year |\n| --- | --- | --- |\n| The Remains of the Day | {?} | {?} |',
      'Petrichor: {?what it means}',
      '1 cup of plain flour is about {?grams} grams.',
      '# {?}\n\nBook the cabin for the second week of October.',
      'The 2022 World Cup was won by {?}',
      'Opening line, friendlier: {?a friendlier way to say: fix the boiler now}',
      '{?how long to boil an egg}',
      '# Trip to {?capital of Japan}',
      'What’s the average lifespan of a cat? {?}',
      'Which day of our trip is best for the temple? {?}',
    ]) {
      expect(worked(text), text).toBeNull();
    }
  });
});

describe('units', () => {
  it('converts a temperature, a distance and a weight', () => {
    expect(answer('180 °C in Fahrenheit is {?°F}.')).toBe('356 °F');
    expect(worked('180 °C in Fahrenheit is {?°F}.')).toMatchObject({ working: '180 × 9 ÷ 5 + 32 = 356.' });
    expect(answer('10 km is {?} miles.')).toBe('6.2 mi');
    expect(answer('How far is 10 km in miles? {?}')).toBe('6.2 mi');
    expect(answer('2 lb in kg: {?}')).toBe('0.9 kg');
  });

  it('passes a cup to grams on, since that depends on the thing', () => {
    expect(worked('1 cup of plain flour is about {?grams} grams.')).toBeNull();
    expect(worked('A tablespoon of butter is about {?grams} grams.')).toBeNull();
  });
});

describe('the time', () => {
  it('says the time in a city now, with its weekday, changing each minute', () => {
    expect(answer('What time is it in Tokyo now? {?}')).toBe('22:05 Monday');
    expect(worked('What time is it in Tokyo now? {?}')).toMatchObject({ icon: 'globe', changes: 'minute', working: 'Tokyo is 8 hours ahead of London today. It changes each minute.' });
  });

  it('gives the difference between two cities across a month, with the day the clocks change', () => {
    expect(answer('Tokyo is {?how many hours} ahead of London in October.')).toBe('8 hours, 9 from 25 October');
    expect(answer('Tokyo is {?how many hours} ahead of London in July.')).toBe('8 hours');
    expect(answer('Tokyo is {?how many hours} ahead of London in December.')).toBe('9 hours');
  });

  it('turns a time in one city into another’s', () => {
    expect(answer('14:00 in London is {?} in Tokyo')).toBe('22:00');
  });

  it('says so for a city it does not know', () => {
    expect(refusal('What time is it in Ulaanbaatar? {?}')).toBe('The app knows the time in about sixty cities, and Ulaanbaatar is not one.');
  });
});
