import { afterEach, describe, expect, it, vi } from 'vitest';
import { prefersStill } from './motion.ts';

function phoneAsking(reduce: boolean) {
  const ask = vi.fn((query: string) => ({ matches: reduce && query === '(prefers-reduced-motion: reduce)', media: query }) as MediaQueryList);
  vi.stubGlobal('matchMedia', ask);
  return ask;
}

describe('whether the phone asks for less motion', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('says so when the phone asks for reduced motion', () => {
    const ask = phoneAsking(true);
    expect(prefersStill()).toBe(true);
    expect(ask).toHaveBeenCalledWith('(prefers-reduced-motion: reduce)');
  });

  it('says no when it does not', () => {
    phoneAsking(false);
    expect(prefersStill()).toBe(false);
  });

  it('asks every time rather than remembering, so a setting changed mid-session holds for the next animation', () => {
    phoneAsking(false);
    expect(prefersStill()).toBe(false);
    phoneAsking(true);
    expect(prefersStill()).toBe(true);
  });

  it('answers no, rather than throwing, where there is no matchMedia to ask', () => {
    vi.stubGlobal('matchMedia', undefined);
    expect(prefersStill()).toBe(false);
  });
});
