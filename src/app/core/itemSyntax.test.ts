import { describe, expect, it } from 'vitest';
import {
  AFTER_MARK,
  COUNTER_IN_WORDS,
  anchorSpan,
  isDoneName,
  listLead,
  taskBox,
  withoutAnchor,
  withoutBookmark,
  withoutLead,
  wordsEnd,
} from './itemSyntax.ts';

/*
 * "One grammar means a line is a to-do everywhere or nowhere" (itemSyntax.ts). These are the lines the copies used to
 * disagree about, read once, so a change to the grammar shows up here before it shows up as a box that stopped
 * ticking.
 */

describe('what opens a list item', () => {
  it('reads every marker: a dash, a star, a plus, a number with a dot or a bracket', () => {
    for (const [line, marker] of [
      ['- Milk', '-'],
      ['* Milk', '*'],
      ['+ Milk', '+'],
      ['1. Milk', '1.'],
      ['12) Milk', '12)'],
      ['1234. Milk', '1234.'],
    ]) {
      expect(listLead(line!)).toMatchObject({ marker, done: null, picked: null, boxAt: -1, wordsAt: marker!.length + 1 });
    }
  });

  it('takes any run of spaces or tabs after the marker, and the indent before it', () => {
    expect(listLead('-  Milk')).toMatchObject({ indent: '', wordsAt: 3 });
    expect(listLead('-\tMilk')).toMatchObject({ wordsAt: 2 });
    expect(listLead('    * Milk')).toMatchObject({ indent: '    ', marker: '*', wordsAt: 6 });
    expect(listLead('\t1. Milk')).toMatchObject({ indent: '\t', marker: '1.' });
  });

  it('is not fooled by what only looks like a list', () => {
    for (const line of ['Milk', '-Milk', '1.Milk', '#1. Milk', '-', '', '[ ] Milk', '(x) Milk', '1.5 litres']) expect(listLead(line)).toBeNull();
  });

  it('reads a to-do box after any marker, ticked or not, and the words after it', () => {
    expect(listLead('- [ ] Milk')).toMatchObject({ done: false, boxAt: 2, wordsAt: 6 });
    expect(listLead('* [x] Milk')).toMatchObject({ done: true, boxAt: 2, wordsAt: 6 });
    expect(listLead('+ [X] Milk')).toMatchObject({ done: true });
    expect(listLead('3. [x] Milk')).toMatchObject({ done: true, boxAt: 3, wordsAt: 7 });
    expect(listLead('-  [ ]  Milk')).toMatchObject({ done: false, boxAt: 3, wordsAt: 7 });
    // An empty to-do is still one: the box is what is being typed.
    expect(listLead('- [ ]')).toMatchObject({ done: false, wordsAt: 5 });
  });

  it('takes a box glued to its words, or a link whose words are x, as words: the editor draws no box there', () => {
    expect(listLead('- [ ]Milk')).toMatchObject({ done: null, boxAt: -1, wordsAt: 2 });
    expect(listLead('- [x](https://example.com/x)')).toMatchObject({ done: null, wordsAt: 2 });
    expect(listLead('- [xx] Milk')).toMatchObject({ done: null });
  });

  it('reads a choice after a bullet, never after a number, and never as a tick', () => {
    expect(listLead('- ( ) Tent')).toMatchObject({ done: null, picked: false, boxAt: 2, wordsAt: 6 });
    expect(listLead('*  (X) Cabin')).toMatchObject({ picked: true, boxAt: 3, wordsAt: 7 });
    expect(listLead('- ( )')).toMatchObject({ picked: false, wordsAt: 5 });
    expect(listLead('1. ( ) Tent')).toMatchObject({ done: null, picked: null, boxAt: -1, wordsAt: 3 });
    expect(listLead('- ( )Tent')).toMatchObject({ picked: null, wordsAt: 2 });
    // A box and then a choice is a to-do whose words start with brackets.
    expect(listLead('- [ ] ( ) Tent')).toMatchObject({ done: false, picked: null, wordsAt: 6 });
  });

  it('says where the box is and whether it is ticked, for the lines that have one', () => {
    expect(taskBox('  1. [x] Bins')).toEqual({ at: 5, done: true });
    expect(taskBox('- [ ] Milk')).toEqual({ at: 2, done: false });
    expect(taskBox('- ( ) Tent')).toBeNull();
    expect(taskBox('- Milk')).toBeNull();
    expect(taskBox('- [ ]Milk')).toBeNull();
  });

  it('says a line back without its lead, and any other line as it is', () => {
    expect(withoutLead('- [ ] Buy milk')).toBe('Buy milk');
    expect(withoutLead('* [x] Buy milk')).toBe('Buy milk');
    expect(withoutLead('1. [ ] Buy milk')).toBe('Buy milk');
    expect(withoutLead('  -  Buy milk')).toBe('Buy milk');
    expect(withoutLead('- ( ) Tent')).toBe('Tent');
    expect(withoutLead('The login is broken.')).toBe('The login is broken.');
  });
});

