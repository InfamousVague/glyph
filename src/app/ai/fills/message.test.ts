import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { inLocale } from '../../../test/locale.ts';
import { blanksIn, fillsIn } from '../../core/blanks.ts';
import { barFixture } from './bar.ts';
import { buildFill, estimateTokens, fillPlan, fits, modelDay, scopeText, type Ask } from './message.ts';
import { FILL_RUNGS, rungFor } from './prompts.ts';
import { shapeOf } from './shape.ts';

const TODAY = new Date(2026, 8, 28, 12);
const asksOf = (note: string): Ask[] => blanksIn(note).map((blank) => ({ blank, info: shapeOf(blank, note) }));
const numbered = (ask: Ask, index: number) => `{?${index + 1} ${ask.blank.question}}`;

describe('the date the model is told', () => {
  it('is fixed English whatever the phone speaks', () => {
    expect(modelDay(TODAY)).toBe('Monday 28 September 2026');
    expect(inLocale('en-US', () => modelDay(TODAY))).toBe('Monday 28 September 2026');
    expect(inLocale('de-DE', () => modelDay(TODAY))).toBe('Monday 28 September 2026');
  });
});

describe('what the model reads', () => {
  it('is the Tokyo note as the spec writes it', () => {
    const note = '# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}';
    expect(buildFill(note, asksOf(note), { rung: 1, today: TODAY }).prompt).toBe(
      'Today is Monday 28 September 2026.\n\nThe note:\n# Tokyo trip\n\nFlights are cheapest to Tokyo on {?1 what day / time?}\n\nAnswer blank 1.',
    );
  });

  it('reads a cell’s headings, its header row and its own row, each blank named in words', () => {
    const note = '# Kyoto in November\n\nIntro words here.\n\n## Phrases\n| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |\n| Where is the station? | {?} |';
    expect(buildFill(note, asksOf(note), { rung: 1, today: TODAY }).prompt).toBe(
      [
        'Today is Monday 28 September 2026.',
        '',
        'The note:',
        '# Kyoto in November',
        '',
        '(lines left out)',
        '',
        '## Phrases',
        '| Say | In Japanese |',
        '| --- | --- |',
        '| Thank you | {?1 } |',
        '| Where is the station? | {?2 } |',
        '',
        'Blank 1 is Thank you in Japanese.',
        'Blank 2 is Where is the station? in Japanese.',
        '',
        'Answer blanks 1 to 2.',
      ].join('\n'),
    );
    const one = '# Reading\n\n| Book | Author | Year |\n| --- | --- | --- |\n| Never Let Me Go | Kazuo Ishiguro | 2005 |\n| The Remains of the Day | {?} | 1989 |';
    const scope = scopeText(one, asksOf(one), numbered);
    expect(scope).not.toContain('Never Let Me Go');
    expect(scope).toContain('| The Remains of the Day | {?1 } | 1989 |');
  });

  it('cuts a long section to a thousand characters before and six hundred after, at line ends', () => {
    const filler = (n: number) => Array.from({ length: n }, (_, i) => `Line ${i} of words about the trip and nothing else much.`).join('\n');
    const note = `# Trip\n\n${filler(40)}\nFlights are cheapest on {?which day}\n${filler(40)}`;
    const scope = scopeText(note, asksOf(note), numbered);
    const at = scope.indexOf('{?1 which day}');
    expect(at).toBeGreaterThan(0);
    const before = scope.slice(scope.indexOf('(lines left out)') + 17, at);
    expect(before.length).toBeLessThanOrEqual(1060);
    expect(scope.length).toBeLessThan(2000);
    expect(scope.startsWith('# Trip')).toBe(true);
  });

  it('writes other blanks as ___, worked-out ones as their answers, fills as words, and no front matter', () => {
    const note = '---\nlocation: 51.5,-0.1\n---\n# Trip\n\nTotal: {?total}\nWeather: {?}\nCheapest on ??midweek??(Qwen3.5 4B from memory, 2026-09-28) and [the site](https://x.y/z) or https://a.b\nAsk: {?which airport}';
    const asks = asksOf(note).filter((a) => a.blank.question === 'which airport');
    const scope = scopeText(note, asks, numbered, (blank) => (blank.question === 'total' ? '$325' : null));
    expect(scope).toBe('# Trip\n\nTotal: $325\nWeather: ___\nCheapest on midweek and the site or\nAsk: {?1 which airport}');
  });

  it('writes an answer asked again back as its question, and says which answer it is not', () => {
    const note = '# Football\n\nThe 2022 World Cup was won by ??France??(Qwen3.5 4B from memory, 2026-09-28)';
    const fill = fillsIn(note)[0]!;
    const ask: Ask = { blank: { from: fill.from, to: fill.to, question: '' }, info: asksOf('{?}')[0]!.info, again: { words: 'France' } };
    const prompt = buildFill(note, [ask], { rung: 1, today: TODAY }).prompt;
    expect(prompt).toContain('The 2022 World Cup was won by {?1 }');
    expect(prompt.endsWith('It is not: France.\nAnswer blank 1.')).toBe(true);
  });
});

