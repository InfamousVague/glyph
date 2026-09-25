import { describe, expect, it } from 'vitest';
import { noteTitle, withoutFrontMatter } from './noteTitle.ts';

describe('a note’s lines without its front matter', () => {
  it('puts the front matter’s title first, where it has one', () => {
    expect(withoutFrontMatter(['---', 'title: "Plan"', 'id: x', '---', '', 'Words'])).toEqual(['Plan', '', 'Words']);
    expect(withoutFrontMatter(['---', 'id: x', '---', '# Plan'])).toEqual(['# Plan']);
  });

  it('keeps every line of a note whose opening rule is not front matter', () => {
    const ruled = ['---', 'Some words here', '---', 'Real title'];
    expect(withoutFrontMatter(ruled)).toEqual(ruled);
    expect(noteTitle(ruled.join('\n'))).toBe('---');
  });

  it('is what core/store.ts hands its callers', async () => {
    const store = await import('./store.ts');
    expect(store.noteTitle).toBe(noteTitle);
    expect(store.withoutFrontMatter).toBe(withoutFrontMatter);
  });
});
