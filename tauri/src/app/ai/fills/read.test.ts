import { describe, expect, it } from 'vitest';
import { allNumbered, readFill } from './read.ts';

describe('the model’s output, read into answers', () => {
  it('reads [N] lines by blank', () => {
    const read = readFill('[1] Kazuo Ishiguro\n[2] 1989', [1, 2]);
    expect(read.get(1)).toEqual(['Kazuo Ishiguro']);
    expect(read.get(2)).toEqual(['1989']);
  });

  it('reads a repeated number as an items blank’s items, and passes over a number not asked', () => {
    const read = readFill('[1] Rail pass\n[1] Walking shoes\n[4] Nonsense\n[1] Cash in yen', [1]);
    expect(read.get(1)).toEqual(['Rail pass', 'Walking shoes', 'Cash in yen']);
    expect(read.has(4)).toBe(false);
  });

  it('never reads a note’s own numbered list as an answer', () => {
    const read = readFill('3. Rail pass\n[1] Rail pass', [1, 2]);
    expect(read.get(1)).toEqual(['Rail pass']);
    expect(read.get(2)).toEqual([]);
    expect(readFill('1. Passport\n2. Plug adapter\n3. Rail pass', [1, 2, 3]).get(3)).toEqual([]);
  });

  it('reads a bare answer when one blank was asked', () => {
    expect(readFill('Canberra', [1]).get(1)).toEqual(['Canberra']);
    expect(readFill('Rail pass\nWalking shoes', [1]).get(1)).toEqual(['Rail pass', 'Walking shoes']);
    expect(readFill('Canberra', [1, 2]).get(1)).toEqual([]);
  });

  it('says whether every line was an [N] line for an asked blank', () => {
    expect(allNumbered('[1] a\n[2] b', [1, 2])).toBe(true);
    expect(allNumbered('[1] a\nb', [1])).toBe(false);
    expect(allNumbered('[3] a', [1, 2])).toBe(false);
  });
});
