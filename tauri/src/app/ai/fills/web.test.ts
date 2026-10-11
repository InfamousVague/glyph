import { describe, expect, it } from 'vitest';
import { askingWords, blanksIn } from '../../core/blanks.ts';
import { cannotKnow } from '../../core/fillLive.ts';
import forecast from './recorded/forecast-lisbon.json';
import geocodeLisbon from './recorded/geocode-lisbon.json';
import geocodeNowhere from './recorded/geocode-nowhere.json';
import ratesUnknown from './recorded/rates-unknown.json';
import rates from './recorded/rates-usd-jpy.json';
import wikiNothing from './recorded/wiki-nothing.json';
import wikiCup from './recorded/wiki-world-cup.json';
import wikidataLabels from './recorded/wikidata-labels.json';
import wikidataCup from './recorded/wikidata-world-cup.json';
import { bestPage, lookUp, lookupPlan, NO_SOURCE, parseForecast, parseGeocode, parseRates, parseWikidataClaims, parseWikidataLabels, parseWikiSearch, URLS, webMessage, type Fetcher } from './web.ts';

/** Answers recorded from each source once (2026-09-28), served by address: the tests never touch the network. */
function recorded(answers: Record<string, unknown>, asked: string[] = []): Fetcher {
  return async (url) => {
    asked.push(url);
    for (const [part, json] of Object.entries(answers)) if (url.includes(part)) return { status: 200, json };
    return { status: 404, json: { message: 'not found' } };
  };
}
const offline: Fetcher = async () => {
  throw new Error('offline');
};

const MONDAY = new Date(2026, 8, 28, 14, 5);
const planFor = (text: string) => {
  const blank = blanksIn(text).at(-1)!;
  const live = cannotKnow(blank, text, 2024)!;
  return lookupPlan(live.kind, askingWords(blank, text), MONDAY);
};

describe('what a lookup asks', () => {
  it('asks Open-Meteo for a named place, Frankfurter for two currencies, Wikipedia for the rest', () => {
    expect(planFor('Weather in Lisbon tomorrow: {?weather}')).toEqual({ kind: 'weather', place: 'Lisbon', days: { from: 1, to: 1 } });
    expect(planFor('100 dollars is {?how many yen} yen.')).toEqual({ kind: 'rates', amount: 100, from: 'USD', to: 'JPY' });
    expect(planFor('The 2026 World Cup was won by {?}')).toEqual({ kind: 'wiki', terms: '2026 World Cup won' });
  });

  it('says so where no public source answers, or where the place is not named', () => {
    expect(planFor('A return flight London to Tokyo costs {?price today}')).toEqual({ kind: 'none', why: NO_SOURCE });
    expect(planFor('Kinkaku-ji opens at {?opening time}')).toEqual({ kind: 'none', why: NO_SOURCE });
    expect(planFor('Will it rain today? {?}')).toMatchObject({ kind: 'none', why: expect.stringContaining('Name the place') });
  });
});

describe('the parsers, on answers recorded from each source', () => {
  it('reads Open-Meteo’s place and forecast', () => {
    const place = parseGeocode(geocodeLisbon)!;
    expect(place).toMatchObject({ name: 'Lisbon', country: 'Portugal' });
    expect(parseGeocode(geocodeNowhere)).toBeNull();
    const lines = parseForecast(forecast, place, { from: 1, to: 1 })!;
    expect(lines).toMatch(/^Lisbon, Portugal, \w+day \d+ \w+ 2026: [a-z ]+, \d+ to \d+ °C, a \d+% chance of rain, wind up to \d+ km\/h\.$/);
    expect(parseForecast(forecast, place, { from: 0, to: 0 })!.split('\n')[0]).toMatch(/^Lisbon, Portugal, now: /);
    expect(parseForecast({}, place, { from: 0, to: 0 })).toBeNull();
  });

  it('reads Frankfurter’s rate, and the app turns the amount', () => {
    expect(parseRates(rates, { amount: 100, from: 'USD', to: 'JPY' })).toBe("The European Central Bank's rate for Monday 28 September 2026: 1 USD is 156.88 JPY.\nSo 100 USD is 15,688 JPY.");
    expect(parseRates(ratesUnknown.body, { amount: 1, from: 'XXX', to: 'JPY' })).toBeNull();
  });

  it('reads Wikipedia’s pages in its order, and picks the one the words name best', () => {
    const pages = parseWikiSearch(wikiCup);
    expect(pages.map((p) => p.title)).toEqual(['2026 FIFA World Cup Group B', '2026 FIFA World Cup knockout stage', '2026 FIFA World Cup']);
    expect(bestPage(pages, '2026 World Cup won')?.item).toBe('Q5020214');
    expect(parseWikiSearch(wikiNothing)).toEqual([]);
  });

  it('reads Wikidata’s winner and dates, and its labels', () => {
    const claims = parseWikidataClaims(wikidataCup, 'Q5020214');
    expect(claims.find((c) => c.property === 'winner')?.values).toEqual([{ entity: 'Q42267' }]);
    expect(claims.find((c) => c.property === 'until')?.values).toEqual(['19 July 2026']);
    expect(parseWikidataLabels(wikidataLabels).Q42267).toBe("Spain men's national football team");
  });
});

