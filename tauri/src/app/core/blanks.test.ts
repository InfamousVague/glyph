import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { ensureSyntaxTree } from '@codemirror/language';
import { MARKS } from '../plugins/marks/index.tsx';
import { glyphMarkdown } from '../editor/language.ts';
import { notePattern, notesIn } from '../editor/markNotes.ts';
import { asksForTitle, askingWords, blankMatches, blanksIn, fillsIn, filledMark, findBlank, orderOf, plainFills, readFilled, readableWords, titleWords } from './blanks.ts';
import titles from './titles.fixture.json';

const questions = (text: string) => blankMatches(text).map((b) => b.question);
const MEMORY = { model: 'Qwen3.5 4B', source: { kind: 'memory' as const }, date: '2026-09-28' };

/** The names of the parser's nodes over `text`, with the Marks plugin's formats, as the note's editor parses it. */
function nodes(text: string): { name: string; text: string }[] {
  const state = EditorState.create({ doc: text, extensions: [glyphMarkdown(MARKS)] });
  const tree = ensureSyntaxTree(state, state.doc.length, 5000)!;
  const out: { name: string; text: string }[] = [];
  tree.iterate({ enter: (node) => void out.push({ name: node.name, text: state.doc.sliceString(node.from, node.to) }) });
  return out;
}

describe('the pattern', () => {
  it('reads the sixteen cases', () => {
    expect(questions('Flights are cheapest to Tokyo on {?what day / time?}')).toEqual(['what day / time?']);
    expect(questions('The capital of Australia is {?}.')).toEqual(['']);
    expect(questions('Journal {{?q}} stays a template')).toEqual([]);
    expect(questions('Handlebars {{date}} and {?x}')).toEqual(['x']);
    expect(questions('Escaped \\{?not a blank}')).toEqual([]);
    expect(questions('Nested {?a {b} c}')).toEqual([]);
    expect(questions('Unsure in braces {??maybe??}')).toEqual([]);
    expect(questions('Two {?a} and {?b} on a line')).toEqual(['a', 'b']);
    expect(questions('| Thank you | {?} |')).toEqual(['']);
    expect(questions('# {?}')).toEqual(['']);
    expect(questions(`{?${'x'.repeat(160)}}`)).toHaveLength(1);
    expect(questions(`{?${'x'.repeat(161)}}`)).toEqual([]);
    expect(questions('HOCON ${?HOME} in prose')).toEqual([]);
    expect(questions('| {?Paris | London} |')).toEqual([]);
    expect(questions('Paris or London: {?which, Paris | London}')).toEqual([]);
    expect(questions('Costs $5 {?total}')).toEqual(['total']);
  });

  it('makes no node in the parser, and no link', () => {
    const names = nodes('Flights are cheapest on {?what day}').map((n) => n.name);
    expect(names).not.toContain('Link');
    expect(names).toEqual(['Document', 'Paragraph']);
  });
});

describe('the reader away from the editor', () => {
  it('skips front matter, code, comments, tags, maths and addresses', () => {
    const note = [
      '---',
      'title: {?no}',
      '---',
      'Real {?yes}',
      '```',
      '{?fenced}',
      '```',
      'A `code {?span}` and ``two {?ticks}``',
      '<!-- {?comment} -->',
      '<span title="{?tag}">words</span>',
      'Maths $x {?maths}$ here',
      '[words](https://x.y/{?address}) and <https://x.y/{?auto}>',
      'And {?last}',
    ].join('\n');
    expect(blanksIn(note).map((b) => b.question)).toEqual(['yes', 'last']);
  });

  it('keeps a blank in a table cell and in a link’s words', () => {
    expect(blanksIn('| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |').map((b) => b.question)).toEqual(['']);
    expect(blanksIn('[{?which}](https://x.y)').map((b) => b.question)).toEqual(['which']);
  });

  it('tells blanks with one question apart by their order', () => {
    const text = '{?a} {?b} {?a}';
    const blanks = blanksIn(text);
    expect(orderOf(blanks, blanks[2]!)).toBe(1);
    expect(findBlank(blanks, 'a', 1)?.from).toBe(10);
    expect(findBlank(blanks, 'a', 2)).toBeNull();
  });
});

