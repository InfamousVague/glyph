import { askingWords, type Asking, type Blank } from './blanks.ts';

/**
 * Blanks that need live facts, found before any model is asked (docs/DESIGN.md §145, 2.4).
 *
 * The model has no internet: it runs on the phone with none, even when the phone has one. Measured on the 4B, it named
 * a 2026 World Cup winner twice, and said a temple opens at 9:00 with nothing to say that may change. So a blank whose
 * words make its answer live (weather today, a fare now, an exchange rate, a market, opening hours, the newest of
 * anything, results, events after the model's training) is not handed to the model. It looks for words that make an
 * answer live, not for topics: "Flights are cheapest to Tokyo on" is general advice and goes to the model, "A return
 * flight costs {?price today}" does not.
 *
 * Matt then chose "Pause till online" and "Phone looks it up, all local": a live blank pressed with Fill waits for a
 * connection, then the phone itself asks a keyless public source and the model on the phone writes the answer from
 * what came back (ai/fills/web.ts). So this screen also says what a lookup would ask: the place and the day for the
 * weather, the two currencies for a rate, the words to search for the rest. Where no public source can answer (a fare,
 * a market, opening hours) the app says so, and Ask the model anyway stays.
 *
 * The horizon is a fixed year per model (core/ai.ts `learntUntil`), never the clock, so a 2026 event is after what the
 * model learnt in 2028 as well. Pure: every rule is a test.
 */

export type LiveKind = 'weather' | 'prices' | 'money' | 'markets' | 'hours' | 'newest' | 'after' | 'news' | 'transport';

export interface Live {
  kind: LiveKind;
  /** Why the model can't know it, in the app's words. */
  words: string;
}

/** The panel's sentence for each kind. */
export function liveWords(kind: LiveKind, year?: number): string {
  switch (kind) {
    case 'weather':
      return 'Weather changes by the hour, and the model has no internet.';
    case 'prices':
      return 'Prices change, and the model has no internet.';
    case 'money':
      return 'Exchange rates change every day, and the model has no internet.';
    case 'markets':
      return 'Prices change by the minute, and the model has no internet.';
    case 'hours':
      return 'Opening hours change, and the model could be out of date.';
    case 'newest':
      return 'Something newer may exist than the model knows of.';
    case 'after':
      return `${year ?? 'That year'} is after what the model learnt. It would only be guessing.`;
    case 'news':
      return 'This happened after what the model learnt, or may have.';
    case 'transport':
      return 'This changes by the minute, and the model has no internet.';
  }
}

const WHEN_NOW = /\b(today|tonight|tomorrow|now|this week|this weekend|right now|at the moment)\b/i;
const WEATHER = /\b(weather|forecast|rain|raining|rainy|snow|snowing|temperature|sunny|windy)\b/i;
const PRICE = /\b(price|prices|cost|costs|fare|fares|how much)\b/i;
const PRICE_NOW = /\b(today|now|current|currently|this week|right now|at the moment)\b/i;
const MARKET = /\b(stocks?|share price|shares|bitcoin|ethereum|crypto|the market|nasdaq|ftse|dow jones|s&p)\b/i;
const MARKET_WHAT = /\b(price|value|worth|trading|at)\b/i;
const HOURS = /\b(opens|opening hours|opening times|closes|closing time|open on|is it open|open until)\b/i;
const NEWEST = /\b(newest|latest|most recent|current)\b/i;
const PRODUCT = /\b(version|model|phone|release|update|edition)\b/i;
const HOLDER = /\b(leader|champion|winner|record|holder|prime minister|president|ceo)\b/i;
const EVENT = /\b(won|win|winner|winners|result|results|score|released|launched|elected|announced|happened|died|champion)\b/i;
const NEWS = /\b(who won|the score|results?)\b/i;
const NEWS_WHEN = /\b(last night|yesterday|this season|this year|last week|at the weekend)\b/i;
const TRANSPORT = /\b(delays?|departures?|next train|next bus|next tram|traffic|is it running|running late)\b/i;

/** The pieces a blank asks with, each on its own: a rule that needs two words needs them in one sentence. */
function pieces(asking: Asking): string[] {
  return [asking.question, asking.sentence, asking.prior].filter(Boolean);
}

/** Whether `word` stands in an `if` clause of `piece`: "If it rains tomorrow, what do we do?" asks for a plan. */
function inIf(piece: string, word: RegExp): boolean {
  const at = piece.search(word);
  const cond = piece.search(/\b(if|unless|in case)\b/i);
  return at >= 0 && cond >= 0 && cond < at;
}

