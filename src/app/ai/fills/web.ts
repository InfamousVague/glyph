import type { Asking } from '../../core/blanks.ts';
import { dayAsked, type LiveKind, moneyAsked, placeAsked, searchWords } from '../../core/fillLive.ts';
import { modelDay } from './message.ts';
import { isMacApp } from '../../core/platform.ts';

/**
 * Live blanks, looked up by the phone itself (docs/DESIGN.md §145). Matt, asked where an answer that needs live facts
 * comes from once the phone is online: "Phone looks it up, all local". So there is no Ghost.md server and no account
 * in it: the page asks a public source that needs no key and lets a page call it (it answers a browser's CORS check with
 * `*`, checked on 2026-09-28), and the model on the phone writes the answer from what came back, marked in the file as
 * from the web with the source named.
 *
 * - **Open-Meteo** for the weather: its geocoder for the place named, then its forecast for those coordinates.
 * - **Frankfurter** for exchange rates: the European Central Bank's reference rates. The sum is the app's own.
 * - **Wikipedia** for news, results, the newest of anything and events after a model's training: its search, with the
 *   first sentences of the pages it finds, and **Wikidata** for the facts of the page the question names best (a
 *   tournament's winner, a release's date).
 *
 * No general web search lets a page call it with no key: DuckDuckGo's result pages refuse a script (403), and its
 * instant-answer API, which does allow one, answers only from Wikipedia's topics (nothing for "newest Pixel phone" or
 * "cheapest day to fly to Tokyo", checked 2026-09-28). So Wikipedia's own search is the search source. Prices, fares,
 * markets, opening hours and transport have no public source that allows it, and say so; Ask the model anyway stays.
 *
 * Only what the question needs leaves the phone, and only to the one source asked: a place's name and then its
 * coordinates, two currency codes (never the amount), or the question's own words. Never the note. The parsers are pure
 * and tested on answers recorded once (src/app/ai/fills/recorded), never the network.
 */

/** What a lookup asks, decided from the words alone. */
export type LookupPlan =
  | { kind: 'weather'; place: string; days: { from: number; to: number } }
  | { kind: 'rates'; amount: number; from: string; to: string }
  | { kind: 'wiki'; terms: string }
  | { kind: 'none'; why: string };

/** The sentence for a live blank no public source can answer. */
export const NO_SOURCE = `No public source ${isMacApp ? 'this Mac' : 'the phone'} can ask answers this.`;

/** What a lookup for a live blank would ask, or why there is none. */
export function lookupPlan(kind: LiveKind, asking: Asking, now: Date): LookupPlan {
  switch (kind) {
    case 'weather': {
      const place = placeAsked(asking);
      return place ? { kind: 'weather', place, days: dayAsked(asking, now) } : { kind: 'none', why: `Name the place, as in “Weather in Lisbon today”, and ${isMacApp ? 'this Mac' : 'the phone'} can look it up.` };
    }
    case 'money': {
      const money = moneyAsked(asking);
      return money ? { kind: 'rates', ...money } : { kind: 'none', why: 'Name both currencies and an amount, as in “100 dollars is {?how many yen} yen”.' };
    }
    case 'newest':
    case 'after':
    case 'news': {
      const terms = searchWords(asking);
      return terms ? { kind: 'wiki', terms } : { kind: 'none', why: NO_SOURCE };
    }
    default:
      return { kind: 'none', why: NO_SOURCE };
  }
}

/** The source a plan asks, as the answer's bracket names it. */
export function sourceName(plan: LookupPlan): string | null {
  if (plan.kind === 'weather') return 'Open-Meteo';
  if (plan.kind === 'rates') return 'Frankfurter';
  if (plan.kind === 'wiki') return 'Wikipedia';
  return null;
}

// ---- the parsers --------------------------------------------------------------------------------------------------

export interface Place {
  name: string;
  country: string;
  latitude: number;
  longitude: number;
}

/** Open-Meteo's geocoder, its first place; null for none. */
export function parseGeocode(json: unknown): Place | null {
  const first = (json as { results?: { name?: string; country?: string; latitude?: number; longitude?: number }[] })?.results?.[0];
  if (!first || typeof first.latitude !== 'number' || typeof first.longitude !== 'number') return null;
  return { name: first.name ?? '', country: first.country ?? '', latitude: first.latitude, longitude: first.longitude };
}