describe('the asking words', () => {
  const asking = (text: string) => askingWords(blanksIn(text).at(-1)!, text);

  it('read the question before an empty blank', () => {
    expect(asking('How many days until Christmas? {?}').prior).toBe('How many days until Christmas?');
    expect(asking('Who brings the charger? {?}').text).toContain('Who brings the charger?');
  });

  it('read the line above a label', () => {
    expect(asking('Q: Who won the 2026 World Cup?\nA: {?}').prior).toBe('Q: Who won the 2026 World Cup?');
    expect(asking('Who won the 2026 World Cup?\n\nAnswer: {?}').prior).toBe('Who won the 2026 World Cup?');
    expect(asking('What time is it in Tokyo?\n→ {?}').prior).toBe('What time is it in Tokyo?');
  });

  it('keep to a sentence that has words of its own', () => {
    const summary = asking('Tom will get the keys today.\n\nIn one line: {?summary}');
    expect(summary.prior).toBe('');
    expect(summary.text).not.toContain('today');
    expect(asking('Total so far: {?total}').label).toBe('Total so far:');
  });

  it('find the sentence the blank sits in, and the words after it', () => {
    const found = asking('I left early. 1 cup of plain flour is about {?grams} grams. Then more.');
    expect(found.sentence).toBe('1 cup of plain flour is about grams.');
    expect(found.after).toBe('grams.');
    expect(found.question).toBe('grams');
  });

  it('never let a question’s own question mark end a sentence', () => {
    expect(asking('Flights are cheapest to Tokyo on {?what day / time?} in winter').sentence).toBe('Flights are cheapest to Tokyo on in winter');
  });
});

describe('the bracket', () => {
  it('reads all four forms, a web source and Claude, and refuses a person’s own note', () => {
    expect(readFilled('Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?')).toEqual({ model: 'Qwen3.5 4B', source: { kind: 'memory' }, date: '2026-09-28', question: 'what day / time?', place: null });
    expect(readFilled('Qwen3.5 4B from this note, 2026-09-28')?.source).toEqual({ kind: 'note' });
    expect(readFilled('Qwen3.5 4B from memory, 2026-09-28. Asked: three more things. 2 of 3')?.place).toEqual({ n: 2, of: 3 });
    expect(readFilled('Qwen3.5 4B from Open-Meteo, 2026-09-28. Asked: weather')?.source).toEqual({ kind: 'web', name: 'Open-Meteo' });
    expect(readFilled('Qwen3.5 4B from Wikipedia and Wikidata, 2026-09-28')?.source).toEqual({ kind: 'web', name: 'Wikipedia and Wikidata' });
    expect(readFilled('Claude from memory, 2026-09-28. Asked: question')?.model).toBe('Claude');
    expect(readFilled('check with Sam')).toBeNull();
    expect(readFilled('Sam said 400, the email says 450')).toBeNull();
  });
});

