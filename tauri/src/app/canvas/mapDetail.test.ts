import { describe, expect, it } from 'vitest';
import { noteBars, roundedBox, wordBars } from './mapDetail.ts';

/** What a card looks like small (canvas/mapDetail.ts): its words as the bars they make from far off. */
describe('a card’s words on the map', () => {
  it('draws a heading heavier, a list’s line as a dot and a bar, and a paragraph as the lines it wraps to', () => {
    const bars = wordBars('# Plan\n\n- [ ] One thing\n\nA paragraph long enough that it runs on to a second line of the card.', 260, 220);
    expect(bars[0]).toMatchObject({ x: 14, y: 14, strong: true });
    // The list's line: a square dot, then its words set in from it.
    expect(bars[1]).toMatchObject({ x: 14, width: 8, height: 8 });
    expect(bars[2]!.x).toBe(30);
    expect(bars[2]!.y).toBe(bars[1]!.y);
    // The paragraph: full lines, then what is left over, shorter.
    expect([bars[3]!.width, bars[4]!.width]).toEqual([232, 232]);
    expect(bars[5]!.width).toBeLessThan(232);
    expect(bars[4]!.y - bars[3]!.y).toBe(20);
    expect(bars).toHaveLength(6);
  });

  it('draws a table as its rows, the card’s width, and nothing for the rule under its head or a fence’s own lines', () => {
    expect(wordBars('| a | b |\n| --- | --- |\n| 1 | 2 |', 200, 120).map((b) => b.width)).toEqual([172, 172]);
    expect(wordBars('```mermaid\nflowchart LR\n```', 200, 120)).toHaveLength(1);
  });

  it('stops at the card’s foot, and draws nothing in a card too small to hold a line', () => {
    const many = Array.from({ length: 40 }, (_, n) => `line ${n}`).join('\n');
    const bars = wordBars(many, 200, 100);
    expect(bars.length).toBe(4);
    expect(Math.max(...bars.map((b) => b.y + b.height))).toBeLessThanOrEqual(93);
    expect(wordBars('words', 40, 100)).toEqual([]);
    // And never more than a page's worth, however tall the card.
    expect(wordBars(many, 200, 4000).length).toBeLessThanOrEqual(28);
  });

  it('draws a note as its title and what fits of a few lines under it', () => {
    const bars = noteBars('Launch week', 200, 80);
    expect(bars.map((b) => !!b.strong)).toEqual([true, false, false]);
    expect(noteBars('Launch week', 200, 30)).toEqual([]);
  });
});

describe('the screen’s box on the map', () => {
  it('is a closed path with round corners, no rounder than the box allows', () => {
    expect(roundedBox(10, 20, 100, 50, 5)).toBe('M15 20h90a5 5 0 0 1 5 5v40a5 5 0 0 1 -5 5h-90a5 5 0 0 1 -5 -5v-40a5 5 0 0 1 5 -5Z');
    // A box smaller than twice the round is a pill, not a knot.
    expect(roundedBox(0, 0, 6, 20, 5)).toContain('a3 3');
  });
});
