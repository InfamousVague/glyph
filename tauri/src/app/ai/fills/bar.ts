import { blanksIn, fillsIn, readFilled } from '../../core/blanks.ts';
import { buildFill, fillPlan, type Ask } from './message.ts';
import { FILL_PROMPT_TOKENS, FILL_RUNGS, type Rung } from './prompts.ts';
import { shapeOf, type ShapeInfo } from './shape.ts';
import forecast from './recorded/forecast-lisbon.json';
import geocode from './recorded/geocode-lisbon.json';
import wikiCup from './recorded/wiki-world-cup.json';
import wikidataCup from './recorded/wikidata-world-cup.json';
import wikidataLabels from './recorded/wikidata-labels.json';
import { bestPage, parseForecast, parseGeocode, parseWikidataClaims, parseWikidataLabels, parseWikiSearch, webMessage, wikiFacts } from './web.ts';

/**
 * The Rust bar's cases (docs/DESIGN.md §145, 16.2), as the page builds them: each note, the messages each rung sends
 * for it, and what its answers must hold. Written into src/app/ai/fills.fixture.json, which
 * src-tauri/src/llm/tests.rs reads, and kept equal to what the builder makes by ai/fills/message.test.ts, so the Mac
 * measures what the phone sends. Not part of any screen.
 */

/** What an answer must hold, in words the Rust test reads. */
export interface Expect {
  blank: number;
  /** One of these, in any case. */
  any?: string[];
  /** None of these. */
  none?: string[];
  /** UNKNOWN, or not. */
  unknown?: boolean;
  /** Its word count, from and to. */
  words?: [number, number];
  /** At least this many items once the list's own are left out. */
  items?: number;
  /** No `#` and no full stop at its end: a title. */
  title?: true;
}

export interface BarCase {
  name: string;
  note: string;
  /** Ask the filled answer again rather than a blank. */
  again?: true;
  expect: Expect[];
  /** No line of the raw answer may start with any of these (a numbered list carried on). */
  rawNone?: string[];
  /** The answers come back in the order the blanks were asked. */
  inOrder?: true;
}

export const BAR_CASES: BarCase[] = [
  { name: 'capital', note: '# Australia trip\n\nThe capital of Australia is {?}.', expect: [{ blank: 1, any: ['Canberra'] }] },
  {
    name: 'book-cells',
    note: '# Reading\n\n| Book | Author | Year |\n| --- | --- | --- |\n| The Remains of the Day | {?} | {?} |',
    expect: [
      { blank: 1, any: ['Ishiguro'] },
      { blank: 2, any: ['1989'] },
    ],
  },
  { name: 'title', note: '# {?}\n\nBook the cabin for the second week of October. Ferry once Sam confirms dates with her brother. Deposit $200 by Friday.', expect: [{ blank: 1, words: [2, 6], title: true }] },
  { name: 'newest-pixel', note: '# Phones\n\nThe newest Pixel is the {?}', expect: [{ blank: 1, unknown: true }] },
  { name: 'world-cup-2026', note: '# Football\n\nThe 2026 World Cup was won by {?}', expect: [{ blank: 1, unknown: true }] },
  { name: 'charger', note: '# Cabin weekend\n\nSam said she would bring the charger and the dog food. I am booking the ferry.\n\nWho brings the charger? {?}', expect: [{ blank: 1, any: ['Sam'] }] },
  {
    name: 'phrases',
    note: '# Phrases\n\n- Thank you: {?in Japanese}\n- Where is the station? {?in Japanese}',
    expect: [{ blank: 2, any: ['駅はどこですか'] }],
    inOrder: true,
  },
  { name: 'packing', note: '## Japan packing\n- Passport\n- Plug adapter\n- {?three more things}', expect: [{ blank: 1, items: 3, none: ['Passport', 'Plug adapter'] }] },
  { name: 'numbered-list', note: '# Japan packing\n\n1. Passport\n2. Plug adapter\n3. {?more}', expect: [{ blank: 1, items: 3, none: ['Passport', 'Plug adapter'] }], rawNone: ['3.', '4.', '5.'] },
  { name: 'everest', note: '# Trekking\n\nMount Everest is {?} metres high.', expect: [{ blank: 1, any: ['8848', '8849', '8,848', '8,849'], unknown: false }] },
  { name: 'ask-again', note: '# Football\n\nThe 2022 World Cup was won by ??France??(Qwen3.5 4B from memory, 2026-09-28)', again: true, expect: [{ blank: 1, none: ['France'] }] },
];