describe('the mark an answer is written as', () => {
  const pattern = notePattern(MARKS)!;
  /** The mark found by markNotes and by the parser, as the editor finds it. */
  function readsBack(line: string, words: string) {
    const [note] = notesIn(line, pattern);
    expect(note, line).toBeTruthy();
    expect(line.slice(note!.words.from, note!.words.to)).toBe(words);
    expect(readFilled(note!.text), line).not.toBeNull();
    const unsure = nodes(line).find((n) => n.name === 'Unsure');
    expect(unsure?.text, line).toBe(`??${words}??`);
  }

  it('is the Unsure mark with its source, in every case of the table', () => {
    const plain = `Flights are cheapest to Tokyo on ${filledMark('midweek', MEMORY, 'what day / time?')}`;
    expect(plain).toBe('Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)');
    readsBack(plain, 'midweek');

    const asked = `Opening line: ${filledMark('Could you please get the boiler fixed as soon as possible?', MEMORY, 'a friendlier way')}`;
    expect(asked.endsWith(')?')).toBe(true);
    readsBack(asked, 'Could you please get the boiler fixed as soon as possible');

    readsBack(`Why: ${filledMark('why????', MEMORY, 'x')}`, 'why');
    const brackets = filledMark('Be kind', MEMORY, 'a friendlier way (kind)');
    expect(brackets).toContain('Asked: a friendlier way [kind]');
    readsBack(`Say: ${brackets}`, 'Be kind');
    expect(filledMark('A', MEMORY, 'is it ??maybe??')).toContain('Asked: is it ?maybe?');
    const who = `Who?${filledMark('Sam', MEMORY, '', 'Who?')}`;
    expect(who).toBe('Who? ??Sam??(Qwen3.5 4B from memory, 2026-09-28)');
    readsBack(who, 'Sam');
    expect(filledMark('A', MEMORY, 'pick one. 2 of 3')).toContain('Asked: pick one, 2 of 3');
    expect(readFilled(filledMark('A', MEMORY, 'pick one. 2 of 3').slice(5, -1))?.place).toBeNull();
  });

  it('carries an item’s place only when there are several', () => {
    expect(filledMark('Rail pass', MEMORY, 'three more things', '', { n: 1, of: 3 })).toContain('. Asked: three more things. 1 of 3)');
    expect(filledMark('Rail pass', MEMORY, 'the next step', '', { n: 1, of: 1 })).not.toContain('1 of 1');
  });

  it('reads in a table cell', () => {
    const row = `| Thank you | ${filledMark('ありがとう (arigatō)', MEMORY, '')} |`;
    readsBack(row, 'ありがとう (arigatō)');
    const table = `| Say | In Japanese |\n| --- | --- |\n${row}`;
    expect(nodes(table).some((n) => n.name === 'Unsure')).toBe(true);
  });
});

describe('a filled answer read as its words', () => {
  it('drops the bracket of a fill and keeps a person’s own note', () => {
    expect(plainFills('on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?) or so')).toBe('on midweek or so');
    expect(plainFills('as soon as possible??(Qwen3.5 4B from memory, 2026-09-28)?')).toBe('as soon as possible??(Qwen3.5 4B from memory, 2026-09-28)?');
    expect(plainFills('Say ??as soon as possible??(Qwen3.5 4B from memory, 2026-09-28)?')).toBe('Say as soon as possible?');
    expect(plainFills('??maybe??(check with Sam)')).toBe('??maybe??(check with Sam)');
    expect(plainFills('no marks at all')).toBe('no marks at all');
  });

  it('finds each fill with its span', () => {
    const text = 'a ??x??(Qwen3.5 4B from memory, 2026-09-28) b ??y??(mine)';
    expect(fillsIn(text).map((f) => f.words)).toEqual(['x']);
    expect(fillsIn(text)[0]!.from).toBe(2);
  });

  it('reads a blank as its question for an item’s words', () => {
    expect(readableWords('{?the next step}')).toBe('the next step');
    expect(readableWords('??Turn off the water??(Qwen3.5 4B from memory, 2026-09-28. Asked: the next step)')).toBe('Turn off the water');
  });
});

describe('the title', () => {
  it('knows a question that asks for one', () => {
    for (const q of ['', 'title', 'a title', 'name', 'A name', 'heading', 'a heading', 'name this', 'title this', 'what to call this', 'Title?']) expect(asksForTitle(q), q).toBe(true);
    for (const q of ['how long to boil an egg', 'who wrote Dune', 'capital of Japan', 'name of the band']) expect(asksForTitle(q), q).toBe(false);
  });

  it('reads every row of the shared fixture', () => {
    for (const row of titles.rows) expect(titleWords(row.line), row.line).toBe(row.words);
  });
});
