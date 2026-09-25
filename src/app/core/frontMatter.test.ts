import { describe, expect, it } from 'vitest';
import { FENCE, FRONT_MATTER_LINES, frontMatterEnd, frontMatterValue, quotedTitle, withFrontMatterTitle, withFrontMatterValue } from './frontMatter.ts';
import { noteTitle } from './store.ts';

/** A block of `count` keys between two fences, then a line of words. */
const keys = (count: number) => ['---', ...Array.from({ length: count }, (_, n) => `key${n}: value`), '---', 'Words'];

describe('what counts as front matter', () => {
  it('is a fence on the first line, keys or blank lines, and a fence to close it', () => {
    expect(frontMatterEnd(['---', 'title: A', '', 'tags: x', '---', 'Words'])).toBe(5);
    expect(frontMatterEnd(['+++', 'id: 1', '+++'])).toBe(3);
    expect(frontMatterEnd(['---  ', '---', 'Words'])).toBe(2);
    expect(frontMatterEnd([])).toBe(0);
    expect(FENCE.test('---')).toBe(true);
    expect(FENCE.test('+++ ')).toBe(true);
    expect(FENCE.test('----')).toBe(false);
    expect(FENCE.test(' ---')).toBe(false);
  });

  it('is not a rule further down, a rule with words under it, or a fence that never closes', () => {
    expect(frontMatterEnd(['Words', '---', 'title: A', '---'])).toBe(0);
    expect(frontMatterEnd(['---', 'Some words here', '---', 'Real title'])).toBe(0);
    expect(frontMatterEnd(['---', 'title: A', 'Words'])).toBe(0);
  });

  it('closes within the first forty lines, fences and all', () => {
    expect(FRONT_MATTER_LINES).toBe(40);
    expect(frontMatterEnd(keys(38))).toBe(40);
    expect(frontMatterEnd(keys(39))).toBe(0);
  });
});

describe('a front matter value read', () => {
  it('is one key, any case, its quotes off', () => {
    expect(frontMatterValue('---\ntitle: "Map"\nBook:  true\n---\n# Map', 'title')).toBe('Map');
    expect(frontMatterValue('---\ntitle: "Map"\nBook:  true\n---\n# Map', 'book')).toBe('true');
    expect(frontMatterValue('---\ntitle: Map\n---\n', 'authors')).toBeNull();
    expect(frontMatterValue('# Map\n\nbook: true', 'book')).toBeNull();
  });

  // Until 2026-09-25 this took any closing fence, so it read keys out of a block the list's title reader showed as
  // words: a note could be a book while its tab said "---".
  it('is nothing out of a block the list does not count as front matter', () => {
    expect(frontMatterValue('---\nbook: true\nsome words about it\n---\n# B', 'book')).toBeNull();
    expect(frontMatterValue(keys(39).join('\n'), 'key0')).toBeNull();
    expect(frontMatterValue(keys(38).join('\n'), 'key0')).toBe('value');
  });
});

describe('a title written as a value', () => {
  it('is quoted, with a quote or a line break made a single quote, and the fallback where nothing is left', () => {
    expect(quotedTitle('Cabin plan: the weekend', 'Canvas')).toBe('"Cabin plan: the weekend"');
    expect(quotedTitle(' Say "hi"\nthere ', 'Canvas')).toBe(`"Say 'hi''there"`);
    expect(quotedTitle('   ', 'Book')).toBe('"Book"');
  });
});

describe('naming a note by its front matter', () => {
  const canvas = '{\n  "nodes": []\n}\n';

  it('replaces the title where there is one, keeping the other keys and the words', () => {
    const body = `---\nid: abc\ntitle: "Old name"\ntags: [trip]\n---\n${canvas}`;
    const next = withFrontMatterTitle(body, 'Cabin weekend: laid out');
    expect(next).toBe(`---\ntitle: "Cabin weekend: laid out"\nid: abc\ntags: [trip]\n---\n${canvas}`);
    expect(noteTitle(next)).toBe('Cabin weekend: laid out');
  });

  it('adds the key to front matter that has none, and makes front matter where there is none', () => {
    expect(withFrontMatterTitle(`---\nid: abc\n---\n${canvas}`, 'Plan')).toBe(`---\ntitle: "Plan"\nid: abc\n---\n${canvas}`);
    expect(withFrontMatterTitle(canvas, 'Plan')).toBe(`---\ntitle: "Plan"\n---\n${canvas}`);
    expect(noteTitle(withFrontMatterTitle(canvas, 'Plan'))).toBe('Plan');
  });

  it('keeps a quote or a line break out of the name, and takes an empty name off', () => {
    expect(withFrontMatterTitle(canvas, ' Say "hi"\nthere ')).toContain(`title: "Say 'hi''there"`);
    expect(withFrontMatterTitle(`---\ntitle: "Plan"\nid: abc\n---\n${canvas}`, '')).toBe(`---\nid: abc\n---\n${canvas}`);
    expect(withFrontMatterTitle(`---\ntitle: "Plan"\n---\n${canvas}`, '  ')).toBe(canvas);
    expect(withFrontMatterTitle(canvas, '')).toBe(canvas);
  });

  // Until 2026-09-25 the title went inside a rule with words under it, where the list never looked, so a rename left
  // the note called "---". The rule and its words are now the note's words, under front matter of its own.
  it('names a note that opens with a rule and words by front matter of its own, above them', () => {
    const ruled = '---\nSome words here\n---\nMore.';
    const next = withFrontMatterTitle(ruled, 'Plan');
    expect(next).toBe(`---\ntitle: "Plan"\n---\n${ruled}`);
    expect(noteTitle(next)).toBe('Plan');
    expect(withFrontMatterTitle(ruled, '')).toBe(ruled);
  });
});

describe('a front matter key written', () => {
  it('goes into front matter of its own above a rule with words under it', () => {
    const ruled = '---\nSome words here\n---\n# B';
    expect(withFrontMatterValue(ruled, 'authors', 'a, b')).toBe(`---\nauthors: a, b\n---\n${ruled}`);
    expect(withFrontMatterValue(ruled, 'authors', null)).toBe(ruled);
  });
});