/**
 * The model's scenarios of the spec's section 13 and a few more, printed rather than held to anything
 * (`prints_fills_for_the_eye`): what each model writes, and how long it takes, for DESIGN.
 */
export const EYE_CASES: BarCase[] = [
  { name: 'tokyo', note: '# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}', expect: [] },
  { name: 'standup', note: '# Standup 28 Sep\n\nPriya: export bug fixed, in review, lands Tuesday. Tom: blocked on staging keys, will get them today. We moved the launch to the 24th.\n\nIn one line: {?summary}', expect: [] },
  { name: 'kitchen-tap', note: '# Kitchen tap\n- [x] Found the leak under the sink\n- [x] Bought a new washer\n- [ ] {?the next step}', expect: [] },
  { name: 'phrase-table', note: '# Kyoto in November\n\n| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |\n| Where is the station? | {?} |\n| Excuse me | {?} |', expect: [] },
  { name: 'petrichor', note: '# Words\n\nPetrichor: {?what it means}', expect: [] },
  { name: 'flour', note: '# Baking\n\n1 cup of plain flour is about {?grams} grams.', expect: [] },
  { name: 'world-cup-2022', note: '# Football\n\nWe watched France play in Qatar.\n\nThe 2022 World Cup was won by {?}', expect: [] },
  { name: 'friendlier', note: '# Email to the landlord\n\nOpening line, friendlier: {?a friendlier way to say: fix the boiler now}', expect: [] },
  { name: 'egg-title-question', note: '{?how long to boil an egg}', expect: [] },
  { name: 'dune', note: '# {?who wrote Dune}', expect: [] },
  { name: 'trip-to', note: '# Trip to {?capital of Japan}\n\nFlights booked for November.', expect: [] },
  { name: 'cat', note: '# Pets\n\nWhat’s the average lifespan of a cat? {?}', expect: [] },
  { name: 'buttermilk', note: '# Pancakes\n\nA substitute for buttermilk: {?}', expect: [] },
  { name: 'soft-egg', note: '# Kitchen\n\nFor a soft-boiled egg, boil it for {?how long}.', expect: [] },
  { name: 'portuguese', note: '# Lisbon\n\n- Two coffees, please: {?in Portuguese}', expect: [] },
  { name: 'korean', note: '# Seoul\n\n- Where is the toilet? {?in Korean}', expect: [] },
  { name: 'five-blanks', note: '# Trip prep\n\nThe capital of Portugal is {?}.\n\n| Say | In Portuguese |\n| --- | --- |\n| Thank you | {?} |\n| Good night | {?} |\n\n## Packing\n- Passport\n- {?two more things}\n\nIn one line: {?summary}', expect: [] },
];

/**
 * The models the bar binds on: those that met it on the Mac at their rung (docs/DESIGN.md §145). The 2B met it at none,
 * and fills at the rung where it missed least, its misses printed rather than failed.
 */
export const BAR_BINDS = ['qwen3.5-4b', 'qwen3.5-9b'];

/** The day every message in the fixture is written on. */
export const BAR_DAY = new Date(2026, 8, 28, 12);

/** A case's asks: its blanks, or its one filled answer asked again. */
export function barAsks(one: BarCase): Ask[] {
  if (!one.again) return blanksIn(one.note).map((blank) => ({ blank, info: shapeOf(blank, one.note) }));
  const fill = fillsIn(one.note)[0]!;
  const blank = { from: fill.from, to: fill.to, question: readFilled(fill.bracket)?.question ?? '' };
  const info: ShapeInfo = { shape: 'phrase', count: 1, language: null, cell: null, titleLine: false, wholeLine: false, tooShort: false };
  return [{ blank, info, again: { words: fill.words } }];
}

/** One generation as the fixture holds it: the prompts by name, the message, the budget, and which case blanks it asks. */
export interface BarGeneration {
  system: string[];
  prompt: string;
  max_tokens: number;
  blanks: number[];
}