describe('a lookup', () => {
  it('asks only for the place, then its coordinates, and gives the forecast as facts', async () => {
    const asked: string[] = [];
    const found = await lookUp({ kind: 'weather', place: 'Lisbon', days: { from: 1, to: 1 } }, recorded({ 'geocoding-api.open-meteo.com': geocodeLisbon, 'api.open-meteo.com/v1/forecast': forecast }, asked));
    expect(found).toMatchObject({ ok: true, source: 'Open-Meteo' });
    expect(asked).toEqual([URLS.geocode('Lisbon'), URLS.forecast(parseGeocode(geocodeLisbon)!, 2)]);
  });

  it('asks Frankfurter for the two codes and never the amount', async () => {
    const asked: string[] = [];
    const found = await lookUp({ kind: 'rates', amount: 100, from: 'USD', to: 'JPY' }, recorded({ 'api.frankfurter.dev': rates }, asked));
    expect(found).toMatchObject({ ok: true, source: 'Frankfurter' });
    expect(asked).toEqual(['https://api.frankfurter.dev/v1/latest?base=USD&symbols=JPY']);
    expect(asked.join(' ')).not.toContain('100');
  });

  it('asks Wikipedia for the question’s words, then Wikidata for the page they name best', async () => {
    const asked: string[] = [];
    const found = await lookUp({ kind: 'wiki', terms: '2026 World Cup won' }, recorded({ 'en.wikipedia.org': wikiCup, 'props=claims': wikidataCup, 'props=labels': wikidataLabels }, asked));
    expect(found.ok).toBe(true);
    if (!found.ok) return;
    expect(found.source).toBe('Wikipedia and Wikidata');
    expect(found.facts).toContain('concluded on July 19 with Spain winning the championship');
    expect(found.facts).toContain("Wikidata on 2026 FIFA World Cup:\n- winner: Spain men's national football team\n- when: 2026");
    expect(asked[0]).toBe(URLS.wiki('2026 World Cup won'));
  });

  it('keeps Wikipedia’s pages when Wikidata does not answer', async () => {
    const found = await lookUp({ kind: 'wiki', terms: '2026 World Cup won' }, recorded({ 'en.wikipedia.org': wikiCup }));
    expect(found).toMatchObject({ ok: true, source: 'Wikipedia' });
  });

  it('says offline when the network fails, and nothing when a source had nothing', async () => {
    expect(await lookUp({ kind: 'rates', amount: 1, from: 'USD', to: 'JPY' }, offline)).toEqual({ ok: false, why: 'offline' });
    expect(await lookUp({ kind: 'wiki', terms: 'qqq' }, recorded({ 'en.wikipedia.org': wikiNothing }))).toEqual({ ok: false, why: 'nothing', words: 'Wikipedia had nothing on this.' });
    expect(await lookUp({ kind: 'weather', place: 'Qqqzzxxy', days: { from: 0, to: 0 } }, recorded({ 'geocoding-api.open-meteo.com': geocodeNowhere }))).toMatchObject({ ok: false, why: 'nothing' });
  });
});

describe('the message for a looked-up blank', () => {
  it('puts what the source returned before the answer line', () => {
    const message = 'Today is Monday 28 September 2026.\n\nThe note:\n# Lisbon\nWeather in Lisbon tomorrow: {?1 weather}\n\nAnswer blank 1.';
    expect(webMessage(message, 'Open-Meteo', 'Lisbon, Portugal, Tuesday 29 September 2026: rain.')).toBe(
      'Today is Monday 28 September 2026.\n\nThe note:\n# Lisbon\nWeather in Lisbon tomorrow: {?1 weather}\n\nWhat Open-Meteo returned:\nLisbon, Portugal, Tuesday 29 September 2026: rain.\n\nAnswer blank 1.',
    );
  });
});