describe('what ends an item line', () => {
  it('finds the anchor last on the line, or with marks and counters after it', () => {
    expect(anchorSpan('- [ ] Ship it ^ship-it')).toEqual({ id: 'ship-it', from: 14, to: 22 });
    expect(anchorSpan('- [ ] Ship it ^ship [notion](https://n.so/a)')).toEqual({ id: 'ship', from: 14, to: 19 });
    expect(anchorSpan('- Water [3/8] ^water [1/2]  ')).toEqual({ id: 'water', from: 14, to: 20 });
    expect(anchorSpan('^first')).toEqual({ id: 'first', from: 0, to: 6 });
  });

  it('leaves superscripts, glued carets and anchors with words after them alone', () => {
    for (const text of ['- E = mc^2^', '- the 2 ^nd^ of June', '- Ship it^ship', '- ^ship then words', '- Ship ^Ship', '- Ship ^-ship']) expect(anchorSpan(text)).toBeNull();
  });

  it('takes the anchor and the one space before it off, and nothing else', () => {
    expect(withoutAnchor('- [ ] Ship it ^ship')).toBe('- [ ] Ship it');
    expect(withoutAnchor('- [ ] Ship it ^ship [notion](https://n.so/a)')).toBe('- [ ] Ship it [notion](https://n.so/a)');
    expect(withoutAnchor('- [ ] Ship it ^ship   ')).toBe('- [ ] Ship it');
    expect(withoutAnchor('^ship')).toBe('');
    expect(withoutAnchor('- E = mc^2^')).toBe('- E = mc^2^');
  });

  it('takes the bookmark out only where it stands as a word', () => {
    expect(withoutBookmark('- [ ] Ship it §§ [notion](https://n.so/a) ^ship')).toBe('- [ ] Ship it [notion](https://n.so/a) ^ship');
    expect(withoutBookmark('The deposit is four hundred. §§')).toBe('The deposit is four hundred.');
    expect(withoutBookmark('section §§5')).toBe('section §§5');
  });

  it('knows where the words end: before the bookmark, the mark, the counters and the anchor', () => {
    const line = '- [ ] Ship it §§ [notion](https://n.so/a) [3/8] ^ship';
    expect(line.slice(0, wordsEnd(line))).toBe('- [ ] Ship it');
    expect(wordsEnd('Just a line  ')).toBe(11);
    // An empty to-do or choice ends after its box, where the words would start.
    expect(wordsEnd('- [ ] ^ship')).toBe(6);
    expect(wordsEnd('- ( ) ^pick')).toBe(6);
  });

  it('knows what may follow a mark: nothing, or anchors and counters', () => {
    expect(AFTER_MARK.test('')).toBe(true);
    expect(AFTER_MARK.test(' ^ship [3/8]  ')).toBe(true);
    expect(AFTER_MARK.test(' and more words')).toBe(false);
    expect(AFTER_MARK.test('^ship')).toBe(false);
  });

  it('finds a counter in words, never a link, a picture or a footnote', () => {
    const counters = (text: string) => [...text.matchAll(new RegExp(COUNTER_IN_WORDS, 'g'))].map((found) => found[0]);
    expect(counters('Water [3/8] and push-ups [0/50]')).toEqual(['[3/8]', '[0/50]']);
    expect(counters('see [3/8](https://a.b) or ![1/2] or note[1/2]')).toEqual([]);
  });
});

describe('the lane a tick belongs in', () => {
  it('is a lane whose name starts or ends with Done, in any case', () => {
    for (const name of ['Done', 'done', ' DONE ', 'Done this week', 'All done']) expect(isDoneName(name)).toBe(true);
    for (const name of ['Doing', 'Undone work', 'Donut', 'Finished', '']) expect(isDoneName(name)).toBe(false);
  });
});