/** The generations each rung sends for a case. */
export function barGenerations(one: BarCase, rung: Rung): BarGeneration[] {
  const asks = barAsks(one);
  return fillPlan(one.note, asks, rung, BAR_DAY).map((generation) => {
    const built = buildFill(one.note, generation.asks, { rung, today: BAR_DAY, tight: generation.tight });
    const system = rung === 3 ? ['FILL_CORE', blockName(generation.asks[0]!.info.shape)] : ['FILL_PROMPT'];
    // Each number the message asks, as the case's own blank: an items blank's slots all answer the one blank.
    const blanks = generation.asks.flatMap((ask, i) => built.numbers[i]!.map(() => asks.indexOf(ask) + 1));
    return { system, prompt: built.prompt, max_tokens: built.maxTokens, blanks };
  });
}

function blockName(shape: ShapeInfo['shape']): string {
  const names: Record<ShapeInfo['shape'], string> = {
    phrase: 'FILL_ANSWER',
    line: 'FILL_ANSWER',
    number: 'FILL_NUMBER',
    title: 'FILL_TITLE',
    summary: 'FILL_SUMMARY',
    items: 'FILL_ITEMS',
    cell: 'FILL_CELL',
    language: 'FILL_TRANSLATE',
  };
  return names[shape];
}

/**
 * Blanks looked up on the web (ai/fills/web.ts), with what the sources returned when they were recorded: the model
 * writes the answer from those words and nothing else, or says UNKNOWN. Measured, not a bar for the rung.
 */
export function webCases() {
  const place = parseGeocode(geocode)!;
  const pages = parseWikiSearch(wikiCup);
  const best = bestPage(pages, '2026 World Cup won')!;
  const cup = wikiFacts(pages, { title: best.title, claims: parseWikidataClaims(wikidataCup, best.item!), labels: parseWikidataLabels(wikidataLabels) });
  const cases: { name: string; note: string; source: string; facts: string; expect: Expect[] }[] = [
    { name: 'web-weather', note: '# Lisbon\n\nWeather in Lisbon tomorrow: {?weather}', source: 'Open-Meteo', facts: parseForecast(forecast, place, { from: 1, to: 1 })!, expect: [{ blank: 1, any: ['°c'] }] },
    { name: 'web-world-cup', note: '# Football\n\nThe 2026 World Cup was won by {?}', source: 'Wikipedia and Wikidata', facts: cup, expect: [{ blank: 1, any: ['Spain'] }] },
    { name: 'web-nothing', note: '# Football\n\nThe 2026 World Cup was won by {?}', source: 'Wikipedia', facts: pages.find((p) => p.title.includes('Group B'))!.extract, expect: [{ blank: 1, unknown: true }] },
  ];
  return cases.map((one) => {
    const asks = barAsks({ name: one.name, note: one.note, expect: [] });
    const built = buildFill(one.note, asks, { rung: 1, today: BAR_DAY });
    return { name: one.name, note: one.note, expect: one.expect, raw_none: [], in_order: false, source: one.source, rungs: { '1': [{ system: ['FILL_WEB_PROMPT'], prompt: webMessage(built.prompt, one.source, one.facts), max_tokens: built.maxTokens, blanks: [1] }] } };
  });
}

/** The whole fixture, as the Rust test reads it. */
export function barFixture() {
  return {
    about:
      'The fill bar (docs/DESIGN.md §145, 16.2): each case as the page builds it at each rung, the prompts by their names in src/app/ai/fills/prompts.ts, and what the answers must hold. Written by src/app/ai/fills/message.test.ts (GLYPH_WRITE_FILLS_FIXTURE=1); read by src-tauri/src/llm/tests.rs.',
    rungs: FILL_RUNGS,
    binds: BAR_BINDS,
    prompt_tokens: FILL_PROMPT_TOKENS,
    cases: BAR_CASES.map(fixtureCase),
    eye: EYE_CASES.map(fixtureCase),
    web: webCases(),
  };
}

function fixtureCase(one: BarCase) {
  return {
    name: one.name,
    note: one.note,
    expect: one.expect,
    raw_none: one.rawNone ?? [],
    in_order: one.inOrder ?? false,
    rungs: { '1': barGenerations(one, 1), '2': barGenerations(one, 2), '3': barGenerations(one, 3) },
  };
}
