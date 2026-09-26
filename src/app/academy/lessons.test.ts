import { afterEach, describe, expect, it } from 'vitest';
import { markGroups } from '../guide/marks.ts';
import { MARKS } from '../plugins/marks/index.tsx';
import { plugins } from '../plugins/registry.ts';
import { CHAPTERS, LESSONS, lessonsIn, lessonsNow, readProgress, writeProgress } from './lessons.ts';

const passes = (id: string, text: string) => {
  const lesson = LESSONS.find((one) => one.id === id);
  if (!lesson) throw new Error(`no lesson ${id}`);
  return lesson.passes(text);
};

afterEach(() => plugins.setEnabled('marks', true));

describe('Ghost.md Academy’s lessons', () => {
  it('teaches every lesson with an example that passes its own check', () => {
    for (const lesson of LESSONS) {
      expect(lesson.passes(lesson.example), `${lesson.id}: its own example`).toBe(true);
    }
  });

  it('has a lesson for every part of a mark: what it is, what to type, what to do, and a way out', () => {
    for (const lesson of LESSONS) {
      expect(lesson.title, lesson.id).toBeTruthy();
      expect(lesson.symbol, lesson.id).toBeTruthy();
      expect(lesson.teach.length, lesson.id).toBeGreaterThan(30);
      expect(lesson.task, lesson.id).toBeTruthy();
      expect(lesson.hint, lesson.id).toBeTruthy();
      expect(lesson.praise, lesson.id).toBeTruthy();
      expect(CHAPTERS).toContain(lesson.chapter);
    }
    expect(new Set(LESSONS.map((lesson) => lesson.id)).size).toBe(LESSONS.length);
    expect(CHAPTERS.flatMap((chapter) => lessonsIn(chapter)).length).toBe(LESSONS.length);
  });

  it('teaches each chapter in one run, in the order the chapters are named', () => {
    const order = LESSONS.map((lesson) => CHAPTERS.indexOf(lesson.chapter));
    expect(order).toEqual([...order].sort((a, b) => a - b));
    for (const chapter of CHAPTERS) expect(lessonsIn(chapter).length, chapter).toBeGreaterThan(0);
  });

  it('passes words of a person’s own, not only the example', () => {
    expect(passes('title', '# Camping in June')).toBe(true);
    expect(passes('heading', 'notes\n\n## What to pack')).toBe(true);
    // The lesson offers ### as well as ##, so it has to take it (Matt: "the lesson isn't passed").
    expect(passes('heading', '### Friday')).toBe(true);
    expect(passes('heading', '#### Friday morning')).toBe(true);
    expect(passes('bold', 'bring the **big tent**')).toBe(true);
    expect(passes('italic', 'the _small_ one leaks')).toBe(true);
    // Stars lean words over too, and the page below shows it, so the lesson takes them.
    expect(passes('italic', 'the *small* one leaks')).toBe(true);
    expect(passes('both', 'it is ***here***')).toBe(true);
    expect(passes('struck', '~~Thursday~~ Friday')).toBe(true);
    expect(passes('code', 'type `ls` to look')).toBe(true);
    expect(passes('link', 'see [the map](https://maps.example.com/x)')).toBe(true);
    expect(passes('list', '- tent\n- stove')).toBe(true);
    expect(passes('number', '1) Pack\n2) Go')).toBe(true);
    expect(passes('todo', '- [ ] ring the site')).toBe(true);
    expect(passes('quote', '> no dogs in July')).toBe(true);
    expect(passes('rule', 'before\n\n***\n\nafter')).toBe(true);
    expect(passes('fence', '```\nkeep this\n```')).toBe(true);
    expect(passes('table', '| Day | Where |\n| --- | --- |\n| Fri | Cabin |')).toBe(true);
    expect(passes('picture', '![the view](image/lake.jpg)')).toBe(true);
    expect(passes('raised', 'E = mc^2^')).toBe(true);
    expect(passes('lowered', 'CO~2~ levels')).toBe(true);
    expect(passes('footnote', 'the lake is cold[^1]\n\n[^1]: In June, anyway.')).toBe(true);
    expect(passes('definition', 'Kayak\n: a boat for one')).toBe(true);
    expect(passes('maths', 'area is $\\pi r^2$')).toBe(true);
    expect(passes('emoji', 'on the way :rocket:')).toBe(true);
    expect(passes('callout', '> [!WARNING]\n> The road floods.')).toBe(true);
    expect(passes('diagram', '```mermaid\nflowchart LR\n  Home --> Lake\n```')).toBe(true);
    expect(passes('tag', 'swim at dawn #lake')).toBe(true);
    expect(passes('choice', 'Dinner?\n- (x) Pasta\n- ( ) Fish')).toBe(true);
    expect(passes('counter', '- Lengths [2/10]')).toBe(true);
    expect(passes('sum', '= 12 * 4')).toBe(true);
    expect(passes('hiddenLine', '>| the gate code is 4411')).toBe(true);
    expect(passes('progress', '# Trip\n- [ ] Pack')).toBe(true);
    expect(passes('wiki', 'see [[Packing list]]')).toBe(true);
    expect(passes('anchor', '- Book the kayak ^kayak')).toBe(true);
    expect(passes('itemRef', 'after [[#^kayak]]')).toBe(true);
    expect(passes('bookmark', 'start reading here §§')).toBe(true);
    expect(passes('board', '```board\nLater: kayak\n```')).toBe(true);
    expect(passes('spoiler', 'it was ||Sam|| all along')).toBe(true);
    expect(passes('highlight', 'the ==gate code==')).toBe(true);
    expect(passes('tint', 'the ==gate code==(amber)')).toBe(true);
    expect(passes('aside', 'swim %%if warm%%')).toBe(true);
    expect(passes('unsure', 'about ??six miles??')).toBe(true);
    expect(passes('markNote', 'about ??six miles??(from the map)')).toBe(true);
    expect(passes('shout', '^^do not^^ feed the ducks')).toBe(true);
    expect(passes('added', 'bring ++a towel++')).toBe(true);
    expect(passes('heat', '🔥🔥a hot day🔥🔥')).toBe(true);
    expect(passes('frost', '❄️❄️cold water❄️❄️')).toBe(true);
    expect(passes('wave', '🌊🌊rough today🌊🌊')).toBe(true);
    expect(passes('shimmer', '✨✨the lake at night✨✨')).toBe(true);
    expect(passes('haunt', '👻👻the old boathouse👻👻')).toBe(true);
  });

  it('is not passed by the words alone, or by another mark', () => {
    expect(passes('title', 'Weekend trip')).toBe(false);
    // A title is not a heading: the lesson wants its own mark.
    expect(passes('heading', '# Weekend trip')).toBe(false);
    expect(passes('bold', '*one star*')).toBe(false);
    expect(passes('italic', 'snake_case_words')).toBe(false);
    // Bold is two stars, and is its own lesson.
    expect(passes('italic', '**Friday at noon**')).toBe(false);
    expect(passes('both', '**Friday at noon**')).toBe(false);
    expect(passes('struck', '~one squiggle~')).toBe(false);
    expect(passes('code', 'no backticks here')).toBe(false);
    expect(passes('link', '[words] (https://example.com)')).toBe(false);
    expect(passes('list', 'milk and bread')).toBe(false);
    expect(passes('number', '2026 was the year')).toBe(false);
    expect(passes('todo', '- ring the site')).toBe(false);
    expect(passes('quote', 'she said no dogs')).toBe(false);
    expect(passes('rule', '- -')).toBe(false);
    // One fence is a block that never closes.
    expect(passes('fence', '```js\nconst x = 1;')).toBe(false);
    expect(passes('table', '| just | pipes |')).toBe(false);
    expect(passes('picture', '[the view](image/lake.jpg)')).toBe(false);
    expect(passes('raised', 'x^2 with no end')).toBe(false);
    // Two squiggles cross words out; one lowers them.
    expect(passes('lowered', '~~struck~~')).toBe(false);
    // A mark that says nothing is a typo, not a footnote.
    expect(passes('footnote', 'the lake is cold[^1]')).toBe(false);
    expect(passes('definition', ': a colon on its own')).toBe(false);
    expect(passes('maths', 'it costs $450')).toBe(false);
    expect(passes('emoji', 'a :not-a-name-we-know: here')).toBe(false);
    expect(passes('callout', '> an ordinary quote')).toBe(false);
    expect(passes('diagram', '```js\nconst x = 1;\n```')).toBe(false);
    expect(passes('tag', '# Weekend trip')).toBe(false);
    expect(passes('choice', '- [ ] a to-do, not a choice')).toBe(false);
    expect(passes('counter', 'three of 3/8')).toBe(false);
    expect(passes('sum', '450 + 120')).toBe(false);
    expect(passes('hiddenLine', '> an ordinary quote')).toBe(false);
    expect(passes('progress', '## Packing\n- tent')).toBe(false);
    // A place in this note is not another note.
    expect(passes('wiki', 'after [[#^kayak]]')).toBe(false);
    expect(passes('anchor', '- Book the kayak')).toBe(false);
    expect(passes('itemRef', 'see [[Packing list]]')).toBe(false);
    expect(passes('bookmark', 'one section sign §')).toBe(false);
    expect(passes('board', '```\nLater: kayak\n```')).toBe(false);
    expect(passes('spoiler', 'a |single| bar')).toBe(false);
    expect(passes('highlight', 'a =single= sign')).toBe(false);
    expect(passes('tint', 'a ==plain== highlight')).toBe(false);
    expect(passes('aside', 'fifty %')).toBe(false);
    expect(passes('unsure', 'really?')).toBe(false);
    // A colour is not a note, and a mark with nothing after it is not one either.
    expect(passes('markNote', 'the ==gate code==(amber)')).toBe(false);
    expect(passes('markNote', 'about ??six miles??')).toBe(false);
    // One caret either side raises; two shout.
    expect(passes('shout', 'the 2^nd^ of June')).toBe(false);
    expect(passes('added', '1 + 1')).toBe(false);
    // One emoji is a word, and three are three.
    expect(passes('heat', '🔥a fire🔥')).toBe(false);
    expect(passes('heat', '🔥🔥🔥a fire🔥🔥🔥')).toBe(false);
    expect(passes('frost', '❄️cold❄️')).toBe(false);
    expect(passes('wave', '🌊sea🌊')).toBe(false);
    expect(passes('shimmer', '✨one✨')).toBe(false);
    expect(passes('haunt', '👻boo👻')).toBe(false);
  });

  it('knows a to-do the way the note does: a box after any marker, with a space after it (core/itemSyntax.ts)', () => {
    expect(passes('todo', '1. [ ] ring the site')).toBe(true);
    expect(passes('todo', '* [x] rang the site')).toBe(true);
    // Brackets against the words draw no box in a note, so there is nothing to tap: not a to-do yet.
    expect(passes('todo', '- [ ]ring the site')).toBe(false);
  });

  it('keeps what has been learned, and shrugs off a store it cannot read', () => {
    writeProgress(new Set(['title', 'bold']));
    expect(readProgress()).toEqual(new Set(['title', 'bold']));
    localStorage.setItem('glyph-academy', 'not json');
    expect(readProgress()).toEqual(new Set());
    localStorage.removeItem('glyph-academy');
    expect(readProgress()).toEqual(new Set());
  });
});

