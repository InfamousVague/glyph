import { describe, expect, it } from 'vitest';
import { applySteps, countSteps, diffLines, linesOf } from './diff.ts';

const round = (before: string, after: string) => applySteps(linesOf(before), diffLines(linesOf(before), linesOf(after)))?.join('\n');

describe('the change from one version to the next', () => {
  it('is only the lines that changed, with the rest kept in runs', () => {
    const steps = diffLines(['# Plan', 'a', 'b', 'c', 'end'], ['# Plan', 'a', 'B', 'c', 'end']);
    expect(steps).toEqual([{ keep: 2 }, { del: 'b' }, { add: 'B' }, { keep: 2 }]);
    expect(countSteps(steps)).toEqual({ added: 1, removed: 1 });
  });

  it('turns any version into any other, exactly, trailing newline and blank lines included', () => {
    const cases: [string, string][] = [
      ['', '# New\n'],
      ['# New\n', ''],
      ['a\nb\nc', 'c\nb\na'],
      ['one\n\ntwo\n\n', '\none\ntwo\n\n\n'],
      ['x\ny\nz\nx\ny\nz', 'y\nz\nx\ny\nq\nz\nx'],
      ['same', 'same'],
    ];
    for (const [before, after] of cases) expect(round(before, after), JSON.stringify([before, after])).toBe(after);
  });

  it('finds the shortest change, as git does, on a note with lines moved about', () => {
    const before = linesOf('a\nb\nc\na\nb\nb\na');
    const after = linesOf('c\nb\na\nb\na\nc');
    const steps = diffLines(before, after);
    // Myers' own example: five lines out and in, no fewer.
    const { added, removed } = countSteps(steps);
    expect(added + removed).toBe(5);
    expect(applySteps(before, steps)?.join('\n')).toBe(after.join('\n'));
  });

  it('refuses steps that do not fit the version they are applied to', () => {
    expect(applySteps(['a', 'b'], [{ keep: 1 }, { del: 'x' }])).toBeNull();
    expect(applySteps(['a'], [{ keep: 3 }])).toBeNull();
  });

  it('copes with a long note in good time', () => {
    const before = Array.from({ length: 4000 }, (_, i) => `line ${i}`);
    const after = before.map((line, i) => (i % 97 === 0 ? `${line} changed` : line));
    const started = performance.now();
    const steps = diffLines(before, after);
    expect(performance.now() - started).toBeLessThan(1000);
    expect(applySteps(before, steps)).toEqual(after);
  });
});