/** The WMO weather codes Open-Meteo reports, in words. */
const WEATHER_CODES: Record<number, string> = {
  0: 'clear sky',
  1: 'mainly clear',
  2: 'partly cloudy',
  3: 'overcast',
  45: 'fog',
  48: 'freezing fog',
  51: 'light drizzle',
  53: 'drizzle',
  55: 'heavy drizzle',
  56: 'freezing drizzle',
  57: 'freezing drizzle',
  61: 'light rain',
  63: 'rain',
  65: 'heavy rain',
  66: 'freezing rain',
  67: 'freezing rain',
  71: 'light snow',
  73: 'snow',
  75: 'heavy snow',
  77: 'snow grains',
  80: 'rain showers',
  81: 'rain showers',
  82: 'heavy rain showers',
  85: 'snow showers',
  86: 'heavy snow showers',
  95: 'thunderstorms',
  96: 'thunderstorms with hail',
  99: 'thunderstorms with hail',
};

interface Forecast {
  current?: { time?: string; temperature_2m?: number; weather_code?: number; wind_speed_10m?: number };
  daily?: { time?: string[]; weather_code?: number[]; temperature_2m_max?: number[]; temperature_2m_min?: number[]; precipitation_probability_max?: number[]; wind_speed_10m_max?: number[] };
}

const round = (n: number) => Math.round(n);

/** Open-Meteo's forecast for the days asked, as the lines the model reads; null when it has none of them. */
export function parseForecast(json: unknown, place: Place, days: { from: number; to: number }): string | null {
  const forecast = json as Forecast;
  const daily = forecast?.daily;
  if (!daily?.time?.length) return null;
  const lines: string[] = [];
  const where = place.country ? `${place.name}, ${place.country}` : place.name;
  if (days.from === 0 && forecast.current && typeof forecast.current.temperature_2m === 'number') {
    const now = forecast.current;
    lines.push(`${where}, now: ${WEATHER_CODES[now.weather_code ?? -1] ?? 'weather unknown'}, ${round(now.temperature_2m!)} °C, wind ${round(now.wind_speed_10m ?? 0)} km/h.`);
  }
  for (let d = days.from; d <= days.to && d < daily.time.length; d += 1) {
    const [y, m, day] = daily.time[d]!.split('-').map(Number);
    const date = new Date(y!, m! - 1, day!, 12);
    const words = WEATHER_CODES[daily.weather_code?.[d] ?? -1] ?? 'weather unknown';
    const low = daily.temperature_2m_min?.[d];
    const high = daily.temperature_2m_max?.[d];
    const rain = daily.precipitation_probability_max?.[d];
    const wind = daily.wind_speed_10m_max?.[d];
    const parts = [words];
    if (typeof low === 'number' && typeof high === 'number') parts.push(`${round(low)} to ${round(high)} °C`);
    if (typeof rain === 'number') parts.push(`a ${rain}% chance of rain`);
    if (typeof wind === 'number') parts.push(`wind up to ${round(wind)} km/h`);
    lines.push(`${where}, ${modelDay(date)}: ${parts.join(', ')}.`);
  }
  return lines.length ? lines.join('\n') : null;
}

/** A figure as a person reads it: grouped, at most two decimals. */
const figure = (n: number) => n.toLocaleString('en-GB', { maximumFractionDigits: n < 10 ? 4 : 2 });

/** Frankfurter's rate, and the amount turned by the app, as the lines the model reads; null for a pair it does not know. */
export function parseRates(json: unknown, plan: { amount: number; from: string; to: string }): string | null {
  const rates = json as { date?: string; base?: string; rates?: Record<string, number> };
  const rate = rates?.rates?.[plan.to];
  if (typeof rate !== 'number' || !rates.date) return null;
  const [y, m, d] = rates.date.split('-').map(Number);
  const day = modelDay(new Date(y!, m! - 1, d!, 12));
  return `The European Central Bank's rate for ${day}: 1 ${plan.from} is ${figure(rate)} ${plan.to}.\nSo ${figure(plan.amount)} ${plan.from} is ${figure(Math.round(plan.amount * rate * 100) / 100)} ${plan.to}.`;
}

/**
 * The weather's answer, written by the app from the forecast: "Rain showers, 19 to 25 °C", or one such part a day for a
 * weekend. The model never writes it, so nothing it says can be marked as Open-Meteo's without being Open-Meteo's.
 */
