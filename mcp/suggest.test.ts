// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { diff, structureLines, suggestBody, wordsOf } from './suggest.ts';

/**
 * Suggest mode's marks (docs/CLAUDE_LIVE.md, "Suggest mode"): what a change to a note is written as, and what is
 * written directly instead. Keeping every mark gives the new body; reverting every mark gives the old one, for prose.
 */

const keep = (body: string) =>
  body
    .replace(/\{>>[^<]*<<\}/g, '')
    .replace(/\{\+\+([\s\S]*?)\+\+\}/g, '$1')
    .replace(/\{--([\s\S]*?)--\}/g, '')
    .replace(/\{~~([\s\S]*?)~>([\s\S]*?)~~\}/g, '$2');
const revert = (body: string) =>
  body
    .replace(/\{>>[^<]*<<\}/g, '')
    .replace(/\{\+\+([\s\S]*?)\+\+\}/g, '')
    .replace(/\{--([\s\S]*?)--\}/g, '$1')
    .replace(/\{~~([\s\S]*?)~>([\s\S]*?)~~\}/g, '$1');

describe('the diff', () => {
  it('finds the shortest script, the same runs kept in order', () => {
    const ops = diff('abcabba'.split(''), 'cbabac'.split(''));
    expect(ops.filter((op) => op.kind !== 'same').length).toBe(5);
    expect(ops.filter((op) => op.kind !== 'came').map((op) => op.value).join('')).toBe('abcabba');
    expect(ops.filter((op) => op.kind !== 'gone').map((op) => op.value).join('')).toBe('cbabac');
    expect(diff([], ['a'])).toEqual([{ kind: 'came', value: 'a' }]);
    expect(diff(['a'], ['a'])).toEqual([{ kind: 'same', value: 'a' }]);
  });

  it('counts a link, a code span and a blank as one word', () => {
    expect(wordsOf('see [the plan](https://x.test/a b) and `a b` or {?who}')).toEqual(['see', ' ', '[the plan](https://x.test/a b)', ' ', 'and', ' ', '`a b`', ' ', 'or', ' ', '{?who}']);
  });

  it('knows front matter, fences, a table rule and the title from prose', () => {
    const lines = ['---', 'authors: matt', '---', '# Plan', '', 'Words', '```js', 'x', '```', '| a | b |', '| --- | --- |', '| 1 | 2 |'];
    expect(structureLines(lines)).toEqual([true, true, true, true, false, false, true, true, true, false, true, false]);
  });
});

describe('suggestions', () => {
  it('writes a reworded sentence as one replacement, signed', () => {
    const before = '# Trip\n\nWe leave on Monday morning by train.\n';
    const after = '# Trip\n\nWe leave on Tuesday evening by train.\n';
    const { body, count } = suggestBody(before, after, 'Claude');
    expect(body).toBe('# Trip\n\nWe leave on {~~Monday morning~>Tuesday evening~~}{>>Claude<<} by train.\n');
    expect(count).toBe(1);
    expect(keep(body)).toBe(after);
    expect(revert(body)).toBe(before);
  });

  it('marks an insertion and a deletion, their spaces inside so keep and revert both read spaced', () => {
    const before = 'Pack the bags and the very big tent.';
    const after = 'Pack the small bags and the tent.';
    const { body, count } = suggestBody(before, after, 'Claude');
    expect(count).toBe(2);
    expect(body).toContain('{++');
    expect(body).toContain('{--');
    expect(keep(body)).toBe(after);
    expect(revert(body)).toBe(before);
  });

  it('marks a line added or taken out whole after its bullet, box or heading marks', () => {
    const before = '# List\n\n- [ ] eggs\n- [ ] milk\n\n## Old part\n';
    const after = '# List\n\n- [ ] eggs\n- [ ] milk\n- [ ] bread\n';
    const { body } = suggestBody(before, after, 'Claude');
    expect(body).toBe('# List\n\n- [ ] eggs\n- [ ] milk\n\n## {--Old part--}{>>Claude<<}\n- [ ] {++bread++}{>>Claude<<}\n');
  });

  it('pairs the lines that share words, and leaves the rest whole', () => {
    const before = 'Alpha beta gamma delta.\nSomething else entirely here.';
    const after = 'A brand new opening line.\nAlpha beta gamma epsilon.';
    const { body } = suggestBody(before, after, 'Claude');
    expect(body.split('\n')).toEqual(['{++A brand new opening line.++}{>>Claude<<}', 'Alpha beta gamma {~~delta.~>epsilon.~~}{>>Claude<<}', '{--Something else entirely here.--}{>>Claude<<}']);
  });

  it('writes a ticked box as the new box, and the words of the item diffed', () => {
    const { body } = suggestBody('- [ ] call the venue', '- [x] call the venue today', 'Claude');
    expect(body).toBe('- [x] call the venue{++ today++}{>>Claude<<}');
  });

  it('never marks inside front matter, a fence or the title, and writes those as the change itself', () => {
    const before = '# Notes\n\nSome words.\n\n```js\nconst a = 1;\n```\n';
    const after = '---\nauthors: matt, Claude\n---\n# Better notes\n\nSome words.\n\n```js\nconst a = 2;\n```\n';
    const { body, count } = suggestBody(before, after, 'Claude');
    expect(body).toBe(after);
    expect(count).toBe(0);
  });

  it('writes a table row whose cells moved directly, and marks a cell’s words', () => {
    const before = '| a | b |\n| --- | --- |\n| one | two |';
    expect(suggestBody(before, '| a | b |\n| --- | --- |\n| one | three |', 'Claude').body).toBe('| a | b |\n| --- | --- |\n| one | {~~two~>three~~}{>>Claude<<} |');
    expect(suggestBody(before, '| a | b | c |\n| --- | --- | --- |\n| one | two | x |', 'Claude').body).toBe('| a | b | c |\n| --- | --- | --- |\n| one | two | x |');
  });

  it('writes words that would close a mark early as they are', () => {
    expect(suggestBody('a b', 'a --} b', 'Claude').body).toBe('a --} b');
  });

  it('answers the same body unmarked, and names the author it is given', () => {
    expect(suggestBody('same', 'same', 'Claude')).toEqual({ body: 'same', count: 0 });
    expect(suggestBody('one', 'two', 'Claude Code').body).toBe('{~~one~>two~~}{>>Claude Code<<}');
  });

  it('keeps a blank line that went, so paragraphs stay apart until the change is kept', () => {
    const { body } = suggestBody('First.\n\nSecond.', 'First.', 'Claude');
    expect(body).toBe('First.\n\n{--Second.--}{>>Claude<<}');
  });

  it('copes with a long rewrite', () => {
    const before = Array.from({ length: 3000 }, (_, i) => `Line ${i} says something.`).join('\n');
    const after = Array.from({ length: 3000 }, (_, i) => (i % 7 ? `Line ${i} says something.` : `Line ${i} says another thing.`)).join('\n');
    const { body, count } = suggestBody(before, after, 'Claude');
    expect(count).toBe(429);
    expect(keep(body)).toBe(after);
    expect(revert(body)).toBe(before);
  });
});