describe('an items blank', () => {
  it('asks one new item a numbered blank, under the list’s own lead', () => {
    const note = '# Japan packing\n\n1. Passport\n2. Plug adapter\n3. {?more}';
    const built = buildFill(note, asksOf(note), { rung: 1, today: TODAY });
    expect(built.prompt).toContain('3. {?1 more}\n4. {?2 }\n5. {?3 }');
    expect(built.prompt).toContain('Blanks 1 to 3 are whole items of the list they are in, each one new.');
    expect(built.prompt.endsWith('Answer blanks 1 to 3.')).toBe(true);
    expect(built.numbers).toEqual([[1, 2, 3]]);
    const todo = '# Tap\n- [x] Found the leak\n- [ ] {?the next step}\n\nThe capital of France is {?}.';
    const both = buildFill(todo, asksOf(todo), { rung: 1, today: TODAY });
    expect(both.numbers).toEqual([[1], [2]]);
    expect(both.prompt).toContain('Blank 1 is a whole item of the list it is in.');
  });
});

describe('the room', () => {
  it('counts tokens by script, on the high side', () => {
    expect(estimateTokens('abcd efgh')).toBe(3);
    expect(estimateTokens('ありがとう')).toBe(5);
    expect(estimateTokens('화장실이 어디예요')).toBe(9);
    expect(estimateTokens('Спасибо')).toBe(4);
  });

  it('puts seven language cells in one generation and the eighth in the next', () => {
    const rows = Array.from({ length: 8 }, (_, i) => `| Phrase number ${i + 1} | {?} |`).join('\n');
    const note = `# Phrases\n\n| Say | In Japanese |\n| --- | --- |\n${rows}`;
    const plan = fillPlan(note, asksOf(note), 1, TODAY);
    expect(plan.map((g) => g.asks.length)).toEqual([7, 1]);
  });

  it('splits long Japanese scopes so each generation stays in the window', () => {
    const para = 'これは長い段落です。'.repeat(60);
    const note = Array.from({ length: 12 }, (_, i) => `## 第${i + 1}\n${para}\n説明: {?}`).join('\n\n');
    const plan = fillPlan(note, asksOf(note), 1, TODAY);
    expect(plan.length).toBeGreaterThan(1);
    for (const generation of plan) expect(fits(buildFill(note, generation.asks, { rung: 1, today: TODAY, tight: generation.tight }))).toBe(true);
  });

  it('gives each blank its own generation at the second rung, grouped by shape at the third', () => {
    const note = '# Mixed\n\nThe capital of France is {?}.\n\n- Thank you: {?in Japanese}\n\nThe capital of Peru is {?}.';
    expect(fillPlan(note, asksOf(note), 2, TODAY).map((g) => g.asks.length)).toEqual([1, 1, 1]);
    expect(fillPlan(note, asksOf(note), 3, TODAY).map((g) => g.asks[0]!.info.shape)).toEqual(['phrase', 'phrase', 'language']);
    expect(fillPlan(note, asksOf(note), 1, TODAY).map((g) => g.asks.length)).toEqual([3]);
  });
});

describe('the fixture the Rust bar reads', () => {
  // From the repository's root, where the suite runs: the page's tests run in jsdom, whose module URLs are not files.
  const path = resolve(process.cwd(), 'src/app/ai/fills.fixture.json');

  it('is what the page builds, every case at every rung', () => {
    const built = JSON.parse(JSON.stringify(barFixture()));
    if (process.env.GLYPH_WRITE_FILLS_FIXTURE) writeFileSync(path, `${JSON.stringify(built, null, 2)}\n`);
    expect(JSON.parse(readFileSync(path, 'utf8'))).toEqual(built);
  });

  it('names the rungs the page ships, and a model never measured takes the middle one', () => {
    expect(JSON.parse(readFileSync(path, 'utf8')).rungs).toEqual(FILL_RUNGS);
    expect(rungFor('a-model-nobody-measured')).toBe(2);
  });
});