describe('the Academy and the cheat sheet', () => {
  const rows = () => markGroups().flatMap((group) => group.rows);

  it('teaches every mark the cheat sheet lists, each in exactly one lesson', () => {
    const taught = LESSONS.flatMap((lesson) => lesson.rows);
    for (const row of rows()) expect(taught.filter((name) => name === row.name), row.name).toHaveLength(1);
    // And no lesson teaches a row the cheat sheet does not have.
    const names = new Set(rows().map((row) => row.name));
    for (const name of taught) expect(names, name).toContain(name);
  });

  it('writes each lesson’s mark as the cheat sheet writes it', () => {
    for (const lesson of LESSONS) {
      const row = rows().find((one) => one.name === lesson.rows[0]);
      expect(row?.symbol, lesson.id).toBe(lesson.symbol);
    }
  });

  it('has a lesson for each of the Marks plugin’s marks, the five effects among them', () => {
    for (const mark of MARKS) {
      const lesson = LESSONS.find((one) => one.rows.includes(mark.name));
      expect(lesson?.symbol, mark.name).toBe(mark.delimiter);
      expect(lesson?.needs, mark.name).toBe(mark.name);
    }
  });

  it('offers a plugin’s lessons only while its marks are switched on, as the cheat sheet shows them', () => {
    expect(lessonsNow()).toHaveLength(LESSONS.length);
    plugins.setEnabled('marks', false);
    const now = lessonsNow();
    expect(now.every((lesson) => !lesson.needs)).toBe(true);
    expect(now.map((lesson) => lesson.id)).not.toContain('hiddenLine');
    expect(now.map((lesson) => lesson.id)).toContain('board');
    // The two agree with the plugin off as well: every row still shown is still taught.
    const taught = now.flatMap((lesson) => lesson.rows);
    for (const row of rows()) expect(taught, row.name).toContain(row.name);
    expect(lessonsIn('Marks and effects', now)).toEqual([]);
  });
});