/** Whether the blank needs something live or newer than the model (`learntUntil`, the last year it is taken to know). */
export function cannotKnow(blank: Blank, text: string, learntUntil: number): Live | null {
  return screen(askingWords(blank, text), learntUntil);
}

/** The screen over the asking words, for a caller that has them already. */
export function screen(asking: Asking, learntUntil: number): Live | null {
  const all = pieces(asking);
  const any = (test: (piece: string) => boolean) => all.some(test);
  if (any((p) => WEATHER.test(p) && WHEN_NOW.test(p) && !inIf(p, WEATHER))) return { kind: 'weather', words: liveWords('weather') };
  if (moneyAsked(asking) || any((p) => /\bexchange rates?\b|\brate of exchange\b/i.test(p))) return { kind: 'money', words: liveWords('money') };
  if (any((p) => MARKET.test(p) && MARKET_WHAT.test(p))) return { kind: 'markets', words: liveWords('markets') };
  if (any((p) => PRICE.test(p) && PRICE_NOW.test(p))) return { kind: 'prices', words: liveWords('prices') };
  if (any((p) => HOURS.test(p))) return { kind: 'hours', words: liveWords('hours') };
  if (any((p) => TRANSPORT.test(p))) return { kind: 'transport', words: liveWords('transport') };
  const year = laterYear(asking, learntUntil);
  if (year) return { kind: 'after', words: liveWords('after', year) };
  if (any((p) => NEWEST.test(p) && (HOLDER.test(p) || PRODUCT.test(p) || namedAfter(p)))) return { kind: 'newest', words: liveWords('newest') };
  if (any((p) => NEWS.test(p) && NEWS_WHEN.test(p))) return { kind: 'news', words: liveWords('news') };
  return null;
}

/** A capitalised name straight after newest or latest: "The newest Pixel", "the latest version of Android". */
function namedAfter(piece: string): boolean {
  return /\b(?:newest|latest|most recent|current)\s+(?:version of\s+(?:the\s+)?)?[A-Z][\w-]*/.test(piece);
}

/** A year after the model's horizon, beside a word for something that happened: a year alone is a plan, not news. */
function laterYear(asking: Asking, learntUntil: number): number | null {
  for (const piece of pieces(asking)) {
    if (!EVENT.test(piece)) continue;
    for (const match of piece.matchAll(/\b(1\d{3}|2\d{3})\b/g)) {
      const year = Number(match[1]);
      if (year > learntUntil) return year;
    }
  }
  return null;
}

// ---- what a lookup would ask ----------------------------------------------------------------------------------

/**
 * Currencies by what people call them, as ISO codes Frankfurter's ECB rates know. Words that are also everyday words
 * ("won", "real", "try") count only with their country, and a code only in capitals, so "who won" is not money.
 */
const CURRENCY_NAMES: [RegExp, string][] = [
  [/\baustralian dollars?\b/i, 'AUD'],
  [/\bcanadian dollars?\b/i, 'CAD'],
  [/\bnew zealand dollars?\b/i, 'NZD'],
  [/\bhong kong dollars?\b/i, 'HKD'],
  [/\bsingapore dollars?\b/i, 'SGD'],
  [/\b(?:us )?dollars?\b|\bbucks\b|\$/i, 'USD'],
  [/\beuros?\b|€/i, 'EUR'],
  [/\bpounds? sterling\b|\bpounds?\b|\bquid\b|\bsterling\b|£/i, 'GBP'],
  [/\byen\b|¥/i, 'JPY'],
  [/\byuan\b|\brenminbi\b/i, 'CNY'],
  [/\brupees?\b|₹/i, 'INR'],
  [/\bswiss francs?\b|\bfrancs?\b/i, 'CHF'],
  [/\bswedish kron(?:a|or)\b|\bkronor\b/i, 'SEK'],
  [/\bnorwegian kron(?:e|er)\b/i, 'NOK'],
  [/\bdanish kron(?:e|er)\b/i, 'DKK'],
  [/\bkorean won\b/i, 'KRW'],
  [/\bmexican pesos?\b|\bpesos?\b/i, 'MXN'],
  [/\bbrazilian real\b|\breais\b/i, 'BRL'],
  [/\bsouth african rand\b/i, 'ZAR'],
  [/\bzloty\b|\bzłoty\b/i, 'PLN'],
  [/\bbaht\b/i, 'THB'],
  [/\bturkish lira\b/i, 'TRY'],
  [/\bforint\b/i, 'HUF'],
  [/\bczech koruna\b|\bkoruna\b/i, 'CZK'],
];

