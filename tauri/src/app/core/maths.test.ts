import { describe, expect, it } from 'vitest';
import { mathsIn } from './maths.ts';

/** The maths found in a line, as the words it covers. */
const found = (line: string) => mathsIn(line).map(({ from, to }) => line.slice(from, to));

describe('maths, by Pandoc’s rule', () => {
  it('finds maths inline and on a line', () => {
    expect(found('$x^2$')).toEqual(['$x^2$']);
    expect(found('$$a+b$$')).toEqual(['$$a+b$$']);
    expect(found('where $n$ is 3')).toEqual(['$n$']);
    expect(found('when $x^2 + y$ holds')).toEqual(['$x^2 + y$']);
  });

  it('reads two prices on a line as prices', () => {
    expect(found('$200 and $45')).toEqual([]);
    expect(found('It costs $5, or $6 with tax.')).toEqual([]);
    expect(found('Cabin $200, ferry $45, food $80')).toEqual([]);
    expect(found('it cost $20 and $30')).toEqual([]);
  });

  it('leaves a budget line alone with a filled answer in it', () => {
    expect(found('Budget $500 for ??$200??(Qwen3.5 4B from memory, 2026-09-28. Asked: the deposit) and the rest')).toEqual([]);
    expect(found('Total so far: $325, and ??$40??(Qwen3.5 4B from memory, 2026-09-28) for the taxi')).toEqual([]);
  });

  it('needs a word against each dollar sign, and none after a backslash', () => {
    expect(found('$ 5 $')).toEqual([]);
    expect(found('\\$200 and \\$45')).toEqual([]);
  });

  it('counts from an offset', () => {
    expect(mathsIn('so $n$', 10)).toEqual([{ from: 13, to: 16 }]);
  });
});
