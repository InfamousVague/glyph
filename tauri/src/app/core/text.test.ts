import { describe, expect, it } from 'vitest';
import { capitalise, escapeRegExp, lowerFirst } from './text.ts';

describe('the first letter', () => {
  it('is capitalised and nothing after it is touched', () => {
    expect(capitalise('milk')).toBe('Milk');
    expect(capitalise('iPhone case')).toBe('IPhone case');
    expect(capitalise('the API docs')).toBe('The API docs');
  });

  it('is lowered for a command read after "Hey Ghost,", and nothing after it is touched', () => {
    expect(lowerFirst('Add milk to Shopping')).toBe('add milk to Shopping');
    expect(lowerFirst('API key')).toBe('aPI key');
  });

  it('leaves an empty string empty, and a string that has no case as it was', () => {
    expect(capitalise('')).toBe('');
    expect(lowerFirst('')).toBe('');
    expect(capitalise('3 eggs')).toBe('3 eggs');
  });
});

describe('words inside a pattern', () => {
  it('match themselves, however much of them is RegExp syntax', () => {
    const said = 'C++ (the book) costs $30.00? [maybe] {or} a|b ^ \\ *';
    expect(new RegExp(`^${escapeRegExp(said)}$`).test(said)).toBe(true);
    expect(new RegExp(escapeRegExp('a.c')).test('abc')).toBe(false);
  });

  it('leaves words with nothing to escape as they were', () => {
    expect(escapeRegExp('status')).toBe('status');
  });
});