export function forecastAnswer(json: unknown, days: { from: number; to: number }): string | null {
  const daily = (json as Forecast)?.daily;
  if (!daily?.time?.length) return null;
  const parts: string[] = [];
  for (let d = days.from; d <= days.to && d < daily.time.length; d += 1) {
    const words = WEATHER_CODES[daily.weather_code?.[d] ?? -1];
    if (!words) continue;
    const low = daily.temperature_2m_min?.[d];
    const high = daily.temperature_2m_max?.[d];
    const temps = typeof low === 'number' && typeof high === 'number' ? `, ${round(low)} to ${round(high)} °C` : '';
    const text = `${words}${temps}`;
    if (days.to > days.from) {
      const [y, m, day] = daily.time[d]!.split('-').map(Number);
      const weekday = new Date(y!, m! - 1, day!, 12).toLocaleDateString('en-GB', { weekday: 'long' });
      parts.push(`${weekday} ${text}`);
    } else parts.push(text);
  }
  if (!parts.length) return null;
  const joined = parts.join(', then ');
  return joined.charAt(0).toUpperCase() + joined.slice(1);
}

/** The exchange's answer, worked out by the app from the ECB's rate: "67.06 USD". */
export function ratesAnswer(json: unknown, plan: { amount: number; to: string }): string | null {
  const rate = (json as { rates?: Record<string, number> })?.rates?.[plan.to];
  if (typeof rate !== 'number') return null;
  return `${figure(Math.round(plan.amount * rate * 100) / 100)} ${plan.to}`;
}

/**
 * Whether a model's answer stands in what a source returned: every number in it, and every content word, is in the
 * facts. Measured before this: the 2B landed seven of eight answers wrong "from Wikipedia" ("newest" for the newest
 * Pixel, a 2024 winner for 2025), each marked as the web's. An answer the facts do not hold is not the web's, and
 * does not land as it.
 */
export function standsIn(answer: string, facts: string): boolean {
  const fold = (t: string) => t.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').replace(/(\d),(\d)/g, '$1$2');
  const have = fold(facts);
  const numbers = fold(answer).match(/\d+(?:\.\d+)?/g) ?? [];
  if (numbers.some((n) => !have.includes(n))) return false;
  const words = (fold(answer).match(/[\p{L}]+/gu) ?? []).filter((w) => w.length >= 3 && !SMALL.has(w));
  if (!words.length && !numbers.length) return false;
  const haveWords = new Set((have.match(/[\p{L}]+/gu) ?? []).map((w) => w.replace(/s$/, '')));
  return words.every((w) => haveWords.has(w.replace(/s$/, '')));
}

const SMALL = new Set('the and for with from that this was were are its his her their has had have been into over than then about after before'.split(' '));

export interface WikiPage {
  title: string;
  extract: string;
  item: string | null;
}

/** Wikipedia's search, the pages in its order with the first sentences of each; empty for none. */
export function parseWikiSearch(json: unknown): WikiPage[] {
  const pages = (json as { query?: { pages?: { index?: number; title?: string; extract?: string; pageprops?: { wikibase_item?: string } }[] } })?.query?.pages ?? [];
  return [...pages]
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
    .filter((p) => p.title && p.extract?.trim())
    .map((p) => ({ title: p.title!, extract: p.extract!.replace(/\s+/g, ' ').trim(), item: p.pageprops?.wikibase_item ?? null }));
}

/**
 * The page the search words name best: most of them in its title, then the fewest other words in it, then the search's
 * own order. "2026 World Cup won" names "2026 FIFA World Cup" before "2026 FIFA World Cup Group B".
 */
export function bestPage(pages: readonly WikiPage[], terms: string): WikiPage | null {
  const words = terms.toLowerCase().split(/\s+/).filter(Boolean);
  let best: WikiPage | null = null;
  let score = -1;
  let extra = Infinity;
  for (const page of pages) {
    const title = page.title.toLowerCase();
    const here = words.filter((w) => title.includes(w)).length;
    const others = title.split(/\s+/).length - here;
    if (here > score || (here === score && others < extra)) {
      best = page;
      score = here;
      extra = others;
    }
  }
  return best;
}

/** The Wikidata properties worth a live answer, in words. */
const PROPERTIES: Record<string, string> = {
  P1346: 'winner',
  P585: 'when',
  P580: 'from',
  P582: 'until',
  P577: 'published',
  P348: 'version',
  P1082: 'population',
  P6: 'head of government',
  P35: 'head of state',
  P169: 'chief executive',
  P156: 'followed by',
  P155: 'follows',
};

