import { describe, expect, it } from 'vitest';
import { askingWords, blanksIn } from './blanks.ts';
import { cannotKnow, dayAsked, moneyAsked, placeAsked, searchWords } from './fillLive.ts';

/** The screen over the last blank of `text`, for a model taken to know up to 2024. */
const live = (text: string, learntUntil = 2024) => cannotKnow(blanksIn(text).at(-1)!, text, learntUntil)?.kind ?? null;
const asking = (text: string) => askingWords(blanksIn(text).at(-1)!, text);

describe('what the model can’t know offline', () => {
  it('refuses the scenarios that need something live or newer', () => {
    expect(live('Weather in Lisbon today: {?weather}')).toBe('weather');
    // A place named is enough for the weather, with no word for now: "weather in Tokyo" means now, and went to the
    // model before (Matt: it never fills on mobile).
    expect(live('Weather in Lisbon: {?}')).toBe('weather');
    expect(live('The weather in Tokyo is {?}')).toBe('weather');
    expect(live('The forecast for New York: {?}')).toBe('weather');
    expect(live('A return flight London to Tokyo costs {?price today}')).toBe('prices');
    // Found by the shots: a fare asked with "cheapest" went to the model, which could only say it did not know.
    expect(live('Cheapest flight to Lisbon today: {?}')).toBe('prices');
    expect(live('The cheapest hotel in Porto tomorrow night is {?}')).toBe('prices');
    expect(live('The 2026 World Cup was won by {?}')).toBe('after');
    expect(live('100 dollars is {?how many yen} yen.')).toBe('money');
    expect(live('Kinkaku-ji opens at {?opening time}')).toBe('hours');
    expect(live('The newest Pixel is the {?}')).toBe('newest');
    expect(live('Q: Who won the 2026 World Cup?\nA: {?}')).toBe('after');
    expect(live('Bitcoin is worth {?} now.')).toBe('markets');
    expect(live('Next train to Brighton: {?}')).toBe('transport');
    expect(live('Who won last night? {?}')).toBe('news');
  });

  it('lets through what stays true from month to month', () => {
    for (const text of [
      'Flights are cheapest to Tokyo on {?what day / time?}',
      'The capital of Australia is {?}.',
      'Priya: export bug fixed, lands today.\n\nIn one line: {?summary}',
      '| Book | Author |\n| --- | --- |\n| The Remains of the Day | {?} |',
      'Petrichor: {?what it means}',
      '1 cup of plain flour is about {?grams} grams.',
      'The 2022 World Cup was won by {?}',
      'Opening line, friendlier: {?a friendlier way to say: fix the boiler now}',
      '{?how long to boil an egg}',
      'What’s the average lifespan of a cat? {?}',
      'If it rains tomorrow what do we do? {?}',
      'The latest check-out time is {?}',
      'Our 2026 trip: flights are cheapest on {?}',
      // Past weather is a thing the model may know; only "now" needs the live look-up.
      'The weather in Tokyo back in 1990 was {?}',
      'What was the weather in Lisbon on our wedding day? {?}',
    ]) {
      expect(live(text), text).toBeNull();
    }
  });

  it('keeps the horizon a fixed year per model, never the clock', () => {
    expect(live('The 2022 World Cup was won by {?}', 2024)).toBeNull();
    expect(live('The 2025 World Cup was won by {?}', 2024)).toBe('after');
    expect(live('The 2026 World Cup was won by {?}', 2024)).toBe('after');
    expect(live('The 2026 World Cup was won by {?}', 2026)).toBeNull();
  });

  it('never reads “who won” as a currency', () => {
    expect(live('Who won the 2022 World Cup? {?}')).toBeNull();
  });
});

describe('what a lookup would ask', () => {
  it('reads the amount and the two currencies', () => {
    expect(moneyAsked(asking('100 dollars is {?how many yen} yen.'))).toEqual({ amount: 100, from: 'USD', to: 'JPY' });
    expect(moneyAsked(asking('€250 in pounds: {?}'))).toEqual({ amount: 250, from: 'EUR', to: 'GBP' });
    expect(moneyAsked(asking('1,000 USD is {?} EUR'))).toEqual({ amount: 1000, from: 'USD', to: 'EUR' });
  });

  it('reads the place and the day for the weather', () => {
    expect(placeAsked(asking('Weather in Lisbon today: {?weather}'))).toBe('Lisbon');
    expect(placeAsked(asking('The forecast for New York tomorrow: {?}'))).toBe('New York');
    expect(placeAsked(asking('Will it rain today? {?}'))).toBeNull();
    const monday = new Date(2026, 8, 28);
    expect(dayAsked(asking('Weather in Lisbon tomorrow: {?}'), monday)).toEqual({ from: 1, to: 1 });
    expect(dayAsked(asking('Weather in Lisbon this weekend: {?}'), monday)).toEqual({ from: 5, to: 6 });
  });

  it('searches for the question’s own words, the small ones left out', () => {
    expect(searchWords(asking('The 2026 World Cup was won by {?}'))).toBe('2026 World Cup won');
    expect(searchWords(asking('Q: Who won the 2026 World Cup?\nA: {?}'))).toBe('won 2026 World Cup');
    // "newest" is kept: a search for plain "Pixel" found the picture element (the review of §145).
    expect(searchWords(asking('The newest Pixel is the {?}'))).toBe('newest Pixel');
  });

  it('sends the braces’ own question alone, and never the rest of the sentence or the one before', () => {
    expect(searchWords(asking('Sarah Jones owes me £450 for rent. {?who won the 2026 World Cup}'))).toBe('won 2026 World Cup');
    expect(searchWords(asking('My HIV test results came back and Dr Patel said to ask who won the 2026 World Cup {?}'))).toBe('won 2026 World Cup');
    expect(searchWords(asking('Told Dr Patel about my knee, and he asked who won the 2026 World Cup {?}'))).toBe('won 2026 World Cup');
  });

  it('takes a place only from the question or its own clause, never a person or a language', () => {
    expect(placeAsked(asking('Weather for Sarah’s wedding in Lisbon tomorrow: {?}'))).toBe('Lisbon');
    expect(placeAsked(asking('Q: Will it rain at Dr Patel’s clinic tomorrow? A: {?}'))).toBeNull();
    expect(placeAsked(asking('- Will it rain tomorrow? {?in Italian}'))).toBeNull();
  });
});
