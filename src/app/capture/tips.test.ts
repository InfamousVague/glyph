import { describe, expect, it } from 'vitest';
import { bareWords, runOf } from '../ai/instruction.ts';
import { ASKS, starters, tips } from './tips.ts';

describe('tips in a pause', () => {
  it('teach the newer cues, and a note’s board lanes when it has a board', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true, lane: 'Doing' }).map((tip) => tip.say);
    expect(said).toContain('Info box');
    expect(said).toContain('Option');
    expect(said).toContain('Hey Ghost, add … to Doing');
    expect(said).toContain('Hey Ghost, move … to Doing');
    expect(tips({ noteTitle: null, continuing: false }).some((tip) => tip.say.includes('to Doing'))).toBe(false);
  });

  it('teach a chapter for a book the library has, or how to make one', () => {
    expect(tips({ noteTitle: 'Groceries', continuing: false, book: 'Field guide' }).map((tip) => tip.say)).toContain('Hey Ghost, add a chapter to Field guide');
    expect(tips({ noteTitle: null, continuing: false }).map((tip) => tip.say)).toContain('Hey Ghost, make a book called …');
  });
});

describe('a note with a board', () => {
  it('still comes round to every routing line, the ones past the cues’ slots after them', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: true, lane: 'Doing', book: 'Field guide' }).map((tip) => tip.say);
    for (const line of ['Hey Ghost, add … to Groceries', 'Hey Ghost, move … to Doing', 'Hey Ghost, add a table to Groceries', 'Hey Ghost, add a chapter to Field guide']) expect(said).toContain(line);
    expect(said.some((line) => /fix the spelling|summarize/i.test(line))).toBe(false);
  });
});

describe('the card before the first word', () => {
  it('shows a couple of each kind, naming a note of theirs and a book’s chapter over moving the take', () => {
    const card = starters({ noteTitle: 'Groceries', book: 'Field guide', asking: true });
    expect(card.shape.map((tip) => tip.say)).toEqual(['Bullet point', 'The next item is …']);
    expect(card.send.map((tip) => tip.say)).toEqual(['Hey Ghost, add … to Groceries', 'Hey Ghost, add a chapter to Field guide']);
    expect(card.ask.map((tip) => tip.say)).toEqual(['Hey Ghost, fix the spelling', 'Hey Ghost, summarize this']);
    expect(starters({ noteTitle: 'Groceries' }).send.map((tip) => tip.say)).toEqual(['Hey Ghost, add … to Groceries', 'Hey Ghost, move this to Groceries']);
  });

  it('still sends somewhere with no note to name, drops the keyword when it is off, and offers no ask where none can run', () => {
    const card = starters({ noteTitle: null, keyword: false });
    expect(card.send.map((tip) => tip.say)).toEqual(['Make a list called …', 'Make a book called …']);
    expect(card.ask).toEqual([]);
    expect(starters({ noteTitle: null, keyword: false, asking: true }).ask[0]?.say).toBe('Fix the spelling');
  });

  it('never suggests an ask the reader would not take: each one, spoken first with the keyword, is read as its run', () => {
    expect(ASKS.length).toBe(5);
    for (const ask of ASKS) {
      const said = `Hey Ghost, ${ask.say.charAt(0).toLowerCase()}${ask.say.slice(1)}`;
      const bare = bareWords(said, true);
      expect(bare?.keyed, said).toBe(true);
      expect(runOf(bare!.words), said).not.toBeNull();
    }
  });
});