interface Snak {
  datavalue?: { type?: string; value?: unknown };
}

/** A Wikidata date in words, as precise as it is: a year, a month, or a day. */
function wikidataDate(value: { time?: string; precision?: number }): string | null {
  const found = /^\+?(\d{4})-(\d{2})-(\d{2})/.exec(value.time ?? '');
  if (!found) return null;
  const [y, m, d] = [Number(found[1]), Number(found[2]), Number(found[3])];
  if ((value.precision ?? 11) <= 9 || m === 0) return String(y);
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  if ((value.precision ?? 11) === 10 || d === 0) return `${MONTHS[m - 1]} ${y}`;
  return `${d} ${MONTHS[m - 1]} ${y}`;
}

/** An entity's claims worth reading, each as its property's word and its values, the entities among them by id. */
export function parseWikidataClaims(json: unknown, id: string): { property: string; values: (string | { entity: string })[] }[] {
  const claims = (json as { entities?: Record<string, { claims?: Record<string, { mainsnak?: Snak; rank?: string }[]> }> })?.entities?.[id]?.claims ?? {};
  const out: { property: string; values: (string | { entity: string })[] }[] = [];
  for (const [key, word] of Object.entries(PROPERTIES)) {
    const list = claims[key];
    if (!list?.length) continue;
    const preferred = list.filter((c) => c.rank === 'preferred');
    const values: (string | { entity: string })[] = [];
    for (const claim of (preferred.length ? preferred : list.filter((c) => c.rank !== 'deprecated')).slice(0, 3)) {
      const value = claim.mainsnak?.datavalue;
      if (!value) continue;
      if (value.type === 'wikibase-entityid') values.push({ entity: (value.value as { id: string }).id });
      else if (value.type === 'time') {
        const date = wikidataDate(value.value as { time?: string; precision?: number });
        if (date) values.push(date);
      } else if (value.type === 'quantity') values.push(figure(Number((value.value as { amount: string }).amount)));
      else if (value.type === 'string') values.push(String(value.value));
    }
    if (values.length) out.push({ property: word, values });
  }
  return out;
}

/** Wikidata's labels, by id. */
export function parseWikidataLabels(json: unknown): Record<string, string> {
  const entities = (json as { entities?: Record<string, { labels?: { en?: { value?: string } } }> })?.entities ?? {};
  return Object.fromEntries(Object.entries(entities).flatMap(([id, e]) => (e.labels?.en?.value ? [[id, e.labels.en.value]] : [])));
}

/** What Wikipedia and Wikidata returned, as the lines the model reads. */
export function wikiFacts(pages: readonly WikiPage[], facts: { title: string; claims: { property: string; values: (string | { entity: string })[] }[]; labels: Record<string, string> } | null): string {
  const lines = pages.map((p) => `${p.title}: ${p.extract}`);
  if (facts?.claims.length) {
    // One fact a line, its property first: "- winner: Spain men's national football team".
    const said = facts.claims
      .map((c) => ({ property: c.property, values: c.values.map((v) => (typeof v === 'string' ? v : (facts.labels[v.entity] ?? '')).trim()).filter(Boolean) }))
      .filter((c) => c.values.length)
      .map((c) => `- ${c.property}: ${c.values.join(', ')}`);
    if (said.length) lines.push(`Wikidata on ${facts.title}:`, ...said);
  }
  return lines.join('\n');
}

// ---- asking ----------------------------------------------------------------------------------------------------

/** How a lookup went: what came back, with the source to name; offline; or nothing from a source that answered. */
export type Found = { ok: true; source: string; facts: string; answer?: string } | { ok: false; why: 'offline' } | { ok: false; why: 'nothing'; words: string };

/** Asks a URL for JSON; throws `offline` on a network failure, and answers the status with the body otherwise. */
export type Fetcher = (url: string) => Promise<{ status: number; json: unknown }>;

/** The page's own fetch, ten seconds at most, no cookies, nothing but the address. */
export const pageFetch: Fetcher = async (url) => {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) throw new Error('offline');
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(url, { credentials: 'omit', referrerPolicy: 'no-referrer', signal: controller.signal, headers: { Accept: 'application/json' } });
    const json: unknown = await response.json().catch(() => null);
    return { status: response.status, json };
  } catch {
    throw new Error('offline');
  } finally {
    clearTimeout(timer);
  }
};

