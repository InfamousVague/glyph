import { describe, expect, it } from 'vitest';
import { tips } from './tips.ts';

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
