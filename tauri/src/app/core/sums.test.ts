import { describe, expect, it } from 'vitest';
import { answer, leadingNumber, totalOf, writtenNumber } from './sums.ts';

/*
 * The arithmetic a sum and a query's totals share (core/sums.ts). The sums themselves are tested where they are drawn
 * (editor/sums.test.ts); here is what a query adds up with.
 */

describe('a number as a sum reads one', () => {
  it('reads a value that is only a number', () => {
    expect(writtenNumber('3')).toBe(3);
    expect(writtenNumber(' $1,200 ')).toBe(1200);
    expect(writtenNumber('-2.5')).toBe(-2.5);
    expect(writtenNumber('−4')).toBe(-4);
    expect(writtenNumber('50%')).toBe(0.5);
    expect(writtenNumber('3 days')).toBeNull();
    expect(writtenNumber('GHO-12')).toBeNull();
    expect(writtenNumber('')).toBeNull();
  });

  it('reads the number a value starts with', () => {
    expect(leadingNumber('3 days')).toBe('3');
    expect(leadingNumber('$1,200 a month')).toBe('$1,200');
    expect(leadingNumber('- 2.5')).toBe('-2.5');
    expect(leadingNumber('about 3')).toBeNull();
  });
});

describe('a total', () => {
  it('adds the numbers the values start with, as a sum would', () => {
    expect(totalOf(['3', '2.5 days', '1'])).toBe('6.5');
    expect(totalOf(['$1,200', '$300'])).toBe('$1,500');
    expect(totalOf(['$12', '$4.50'])).toBe('$16.50');
    expect(totalOf(['5', '-2'])).toBe('3');
  });

  it('is the value itself where there is one, and nothing where none has a number', () => {
    expect(totalOf(['7'])).toBe('7');
    expect(totalOf(['soon', 'later'])).toBeNull();
    expect(totalOf([])).toBeNull();
  });

  it('agrees with the sum of the same numbers', () => {
    expect(totalOf(['1,000', '2,500'])).toBe(answer('1,000 + 2,500'));
  });
});