/** The ECB's currencies by their codes, in capitals only. */
const CODES = /\b(AUD|BGN|BRL|CAD|CHF|CNY|CZK|DKK|EUR|GBP|HKD|HUF|IDR|ILS|INR|ISK|JPY|KRW|MXN|MYR|NOK|NZD|PHP|PLN|RON|SEK|SGD|THB|TRY|USD|ZAR)\b/;

/** The currencies a piece of words names, where each is named, in order. */
function currenciesIn(piece: string): { code: string; at: number; amount: number | null }[] {
  const found: { code: string; at: number; amount: number | null }[] = [];
  let rest = piece;
  const codes = [...piece.matchAll(new RegExp(CODES.source, 'g'))].map((m): [RegExp, string] => [new RegExp(String.raw`\b${m[1]}\b`), m[1]!]);
  for (const [pattern, code] of [...codes, ...CURRENCY_NAMES]) {
    const match = new RegExp(pattern.source, pattern.flags).exec(rest);
    if (!match || found.some((f) => f.code === code)) continue;
    const before = /(\d[\d,]*(?:\.\d+)?)\s*$/.exec(rest.slice(0, match.index));
    const after = /^\s*(\d[\d,]*(?:\.\d+)?)/.exec(rest.slice(match.index + match[0].length));
    const amount = before ? Number(before[1]!.replace(/,/g, '')) : match[0].length === 1 && after ? Number(after[1]!.replace(/,/g, '')) : null;
    found.push({ code, at: match.index, amount });
    rest = `${rest.slice(0, match.index)}${' '.repeat(match[0].length)}${rest.slice(match.index + match[0].length)}`;
  }
  return found.sort((a, b) => a.at - b.at);
}

/**
 * An amount in one currency with another asked for: `100 dollars is {?how many yen} yen`. The source is the currency
 * with an amount, the target the one the question or the words after the blank name, else the other one named.
 */
export function moneyAsked(asking: Asking): { amount: number; from: string; to: string } | null {
  const named = currenciesIn([asking.question, asking.sentence, asking.prior].join(' '));
  if (named.length < 2) return null;
  const source = named.find((c) => c.amount !== null);
  if (!source) return null;
  const asked = currenciesIn(`${asking.question} ${asking.after}`)[0];
  const target = asked && asked.code !== source.code ? asked : named.find((c) => c.code !== source.code);
  if (!target) return null;
  return { amount: source.amount!, from: source.code, to: target.code };
}

/** The place a weather question names: `Weather in Lisbon today`, `the forecast for New York`. */
export function placeAsked(asking: Asking): string | null {
  for (const piece of pieces(asking)) {
    const found = /\b(?:in|at|for|over)\s+((?:[A-Z][\p{L}'’-]+)(?:\s+(?:de|del|da|do|di|la|le|am|upon|on)?\s*[A-Z][\p{L}'’-]+){0,2})/u.exec(piece);
    if (found) return found[1]!.replace(/\s+/g, ' ').trim();
  }
  return null;
}

/** Which day a weather question is about, as days from today: today 0, tomorrow 1, this weekend the coming Saturday. */
export function dayAsked(asking: Asking, now: Date): { from: number; to: number } {
  const words = pieces(asking).join(' ');
  if (/\btomorrow\b/i.test(words)) return { from: 1, to: 1 };
  if (/\bthis weekend\b/i.test(words)) {
    const saturday = (6 - now.getDay() + 7) % 7;
    return { from: saturday, to: Math.min(saturday + 1, 6) };
  }
  if (/\bthis week\b/i.test(words)) return { from: 0, to: 6 };
  return { from: 0, to: 0 };
}

/** Words that carry nothing for a search: the question's small words. */
const STOP = new Set(
  'a an the of to in on at and or is are was were be been it for with by from as that this what which who whom whose when where why how do does did will would can could should i we you he she they me my our your his her their there here about into over than then so not no yes please tell me find out newest latest current most recent'.split(
    ' ',
  ),
);

/**
 * The words a lookup searches for: the question's own words, the small ones left out, at most eight. Only these leave
 * the phone, to the one source asked (docs/DESIGN.md §145): never the note.
 */
export function searchWords(asking: Asking): string {
  const words = pieces(asking)
    .join(' ')
    .replace(/[^\p{L}\p{N}'’ -]+/gu, ' ')
    .split(/\s+/)
    // A label's lone letter (the Q of "Q: …") says nothing either.
    .filter((w) => w && !STOP.has(w.toLowerCase()) && (w.length > 1 || /\d/.test(w)));
  const seen = new Set<string>();
  return words
    .filter((w) => {
      const key = w.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 8)
    .join(' ');
}
