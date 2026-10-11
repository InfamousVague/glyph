import { describe, expect, it } from 'vitest';
import { noteTitle, withoutFrontMatter } from './noteTitle.ts';
import titles from './titles.fixture.json';

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

describe('a title with a blank in it (docs/DESIGN.md §145)', () => {
  it('reads every row of the shared fixture', () => {
    for (const row of titles.rows) expect(noteTitle(`${row.line}\n\nSome words under it.`), row.line).toBe(row.title);
  });

  it('is untitled until a title blank fills, and never shows a fill’s bracket', () => {
    expect(noteTitle('# {?}\n\nBook the cabin for the second week of October.')).toBe('');
    expect(noteTitle('# Trip to ??Tokyo??(Qwen3.5 4B from memory, 2026-09-28. Asked: capital of Japan) §§')).toBe('Trip to Tokyo');
  });
});