const enc = encodeURIComponent;

/** The addresses each source is asked at: the only thing that leaves the phone. */
export const URLS = {
  geocode: (place: string) => `https://geocoding-api.open-meteo.com/v1/search?name=${enc(place)}&count=1&language=en&format=json`,
  forecast: (p: Place, days: number) =>
    `https://api.open-meteo.com/v1/forecast?latitude=${p.latitude}&longitude=${p.longitude}&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto&forecast_days=${days}`,
  rates: (from: string, to: string) => `https://api.frankfurter.dev/v1/latest?base=${enc(from)}&symbols=${enc(to)}`,
  wiki: (terms: string) =>
    `https://en.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=${enc(terms)}&gsrlimit=3&prop=extracts%7Cpageprops&ppprop=wikibase_item&exintro=1&explaintext=1&exsentences=4&exlimit=3&format=json&formatversion=2&origin=*`,
  claims: (id: string) => `https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${enc(id)}&props=claims&format=json&origin=*`,
  labels: (ids: readonly string[]) => `https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${ids.map(enc).join('%7C')}&props=labels&languages=en&format=json&origin=*`,
};

/** Looks a plan up: the source's answer as facts for the model, offline, or nothing found. */
export async function lookUp(plan: LookupPlan, fetcher: Fetcher = pageFetch): Promise<Found> {
  try {
    if (plan.kind === 'weather') {
      const place = parseGeocode((await fetcher(URLS.geocode(plan.place))).json);
      if (!place) return { ok: false, why: 'nothing', words: `Open-Meteo doesn’t know a place called ${plan.place}.` };
      const forecast = (await fetcher(URLS.forecast(place, Math.min(7, plan.days.to + 1)))).json;
      const facts = parseForecast(forecast, place, plan.days);
      const answer = forecastAnswer(forecast, plan.days);
      return facts && answer ? { ok: true, source: 'Open-Meteo', facts, answer } : { ok: false, why: 'nothing', words: 'Open-Meteo had no forecast for that day.' };
    }
    if (plan.kind === 'rates') {
      const rates = (await fetcher(URLS.rates(plan.from, plan.to))).json;
      const facts = parseRates(rates, plan);
      const answer = ratesAnswer(rates, plan);
      return facts && answer ? { ok: true, source: 'Frankfurter', facts, answer } : { ok: false, why: 'nothing', words: `The European Central Bank has no rate from ${plan.from} to ${plan.to}.` };
    }
    if (plan.kind === 'wiki') {
      const pages = parseWikiSearch((await fetcher(URLS.wiki(plan.terms))).json);
      if (!pages.length) return { ok: false, why: 'nothing', words: 'Wikipedia had nothing on this.' };
      const best = bestPage(pages, plan.terms);
      let facts: Parameters<typeof wikiFacts>[1] = null;
      if (best?.item) {
        // Wikidata is a second word, not the answer: without it the pages still stand.
        try {
          const claims = parseWikidataClaims((await fetcher(URLS.claims(best.item))).json, best.item);
          const ids = [...new Set(claims.flatMap((c) => c.values.flatMap((v) => (typeof v === 'string' ? [] : [v.entity]))))].slice(0, 20);
          const labels = ids.length ? parseWikidataLabels((await fetcher(URLS.labels(ids))).json) : {};
          facts = { title: best.title, claims, labels };
        } catch {
          facts = null;
        }
      }
      const used = facts?.claims.length ? 'Wikipedia and Wikidata' : 'Wikipedia';
      return { ok: true, source: used, facts: wikiFacts(pages, facts) };
    }
    return { ok: false, why: 'nothing', words: plan.why };
  } catch {
    return { ok: false, why: 'offline' };
  }
}

/** The message the model reads for a looked-up blank: the note's lines as any fill's, then what the source returned. */
export function webMessage(scopeMessage: string, source: string, facts: string): string {
  // The builder's message ends with its answer line; the source's words go before it.
  const cut = scopeMessage.lastIndexOf('\n\n');
  const head = cut >= 0 ? scopeMessage.slice(0, cut) : scopeMessage;
  const tail = cut >= 0 ? scopeMessage.slice(cut + 2) : 'Answer blank 1.';
  return `${head}\n\nWhat ${source} returned:\n${facts}\n\n${tail}`;
}
