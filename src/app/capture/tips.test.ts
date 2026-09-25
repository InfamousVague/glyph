import { describe, expect, it } from 'vitest';
import { bareWords, runOf } from '../ai/instruction.ts';
import { starters, tips } from './tips.ts';

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

describe('the asks in a pause', () => {
  it('teach what the AI takes, as commands', () => {
    const said = tips({ noteTitle: 'Groceries', continuing: false }).map((tip) => tip.say);
    expect(said).toContain('Hey Ghost, fix the spelling');
    expect(said).toContain('Hey Ghost, summarize this');
    expect(tips({ noteTitle: null, continuing: false, keyword: false }).map((tip) => tip.say)).toContain('Fix the spelling');
  });
});

describe('the card before the first word', () => {
  it('shows one of each kind, naming a note and a book of theirs', () => {
    const card = starters({ noteTitle: 'Groceries', book: 'Field guide' });
    expect(card.shape.map((tip) => tip.say)).toEqual(['Bullet point', 'The next item is …']);
    expect(card.send.map((tip) => tip.say)).toEqual(['Hey Ghost, add … to Groceries', 'Hey Ghost, move this to Groceries']);
    expect(card.ask.map((tip) => tip.say)).toEqual(['Hey Ghost, fix the spelling', 'Hey Ghost, summarize this']);
  });

  it('still sends somewhere with no note to name, and drops the keyword when it is off', () => {
    const card = starters({ noteTitle: null, keyword: false });
    expect(card.send.map((tip) => tip.say)).toEqual(['Make a list called …', 'Make a book called …']);
    expect(card.ask[0]?.say).toBe('Fix the spelling');
  });

  it('never suggests an ask the reader would not take: each one, spoken with the keyword, is read as its run', () => {
    const asks = tips({ noteTitle: 'Groceries', continuing: false }).filter((tip) => /^Hey Ghost, (fix|summari|make this|tidy|carry)/.test(tip.say));
    expect(asks.length).toBe(5);
    for (const tip of [...starters({ noteTitle: 'Groceries' }).ask, ...asks]) {
      const bare = bareWords(tip.say, true);
      expect(bare?.keyed, tip.say).toBe(true);
      expect(runOf(bare!.words), tip.say).not.toBeNull();
    }
  });
});
